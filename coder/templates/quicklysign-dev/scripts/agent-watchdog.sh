#!/usr/bin/env bash
# agent-watchdog: keeps the Coder workspace alive while Claude/Codex sessions
# are doing useful work, and lets it autostop when they are idle or merely
# waiting for input.
#
# Runs as a systemd user service (see install-agent-tools.sh). Requires
# CODER_URL, CODER_SESSION_TOKEN and CODER_WORKSPACE_NAME in the environment
# (written to ~/.config/agent-watchdog/env by the agent startup script on
# every workspace start).
#
# A lane counts as ACTIVE when any of:
#   * its agent reported a work event (hook/notify) within ACTIVE_OUTPUT_WINDOW
#   * its tmux pane content changed within ACTIVE_OUTPUT_WINDOW
#   * known busy child processes (pytest, npm, docker, ...) are running in it
#   * files in its repo changed within ACTIVE_FILE_CHANGE_WINDOW
# A lane whose agent reported "waiting for input" gets WAITING_FOR_INPUT_GRACE
# of continued bumping, then stops counting. TTL is an INACTIVITY timeout (not
# a lifetime cap): a lane stops counting after TTL seconds with no work, and
# revives the moment work resumes — active work is never force-stopped.
#
# While any lane is active, the Coder autostop deadline is extended with
# `coder schedule extend <workspace> <minutes>m` whenever the remaining time
# drops below the bump amount. Decisions are logged to
# ~/.local/state/agent-watchdog.log
set -u

SESSIONS_DIR="$HOME/.local/share/agent-sessions"
SIGNALS_DIR="$SESSIONS_DIR/signals"
RUNTIME_DIR="${TMPDIR:-/tmp}/agent-watchdog-$(id -u)"
LOG_FILE="$HOME/.local/state/agent-watchdog.log"
CONFIG_FILE="$HOME/.config/agent-watchdog/config"

# Defaults — override by exporting in $CONFIG_FILE
ACTIVE_OUTPUT_WINDOW_SECONDS=180
ACTIVE_FILE_CHANGE_WINDOW_SECONDS=300
WAITING_FOR_INPUT_GRACE_SECONDS=180
DEFAULT_AGENT_TTL_SECONDS=3600   # inactivity timeout (reset on activity), 1h
MAX_AGENT_TTL_SECONDS=14400      # ceiling for per-lane --ttl overrides
WATCHDOG_INTERVAL_SECONDS=60
# The bump window IS the effective idle grace: when active the deadline is kept
# this far ahead, so when work stops the workspace coasts this long before
# autostopping. Keep it aligned with the 1h inactivity TTL so coming back within
# the hour re-extends (a 45m window stopped a lane idle-then-resumed at ~47m).
AUTOSTOP_BUMP_MINUTES=60

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
mkdir -p "$SESSIONS_DIR" "$SIGNALS_DIR" "$RUNTIME_DIR" "$(dirname "$LOG_FILE")"

# Process names that indicate real work when running inside a lane's pane.
# Deliberately excludes bare node/python/bash: the agents themselves and
# their MCP servers run on those and would read as permanently busy.
BUSY_PROCS='pytest|npm|pnpm|yarn|uv|pip|docker|make|cargo|rustc|tsc|jest|vitest|playwright|webpack|vite|next|gradle|mvn|gcc|g\+\+|go'

log() { echo "$(date -u +%FT%TZ) $*" >> "$LOG_FILE"; }
mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
path_key() { printf '%s' "$1" | tr '/ ' '--'; } # must match agent-activity-hook

meta_set() { # <file> <jq-assignment>  e.g. meta_set "$f" '.status = "active"'
  local tmp
  tmp=$(mktemp) && jq "$2" "$1" > "$tmp" && mv "$tmp" "$1"
}

pane_changed() { # <lane>  -> returns 0 and refreshes marker on content change
  local lane="$1" hash_file="$RUNTIME_DIR/$1.hash" new old
  new=$(tmux capture-pane -p -t "=$lane:" 2>/dev/null | md5sum | cut -d' ' -f1) || return 1
  old=$(cat "$hash_file" 2>/dev/null || true)
  echo "$new" > "$hash_file"
  [ -n "$old" ] && [ "$new" != "$old" ]
}

busy_children() { # <lane> -> count of known busy processes under the pane
  local pane_pid
  pane_pid=$(tmux list-panes -t "=$1:" -F '#{pane_pid}' 2>/dev/null | head -1)
  [ -n "$pane_pid" ] || { echo 0; return; }
  ps -eo pid=,ppid=,comm= | awk -v root="$pane_pid" -v busy="^($BUSY_PROCS)" '
    { ppid[$1]=$2; comm[$1]=$3 }
    END {
      for (p in ppid) {
        q = p
        while (q in ppid && ppid[q] != 1) {
          if (ppid[q] == root) { if (comm[p] ~ busy) n++; break }
          q = ppid[q]
        }
      }
      print n + 0
    }'
}

recent_file_changes() { # <repo> -> 0 if any file changed within the window
  [ -d "$1" ] || return 1
  [ -n "$(find "$1" \
      -name .git -prune -o -name node_modules -prune -o -name .venv -prune \
      -o -name __pycache__ -prune \
      -o -type f -mmin "-$((ACTIVE_FILE_CHANGE_WINDOW_SECONDS / 60))" -print -quit \
      2>/dev/null)" ]
}

