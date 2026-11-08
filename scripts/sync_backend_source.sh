#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="https://github.com/cirvannaco-png/Midas-touch2-.git"
SOURCE_REF="${BACKEND_SOURCE_REF:-main}" # refresh source snapshot after validated upstream merges
SOURCE_DIR="${RUNNER_TEMP:-/tmp}/midas-touch2-source"
DEST_DIR="backend/source"

rm -rf "$SOURCE_DIR"
git clone --depth 1 --branch "$SOURCE_REF" "$SOURCE_REPO" "$SOURCE_DIR"
SOURCE_SHA="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

mkdir -p "$DEST_DIR"
rsync -a --delete --exclude='.git/' "$SOURCE_DIR/" "$DEST_DIR/"

cat > backend/SOURCE_REVISION.md <<EOF
# Backend source snapshot

- Upstream: $SOURCE_REPO
- Branch: $SOURCE_REF
- Commit: $SOURCE_SHA
- Snapshot path: backend/source/

This is a byte-for-byte source snapshot of the upstream repository, excluding its
Git object database. It preserves source, tests, migrations, docs, deployment
manifests and research tooling. Files nested under backend/source/.github/
are provenance only; GitHub Actions does not execute workflows from nested
directories.

The snapshot is not yet a claim that every backend capability is wired into the
root MT5 EA. Integration contracts and runtime validation remain separate gates.
EOF

git add "$DEST_DIR" backend/SOURCE_REVISION.md
if git diff --cached --quiet; then
  echo "Backend snapshot is already current."
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -m "chore: import complete Midas-touch2 backend source snapshot"
git push origin "HEAD:${GITHUB_REF_NAME}"
