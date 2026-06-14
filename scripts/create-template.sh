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

# Default autostop: 1 hour. Activity bump is set to 0 so an open connection
# (SSH/IDE/web terminal) does NOT extend the deadline — a forgotten-open session
# can't keep the workspace (and its cost) alive. The agent-watchdog's explicit
# `coder schedule extend` is then the ONLY thing that pushes the deadline out,
# and only while Claude/Codex are actively working. Trade-off: manual (non-agent)
# work also won't auto-extend — use an agent lane or `coder schedule extend`.
#
# NOTE: `--activity-bump 0` is forward-compatible but a NO-OP on coder CLI < 2.34
# (it drops the zero value, omitempty). activity_bump=0 was applied out-of-band
# via the API (PATCH /api/v2/templates/{id}) and is a template-level setting, so
# it persists across these version pushes. If it ever reverts to 1h, re-apply via
# the UI (Template > Settings > Schedule > Activity bump = 0) or the API.
coder templates edit "$TEMPLATE_NAME" --default-ttl 1h --activity-bump 0 --yes \
  || echo "NOTE: could not set TTL via CLI; set 'Default autostop: 1h' and 'Activity bump: 0' in the template UI settings."

echo "Template $TEMPLATE_NAME is ready."
