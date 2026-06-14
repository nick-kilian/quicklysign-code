#!/usr/bin/env bash
# create-template: create or update the quicklysign-dev template in Coder.
set -euo pipefail

TEMPLATE_NAME="quicklysign-dev"
TEMPLATE_DIR="$(dirname "$0")/../coder/templates/quicklysign-dev"

if ! command -v coder >/dev/null 2>&1; then
  echo "ERROR: coder CLI not installed. Run: curl -fsSL https://coder.com/install.sh | sh"
  exit 1
fi

if ! coder templates list >/dev/null 2>&1; then
  echo "ERROR: not logged in to Coder. Run: coder login https://coder.ragingbucket.com"
  exit 1
fi

# Older CLIs emit [{...}], newer wrap rows as [{"Template": {...}}] — handle both.
if coder templates list --output json 2>/dev/null | jq -e --arg n "$TEMPLATE_NAME" '.[] | (.Template // .) | select(.name == $n)' >/dev/null; then
  echo "Updating existing template $TEMPLATE_NAME..."
  coder templates push "$TEMPLATE_NAME" --directory "$TEMPLATE_DIR" --yes
else
  echo "Creating template $TEMPLATE_NAME..."
  coder templates create "$TEMPLATE_NAME" --directory "$TEMPLATE_DIR" --yes
fi

# Default autostop: 1 hour of no activity. The agent watchdog extends this
# while Claude/Codex are actively working.
coder templates edit "$TEMPLATE_NAME" --default-ttl 1h --yes \
  || echo "NOTE: could not set default TTL via CLI; set 'Default autostop: 1 hour' in the template UI settings."

echo "Template $TEMPLATE_NAME is ready."
