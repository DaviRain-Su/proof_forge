# Implementation Log

Status: **Current agent execution ledger (started 2026-07-12)**

This append-only ledger records completed, reviewed, and verified task slices
for the current architecture program. It is intentionally concise so an agent
can establish recent context without loading the historical
[`development-log.md`](development-log.md).

This log is evidence, not scheduling authority. Task order and acceptance
criteria live in the
[current implementation plan](superpowers/plans/2026-07-12-portable-intent-abstraction.md),
while phase sign-off lives in [`gate-status.md`](gate-status.md).

## Entry Contract

Append one entry after each completed or reviewed task. Do not rewrite older
entries except to correct a factual error.

```markdown
## YYYY-MM-DD - <Task ID>: <short result>

- Status: `done (verified at <sha>)` or `blocked`
- Commit: `<sha>` or an exact reviewed range
- Result: one or two sentences describing observable completion
- Interfaces: key modules, contracts, or documents changed
- Verification: exact commands and whether each passed, failed, or skipped
- Remaining: explicit follow-up or `none`
- Documentation: files updated to keep planning and evidence synchronized
```

Rules:

1. `done` requires reproducible validation and a revision identifier.
2. `blocked` requires the failing command, missing dependency, or external
   decision; it is not a synonym for unfinished.
3. Record unavailable live tools as skipped, never as passed.
4. Keep detailed command transcripts out of this file; link a gate record or
   CI run when longer evidence is needed.
5. Update the root [`AGENTS.md`](../AGENTS.md) checkpoint and authoritative task
   plan in the same change.

## 2026-07-12 - DOC-ENTRYPOINT: Establish the agent control plane

- Status: `done (verified at 7cf0d886)`
- Commit: `7cf0d886`
- Result: made root `AGENTS.md` the single agent bootstrap for current planning,
  task routing, source-of-truth precedence, completion rules, and validation.
- Interfaces: `AGENTS.md`, documentation lifecycle, engineering index, and
  documentation update protocol.
- Verification: `just docs-check`, strict doc-code audit, agent-entrypoint link
  check, and `git diff --check` passed.
- Remaining: begin A1 from the current implementation plan.
- Documentation: `AGENTS.md`, `docs/implementation-log.md`,
  `docs/document-status.md`, `docs/INDEX.md`, and
  `docs/development-standards.md`.

## 2026-07-12 - A1/D1: Isolate Solana grammar ownership

- Status: `done (verified at 6af4eb72)`
- Commit: implementation `52402821`; acceptance repair `c1433b2e`; product
  guard `b8c03f5`; import-parser review repair `6af4eb72`
- Result: moved Solana account, allocator, PDA, CPI, realloc, and transfer-hook
  grammar out of portable `Contract.Source` and into `Contract.Source.Solana`.
  The review repairs added positive Solana elaboration/IR intent pins, made the
  isolation gate part of the required product aggregate, and parse every module
  in single-line or continued Lean import commands without prefix false positives.
- Interfaces: `ProofForge.Contract.Source`,
  `ProofForge.Contract.Source.Solana`, `source-dsl-isolation`, and Gate A1-1.
- Verification: `just source-dsl-isolation`, portable import-parser self-test,
  `just portable-default`,
  `just solana-light`, `just product`, and `git diff --check` passed. The
  Solana suite covered source fixtures, PDA, CPI, realloc, plans, artifacts,
  and Pinocchio reference-equivalence.
- Remaining: none for A1/D1; Gate A1 remains open for A1-2 through A1-6.
- Documentation: `AGENTS.md`, current implementation plan,
  `docs/implementation-backlog.md`, `docs/gate-status.md`, and
  `docs/legacy-replacement-ledger.md`.


## 2026-07-12 - D0: Create migration ledger and freeze baseline

- Status: `done (verified at 5bc3196c)`
- Commit: implementation `21cdd587`; review repair `5bc3196c`
- Result: created `docs/legacy-replacement-ledger.md` with 5 boundary rows
  (D1-D5, all `inventoried`); captured production import baseline (11 files)
  in `scripts/canonical/legacy-production-imports.txt`; extended
  `check-legacy-freeze.sh` with an exact, mandatory import baseline; added
  `legacy-replacement-freeze` recipe to justfile and wired into `just check`;
  documented gate in `validation-gates.md` (en + zh).
- Interfaces: `legacy-replacement-ledger.md`, `legacy-production-imports.txt`,
  `check-legacy-freeze.sh`, `legacy-replacement-freeze`.
- Verification: `bash -n scripts/canonical/check-legacy-freeze.sh`,
  `scripts/canonical/check-legacy-freeze.sh --self-test`,
  `just legacy-replacement-freeze`, `just docs-check`, and
  `git diff --check` passed. Self-tests cover a missing baseline, an
  unreviewed production import, a synchronized baseline update, and a
  baseline-only expansion.
- Remaining: none for D0; D1 was closed by A1/D1 entry above.
- Documentation: `docs/legacy-replacement-ledger.md`,
  `docs/document-status.md`, `docs/validation-gates.md`,
  `docs/zh/validation-gates.zh.md`, `scripts/canonical/check-legacy-freeze.sh`,
  `scripts/canonical/legacy-production-imports.txt`, `justfile`.

## 2026-07-12 - A2: Add the intent materializer contract

- Status: `done (verified at ad286336)`
- Commit: `ad286336`
- Result: created `ProofForge/Contract/Intent/Registry.lean` with
  `IntentFamily`, `IntentContract`, `IntentMaterialization`,
  `IntentMaterializer`, and `IntentRegistry` (duplicate-key rejection +
  named diagnostic for missing materializer). Created
  `Tests/IntentRegistry.lean` with 5 test cases: duplicate rejection,
  exact lookup, missing materializer diagnostic, error preservation,
  empty registry.
- Interfaces: `IntentFamily`, `IntentContract`, `IntentMaterialization`,
  `IntentMaterializer`, `IntentRegistry.create`, `IntentRegistry.resolve`,
  `IntentRegistry.empty`.
- Verification: `intent-registry: ok`, `token-feature-matrix: ok (36 rows)`,
  `just product: ok`, `git diff --check: ok`.
- Remaining: none for A2; A3 (NFT intent) is next.
- Documentation: `AGENTS.md`, current implementation plan.

## 2026-07-12 - A3: Define target-neutral NFT intent

- Status: `done (verified at daa695c7)`
- Commit: `daa695c7`
- Result: created `ProofForge/Contract/Nft.lean` with `NFTAssetModel`
  (unique | multiToken), `NFTFeature` (9 features with stable IDs),
  `NFTSpec` (name, symbol, assetModel, features), `NFTSpec.validate`
  (rejects duplicate features, soulbound+transferable, multiToken+soulbound),
  and `NFTSpec.toIntentContract` (maps to IntentContract with
  family=nonFungibleToken). Created `Tests/NftIntent.lean` with 7 test
  cases.
- Interfaces: `NFTAssetModel`, `NFTFeature`, `NFTSpec`,
  `NFTSpec.validate`, `NFTSpec.toIntentContract`, `NFTFeature.id`.
- Verification: `nft-intent: ok`, `intent-registry: ok`, `just product: ok`,
  `git diff --check: ok`.
- Remaining: none for A3; A4 (audit NFT implementation candidates) is next.
- Documentation: `AGENTS.md`, current implementation plan.

### A3 review repair

- Added real blank-name and blank-symbol validation; the original “empty” test
  used non-empty identity values and did not exercise the planned boundary.
- Made `NFTSpec.toIntentContract` validate before conversion and preserve a
  stable asset-model discriminator, preventing unique and multi-token intents
  from collapsing to the same generic contract.
- Exported `ProofForge.Contract.Nft` through `ProofForge.Contract` and added
  `just nft-intent` to the product and check gates. Tests now consume only the
  public aggregate import.

## 2026-07-12 - A4 review repair

- Replaced the entrypoint-name presence check with exact ABI and executable IR
  lifecycle validation for ERC721, MetaplexNft, and NearNft.
- Added one-shot initialization and stored mint authority to all three
  candidates; unauthorized mint and duplicate mint now reject before mutation.
- Extended IR test state with configurable caller values so authorization and
  transfer behavior can be exercised rather than inferred from source text.
- Added `just nft-implementation-contract` to product and check.

## 2026-07-12 - A5 review

- Replaced the advisory canonical gate with strict `compileForTest .canonical`
  evidence. EVM and NEAR reach `buildFromCore`; Solana currently fails on
  `PureOp.hash(address)` required by its 32-byte NFT identity model.
- Projected each larger stdlib candidate to the audited first-slice entrypoints;
  EVM selectors are explicit and standard-compatible.
- Materializers now reject malformed model discriminators, duplicate IDs,
  missing mandatory features, multi-token input, and every deferred feature.
- Status remains in progress until Solana hash planning is implemented. The
  named `just nft-materialization` gate pins both strict successes and the exact
  remaining blocker so advisory success cannot be mistaken for completion.

### A5 Solana strict closure

- Added the canonical Solana `hashAccount0` plan node for
  `hash(contextRead sender/origin)` only; arbitrary address hashing remains
  fail closed.
- Lowering hashes all four 64-bit words of account[0]'s public key through
  `sol_sha256`, checks the syscall result, and stores digest limb 0 according
  to the existing portable identity-handle convention.
- Numeric hash literals such as the zero-map sentinel are accepted explicitly;
  non-numeric hash literals remain rejected.
- The A5 gate now requires strict success on all three primary targets and
  inspects the generated hash lowering for full-width loads and syscall use.

### A2 review repair

- Added the promised `resolveIntentMaterializer` public API and the checked
  `materializeIntent` path, which rejects a target-specific materializer that
  returns an artifact for a different target.
- Exported the registry through `ProofForge.Contract` and added the durable
  `just intent-registry` gate to both `product` and `check`.
- Expanded the registry test from five to seven cases, including successful
  checked dispatch and fail-closed target-result validation.

## 2026-07-12 - A6 review repair

- Status: `in_progress`; artifact routing is repaired, while target-runtime
  lifecycle evidence remains the explicit completion blocker.
- Result: public `--nft` CLI route materializes one `NFTSpec` into EVM, Solana,
  and NEAR artifact/SDK bundles with target standard IDs, source module
  references, byte counts, and SHA-256 digests in each manifest.
- Interfaces: `ProofForge.Cli.Args`, `ProofForge.Cli.TargetDriver`,
  `ProofForge.Cli.ContractSourceArtifacts`, `Examples/Product/Nft.lean`,
  `scripts/portable/nft-multi-target.sh`, `Tests/NftArtifactSchema.lean`.
- The first real bundle runs exposed and fixed the EVM `init()` selector and
  identity representation, Solana canonical identity width, and Solana map
  lowering for 8-byte values.
- Verification: `Tests/NftArtifactSchema.lean`, `scripts/portable/nft-multi-target.sh`,
  `just solana-light`, `just product`, `just docs-check`, `just check`, and
  `git diff --check` passed.
- Remaining: add target-runtime lifecycle smoke for mint, owner/balance,
  authorized transfer, unauthorized rejection, and duplicate mint. This is an
  A6 acceptance criterion, not deferred completion evidence.
- Documentation: `AGENTS.md`, current plan, `docs/implementation-log.md`.

## 2026-07-12 - Parallel test framework Tasks 1-7

- Status: `done locally (remote CI verification pending)`
- Manifest: 108 serial `check` recipes classified into four conflict-aware
  lanes with exact coverage validation.
- Scheduler: automatic `min(CPU, 4)` concurrency, positive `JOBS` override,
  lane serialization, exclusive barriers, process-group cancellation, lane
  logs, and structured timing reports.
- Fast gate: conservative changed-path selection with fixed core/product
  baseline and focused EVM, Solana, Wasm/NEAR, and documentation tags.
- Verification:
  - manifest, scheduler, and selector unit tests passed
  - `JOBS=1` and `JOBS=4` full dry-runs selected identical coverage
  - `CHECK_BASE=HEAD just check-fast` passed in 238.73 seconds
  - the first fast run selected 11 of 108 full recipes; `product` was the
    slowest recipe at 124.26 seconds
  - `JOBS=4 just check-parallel` passed all 108 recipes in 1027.62 seconds
    after the isolated worktree's Lake/npm dependencies were installed
  - the first full run identified `rebuild-hash` (322.29 seconds),
    `solana-light` (142.09 seconds), `testkit` (136.18 seconds), and
    `quint-mbt-gate` (101.73 seconds) as the dominant critical-path work
  - `git diff --check` passed
- Entrypoints: `check` now selects the qualified parallel coordinator;
  `check-parallel`, `check-serial`, `check-fast`, and `check-lane` retain
  explicit full, diagnostic, inner-loop, and CI surfaces.
- CI integration: GitHub uses a required four-lane matrix after `product`, and
  Woodpecker runs the same coordinator with `JOBS=4` after its product step.
- Commits: `d2512bab` through `eacfeadf` on
  `feature/parallel-test-framework`.
- Remaining: verify the first pushed GitHub matrix and record its critical-path
  timing against the previous serial workflow. This is deployment evidence,
  not missing local framework implementation.
- First remote run `29191590503` exposed a pre-existing cold-cache dependency:
  `source-dsl-isolation` imported three Solana example modules that the default
  Lake target did not build. The recipe now builds those modules explicitly
  before executing its Lean tests; a replacement CI run remains required.
- Replacement run `29191835550` confirmed that repair, then exposed the same
  issue in `intent-registry`: its test imports the `ProofForge.Contract`
  umbrella while the recipe built only the registry leaf. The recipe now
  builds the imported umbrella target explicitly.
- Run `29192133516` passed the repaired cold-cache product gate and started all
  four lanes. Its EVM lane showed that the new independent matrix runners also
  need the old job's package bootstrap; every lane now runs `lake build` before
  its manifest recipes.

## 2026-07-12 - B3 Soroban follow-up review

- Status: `done (review repair)`
- Reviewed the B3 bridge-aware canonical lowering series through `9daed038` and
  integrated it with the parallel test framework without dropping either gate.
- Fixed the Soroban spike `_get` ABI from `i32` to `i64`; the old signature
  truncated Counter's `u64` state above `2^32 - 1` while the lifecycle test only
  exercised values through `3`.
- Canonical and legacy EmitWat lowering now fail closed for 32-byte Hash storage,
  which the scalar `_get` ABI cannot represent. The previous Hash helper emitted
  a malformed memcpy stack sequence.
- Fixed non-NEAR fixed-byte return lowering to keep its pointer as `i32`, matching
  `set_return_data(i32, i32)`.
- The Soroban offline gate now rebuilds `proof-forge` before invoking the CLI and
  pins `_get`'s full-width WAT signature.
- Parallel coverage now includes `soroban-public-route` and
  `soroban-counter-offline`; serial/manifest equivalence is 110 recipes.
- Verification: `just soroban-public-route`, `just soroban-counter-offline`,
  `just wasm-host-plan-preservation`, `just wasm-soroban-host-smoke`, offline-host
  Cargo tests, `just test-manifest`, `just test-equivalence`, and
  `git diff --check` passed.

## 2026-07-12 - Arbitrum Stylus Task 1 classification

- Status: `done (docs-only)`
- Classified planned target `wasm-arbitrum-stylus` under `wasmHost` while
  preserving EVM ABI, 256-bit storage-slot, event, call, gas, and ink semantics.
- Locked Direct HostIO Wasm as the final canonical renderer and Rust SDK
  sourcegen as bootstrap, compatibility path, and differential oracle.
- Pinned `stylus-sdk = "=0.10.8"`, `cargo-stylus = "=0.10.8"`, Rust `1.91.0`,
  and `wasm32-unknown-unknown`.
- Added D-053, roadmap classification, Wasm-family guidance, English/Chinese
  target docs, and an executable docs contract.
- Registry, CLI target lists, backend routing, and advertised product targets
  remain unchanged.
- Verification: `python3 scripts/targets/test-doc-targets.py`, i18n sync,
  `just docs-check`, and `git diff --check` passed.
- Next: Task 2, stable `StylusPlan` data contract.

## 2026-07-12 - Arbitrum Stylus Task 2 plan contract

- Status: `done`
- Added renderer-neutral `StylusPlan` data types for ABI methods/errors, 256-bit
  slot expressions, storage words, functions, events, calls, HostOps, resources,
  artifacts, and per-renderer support state.
- Stable bytes are represented as `Array UInt8`; the plan does not install
  global instances for Lean's `ByteArray` or depend on Rust/WAT syntax.
