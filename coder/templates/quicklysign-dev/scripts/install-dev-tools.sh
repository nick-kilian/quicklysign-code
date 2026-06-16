#!/usr/bin/env bash
# install-dev-tools: user-level toolchain. System packages (git, tmux, docker,
# gh, gcloud, jq, ripgrep, fd, direnv, psql, redis-cli, ...) are installed by
# the root startup script in main.tf; this script handles everything that
# lives in $HOME. Everything persists on the root disk, so this is a no-op
# after the first boot.
set -euo pipefail

STAMP="$HOME/.local/state/dev-tools.v2.done"
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

# Python: mise is the version manager — precompiled standalone interpreters
# (python-build-standalone), no from-source compile. Multiple versions are
# installed and exposed on PATH as python3.11 / python3.12 / python3.13;
# python & python3 default to 3.12. Switch per project with `mise use
# python@3.x` (writes .mise.toml). venv and poetry resolve these off PATH.
mise settings set python.compile false 2>/dev/null || true
mise use -g python@3.12 python@3.11 python@3.13

# uv: fast venv/runner + isolated tool installer. Point it at mise's
# interpreters (one source of truth) instead of keeping a parallel set; it
# still auto-downloads a version only if a project needs one mise lacks.
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
mkdir -p "$HOME/.config/uv"
grep -q 'python-preference' "$HOME/.config/uv/uv.toml" 2>/dev/null ||
  echo 'python-preference = "system"' >> "$HOME/.config/uv/uv.toml"

# poetry + ruff, globally available as isolated uv-managed tools (poetry uses
# the PATH python; pick a version per project with `poetry env use 3.x`). ruff
# is the format/lint gate CLAUDE.md asks for.
uv tool install poetry >/dev/null 2>&1 || true
uv tool install ruff >/dev/null 2>&1 || true

# Put mise's python shims + uv tool bin on the NON-interactive PATH too, so an
# agent's `bash -c` (which may not source .bashrc) gets mise's python3 (with
# pip/venv) and poetry/ruff/uv — not the bare /usr/bin/python3.
for b in python python3 python3.11 python3.12 python3.13; do
  s="$HOME/.local/share/mise/shims/$b"
  [ -x "$s" ] && sudo ln -sf "$s" "/usr/local/bin/$b"
done
for t in uv poetry ruff; do
  [ -x "$HOME/.local/bin/$t" ] && sudo ln -sf "$HOME/.local/bin/$t" "/usr/local/bin/$t"
done

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
