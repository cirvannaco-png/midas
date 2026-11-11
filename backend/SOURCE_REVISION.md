# Backend source snapshot

- Upstream: https://github.com/cirvannaco-png/Midas-touch2-.git
- Branch: main
- Commit: 52d737237c08f36d668853312f643cb74d4548da
- Snapshot path: backend/source/

This imports the complete upstream project tree (495 files and all 495 paths),
excluding its Git object database. It preserves source, tests, migrations,
docs, deployment manifests, and research tooling. Three imported files have
target-specific extensions for execution-deal slippage provenance and the
matching tests; the detailed paths and rationale are recorded in
docs/INTEGRATED_TRADING_ARCHITECTURE_AUDIT.md.

Files nested under backend/source/.github/ are provenance only; GitHub Actions
does not execute workflows from nested directories.

The canonical distributable EA is the generated root MidasTouch2.mq5, built
from the active modular source under development/EA/. The imported
backend/source/EA/ tree is the upstream reference snapshot, not a second
active build target. The active MetaEditor workflow is
.github/workflows/mt5-compile.yml.

The snapshot is not a claim that every backend or research capability is wired
into the root MT5 EA. Integration contracts and runtime validation remain
separate gates.
