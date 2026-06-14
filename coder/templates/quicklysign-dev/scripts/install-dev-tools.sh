#!/usr/bin/env bash
# install-dev-tools: user-level toolchain. System packages (git, tmux, docker,
# gh, gcloud, jq, ripgrep, fd, direnv, psql, redis-cli, ...) are installed by
# the root startup script in main.tf; this script handles everything that
# lives in $HOME. Everything persists on the root disk, so this is a no-op
# after the first boot.
set -euo pipefail

STAMP="$HOME/.local/state/dev-tools.v1.done"
if [ -f "$STAMP" ]; then
  echo "dev tools already installed ($STAMP exists)"
  exit 0
fi

export PATH="$HOME/.local/bin:$PATH"

# mise: single runtime manager for Node (and anything else later).
# Chosen over asdf: faster (no shim overhead in exec mode), actively
# maintained, asdf-plugin compatible.
if ! command -v mise >/dev/null 2>&1; then
  curl -fsSL https://mise.run | sh
fi
grep -q 'mise activate' "$HOME/.bashrc" 2>/dev/null || \
  echo 'eval "$("$HOME/.local/bin/mise" activate bash)"' >> "$HOME/.bashrc"
eval "$("$HOME/.local/bin/mise" activate bash --shims)"

mise use -g node@22
mise use -g zellij@latest # optional multiplexer; tmux (apt) is the default

# pnpm + devcontainers CLI via npm (Node 22 from mise)
npm install -g pnpm @devcontainers/cli

# uv manages Python (prebuilt standalone interpreters — no compile step,
# unlike mise/asdf python plugins which build from source)
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
"$HOME/.local/bin/uv" python install 3.12

# direnv shell hook
grep -q 'direnv hook' "$HOME/.bashrc" 2>/dev/null || \
  echo 'eval "$(direnv hook bash)"' >> "$HOME/.bashrc"

# tmux defaults (only if you haven't customised it)
if [ ! -f "$HOME/.tmux.conf" ]; then
  cat > "$HOME/.tmux.conf" <<'EOF'
# QuicklySign workspace defaults — edit freely, this file is yours.
set -g mouse on
set -g history-limit 100000
set -g default-terminal "tmux-256color"
set -g renumber-windows on
setw -g automatic-rename off   # lane names are set explicitly by agent-run/worklane

# Optional: tmux-resurrect/continuum restore tmux LAYOUTS after a VM restart,
# NOT running Claude/Codex processes. The durable recovery path is
# `claude --resume <lane>` / `codex resume --last` (see worklane).
# To enable: git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
# and uncomment:
# set -g @plugin 'tmux-plugins/tpm'
# set -g @plugin 'tmux-plugins/tmux-resurrect'
# set -g @plugin 'tmux-plugins/tmux-continuum'
# run '~/.tmux/plugins/tpm/tpm'
EOF
fi

mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
echo "dev tools installed"
