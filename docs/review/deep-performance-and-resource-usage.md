# Gap Analysis: Performance and Resource Usage

**Dimension:** `performance-and-resource-usage`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10
**Branch:** `main` (dirty: `docs/zh/INDEX.zh.md`, `scripts/i18n/manifest.json`, `scripts/near/target-first-smoke.sh`, `docs/review/` untracked)

## Executive summary

ProofForge has a **functional** performance baseline for its user-facing
multi-target compiler: the required `just product` gate runs in ~27 s on a warm
cache, and a nascent ProofForge-vs-native benchmark matrix (B1 wave) records
artifact sizes and chain-native costs.  However, the project is **not yet
performance-regression-proof**.  There are no enforced output-size budgets, no
compile-time tracking, no peak-memory measurement, no CI performance job, and
the cold-build experience is unmeasured.  The generated artifact size data that
does exist already shows PF can be both smaller (NEAR/Wasm Counter: 403 B vs
54 785 B native) and larger (EVM ValueVault: 1 326 B vs 745 B native) than
hand-written baselines, so the absence of systematic gates is a real product
risk.

**Overall maturity score: 4 / 10**

---

## 1. Existing performance/resource data

### 1.1 Benchmark matrix (B1)

The B1 wave is the primary source of performance truth.  It is documented in
`docs/benchmarks.md` and `benchmarks/README.md`, driven by `justfile` recipes,
and emits machine-readable rows under `build/benchmarks/`.

- **Spec + schema:** `docs/benchmarks.md:52-103` defines the
  `proof-forge.benchmark-result.v1` schema.  The JSON schema and a pure-Python
  checker live in `benchmarks/schema/result.schema.json` and
  `scripts/benchmarks/validate-result-schema.py`.
- **Just recipes:** `justfile:1238-1295` expose
  `benchmark-schema`, `benchmark-counter`, `benchmark-value-vault`,
  `benchmark-ownable`, `benchmark-matrix`, and `benchmark-zk-counter`.
- **PF runners:** `scripts/benchmarks/counter-pf-runner.sh`,
  `scripts/benchmarks/value-vault-pf-runner.sh`, and
  `scripts/benchmarks/ownable-pf-runner.sh` build Product examples for the
  primary triad and emit `artifactBytes` plus honest cost notes.
- **Native runners:** `scripts/benchmarks/counter-native-runner.sh` and
  companions build hand-written baselines (`benchmarks/native/`) and record
  native costs such as `evm_gas` via Anvil/cast where tools are present.
- **Rendered table:** `scripts/benchmarks/render-cost-table.py:17-28`
  discovers rows and renders `docs/generated/benchmark-counter.md`.

Current snapshot (`docs/generated/benchmark-counter.md:26-95`, generated
2026-07-10):

| Scenario | Target | PF artifact bytes | Native artifact bytes | PF/native size |
|----------|--------|------------------:|----------------------:|---------------:|
| Counter  | evm    | 180               | 359                   | 0.50× |
| Counter  | solana-sbpf-asm | 1 384      | 0 (cargo-build-sbf failed) | — |
| Counter  | wasm-near | 403            | 54 785                | 0.01× |
| Ownable  | evm    | 293               | 520                   | 0.56× |
| Ownable  | solana-sbpf-asm | 2 744      | 0 (no native corpus)  | — |
| Ownable  | wasm-near | 627            | 160 515               | 0.00× |
| ValueVault | evm  | 1 326             | 745                   | 1.78× |
| ValueVault | solana-sbpf-asm | 5 088     | 0 (no native corpus)  | — |
| ValueVault | wasm-near | 2 053          | 156 142               | 0.01× |

Cost fields are honest but incomplete: EVM gas is only recorded for the native
Anvil path, Solana CU is deferred, and NEAR offline-host reports
`wasmtimeFuelDelta` rather than `near_gas`
(`scripts/near/budget-honesty-smoke.sh:34-40`).

### 1.2 Testkit budget assertions

The unified testkit has per-step budget baselines with tolerances for the
Counter and ValueVault scenarios.

