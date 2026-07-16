# Contributing to ProofForge V2

Thanks for interest. This repository is the **V2 product tree** (`proof-forge-next`).
The archived v1 tree lives under [`active/`](active/ARCHIVE.md) and is research-only.

## Before you open a PR

1. Read [`AGENTS.md`](AGENTS.md) (control plane) and [`docs/document-status.md`](docs/document-status.md).
2. Prefer a focused change that matches one task in [`docs/04-task-breakdown.md`](docs/04-task-breakdown.md).
3. Do **not** import from `active/` or reintroduce legacy fallbacks.
4. Keep maturity claims honest (plan-only / source-only / runtime-validated).

## Local gates

```bash
just docs-check   # documentation control plane
just ci           # portable Linux subset (matches GitHub Actions)
# Full local hermetic suite (macOS + locked tools) is optional for most PRs:
# just check
```

CI on GitHub runs `docs` + `source-core` (`just ci`). A green hosted CI does **not**
mean hermetic clean-room evidence.

## Style and docs

- Prefer small, reviewable diffs.
- Spec or diagnostic changes: update ADR/spec/tests in the same PR when behavior changes.
- After documentation edits: `just docs-check` and `git diff --check`.
- Filenames under `docs/` must match the **lowercase** paths expected by
  `scripts/docs_check.py` (Linux CI is case-sensitive).

## Reporting issues

Use GitHub Issues with:

- What you ran (exact command)
- Expected vs actual output
- Toolchain: `lean --version`, OS
- Whether the failure is product code vs hermetic/local-only tooling

Security-sensitive reports: see [`SECURITY.md`](SECURITY.md).
