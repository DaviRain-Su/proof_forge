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

## Local gates (what to run — do **not** default to `just ci`)

Hosted CI wall-clock is ~30 minutes with three heavy Lean jobs. Locally, match
the change to the smallest command. **Prefer `test-fast` / `test-shard` /
`docs-check` over `just ci`.**

| You changed… | Run locally (typical) | Hosted CI lanes |
|---|---|---|
| `docs/**`, `*.md`, product markdown | `just docs-check` && `git diff --check` | `docs` only (heavy jobs skipped on PR) |
| One Lean test area | `just test-shard core` (or `typed` / `language*` / `targets` / …) | path filter → relevant heavy jobs |
| Daily product smoke | `just test-fast` or `just dev-check` | full on `main` push |
| EVM materialize / CLI pins | `just test-shard targets-evm` | `target-smoke` |
| Solana Lean plan/CPI (no Mollusk) | `just test-shard targets-solana` | `target-smoke` |
| NEAR/CW/TON/Noir/Psy/Quint | `just test-shard targets-host` | `target-smoke` |
| All target materialize suites | `just test-targets` (3-way parallel) | `target-smoke` |
| Solana Mollusk / CPI runtime | `just solana-runtime` (slow) | `solana-runtime` |
| Full ordinary-host gate | `just ci` (slow; last resort) | all heavy jobs |

```bash
just docs-check         # docs control plane only (~seconds)
just test-fast          # core product tests only (daily feedback)
just dev-check          # docs + build + test-fast + light gates
just test-shard targets-evm     # focused: also targets-solana | targets-host | targets
just test-targets       # three target processes in parallel (CI default)
just test-nontarget     # nine non-target shards (CI lean-product half)
just solana-runtime     # Mollusk differential (heavy; needs tool root + Rust)
just test               # all shards, bounded parallel (still long)
just ci                 # full product tests — avoid for routine local loops

# Parallelism for shard *execution* (not lake build):
# PROOF_FORGE_TEST_JOBS=1   # serial (low-memory)
# PROOF_FORGE_TEST_JOBS=4   # default
PROOF_FORGE_TEST_JOBS=6 just test-nontarget

# Frontend worker is not on default build / test-fast / dev-check (in-process Loader).
just build-frontend-worker
just test-frontend-worker

# Historical control-plane names are currently NOT registered in justfile:
# just governance-check
# just release-check
```

### Hosted CI map (`.github/workflows/ci.yml`)

| Job | What | Approx. wall (warm cache) |
|---|---|---|
| `docs` | `just docs-check` + whitespace | ~10s |
| `lean-product` | nine non-target shards + `ci-lean-gates` | ~25–30 min |
| `target-smoke` | 3 parallel target shards + CLI smoke | ~12–18 min (was ~25–30 serial) |
| `solana-runtime` | `lake build` CLI + Mollusk | ~25–30 min |

Jobs run **in parallel**; total wall ≈ slowest job. Path filter
(`scripts/ci/detect_ci_paths.sh`) skips heavy jobs on docs/MCP/template-only
PRs. **Pushes to `main` always run all heavy jobs.** `workflow_dispatch` also
forces all lanes. A green hosted CI does **not** mean hermetic or formal
release evidence.

Target shards: `targets-evm` · `targets-solana` · `targets-host` (see
`Tests/Shards/Targets*.lean`). Aggregate `test-shard targets` still exists for
one-process debugging.

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
