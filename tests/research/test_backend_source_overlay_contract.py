import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OVERLAY = ROOT / "backend/overlays/upstream-6dad8a00a522e3fd507b0f2669de47bcb47e43ee"


def test_backend_overlay_is_bound_to_exact_reviewed_upstream_commit():
    manifest = json.loads((OVERLAY / "manifest.json").read_text())
    assert manifest["upstream_commit"] == "6dad8a00a522e3fd507b0f2669de47bcb47e43ee"
    assert len(manifest["files"]) == 19
    assert manifest["deleted_paths"] == []


def test_every_backend_overlay_file_matches_its_hash_and_applied_copy():
    manifest = json.loads((OVERLAY / "manifest.json").read_text())
    for entry in manifest["files"]:
        relative = Path(entry["path"])
        assert not relative.is_absolute() and ".." not in relative.parts
        overlay_file = OVERLAY / relative
        applied_file = ROOT / "backend/source" / relative
        content = overlay_file.read_bytes()
        assert len(content) == entry["size_bytes"]
        assert hashlib.sha256(content).hexdigest() == entry["sha256"]
        assert applied_file.read_bytes() == content


def test_backend_sync_refuses_unreviewed_upstream_refresh():
    script = (ROOT / "scripts/sync_backend_source.sh").read_text()
    apply_script = (ROOT / "scripts/apply_backend_source_overlays.py").read_text()
    workflow = (ROOT / ".github/workflows/backend-source-sync.yml").read_text()
    assert "Refusing unreviewed backend source refresh" in script
    assert "apply_backend_source_overlays.py" in script
    assert "source_sha != expected" in apply_script
    assert "6dad8a00a522e3fd507b0f2669de47bcb47e43ee" in workflow
