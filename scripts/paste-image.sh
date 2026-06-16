#!/usr/bin/env bash
# paste-image.sh: bridge a clipboard image from this Mac into a remote Claude
# Code session over SSH.
#
# Claude Code running over SSH can't read your local clipboard (SSH carries
# text, not clipboard images), so a Cmd+V image paste does nothing. This saves
# the clipboard image to a file, scp's it to the workspace, and copies the
# remote `@<path>` onto your clipboard — paste THAT (text) into the claude
# prompt and Claude reads the image.
#
#   scripts/paste-image.sh [workspace-ssh-host] [remote-dir]
#
# Workflow:
#   1. screenshot to clipboard (macOS: Shift-Cmd-Ctrl-4, or Cmd-C an image)
#   2. run this   ->  it prints/clips `@/home/coder/.clips/clip-<ts>.png`
#   3. in the remote claude prompt: Cmd-V (pastes the path), Enter
set -uo pipefail

WS="${1:-quicklysign-dev.coder}"
RDIR="${2:-/home/coder/.clips}"
TS=$(date +%Y%m%d-%H%M%S)
LOCAL="${TMPDIR:-/tmp}/clip-$TS.png"

# 1) clipboard image -> PNG file
if command -v pngpaste >/dev/null 2>&1; then
  pngpaste "$LOCAL" 2>/dev/null || { echo "No image on the clipboard — copy/screenshot one first."; exit 1; }
else
  # Fallback without pngpaste: AppleScript PNG extraction (PNG clipboards only,
  # e.g. macOS screenshots). For other formats: brew install pngpaste
  osascript >/dev/null 2>&1 <<OSA || true
set p to POSIX file "$LOCAL"
try
  set d to (the clipboard as «class PNGf»)
  set f to open for access p with write permission
  write d to f
  close access f
end try
OSA
  [ -s "$LOCAL" ] || { echo "No PNG on the clipboard. For non-PNG images: brew install pngpaste"; exit 1; }
fi

# 2) upload to the workspace
REMOTE="$RDIR/clip-$TS.png"
ssh "$WS" "mkdir -p '$RDIR'" 2>/dev/null || { echo "Can't reach $WS (workspace started? 'coder config-ssh' done?)"; exit 1; }
scp -q "$LOCAL" "$WS:$REMOTE" || { echo "scp to $WS failed."; exit 1; }
rm -f "$LOCAL"

# 3) put the @path on the clipboard to paste into the claude prompt
printf '@%s' "$REMOTE" | pbcopy 2>/dev/null || true
echo "Uploaded → $WS:$REMOTE"
echo "Paste into the claude prompt (already on your clipboard):  @$REMOTE"
