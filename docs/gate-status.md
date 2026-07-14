# Gate Completion Records

Status: **Live (refreshed 2026-07-12)**

This page is the authoritative per-gate completion ledger for the tiered
portfolio ([target-roadmap](target-roadmap.md), D-034). Each Gate has one
record listing its acceptance criteria, per-criterion status, evidence, and
sign-off date. A Gate is **closed** only when every criterion is **met**; a
single unmet criterion blocks the next tier. Gate P0 records the
primary-chain completion covenant (D-045), which is stricter than the G0
behavior/budget slice.

Unlike [development-log](development-log.md) (a stream of engineering
milestones), this page records the *phase boundary* decisions: whether the
current phase's Definition of Done is satisfied, with auditable evidence.

## Gate A1 — Portable Intent and NFT vertical slice

**Status: Closed**

**Closed: 2026-07-12**

| # | Criterion | Status | Evidence required |
|---|---|---|---|
| A1-1 | Solana grammar isolated from portable `Source` | ✅ met | `52402821` moves grammar; `c1433b2e` pins portable rejection plus Source.Solana account/PDA/CPI/realloc IR intents; `just solana-light` and `just product` pass |
| A1-2 | Target-neutral Intent materializer registry | ✅ met | private registry construction; `resolveIntentMaterializer`; checked result target; `just intent-registry` in product/check |
| A1-3 | Minimal NFT intent and implementation contracts | ✅ met | `just nft-intent` and `just nft-implementation-contract`; validated portable intent plus three executable audited candidates |
| A1-4 | Strict primary-triad NFT materialization | ✅ met | `just nft-materialization`: strict canonical validation and `buildFromCore` for EVM, Solana, and NEAR; no advisory fallback |
| A1-5 | Product artifacts and lifecycle runtime evidence | ✅ met | `just portable-nft-multi-target` proves three bundles; `just portable-nft-runtime` executes mint, owner/balance, authorized transfer, unauthorized rejection, and duplicate-mint rejection on EVM Foundry, Solana Surfpool/SVM, and NEAR Wasm |
| A1-6 | Aggregate acceptance | ✅ met | `6a6022ea`; `just product`, `just portable-nft-runtime`, `just solana-light`, `just check`, and `git diff --check` pass |

Gate A1 closes only when every row is met on one tested revision. Wasm-host or
ZK research may proceed independently, but public promotion requires its own
strict gate and does not count toward A1.

## Gate A-CUT1e — Direct Solana authoring cutover

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT1e-1 | Public/internal Solana authoring has no Legacy builder dependency | ✅ met | `Source.Solana` emits one `AuthoredContract`; boundary search finds no `Source.Solana.Legacy`, `ContractSpec`, or `IR.Module` dependency in the public/internal modules; `just source-dsl-isolation` passes |
| A-CUT1e-2 | Typed target operations survive strict planning and plan-only lowering | ✅ met | account/PDA/CPI/allocator/realloc payloads decode fail closed; `Tests/Canonical/SolanaHostOpCatalog.lean`, `Tests/SourceDslSolanaAcceptance.lean`, and `Tests/Backend/Solana/SolanaCpiPacking.lean` pass |
| A-CUT1e-3 | Plan-only artifacts preserve SDK and runtime constraints | ✅ met | `Tests/Backend/Solana/SolanaSdkManifest.lean` and `SolanaAccountRealloc.lean` pass; canonical lowering enforces instruction length and signer/writable/owner validation; System, Memo, close-account, and authority Pinocchio structural comparisons pass |
| A-CUT1e-4 | No fallback was introduced | ✅ met | public fixtures expose `.contract` only; public CLI fixture routes call `compileSolanaAuthoredSbpf`/`compileSolanaAuthoredElf`; failures from normalization, planning, lowering, package generation, and sBPF build remain terminal |

