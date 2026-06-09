#!/bin/bash

echo "📂 Setting up repositories..."

REPO_CONFIG="/home/coder/repos.json"
if [ ! -f "$REPO_CONFIG" ]; then
    echo "⚠️ No repos.json found at $REPO_CONFIG. Using example."
    REPO_CONFIG="/home/coder/scripts/repos.example.json"
fi

mkdir -p ~/src

# Parse JSON and clone if not exists
# Using a simple loop and jq
if command -v jq &> /dev/null; then
    jq -c '.[]' "$REPO_CONFIG" | while read -r repo; do
        NAME=$(echo "$repo" | jq -r '.name')
        URL=$(echo "$repo" | jq -r '.url')
        PATH_RAW=$(echo "$repo" | jq -r '.path')
        # Expand ~ to $HOME
        TARGET_PATH="${PATH_RAW/#\~/$HOME}"

        if [ ! -d "$TARGET_PATH" ]; then
            echo "Cloning $NAME into $TARGET_PATH..."
            # Note: This might fail if SSH keys are not set up yet
            git clone "$URL" "$TARGET_PATH" || echo "Failed to clone $NAME (likely missing SSH keys)"
        else
            echo "✅ $NAME already exists at $TARGET_PATH"
        fi
    done
else
    echo "❌ jq not found, skipping repo auto-setup."
fi

echo "✅ Repository setup phase complete."
