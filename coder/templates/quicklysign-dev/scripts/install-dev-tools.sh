#!/bin/bash
set -e

echo "🛠️ Installing dev tools..."

# Docker & Docker Compose
if ! command -v docker &> /dev/null; then
    sudo apt-get install -y ca-certificates gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker $USER
fi

# mise (replacing asdf) - multi-runtime manager
if ! command -v mise &> /dev/null; then
    curl https://mise.jdx.dev/install.sh | sh
    echo 'eval "$(/home/coder/.local/bin/mise activate bash)"' >> ~/.bashrc
    export PATH="/home/coder/.local/bin:$PATH"
    eval "$(mise activate bash)"
fi

# Node.js 22 & Python 3.12 via mise
mise use -g node@22 python@3.12
mise install

# pnpm & npm (npm comes with node)
corepack enable
corepack prepare pnpm@latest --activate

# uv (Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# GitHub CLI
if ! command -v gh &> /dev/null; then
    type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh -y
fi

# Google Cloud CLI
if ! command -v gcloud &> /dev/null; then
    curl https://sdk.cloud.google.com | bash -s -- --disable-prompts
    echo 'source /home/coder/google-cloud-sdk/path.bash.inc' >> ~/.bashrc
fi

# PostgreSQL & Redis client tools
sudo apt-get install -y postgresql-client redis-tools

# Devcontainers CLI
npm install -g @devcontainers/cli

echo "✅ Dev tools installed!"
