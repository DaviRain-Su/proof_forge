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
| CMP-0-1 | The tracked comparison inventory is complete and honest | ✅ met | `6273dfe2`; generated `testkit/differential/inventory.v1.json` lists 85 NEAR, Solana, Stylus, EVM, portable-scenario, and CI assets and reports zero semantically verified assets |
| CMP-0-2 | Versioned contracts fail closed | ✅ met | four v1 schemas plus 11 unit tests reject missing provenance, duplicate step IDs, unknown observation dimensions, skipped/error runners, and incomplete coverage claimed as semantic success |
| CMP-0-3 | Current v0 manifests have explicit, non-promoting migration | ✅ met | all 28 NEAR and 7 Solana manifests migrate through schema-specific functions; inferred/missing provenance stays explicit and migrated observations keep `semanticMatch=false` |
| CMP-0-4 | Comparison contracts remain outside production architecture | ✅ met | boundary test scans `ProofForge/**/*.lean` for comparison schema/import leakage; `just differential-contracts` and `git diff --check` pass; migration functions exist only under `scripts/differential` and are deletion work after v1 conversion |

## Gate CMP-1 — Normalized runner result and comparator

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-1-1 | Runner results preserve logical and target-native identity separately | ✅ met | `25ef8eb3`; typed values plus logical account/actor/clock context compare portable identity while retaining native account IDs, heights, and timestamps in evidence |
| CMP-1-2 | Every required observation dimension fails closed | ✅ met | 12 comparator tests exercise independent mismatches for call status/error, return, state, balances, ordered events, external actions, interface, and resources; missing coverage, skips/errors, and incomplete provenance keep `semanticMatch=false` |
| CMP-1-3 | Target-owned observations are not flattened into false equivalence | ✅ met | cross-target external actions compare logical payload and retain native payload; resource values compare only within one target family and aggregate score fields are rejected |
| CMP-1-4 | The shared comparator remains test-only | ✅ met | runner schema and implementation live under `testkit/differential` and `scripts/differential`; compiler boundary test includes the runner schema ID; `just differential-contracts` passes 23 contract/comparator tests plus inventory and matrix snapshots |

## Gate A-CUT2g — Direct public authoring route

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT2g-1 | Public Source and Loader exchange only `AuthoredContract` | ✅ met | `just public-authored-route` proves Counter and ValueVault export `contract`, not `spec`/`module`; internal Surface fixtures retain a distinct loader identity and no Legacy fallback exists |
| A-CUT2g-2 | Primary-triad materialization avoids `ContractSpec` and `IR.Module` | ✅ met | `just portable-counter-multi-target` builds EVM, Solana assembly, and NEAR/Wasm from the unchanged Product Counter with `contract-source-authored` / `canonical-core-v1` metadata and rejects any ContractSpec sidecar |
| A-CUT2g-3 | Final Solana ELF also uses the direct target plan | ✅ met | target-specific Counter testkit run builds the ELF through `compileSolanaAuthoredElf`; the initialize/get/increment/get lifecycle passes under Mollusk with strict account and instruction-data validation |
| A-CUT2g-4 | Target behavior remains executable | ✅ met | individual Counter testkit runners pass for `evm`, `solana-sbpf-asm`, and `wasm-near`; NEAR offline-host reports `0 -> 1`; EVM selector metadata and target goldens pass |
| A-CUT2g-5 | Legacy is deletion inventory, not compatibility | ✅ met | direct boundary gate rejects Legacy imports in Source/Counter; remaining callers explicitly import `Source.Legacy`, which the public Loader cannot discover; no direct-to-Legacy adapter or fallback exists |

## Gate A-CUT2h — Counter reverse-dependency removal

Status: **closed at `fbc69309`**.

