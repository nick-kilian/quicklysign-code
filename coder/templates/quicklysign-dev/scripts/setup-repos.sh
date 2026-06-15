#!/usr/bin/env bash
# setup-repos: clone the QuicklySign repos listed in repos.json, and keep the
# canonical ~/src clones fresh. Runs on every workspace boot. For a missing
# repo it clones; for an existing clone it `git fetch --all --prune` and
# fast-forwards the checked-out branch to its upstream when the clone is clean
# and on a tracking branch (the canonical clones stay pristine on their default
# branch, so this just advances e.g. main — it never merges/rebases and leaves
# lane worktrees untouched). Degrades gracefully when GitHub auth, the network,
# or the config file is missing.
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
    if ! git -C "$target" fetch --all --prune --quiet 2>/dev/null; then
      echo "ok:      $name (already cloned; fetch failed — offline/auth?)"
      continue
    fi
    # Fast-forward the checked-out branch to its upstream, but only when the
    # clone is clean and on a tracking branch. Never merges/rebases; a dirty
    # tree, detached HEAD, or diverged branch is left exactly as-is.
    cur=$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if [ -n "$cur" ] && [ -z "$(git -C "$target" status --porcelain 2>/dev/null)" ] &&
      git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      if git -C "$target" merge --ff-only --quiet '@{u}' 2>/dev/null; then
        echo "updated: $name (fetched + fast-forwarded $cur)"
      else
        echo "ok:      $name (fetched; $cur not fast-forwardable, left as-is)"
      fi
    else
      echo "ok:      $name (fetched; dirty/detached, branch not advanced)"
    fi
  else
    echo "cloning: $name -> $target"
    if ! git clone --quiet "$url" "$target"; then
      echo "FAILED:  $name (check access to $url)"
      failures=$((failures + 1))
    fi
  fi
done

echo "Repo setup complete."
