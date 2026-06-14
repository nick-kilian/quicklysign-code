#!/usr/bin/env bash
# agent-status: one-line-per-lane view of agent sessions and watchdog state.
set -uo pipefail

SESSIONS_DIR="$HOME/.local/share/agent-sessions"
now=$(date +%s)

rel() { # seconds -> "1m", "3h12m", "-"
  local s="$1"
  [ "$s" -le 0 ] 2>/dev/null || [ -z "$s" ] && { echo "-"; return; }
  if [ "$s" -lt 60 ]; then echo "${s}s"
  elif [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
  else echo "$((s / 3600))h$(( (s % 3600) / 60 ))m"
  fi
}

printf "%-22s %-7s %-28s %-14s %-12s %-12s %-9s\n" \
  "SESSION" "AGENT" "REPO" "STATE" "LAST_OUTPUT" "LAST_CHANGE" "TTL_LEFT"

found=false
for meta in "$SESSIONS_DIR"/*.json; do
  [ -e "$meta" ] || continue
  found=true

  name=$(jq -r '.name' "$meta")
  agent=$(jq -r '.agent_type' "$meta")
  repo=$(jq -r '.repo_path' "$meta" | sed "s|^$HOME|~|")
  status=$(jq -r '.status // "unknown"' "$meta")
  start=$(jq -r '.start_epoch // 0' "$meta")
  ttl=$(jq -r '.ttl_seconds // 0' "$meta")
  last_out=$(jq -r '.last_output_epoch // 0' "$meta")
  last_chg=$(jq -r '.last_change_epoch // 0' "$meta")

  # Live check beats possibly-stale watchdog status for gone sessions.
  if ! tmux has-session -t "=$name" 2>/dev/null; then
    status="finished"
  fi

  out_ago="-";  [ "$last_out" -gt 0 ] && out_ago="$(rel $((now - last_out))) ago"
  chg_ago="-";  [ "$last_chg" -gt 0 ] && chg_ago="$(rel $((now - last_chg))) ago"
  ttl_left="-"
  if [ "$status" != "finished" ] && [ "$ttl" -gt 0 ]; then
    ttl_left=$(rel $((start + ttl - now)))
  fi

  printf "%-22s %-7s %-28s %-14s %-12s %-12s %-9s\n" \
    "$name" "$agent" "$repo" "$status" "$out_ago" "$chg_ago" "$ttl_left"
done

if [ "$found" = false ]; then
  echo "(no agent sessions — start one with: agent-run claude <lane> --repo ~/src/<repo>)"
fi
