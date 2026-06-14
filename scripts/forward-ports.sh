#!/usr/bin/env bash
# forward-ports.sh: mirror a Coder workspace's app / admin-UI ports onto the
# same local ports, following devcontainers' DYNAMIC ports automatically — new
# worktree comes up on a new host port, it appears locally within one poll;
# tear the container down and the forward goes away.
#
#   scripts/forward-ports.sh [workspace-ssh-host] [poll-seconds]
#   scripts/forward-ports.sh quicklysign-dev.coder 5
#
# Requires `coder config-ssh` to have created the <workspace>.coder host.
# Assumes no local port clashes (remote port -> identical local port).
# Survives workspace restarts / Spot preemption: the master is rebuilt and
# forwards re-established on the next poll. Ctrl-C tears everything down.
#
# Kept bash-3.2 compatible (macOS system bash): no mapfile, no associative
# arrays — the forwarded set is a space-delimited string.
set -uo pipefail

WS="${1:-quicklysign-dev.coder}"
INTERVAL="${2:-5}"
SOCK="${TMPDIR:-/tmp}/coder-fwd-$(printf '%s' "$WS" | tr -c 'A-Za-z0-9' _).sock"
FWD=" " # space-delimited set of currently-forwarded ports

open_master() { ssh -fNT -M -S "$SOCK" -o ControlPersist=yes "$WS" 2>/dev/null; }

cleanup() {
  printf '\ntearing down forwards...\n'
  ssh -S "$SOCK" -O exit "$WS" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

if ! open_master; then
  echo "Could not open an SSH master to '$WS'." >&2
  echo "Is the workspace started, and did you run 'coder config-ssh'?" >&2
  exit 1
fi

echo "Following $WS app ports -> localhost (poll ${INTERVAL}s). Ctrl-C to stop."
while true; do
  # Rebuild the master if it died (e.g. Spot preemption) and reset state.
  if ! ssh -S "$SOCK" -O check "$WS" 2>/dev/null; then
    echo "  (connection lost — reconnecting)"
    open_master || { sleep "$INTERVAL"; continue; }
    FWD=" "
  fi

  WANT=" "
  while read -r port label; do
    case "$port" in '' | *[!0-9]*) continue ;; esac
    WANT="$WANT$port "
    case "$FWD" in
      *" $port "*) : ;; # already forwarded
      *)
        if ssh -S "$SOCK" -O forward -L "$port:localhost:$port" "$WS" 2>/dev/null; then
          FWD="$FWD$port "
          printf '  + http://localhost:%-5s (%s)\n' "$port" "$label"
        fi
        ;;
    esac
  done < <(ssh -S "$SOCK" "$WS" list-app-ports 2>/dev/null)

  # Cancel forwards whose remote port vanished.
  NEW=" "
  for port in $FWD; do
    case "$WANT" in
      *" $port "*) NEW="$NEW$port " ;;
      *)
        ssh -S "$SOCK" -O cancel -L "$port:localhost:$port" "$WS" 2>/dev/null || true
        printf '  - localhost:%s (gone)\n' "$port"
        ;;
    esac
  done
  FWD="$NEW"

  sleep "$INTERVAL"
done
