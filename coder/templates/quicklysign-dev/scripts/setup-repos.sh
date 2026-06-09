#!/bin/bash

echo "📂 Checking repository configuration..."

REPO_CONFIG="/home/coder/repos.json"

if [ ! -f "$REPO_CONFIG" ]; then
    echo "⚠️  No repos.json found at $REPO_CONFIG."
    echo "💡 To automate repository cloning, create $REPO_CONFIG with the following structure:"
    echo '   ['
    echo '     {'
    echo '       "name": "your-repo-name",'
    echo '       "url": "git@github.com:your-org/your-repo.git",'
    echo '       "path": "~/src/your-repo-name"'
    echo '     }'
    echo '   ]'
    echo "⏭️  Skipping automatic repository setup."
    exit 0
fi

echo "🚀 Parsing $REPO_CONFIG and cloning repositories..."

mkdir -p ~/src

if command -v jq &> /dev/null; then
    jq -c '.[]' "$REPO_CONFIG" | while read -r repo; do
        NAME=$(echo "$repo" | jq -r '.name')
        URL=$(echo "$repo" | jq -r '.url')
        PATH_RAW=$(echo "$repo" | jq -r '.path')
        # Expand ~ to $HOME
        TARGET_PATH="${PATH_RAW/#\~/$HOME}"

        if [ ! -d "$TARGET_PATH" ]; then
            echo "📥 Cloning $NAME into $TARGET_PATH..."
            git clone "$URL" "$TARGET_PATH" || echo "❌ Failed to clone $NAME (check SSH keys or URL)"
        else
            echo "✅ $NAME already exists at $TARGET_PATH"
        fi
    done
else
    echo "❌ jq not found, skipping repo auto-setup."
fi

echo "✅ Repository setup phase complete."