| Criterion | Requirement | Status | Evidence |
|---|---|---|---|
| A-CUT2h-1 | No retired Product Counter `.spec`/`.module` alias remains | ✅ met | `just counter-authoring-cutover` scans production, tests, examples, scripts, and `justfile`; formal/Quint consumers now use Authored/checked Core or explicitly named v1 fixtures |
| A-CUT2h-2 | Obsolete backend wrappers are deleted | ✅ met | EVM `Contracts/Counter.lean` plus its duplicate golden and Solana `Counter.lean` are absent; topology and EVM example gates pass |
| A-CUT2h-3 | EVM constructor ABI remains target-owned | ✅ met | `evmConstructor : ConstructorConfigPlan` is loaded only after EVM selection; `buildFromCore` rejects shared Canonical constructor payloads and validates parameter/storage binding references |
| A-CUT2h-4 | Direct runtime behavior survives | ✅ met | `just evm-anvil-deploy` records `creationMode: deploy-object`, reads initial `123`, then observes `0`, `1`, and `2`; `just portable-counter-multi-target` passes without a ContractSpec sidecar |
| A-CUT2h-5 | No compatibility route was added | ✅ met | public `build`, Yul, and `check` consume Authored -> checked Core -> EVM plan; the direct EVM check passes and invalid shared/target constructor configurations fail closed |

## Gate A-CUT3a - ValueVault direct authoring cutover

Status: **closed with primary-triad native differential evidence; catalog migration remains active**.

| Criterion | Requirement | Status | Evidence |
|---|---|---|---|
| A-CUT3a-1 | Product ValueVault has one current authoring identity | ✅ met | `just value-vault-authoring-cutover` proves the module exports only `contract`; no `.spec`, `.module`, or `Source.Legacy` product path remains |
| A-CUT3a-2 | Portable state, events, and context enter checked Core directly | ✅ met | explicit typed event schemas, named arguments, and `blockNumber` normalize to 6 states, 7 functions, and 5 events equal to the internal Core baseline |
| A-CUT3a-3 | Primary targets consume target-owned plans | ✅ met | focused EVM, Solana, and NEAR CLI builds each report `contract-source-authored` / `canonical-core-v1`; Solana package checks retain events and Clock materialization |
| A-CUT3a-4 | Old reverse aliases are removed rather than adapted | ✅ met | production and tests contain no `ProofForge.Contract.Examples.ValueVault.spec/module` or `Examples.Product.ValueVault.module`; historical v1 proofs name `ProofForge.IR.Examples.ValueVault` explicitly |

## Gate CMP-2 — Primary-triad native Counter differential

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-2-1 | One direct ProofForge business source reaches all three targets | ✅ met | `bec50074`; `Examples/Product/Counter.lean` builds with `contract-source-authored` / `canonical-core-v1` metadata for EVM, Solana, and NEAR; the focused runner rejects ContractSpec sidecars |
| CMP-2-2 | Independent native references have complete provenance | ✅ met | Solidity, Pinocchio Rust, and near-sdk Rust v1 manifests pin exact source SHA-256, Apache-2.0, and toolchain versions; stale source digests fail `just differential-contracts` and the runtime gate |
| CMP-2-3 | Native and ProofForge artifacts execute on target VMs | ✅ met | Anvil executes both EVM artifacts, Mollusk executes both sBPF ELFs, and `near-vm-runner` executes both Wasm artifacts on upstream NEAR VM logic |
| CMP-2-4 | Required semantics fail closed | ✅ met | each target reports all eight dimensions covered, `semanticMatch=true`, and zero unallowed mismatches; exact target-local gas/CU differences remain visible as allowed resource evidence |
| CMP-2-5 | The comparison is not a compiler compatibility route | ✅ met | schemas, manifests, runner, and reports live under `testkit/`, `scripts/`, `benchmarks/`, and ignored `build/`; the compiler import-boundary test remains green |

## Gate CMP-3a - Primary-triad native ValueVault differential

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3a-1 | The direct ValueVault Product source is the only ProofForge business input | ✅ met | `just differential-value-vault` builds `Examples/Product/ValueVault.lean` with `contract-source-authored` / `canonical-core-v1` metadata and rejects any ContractSpec sidecar |
| CMP-3a-2 | Independent references have complete pinned provenance | ✅ met | Solidity, Pinocchio Rust, and near-sdk Rust v1 manifests pin exact source SHA-256, Apache-2.0, and compiler/framework toolchains |
| CMP-3a-3 | Both implementations execute the same stateful and negative lifecycle | ✅ met | Anvil, Mollusk, and upstream `near-vm-runner` execute all 13 steps, including checked underflow rejection and post-failure state preservation |
| CMP-3a-4 | All required observations fail closed | ✅ met | EVM, Solana, and NEAR each cover status, return, state, balances, events, external actions, interface, and target-local resources with `semanticMatch=true` |
| CMP-3a-5 | ABI normalization does not create a compiler compatibility path | ✅ met | the test-only runner invokes native Solidity `uint64` and ProofForge EVM `uint256` signatures separately, then normalizes both to portable `u64`; no compiler adapter, fallback, or dual-write route was added |

