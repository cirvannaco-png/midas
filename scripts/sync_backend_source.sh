#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="https://github.com/cirvannaco-png/Midas-touch2-.git"
OVERLAY_MANIFEST="backend/overlays/upstream-6dad8a00a522e3fd507b0f2669de47bcb47e43ee/manifest.json"
EXPECTED_SOURCE_SHA="$(python3 -c 'import json; print(json.load(open("'"$OVERLAY_MANIFEST"'"))["upstream_commit"])')"
SOURCE_REF="${BACKEND_SOURCE_REF:-$EXPECTED_SOURCE_SHA}"
SOURCE_DIR="${RUNNER_TEMP:-/tmp}/midas-touch2-source"
DEST_DIR="backend/source"

rm -rf "$SOURCE_DIR"
git clone --filter=blob:none --no-checkout "$SOURCE_REPO" "$SOURCE_DIR"
git -C "$SOURCE_DIR" fetch --depth 1 origin "$SOURCE_REF"
git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
SOURCE_SHA="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

if [[ "$SOURCE_SHA" != "$EXPECTED_SOURCE_SHA" ]]; then
  echo "Refusing unreviewed backend source refresh: expected $EXPECTED_SOURCE_SHA, received $SOURCE_SHA." >&2
  echo "Review the new upstream source/PR diffs and regenerate the Midas overlay first." >&2
  exit 2
fi

mkdir -p "$DEST_DIR"
rsync -a --delete --exclude='.git/' "$SOURCE_DIR/" "$DEST_DIR/"
python3 scripts/apply_backend_source_overlays.py --source-dir "$DEST_DIR" --source-sha "$SOURCE_SHA"

cat > backend/SOURCE_REVISION.md <<EOF
# Backend source base and Midas overlay

- Upstream: $SOURCE_REPO
- Reviewed upstream commit: $SOURCE_SHA
- Snapshot path: backend/source/
- Midas overlay manifest: backend/overlays/upstream-6dad8a00a522e3fd507b0f2669de47bcb47e43ee/manifest.json

The upstream base is pinned to an exact reviewed commit. Midas-specific
reconciliations are applied from the versioned overlay after every refresh;
this directory is therefore the upstream base plus the explicit Midas overlay,
not a byte-for-byte unmodified upstream checkout. The overlay script verifies
the source commit and every overlay file hash, and fails closed on a different
upstream commit. Review and regenerate the overlay before changing the pin.

Files nested under backend/source/.github/ are provenance only; GitHub Actions
does not execute workflows from nested directories. The active Midas EA build
is development/EA/MedisTouch_v2.8.mq5 and the active CI workflows are at the
repository root.
EOF

git add "$DEST_DIR" backend/SOURCE_REVISION.md
if git diff --cached --quiet; then
  echo "Backend snapshot and reviewed overlay are already current."
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -m "chore: refresh reviewed Midas backend source and overlay"
git push origin "HEAD:${GITHUB_REF_NAME}"