- **Scenario manifests:** `testkit/scenarios/counter.toml:609-639` and
  `testkit/scenarios/value-vault.toml:816-915` declare budgets such as
  `evm_gas = { baseline = 23332, tolerance = 0.10 }` and
  `wasmtime_fuel_cumulative = { baseline = 22, tolerance = 0.05 }`.
- **Core model:** `testkit/core/src/lib.rs:324-365` defines `BudgetExpectation`,
  `BudgetValue` (exact or baseline+tolerance), and `max_allowed()`.
- **Harness reporting:** `testkit/harness-evm/src/lib.rs:818-836`,
  `testkit/harness-solana/src/lib.rs:1328-1356`, and the NEAR harness emit
  `evm_gas`, `solana_cu`, and `wasmtime_fuel_*` into `CallOutcome`.
- **Gate:** `justfile:1313-1317` defines `testkit-budget-gate` for Counter and
  ValueVault.

Only two product scenarios currently carry budget assertions; the broader B1
matrix does not feed back into CI as a regression gate.

### 1.3 Worker resource-limit wrappers

A portable resource-limit runner exists for hosted/CI isolation, but it is an
external wrapper rather than an internal CLI control.

- `scripts/cli/worker-resource-limit.py:130-232` supports `--wall-sec`,
  `--cpu-sec`, and `--mem-bytes`, applying `RLIMIT_CPU`, cgroup v2, or
  `RLIMIT_AS`/`RLIMIT_DATA`.
- `scripts/cli/worker-limits-smoke.sh:60-72` proves a Counter build completes
  under a 120 s wall-clock wrapper.
- `scripts/cli/worker-cgroup-smoke.sh:29-105` proves CPU and memory limits kill
  runaway processes and that a Counter build succeeds under generous limits.
- `justfile:398-404` wires `worker-limits` and `worker-cgroup` into `just check`.

### 1.4 Build/output sizes

Local build caches are large and growing:

| Path | Size |
|------|------|
| `.lake/` | 7.9 GiB |
| `build/` | 1.0 GiB |
| `build/solana/` | 559 MiB |
| `build/evm/` | 1.1 MiB |

A single `just product` run emits ~284 KiB of portable Counter/RemoteCall
artifacts (`build/portable-counter` 116 KiB, `build/portable-remote-call`
168 KiB).  Individual generated runtime artifacts are small (e.g. Counter EVM
runtime 180 B, NEAR Wasm 403 B, Solana ELF 1 384 B), but no budget enforces
those sizes.

### 1.5 CI timing data

There is **no structured CI performance data**.  `.github/workflows/ci.yml`
has no benchmark job, no `upload-artifact` for benchmark JSON, no per-step
timings, and no `timeout-minutes` except for the optional
`solana-pinocchio-live` job (`timeout-minutes: 75`,
`.github/workflows/ci.yml:246`).  `.woodpecker.yml:16-31` runs only
`just product` and `just check` with no timing capture.

---

## 2. Wall-clock cost of primary gates

All measurements below were taken on the current macOS host with a warm
`.lake/` and `build/` cache.  They represent incremental/replay costs, not
cold-build costs.

| Gate | Command | Wall time | Notes |
|------|---------|----------:|-------|
| Lean package build | `lake build` | ~2.6 s | Replayed 654 jobs; cold build is orders of magnitude longer. |
| CLI startup | `lake env proof-forge --list-targets` | ~1.5 s | Includes `lake env` overhead; no `--version` flag exists. |
| Single EVM compile | `proof-forge build --target evm Examples/Product/Counter.lean` | ~2.7 s | Outputs init/runtime bytecode, Yul, ABI, client, SDK JSON, artifact metadata. |
| Product gate | `just product` | ~27 s | Builds catalog check, portable-default, product-matrix, Counter triad, RemoteCall multi-target. |