## Gate A-CUT3b1 - Direct authorization authoring primitives

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT3b1-1 | Caller identity remains target-neutral before target selection | ✅ met | `just authored-authorization` proves public `caller` normalizes to Canonical Core `contextRead.sender` |
| A-CUT3b1-2 | Authorization checks are direct Core operations | ✅ met | public `requireEq` / `requireNe` statements normalize to typed Core comparisons and assertions; unsupported direct actions fail with a no-Legacy-fallback diagnostic |
| A-CUT3b1-3 | Primary target plans consume the same checked contract | ✅ met | focused EVM, Solana, and NEAR `buildFromCore` calls all pass for the same Authored authorization probe |

## Gate A-CUT3b2 - Product Ownable direct cutover

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT3b2-1 | Product Ownable has one current source identity | ✅ met | `just ownable-authoring-cutover` requires `contract : AuthoredContract`, rejects Product `.spec`/`.module`, `Source.Legacy`, the stdlib facade, its allowlist entry, and the obsolete EVM wrapper |
| A-CUT3b2-2 | Authorization reaches checked Core and target-owned plans | ✅ met | the focused Lean gate observes sender context, equality/inequality assertions, EVM caller/revert behavior, Solana signer authority, and final NEAR plan-to-Wasm lowering from the same checked contract |
| A-CUT3b2-3 | Every primary target emits only Canonical artifacts | ✅ met | focused EVM bytecode/Yul, Solana assembly/package, and NEAR WAT/Wasm builds report `contract-source-authored` / `canonical-core-v1` and emit no ContractSpec/v1 sidecar |
| A-CUT3b2-4 | NEAR address representation remains target-owned | ✅ met | Wasm-host parameter, scalar storage, event, and return lowering materializes portable address values as the target's i64 carrier; final `wat2wasm` validation passes |
| A-CUT3b2-5 | EVM plan metadata retains the shared artifact schema | ✅ met | the plan-only event writer emits `topics` and `dataWords`; metadata validation checks the standard `transferOwnership(address)` selector `f2fde38b` and the 160-bit address layout |

## Gate A-CUT3c1 - Product Pausable direct cutover

**Status: Closed**

**Closed: 2026-07-14 at `7256db23`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT3c1-1 | Product Pausable has one current source identity | ✅ met | `just pausable-authoring-cutover` requires one `contract : AuthoredContract` and rejects Product `.spec`/`.module`, `Source.Legacy`, stdlib-facade references, and compatibility allowlist entries |
| A-CUT3c1-2 | Retired implementations are deleted instead of adapted | ✅ met | `ProofForge/Contract/Stdlib/Pausable.lean` and the EVM wrapper are absent; all former Product callers use `.contract` or the dedicated checked-Core gate, and topology no longer requires the wrapper |
| A-CUT3c1-3 | The state machine reaches checked Core and target-owned plans | ✅ met | one checked contract preserves equality and inequality guards plus state stores through EVM, Solana, NEAR, and the shared Soroban Wasm-host plan |
| A-CUT3c1-4 | Public primary-target artifacts are Canonical-only | ✅ met | target-first EVM bytecode/Yul, Solana assembly/package, and NEAR WAT/Wasm report `contract-source-authored` / `canonical-core-v1`, emit no retired sidecars, and pass selector/metadata validation |
| A-CUT3c1-5 | New architecture semantics are retained | ✅ met | the EVM golden is regenerated from direct Core and keeps its stricter packed-u64 width checks; EVM, Solana, and Wasm outputs preserve both pause-state assertions without a fallback renderer |

## Gate A-CUT3c2 - Product ReentrancyGuard direct cutover

**Status: Closed**

