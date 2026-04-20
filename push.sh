#!/usr/bin/env bash
# Quick push to GitHub.
# Reads token from ~/.github_token (chmod 600) or GH_TOKEN env var.
#
# Usage:
#   ./push.sh                  # auto commit all changes + push
#   ./push.sh "commit message" # custom commit message

set -euo pipefail

# ── resolve token ─────────────────────────────────────────────────────────────
TOKEN="${GH_TOKEN:-}"
if [[ -z "$TOKEN" && -f "$HOME/.github_token" ]]; then
  TOKEN=$(cat "$HOME/.github_token")
fi
if [[ -z "$TOKEN" ]]; then
  echo "Error: no token found. Set GH_TOKEN or create ~/.github_token" >&2
  exit 1
fi

# ── resolve remote URL with token ─────────────────────────────────────────────
REMOTE_URL=$(git remote get-url origin)
# inject token into https URL: https://user:TOKEN@github.com/...
AUTH_URL=$(echo "$REMOTE_URL" | sed "s|https://|https://$(git config user.name):${TOKEN}@|")

# ── stage & commit if there are changes ───────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n $(git ls-files --others --exclude-standard) ]]; then
  MSG="${1:-chore: update $(date '+%Y-%m-%d %H:%M')}"
  git add -A
  git commit -m "$MSG"
  echo "Committed: $MSG"
else
  echo "Nothing to commit."
fi

# ── push ──────────────────────────────────────────────────────────────────────
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push "$AUTH_URL" "$BRANCH"
echo "Pushed -> $REMOTE_URL ($BRANCH)"
