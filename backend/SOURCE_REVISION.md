# Backend source snapshot

- Upstream: https://github.com/cirvannaco-png/Midas-touch2-.git
- Branch: main
- Commit: 6dad8a00a522e3fd507b0f2669de47bcb47e43ee
- Snapshot path: backend/source/

This imports the complete upstream project tree (495 files and all 495 paths),
excluding its Git object database. It preserves source, tests, migrations,
docs, deployment manifests, and research tooling. The imported snapshot is refreshed through 6dad8a00a522e3fd507b0f2669de47bcb47e43ee. Three imported files have
target-specific extensions for execution-deal slippage provenance and the
matching tests; the detailed paths and rationale are recorded in
docs/INTEGRATED_TRADING_ARCHITECTURE_AUDIT.md.

Files nested under backend/source/.github/ are provenance only; GitHub Actions
does not execute workflows from nested directories.

The canonical distributable EA is the generated, self-contained
`development/EA/MedisTouch_v2.8.mq5`, built from the modular entrypoint
`development/EA/MedisTouch_v2.8.source.mq5` and local modules under
`development/EA/includes/`. Native tests remain separate under
`development/EA/tests/`. The imported
backend/source/EA/ tree is the upstream reference snapshot, not a second
active build target. The active MetaEditor workflow is
.github/workflows/mt5-compile.yml.

The snapshot is not a claim that every backend or research capability is wired
into the root MT5 EA. Integration contracts and runtime validation remain
separate gates.