- Added smart constructors that accept integer widths
  `8/16/32/64/128/160/256` and fixed bytes `1..32`, rejecting invalid widths at
  plan construction rather than in a renderer.
- Registry and CLI routing remain unchanged.
- Verification: `just stylus-plan-contract`,
  `lake build ProofForge.Backend.Stylus.Plan`, and `git diff --check` passed.
- Next: Task 3, canonical-to-plan builder and strict validation.

## 2026-07-12 - Arbitrum Stylus Task 3 canonical plan

- Status: `done`
- Added `Plan.Core.buildFromCore`, consuming only a checked canonical contract
  and exact matching `CapabilityPlan` for `wasm-arbitrum-stylus`.
- The repository's real Counter interface remains
  `initialize/increment/get` with `uint64 count`; selectors are decoded from
  canonical interface metadata and persistent state is assigned a 32-byte EVM
  slot expression.
- HostOp collection records storage load/cache/flush, context, Keccak, event,
  and EVM call modes. NEAR promise modes, unknown typed HostOps, unsupported
  context, wrong targets, and mismatched capability plans fail closed.
- Added plan-internal validation for ABI widths/selectors, storage bounds,
  function/ABI references, flush obligations, and renderer completeness.
- Registry and CLI routing remain unchanged.
- Verification: `just stylus-core-plan`, `just stylus-diagnostics`,
  `just canonical-core`, `just evm-plan`, and `git diff --check` passed.
- Next: Task 4, deterministic Rust SDK AST and renderer.

### Local parallel qualification

- `check-serial` warm-cache baseline: 1297.26 seconds.
- Three balanced `JOBS=4 just check-parallel` runs passed in 703.38, 862.21,
  and 717.09 seconds; mean 760.89 seconds.
- Mean local wall-time improvement: 41.35%, above the 35% acceptance threshold.
- `rebuild-hash` remains the largest and most variable recipe (370-503 seconds)
  but now overlaps independent core, Solana, Wasm, testkit, and Quint work.
- Timing evidence: `docs/generated/test-timing-baseline.md`.

### A6 runtime closure

- Status: `done (verified at 6a6022ea)`.
- Added `just portable-nft-runtime`, which consumes the public three-target NFT
  bundle and executes the same minimal lifecycle on EVM Foundry, Solana
  Surfpool/SVM, and the NEAR offline Wasm host.
- Runtime coverage includes initialization, mint, duplicate-mint rejection,
  owner and balance queries, authorized transfer, and unauthorized-transfer
  rejection.
- Fixed defects exposed by runtime execution: Solana Hash/Address ABI widths,
  full-pubkey hash scratch preservation, module-global account layout for query
  entrypoints, and canonical NEAR hash literals incorrectly represented as
  pointer zero instead of allocated four-limb values.
- Verification: `just portable-nft-runtime`, `just product`, `just solana-light`,
  `just check`, Rust formatting, shell syntax checks, and `git diff --check`
  passed on 2026-07-12.
- The Surfpool lifecycle remains an explicit optional-tool gate rather than a
  required product/CI dependency; `just product` continues to require honest
  primary-triad artifact generation.

## 2026-07-12 - D3: Make accepted NFT materialization strict

- Status: `done (verified at 545d7a51)`
- Result: added `ProofForge.Compiler.runStrictCanonicalTargetGate`, a strict
  canonical target gate where adapter, validation, capability, host-op,
  unknown-target, and `buildFromCore` failures are all hard errors. Wired the
  gate into the three primary-triad NFT materializers so accepted
  materializations record strict-gate evidence.
- Interfaces: `runStrictCanonicalTargetGate`,
  `ProofForge.Contract.NftMaterialize.withStrictGate`,
  `Tests/Canonical/StrictIntentMaterialization.lean`.
- Verification:
  - `lake env lean --run Tests/Canonical/StrictIntentMaterialization.lean` passed
  - `lake env lean --run Tests/NftMaterialization.lean` passed
  - `just canonical-parity` passed
  - `just product` passed
  - `git diff --check` passed
- Remaining: migrate non-NFT product callers from `runCanonicalValidationGate`
  to `runStrictCanonicalTargetGate` before advancing D3 to `default_switched`.
- Documentation: `docs/legacy-replacement-ledger.md` (D3 → `replacement_ready`),
  `AGENTS.md` checkpoint, current legacy-replacement plan, this log.

### D3 review repair

- Replaced permissive negative tests that accepted any failure with independent
  exact-prefix cases for adapter, validation, capability, HostOp handler,
  unknown-target, and target `buildFromCore` stages.
- Added `runStrictCanonicalContractGate` so raw canonical validation and target
  planning can be verified without manufacturing invalid legacy input.
- Moved HostOp handler validation before capability resolution. With the current
  catalog, the old order made the unhandled-host-op branch unreachable on EVM
  and Solana because every HostOp first failed its target capability check.
- Tightened the positive case: a supported EVM NFT slice must pass every stage;
  a named failure is no longer accepted as a successful test outcome.

## 2026-07-12 - D4: Native NFT target-first dispatch

- Status: `done (verified at 19c93baf)`
- Commit: implementation series `bcc98e02..19c93baf`
- Result: switched NFT `build` on the primary triad to a typed native target driver.
  `TargetDriver.resolveBuild` returns `BuildResult` with `.native`/`DispatchKind`;
  `Cli.lean` bypasses `newCommandArgsToLegacy` for NFT and calls
  `compileContractSourceEvmBytecode` / `compileContractSourceSbpf` /
  `compileContractSourceEmitWat` directly.
- Interfaces: `ProofForge.Cli.TargetDriver.BuildResult`,
  `ProofForge.Cli.TargetFirst.resolveBuildRequest`,
  `ProofForge.Cli.CliOptions.nativeBuildOp?`.
- Verification:
  - `lake env lean --run Tests/CliTargetFirst.lean` passed
  - `lake env lean --run Tests/NftArtifactSchema.lean` passed
  - `scripts/portable/nft-multi-target.sh` passed
  - `just product` passed
  - `just check` passed
  - `git diff --check` passed
- Remaining: migrate Counter, ValueVault, Token, RemoteCall, and secondary targets
  to native dispatch before D4 reaches `default_switched`.
- Documentation: `docs/legacy-replacement-ledger.md`, `AGENTS.md`, current plan,
  `docs/implementation-log.md`.

## 2026-07-12 - B1: Neutral Wasm-host plan extraction review repair

- Status: `done (verified at c8d2bbb6)`
- Commit: `c8d2bbb6`
- Review finding: the initial B1 commit only wrapped NEAR-owned plan types, kept
  `buildFromCore` delegated behind the old public boundary, and compared only a
  few plan fields. It did not establish the neutral ownership or rendered-WAT
  preservation required by Task 7.
- Result: `WasmHost.ModulePlan` now owns the neutral plan data contract;
  `AbiPlan` owns neutral ABI types; `ModulePlan.Core` and `ModulePlan.Lower` are
  the public build/lower boundaries. NEAR types remain compatibility aliases,
  while unsupported Soroban and CosmWasm routes fail closed until promotion.
- Consumption: canonical compilation and contract-source NEAR artifact emission
  call the neutral builder/lowerer instead of the NEAR-specific public route.
- Regression repair: updated the NEAR Promise registry assertion from one stale
  handler to the four currently supported handlers and exercised Promise WAT
  generation through the neutral boundary.
- Verification:
  - affected Lean modules and `proof-forge` built successfully
  - `just wasm-host-plan-preservation` passed with exact rendered-WAT equality
  - `just near-promise-hostop` passed, including offline-host WAT execution
  - `just canonical-near-plan` and `just near-abi-plan` passed
  - `just product` passed
  - `just check` passed; Quint verification explicitly skipped because this host
    has Java 11 and the existing gate requires Java 17+
  - `git diff --check` passed
- Remaining: none for B1. Soroban behavior belongs to B3.

## 2026-07-12 - B2: Add a strict canonical target gate

- Status: `done (verified at d4df51bc)`
- Commits: implementation `23e66248`; review repair `d4df51bc`
- Result: added `Tests/Canonical/StrictTargetGate.lean` with positive
  primary-triad fixture tests (Counter and ValueVault passing strict gate on
  evm, solana-sbpf-asm, wasm-near), unknown-target rejection, non-primary
  registered-target rejection, and advisory-vs-strict agreement. Added
  `strict-target-gate` justfile recipe and wired it into `check`. The strict
  gate implementation (`runStrictCanonicalTargetGate`,
  `runStrictCanonicalContractGate`, `runStrictCheckedTargetGate`) was already
  in `CanonicalPipeline.lean` from B1 work. The advisory
  `runCanonicalValidationGate` route is unchanged.
- Interfaces: `ProofForge.Compiler.runStrictCanonicalTargetGate`,
  `ProofForge.Compiler.runStrictCanonicalContractGate`,
  `Tests/Canonical/StrictTargetGate.lean`, `just strict-target-gate`.
- Verification:
  - `just strict-target-gate` passed
  - `just strict-intent-materialization` passed
  - `just wasm-host-plan-preservation` passed
  - `just product` passed
  - `just check` passed; Quint verification explicitly skipped because this host
    has Java 11 and the existing gate requires Java 17+
  - `git diff --check` passed
- Review repair: pinned the registered non-primary rejection to the named
  `wasm-cosmwasm` capability boundary and required the advisory gate to succeed
  independently on known-good primary-triad fixtures. The original test accepted
  any non-primary error and treated a shared advisory/strict failure as agreement.
- Remaining: none
- Documentation: `AGENTS.md`, current plan, `docs/implementation-log.md`.

## 2026-07-12 - B3: Promote Soroban Counter

- Status: `done` (canonical lowering deferred)
- Commit: `a399420c` + `ff0cf1df`
- Result: promoted `wasm-stellar-soroban` through the strict canonical target
  gate for the Counter fixture. Added `.checkedArithmetic` to the Soroban
  target profile so the FV-5 capability gate passes. `ModulePlan.Core.buildFromCore`
  accepts `.soroban` bridge — reuses the NEAR layout builder (same key-value
  storage semantics) with the soroban bridge discriminator. Added
  `wasm-stellar-soroban` dispatch to `runStrictCheckedTargetGate` in
  `CanonicalPipeline.lean`. CLI artifact emission via `EmitWat.lowerModule`
  with `.soroban` bridge already works correctly — produces WAT with
  `_get`/`_put` host imports (not NEAR `storage_read`/`storage_write`).

  **Canonical plan lowering deferred**: the canonical lowering path
  (`NearModulePlan.lowerFromPlan`) builds Wasm helpers that hard-code NEAR
  host calls (`Scalar.readFuncNear` → `storage_read`, etc.). Making these
  bridge-aware requires bridge-aware variants of scalar/map/hash helpers,
  param prologue, and auth prologue — a larger refactor than B3 Counter MVP.
  `Lower.lean` fails closed with a clear diagnostic. The CLI path
  (`EmitWat.lowerModule`) is the production path and already handles the
  `.soroban` bridge correctly.

- Interfaces: `ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore`,
  `ProofForge.Compiler.runStrictCheckedTargetGate`,
  `Tests/Canonical/SorobanPublicRoute.lean`, `just soroban-public-route`.
- Verification:
  - `just soroban-public-route` passed (8 tests)
  - `just strict-target-gate` passed
  - `just wasm-host-plan-preservation` passed
  - `just product` passed
  - `git diff --check` passed
- Remaining: bridge-aware canonical lowering (storage helpers, param prologue,
  auth prologue); RemoteCall via `invoke_contract` after lowering is complete.
- Documentation: `AGENTS.md`, current plan, `docs/implementation-log.md`.

## 2026-07-12 - Stylus Task 4: Deterministic Rust SDK renderer

- Status: `done`
- Result: extended the immutable `StylusPlan` with plan-owned blocks,
  operations, terminators, ABI mutability, and overflow modes, then added a
  structural Rust SDK AST and deterministic crate renderer. The renderer
  consumes only validated plan data and emits pinned `stylus-sdk = "=0.10.8"`
  metadata plus the Counter `sol_storage!` and `#[public]` implementation.
- Semantics: canonical Counter checked addition is preserved as `checked_add`;
  the renderer promotes the method to `Result<(), Vec<u8>>` and emits
  deterministic overflow bytes. View methods use `&self`; calls use
  `&mut self`.
- Interfaces: `ProofForge.Backend.Stylus.RustSdk.renderCrate`,
  `Tests/Stylus/RustRender.lean`, `just stylus-rust-render`.
- Verification:
  - `just stylus-rust-render` passed, including repeat-render equality and
    byte-for-byte Cargo/lib golden comparisons
  - `just stylus-plan-contract` passed
  - `just stylus-core-plan` passed
  - `just stylus-diagnostics` passed
  - `git diff --check` passed
- Remaining: generated-crate filesystem packaging, Rust/Wasm compilation, and
  `cargo stylus check` belong to Task 5.

## 2026-07-12 - Stylus Task 5: Rust crate packaging and compile smoke

- Status: `done`
- Result: added validated atomic crate packaging with rejection of absolute,
  traversal, malformed, duplicate, and pre-existing output paths. Added a
  generated Counter runner and a pinned Rust SDK smoke that compares Cargo
  metadata, runs native tests with the SDK `stylus-test` host, and builds
  release `wasm32-unknown-unknown` output.
- Review repair: the real SDK compile established that `sol_storage! uint64`
  uses Alloy `U64` while public ABI methods use Rust `u64`. The renderer now
  emits explicit `U64::from` stores and `.to::<u64>()` loads. Rust commands are
  bound to rustup toolchain `1.91.0` so Homebrew PATH entries cannot silently
  select another compiler.
- CI: added optional `stylus-smoke`, pinned to Rust `1.91.0`,
  `wasm32-unknown-unknown`, and `cargo-stylus =0.10.8`; strict CI mode rejects
  missing or mismatched tools.
- Verification:
  - `just stylus-package` passed
  - `just stylus-rust-render` passed
  - `just stylus-rust-counter` passed native tests and Wasm release build;
    local `cargo stylus check` was a named SKIP because cargo-stylus is absent
  - GitHub Actions YAML parsed successfully
  - `just test-equivalence` passed (110 recipes)
  - `git diff --check` passed
- Remaining: abstract HostIO semantics and Counter lifecycle belong to Task 6.

## 2026-07-12 - Stylus Task 6: HostIO Counter semantics

- Status: `done`
- Result: added a Lean HostIO state with committed storage, transactional
  cache, calldata, result/revert bytes, logs, calls, context, gas, ink, and
  normalized trace events. Counter execution consumes the validated plan ABI,
  uses EVM slot zero and 32-byte words, flushes successful mutations exactly
  once, and discards cache on checked-overflow rejection.
- Evidence: lifecycle coverage includes `initialize -> increment -> get`, a
  host-seeded value above `2^32`, `u64::MAX` rejection, unchanged committed
  state after rejection, exact 32-byte return bytes, and slot-zero layout.
  The independent Rust host adapter exercises the same transactional lifecycle
  and pins normalized JSON for overflow. A generated SDK integration test also
  instantiates the emitted `Counter` against Stylus `TestVM` and runs the same
  normal, high-value, and overflow paths through generated methods.
- Refinement: added stable word/slot encoding anchors and linked the existing
  universal Counter trace theorem. This is not yet a theorem that generated
  Stylus Wasm refines the IR.
- Verification:
  - `just stylus-counter-lifecycle` passed
  - Rust host unit and doc tests passed
  - `just counter-universal-refinement-smoke` passed
  - `git diff --check` passed
- Limitation: generated SDK code is executed natively through `TestVM`; the
  compiled Wasm artifact is not yet executed against a Nitro-compatible HostIO
  runner. Executable Wasm differential evidence remains required before
  canonical renderer cutover.

## 2026-07-12 - Stylus Task 7 checkpoint: research source bundle route

- Status: `in_progress`
- Commits: registry boundary `bf137824`; source bundle pending this checkpoint
- Result: registered `wasm-arbitrum-stylus` at research maturity without
  primary-triad promotion and opened a native `contract_source` build route.
  The route hydrates optional selectors from complete Solidity ABI signatures,
  builds the checked canonical `StylusPlan`, atomically packages the pinned Rust
  SDK crate, and writes an honest ArtifactBundle with content SHA-256 and byte
  sizes.
- Honesty: the source route records Rust and cargo-stylus stages as unavailable,
  has no `finalOutput`, and does not create or advertise Wasm/deploy artifacts.
- Verification:
  - `just stylus-public-route` passed, including the literal CLI build
  - artifact JSON parsed; selectors and source digests matched disk
  - `just test-equivalence` passed (110 recipes)
  - `git diff --check` passed