Evidence:
- `lake build`: measured 2026-07-10, output shows `Build completed successfully (654 jobs)` in ~2.57 s real.
- `lake env proof-forge --list-targets`: lists 10 registered targets in ~1.46 s real.
- `proof-forge build --target evm …`: wrote `Counter.bin` (360 hex chars / 180 B runtime) in ~2.73 s real.
- `just product`: completed `product: ok (catalog · matrix · counter · remote)` in ~27.08 s real.

**Caveat:** cold-build latency (fresh clone, empty `.lake/`) is the metric that
matters most for onboarding and CI, and it was not measured here.  The 7.9 GiB
`.lake/` directory suggests first-time builds can take many minutes and consume
significant disk space.

---

## 3. Missing performance/resource gates

### 3.1 Output-size budgets

The B1 rows record `artifactBytes`, but no gate enforces a maximum or a
regression band.  `docs/benchmarks.md:105-109` proposes a ±15 % tolerance vs
native, yet that tolerance is only aspirational.  Risks:

- EVM ValueVault is already 1.78× larger than the native baseline
  (`docs/generated/benchmark-counter.md:81`).
- Solana ELF sizes grow quickly with account metadata (ValueVault ELF 5 088 B
  vs Counter ELF 1 384 B) with no size model.

### 3.2 Compile-time regression tracking

There is no measurement, budget, or CI gate for:

- `lake build` cold/warm time.
- `just product` latency.
- Per-target codegen latency (e.g. EVM vs Solana vs NEAR for the same source).
- Elaboration time for individual `Examples/Product/*.lean` modules.

Without this, compiler changes that accidentally slow down the product gate
will only be noticed anecdotally.

### 3.3 Memory limits and profiling

- The worker wrapper exists but is not applied to the main `lake build` or
  `just check` paths in CI.
- No peak-RSS measurement is emitted for Lean elaboration or codegen.
- No gate prevents pathological inputs from exhausting memory during
  elaboration.

### 3.4 Generated-code bloat detection

There is no structural check that relates generated artifact size to source
complexity.  For example:

- NEAR/Wasm PF outputs are tiny because the offline-host ABI is lean, but this
  is not automatically validated against a complexity metric.
- EVM Yul output could bloat due to redundant dispatcher code; only golden-file
  diffing (`testkit/scenarios/counter.toml:391-392`) catches changes, not bloat.

### 3.5 CI performance artifacts

- No `upload-artifact` for `build/benchmarks/` JSON.
- No JUnit/TAP or structured timing report.
- No nightly or on-demand benchmark job.
- Failure diagnosis requires local re-runs.

### 3.6 Cross-target cost regression harness

Only Counter and ValueVault have testkit budget baselines.  The full B1 matrix
(Counter, ValueVault, Ownable, optional ZK) is not wired into a single
regression command that fails CI on cost/size drift.

---

## 4. Recommendations: minimal performance dashboard / regression harness

### 4.1 Extend the benchmark schema

Add `compileTimeSec`, `peakMemoryMb`, and `toolchain` fields to
`proof-forge.benchmark-result.v1` (`benchmarks/schema/result.schema.json`).
Emit these from `scripts/benchmarks/*-pf-runner.sh` using `/usr/bin/time -l`
or cgroup metrics.

### 4.2 Pin and enforce baselines

Create `benchmarks/baselines/<scenario>.json` (or TOML) with:

```json
{
  "scenario": "bm-counter",
  "target": "evm",
  "maxArtifactBytes": 250,
  "maxCompileTimeSec": 5.0,
  "costs": { "evm_gas": { "baseline": 23332, "tolerance": 0.10 } }
}
```

Add `just benchmark-regression-gate` that compares current
`build/benchmarks/bm-*.json` against the baseline and fails on drift.

### 4.3 Add compile-time gates

- Run `time lake build` and `time just product` in CI on every PR, publishing
  the numbers as a PR comment or artifact.
- Set SLOs: e.g. warm `just product` < 60 s, cold `lake build` < 10 min.
- Add per-target build time to each B1 row.

### 4.4 Add memory gating

