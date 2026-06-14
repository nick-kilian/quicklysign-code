#!/usr/bin/env bash
# First-boot system bootstrap. Runs as root, invoked by the GCE startup script
# (see metadata_startup_script in main.tf) which templatefile()-renders this —
# shell variables here must avoid the $${...} form; $(...) and $VAR are fine.
#
# Failure here is logged but NEVER blocks the Coder agent from starting:
# a workspace you can SSH into with broken tooling beats an unreachable one.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Remove the legacy Google Cloud SDK apt repo if a previous build added it —
# its GPG key rotation breaks ALL of apt when stale (gcloud now comes via snap).
rm -f /etc/apt/sources.list.d/google-cloud-sdk.list /usr/share/keyrings/cloud.google.gpg

apt-get update -qq
apt-get install -y -qq git tmux htop jq ripgrep fd-find direnv unzip \
  curl ca-certificates gnupg build-essential postgresql-client redis-tools
ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# Docker Engine + Compose plugin (official repo; 'noble' = Ubuntu 24.04)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list

# GitHub CLI (official repo)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin gh

# Google Cloud CLI via snap: immune to Google's apt key rotations
snap install google-cloud-cli --classic

usermod -aG docker ${linux_user}
loginctl enable-linger ${linux_user} # user-level systemd (watchdog) runs at boot

echo "bootstrap complete"
