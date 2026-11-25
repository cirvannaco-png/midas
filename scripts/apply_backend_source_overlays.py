#!/usr/bin/env python3
"""Apply the reviewed Midas overlay to its exact pinned upstream snapshot."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / "backend/overlays/upstream-6dad8a00a522e3fd507b0f2669de47bcb47e43ee"
MANIFEST = OVERLAY / "manifest.json"


def safe_relative(value: str) -> Path:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise SystemExit(f"Unsafe overlay path: {value!r}")
    return path


def apply(source_dir: Path, source_sha: str) -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = manifest["upstream_commit"]
    if source_sha != expected:
        raise SystemExit(
            f"Refusing backend overlay: source commit {source_sha} does not match reviewed base {expected}. "
            "Review the new upstream diff and regenerate the overlay before refreshing."
        )

    for entry in manifest["files"]:
        relative = safe_relative(entry["path"])
        overlay_file = OVERLAY / relative
        content = overlay_file.read_bytes()
        if len(content) != entry["size_bytes"] or hashlib.sha256(content).hexdigest() != entry["sha256"]:
            raise SystemExit(f"Overlay integrity check failed: {entry['path']}")
        destination = source_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(overlay_file, destination)

    for value in manifest.get("deleted_paths", []):
        destination = source_dir / safe_relative(value)
        if destination.exists():
            if destination.is_dir():
                raise SystemExit(f"Refusing recursive overlay deletion: {value}")
            destination.unlink()

    print(f"Applied {len(manifest['files'])} reviewed Midas overlay files to {source_dir}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, default=ROOT / "backend/source")
    parser.add_argument("--source-sha", required=True)
    args = parser.parse_args()
    apply(args.source_dir.resolve(), args.source_sha)


if __name__ == "__main__":
    main()