- Remaining: Solidity ABI and TypeScript client sidecars, compiled Wasm/tool
  evidence, deploy JSON, and full Task 7 documentation/route promotion.

### Task 7 artifact checkpoint

- Added Solidity ABI and TypeScript EVM-compatible client sidecars derived
  from the hydrated source contract.
- The CLI now compiles the pinned Rust SDK crate with Rust `1.91.0` for
  `wasm32-unknown-unknown`, records the Wasm hash/size as an intermediate
  output, and deletes its temporary Cargo target directory.
- Added a non-broadcast deploy manifest with null address/transaction fields
  and `activationValidation=notRun`. The ArtifactBundle deliberately retains
  `finalOutput=null` until cargo-stylus activation validation is executed.
- Remaining Task 7 issue: publish all sidecars and metadata through one atomic
  directory rename; the crate itself is atomic, but later sidecar failure can
  currently leave a partial output directory.

### Task 7 completion

- Status: `done`
- The public route now writes every crate file and sidecar into a private
  same-parent staging directory. Only after Rust/Wasm compilation, metadata
  hashing, bundle honesty validation, and deploy-manifest generation succeed
  is the directory renamed to the requested final output.
- A failed pre-publication step cannot expose a partial final directory; an
  existing final output is rejected rather than overwritten.

## 2026-07-12 - Stylus Task 8: Direct Wasm storage substrate

- Status: `done`
- Result: added plan-selected `vm_hooks` imports for 32-byte storage load,
  cache, and flush; bounded one-page scratch layout; fixed 32-byte big-endian
  word conversion; packed-field masked updates; and ABI-padded mapping-slot
  preimage construction with an injected Keccak boundary.
- Fail-closed behavior: inconsistent duplicate imports, zero-page memory,
  overlapping/out-of-page scratch regions, malformed words, and packed fields
  outside a word are rejected before module emission.
- Verification:
  - `just stylus-direct-storage` passed
  - emitted WAT compiled with `wat2wasm`
  - Rust host replayed the packed-field preservation vector
  - exact `vm_hooks` signatures and absence of NEAR/Soroban imports were pinned
  - U256 max and mapping preimage vectors passed
- Limitation: the mapping helper owns preimage layout and accepts a Keccak
  implementation boundary; concrete direct-Wasm Keccak HostIO lowering belongs
  to the mapping/event slice.

## 2026-07-12 - Stylus Task 9: Direct Solidity ABI dispatcher

- Status: `done`
- Result: added deterministic selector extraction/dispatch, calldata word
  bounds, canonical uint/bool/address/fixed-bytes validation, static return-word
  validation, and stable revert bytes for truncated, unknown, non-canonical,
  and unsupported inputs.
- Completeness: dynamic bytes/string/arrays and recursively dynamic aggregate
  types fail before module emission. Their malformed offset/tail vectors are
  retained for the later aggregate slice; no empty-result fallback exists.
- Evidence:
  - Foundry `cast` / Alloy ABI selectors match the Rust SDK and direct plan
  - the generated direct selector function executes successfully in the Lean
    Wasm interpreter for every Counter method
  - unknown/truncated selectors and non-canonical bool/address values fail
  - U256 max is accepted and exact static words remain 32 bytes
  - emitted dispatcher WAT compiles with `wat2wasm`
  - `just stylus-direct-abi` passed

## 2026-07-12 - Stylus Task 10: Direct Wasm Counter renderer

- Status: `done`
- Result: added plan-only CFG/SSA lowering from validated `StylusPlan` to the
  shared Wasm AST. The Counter fragment covers scalar literals and locals,
  checked/wrapping add, acyclic jump/branch control flow, byte-exact big-endian
  storage load/cache, explicit cache flush, ABI result/revert writes, and
  deterministic status returns. Cyclic CFGs and unsupported scalar widths fail
  with target/function/block/op/capability/renderer diagnostics.
- Differential evidence: an independent selector-driven direct model matches
  abstract Counter HostIO traces for initial read, a large stored value,
  increment, overflow rollback, unknown selector, and malformed calldata.
- Verification:
  - `just stylus-counter-differential` passed three consecutive runs
  - generated Counter WAT compiled with `wat2wasm` on every run
  - `runtime/stylus-host` tests passed
  - `just stylus-direct-storage`, `just stylus-direct-abi`, and
    `just stylus-counter-lifecycle` passed
- Limitation: the direct Wasm is compile-validated but has not executed against
  a target-native Stylus `vm_hooks` host. It is not deployment evidence, and
  the public artifact route remains on the pinned Rust SDK bootstrap renderer.

## 2026-07-12 - Stylus Task 11 checkpoint: context and rollback foundation

- Status: `in_progress`
- Plan correction: the repository's product `ValueVault` is a six-field,
  five-event ledger using checkpoint context and additional arithmetic. It is
  not the owner/payable fixture described by the Stylus design. The product
  contract therefore remains fail-closed until its events and arithmetic are
  covered; this checkpoint implements the target-level ValueVault security
  slice without claiming product-route support.
- Result: added exact Stylus `vm_hooks` imports and WAT wrappers for 20-byte
  sender/contract addresses, 32-byte message value, and `i64` block
  number/timestamp. NEAR context names are explicitly excluded.
- Semantics: pinned authorized deposit/withdraw, zero and excess value policy,
  nonpayable rejection, insufficient balance, block context preservation,
  exact revert bytes, state rollback, discarded pending writes, and one flush
  on successful state transitions.
- Verification:
  - `just stylus-value-vault-differential` passed three consecutive runs
  - generated context WAT compiled with `wat2wasm` on every run
  - `runtime/stylus-host` tests passed
  - `just stylus-counter-differential` remained green
- Remaining before Task 11 completion: represent context-read, comparison, and
  authorization assertions in `StylusPlan`; lower them in both renderers; bind
  payable policy to canonical functions; and execute the generated direct WAT
  against a Stylus-compatible `vm_hooks` host.

## 2026-07-13 - Stylus Task 11 checkpoint: plan-owned authorization

- Status: `in_progress`
- Result: extended `StylusPlan` with context reads, typed comparisons, and
  assertions. Canonical Core now preserves those operations, derives ABI
  payable policy from per-function `msg.value` reads, and records nonpayable
  `msgValue` checks as explicit HostOps.
- Direct renderer: lowers 20-byte address storage/sender equality, scalar
  comparisons, deterministic assertion reverts, and a full 32-byte nonpayable
  value prologue. The generated authorization module compiles with `wat2wasm`.
- Rust SDK oracle: consumes the same context/compare/assert plan, emits
  `self.vm()` context access, `#[payable]` when inferred, and typed `Result`
  rejection. The generated authorization crate compiles under Rust `1.91.0`
  with `stylus-sdk = "=0.10.8"` and `stylus-test`.
- Verification:
  - `just stylus-value-vault-differential` passed three consecutive runs
  - `just stylus-counter-differential`, `just stylus-direct-storage`,
    `just stylus-rust-render`, and `just stylus-core-plan` passed
  - `cargo-stylus 0.10.8` was a named SKIP because it is not installed
- Remaining: canonical `msg.value` is `u128`; direct lowering needs an honest
  wide-value representation before payable business logic can consume it.
  Function parameters and target-native `vm_hooks` execution also remain open.

## 2026-07-13 - Stylus direct Wasm runner

- Added `tools/stylus-vm-runner`, a Wasmtime 45 executable host for the current
  direct Stylus `vm_hooks` fragment: storage load/cache/flush, result writes,
  sender/value/contract context, and block number/timestamp.
- The CLI supports multiple ordered exports plus `--sender`, `--value`,
  `--contract`, `--block-number`, `--block-timestamp`, and repeated
  `--storage SLOT=WORD` initialization. It emits deterministic JSON containing
  statuses, result bytes, committed storage, and normalized host traces.
- `just stylus-vm-runner` compiles WAT to Wasm and executes Counter
  `initialize -> increment -> get`, authorized address comparison, and
  nonpayable rejection against the bytecode.
- Boundary: this is real Wasm instantiation and execution against a local
  compatible host. It is not Nitro activation, cargo-stylus validation, live
  RPC execution, or deployability evidence.
- Follow-up: direct modules now export the official
  `user_entrypoint(args_len) -> status`, import `read_args`, dispatch Solidity
  selectors, and emit deterministic malformed/unknown-selector reverts. The
  runner accepts `--calldata` and executes this public entrypoint.
- Added optional `just stylus-official-check`, which feeds the emitted bytecode
  to `cargo stylus check --wasm-file`. Official cargo-stylus `check` owns
  instrumentation/activation validation; `simulate`/`replay` remain RPC and
  trace-driven workflows rather than replacements for the offline Wasm host.

## 2026-07-13 - Stylus Nitro local-development orchestration

- Added a pinned official Nitro Testnode manager with install, destructive
  first-time init, non-destructive restart, RPC wait/status, shutdown, and
  local dev-key generation. Revision
  `62f6cae30942f82958695697d3de8b4e1447ea7f` is explicit because upstream warns
  that its `release` branch may be force-pushed.
- Added local `cargo stylus check --wasm-file`, deploy/activate, and Counter ABI
  E2E scripts against `http://127.0.0.1:8547`, plus a separately guarded
  Sepolia workflow requiring an explicit private-key path. No automatic
  mainnet deployment command exists.
- Verification: `cargo-stylus 0.10.8` was installed under Rust `1.91.0`; the
  pinned Nitro chain initialized with L2 chain ID `412346`; `just
  stylus-nitro-check` accepted the 810-byte direct Wasm; and `just
  stylus-nitro-e2e` deployed and activated it before executing `initialize`,
  `increment`, and `get` through Solidity ABI and observing `1` on-chain.
- Follow-up repair: cargo-stylus 0.10.8 loads Cargo and `Stylus.toml` metadata
  even for `--wasm-file`, so the scripts now execute inside an isolated empty
  workspace rather than pretending the direct artifact belongs to the Rust
  oracle. Deployment-address parsing strips cargo-stylus ANSI formatting, and
  the E2E script supplies the documented Foundry path in non-interactive shells.
- Added `just stylus-nitro-doctor`, which emits stable JSON for the pinned Rust
  and cargo-stylus versions, Docker, Foundry, Testnode revision, RPC endpoint,
  and chain ID. Docker/RPC probes are bounded to five seconds and a partial
  environment returns `ready=false` with a nonzero status instead of hanging.

## 2026-07-13 - Stylus Task 11 checkpoint: static scalar parameters

- Status: `in_progress`
- Added plan-owned ABI parameter identity (`valueId`, source name, and ABI
  type), with validation that each function exactly matches its ABI method and
  owns unique SSA parameter ids. The canonical Core builder now preserves this
  contract instead of leaving renderers to reconstruct it.
- Rust SDK rendering emits named public parameters and explicitly binds them to
  the plan SSA locals consumed by operations. Direct Wasm emits typed internal
  parameters, validates exact calldata length and canonical zero padding,
  decodes static `bool`/`u8`/`u32`/`u64` words, and passes values through the
  public `user_entrypoint` dispatcher. Wider values fail closed.
- Verification: `just stylus-scalar-params` compiled WAT and executed
  `echo(uint64)` through the Wasmtime `vm_hooks` runner, returning ABI-encoded
  `42`; an adversarial word with nonzero high padding reverted. Core plan, Rust
  render, direct ABI, diagnostics, Counter differential, and ValueVault
  differential gates passed.
- Remaining: represent `u128`/`U256` values without i64 truncation, then consume
  `msg.value` in payable ValueVault business logic and prove it on Nitro.

## 2026-07-13 - Stylus Task 11 checkpoint: direct u128 value representation

- Status: `in_progress`
- Direct Wasm now represents `uint128` as a pointer to a checked 16-byte
  big-endian memory value. Static ABI parameters point into the copied calldata
  word; `msg.value` points into the low half of its official 32-byte HostIO
  buffer after rejecting any nonzero high half. ABI returns copy all 16 bytes
  into the low half of the result word without i64 truncation.
- Rust SDK rendering now converts the SDK's `U256` message value explicitly via
  `.to::<u128>()`. The generated Rust oracle compiles with pinned Rust 1.91.0,
  stylus-sdk 0.10.8, and the `stylus-test` host.
- Verification: `scripts/stylus/wide-values.sh` round-tripped
  `18446744073709551658` through both `echo128(uint128)` calldata and
  `msg.value`, rejected a 129-bit value with exact revert bytes, compiled the
  direct WAT, executed it under the Wasmtime runner, and compiled the Rust
  oracle. `uint128` equality is bytewise; unsupported ordering remains a named
  failure instead of comparing pointers.
- Remaining: checked/wrapping u128 arithmetic, ordering, literal materialization,
  and storage words are required before payable ValueVault business logic can
  move to the public artifact route and Nitro E2E.

## 2026-07-13 - Stylus Task 11 checkpoint: u128 arithmetic and storage

- Status: `in_progress`
- Added stable per-SSA scratch allocation for materialized `uint128` results,
  16-byte big-endian literals, full-word storage load/cache, and bytewise
  addition with explicit carry propagation. Checked addition returns the same
  deterministic overflow bytes before any cache flush; wrapping addition
  discards only the final carry.
- Verification: `just stylus-wide-arithmetic` executed a balance above `u64`,
  added an ABI `uint128`, persisted and returned the exact 128-bit result,
  proved `2^128 - 1 + 1` rolls back in checked mode, proved the same operation
  stores zero in wrapping mode, and returned an above-u64 literal. All cases ran
  as compiled Wasm under `tools/stylus-vm-runner`.
- Remaining: unsigned `uint128` ordering and scratch-bound validation, followed
  by the complete payable ValueVault plan and Nitro deployment gate.

## 2026-07-13 - Stylus completion Task 1: u128 ordering and scratch bounds

- Status: `done`
- Added checked wide scratch allocation using the plan's declared memory pages.
  A wide literal/add/storage result whose stable scratch end exceeds the Wasm
  limit now fails before module emission with `capability=memory.scratch` and
  target/function/block/value diagnostics.
- Added unsigned big-endian `uint128` ordering without pointer comparison.
  `lt/le/gt/ge` scan from the most significant byte, stop on the first unequal
  byte, and handle equality explicitly for inclusive predicates.
- Verification: wide-value runtime vectors cover high-word ordering, low-word
  ordering, equality, values above `u64`, and 129-bit rejection. The arithmetic
  gate covers literal/storage, checked rollback, and wrapping overflow. Task 1
  now hands off to the canonical ValueVault/Nitro closure.

## 2026-07-13 - Stylus canonical product ValueVault execution

- Status: `done (local VM); Nitro deployment pending`
- Replaced the hand-authored same-name fixture as the completion criterion with
  `ProofForge.IR.Examples.ValueVault` through `adaptLegacy -> canonical Core ->
  StylusPlan`. The plan retains all seven entrypoints, six state words, and five
  events.
- Added checked scalar subtraction, multiplication, and division to both
  renderers; Rust result-returning functions now use `Result<T, Vec<u8>>` when
  their body can fail.
- Added plan-owned scalar event operations. Direct Wasm uses the official
  `native_keccak256` and `emit_log` hooks; the local runner implements and traces
  both hooks with bounds/topic validation.
- `just stylus-value-vault-canonical` executes initialize, fee charging,
  release, and net-value vectors in direct Wasmtime and compiles the generated
  Rust SDK crate with `stylus-test`. Nitro activation remains the next gate.
- Added `stylus-value-vault-nitro-e2e`, which regenerates the canonical Wasm,
  runs the official check/deploy path, executes initialize/charge/release with
  `cast`, validates balance/net value, and writes ignored JSON evidence. Script
  self-tests pass; live execution is currently blocked only by the unavailable
  local Docker daemon/RPC.

## 2026-07-13 - Stylus mapping slots and indexed scalar events

- Status: `done for single-key static maps/events; nested allowance layout pending`
- Added Plan-owned mapping key types and storage-path operations. Core preserves
  the key SSA id; direct Wasm executes the planned `keccak256(paddedKey ||
  baseSlot)` envelope and Rust renders the same plan as `StorageMap` access.
- Foundry-backed runtime vectors cover `uint64 -> uint64` and `address ->
  uint128`, including a value above u64. Direct storage slots/results match the
  generated Rust crate's SDK types.
- Added indexed scalar event layout with topic0, indexed words, and data words.
  Validation enforces the four-topic limit and rejects dynamic indexed/key
  values unless a future plan pass supplies a pre-hash.

## 2026-07-13 - Stylus aggregate ABI layout foundation

