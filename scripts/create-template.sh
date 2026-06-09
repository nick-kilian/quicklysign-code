#!/bin/bash
set -e

TEMPLATE_NAME="quicklysign-dev"
TEMPLATE_DIR="coder/templates/quicklysign-dev"

echo "🏗️ Creating Coder template: $TEMPLATE_NAME..."

# Check if logged in to coder
if ! coder profile ls &>/dev/null; then
    echo "❌ Not logged in to Coder. Run 'coder login <url>' first."
    exit 1
fi

# Create/Update the template
coder templates create "$TEMPLATE_NAME" \
    --directory "$TEMPLATE_DIR" \
    --yes

echo "✅ Template $TEMPLATE_NAME created/updated!"