# Extend the autostop deadline when the time remaining drops below the bump.
LAST_BUMP_EPOCH=0
maybe_bump() {
  local now deadline rem
  now=$(date +%s)

  deadline=$(coder list --output json 2>/dev/null \
    | jq -r ".[] | select(.name == \"$CODER_WORKSPACE_NAME\") | .latest_build.deadline // empty")

  if [ -n "$deadline" ]; then
    rem=$(( $(date -d "$deadline" +%s 2>/dev/null || echo 0) - now ))
    if [ "$rem" -ge $((AUTOSTOP_BUMP_MINUTES * 60)) ]; then
      return 0 # plenty of runway; do not ratchet the deadline upward
    fi
  else
    # Could not read the deadline; rate-limit blind bumps to one per 5 min.
    [ $((now - LAST_BUMP_EPOCH)) -lt 300 ] && return 0
  fi

  if coder schedule extend "$CODER_WORKSPACE_NAME" "${AUTOSTOP_BUMP_MINUTES}m" >>"$LOG_FILE" 2>&1; then
    LAST_BUMP_EPOCH=$now
    log "BUMP deadline +${AUTOSTOP_BUMP_MINUTES}m (remaining was ${rem:-unknown}s)"
  else
    log "BUMP FAILED — check CODER_SESSION_TOKEN / coder CLI"
  fi
}

log "watchdog started (interval=${WATCHDOG_INTERVAL_SECONDS}s bump=${AUTOSTOP_BUMP_MINUTES}m)"

while true; do
  any_active=false
  now=$(date +%s)

  for meta in "$SESSIONS_DIR"/*.json; do
    [ -e "$meta" ] || continue
    lane=$(basename "$meta" .json)
    status=$(jq -r '.status // "unknown"' "$meta")
    repo=$(jq -r '.repo_path // empty' "$meta")
    ttl=$(jq -r ".ttl_seconds // $DEFAULT_AGENT_TTL_SECONDS" "$meta")
    # TTL is an INACTIVITY timeout: last_active_epoch is bumped to now on every
    # active tick (below), so a lane only expires after `ttl` seconds with no
    # work — and revives the moment activity resumes. Falls back to start_epoch
    # before the first activity tick records last_active_epoch.
    last_active=$(jq -r '.last_active_epoch // .start_epoch // 0' "$meta")

    # Lane's tmux session is gone -> finished.
    if ! tmux has-session -t "=$lane" 2>/dev/null; then
      [ "$status" != "finished" ] && { meta_set "$meta" '.status = "finished"'; log "$lane: finished (tmux session gone)"; }
      continue
    fi

    key=$(path_key "$repo")
    hook_state=$(cat "$SIGNALS_DIR/$key.state" 2>/dev/null || echo "")
    hook_state_age=$((now - $(mtime "$SIGNALS_DIR/$key.state")))
    hook_act_age=$((now - $(mtime "$SIGNALS_DIR/$key.activity")))

    pane_act=false
    if pane_changed "$lane"; then
      pane_act=true
      meta_set "$meta" ".last_output_epoch = $now"
    fi
    last_output=$(jq -r '.last_output_epoch // 0' "$meta")
    output_recent=$([ $((now - last_output)) -lt "$ACTIVE_OUTPUT_WINDOW_SECONDS" ] && echo true || echo false)

    files_recent=false
    if recent_file_changes "$repo"; then
      files_recent=true
      meta_set "$meta" ".last_change_epoch = $now"
    fi

    busy=$(busy_children "$lane")

    # Decision. An explicit, recent "waiting" signal from the agent overrides
    # pane-content heuristics (spinners/redraws repaint the pane while the
    # agent is actually just sitting at a prompt).
    state="idle"
    if [ "$hook_state" = "waiting" ]; then
      if [ "$hook_state_age" -lt "$WAITING_FOR_INPUT_GRACE_SECONDS" ]; then
        state="waiting-grace"
      elif [ "$files_recent" = true ] || [ "$busy" -gt 0 ]; then
        state="active" # something is still doing real work despite the prompt
      else
        state="waiting"
      fi
    else
      if [ "$hook_state" = "working" ] && [ "$hook_act_age" -lt "$ACTIVE_OUTPUT_WINDOW_SECONDS" ]; then
        state="active"
      elif [ "$output_recent" = true ] || [ "$files_recent" = true ] || [ "$busy" -gt 0 ]; then
        state="active"
      fi
    fi

    case "$state" in
      active|waiting-grace)
        any_active=true
        [ "$status" != "active" ] && log "$lane: active (hook=$hook_state pane=$pane_act files=$files_recent busy=$busy)"
        # Activity resets the inactivity clock (and revives an expired lane).
        meta_set "$meta" ".status = \"active\" | .last_active_epoch = $now"
        ;;
      waiting | idle)
        inactive=$((now - last_active))
        if [ "$inactive" -gt "$ttl" ]; then
          [ "$status" != "expired" ] && { meta_set "$meta" '.status = "expired"'; log "$lane: idle ${inactive}s > ttl ${ttl}s — not extending (revives on activity)"; }
        elif [ "$state" = "waiting" ]; then
          [ "$status" != "waiting" ] && { meta_set "$meta" '.status = "waiting"'; log "$lane: waiting for input past grace — not extending autostop"; }
        else
          [ "$status" != "idle" ] && { meta_set "$meta" '.status = "idle"'; log "$lane: idle — not extending autostop"; }
        fi
        ;;
    esac
  done

  if [ "$any_active" = true ]; then
    maybe_bump
  fi

  sleep "$WATCHDOG_INTERVAL_SECONDS"
done
