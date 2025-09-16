#!/usr/bin/env bash
set -euo pipefail

#############################################
# EDIT THESE 2 LINES ONCE (fixed credentials)
GITHUB_USER="burodw1024"          # your GitHub username
GITHUB_TOKEN="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" # your Personal Access Token (acts like password)
#############################################

OWNER="${OWNER:-$GITHUB_USER}"     # change to org name if pushing to an org
VISIBILITY="${2:-private}"         # 'public' or 'private' (default: private)

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 mlops [public|private]"
  exit 1
fi
REPO="$1"

# Dependencies check
command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl not found"; exit 1; }

API="https://api.github.com"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"

# 1) Create the repository on GitHub (idempotent)
# If OWNER == user → POST /user/repos; if org → POST /orgs/{org}/repos
create_payload() {
  cat <<JSON
{
  "name": "${REPO}",
  "private": $( [[ "${VISIBILITY}" == "private" ]] && echo true || echo false ),
  "description": "Auto-created by script",
  "auto_init": false
}
JSON
}

# Check if repo exists
status=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
  "${API}/repos/${OWNER}/${REPO}")

if [[ "$status" == "404" ]]; then
  if [[ "$OWNER" == "$GITHUB_USER" ]]; then
    create_code=$(curl -sS -o /dev/null -w "%{http_code}" \
      -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
      -X POST "${API}/user/repos" \
      -d "$(create_payload)")
  else
    create_code=$(curl -sS -o /dev/null -w "%{http_code}" \
      -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
      -X POST "${API}/orgs/${OWNER}/repos" \
      -d "$(create_payload)")
  fi

  if [[ "$create_code" != "201" ]]; then
    echo "Failed to create repo (${OWNER}/${REPO}). HTTP ${create_code}"
    exit 1
  fi
  echo "✅ Created repo: https://github.com/${OWNER}/${REPO}"
else
  echo "ℹ️ Repo already exists: https://github.com/${OWNER}/${REPO}"
fi

# 2) Initialize local repo in current folder (if needed)
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init
fi

# Ensure identity (avoid “please tell me who you are”)
git config --get user.name  >/dev/null 2>&1 || git config user.name  "${GITHUB_USER}"
git config --get user.email >/dev/null 2>&1 || git config user.email "${GITHUB_USER}@users.noreply.github.com"

# 3) Stage & commit
git add -A
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  git commit --allow-empty -m "Initial commit"
else
  if ! git diff --cached --quiet; then
    git commit -m "Initial commit"
  fi
fi

# 4) Use main branch
git branch -M main

# 5) Set remote with embedded token (no prompts)
REMOTE_WITH_TOKEN="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${OWNER}/${REPO}.git"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_WITH_TOKEN"
else
  git remote add origin "$REMOTE_WITH_TOKEN"
fi

# 6) If remote main exists (e.g., someone added README), rebase then push
if git ls-remote --exit-code --heads "https://github.com/${OWNER}/${REPO}.git" main >/dev/null 2>&1; then
  git pull --rebase origin main --allow-unrelated-histories || true
fi

# 7) Push
git push -u origin main

echo
echo "✅ Done. Repo URL: https://github.com/${OWNER}/${REPO}"
echo "   Branch: main"
echo "   (Remote saved with token so future pushes won’t prompt.)"