## Gate CMP-0 — Native differential contracts and inventory

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-0-1 | The tracked comparison inventory is complete and honest | ✅ met | `18f15e59`; generated `testkit/differential/inventory.v1.json` lists 85 NEAR, Solana, Stylus, EVM, portable-scenario, and CI assets and reports zero semantically verified assets |
| CMP-0-2 | Versioned contracts fail closed | ✅ met | four v1 schemas plus 11 unit tests reject missing provenance, duplicate step IDs, unknown observation dimensions, skipped/error runners, and incomplete coverage claimed as semantic success |
| CMP-0-3 | Current v0 manifests have explicit, non-promoting migration | ✅ met | all 28 NEAR and 7 Solana manifests migrate through schema-specific functions; inferred/missing provenance stays explicit and migrated observations keep `semanticMatch=false` |
| CMP-0-4 | Comparison contracts remain outside production architecture | ✅ met | boundary test scans `ProofForge/**/*.lean` for comparison schema/import leakage; `just differential-contracts` and `git diff --check` pass; migration functions exist only under `scripts/differential` and are deletion work after v1 conversion |

## Gate CMP-1 — Normalized runner result and comparator

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-1-1 | Runner results preserve logical and target-native identity separately | ✅ met | `7fee238c`; typed values plus logical account/actor/clock context compare portable identity while retaining native account IDs, heights, and timestamps in evidence |
| CMP-1-2 | Every required observation dimension fails closed | ✅ met | 12 comparator tests exercise independent mismatches for call status/error, return, state, balances, ordered events, external actions, interface, and resources; missing coverage, skips/errors, and incomplete provenance keep `semanticMatch=false` |
| CMP-1-3 | Target-owned observations are not flattened into false equivalence | ✅ met | cross-target external actions compare logical payload and retain native payload; resource values compare only within one target family and aggregate score fields are rejected |
| CMP-1-4 | The shared comparator remains test-only | ✅ met | runner schema and implementation live under `testkit/differential` and `scripts/differential`; compiler boundary test includes the runner schema ID; `just differential-contracts` passes 23 contract/comparator tests plus inventory and matrix snapshots |

## Gate A-CUT2g — Direct public authoring route

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT2g-1 | Public Source and Loader exchange only `AuthoredContract` | ✅ met | `42183403`; `just public-authored-route` proves Counter exports `contract`, not `spec`/`module`, and Loader rejects the quarantined ValueVault instead of falling back |
| A-CUT2g-2 | Primary-triad materialization avoids `ContractSpec` and `IR.Module` | ✅ met | `just portable-counter-multi-target` builds EVM, Solana assembly, and NEAR/Wasm from the unchanged Product Counter with `contract-source-authored` / `canonical-core-v1` metadata and rejects any ContractSpec sidecar |
| A-CUT2g-3 | Final Solana ELF also uses the direct target plan | ✅ met | target-specific Counter testkit run builds the ELF through `compileSolanaAuthoredElf`; the initialize/get/increment/get lifecycle passes under Mollusk with strict account and instruction-data validation |
| A-CUT2g-4 | Target behavior remains executable | ✅ met | individual Counter testkit runners pass for `evm`, `solana-sbpf-asm`, and `wasm-near`; NEAR offline-host reports `0 -> 1`; EVM selector metadata and target goldens pass |
| A-CUT2g-5 | Legacy is deletion inventory, not compatibility | ✅ met | direct boundary gate rejects Legacy imports in Source/Counter; remaining callers explicitly import `Source.Legacy`, which the public Loader cannot discover; no direct-to-Legacy adapter or fallback exists |

## How to use

- Add a new `## Gate GN` section when a Gate's first criterion starts.
- Update status to ✅ / ❌ / 🟡 (met / unmet / in-progress) as work lands.
- Record evidence as reproducible commands and commit ranges, not prose.
- A Gate closes with a `**Closed: YYYY-MM-DD**` line; until then it stays
  **Open**.

## Gate G0 — Tier-0 exit (current phase goal)

**Definition of Done:** the shared scenario (Counter, then ValueVault) passes
in [testkit](../testkit/) (RFC 0007) on `evm`, `solana-sbpf-asm`, and
`wasm-near` — behavior parity *and* resource budgets (D-040 / RFC 0010).