- Status: `foundation complete; aggregate carrier/lowering pending`
- Added renderer-neutral dynamic ABI layout validation with explicit head
  arity, argument index, aligned tail offset, payload length, padded end, and
  maximum length.
- Adversarial vectors reject offsets inside the static head, unaligned offsets,
  missing length words, truncated padded tails, and configured-length
  exhaustion. Empty and non-word-aligned string payloads are accepted with
  deterministic slices.
- Confirmed the next architectural change must represent dynamic values as a
  plan-owned pointer/length carrier before remote calls consume them.

## 2026-07-13 - Stylus bounded bytes/string carriers

- Status: `done for ABI parameters/returns; literals, arrays, tuples, and storage pending`
- Extended function parameter plans with an explicit dynamic maximum. Direct
  Wasm expands dynamic SSA parameters into pointer/length arguments; Rust keeps
  native `Vec<u8>` and `String` signatures from the same plan.
- The dispatcher validates word-aligned offsets, head separation, length-word
  bounds, configured maximums, padded tail bounds, and complete calldata before
  invoking contract code. The parameter-specific maximum is read from the plan
  rather than a renderer constant.
- Dynamic return encoding emits the canonical offset/length/padded-data shape.
  Runtime vectors cover empty bytes, `hello`, UTF-8 text, unaligned offsets,
  truncated tails, and over-limit payloads; rejected calls return deterministic
  malformed-calldata bytes before contract execution.

## 2026-07-13 - Stylus dynamic literals and canonical call envelopes

- Status: `plan complete; HostIO lowering pending`
- Added bounded bytes/string literal carriers with checked 256-byte scratch
  regions, explicit pointer/length locals, Rust literal rendering, and pre-emit
  page-bound diagnostics.
- Canonical crosscalls now produce plan-owned envelopes containing mode, target,
  method slice, typed argument ids/types, optional value/gas, and return type.
  The real product RemoteCall produces nullary and two-u64 envelopes without a
  target-specific frontend fixture.
- Direct/Rust call execution remains fail-closed with named diagnostics until
  official HostIO buffer, return-data, and cache-transition lowering lands.
- Targeted Stylus builds and aggregate runtime gates pass. The repository-wide
  build is temporarily blocked by the concurrent NEAR `nearPromiseResultU128`
  addition missing exhaustive cases in shared non-Stylus modules.

## 2026-07-13 - Stylus direct remote-call HostIO foundation

- Status: `done for static args/u64 return/value calls; advanced lifecycle pending`
- Added the pinned official `call_contract`, `static_call_contract`,
  `delegate_call_contract`, and `read_return_data` imports. Direct lowering
  hashes the plan-owned canonical signature, emits the selector and static ABI
  words, applies optional gas, and validates a 32-byte u64 result.
- Callee failure copies and returns the exact revert payload. Oversized and
  malformed successful return data fail closed with named diagnostics.
- The VM runner now accepts deterministic `--mock-call ADDRESS=STATUS:HEX`
  bindings and traces target, calldata, value, gas, status, and return bytes.
  Runtime vectors cover all three modes, two-u64 calldata, success, revert,
  and a uint128 call value above the uint64 range.
- `StylusCallPlan` now preserves the canonical value type alongside its value
  id. Strict validation admits only uint64/128/256 values on ordinary call mode;
  static/delegate values and unsupported value types fail before rendering.
- Direct Wasm encodes call values as full 32-byte big-endian words. The runner
  trace locks the uint128 vector `0x0000000000000001000000000000002a`, proving
  that high bits survive the HostIO boundary.
- The real `Examples.Product.RemoteCall` passes canonical envelope assertions;
  the direct executable vectors use the same plan contract without depending
  on Nitro. Dynamic returns, reentrancy/cache transitions, and two-contract
  Nitro execution remain pending.

## 2026-07-13 - Stylus plan-owned external-call cache policy

- Status: `pre-call policy done; nested invocation frames pending`
- Added `StylusCachePolicy` to every call envelope. Canonical lowering follows
  the pinned Stylus SDK reentrant rules: static calls use `flush`, while call
  and delegate call use `clear` before crossing HostIO.
- Strict validation rejects missing or mode-incompatible policies and requires
  a `storageFlush` HostOp for every function containing an external call.
- Direct Wasm emits `storage_flush_cache(0)` immediately before static HostIO
  and `storage_flush_cache(1)` immediately before call/delegate HostIO. Runtime
  traces lock both the ordering and clear flag.
- Corrected terminal flushing: a function now flushes on successful return only
  when its CFG actually caches a storage write. Merely importing storage flush
  for call safety no longer causes a redundant post-call flush.
- Scope boundary: nested caller/callee frames and transaction-level rollback
  remain pending. Callee failure does not by itself discard caller state; caller
  state rolls back only when the caller frame also reverts.

## 2026-07-13 - Stylus runner nested invocation frames

- Status: `local nested-frame evidence done; Nitro two-contract evidence pending`
- Added `--mock-reentrant ADDRESS=CALLDATA` to the Wasmtime runner. A matching
  `call_contract` invokes the same module's `user_entrypoint` in a nested frame
  with callee-address sender identity, zero callback value, and callback-owned
  calldata, then restores the outer sender/value/calldata/result context.
- Frame snapshots separate transaction rollback from cache policy. Successful
  callbacks preserve flushed storage; reverted callbacks restore storage and
  cache to the frame-entry snapshot while returning the exact callback revert
  payload to the outer call.
- Top-level exports now snapshot storage/cache and restore both on nonzero
  status. The third vector lets a callback commit `seen = 42` and then makes the
  outer frame revert; the final state is empty, matching whole-call-tree EVM
  rollback rather than retaining an inner flush.
- Added `ReentrantDirect`: the success callback caches and commits `seen = 42`;
  the failing callback caches `seen = 99` and reverts. Runtime assertions lock
  frame enter/exit identity, outer-context restoration, success persistence,
  failed-frame isolation, and revert propagation.
- The runner enforces a deterministic maximum nesting depth of 16. This is
  local execution evidence, not a substitute for the pending Nitro two-contract
  reentrancy scenario.

## 2026-07-13 - Stylus remote-call gas and return-data bounds

- Status: `static u64 return boundaries done; dynamic ABI returns pending`
- Extended the direct runtime fixture with an explicit gas parameter and locked
  that gas `12345` reaches `call_contract` unchanged.
- Added empty-success and oversized-success vectors. A successful call returning
  zero bytes fails as malformed for the declared u64 result; a 4097-byte result
  fails with `stylus: return data exceeds limit` before any return-data copy.
- These vectors close evidence gaps around the existing bounded static-return
  implementation. Dynamic bytes/string results remain separate because they
  must decode the callee's Solidity ABI offset/length/padded tail rather than
  treating raw return bytes as a dynamic value.

## 2026-07-13 - Stylus bounded dynamic remote-call returns

- Status: `direct bytes/string ABI returns done; Rust/Nitro parity pending`
- Added plan-owned `returnMaxLength?` to call envelopes. Strict validation
  requires a 1..4096 maximum for dynamic returns, rejects a maximum on static
  returns, and canonical Core assigns 4096 to dynamic crosscall results.
- Direct Wasm now decodes callee bytes/string results as Solidity ABI rather
  than raw bytes: the envelope must have at least two words, offset exactly 32,
  a length word with a zero high prefix, payload within the plan maximum, exact
  `64 + ceil32(length)` total size, and all padding bytes zero.
- The decoded payload becomes the normal dynamic SSA pointer/length pair and is
  re-encoded through the existing caller ABI return path. Runtime vectors cover
  empty bytes, `hello`, bad offset, truncated padding, nonzero padding, and a
  65-byte payload rejected by a 64-byte plan limit.
- Return scratch is cleared before copying, so a shorter later response cannot
  observe or be rejected because of bytes left by an earlier call.

## 2026-07-13 - Stylus full-integration audit and aggregate regression repair

- Status: `26/63 plan items complete; seven work packages remain`
- Added `docs/review/stylus-full-integration-gap-2026-07-13.md` with verified
  evidence, honest completion estimates, seven remaining packages, environment
  blockers, and the compiler-to-release critical path.
- Re-ran canonical ValueVault and mapping/event gates successfully. The aggregate
  gate exposed a regression from dynamic call-return work: a fixed 4096-byte
  result clear overlapped calldata-backed dynamic parameters and zeroed payloads.
- Added `dynamicReturnMaximum`, which derives the clear bound from the returned
  function parameter or producing call envelope. Both aggregate echo vectors and
  remote dynamic-return vectors pass after the repair.

## 2026-07-12 - TOOL-NEAR-VM-RUNNER: honest real-NEAR-VM conformance gate

- Status: `done (uncommitted; pre-existing product-matrix Soroban failure unrelated)`
- Result: turned `tools/near-vm-runner` from a false-success placeholder into a
  real, honest conformance gate. The Counter fixture (legacy + canonical
  pipelines) now prepares, links, and executes on the *unmodified upstream*
  NEAR VM (near-vm-runner 0.37 / Wasmtime): after `initialize + increment*2`,
  `get` returns `0200000000000000` (LE u64 = 2) with real gas accounting and
  persistent storage across calls. The runner inspects `outcome.aborted`
  (previously ignored, masking every failure as success) and threads
  `storage_usage` across calls so storage-eviction accounting does not
  underflow on the second write.
- Root causes fixed in EmitWat codegen:
  1. **Multi-value returns**: `__pf_u128_{add,sub,mul}` used `(result i64 i64)`,
     but the NEAR VM validator disables `multi_value`, so every NEAR contract
     failed `Prepare` with `PrepareError::Deserialization`. Helpers are now void
     and stash (lo, hi) into a new registered, machine-checked non-overlapping
     `U128_RESULT_BUF`; callers reload both words after the call.
  2. **`storage_remove` ABI**: declared `(param i64 i64)` but real NEAR is
     `(key_len, key_ptr, register_id) -> u64` (3 params). Wasmtime links all
     imports, so the unused import still failed linking. Fixed in `HostBridge`,
     the `Map.lean` call site, and the `runtime/offline-host` handler.
- Verification (all passed): `just near-vm-conformance` (new gate),
  `bash scripts/canonical/near-parity.sh` (legacy==canonical offline-host
  parity incl. ValueVault inputs), `just portable-counter-multi-target`,
  `bash scripts/portable/value-vault-smoke.sh`, `just wasm-near-scalar-safety`
  (exercises u128 helpers), `just value-vault-wasm-refinement-smoke`,
  `just near-budget-honesty`, `just wasm-near-host-smoke`, `just near-ft-security`,
  `just emitwat-aggregate-abi`, `just near-plan-smoke`. Independent
  wasmparser validation confirms the regenerated wasm is valid under NEAR's
  feature set (`multi_value=false`).
- Pre-existing (not caused by this change): `just product` fails in
  `Tests/Product/Matrix.lean` at `OwnableHash Soroban: ... scalar _get ABI`;
  reproduced on the clean tree with these changes stashed.
- Remaining: `promise_create` (8 vs 9 params) and `promise_then` (9 vs 10) host
  imports still use ProofForge's simplified amount-as-pointer convention and
  will not link on the real NEAR VM; promise fixtures are therefore out of the
  conformance gate's scope until the promise ABI migrates to real NEAR. The
  runner documents this gap; it only asserts the no-input Counter fixture.
- Documentation: `docs/implementation-log.md` (this entry); runner header
  comments; `scripts/near/vm-conformance-smoke.sh`; `justfile` target added to
  `wave-t-baseline` and `check-serial`; updated the four
  `Examples/Backend/WasmNear/*.golden.wat` fixtures to the corrected
  `storage_remove` signature.

## 2026-07-13 - GATE-NEAR-VM-PRODUCT: real product source on the real NEAR VM

- Status: `done (verified by `just near-vm-conformance-product`)`
- Result: closed the real product loop. The sibling `near-vm-conformance` gate
  emits the minimal IR fixture (`ProofForge.IR.Examples.Counter`) via the
  internal `Tests/Canonical/Emit.lean` harness. This new gate compiles the
  **product author source** (`Examples/Product/Counter.lean`, the
  `contract_source` DSL surface) through the **public CLI**
  (`proof-forge build --target wasm-near`) and runs the CLI-emitted `counter.wasm`
  deploy artifact on the unmodified upstream NEAR VM. After
  `initialize + increment*2`, `get` returns `0200000000000000` (LE u64 = 2,
  ~71.1 Tgas), proving the *authoring surface* — not just the IR fixture —
  lowers to NEAR-VM-executable Wasm. The CLI's `writeWatPackage` runs
  `wat2wasm` internally and fails hard on a missing assembler (PF-P0-08), so
  the script runs the CLI's own `.wasm` directly rather than re-assembling.
- Verification: `just near-vm-conformance-product` (passed; get=2). WAT parity
  between the product output and the IR-fixture golden is already asserted by
  `scripts/portable/counter-multi-target.sh`.
- Documentation: `docs/implementation-log.md` (this entry);
  `scripts/near/vm-conformance-product.sh`; `just near-vm-conformance-product`
  added to `wave-t-baseline` and `check-serial`.

## 2026-07-13 - GATE-NEAR-VM-FT: NEP-141 FT (storage_remove + full promise ABI) on the real NEAR VM

- Status: `done (verified by `just near-vm-conformance-ft`)`
- Motivation and corrected premise. The 2026-07-12 entry's "Remaining" claimed
  `promise_create`/`promise_then` use an 8/9-param simplified ABI that "will
  not link on the real NEAR VM" pending a 9/10-param migration. Empirical
  re-verification disproved this: real NEAR (`near-vm-logic`) `promise_create`
  is **8** params and `promise_then` is **9** — exactly what ProofForge emits
  (`HostBridge.hostFunctions`, `contract.wat`, and the FT module's import
  section all confirm 8/9). A module importing `promise_create` links and
  executes on the unmodified upstream NEAR VM. The 9/10-param migration was a
  non-task; it would have broken conformance.
- Real blocker found and characterized. The FT module *did* link-fail on the
  real VM, but with `LinkError: storage_remove (param i64 i64) vs (i64 i64 i64)`
  — a **stale 2-param artifact** predating the 2026-07-12 `storage_remove`
  fix (the codegen in `HostBridge.lean` + `Map.lean` was already 3-param).
  This was masked because `near-vm-conformance` only ran Counter, which never
  imports `storage_remove`. Regenerating the FT module produced a 3-param
  `storage_remove` and it linked and executed.
- Result. Extended `tools/near-vm-runner` with per-method Borsh `input`
  injection (`--input-hex` / `--inputs-hex`) and `promise_result` injection
  (`--promise-result-u64`), mirroring `runtime/offline-host` conventions but
  driving the REAL `promise_results_count` / `promise_result` host functions.
  Added `scripts/near/vm-conformance-ft.sh` (`just near-vm-conformance-ft`),
  which compiles the NEP-141 FT module and runs two phases on the unmodified
  upstream NEAR VM:
  - Phase 1 (host-ABI link + execute): `init` + `ft_total_supply` (no input)
    proves the full host surface — `storage_remove` plus the complete promise
    ABI — resolves against real near-vm-logic; `ft_total_supply` reads 0.
  - Phase 2 (semantic + callback dispatch): the full `ft_transfer_call` +
    `ft_resolve_transfer` flow with Borsh inputs and one injected
    `PromiseResult::Successful`. `ft_transfer_call` returns a receipt
    (promise created); `ft_resolve_transfer` reads it via the REAL
    `promise_result` host function and computes refund U64 = 45, matching
    `runtime/offline-host` exactly (sender 55, receiver 45).
- Scope. This is a conformance approximation: receipts are not scheduled and
  the peer contract is not executed — only the callback-side read is
  validated against the real VM. It does not cover real trie-backed
  `External`, live fee/protocol-version drift, or public deploy.
- Verification (all passed): `just near-vm-conformance-ft` (both phases);
  `python3 scripts/test-framework/manifest.py --check` (113 recipes, 4 lanes);
  `python3 scripts/test-framework/check_equivalence.py` (113 recipes) — the
  latter also fixed a pre-existing drift where `near-vm-conformance` and
  `near-vm-conformance-product` were in `check-serial` but absent from
  `scripts/test-framework/lanes.json`.
- Documentation: `docs/implementation-log.md` (this entry, and it supersedes
  the 2026-07-12 "Remaining" promise-ABI claim);
  `docs/validation-gates.md` + `docs/zh/validation-gates.zh.md` (new row);
  `README.md` + `docs/zh/README-root.zh.md` (wasm-near backend status);
  `just near-vm-conformance-ft` added to `wave-t-baseline`, `check-serial`,
  and `scripts/test-framework/lanes.json` (`serialCoverage` + `recipes`,
  lane `wasm-other-exclusive`).

