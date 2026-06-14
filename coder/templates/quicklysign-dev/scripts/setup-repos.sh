#!/usr/bin/env bash
# setup-repos: clone the QuicklySign repos listed in repos.json.
# Safe to run repeatedly; skips repos that already exist and degrades
# gracefully when GitHub auth or the config file is missing.
set -uo pipefail

CONFIG="${1:-$HOME/.config/quicklysign/repos.json}"

if [ ! -f "$CONFIG" ]; then
  echo "No repo config found at $CONFIG."
  echo "Copy repos.example.json there (or push an updated template) to enable cloning."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) not installed yet; skipping repo setup."
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Not authenticated to GitHub. To clone the QuicklySign repos, run:"
  echo "    gh auth login        # one-time; stored on the persistent disk"
  echo "    setup-repos          # then re-run this"
  exit 0
fi

# Let git use gh's credentials for HTTPS clones (idempotent).
gh auth setup-git >/dev/null 2>&1 || true

mkdir -p "$HOME/src"
failures=0

jq -c '.[]' "$CONFIG" | while read -r repo; do
  name=$(jq -r '.name' <<<"$repo")
  url=$(jq -r '.url' <<<"$repo")
  raw_path=$(jq -r '.path' <<<"$repo")
  target="${raw_path/#\~/$HOME}"

  if [ -d "$target/.git" ]; then
    echo "ok:      $name (already cloned)"
  else
    echo "cloning: $name -> $target"
    if ! git clone --quiet "$url" "$target"; then
      echo "FAILED:  $name (check access to $url)"
      failures=$((failures + 1))
    fi
  fi
done

echo "Repo setup complete."
