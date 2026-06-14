#!/usr/bin/env bash
# agent-activity-hook: receives lifecycle events from Claude Code (hook JSON
# on stdin) and Codex (notify JSON as argv[1]) and records working/waiting
# signals that agent-watchdog reads.
#
# Signal files, keyed by the session's working directory:
#   ~/.local/share/agent-sessions/signals/<key>.state     "working"|"waiting"|"idle"
#   ~/.local/share/agent-sessions/signals/<key>.activity  mtime = last work event
set -u

SIGNALS_DIR="$HOME/.local/share/agent-sessions/signals"
mkdir -p "$SIGNALS_DIR"

if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  payload="$1"      # Codex notify: JSON passed as a single argument
else
  payload="$(cat)"  # Claude Code hooks: JSON on stdin
fi

event=$(printf '%s' "$payload" | jq -r '.hook_event_name // .type // empty' 2>/dev/null || true)
dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$dir" ] || dir="$PWD"

# Must match path_key() in agent-watchdog
key=$(printf '%s' "$dir" | tr '/ ' '--')

case "$event" in
  UserPromptSubmit|PreToolUse|PostToolUse|SessionStart)
    echo working > "$SIGNALS_DIR/$key.state"
    touch "$SIGNALS_DIR/$key.activity"
    ;;
  Stop|Notification|PermissionRequest|agent-turn-complete)
    # Finished a turn or blocked on the human: waiting for input.
    echo waiting > "$SIGNALS_DIR/$key.state"
    ;;
  SessionEnd)
    echo idle > "$SIGNALS_DIR/$key.state"
    ;;
  *)
    touch "$SIGNALS_DIR/$key.activity"
    ;;
esac

exit 0
