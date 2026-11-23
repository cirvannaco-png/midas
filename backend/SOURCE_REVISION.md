# Backend source base and Midas overlay

- Upstream: https://github.com/cirvannaco-png/Midas-touch2-.git
- Reviewed upstream commit: `6dad8a00a522e3fd507b0f2669de47bcb47e43ee`
- Snapshot path: `backend/source/`
- Midas overlay manifest: `backend/overlays/upstream-6dad8a00a522e3fd507b0f2669de47bcb47e43ee/manifest.json`
- Overlay files: 19

The upstream base contains the reviewed 495-file source tree. Midas-specific
reconciliations are applied from the versioned overlay after every refresh;
`backend/source/` is therefore the upstream base plus the explicit Midas
overlay, not a byte-for-byte unmodified upstream checkout. The overlay
manifest records each file's SHA-256 and size. `scripts/apply_backend_source_overlays.py`
verifies the source commit and every overlay file hash, and fails closed on a
different upstream commit. Review the new upstream diff and regenerate the
overlay before changing the pin.

The overlay preserves the target-specific tester/deal-attribution extensions
and the Midas-native account-wide margin-admission contract, including its
bridge API, regression tests, and protocol version. See
`docs/MIDAS_MARGIN_ADMISSION_IMPLEMENTATION.md` and the overlay manifest for
the exact files.

Files nested under `backend/source/.github/` are provenance only; GitHub
Actions does not execute workflows from nested directories. The active Midas
EA build is `development/EA/MedisTouch_v2.8.mq5`; active CI workflows are at
the repository root.
