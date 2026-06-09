#!/bin/bash
set -e

echo "🤖 Installing agent tools..."

# Create session directory
mkdir -p ~/.local/share/agent-sessions
mkdir -p ~/.local/bin

# Claude Code CLI (Placeholder for actual install command)
# Example: npm install -g @anthropic-ai/claude-code
echo "#!/bin/bash" > ~/.local/bin/claude
echo "echo 'Claude Code CLI not installed. Please run: npm install -g @anthropic-ai/claude-code'" >> ~/.local/bin/claude
chmod +x ~/.local/bin/claude

# Codex CLI (Placeholder for actual install command)
echo "#!/bin/bash" > ~/.local/bin/codex
echo "echo 'Codex CLI not installed. Please follow your internal install instructions.'" >> ~/.local/bin/codex
chmod +x ~/.local/bin/codex

# Copy agent scripts to ~/.local/bin
cp /home/coder/scripts/agent-run ~/.local/bin/agent-run
cp /home/coder/scripts/agent-status.sh ~/.local/bin/agent-status
cp /home/coder/scripts/worklane ~/.local/bin/worklane
chmod +x ~/.local/bin/agent-run ~/.local/bin/agent-status ~/.local/bin/worklane

# Install Watchdog as a systemd user service
mkdir -p ~/.config/systemd/user/
cat <<EOT > ~/.config/systemd/user/agent-watchdog.service
[Unit]
Description=Coder Agent Activity Watchdog
After=network.target

[Service]
EnvironmentFile=%h/.coder_env
ExecStart=/home/coder/.local/bin/agent-watchdog
Restart=always
RestartSec=60

[Install]
WantedBy=default.target
EOT

echo "✅ Agent tools and watchdog service configured!"