**Closed: 2026-07-14 at `419405e5`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT3c2-1 | Product ReentrancyGuard has one current source identity | ✅ met | `just reentrancy-guard-authoring-cutover` requires one `contract : AuthoredContract` and rejects Product `.spec`/`.module`, `Source.Legacy`, stdlib-facade references, and compatibility allowlist entries |
| A-CUT3c2-2 | Retired implementations are deleted instead of adapted | ✅ met | `ProofForge/Contract/Stdlib/ReentrancyGuard.lean` and the obsolete EVM wrapper are absent; all Product callers use `.contract` or the dedicated checked-Core gate, and topology no longer requires the wrapper |
| A-CUT3c2-3 | Both lock guards reach checked Core and target-owned plans | ✅ met | one checked contract preserves acquire equality, release inequality, and both state stores through EVM, Solana, NEAR, and the shared Soroban Wasm-host plan |
| A-CUT3c2-4 | Public primary-target artifacts are Canonical-only | ✅ met | target-first EVM bytecode/Yul, Solana assembly/package, and NEAR WAT/Wasm report `contract-source-authored` / `canonical-core-v1`, emit no retired sidecars, and pass selector/metadata validation |
| A-CUT3c2-5 | New architecture semantics are retained | ✅ met | the direct Core EVM golden keeps packed-u64 write bounds and adds the guarded release required by the final Product policy; no renderer fallback reproduces the weaker Legacy release |

## Gate A-CUT3d1 - Product ArrayExample direct cutover

**Status: Closed**

**Closed: 2026-07-14 at `ccb9221a`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT3d1-1 | Product ArrayExample has one current source identity | ✅ met | `just array-example-authoring-cutover` requires one direct `contract : AuthoredContract` and rejects Product `.spec`/`.module`, `Source.Legacy`, compatibility allowlist entries, and restored duplicate sources |
| A-CUT3d1-2 | Retired implementations are deleted instead of adapted | ✅ met | the EVM ContractSpec wrapper and temporary Surface fixture/test are absent; Product callers use `.contract`, and topology no longer requires either source |
| A-CUT3d1-3 | Fixed-array intent stays target-neutral through checked Core | ✅ met | direct Source normalizes the three literals to exactly three `memoryAlloc`, nine `memoryStore`, and five `memoryLoad` operations without embedding an EVM, Solana, or NEAR layout |
| A-CUT3d1-4 | Primary targets own concrete memory materialization | ✅ met | EVM emits Yul helpers and bounds checks, Solana emits `sol_alloc_free_` plus typed sBPF loads/stores, and NEAR emits Wasm linear-memory allocation and bounds traps from target-owned plans |
| A-CUT3d1-5 | Public artifacts are Canonical-only and executable | ✅ met | primary artifacts report `contract-source-authored` / `canonical-core-v1`, EVM Yul compiles, Solana package metadata passes, and the NEAR offline host returns 3, 20, and 60 with no retired sidecars |

## Gate A-CUT3e1 - Direct portable map authoring

**Status: Closed**

**Closed: 2026-07-15 at `9f4bd403`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT3e1-1 | Public map authoring constructs only the current frontend | ✅ met | `mapping`, `mapRead`, and `mapWrite` lower directly to `Frontend.Authored`; the implementation does not import ContractSpec, v1 IR, or `Source.Legacy` |
| A-CUT3e1-2 | Map semantics remain target-neutral in checked Core | ✅ met | `just authored-map` observes one `.map .u64 .u64 (some 256)` state plus map-key storage load/store operations; no target layout enters the Product source or Core shape |
| A-CUT3e1-3 | Primary target plans preserve the same checked contract | ✅ met | focused EVM, Solana, and NEAR `buildFromCore` calls all accept the same normalized map probe; Solana receives the portable finite bound rather than a target-specific frontend default |

## Gate A-CUT3e2 - Product StatusMessage direct cutover

**Status: Closed**

**Closed: 2026-07-15 at `2ea8b134`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| A-CUT3e2-1 | Product StatusMessage has one current source identity | ✅ met | `just status-message-authoring-cutover` requires the sole Product source to export `contract : AuthoredContract` and rejects `.spec`/`.module`, `Source.Legacy`, compatibility allowlist entries, and restored duplicate Surface sources |
| A-CUT3e2-2 | Caller projection, map state, and event schema stay target-neutral | ✅ met | the direct source lowers the explicit address-to-u64 cast, bounded map load/store, and typed `StatusSet` event into checked Canonical Core without embedding an EVM, Solana, or NEAR storage/event layout |
| A-CUT3e2-3 | The same checked contract reaches every primary target plan | ✅ met | the focused Lean gate builds EVM, Solana, and NEAR plans from one normalized contract and observes the caller context, Core cast, map operations, and event operation before target materialization |
| A-CUT3e2-4 | Public artifacts are direct and Canonical-only | ✅ met | target-first EVM Yul/bytecode, Solana assembly/package/IDL, and NEAR WAT/Wasm report `contract-source-authored` / `canonical-core-v1`; retired ContractSpec/IR sidecars are absent |
| A-CUT3e2-5 | Obsolete callers and duplicate implementations are deleted | ✅ met | the temporary Surface fixture is absent, StatusMessage is removed from the compatibility allowlist, and Product Matrix plus direct-product callers no longer consume a retired `.module` |