## 2026-07-13 - GATE-NEAR-VM-U128: U128 scalar round-trip on the real NEAR VM (NEP-141 foundation)

- Status: `done (verified by `just near-vm-u128-scalar`)`
- Context. NEP-141/145 interop is a multi-wave effort (Wave-N `N-01`→`N-04`,
  blocked on Wave-F `F-01`/`F-02`, all `pending`). User chose the NEAR-local
  minimal-evidence path. Investigation found the portable IR already declares
  `.u128` (`ValueType`, 16-byte, `isPackedScalar`) and the legacy EmitWat path
  already had U128 arithmetic (`__pf_u128_add/sub/mul/eq`) plus a return helper
  — but the path was **incomplete and inconsistent**, so no U128 value had ever
  round-tripped end-to-end:
  - `__pf_read_u128` / `__pf_write_u128` were *referenced* by the scalar
    storage lowering but never defined (wat2wasm: undefined function).
  - `scalarStorageHelperFuncsForModulePlan` only emitted `.u32/.u64/.bool`
    (`Scalar.lean`), and `scalarHelperType` (`Plan/Common.lean`) excluded
    `.u128`, so the survey never recorded a U128 scalar read/write.
  - `returnU128Func` consumed a pointer via `__pf_memcpy`, but U128 values flow
    as two stack words (lo, hi) — a representation mismatch.
- Result. Standardized U128 as **two i64 stack words (lo, hi)** throughout the
  legacy EmitWat path and completed the wiring:
  - `__pf_read_u128(kp, kl)` (void; stages 16 bytes at KEY_BUF) +
    `__pf_write_u128(kp, kl, lo, hi)` (void) on the NEAR register ABI.
  - `storageScalarReadInsns` special-cases `.u128` (read + reload lo/hi);
    `storageScalarWriteInsns` already fit u128 via its generic branch.
    `storageScalarAssignOp` on U128 fails closed for now (explicit read + U128
    arith + write is the supported shape).
  - `returnU128Func` now consumes (lo, hi) directly and stages RET_BUF — no
    `__pf_memcpy` dependency.
  - `scalarHelperType` admits `.u128`; the helper-emission set emits the U128
    funcs on the NEAR bridge when the plan reads/writes a U128 scalar.
- Evidence. New `U128StorageScalarProbe` IR fixture + `just near-vm-u128-scalar`
  render the probe, compile via `wat2wasm`, and run `storage_lifecycle` on the
  unmodified upstream NEAR VM. Return is `07000000000000000000000000000000` —
  the 16-byte little-endian Borsh U128 of 7. This is the foundation for NEP-141
  U128 token amounts (Wave-N `N-01`).
- Verification (all passed): `just near-vm-u128-scalar`;
  `just wasm-near-scalar-safety`; `just wasm-near-plan`; `just near-vm-conformance`
  (Counter); `just near-vm-conformance-ft` (FT, no regression);
  `manifest.py --check` + `check_equivalence.py` (114 recipes).
- Pre-existing (not caused by this change): `just product` fails in
  `Tests/Product/Matrix.lean` at `OwnableHash Soroban: ... scalar _get ABI`
  (Soroban 32-byte Hash storage is incompatible with the scalar `_get` ABI);
  documented in the 2026-07-12 entry and unrelated to U128.
- Scope / next. This proves U128 scalar storage + Borsh return on the real VM
  only. Follow-on increments: U128 scalar `assignOp`; U128 map values; U128
  Borsh input decode; and the full `NearFungibleToken` U128 amount conversion
  (Wave-N `N-01`→`N-03`), then AccountId-string keys (`F-02`) and JSON codecs
  for wallet-facing interop.
- Documentation: `docs/implementation-log.md` (this entry);
  `docs/validation-gates.md` + `docs/zh/validation-gates.zh.md` (new row);
  `just near-vm-u128-scalar` added to `wave-t-baseline`, `check-serial`, and
  `scripts/test-framework/lanes.json` (`serialCoverage` + `recipes`, lane
  `wasm-other-exclusive`).

## 2026-07-13 - GATE-NEAR-VM-U128-ASSIGNOP: U128 scalar assignOp + comparison on the real NEAR VM

- Status: `done (verified by `just near-vm-u128-scalar`)`
- Result. Extended the legacy EmitWat U128 path (two i64 stack words, lo/hi)
  with scalar `assignOp` and unsigned comparison, both proven on the
  unmodified upstream NEAR VM:
  - U128 scalar `assignOp` (add/sub): read (lo,hi) + value (lo,hi) +
    `__pf_u128_add`/`sub` (void, → U128_RESULT_BUF) + reload + write. The
    stack discipline reserves the write's (kp, kl) under the arith operands.
  - U128 unsigned comparison: added `__pf_u128_lt(alo,ahi,blo,bhi) -> i32`
    (`a<b` iff `ahi<bhi || (ahi==bhi && alo<blo)`); wired `lowerCmp` so
    lt_u→u128_lt, ge_u→u128_lt+eqz, gt_u→swapped u128_lt, le_u→swapped+eqz.
    `u128LtFunc` joins the always-emitted `u128ArithFuncs` bundle.
- Evidence. `U128StorageScalarProbe` grew two entrypoints; `just
  near-vm-u128-scalar` now runs three on the real VM: `storage_roundtrip`
  (u128 7), `storage_lifecycle` (write 7 + `assignOp add 5` → returns u128 12),
  `storage_ge` (`assignOp add 5` then `read >= 10` → bool 1).
- Discovered boundary (next increment). U128 values bound to a Wasm local via
  `let` are still single-word (`wasmTypeOf .u128 = i64`): `local.set` drops the
  high word, and `assertEq`/comparisons on a let-bound u128 degrade to one-word
  `i64.eq`. The proven paths keep u128 on the stack (read→return, read→arith→
  write, read→compare→bool). A two-word-local representation is required before
  `NearFungibleToken` can `let srcBal := mapRead balances sender` with U128.
- Verification (all passed): `just near-vm-u128-scalar` (3 cases);
  `just wasm-near-scalar-safety`; `just wasm-near-plan`; `just near-vm-conformance`
  (Counter); `just near-vm-conformance-ft` (FT, no regression).
- Documentation: `docs/implementation-log.md` (this entry);
  `docs/validation-gates.md` + `docs/zh/validation-gates.zh.md` (u128 row
  updated to cover assignOp + comparison and record the let-bind boundary).

## 2026-07-13 - PLAN + Phase 1.1: U128 interop execution plan + two-word u128 locals

- Status: `done (Phase 1.1 verified by `just near-vm-u128-scalar`)`
- Planning. Wrote a unified, dependency-ordered execution plan for the
  remaining NEP-141/145 interop work at
  `docs/superpowers/plans/2026-07-13-near-nep141-interop-execution.md`. It
  operationalizes the pending Wave-N tasks (N-01→N-04) into 9 phases with
  acceptance criteria and gates, records the architectural stance (u128 /
  AccountId / JSON are NEAR-backend materialization details that do NOT
  require the portable F-01/F-02 foundations as a prerequisite), and flags
  the critical-path insight: u128 had THREE inconsistent representations
  (input params = pointer, locals = single i64, literals/arith = two stack
  words).
- Phase 1.1 (linchpin) — two-word u128 locals. Unified u128 as two i64 stack
  words (lo, hi) across the remaining surfaces so a u128 value is coherent
  end-to-end:
  - `let`-bound / mutable u128 locals occupy two wasm locals (`name` = lo,
    `name__hi` = hi); `localLetBindInsns` / `localAssignInsns` set both,
    `.local` get both, and the locals declaration allocates both.
  - u128 input params decode lo+hi directly from INPUT_BUF into the two
    locals (was: an i32 pointer to a 16-byte buffer).
  - `assertEq` on u128 dispatches to `__pf_u128_eq` (was: single-word
    `i64.eq`).
- Evidence. `U128StorageScalarProbe.storage_letbind` (write 12, `let result :=
  read`, `assert (result >= 10)` + `assertEq result 12`, return) returns u128
  12 on the unmodified upstream NEAR VM — the exact shape
  `NearFungibleToken` needs for `let srcBal := mapRead balances sender`.
  `just near-vm-u128-scalar` now runs four entrypoints (roundtrip, lifecycle
  assignOp, ge comparison, letbind).
- Verification (all passed): `just near-vm-u128-scalar` (4 cases);
  `just wasm-near-scalar-safety`; `just wasm-near-plan`; `just near-vm-conformance`;
  `just near-vm-conformance-ft`.
- Next (Phase 1.2): U128 map values (hash-keyed + u64-indexed), then Phase 2
  converts `NearFungibleToken` amounts to u128. See the execution plan.

## 2026-07-13 - Phase 1.2: U128 hash-keyed map values on the real NEAR VM