**Status: Closed**

**Closed: 2026-07-03**

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| G0-1 | Counter behavior parity on 3 targets | ✅ met | `just testkit` → `counter trace parity: ok (3 target(s))` |
| G0-2 | ValueVault behavior parity on 3 targets | ✅ met | Remote CI `28655651561` (`12a007b`) `build-test` → `Run unified testkit` succeeded with Foundry/cast installed |
| G0-3 | Counter resource budgets: `solana_cu`, `evm_gas`, `wasmtime_fuel_cumulative` | ✅ met | `testkit/scenarios/counter.toml` pins all three budgets; offline-host fuel is Wasmtime (not NEAR gas); `CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --trace` |
| G0-4 | ValueVault resource budgets on 3 targets | ✅ met | `testkit/scenarios/value-vault.toml` pins `solana_cu`, `evm_gas`, and `wasmtime_fuel_cumulative` for all 11 calls; `CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --trace` |
| G0-5 | Unsupported-capability diagnostic parity | ✅ met | `just testkit` → `unsupported-crosscall ... diagnostic crosscall.invoke unsupported: ok` |
| G0-6 | `just check` green (build + lint + gates) | ✅ met | `CAST="$PWD/build/tools/cast-shim" just check` passed locally; remote CI `28658576786` (`0c52fb8`) completed successfully, including `Run unified testkit`, `Check Solana light gates`, Foundry smokes, and Anvil deploy smoke |

### Carry-over work after Gate G0

Gate G0 closes the shared behavior/resource-budget slice. It does **not** close
Gate P0. The remaining primary-chain production hardening stays active:

1. ~~EVM semantic-plan migration (Workstream 3: ExprPlan/StmtPlan/
   EntrypointPlan/EventPlan/CrosscallPlan/MetadataPlan).~~ ✅ Landed — see P0-2.
2. ~~Solana Pinocchio live dual-deploy equivalence CI/toolchain hardening and
   broader reference coverage (Workstream 7).~~ ✅ Landed — see P0-1.
3. ~~NEAR/Wasm target-first local execution/deploy metadata sign-off.~~ ✅
   Landed — see P0-3.

### Sign-off

Gate G0 closed on 2026-07-03 at commit `0c52fb8` after GitHub CI run
`28658576786` completed successfully. The closing run validates the current
`just check` CI surface, including the unified testkit, Solana light gates,
EVM Foundry/Anvil gates, and the smoke jobs for the frozen non-primary spikes.

---

## Gate P0 — Primary-chain completion covenant (current product prerequisite)

**Definition of Done:** ProofForge must complete the three priority chains in
implementation order — `solana-sbpf-asm`, `evm` (Ethereum), and `wasm-near`
(NEAR/Wasm) — before any additional chain advances beyond docs-only research or
frozen spike maintenance (D-045).

**Status: Closed**