## Gate CMP-3g1 - Independent ArrayExample reference contracts

**Status: Closed for reference pinning only**

**Closed: 2026-07-15 at `b8448961`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3g1-1 | Every primary target has an independent native reference | ✅ met | Solidity, Pinocchio Rust, and near-sdk Rust sources implement the same four operations without importing ProofForge compiler or IR modules; all v1 manifests match their source SHA-256 |
| CMP-3g1-2 | The scenario covers positive fixed-array behavior and a planned failure | ✅ met | the four-step v1 scenario checks length, valid indexing, sum, and normalized out-of-bounds failure across all eight observation dimensions |
| CMP-3g1-3 | Native sources build with pinned target toolchains | ✅ met | Solidity 0.8.30 compiles the EVM reference; cargo-build-sbf 3.1.12/platform-tools v1.52 builds the Pinocchio ELF; Rust 1.94.0 builds the near-sdk Wasm |
| CMP-3g1-4 | Reference pinning does not claim equivalence | ✅ met | inventory contains 124 assets and exactly 30 verified assets; all three references and the scenario remain `semanticEvidence=none` until CMP-3g2 VM execution |

## Gate CMP-3g2 - Primary-triad ArrayExample native differential

**Status: Closed**

**Closed: 2026-07-15 at `0035138e`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3g2-1 | ProofForge artifacts come only from the direct Product source | ✅ met | `just differential-array-example` builds `Examples/Product/ArrayExample.lean`; all target artifacts report `contract-source-authored` / `canonical-core-v1`, and forbidden ContractSpec/IR sidecars fail the gate |
| CMP-3g2-2 | Independent references execute on the primary target VMs | ✅ met | both EVM artifacts run on Anvil, both Solana ELFs on Mollusk, and both NEAR Wasm artifacts on upstream `near-vm-runner` |
| CMP-3g2-3 | Positive and negative behavior match completely | ✅ met | length 3, element 20, sum 60, and normalized out-of-bounds failure match across all eight observation dimensions; no state, balance, event, or external-action effects are observed |
| CMP-3g2-4 | Evidence promotion is fail-closed and replaces v0 | ✅ met | the called NEAR v0 manifest is deleted; inventory contains 125 assets and exactly 36 verified assets, including the three references, scenario, runner, and focused gate |

## Gate CMP-3h1 - Independent StatusMessage reference contracts

**Status: Closed for reference pinning only**

**Closed: 2026-07-15 at `8bd968fb`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3h1-1 | Every primary target has an independent native reference | ✅ met | Solidity, Pinocchio Rust, and near-sdk Rust implement init, caller-projected map writes/reads, and `StatusSet` without importing ProofForge compiler or IR modules; all v1 manifests match their source SHA-256 |
| CMP-3h1-2 | Caller identity projection remains target-owned and explicit | ✅ met | EVM narrows the full address to u64, Solana hashes the full authority pubkey then reads digest word zero little-endian, and NEAR hashes the full predecessor AccountId then reads the same u64 limb |
| CMP-3h1-3 | The scenario covers overwrite, readback, state, and events | ✅ met | the five-step v1 scenario initializes, writes 7, reads 7, overwrites with 99, and reads 99 while requiring all eight observation dimensions |
| CMP-3h1-4 | Native sources build with pinned target toolchains | ✅ met | Solidity 0.8.30 compiles; the Pinocchio host test and cargo-build-sbf 3.1.12/platform-tools v1.52 pass; near-sdk host tests and Rust 1.94.0 Wasm build pass |
| CMP-3h1-5 | Reference pinning does not claim VM equivalence | ✅ met | inventory contains 130 assets and exactly 36 verified assets; all three references and the scenario remain `semanticEvidence=none`, and the called NEAR v0 manifest remains explicit CMP-3h2 deletion work |