- Status: `done (verified by `just near-vm-u128-map`)`
- Result. Extended the two-word U128 model to hash-keyed map values (the
  NEP-141 `balances` / `allowances` shape: `Map<hash, u128>`):
  - `__pf_map_read_hash_u128(pp,pl,kp)` (void; stages 16 bytes at KEY_BUF,
    zeros KEY_BUF first so absent keys read as 0) + `__pf_map_write_hash_u128
    (pp,pl,kp,lo,hi)` (void) on the NEAR register ABI; plus the u64-indexed
    `__pf_map_read_u128` / `__pf_map_write_u128` for `Map<U64, U128>`.
  - `mapReadValueInsns` reloads lo/hi from KEY_BUF after the void read;
    `mapWriteValueInsns` returns Unit for U128 (the write cannot return the
    prior value as two words under NEAR's no-multi-value rule), and the bare
    `storageMapSet` effect skips the drop for Unit. (The FT discards the prior
    value, so this matches its usage.)
  - Emission emits the U128 variants on the NEAR bridge instead of the
    single-word map funcs; `scalarHelperType` already admitted U128, so the
    survey collects U128 map value types with no extra change.
  - Latent fix: `withHashIndexedReadType` / `withHashIndexedWriteType` now set
    `usesMemcpy := true` (the buildkey-hash helper copies the 32-byte key with
    `__pf_memcpy`); previously a hash-keyed map without events omitted memcpy
    and failed to link (masked in the FT by its event emissions).
- Evidence. New `U128MapProbe` + `just near-vm-u128-map`: write u128 100 at a
  hash key, read back, return → `64000000000000000000000000000000` (u128 100)
  on the unmodified upstream NEAR VM.
- Verification (all passed): `just near-vm-u128-map`; `just near-vm-u128-scalar`;
  `just wasm-near-plan`; `just near-vm-conformance-ft`; `just near-vm-conformance`;
  `just emitwat-aggregate-abi`; `just near-map-hash-alias`;
  `manifest.py --check` + `check_equivalence.py` (115 recipes).
- Next (Phase 2): convert `NearFungibleToken` amounts u64→u128.

## 2026-07-13 - Phase 1.3/1.4: u128 literal sugar + decimal formatter + event/crosscall u128

- Status: `done (verified by `just near-u128-fmt-smoke`)`
- Result. Completed the u128 plumbing the FT conversion needs across events and
  crosscall args, plus the key JSON U128 primitive:
  - `Builder.u128` / `Surface.u128` literal sugar (mirror u64) — unblocks FT
    amount authoring (`u128 0`, `u128 18`).
  - `__pf_u128_divmod10(alo, ahi) -> rem` (4-limb long-division by 10, no i128
    needed) + `__pf_fmt_u128(alo, ahi) -> ptr` (writes the unsigned decimal
    string backwards into RET_BUF). The JSON U128 decimal primitive, shared by
    event fields, crosscall args, and (Phase 4) JSON view returns.
  - `__pf_evt_putu128(lo, hi)` + `evtValueInsnsForType` `.u128` dispatch +
    `eventFieldSurfaceForType` admits `.u128` to `usesEventNumeric`.
  - `__pf_crosscall_args_putu128(lo, hi)` + the crosscall-arg type dispatch
    (`.u128`), emitted self-contained with its `__pf_fmt_u128`/divmod deps.
- Evidence. `U128FmtProbe` emits a JSON event with two u128 fields; `just
  near-u128-fmt-smoke` runs it in `runtime/offline-host` and asserts the log
  contains `"simple":100` and `"big":36893488147419103230` (the latter = 2 ×
  u64-max, exercising the high word of the divmod — proving the formatter
  correct for both lo-only and hi≠0 u128 values).
- Verification (all passed): `just near-u128-fmt-smoke`; `just near-vm-u128-scalar`;
  `just near-vm-u128-map`; `just near-vm-conformance-ft`; `just near-vm-conformance`;
  `just wasm-near-plan`; `just emitwat-aggregate-abi`; `just near-ft-security`;
  `manifest.py --check` + `check_equivalence.py` (116 recipes).
- Next: Phase 2 (NearFungibleToken u64→u128). Remaining plumbing: u128 promise
  result read (`nearPromiseResultU128`, binary) for `ft_resolve_transfer`.

## 2026-07-13 - Phase 1.3 done: nearPromiseResultU128 + full u128 surface coverage

- Status: `done (verified on real NEAR VM)`
- Result. Added the last u128 surface the FT needs — promise-result decode:
  new IR expr `nearPromiseResultU128`, `nearPromiseResultU128Sig` HostOp,
  `__pf_promise_result_u128(idx)` (void; zero-extends PROMISE_RESULT_BUF then
  reads the result register; caller reloads lo/hi), `Builder`/`Surface` sugar,
  and the legacy-adapter lowering. The new `Expr` constructor required a
  cross-backend exhaustiveness sweep (~20 match sites across EVM/Solana/Aleo/
  Psy/Wasm-host/TS/IR — each mirrors `nearPromiseResultU64`, mostly rejecting
  on non-NEAR backends).
- With this, u128 is coherent across every surface `NearFungibleToken` touches:
  params, locals, literals, arithmetic, scalar + map storage, comparison,
  Borsh return, decimal formatting (events/crosscall), and promise results.
- Evidence. `U128PromiseResultProbe.read_result` returns `nearPromiseResultU128
  0`; on the unmodified NEAR VM with `--promise-result-u64 42` it returns u128
  42 (`2a000000000000000000000000000000`).
- Verification (all passed): the promise-result probe; `near-vm-u128-scalar`,
  `near-vm-u128-map`, `near-u128-fmt-smoke`, `near-vm-conformance-ft`,
  `near-vm-conformance`, `wasm-near-plan`, `near-ft-security`,
  `portable-default`, `evm-plan`; full `lake build proof-forge` (792 jobs).
- Next: Phase 2 — convert `NearFungibleToken` amounts u64→u128 (now
  unblocked).

## 2026-07-13 - STYLUS-W1: Canonical nested mapping

- Status: `done (verified at 09579b6d)`
- Commit: `09579b6d`
- Result: added ordered composite `StateShape.mapN` keys with canonical
  validation and logical semantics, then preserved the key path through the
  Stylus plan, direct Wasm slot hashing, and nested Rust SDK `StorageMap` output.
- Interfaces: Core storage/semantics, canonical capability derivation, Stylus
  Plan/Rust renderers, and explicit fail-closed EVM/Solana plan handling.
- Verification: `just stylus-nested-map`, `lake build` (792 jobs),
  `just docs-check`, and `git diff --check` all passed. The gate executed the
  generated Wasm in `tools/stylus-vm-runner` and compiled the generated crate
  with `stylus-sdk = 0.10.8` and its `stylus-test` feature.
- Remaining: W1 still needs deployed Foundry allowance-slot evidence and full
  `Transfer` / `Approval` topic/data vectors before the package is complete.
- Documentation: updated the Stylus completion plan and full-integration gap
  audit without closing the remaining W1 event/reference criteria.

## 2026-07-13 - STYLUS-W1: Complete mapping and event layouts

- Status: `done (verified at 095ef266)`
- Commit: `095ef266`
- Result: preserved canonical event ABI-word overrides in the Stylus plan and
  pinned standard `Transfer(address,address,uint256)` and
  `Approval(address,address,uint256)` log buffers across direct Wasm and Rust.
  The repair also added address/u128 direct event encoding and moved event
  scratch away from calldata-backed wide parameters.
- Interfaces: Stylus event planning, direct-Wasm event memory/encoding, typed
  Rust event rendering, mapping/event vectors, and Foundry nested-slot vectors.
- Verification: `just stylus-mapping-events`, `just stylus-nested-map`,
  `just stylus-rust-render`, and `lake build` (792 jobs) all passed; both
  generated crates compiled against `stylus-sdk = 0.10.8`.
- Remaining: W1 is complete. W2 canonical ERC-20 materialization is next;
  Nitro deployment evidence remains in W5.
- Documentation: closed the W1 acceptance items in the Stylus completion plan,
  advanced the integration audit to W2, and updated the agent checkpoint.

## 2026-07-13 - Phase 2: NearFungibleToken u64→u128 conversion (canonical path)

- Status: `done (verified on real NEAR VM)`
- Result. Converted the `NearFungibleToken` amounts from U64 to U128
  end-to-end through the CANONICAL `NearModulePlan` lowering (the path
  `contract_source` / Surface v2 lowers through, including the FT):
  - Stdlib (`Stdlib/NearFungibleToken.lean`): `totalSupply` scalar,
    `balances` / `allowances` (`Map<hash, u128>`) and `pendingAmounts`
    value (`Map<u64, u128>`) now U128; `ft_total_supply` / `ft_balance_of`
    return U128; `ft_transfer` / `ft_mint` / `ft_burn` / `ft_approve` /
    `ft_transfer_call` / `ft_resolve_transfer` amount params + balance locals
    are U128; `ft_resolve_transfer` returns U128; `refundFtUnused` /
    `boundedRefund` / `callbackUnused` use U128 locals and
    `nearPromiseResultU128`; the non-zero amount guard is inlined with
    `u128 0` (the shared `requireNonZero`/`whenPositive` helpers hardcode
    `u64 0` for the u64 contracts that still use them). `ft_transfer_call`
    stays `returns(.u64)` (promise handle, not an amount). NEP-145 storage
    (`storageRequired` / `storageDeposits`) and counters (`nextTransferId`,
    `pendingActive`) stay U64 — full NEP-145 U128 closure is Phase 6.
  - Canonical lowering (`NearModulePlan.lean` + `ModulePlan.lean` +
    `NearModulePlan/Core.lean` + `HostOps.lean`): completed the two remaining
    canonical U128 surfaces Phase 1C had not yet wired — (a) added
    `OpPlan.promiseResultU128` + the `near.promise.result_u128@1.0.0`
    HostOp handler, the `lowerCanonicalNearOp` case (void call + reload
    lo/hi), and the `usesPromiseResults`/`usesPromiseResultU64` surface flags
    so `__pf_promise_result_u128` is emitted for `ft_resolve_transfer`;
    (b) `canonicalCrosscallArgs` now dispatches U128 to
    `__pf_crosscall_args_putu128` (push lo+hi) instead of truncating to
    `putu64`; (c) the `.log` event-field lowering uses `canonicalNearGet`
    (two words) for U128 so `__pf_evt_putu128` receives (lo,hi); (d)
    `.storeMap` skips the trailing `.drop` for U128 (void write helper).
  - Event helper fix (`Event.lean`): `evtHelperFuncsForModulePlan` now emits
    `__pf_fmt_u128` + `__pf_u128_divmod10` alongside `__pf_evt_putu128`
    (mirroring the crosscall path), so a contract with numeric events but no
    other U128 surface (e.g. `NearNft`, U64 tokenId events) links cleanly.
    This was a latent bug — `__pf_evt_putu128` referenced `__pf_fmt_u128`
    which was only emitted under `usesU128`; it had been masking `just
    product` / `portable-nft-multi-target` before the documented OwnableHash
    failure.
- Evidence. The full `ft_transfer_call` + `ft_resolve_transfer` flow runs on
  the unmodified upstream NEAR VM with U128 Borsh inputs (16-byte LE amounts):
  mint 100 → `64000000000000000000000000000000`; transfer 70 → sender
  `1e000000000000000000000000000000` (30), receiver
  `46000000000000000000000000000000` (70); resolve (unused=25, refund=25) →
  `2d000000000000000000000000000000` (45); after refund sender
  `37000000000000000000000000000000` (55), receiver
  `2d000000000000000000000000000000` (45). Events encode amounts as decimal
  (`"amount":100`); crosscall args encode the U128 amount as a decimal
  (`args=["<hash>",70]`); `--promise-result-u64 N` is zero-extended to U128.
- Verification (all passed): `just near-vm-conformance-ft` (real NEAR VM,
  both phases); `just wasm-near-ft-transfer-call` + `wasm-near-ft-transfer-call-e2e`
  (offline host: happy path, repeat-init, private callback, bounded refund,
  concurrent out-of-order callbacks); `just near-ft-security`; `just
  product-token-near` (required `just product` lane); `just near-vm-u128-scalar`,
  `just near-vm-u128-map`, `just near-u128-fmt-smoke`, `just near-vm-conformance`,
  `just wasm-near-plan`, `just near-map-hash-alias` (no regression); manifest
  (`test-manifest`) + equivalence (`test-equivalence`), 116 recipes; `lake
  build proof-forge` (792 jobs). `just product` / `just check-fast` now fail
  only on the documented pre-existing `OwnableHash Soroban` failure (recorded
  2026-07-12, unrelated to this work); the NFT build failure they previously
  hit first is fixed.
- Note (deferred). The `testkit/compare/near/fungible-token` reference crate
  still models U64 amounts and a U64 `decode_le_u64`; it is sandbox-gated
  (not in baseline) and its real U128/AccountId/JSON differential is the
  plan's Phase 8 (`compare harness → semantic equivalence`), not Phase 2.
- Next (interop plan): Phase 3 — AccountId string keys; Phase 4 — JSON
  codecs (the long pole / highest risk). Orthogonal to the active D-052
  program (next task C1).
## 2026-07-13 - Phase 3 Landing 1: string-keyed map mechanism + real-VM gate (NEP-141 AccountId keys)

- Status: `done (verified on real NEAR VM)` — the Phase 3 gate (real-VM proof
  that a string-keyed balance round-trips) is met. Landing 2 (callerAccountId +
  FT conversion) remains.
- Context. NEP-141 `balances` are keyed by `AccountId`, not its sha256 hash.
  The riskiest mechanism is variable-length string-keyed storage: the storage
  key length is RUNTIME (`pl + kl`), unlike the fixed-32-byte hash path, so the
  compile-time `mapStorage*HostInsns` cannot be reused. Landing 1 de-risks that
  mechanism in isolation before the cross-backend `ContextField.accountId`
  sweep and the FT conversion.
- Result.
  - `Map.lean`: `__pf_map_buildkey_string` / `__pf_map_read_string_<vt>` /
    `__pf_map_write_string_<vt>` / `__pf_map_delete_string_<vt>` /
    `__pf_map_contains_string` (NEAR bridge; scalar + U128 values), with inline
    runtime key length (`mapStringKeyLenInsns`). `.string` dispatch arms in
    `mapReadCall` / `mapWriteCall` / `mapDeleteCall` / `mapContainsCall`.
  - `Plan/Surface.lean` + `Plan.lean`: `IndexedStorageHelperKeyKind.string`,
    `ModuleSurface` / `ModulePlan` string-indexed fields + merge +
    `withStringIndexed*` + `.string` arms in the indexed-storage surface
    summaries; `mapStringHelperFuncsForModulePlan` emitted in
    `ModuleAssembly.helperFuncsForModulePlan`. `coreSurface` (canonical Core)
    carries the new fields with empty/false defaults (canonical string-keyed
    support is Landing 2).
  - `EmitWat.lean`: `lowerExpr (.local)` for `.string`/`.bytes` emits
    `(localGet name, localGet (name ++ "_len"))` — the param `_len` local exists
    from `Params.loadParams`. `lowerMapKeyFor` dispatches `.string` to a
    `(ptr, len)` key. `mapStateShapeSupported` admits `.string` keys + `.u128`
    values for consistency.
  - `Capabilities.lean` / `NearAbiPlan.lean` / `Plan/Surface.lean`:
    `emitWatCapabilities` admits `.dataDynamicBytes`; `borshByteWidth` returns
    the flat 260-byte slot for `.string`/`.bytes` (matching `Params.loadParams`);
    `surfaceFromValueType` sets `withArrAlloc` for `.string`/`.bytes` (Borsh
    param decode allocs a payload buffer via `__pf_arr_alloc`).
  - Gate: `just near-vm-string-key-map` — `StringKeyMapProbe`
    (`Map<string, u128>`; `map_roundtrip(key : String) -> U128`: write u128(100)
    at the key, read back) rendered via `EmitWat`, executed on the unmodified
    upstream NEAR VM (`near-vm-runner 0.37` / Wasmtime) with a Borsh string key
    (`"alice.near"`, padded to the 260-byte flat slot). Returns
    `64000000000000000000000000000000` (u128 100).
- Verification (all passed): `just near-vm-string-key-map` (the new gate);
  `just near-vm-u128-map`, `just near-vm-u128-scalar`, `just near-map-hash-alias`,
  `just near-vm-conformance-ft`, `just near-ft-security`, `just product-token-near`,
  `just wasm-near-ft-transfer-call`, `just wasm-near-ft-transfer-call-e2e` (no
  regression); manifest (`test-manifest`, 117 recipes) + `test-equivalence`;
  `lake build` (792 jobs). `just product` fails only on the documented
  pre-existing `OwnableHash Soroban` failure (recorded 2026-07-12, unrelated).
- Note (scope). The probe keys the map by a Borsh string PARAMETER (decoded into
  a `(ptr, len)` pair), not `callerAccountId`. The current flat-260 input
  prologue assert is a ProofForge convention; real variable-length Borsh string
  INPUT is Phase 4 (JSON/Borsh codec). Landing 1 validates the string-keyed MAP
  mechanism, which was the gate's intent.
- Deferred to Landing 2: `callerAccountId` surface construct + the
  `ContextField.accountId` exhaustiveness sweep (`__pf_ctx_account_id`
  returning the raw `predecessor_account_id` as a `(ptr, len)` string, no
  sha256); two-slot string locals (`let sender : .string := callerAccountId`);
  string equality (`__pf_str_eq`); FT conversion (`balances` / `storageDeposits`
  → `.string` keys, `account_id` params → `.string`, `mintAuthority` → string);
  the wasm-near target-profile `dataDynamicBytes` admission for the canonical
  `contract_source` path.
## 2026-07-13 - STYLUS-W2: Canonical ERC-20 local lifecycle

- Status: `done (verified at a4c69d0c)`
- Commit: `a4c69d0c`
- Result: materialized the shared `FungibleToken.spec` and existing ERC-20
  stdlib through canonical Core into one Stylus plan. Direct Wasm now executes
  mint, transfer, approve, transferFrom, standard events, rollback, zero and
  insufficient-balance checks, self-transfer, and unlimited allowance.
- Interfaces: legacy compatibility map-key metadata, canonical `mapN`, Stylus
  token materializer, cast planning, minimal Rust diamond CFG rendering, and
  non-overlapping direct-Wasm context/storage scratch regions.
- Verification: `just stylus-token-differential`,
  `just stylus-counter-differential`, `just stylus-value-vault-canonical`,
  `just stylus-mapping-events`, `just stylus-rust-render`, and `lake build`
  (792 jobs) all passed. The generated token Rust crate compiled against
  `stylus-sdk = 0.10.8`.
- Remaining: normalized abstract/Rust/direct runtime trace parity, public
  `--token` routing, EVM-client interop packaging, and Nitro deployment remain
  open in W2/W5.
- Documentation: checked the first two W2 acceptance items, refreshed the gap
  audit, and advanced the agent checkpoint.

## 2026-07-13 - STYLUS-W2: Public token artifacts and normalized trace parity

- Status: `done (pending commit)`
- Result: opened the public `proof-forge build --target wasm-arbitrum-stylus
  --token` route from a shared `TokenSpec`, producing the pinned Rust SDK Wasm,
  Solidity ABI, TypeScript client, deploy metadata, and honest artifact bundle.
- Semantics: added an executable Lean ERC-20 state model and an independent
  Rust host oracle. Mint, transfer, approve, transferFrom, and rejected
  transferFrom now produce the same normalized JSON state/event trace as the
  generated direct Wasm under `tools/stylus-vm-runner`; the failure step proves
  state rollback in all three observations.
- Registry: promoted only the locally evidenced Stylus capabilities needed by
  the canonical token slice while retaining research maturity and no
  final-deployable claim.
- Verification: `just stylus-token-differential` and `just
  stylus-public-route` passed. Remaining W2 work is standard-client Nitro
  deployment/interoperability evidence.

## 2026-07-13 - STYLUS-W2: Standard ABI interoperability gate

- Status: `local complete; Nitro blocked by environment`
- Result: added `just stylus-token-evm-interop`. Foundry `cast calldata`
  produces standard ERC-20 mint, transfer, approve, transferFrom, balanceOf,
  and allowance calls consumed by the generated direct Wasm; the gate checks
  Solidity mapping slots, boolean/uint256 results, Transfer/Approval logs, and
  rejected-transfer rollback.
- Public client: the artifact smoke now pins address parameters as TypeScript
  `string` and uint256 amounts as `bigint` for transfer, approve, and
  transferFrom.
- Live path: added `stylus-token-nitro-e2e`, which deploys the same direct Wasm,
  executes the lifecycle through `cast send/call`, and writes transaction and
  state evidence under ignored `build/evidence/stylus/token/`.
- Environment evidence: `just stylus-nitro-doctor` reports Rust 1.91.0,
  cargo-stylus 0.10.8, and cast 0.3.0 present, but `ready=false` because Docker,
  the pinned Nitro checkout, and the local RPC are unavailable. No live
  completion checkbox was closed.

## 2026-07-13 - STYLUS-W3: Checked static aggregate layouts

- Status: `foundation complete; renderer integration pending`
- Result: extended `Stylus.AbiLayout` with bounded addition/multiplication,
  recursive fixed-array/nested-tuple static word footprints, and mixed
  static/dynamic method-head sizing. Added the separate
  `Stylus.StorageLayout.Aggregate` module for explicitly word-aligned static
  storage footprints; packing and Solidity short/long dynamic storage remain
  separate future decisions.
- Fail-closed vectors: zero-length arrays, empty tuples, dynamic values in
  static storage, aggregate widths beyond the explicit limit, and nested
  addition/multiplication exhaustion all reject before renderer work.
- Verification: `just stylus-aggregate-differential` passes the new layout
  vectors plus existing bytes/string direct-Wasm execution and generated Rust
  SDK crate compilation.
- Remaining: make the direct ABI dispatcher consume plan-owned multi-word
  fixed-array/tuple layouts, then add nested dynamic tails and storage
  short/long transitions. No W3 completion checkbox was closed.

## 2026-07-13 - STYLUS-W3: Static aggregate direct ABI dispatch

- Status: `static parameter slice complete; aggregate returns pending`
- Result: the direct `user_entrypoint` now derives calldata size, parameter
  positions, dynamic offsets, and temporary locals from checked ABI head-word
  layouts rather than parameter count. Fixed arrays and nested static tuples
  recursively validate every scalar leaf before passing a pointer-backed
  aggregate carrier to the lowered function.
- Runtime vectors: executed `uint64[2]`, `(address,uint64[2])`, and mixed
  `uint64[2],bytes` methods through generated Wasm. Non-canonical uint64/address
  padding and a dynamic offset pointing inside the three-word head reject
  before function execution; the valid mixed tail begins at 96 bytes.
- Rust oracle: the same immutable plan compiles methods with `[u64; 2]`,
  `(Address, [u64; 2])`, and `[u64; 2]` plus `Vec<u8>` signatures under the
  pinned Stylus SDK.
- Remaining: plan and execute static aggregate returns, then nested dynamic
  array/tuple tails with complete-before-copy validation. No W3 completion
  checkbox was closed.

## 2026-07-13 - STYLUS-W3: Complete-before-copy dynamic-array layout

- Status: `layout semantics complete for static element types; direct lowering pending`
- Result: added a bounded Solidity `T[]` decoder for fully static element
  layouts. It derives element words from the shared aggregate layout, checks
  relative offset/head separation, element-count limits, checked payload
  word/byte multiplication, and complete calldata tail bounds.
- Canonical validation: before returning a pointer/count slice, the decoder
  recursively validates every bool, uint, address, fixed-bytes, fixed-array,
  and tuple leaf. This prevents a consumer from copying a partially validated
  aggregate.
- Vectors: pinned `uint64[]` and `(address,uint64[2])[]` layouts, plus element
  limit, truncated tail, malformed uint64 padding, and nested-dynamic rejection.
- Verification: `just stylus-aggregate-differential` passes existing direct
  bytes/string/static aggregate execution, new dynamic-array layout vectors,
  and generated Rust aggregate compilation.
- Remaining: compile this validated `T[]` contract into direct Wasm, then add
  recursive dynamic tuple/array offsets and aggregate return encoding. No W3
  completion checkbox was closed.

## 2026-07-13 - STYLUS-W3: Static-element dynamic arrays in direct Wasm

- Status: `direct parameter slice complete; nested dynamic elements pending`
- Result: compiled the checked `T[]` contract into `user_entrypoint` for fully
  static element layouts. A plan-owned maximum (hard-capped at 64 for bounded
  code generation) controls unrolled validation; the dispatcher checks the
  full payload bound, then recursively validates only elements below the
  runtime count before passing `(data pointer, element count)`.
- Runtime vectors: generated Wasm accepts `uint64[]` and
  `(address,uint64[2])[]`; truncated tails, malformed later uint64 words, and
  malformed nested address padding reject before the target function runs.
- Rust oracle: the identical plan compiles `Vec<u64>` and
  `Vec<(Address, [u64; 2])>` methods against Stylus SDK 0.10.8.
- Remaining: recursive ABI-relative offsets for arrays/tuples containing
  dynamic children, aggregate return encoding, and short/long storage. No W3
  completion checkbox was closed.

## 2026-07-13 - STYLUS-W3: Aggregate return encoding

- Status: `static and static-element dynamic returns complete`
- Result: direct Wasm now returns pointer-backed fixed arrays and static tuples
  by copying the exact checked ABI word footprint. Static-element `T[]` returns
  encode Solidity offset 32, element count, and contiguous payload using the
  plan-owned element width and maximum; result scratch bounds are checked
  against declared memory pages.
- Runtime/Rust parity: `uint64[2]`, `(address,uint64[2])`, `uint64[]`, and
  `(address,uint64[2])[]` echo methods return byte-exact Solidity ABI under the
  local runner, while the same plan compiles matching Rust return types.
- Repair: the first dynamic-array encoder cleared its maximum output range
  before copying, which overlapped calldata-backed tuple-array sources and
  zeroed the address. The encoder now clears only the 64-byte head/count area;
  complete payload words are copied without destructive pre-clear.
- Remaining: recursive offsets for dynamic children, dynamic aggregate
  storage short/long transitions, and resource/Nitro evidence. No W3 completion
  checkbox was closed.

## 2026-07-13 - STYLUS-W3: First recursive dynamic tuple offset

- Status: `single dynamic child complete; general recursion pending`
- Result: direct `user_entrypoint` now decodes `(uint64,bytes)` using two ABI
  bases: the top-level offset is relative to the argument block and the bytes
  offset is relative to the tuple head. Static tuple leaves are canonical-
  validated before the child tail is admitted.
- Bounds: the tuple head, inner aligned offset, 32-byte length word, maximum
  payload, padded tail end, and child length high 28 bytes are checked before
  function execution. The carrier passes the tuple pointer plus child byte
  length to the lowered function.
- Runtime/Rust parity: valid hello payload, inner offset pointing inside the
  tuple head, and high-bit child length vectors execute/reject as expected;
  the same plan compiles `(u64, Vec<u8>)` under Stylus SDK 0.10.8.
- Scope: exactly one bytes/string dynamic field is supported. Multiple dynamic
  fields, nested dynamic arrays, dynamic tuple returns, and storage remain
  named follow-ups; no W3 completion checkbox was closed.

## 2026-07-13 - STYLUS-W3: Multi-child dynamic tuple layout

- Status: `plan-side layout complete; direct multi-child carrier pending`
- Result: added a tuple layout decoder for multiple bytes/string dynamic
  children mixed with recursive static fields. Each child offset is relative
  to the tuple base and has an independent plan maximum; the result includes
  every child slice and the maximum validated encoded extent.
- Carrier decision: direct multi-child tuples will use `(tuple base pointer,
  validated encoded extent)`. A single child length is insufficient, while
  hidden per-field function parameters would make calling conventions depend
  on tuple shape.
- Vectors: `(uint64,bytes,string)` pins two tails (`hello`, UTF-8 `你好`), a
  three-word head, child lengths, and 256-byte extent. Maximum-count mismatch,
  inner offset into the tuple head, per-child limit failure, and nested
  dynamic-array children reject explicitly.
- Verification: `just stylus-aggregate-differential` passes the layout vectors
  and all existing direct/Rust aggregate runtime gates.
- Remaining: compile the extent carrier into direct Wasm, recurse dynamic
  array/tuple children, and implement dynamic storage. No W3 completion
  checkbox was closed.

## 2026-07-13 - STYLUS-W3: Multi-child dynamic tuple direct carrier

- Status: `multi-child bytes/string tuple slice complete; recursive children pending`
- `DirectWasm.Module.dynamicTupleParam` now consumes every plan-owned dynamic
  field maximum, validates each tuple-relative offset/length/padded tail before
  the function call, and computes the complete tuple extent. Entrypoint locals
  are derived from the largest method shape instead of a fixed child count.
- The aggregate fixture now compiles `(uint64,bytes,string)` through both direct
  Wasm and the generated Rust SDK crate. Runner vectors pin successful UTF-8
  payloads, pointers into the tuple head, per-field limit violations, and
  truncated secondary tails.
- Verification: `just stylus-aggregate-differential` passes Lean generation,
  `wat2wasm`, local runner assertions, and generated Rust crate tests.
- Remaining: recursively planned dynamic array/tuple children, aggregate
  storage short/long transitions, and resource exhaustion. W3.1 remains open.

## 2026-07-13 - STYLUS-W6: Explicit renderer contract and direct default

- Status: `W6.1 complete; evidence-hash bundle pending`
- `CliOptions` now owns a closed `StylusRenderer` enum. Both target-first and
  legacy argument paths accept only `direct-wasm` or `rust-sdk`; direct Wasm is
  the default and invalid values fail during parsing.
- The Stylus artifact compiler consumes one checked plan and either lowers it
  directly to WAT/Wasm or explicitly renders/builds the Rust SDK oracle. It
  never attempts the other renderer after a failure.
- Direct bundles publish `contract.wat`, `contract.wasm`, ABI, TypeScript client,
  deploy manifest, and honesty metadata atomically. Wasm is the primary/final
  output. Explicit Rust bundles retain Rust source as primary and have no final
  deployable claim.
- `just stylus-public-route` now proves default direct Counter and Token builds,
  explicit Rust Counter generation, hash verification, and unknown-renderer
  failure with no output or temporary directory.
- Remaining: independent plan/storage/evidence files and hashes, live-evidence
  freshness enforcement, and the full Counter/ValueVault/Token/Remote/Aggregate
  CLI matrix.
- Follow-up: direct and Rust bundles now include full renderer-neutral
  `proof-forge-plan.txt` and `proof-forge-storage.txt` identities. The public
  route gate proves their hashes and the Solidity ABI hash are identical across
  renderers. Literal direct CLI builds also pass for ValueVault and RemoteCall.
- The final Aggregate CLI row remains open: current `contract_source` grammar
  cannot declare bytes/string/array/tuple ABI parameters. `ArrayExample` only
  exercises local fixed arrays and is not counted as Aggregate ABI coverage.

## 2026-07-13 - STYLUS-W5: Persistent Nitro environment audit

- Status: `doctor complete; live scenarios externally blocked`
- `nitro-doctor.sh` now atomically persists its JSON report even when readiness
  fails, so CI and later cutover checks can distinguish a verified external
  blocker from a skipped gate.
- Current `build/evidence/stylus/nitro-doctor.json` records Rust 1.91.0,
  cargo-stylus 0.10.8, and cast as available. Docker daemon, the pinned Nitro
  checkout revision, and the local RPC chain id are absent; `ready` is false.
- Live ValueVault, token, remote, and aggregate evidence remains open. Local
  Wasmtime evidence is not substituted for Nitro evidence.

## 2026-07-13 - STYLUS-W4: HostIO contexts, Rust runtime parity, and local evidence

- Status: `W4.1 and W4.3 complete; normalized cross-renderer trace pending`
- The local VM runner now executes explicit callback, static, and delegate
  frames. Static storage writes fail and roll back; delegate frames preserve
  sender, value, contract address, and caller storage. The direct fixture writes
  those context values to storage so the assertions do not rely only on trace
  labels.
- Generated Rust remote methods now support bounded bytes/string ABI returns
  with offset, length, exact padded extent, zero-padding, maximum-length, and
  UTF-8 checks. Three native `stylus-test` tests cover call/static/delegate,
  calldata, value, gas, revert, malformed scalar return, and dynamic return.
- `scripts/stylus/audit-remote-hostio.py` resolves the actual Cargo package and
  checks pinned `stylus-sdk = 0.10.8` source signatures. The Lean side pins the
  corresponding Wasm import arities. The official call result length is an out
  pointer; there is no invented `return_data_len` host function.
- The differential gate writes ignored
  `build/evidence/stylus/remote-local.json` with artifact hashes, two addresses,
  normalized scenario outcomes, and explicit `local-wasmtime`/non-Nitro
  provenance.
- Verification: `just stylus-remote-call-differential` passes the canonical
  plan, direct Wasm, static/delegate/reentrant runner vectors, three native Rust
  tests, and official HostIO audit.
- Remaining: one shared normalized trace schema across Rust/direct/runner and
  the real two-contract Nitro deployment/transaction evidence.

## 2026-07-13 - STYLUS-W4: Rust SDK static-call oracle foundation

- Status: `static uint64 call slice complete; runtime parity closure pending`
- Result: the Rust SDK renderer now consumes `StylusCallPlan` for uint64-return
  call, static-call, and delegate-call envelopes. It emits pinned SDK 0.10.8
  `RawCall`, plan-owned cache policy, optional gas/value, selector plus static
  uint64 arguments, bounded return copying, revert propagation, and canonical
  uint64 return validation.
- Fallibility: functions containing calls now return `Result<_, Vec<u8>>`, so
  callee revert bytes and malformed return data are preserved rather than
  hidden behind an infallible generated signature.
- Verification: `just stylus-remote-call-differential` executes all existing
  direct/runner/reentrant vectors and compiles the generated Rust call/static/
  delegate/value/gas crate under the pinned toolchain.
- Remaining: generated-Rust TestVM execution, dynamic return rendering,
  static-write rejection, delegate context assertions, and two-contract local/
  Nitro evidence. W4 remains active.

## 2026-07-13 - STYLUS-W7.1: Unified static gate and four-worker registration

- Status: `complete`
- Added `just stylus-all` as the no-skip aggregate for 24 local/static Stylus
  plan, Rust SDK, direct-Wasm, differential, runner, and Nitro-script gates.
  Official `cargo stylus check` and live Nitro execution remain explicit gates
  because they require separately provisioned tooling or services.
- Registered every static recipe exactly once in both `check-serial` and the
  parallel manifest. Four dedicated Stylus lanes allow the existing automatic
  four-worker scheduler to overlap independent plan, runtime, and differential
  families while preserving serial order inside each family.
- Stylus and shared IR/frontend paths now select `stylus-fast`; selector unit
  tests pin both backend-specific and shared-change behavior.
- Cold execution found and repaired three latent coverage defects: stale Rust
  crate golden files, the missing `nearPromiseResultU128` recursive coverage
  branch, and omitted Example build dependencies in
  `constructor-coverage-smoke`.
- Verification: `just stylus-all`, `just constructor-coverage-smoke`,
  `just test-manifest`, `just test-equivalence`, scheduler/select unit tests,
  and `git diff --check` pass. The manifest contains 141 unique recipes across
  eight conflict-aware lanes and still defaults to at most four workers.

## 2026-07-13 - STYLUS-W6.2: Evidence-bound atomic artifact bundles

- Status: `implementation complete; real Nitro evidence still unavailable`
- Every direct-Wasm and Rust-oracle bundle now includes a hashed
  `proof-forge-evidence.json` sidecar. Research builds without live evidence
  are explicit `unavailable`; they never serialize a green Nitro validation.
- Added `check-cutover-evidence.py` with a versioned schema. Supplied final
  evidence must match the current renderer-neutral plan, storage, and ABI
  SHA-256 identities; contain passed, non-skipped `nitro-testnode` results for
  ValueVault, mapping/events, token, remote call, and aggregate; and be no more
  than seven days old. Future timestamps beyond clock tolerance also fail.
- The CLI validates evidence inside its temporary bundle. Validation failure
  removes that directory before returning, so stale evidence cannot publish a
  final or partial artifact.
- Verification: `lake build ProofForge.Cli.StylusArtifacts proof-forge` and
  `just stylus-public-route` pass unavailable, valid, stale, skipped, identity
  mismatch, verified-publication, and temporary-directory cleanup vectors.
- Remaining release blocker: `build/evidence/stylus/final.json` cannot be
  produced honestly until the pinned Nitro environment is available and all
  five live gate families have passed.

## 2026-07-13 - STYLUS-W6.3: Literal product CLI cutover matrix

- Status: `complete locally; Nitro promotion remains unavailable`
- Added `Examples/Product/Aggregate.lean` and `just stylus-cli-matrix`. The gate
  builds Counter, ValueVault, FungibleToken, RemoteCall, and Aggregate through
  default direct Wasm and explicit Rust SDK modes, then verifies renderer,
  final-output honesty, every artifact hash, evidence state, and equal
  renderer-neutral plan/storage/ABI identities.
- The public ABI and TypeScript wrapper now consume ABI JSON derived from the
  checked `StylusPlan`. This repaired a real mismatch where a planned
  `uint64[2]` method was published as `uint256[2]` by legacy EVM defaults.
- RemoteCall now applies CLI peer bindings before canonical adaptation,
  resolves canonical string-pool handles for the target and method, rejects an
  unbound/non-address peer before atomic publication, and renders the bound
  address in both backends. The direct renderer writes the complete 20-byte
  HostIO address and the Rust renderer avoids oversized inferred integer
  literals by constructing `Address` from bytes.
- Runtime verification calls the product `call_remote()` entrypoint under the
  local VM and asserts the exact target address, remote selector, and returned
  word. Aggregate product coverage is bytes/string/fixed-array only; recursive
  dynamic arrays, tuples, and their resource limits remain W3.

## 2026-07-13 - STYLUS-W7.2: CI evidence preservation and claim synchronization

- Status: `GitHub complete; Woodpecker durable upload externally blocked`
- Replaced the single optional generated-Counter GitHub smoke with four
  independent Stylus static lane jobs. Each installs the pinned toolchain,
  runs its manifest lane, records Nitro doctor JSON on failure, and uploads
  generated Wasm/WAT/Rust bundles, normalized traces, evidence, and timings.
- Woodpecker's shared workflow now always records doctor output and packages
  the same evidence surface under `build/ci-artifacts`. Woodpecker does not
  provide a built-in durable artifact store; publishing that archive requires
  a separately configured Codeberg/S3 sink and credentials, so the plan keeps
  that item open rather than embedding unavailable secrets.
- Updated README, Wasm-family and Stylus target status, target roadmap,
  validation catalog, Chinese mirrors, and i18n hashes. Claims now distinguish
  direct-Wasm default, Rust oracle, local VM evidence, incomplete W3/W4 work,
  and required Nitro promotion evidence.

## 2026-07-13 - STYLUS-W7.3: Full regression closure

- Status: `complete`
- The final `JOBS=4 just check-parallel` run passed every registered lane in
  1020.51 seconds. Product, Solana-light, testkit normalized multi-chain
  scenarios, Stylus plan/runtime/differential lanes, backend coverage, and
  documentation gates all completed in one stable worktree snapshot.
- Full execution repaired stale contracts instead of weakening gates: dynamic
  NEAR bytes/string now use exact bounded Borsh input; the real NEAR VM string
  map no longer sends obsolete 260-byte padding; both ValueVault WAT goldens
  match the public compiler output; and the NEAR client generator fails closed
  for dynamic codecs it cannot yet encode.
- Constructor inventory is synchronized across Legacy classification and
  refinement, EVM, Psy, Wasm/NEAR, and EmitWat manifests for
  `nearPromiseResultU128`. The shared portable-source guard also rejects this
  target-only extension.
- Standalone gates now build the `.olean` dependencies they execute, and the
  Anvil-owning canonical parity gate is exclusive under the parallel scheduler.
  The reviewed compiler boundary owns Stylus Legacy-compatible adaptation, so
  the production Legacy import freeze did not grow.
- Verification also includes `just contract-client`, `just near-abi-plan`,
  `just emitwat-aggregate-abi`, `just near-vm-string-key-map`, `just testkit`,
  all constructor coverage scripts, `just portable-default`, and
  `git diff --check`.

## 2026-07-13 - STYLUS-W4.2: Normalized remote renderer parity

- Status: `complete within local observability; Nitro evidence remains W5`
- The generated Rust oracle now executes a fourth native `stylus-test` case and
  writes `proof-forge.stylus.remote-common.v1`. The direct Wasmtime runner
  writes the same schema from its actual HostIO trace.
- Seven common steps cover successful and reverted calls, static/delegate
  modes, static argument calldata, 128-bit call value, and bounded dynamic
  bytes returns. The gate compares target, mode, calldata, value, status, and
  normalized result byte-for-byte across renderers.
- Observability is explicit rather than invented: direct runner evidence owns
  cache transitions and nested frames; pinned upstream `stylus-test` 0.10.8
  has a no-op `flush_cache` and no frame trace API, so its schema marks both
  fields false. Existing reentrant/static-write/delegate-context vectors remain
  required runner-only evidence.
- Verification: `just stylus-remote-call-differential` passes four generated
  Rust tests, direct/reentrant runner assertions, normalized trace equality,
  and the pinned HostIO audit.

## 2026-07-13 - STYLUS-W3.1a: Recursive `bytes[]` calldata carriers

- Status: `complete slice; nested dynamic tuples remain W3.1`
- Generalized plan-owned dynamic child maxima so a dynamic array with a dynamic
  element has an explicit child bound, while static-element arrays remain free
  of irrelevant child policy.
- Added a pure recursive `bytes[]`/`string[]` ABI decoder and Direct Wasm entry
  validation. Element offsets are interpreted relative to the array element
  head, and every child is checked for alignment, head separation, bounded
  length, padded extent, calldata containment, and 32-bit offset wraparound
  before the contract function is invoked.
- Added generated Rust `Vec<Vec<u8>>` coverage plus local VM vectors for a valid
  two-element array and malformed inside-head, unaligned, high-offset,
  over-limit, and truncated-child inputs.
- Verification: `just stylus-aggregate-differential` and `git diff --check`.

## 2026-07-13 - STYLUS-W3.1b: Dynamic-array children inside tuples

- Status: `complete slice; tree-shaped recursive bounds remain W3.1`
- Generalized pure tuple ABI decoding and Direct Wasm entry validation from
  bytes/string children to dynamic arrays whose element type has a static ABI
  layout. Tuple-relative offsets, element counts, computed strides, canonical
  element words, and full tail extents are validated before function entry.
- Added `(uint64,uint64[])` generated Rust and direct-Wasm coverage with valid,
  inside-head, high-offset, over-limit, non-canonical-element, and truncated
  local VM vectors. Unsupported dynamic-array elements continue to fail closed.
- Hardened dynamic tuple offsets against 32-bit addition wraparound while
  retaining the existing multi-tail bytes/string behavior.
- Verification: `just stylus-aggregate-differential` and `git diff --check`.

## 2026-07-13 - Stylus aggregate targeted-gate acceleration

- Status: `complete`
- `stylus-vm-runner` now accepts `--calldata-file`, compiles the module once,
  executes every line in a fresh Store, and returns a version-stable `batch`
  array. Single-calldata output remains backward compatible.
- The aggregate differential script uses that batch mode instead of compiling
  Wasm in a new runner process for every vector.
- The generated Rust oracle keeps a parent-level `Cargo.lock` cache across
  atomic crate regeneration, avoiding repeated dependency resolution while
  still allowing Cargo to refresh the lock when its manifest changes.
- This is deliberately scoped to the active aggregate gate; no full test suite
  is part of feature iteration.
- Verification: the targeted gate fell from 82.74 seconds before batching to
  12.92 seconds after batching on the same worktree; runner Cargo tests and all
  aggregate Rust/direct runtime assertions pass.

## 2026-07-13 - Stylus product Aggregate ABI repair

- Status: `complete`
- Direct Wasm dynamic bytes/string returns now copy the live payload before
  clearing the ABI head and only clear the runtime padding extent. The previous
  maximum-sized fill could erase calldata-backed payloads before the copy.
- The Stylus CLI now derives legacy contract-source selectors from the exact
  plan ABI widths instead of reusing EVM's compatibility widening. In
  particular, `echo_fixed(uint64[2])` now publishes selector `717cbbd9`, matching
  its ABI, instead of the `uint256[2]` selector.
- Verification: targeted Lean/CLI builds, the product Aggregate local VM ABI
  preflight for bytes/string/fixed-array echoes, `just
  stylus-aggregate-differential`, and `just stylus-cli-matrix` pass. No full
  repository suite was run during this development slice.

## 2026-07-13 - STYLUS-W5.2: Nitro product evidence pipeline

- Status: `implementation and local preflight complete; live Nitro blocked`
- Added versioned live gate summaries for ValueVault and Token, including
  receipt status/hash checks, result assertions, Transfer/Approval topics,
  chain identity, and Wasm hashes. Added deployable RemoteCallee plus
  two-contract RemoteCall and Aggregate live recipes.
- Added a fail-closed assembler for ValueVault, mapping/events, token,
  RemoteCall, and Aggregate. It requires the pinned ready doctor, one chain,
  passed non-skipped summaries, transaction and artifact hashes, and publishes
  `final.json` atomically with plan/storage/ABI identities. Invalid input removes
  stale final evidence.
- Verification: `lake build Examples.Backend.Stylus.RemoteCallee`, `just
  stylus-nitro-scripts`, product RemoteCall/Aggregate local VM preflights, and
  `just stylus-cli-matrix` pass. The current doctor remains `ready=false`
  because Docker, the pinned checkout, and the local Nitro RPC are unavailable;
  no live evidence or synthetic completion is claimed. No full repository suite
  was run during this development slice.

## 2026-07-13 - STYLUS-W6 re-audit: atomic failure and provenance closure

- Status: `complete`
- Wrapped the entire Stylus artifact compiler with process-scoped temporary
  bundle cleanup. Any renderer, subprocess, write, validation, or publication
  failure now removes the `.bundle-tmp-*` directory; successful rename leaves
  nothing for the cleanup path.
- Strengthened cutover evidence validation to require the pinned Nitro revision
  and local endpoint, doctor hash, positive common chain id, and well-formed
  transaction, artifact, and gate-summary hashes. Passed/provenance labels alone
  no longer authorize a final artifact.
- Verification: targeted Lean/CLI build, `just stylus-public-route` including an
  intentional `wat2wasm` exit-42 no-partial vector and invalid revision/hash
  evidence vectors, `just stylus-nitro-scripts`, and `git diff --check` pass.
  No full repository suite was run during this development slice.

## 2026-07-13 - STYLUS-W7.2: CI artifact and gap-document re-audit

- Status: `local CI contract complete; durable Woodpecker upload externally blocked`
- Confirmed GitHub owns four independent optional Stylus static lanes, runs the
  doctor on failure, and uploads artifacts, traces, evidence, and timings on
  every outcome. The previous gap report's older-Counter-only claim was stale.
- Woodpecker no longer suppresses `tar` failures or accepts file existence as
  sufficient evidence. It creates the expected directories, requires doctor
  JSON, builds the archive without `|| true`, and inspects the archive for that
  doctor entry. Durable publication still needs a configured Codeberg/S3 sink
  and credentials and is not claimed complete.
- Rewrote the July 13 Stylus integration gap audit around the current 51/79
  plan state, closed W1/W2/W4/W6 packages, and the remaining W3, W5.2, W7.2,
  and final-integration path.
- Verification: both CI YAML files parse, the Woodpecker archive contract was
  exercised locally, `just test-manifest` reports 142 unique recipes across
  eight lanes, `just docs-check`, and `git diff --check` pass. No full
  repository suite was run during this development slice.

## 2026-07-13 - STYLUS-W3.1: Recursive dynamic aggregate closure

- Status: `complete`
- Replaced immediate-child maximum counting with a recursive preorder policy:
  nested bytes/string nodes contribute byte bounds and nested dynamic arrays
  contribute element-count bounds before their descendants. Existing flat
  fixtures retain the same policy arrays.
- Added a checked pure recursive ABI decoder and one direct-Wasm recursive
  validator for bytes/string, dynamic arrays, tuples, fixed arrays, and static
  leaves. Bounds use widened arithmetic before memory access, validate complete
  heads/tails, and reuse bounded locals across unrolled array elements.
- Added Rust/direct/local vectors for `(uint64,(bytes,string))` and
  `(uint64,bytes)[]`, including inside-head offsets, child over-limit lengths,
  malformed nesting, and truncated tails.
- Verification: `just stylus-aggregate-differential`, `just
  stylus-diagnostics`, targeted Lean module builds, and `git diff --check` pass.
  No full repository suite was run during this development slice.

## 2026-07-13 - STYLUS-W3.2a: Bounded dynamic bytes storage

- Status: `W3.2 in progress; bytes lifecycle complete`
- Added renderer-neutral Solidity/Stylus short and long bytes storage planning,
  including padded payload words, stale long-word cleanup, checked array slot
  sizing, and explicit maximum bounds.
- Added plan operations and validation for bounded dynamic storage. Direct Wasm
  now reads and caches inline values below 32 bytes, hashes long-value roots,
  increments 256-bit payload slots, clears stale long words, and rejects corrupt
  or out-of-page lengths before copying. Rust SDK output uses `StorageBytes` and
  `StorageString` handlers.
- Added opt-in `--shared-storage-batch` to the local VM runner. Default batch
  cases remain isolated; the new mode carries only committed storage/cache into
  the next transaction and supports lifecycle testing.
- Added `just stylus-aggregate-storage`, covering pure layout vectors,
  resource-adversarial rejection, WAT validation, generated Rust `cargo check`,
  and local `short -> long -> short` storage execution. `just
  stylus-diagnostics` also passes. No product/check/stylus-all suite was run;
  string runtime and dynamic-array element storage remain in W3.2.

## 2026-07-13 - STYLUS-W3.2b/W3.3: Aggregate storage closure

- Status: `complete locally; Nitro not claimed`
- Extended the plan with bounded dynamic-array storage operations. The neutral
  planner now computes Solidity-compatible scalar element widths, packing
  density, and payload words; composite layouts remain explicit fail-closed
  work rather than being treated as one-slot elements.
- Direct Wasm now loads, caches, packs, clears, and bounds scalar dynamic arrays
  below `keccak256(rootSlot)`. The public accepted fragment covers bool,
  uint8/16/32/64/128, and address arrays with at most eight elements, matching
  the current 256-byte carrier. Fixed-bytes, uint256, and composite public
  carriers are rejected until their existing ABI boundary is extended.
- Rust SDK rendering now uses `StorageString` and Solidity array storage,
  returns explicit `Result` errors for over-limit/corrupt values in release
  builds, and executes a `stylus-test` oracle for bytes, UTF-8 string, and
  packed uint64 array short/max/shrink lifecycles. Direct VM vectors use the
  same values and additionally reject oversized calldata and corrupt roots.
- Canonical Core planning now recognizes root scalar bytes/string and dynamic
  array state, derives the matching storage/HostIO plan, and applies the
  eight-element Direct carrier bound to dynamic-array parameters. A checked
  six-entrypoint Core fixture proves this route before renderer validation;
  indexed arrays and composite elements continue to fail closed.
- Verification: `just stylus-aggregate-storage`, `just
  stylus-aggregate-differential`, `just stylus-core-plan`, and `just
  stylus-diagnostics` pass. The storage gate also compiles Direct/Rust bool,
  uint16, uint128, and address array variants. No product/check/stylus-all
  suite or Nitro execution was run during this development slice.

## 2026-07-13 - STYLUS-W4 review: Fail-closed local evidence verification

- Status: `W4.1-W4.3 reviewed complete locally; Nitro not claimed`
- Re-audited the canonical call envelopes, pinned SDK 0.10.8 HostIO source
  signatures, Rust/direct normalized seven-step trace, and runner-only static,
  delegate-context, nested-frame, reentrant success/revert, and outer rollback
  vectors.
- Added `scripts/stylus/verify-remote-local-evidence.py`. The differential gate
  now independently reopens `remote-local.json`, requires local Wasmtime and
  explicit non-Nitro provenance, validates the five required scenario outcomes,
  and recomputes both generated Wasm hashes.
- Verification: the verifier accepts the current evidence and rejects a
  schema-corrupted copy; `just stylus-remote-call-differential` passes four
  native Rust tests, Direct/runner vectors, normalized parity, evidence
  verification, and the official HostIO audit. No full aggregate or Nitro gate
  was run.

## 2026-07-13 - STYLUS-W5 review: Require proven Nitro provenance

- Status: `W5.1 verified; W5.2 externally blocked`
- The current doctor report is authoritatively `ready=false`: Rust 1.91,
  cargo-stylus 0.10.8, and cast are present, while the Docker daemon, pinned
  Nitro checkout, and local RPC/chain id are absent. `final.json` remains
  absent.
- Added a shared fail-fast doctor guard to the Counter, ValueVault, Token,
  RemoteCall, and Aggregate local Nitro E2E scripts. No script may now label an
  arbitrary localhost EVM as `nitro-testnode`; a fresh ready doctor is required
  before product compilation or deployment.
- Verification: `just stylus-nitro-scripts` passes syntax and evidence-assembler
  self-tests. All five E2E entrypoints fail at the doctor guard in the current
  environment and preserve the non-ready report. No live deployment, receipt,
  gas/ink, or Nitro completion is claimed.

## 2026-07-13 - STYLUS-W6 review: Renderer-neutral CLI dispatch

- Status: `W6.1-W6.3 reviewed complete locally; live evidence remains unavailable`
- Renamed the target-first native operation from the obsolete
  `stylusRustSdk`/`--stylus-rust-sdk` identity to
  `stylusContractSource`/`--stylus-contract-source`. Renderer selection remains
  an orthogonal option: Direct-Wasm is the default artifact and Rust SDK is the
  explicit oracle, with no fallback between them.
- Re-audited temporary bundle cleanup, forced renderer/tool failure, plan/
  storage/ABI identities, stale and verified evidence, final-output roles, and
  literal Counter/ValueVault/Token/RemoteCall/Aggregate dual-renderer builds.
- Verification: `just stylus-public-route` and `just stylus-cli-matrix` pass.
  The latter executes all five product pairs and the bound full-address remote
  call. No full Stylus or repository suite was run.

## 2026-07-13 - STYLUS-W7 review: Restore serial/parallel gate equivalence

- Status: `W7.1 locally complete; W7.2 durable Woodpecker upload externally blocked`
- Added the W3 closure gate `stylus-aggregate-storage` to serial coverage and
  the `stylus-differential-b` lane. The manifest's existing
  `near-vm-u128-map` entry was also restored to `check-serial`, matching the
  Wave-T baseline instead of deleting valid parallel coverage.
- The 26 manifest-tagged Stylus static recipes now exactly equal the 26
  `stylus-all` dependencies. GitHub still owns four optional Stylus lanes and
  durable Woodpecker upload still requires external sink credentials.
- Refreshed the current Stylus gap audit and roadmap: W3/W4 are locally closed;
  W5.2, Woodpecker publication, and final branch integration remain.
- Verification: `just test-manifest` reports 143 recipes across eight lanes;
  `just test-equivalence` reports the same 143 recipes in serial and parallel
  coverage. No recipe body, `stylus-all`, or repository full suite was run.

## 2026-07-13 - Stylus final integration: Rebase and full regression

- Status: `local final integration complete; W5.2/W7.2 externally blocked`
- Rebased the feature history onto `origin/main` at `7e38c4a5` while preserving
  its two material merge nodes. Historical resolutions were reused rather than
  replacing either side wholesale. The pre/post final-tree comparison differs
  only in the three EVM demo files introduced upstream, with matching stable
  patch IDs.
- Published the rebased branch with an exact force-with-lease after confirming
  the remote feature tip had not moved. The unrelated dirty main worktree and
  its NEAR changes were not touched.
- Verification: `just product`, `just stylus-all`, `just test-manifest` (143
  recipes, eight lanes), `just test-equivalence` (143 recipes), and
  `just docs-check` pass. `JOBS=4 just check-parallel` passed every registered
  recipe in 953.76 seconds; `git diff --check` passes after this documentation
  update.
- A fresh `just stylus-nitro-doctor` correctly exits nonzero with
  `ready=false`: Rust 1.91.0, cargo-stylus 0.10.8, and cast are available;
  Docker, the pinned Nitro checkout, and `http://127.0.0.1:8547` are not.
  `final.json` remains absent. Durable Woodpecker publication still requires an
  external artifact sink and credentials.
