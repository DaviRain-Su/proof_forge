# Contributing to ProofForge V2

Thanks for your interest. This repository is the **V2 product tree**
(`proof-forge-next`). It contains only the V2 product tree — no v1 archive,
no legacy `ProofForge.*` imports, and no v1 fallbacks.

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
just dev-check          # fast daily product loop (docs + build + test-fast + gates)
just test-fast          # core product tests only (daily feedback)
just test               # all memory-bounded shards (bounded parallel)
just ci                 # full product tests on an ordinary host

# Focused (after `just build` deps via the recipe):
just test-shard core    # one shard: core|typed|language-b|…|targets
just test-targets       # targets materialization suite only

# Parallelism for `just test` shard *execution* (not lake build):
# PROOF_FORGE_TEST_JOBS=1   # serial (low-memory CI)
# PROOF_FORGE_TEST_JOBS=4   # default
PROOF_FORGE_TEST_JOBS=2 just test

# Lake module builds already parallelize (no lake -j on Lake 5).
# PROOF_FORGE_GATE_JOBS=1 just run-deletion-gates   # serial deletion gates

# Frontend worker is not on default build / test-fast / dev-check (in-process Loader).
just build-frontend-worker   # only the worker exe
just test-frontend-worker    # worker exe + WorkerV1 shard

# Historical control-plane names are currently NOT registered in justfile:
# just governance-check
# just release-check
# Do not claim governance/release execution until explicit recipes are restored.
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
