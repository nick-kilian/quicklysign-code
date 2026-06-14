#!/usr/bin/env bash
# forward-ports.sh: mirror a Coder workspace's app / admin-UI ports onto the
# same local ports, following devcontainers' DYNAMIC ports automatically — a new
# worktree's app comes up on a new host port and it appears locally within a
# poll; tear the container down and the forward goes away.
#
#   scripts/forward-ports.sh [workspace-ssh-host] [poll-seconds]
#   scripts/forward-ports.sh quicklysign-dev.coder 5
#
# Requires `coder config-ssh` (creates the <workspace>.coder host) and a
# logged-in `coder` CLI. Mirrors remote port -> identical local port (assumes
# no local clashes).
#
# IMPORTANT: this NEVER starts a stopped workspace. `coder ssh` would otherwise
# auto-start one on connect, which defeats autostop. So before connecting we
# check `coder list` and only attach while the workspace is already running; if
# it autostops, the follower goes dormant and waits (no SSH = no resurrection).
# It re-attaches automatically when the workspace is next started. Ctrl-C tears
# everything down.
#
# bash-3.2 compatible (macOS system bash): no mapfile / associative arrays —
# the forwarded set is a space-delimited string.
set -uo pipefail

WS="${1:-quicklysign-dev.coder}"
INTERVAL="${2:-5}"
IDLE_INTERVAL=30                        # slower poll while the workspace is down
WS_NAME="${WS%.coder}"                  # coder workspace name (strip ssh suffix)
SOCK="${TMPDIR:-/tmp}/coder-fwd-$(printf '%s' "$WS" | tr -c 'A-Za-z0-9' _).sock"
FWD=" "                                 # space-delimited set of forwarded ports

open_master() { ssh -fNT -M -S "$SOCK" -o ControlPersist=yes "$WS" 2>/dev/null; }

ws_running() {
  coder list --output json 2>/dev/null \
    | jq -e --arg n "$WS_NAME" '.[] | select(.name==$n) | .latest_build.status=="running"' \
    >/dev/null 2>&1
}

ws_exists() {
  coder list --output json 2>/dev/null \
    | jq -e --arg n "$WS_NAME" 'any(.[]; .name==$n)' >/dev/null 2>&1
}

cleanup() {
  printf '\ntearing down forwards...\n'
  ssh -S "$SOCK" -O exit "$WS" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

if ! ws_exists; then
  echo "Workspace '$WS_NAME' not found via 'coder list' — logged in? name right?" >&2
  exit 1
fi

echo "Following $WS app ports -> localhost (poll ${INTERVAL}s)."
echo "Will NOT start the workspace; goes dormant when it's stopped. Ctrl-C to stop."

DORMANT=false
while true; do
  if ! ws_running; then
    if [ "$DORMANT" = false ]; then
      echo "  (workspace stopped — dormant; not auto-starting it. Waiting for it to come back up.)"
      ssh -S "$SOCK" -O exit "$WS" 2>/dev/null || true
      FWD=" "
      DORMANT=true
    fi
    sleep "$IDLE_INTERVAL"
    continue
  fi
  if [ "$DORMANT" = true ]; then
    echo "  (workspace is up — reattaching)"
    DORMANT=false
  fi

  # Workspace confirmed running, so opening the master attaches without
  # triggering an auto-start.
  if ! ssh -S "$SOCK" -O check "$WS" 2>/dev/null; then
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