**Closed: 2026-07-04**

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| P0-1 | Solana direct sBPF P0 artifact/execution gates are complete | ✅ met | Gate G0 behavior/budget parity is closed; Pinocchio reference-equivalence is included in `just solana-light`; the Agave/Solana CLI ELF compatibility blocker was fixed by forwarding target-first `--solana-sbpf-arch v0` into the legacy ELF builder, producing loader-compatible v0 ELFs (`e_flags = 0`, valid section table) from `emit --target solana-sbpf-asm --format elf`; local `just solana-pinocchio-live-equivalence` passes all five Surfpool dual-deploy scenarios (System transfer/create_account, SPL Token transfer/ops/authority) with `5 passed, 0 skipped, 0 failed`; GitHub CI run `28675037861` at commit `3b2719a` completed successfully, including the mandatory `solana-pinocchio-live` job. That job installed Agave/Solana CLI, SBF platform-tools, `sbpf`, Surfpool, Node/npm, built ProofForge, and ran the aggregate live suite without allow-skip. |
| P0-2 | Ethereum/EVM P0 lowering/artifact/runtime gates are complete | ✅ met | EVM semantic-plan migration landed (RFC 0004): `Plan.lean` now defines `ExprPlan`, `StmtPlan`, `EntrypointPlan`, `EventPlan`, `CrosscallPlan`, `MetadataPlan`; `Validate.lean` holds pure validation/type-inference; `Lower.lean` constructs the populated `ModulePlan` (entrypoints, events, crosscalls, creates, checked-arithmetic flag); `Metadata.lean` produces plan-driven artifact/deploy metadata; `IR.lean` is the compatibility facade that builds the full semantic plan before Yul generation. Gates: `just evm-plan`, `just evm-semantic-plan`, `just evm-all` (diagnostics 58 cases, 99 IR coverage entries, 19 IR smokes + Foundry + Anvil deploy), `just check` all green. FV-4 additionally includes decide-checked executable EVM/Yul trace obligations for Counter, ValueVault, EvmExpressionProbe, EvmMapProbe, EvmTypedStorageProbe, EvmStorageStructProbe, and EvmAbiAggregateProbe, covering scalar traces plus map slots, typed storage arrays, storage structs, and aggregate ABI params/returns. FV-2 now has IR aggregate/storage and map lifecycle executable trace slices for arrays, structs, storage paths, aggregate ABI values, and state-threaded map insert/set expressions; post-P0 formal hardening wires the covered EVM map/storage/aggregate IR traces into those obligations through `*_ir_observable_trace_ok` anchors. |
| P0-3 | NEAR/Wasm P0 target-first/offline-host gates are complete | ✅ met | EmitWat/NEAR diagnostics, IR coverage, formal anchors, offline host smoke, and budget baselines are green. Commit `466b320` adds target-first `check`, `emit`, and `build` coverage for `wasm-near`, writes `proof-forge-artifact.json` plus `proof-forge-deploy.json`, validates WAT/optional Wasm hashes, ABI entrypoints, capabilities, fixture/module ids, and local offline-host deployment mode with `scripts/near/validate-emitwat-metadata.py`, and executes the generated Counter WAT through `runtime/offline-host`. Evidence: local `just near-target-first` and `just check`; GitHub CI run `28677055773` at commit `466b320` completed successfully, including `Run Wasm-NEAR target-first smoke`, `Run EmitWat offline host smoke`, `Run unified testkit`, Foundry/Anvil, and the mandatory `solana-pinocchio-live` job. |
| P0-4 | Additional-chain advancement stayed frozen through P0 | ✅ met | D-044/D-045 froze Aptos/CosmWasm advancement past M1/M2 and kept other targets docs-first until P0 closed. After closure, Tier-1 work is eligible for scheduling, but the backlog puts CLI M3/M4 cleanup first. |

### Sign-off

Gate P0 closed on 2026-07-04 at commit `466b320` after GitHub CI run
`28677055773` completed successfully. The closing run adds the missing
NEAR/Wasm target-first local execution/deploy metadata evidence and revalidates
the existing Solana, EVM, frozen-spike, and shared testkit gates.

Gate P0 is a scoped engineering sign-off for the documented scenarios and
fragments. It is not a proof of universal compiler correctness, a `Supported`
registry maturity promotion, or a production deployment/operations sign-off.

---

## Gate G1a — CosmWasm M4 (not started)

**Status: Not started.** Gate P0 is closed, so the D-045 freeze no longer
blocks scheduling. The next implementation step is still controlled by the
backlog: finish the CLI M3/M4 target-first migration before advancing this
spike to M3/M4.

## Gate G1b — Aptos M4 (not started)

**Status: Not started.** Gate P0 is closed, so the D-045 freeze no longer
blocks scheduling. The next implementation step is still controlled by the
backlog: finish the CLI M3/M4 target-first migration before advancing this
spike to M3/M4. (Move targets were removed from main on 2026-07-15.)

## Gate G2 — both Tier-1 exits (not started)

**Status: Not started.** Opens only after G1a *and* G1b close.
