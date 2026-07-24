# Contributing to ProofForge V2

Thanks for your interest. This repository is the **V2 product tree**
(`proof-forge-next`). The archived v1 tree under [`active/`](active/ARCHIVE.md)
is research-only and must never become a build or runtime dependency.

## Before you open a PR

1. Read [`AGENTS.md`](AGENTS.md), [`RECOVERY.md`](RECOVERY.md), and
   [`docs/document-status.md`](docs/document-status.md).
2. Prefer one runnable product slice. During recovery, the only active slice is
   `ProgramV1 → Typed → Semantic → EVM Counter artifacts`.
3. Do not add task-qualification ceremony, evidence ledger rows, legacy
   fallbacks, dual readers, or imports from `active/`.
4. Keep maturity claims precise: source-only, plan-only, artifact-validated,
   runtime-validated, or release-qualified are different statements.

## Local gates

```bash
just dev-check          # fast daily product loop
just ci                 # full product tests on an ordinary host

# Explicit, non-default control planes:
just governance-check   # historical task/freeze/evidence consistency
just release-check      # eligible-host and release preflight
```

GitHub runs the lightweight `docs` lane and the product `source-core` lane
(`just ci`). A green hosted CI does **not** mean hermetic or formal release
evidence. Conversely, an ineligible release host must not block ordinary
product development.

## Style and docs

- Prefer small, reviewable diffs and fail-closed behavior.
- Update the relevant architecture/spec text when product behavior changes;
  do not batch-rewrite historical implementation logs or evidence ledgers.
- After documentation edits, run `just docs-check` and `git diff --check`.
- Paths under `docs/` are lowercase where required by
  `scripts/docs_check.py`; Linux CI is case-sensitive.

## Reporting issues

Include:

- the exact command;
- expected and actual output;
- `lean --version` and OS;
- whether the failure is product code, governance audit, or release-only tooling.

Security-sensitive reports: see [`SECURITY.md`](SECURITY.md).