## Gate CMP-3d1 - Independent Ownable reference contracts

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3d1-1 | Every primary target has an independent native reference | ✅ met | `1545c739` pins Solidity, Pinocchio Rust, and near-sdk Rust sources; none imports ProofForge compiler or IR modules |
| CMP-3d1-2 | The logical lifecycle includes authorization failures and one-shot initialization | ✅ met | the ten-step v1 scenario covers unauthorized transfer/renounce, zero-address transfer, ownership events, state-preserving failures, renounce, and rejected reinitialization after owner becomes zero |
| CMP-3d1-3 | Native sources build with pinned target toolchains | ✅ met | `solc` 0.8.30 compiles Solidity; Pinocchio host check and cargo-build-sbf 3.1.12/platform-tools v1.52 pass; near-sdk host tests and Rust 1.94.0 Wasm build pass |
| CMP-3d1-4 | Pinned sources do not overclaim semantic equivalence | ✅ met | `just differential-contracts` validates all digests and records the three references plus scenario as `semanticEvidence=none`; inventory is 106 assets with exactly 12 verified assets |
| CMP-3d1-5 | No compatibility compiler route is introduced | ✅ met | all comparison code remains under `benchmarks/`, `testkit/`, and `scripts/differential/`; the unused benchmark v0 manifest was deleted and CMP-3d2 owns removal of the still-called NEAR v0 test manifest |

## Gate CMP-3d2 - Primary-triad native Ownable differential

**Status: Closed**

**Closed: 2026-07-14**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3d2-1 | The ProofForge side uses only the direct public source | ✅ met | `just differential-ownable` builds `Examples/Product/Ownable.lean` with `contract-source-authored` / `canonical-core-v1` on EVM, Solana, and NEAR and rejects ContractSpec sidecars |
| CMP-3d2-2 | Both implementations execute the same authorization inputs | ✅ met | Anvil, Mollusk, and upstream `near-vm-runner` execute all ten steps with explicit Alice/Bob/zero roles; the Solana runner records and validates each destination instead of inferring it from the result |
| CMP-3d2-3 | Negative cases preserve state and remain classified | ✅ met | unauthorized transfer/renounce, zero-address transfer, and reinitialization after renounce fail with owner state unchanged and normalized authorization/invalid-input/assertion categories |
| CMP-3d2-4 | Events, returns, and target-local resources are observed completely | ✅ met | every target reports `semanticMatch=true` with complete eight-dimension coverage; indexed EVM topics, Solana numeric logs, and NEAR event JSON normalize to the same ordered ownership events |
| CMP-3d2-5 | Replaced v0 evidence is deleted rather than adapted | ✅ met | `testkit/compare/near/ownable/reference-manifest.json` is deleted; the remaining compare caller explicitly names `testkit/differential/ownable/references/near.v1.json` with no fallback |
| CMP-3d2-6 | Inventory promotion is evidence-backed | ✅ met | the generated inventory has 107 assets and exactly 18 verified assets; the three Ownable references, scenario, runner, and focused gate are the six newly verified assets |

## Gate CMP-3e1 - Independent Pausable reference contracts

**Status: Closed**

**Closed: 2026-07-14 at `a37c9ae7`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3e1-1 | Every primary target has an independent native reference | ✅ met | Solidity, Pinocchio Rust, and near-sdk Rust sources import no ProofForge compiler or IR modules; three v1 manifests pin exact source SHA-256, license, and toolchains |
| CMP-3e1-2 | The logical scenario includes negative state preservation | ✅ met | the nine-step scenario covers initial/final queries, unpause while unpaused, repeated pause, post-failure state queries, and successful pause/unpause transitions |
| CMP-3e1-3 | Native sources build with pinned target toolchains | ✅ met | `solc` 0.8.30 compiles Solidity; Pinocchio host check and cargo-build-sbf 3.1.12/platform-tools v1.52 pass; near-sdk host tests and Rust 1.94.0 Wasm build pass |
| CMP-3e1-4 | Pinned sources do not overclaim semantic equivalence | ✅ met | `just differential-contracts` validates all manifests and digests; inventory grows to 112 assets but remains exactly 18 verified, with all four Pausable CMP-3 assets at `none` |
| CMP-3e1-5 | No production compatibility path is introduced | ✅ met | references, scenario, and inventory logic remain under `benchmarks/`, `testkit/`, and `scripts/differential/`; the called NEAR v0 manifest remains explicit deletion work for CMP-3e2, not a compiler adapter |

## Gate CMP-3e2 - Primary-triad native Pausable differential

**Status: Closed**

