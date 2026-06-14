#!/usr/bin/env bash
# install-agent-tools: Claude Code CLI, Codex CLI, the Coder CLI, activity
# hooks for both agents, and the agent-watchdog systemd user service.
# Idempotent; everything persists on the root disk.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
BIN="$HOME/.local/bin"

# --- Coder CLI: downloaded from our own deployment so the version always
#     matches the server (the agent exports CODER_URL).
if [ ! -x "$BIN/coder" ] && [ -n "${CODER_URL:-}" ]; then
  curl -fsSL "$CODER_URL/bin/coder-linux-amd64" -o "$BIN/coder"
  chmod +x "$BIN/coder"
fi

# --- Claude Code CLI (official native installer; self-updates) ---
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- Codex CLI (needs Node 22 from mise; install-dev-tools runs first) ---
if ! command -v codex >/dev/null 2>&1; then
  eval "$("$HOME/.local/bin/mise" activate bash --shims)" 2>/dev/null || true
  npm install -g @openai/codex || echo "WARN: codex install failed; run 'npm install -g @openai/codex' manually"
fi

# --- Gemini CLI (third backend for the code-review ensemble) ---
if ! command -v gemini >/dev/null 2>&1; then
  eval "$("$HOME/.local/bin/mise" activate bash --shims)" 2>/dev/null || true
  npm install -g @google/gemini-cli || echo "WARN: gemini install failed; run 'npm install -g @google/gemini-cli' manually"
fi

HOOK="$HOME/.local/bin/agent-activity-hook"

# --- Claude Code hooks: report working/waiting to the watchdog.
#     Merged into ~/.claude/settings.json without clobbering your settings.
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"

hook_entry() { printf '[{"hooks":[{"type":"command","command":"%s"}]}]' "$HOOK"; }

tmp=$(mktemp)
jq --argjson entry "$(hook_entry)" '
  .hooks = (.hooks // {})
  | .hooks.UserPromptSubmit = $entry
  | .hooks.PreToolUse       = $entry
  | .hooks.PostToolUse      = $entry
  | .hooks.Stop             = $entry
  | .hooks.Notification     = $entry
  | .hooks.SessionEnd       = $entry
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# --- Codex notify hook: fires on agent-turn-complete (= waiting for input).
#     "Working" detection for Codex falls back to the watchdog's tmux/file
#     heuristics. notify is only honoured in the user-level config.
CODEX_CFG="$HOME/.codex/config.toml"
mkdir -p "$HOME/.codex"
touch "$CODEX_CFG"
if ! grep -q '^notify' "$CODEX_CFG"; then
  printf '\nnotify = ["%s"]\n' "$HOOK" >> "$CODEX_CFG"
fi

# --- Watchdog systemd user service (lingering enabled by root startup) ---
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/agent-watchdog.service" <<'EOF'
[Unit]
Description=Agent-aware idle watchdog (extends Coder autostop while agents work)

[Service]
Type=simple
EnvironmentFile=%h/.config/agent-watchdog/env
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=%h/.local/bin/agent-watchdog
Restart=always
RestartSec=30

[Install]
WantedBy=default.target
EOF

# Expose the lane commands on the default PATH so non-interactive SSH
# (`ssh <ws>.coder -t 'worklane x'`) finds them — ~/.local/bin is only on
# PATH in interactive shells.
for c in worklane lane-init agent-run agent-status setup-repos list-app-ports; do
  sudo ln -sf "$HOME/.local/bin/$c" "/usr/local/bin/$c"
done

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now agent-watchdog.service 2>/dev/null \
  || echo "WARN: could not start agent-watchdog via systemd --user; check 'loginctl enable-linger'"

echo "agent tools installed"
echo
echo "One-time logins (credentials persist on this disk):"
command -v claude >/dev/null && claude --version >/dev/null 2>&1 || true
echo "  claude   -> run 'claude' and follow the browser-code login (works over SSH)"
echo "  codex    -> run 'codex login --device-auth'"
echo "  github   -> run 'gh auth login' then 'setup-repos'"
