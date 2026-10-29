#!/bin/zsh
# Publish each reviewed local batch separately after the correct account has write access.
set -euo pipefail
cd "${0:A:h:h}"
if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 'Commit or preserve pending changes before publishing reviewed batches.'
  exit 1
fi
if [[ "$(git branch --show-current)" != main ]]; then
  print -u2 'This batch publisher expects the reviewed main branch.'
  exit 1
fi
git fetch origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
  print -u2 'GitHub has diverged. Integrate the remote changes before publishing; never force-push.'
  exit 1
fi
git rev-list --reverse origin/main..HEAD | while IFS= read -r batch_commit; do
  git show --no-patch --oneline "$batch_commit"
  git push origin "${batch_commit}:refs/heads/main"
done
