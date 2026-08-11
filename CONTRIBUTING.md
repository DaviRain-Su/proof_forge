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
| NEAR/CW/TON/Noir/Psy/Quint (fast) | `just test-shard targets-host-fast` | `target-smoke` |
| CosmWasmPlan + NoirAcir (slow) | `just test-shard targets-host-slow` | `target-host-slow` (main only) |
| All ordinary target suites | `just test-targets` (3-way parallel, host-fast) | `target-smoke` |
| Full host incl. slow | `PROOF_FORGE_TARGET_HOST_SLOW=1 just test-targets` | main + local |
| Solana Mollusk / CPI runtime | `just solana-runtime` (slow) | `solana-runtime` |
| Full ordinary-host gate | `just ci` (slow; last resort) | all heavy jobs |

```bash
just docs-check         # docs control plane only (~seconds)
just test-fast          # core product tests only (daily feedback)
just dev-check          # docs + build + test-fast + light gates
just test-shard targets-evm        # also: targets-solana | targets-host-fast | targets-host-slow
just test-targets                  # evm + solana-lean + host-fast (parallel; CI default)
PROOF_FORGE_TARGET_HOST_SLOW=1 just test-targets   # + CosmWasmPlan/NoirAcir
just test-nontarget                # nine non-target shards (CI lean-product half)
just solana-runtime                # Mollusk (reuses PROOF_FORGE_CLI if set)
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
| `target-smoke` | 3 parallel shards (evm/solana/host-**fast**) + CLI | ~10–15 min |
| `target-host-slow` | CosmWasmPlan + NoirAcir | ~10–15 min (**main/dispatch only**) |
| `solana-runtime` | Mollusk; reuses CLI artifact when available | ~12–20 min (was ~28 with lake) |

Jobs run **in parallel** where independent; `solana-runtime` waits on
lean-product/target-smoke only to download the CLI artifact (skips a third
full monorepo lake build when possible). Path filter skips heavy jobs on
docs/MCP/template-only PRs. **Pushes to `main` always run heavy lanes**
(including host-slow). A green hosted CI does **not** mean hermetic/formal
release evidence.

Target shards: `targets-evm` · `targets-solana` · `targets-host-fast` ·
`targets-host-slow` (see `Tests/Shards/Targets*.lean`).

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
