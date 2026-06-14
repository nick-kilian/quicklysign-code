#!/usr/bin/env bash
# open-coder: open the Coder dashboard in the browser.
set -euo pipefail

TF_DIR="$(dirname "$0")/../infra/terraform"
URL=$(terraform -chdir="$TF_DIR" output -raw coder_url 2>/dev/null || echo "https://coder.ragingbucket.com")

echo "Opening $URL"
open "$URL" 2>/dev/null || xdg-open "$URL" 2>/dev/null || echo "Open manually: $URL"
