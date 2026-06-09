#!/bin/bash

# Log all output
exec > >(tee -a /tmp/coder-startup-script.log) 2>&1

echo "🚀 Starting workspace bootstrap..."

mkdir -p /home/coder/scripts
mkdir -p /home/coder/.local/bin

# --- Create install-dev-tools.sh ---
cat <<'EOF' > /home/coder/scripts/install-dev-tools.sh
#!/bin/bash
set -e
echo "🛠️ Installing dev tools..."
sudo apt-get update
sudo apt-get install -y ca-certificates gnupg lsb-release curl git tmux jq ripgrep fd-find htop direnv postgresql-client redis-tools
# Docker
if ! command -v docker &> /dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker $USER
fi
# mise
if ! command -v mise &> /dev/null; then
    curl https://mise.jdx.dev/install.sh | sh
    export PATH="/home/coder/.local/bin:$PATH"
fi
# Node & Python via mise
/home/coder/.local/bin/mise use -g node@22 python@3.12
/home/coder/.local/bin/mise install
# uv
curl -LsSf https://astral.sh/uv/install.sh | sh
# GitHub CLI
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update && sudo apt install gh -y
fi
echo "✅ Dev tools installed!"
EOF
chmod +x /home/coder/scripts/install-dev-tools.sh

# --- Create install-agent-tools.sh ---
cat <<'EOF' > /home/coder/scripts/install-agent-tools.sh
#!/bin/bash
set -e
echo "🤖 Installing agent tools..."
mkdir -p ~/.local/share/agent-sessions
# Placeholder for Claude/Codex
echo "#!/bin/bash" > ~/.local/bin/claude
echo "echo 'Claude Code CLI not installed. Run: npm install -g @anthropic-ai/claude-code'" >> ~/.local/bin/claude
chmod +x ~/.local/bin/claude
echo "#!/bin/bash" > ~/.local/bin/codex
echo "echo 'Codex CLI not installed.'" >> ~/.local/bin/codex
chmod +x ~/.local/bin/codex
# Systemd service for watchdog
mkdir -p ~/.config/systemd/user/
cat <<EOT > ~/.config/systemd/user/agent-watchdog.service
[Unit]
Description=Coder Agent Activity Watchdog
[Service]
ExecStart=/home/coder/.local/bin/agent-watchdog
Restart=always
[Install]
WantedBy=default.target
EOT
echo "✅ Agent tools configured!"
EOF
chmod +x /home/coder/scripts/install-agent-tools.sh

# --- Create agent-run ---
cat <<'EOF' > /home/coder/.local/bin/agent-run
#!/bin/bash
SESSION_NAME=$1
AGENT_TYPE=$2
shift 2
REPO_PATH="."
TTL="4h"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --repo) REPO_PATH="$2"; shift ;;
        --ttl) TTL="$2"; shift ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done
METADATA_DIR="$HOME/.local/share/agent-sessions"
mkdir -p "$METADATA_DIR"
METADATA_FILE="$METADATA_DIR/$SESSION_NAME.json"
REPO_PATH=$(realpath "$REPO_PATH")
cat <<EOM > "$METADATA_FILE"
{ "name": "$SESSION_NAME", "agent_type": "$AGENT_TYPE", "repo_path": "$REPO_PATH", "start_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")", "ttl": "$TTL", "status": "active" }
EOM
tmux new-session -d -s "$SESSION_NAME" -c "$REPO_PATH" "$AGENT_TYPE ${ARGS[*]}"
EOF
chmod +x /home/coder/.local/bin/agent-run

# --- Create agent-watchdog.sh ---
cat <<'EOF' > /home/coder/.local/bin/agent-watchdog
#!/bin/bash
while true; do
    for meta in "$HOME/.local/share/agent-sessions/"*.json; do
        [ -e "$meta" ] || continue
        SESSION_NAME=$(basename "$meta" .json)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            # Simple check: has output changed?
            LAST_OUT="/tmp/watchdog_$SESSION_NAME.txt"
            tmux capture-pane -t "$SESSION_NAME" -p > "$LAST_OUT.new"
            if [ -f "$LAST_OUT" ] && ! diff -q "$LAST_OUT" "$LAST_OUT.new" >/dev/null; then
                coder schedule extend 45m
            fi
            mv "$LAST_OUT.new" "$LAST_OUT"
        fi
    done
    sleep 60
done
EOF
chmod +x /home/coder/.local/bin/agent-watchdog

# --- Create agent-status.sh ---
cat <<'EOF' > /home/coder/.local/bin/agent-status
#!/bin/bash
printf "%-20s %-10s %-20s %-10s\n" "SESSION" "AGENT" "REPO" "STATE"
for meta in "$HOME/.local/share/agent-sessions/"*.json; do
    [ -e "$meta" ] || continue
    NAME=$(jq -r '.name' "$meta")
    AGENT=$(jq -r '.agent_type' "$meta")
    REPO=$(jq -r '.repo_path' "$meta" | sed "s|$HOME|~|")
    STATE=$(jq -r '.status' "$meta")
    printf "%-20s %-10s %-20s %-10s\n" "$NAME" "$AGENT" "$REPO" "$STATE"
done
EOF
chmod +x /home/coder/.local/bin/agent-status

# --- Create worklane ---
cat <<'EOF' > /home/coder/.local/bin/worklane
#!/bin/bash
SESSION_NAME=$1
METADATA_FILE="$HOME/.local/share/agent-sessions/$SESSION_NAME.json"
if [ -f "$METADATA_FILE" ]; then
    REPO_PATH=$(jq -r '.repo_path' "$METADATA_FILE")
    cd "$REPO_PATH" && tmux attach-session -t "$SESSION_NAME"
else
    echo "Unknown worklane: $SESSION_NAME"
fi
EOF
chmod +x /home/coder/.local/bin/worklane

# Run installs
/home/coder/scripts/install-dev-tools.sh
/home/coder/scripts/install-agent-tools.sh

# Start Watchdog
systemctl --user daemon-reload
systemctl --user enable agent-watchdog.service
systemctl --user start agent-watchdog.service

echo "✅ Workspace bootstrap complete!"