- Apply `scripts/cli/worker-resource-limit.py` to long-running CI steps
  (`just check`, `just testkit`, `just benchmark-matrix`) with a generous but
  bounded memory limit.
- Capture peak RSS for the `proof-forge build` invocation and fail if it
  exceeds a per-scenario limit.

### 4.5 CI performance job

Add an optional but tracked `performance` job to `.github/workflows/ci.yml`
that:

1. Runs `just benchmark-matrix`.
2. Uploads `build/benchmarks/` and `docs/generated/benchmark-counter.md` as
   artifacts.
3. Runs `just benchmark-regression-gate` against pinned baselines.
4. Publishes a markdown summary to the PR.

### 4.6 Honest dashboard

A minimal dashboard can be a markdown file regenerated by CI:

- Source: `build/benchmarks/history/<timestamp>_*.json`.
- Render: extend `scripts/benchmarks/render-cost-table.py` to show trend
  arrows (↑/↓) for artifact size and compile time.
- Host: commit the latest snapshot to `docs/generated/` or attach it to each
  release.

Continue to clearly separate offline fuel from on-chain gas and label ZK
metrics as experimental, per `docs/benchmarks.md:16-21`.

---

## Top 5 gaps

| # | Gap | Severity | Evidence |
|---|-----|----------|----------|
| 1 | **No output-size regression gate** — `artifactBytes` are recorded but no CI step fails on size drift. | High | `docs/benchmarks.md:105-109` (±15 % tolerance aspirational); `docs/generated/benchmark-counter.md:81` (ValueVault EVM 1.78× native). |
| 2 | **No compile-time regression tracking** — cold/warm build times are not measured or budgeted. | High | Measured warm `just product` ~27 s; no cold-build measurement; no timing artifacts in `.github/workflows/ci.yml`. |
| 3 | **No peak-memory measurement** — `.lake/` is 7.9 GiB but RSS during build is unknown. | Medium | `scripts/cli/worker-resource-limit.py` exists but is not applied to main CI path; no RSS logs. |
| 4 | **No CI performance job or artifacts** — benchmark JSON is not uploaded; no nightly run. | Medium | `.github/workflows/ci.yml` has no `performance` job and no `upload-artifact` for `build/benchmarks/`. |
| 5 | **Limited budget coverage** — only Counter and ValueVault have testkit budget baselines. | Medium | `testkit/scenarios/counter.toml:609-639`, `value-vault.toml:816-915`; Ownable and ZK rows lack budgets. |

---

## Evidence index

- `justfile:8` — `build` recipe.
- `justfile:1149` — `product` recipe.
- `justfile:1238-1295` — benchmark matrix recipes.
- `justfile:1313-1317` — `testkit-budget-gate`.
- `justfile:398-404` — `worker-limits` / `worker-cgroup`.
- `docs/benchmarks.md` — benchmark matrix specification.
- `benchmarks/README.md` — B1 status and commands.
- `benchmarks/schema/result.schema.json` — result schema.
- `scripts/benchmarks/counter-pf-runner.sh` — PF Counter benchmark runner.
- `scripts/benchmarks/counter-native-runner.sh` — native Counter benchmark runner.
- `scripts/benchmarks/render-cost-table.py:17-28` — table renderer.
- `scripts/benchmarks/behavior-gate.py` — PF vs native behavior parity gate.
- `scripts/cli/worker-resource-limit.py` — resource-limit wrapper.
- `scripts/cli/worker-limits-smoke.sh` — wall-clock smoke.
- `scripts/cli/worker-cgroup-smoke.sh` — CPU/memory smoke.
- `scripts/near/budget-honesty-smoke.sh:34-40` — honest fuel labeling.
- `testkit/core/src/lib.rs:324-365` — budget expectation model.
- `testkit/scenarios/counter.toml:609-639` — Counter budget baselines.
- `testkit/scenarios/value-vault.toml:816-915` — ValueVault budget baselines.
- `docs/generated/benchmark-counter.md` — latest rendered matrix with sizes.
- `.github/workflows/ci.yml:246` — only `solana-pinocchio-live` has a timeout.
