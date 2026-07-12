# Parallel Test Framework Design

Date: 2026-07-12
Status: accepted
Program: ProofForge test infrastructure

## 1. Problem

`just product` and `just check` currently execute large dependency lists mostly
in sequence. A full local check repeatedly rebuilds or re-emits overlapping
artifacts, while CI repeats product and canonical work in later jobs. Running the
existing recipes with unrestricted `just --jobs` is unsafe because several
smokes share output directories, fixed ports, generated fixtures, or destructive
rebuild sandboxes.

The framework must shorten local feedback and CI wall time without weakening the
current product-first policy or introducing nondeterministic test failures.

## 2. Goals

- Provide a 2-5 minute local feedback path for ordinary changes.
- Provide a conflict-aware parallel equivalent of the current full `just check`.
- Limit automatic concurrency to `min(detected CPUs, 4)` by default.
- Allow an explicit `JOBS` override for controlled benchmarking and CI tuning.
- Split CI into independently visible lanes with reusable dependency caches.
- Preserve the existing required product gate and all current check coverage.
- Record lane and recipe durations so future balancing is evidence-based.

## 3. Non-Goals

- Do not add live-network, Surfpool, SBF platform-tool, Dargo, Sui, or Leo gates
  to the default local baseline.
- Do not make individual tests internally concurrent unless they already own
  isolated state.
- Do not change target maturity, compiler behavior, or test assertions.
- Do not delete the serial baseline until parallel equivalence is demonstrated.

## 4. User-Facing Commands

### `just check-fast`

The default inner-loop gate. It runs:

- the Lean build;
- product catalog and portable-source isolation;
- canonical foundation and strict target gates;
- target-specific focused gates selected from changed paths;
- documentation and translation checks when documentation inputs changed.

When change detection is unavailable or ambiguous, it falls back to a fixed
safe fast baseline rather than silently skipping validation.

### `just check-parallel`

The full local gate. It runs all required `just check` coverage through isolated
lanes, with at most four lanes active. A failure terminates the coordinator,
prints the failing lane log, and returns nonzero.

### `just check`

During rollout, this remains the serial reference. After three clean equivalence
runs and the performance acceptance is met, it becomes an alias for
`check-parallel`; `check-serial` then preserves the old behavior for debugging.

### Configuration

- Default jobs: `min(detected CPUs, 4)`.
- Override: `JOBS=<positive integer> just check-parallel`.
- Invalid, zero, or negative `JOBS` values fail before starting tests.
- `CHECK_BASE=<git revision>` optionally controls affected-path selection.

## 5. Lane Model

The scheduler owns a checked-in lane manifest. Each recipe appears exactly once
in the full coverage set, except explicitly shared prerequisites such as `build`.

| Lane | Scope | Isolation |
|---|---|---|
| `core-product` | build, product, canonical foundation, registries, schemas, docs | canonical/product output roots |
| `evm` | EVM plan, semantics, Yul/bytecode, Foundry and upgrade-policy smokes | lane-specific Anvil port and output root |
| `solana` | Solana light, SDK, assembly, interpreter, Pinocchio equivalence | lane-specific Solana output root |
| `wasm-other-exclusive` | NEAR/Wasm, testkit, Psy, Aleo, Quint, reproducibility and worker-limit gates | serial subgroups for shared or destructive resources |

Lane contents are balanced using measured durations, not only backend labels.
The initial grouping may move long independent recipes between lanes as long as
ownership and isolation requirements remain explicit.

## 6. Isolation Rules

Every manifest entry declares one execution class:

- `isolated`: safe to run with any other isolated recipe.
- `lane_serial`: safe across lanes but ordered within its lane.
- `exclusive`: must run alone because it uses shared state or destructive
  rebuild behavior.

Initial exclusive candidates include `rebuild-hash`, worker limit/cgroup tests,
shared testkit output, and recipes that start fixed-port local services. Before a
recipe moves out of exclusive mode, it must accept a lane-specific output root
and dynamically allocated port where relevant.