**Closed: 2026-07-14 at `8f1f5a1f`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3e2-1 | The ProofForge side uses only the direct public source | ✅ met | `just differential-pausable` builds `Examples/Product/Pausable.lean` as `contract-source-authored` / `canonical-core-v1` on EVM, Solana, and NEAR and rejects legacy sidecars |
| CMP-3e2-2 | Both implementations execute the same guarded state machine | ✅ met | Anvil, Mollusk, and upstream `near-vm-runner` execute the same nine query, pause, unpause, and negative steps against native and ProofForge artifacts |
| CMP-3e2-3 | Negative transitions preserve state and remain classified | ✅ met | unpause while unpaused and repeated pause both fail, retain the previous scalar state, and normalize to distinct assertion error data |
| CMP-3e2-4 | All required observations are complete | ✅ met | every target reports `semanticMatch=true` with status, return, state, balances, events, external actions, interface, and target-local resource coverage |
| CMP-3e2-5 | Replaced v0 evidence is deleted instead of adapted | ✅ met | `testkit/compare/near/pausable/reference-manifest.json` is deleted; the remaining compare caller explicitly names the v1 reference with no discovery fallback |
| CMP-3e2-6 | Inventory promotion is evidence-backed | ✅ met | the generated inventory has 113 assets and exactly 24 verified assets; the three Pausable references, scenario, runner, and focused gate are the six newly verified assets |

## Gate CMP-3f1 - Independent ReentrancyGuard reference contracts

**Status: Closed**

**Closed: 2026-07-14 at `782460f0`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3f1-1 | Every primary target has an independent native reference | ✅ met | Solidity, Pinocchio Rust, and near-sdk Rust sources import no ProofForge compiler or IR modules; three v1 manifests pin exact source SHA-256, license, and toolchains |
| CMP-3f1-2 | The logical scenario includes both invalid lock transitions | ✅ met | the nine-step scenario covers release while unlocked, repeated acquire, successful acquire/release, and state queries after each failure |
| CMP-3f1-3 | Native sources build with pinned target toolchains | ✅ met | `solc` 0.8.30 compiles Solidity; Pinocchio host check and cargo-build-sbf 3.1.12/platform-tools v1.52 pass; three near-sdk host tests and Rust 1.94.0 Wasm build pass |
| CMP-3f1-4 | Pinned sources do not overclaim semantic equivalence | ✅ met | `just differential-contracts` validates all manifests and digests; inventory grows to 118 assets but remains exactly 24 verified, with all four ReentrancyGuard CMP-3 assets at `none` |
| CMP-3f1-5 | The replaced v0 manifest is not deleted prematurely | ✅ met | the called NEAR v0 manifest remains explicit CMP-3f2 deletion work until both native and direct artifacts execute on the upstream VM; it is test data, not a compiler adapter |

## Gate CMP-3f2 - Primary-triad native ReentrancyGuard differential

**Status: Closed**

**Closed: 2026-07-14 at `fb190e31`**

| # | Criterion | Status | Evidence |
|---|---|---|---|
| CMP-3f2-1 | The ProofForge side uses only the direct public source | ✅ met | `just differential-reentrancy-guard` builds `Examples/Product/ReentrancyGuard.lean` as `contract-source-authored` / `canonical-core-v1` on EVM, Solana, and NEAR and rejects legacy sidecars |
| CMP-3f2-2 | Both implementations execute the same guarded lock lifecycle | ✅ met | Anvil, Mollusk, and upstream `near-vm-runner` execute the same nine query, acquire, release, and negative steps against native and ProofForge artifacts |
| CMP-3f2-3 | Negative transitions preserve state and remain classified | ✅ met | release while unlocked and repeated acquire both fail, retain the previous lock state, and normalize to distinct assertion error data |
| CMP-3f2-4 | All required observations are complete | ✅ met | every target reports `semanticMatch=true` with status, return, state, balances, events, external actions, interface, and target-local resource coverage |
| CMP-3f2-5 | Replaced v0 evidence is deleted instead of adapted | ✅ met | `testkit/compare/near/reentrancy-guard/reference-manifest.json` is deleted; the remaining compare caller explicitly names the v1 reference with no discovery fallback |
| CMP-3f2-6 | Inventory promotion is evidence-backed | ✅ met | the generated inventory has 119 assets and exactly 30 verified assets; the three ReentrancyGuard references, scenario, runner, and focused gate are the six newly verified assets |

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