The coordinator creates `build/test-lanes/<run-id>/<lane>/` for logs and exported
temporary paths. It must not delete the repository-wide `.lake` cache.

## 7. Scheduler

A portable shell or Python coordinator will:

1. validate the manifest and coverage set;
2. detect the job limit;
3. create a unique run directory;
4. launch ready lanes up to the job limit;
5. stream short status lines while writing complete per-lane logs;
6. terminate remaining process groups on the first failure;
7. print lane durations and the slowest recipes;
8. return success only when every selected entry succeeds.

Python is preferred for process-group cleanup, structured manifests, duration
reporting, and macOS/Linux portability. The scheduler must not parse `justfile`
with ad hoc regular expressions; the checked-in manifest is authoritative and a
validation script compares it with the declared serial coverage list.

## 8. Affected Test Selection

`check-fast` maps changed paths to conservative tags:

- `ProofForge/IR`, `Frontend`, `Contract`, or shared target code: core plus all
  primary-target planning gates.
- `Backend/Evm`, `scripts/evm`, EVM fixtures: core plus EVM.
- `Backend/Solana`, `Solana`, `scripts/solana`: core plus Solana light.
- `Backend/WasmHost`, `Compiler/Wasm`, `scripts/near`: core plus Wasm/NEAR.
- `docs`, README, or translation manifest: documentation gates.
- `justfile`, CI, scheduler, manifest, or unknown paths: fixed fast baseline
  plus scheduler self-tests.

Selection is an optimization only. It cannot replace the full pre-push or CI
gate.

## 9. CI Design

GitHub Actions retains the required `product` job. After it passes, a matrix job
runs the four full lanes in parallel. A final `check-summary` job requires every
lane and validates the coverage manifest.

CI caches use lockfile/toolchain-keyed entries for:

- `.lake` packages and build cache;
- Cargo registry/git cache and `target` where safe;
- npm download cache.

Generated contract artifacts are not restored across unrelated commits unless
their cache key includes the source revision and toolchain versions.

Woodpecker adopts the same lane commands. If its runner cannot execute steps in
parallel, the coordinator still provides process-level parallelism within one
step, capped at four jobs.

## 10. Failure Reporting

The console shows lane start, completion, duration, and failure summary. Full
logs remain under the run directory. CI uploads failed lane logs and the timing
report as artifacts. A failure message includes the exact standalone `just`
command needed to reproduce the failing recipe.

Interrupted runs terminate child process groups and local services. Cleanup
errors are reported but do not replace the original test failure.

## 11. Coverage and Correctness Gates

- A manifest validator rejects missing, duplicate, or unknown recipes.
- Scheduler unit tests cover job detection, invalid overrides, failure
  propagation, cancellation, exclusive ordering, and duration output.
- A dry-run mode prints the execution graph without running tests.
- Parallel and serial coverage lists must be identical before default cutover.
- Three consecutive full `check-parallel` runs must pass on a clean checkout.
- At least one run must use `JOBS=1` to prove scheduler semantics do not depend
  on concurrency.

## 12. Performance Acceptance

Measure warm-cache wall time on the same machine and commit:

- local `check-parallel` improves over `check-serial` by at least 35%;
- CI full-gate critical path improves by at least 30%;
- `check-fast` completes in 2-5 minutes for representative single-backend and
  documentation changes;
- no lane exceeds 1.5 times the median lane duration without a documented
  exclusive-resource reason.

Timing reports record CPU count, effective job limit, toolchain versions, commit,
lane durations, and total wall time.

## 13. Rollout

1. Add manifest, validator, scheduler self-tests, and timing reports.
2. Add `check-fast`, `check-parallel`, and `check-serial` without changing CI.
3. Isolate shared output roots and ports exposed by repeated parallel runs.
4. Run serial/parallel coverage equivalence and three stability repetitions.
5. Split GitHub and Woodpecker lanes and add caches.
6. Measure acceptance thresholds.
7. Switch `check` to the parallel implementation only after all thresholds pass.

Rollback is immediate: CI and developers can invoke `just check-serial`, and the
existing recipe coverage remains checked in until the parallel path is stable.
