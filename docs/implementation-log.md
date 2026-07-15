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
    `(ptr, len)` key. Canonical EmitWat planning owns `.string` keys + `.u128`
    values; the frozen Rust sourcegen retains its narrower map boundary.
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
  → `.string` keys and `account_id` params → `.string`; `mintAuthority` remains
  a full SHA-256 hash because raw string scalar storage is out of scope);
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

## 2026-07-13 - NEAR-NEP141: Landing 2b - FT AccountId string keys and full transfer_call

- Status: `done (verified at 29b3299f)`
- Commit: `29b3299f`
- Scope: converted the NEP-141 NearFungibleToken to raw AccountId string keys
  through the canonical `NearModulePlan` lowering path, with the full
  `ft_transfer_call` and `ft_resolve_transfer` callback validated on the
  unmodified upstream NEAR VM.
- FT source: `balances` and `storageDeposits` use `.string` keys;
  `account_id` and `receiver_id` params use `.string`; `callerAccountId` owns
  balance and transfer authorization. Allowances and `mintAuthority` remain
  `.hash` because raw string scalar storage is outside this landing.
- Added two-slot string locals, string event values, canonical
  `Core.ContextField.accountId`, string equality, and strict dynamic string
  parameter decoding. Dynamic `.bytes` ABI parameters remain fail closed in
  canonical EmitWat; frozen Rust sourcegen retains its `Vec<u8>` ABI.
- Extended `near-vm-runner` with per-call predecessor ids and attached deposits.
  The FT gate covers storage deposit, authorized withdrawal, and attacker abort.
- Deduplicated generated helper functions by name and kept the frozen Rust
  sourcegen boundary separate from canonical string-keyed U128 map support.
- Verification recorded by the original landing: `near-vm-conformance-ft`,
  `wasm-near-ft-transfer-call`, `wasm-near-ft-transfer-call-e2e`,
  `near-ft-security`, `product-token-near`, `near-vm-caller-account-id-map`,
  `near-vm-string-key-map`, the U128 VM gates, and focused canonical gates.
- Next: wallet-compatible JSON argument and return codecs.

## 2026-07-13 - NEAR-NEP141: Landing 4a - JSON `ft_balance_of`

- Status: `done (verified on the unmodified upstream NEAR VM)`.
- Added JSON as a first-class `NearAbiPlan` codec and extracted
  `buildSignaturePlan`, removing the canonical Core builder's duplicated,
  hard-coded Borsh plan. Both legacy compatibility lowering and canonical
  `NearModulePlan` consume the same per-entrypoint decision.
- `ft_balance_of(account_id : String) -> U128` accepts canonical JSON input,
  validates the exact one-field frame and payload bound, and returns a quoted
  decimal JSON U128 through `__pf_return_json_u128`. Other entrypoints remain
  Borsh in this landing.
- Added `near-vm-json-balance`; it proves mint 100, JSON balance `"100"`, and
  malformed-input abort on the real VM. Existing FT smokes now use JSON balance
  queries while retaining Borsh mutation calls.
- Verification recorded by the original landing: `near-abi-plan`,
  `near-abi-client`, `near-vm-json-balance`, `near-vm-conformance-ft`,
  `wasm-near-ft-transfer-call-e2e`, and `product-token-near`.
- Next: reusable multi-field JSON call decoding and generated-client JSON
  transaction transport.

## 2026-07-13 - NEAR-NEP141: Landing 4b - JSON `ft_transfer`

- Status: `done (verified on the unmodified upstream NEAR VM)`.
- Extended the shared `NearAbiPlan` JSON schema to the required
  `ft_transfer(receiver_id : String, amount : U128)` fields. Canonical
  `NearModulePlan` owns the codec decision and generated clients use the same
  method plan.
- Added bounded decimal U128 parsing and entrypoint-scoped JSON input helpers;
  helper selection remains derived from the frozen module plan.
- Added `near-vm-json-transfer`, covering a successful transfer and malformed
  or unauthorized calls on the real VM. Optional memo/msg and generic
  order-tolerant JSON remain explicit follow-up work.
- Verification recorded by the original landing: `near-abi-plan`,
  `near-abi-client`, `near-vm-json-transfer`, `near-vm-json-balance`,
  `near-vm-conformance-ft`, and `near-ft-security`.
- Next: structured JSON return planning for NEP-145/148.

## 2026-07-14 - NEAR N-T0: remaining-task reconciliation

- Status: `done`.
- Reconciled stale capability claims with current code and retained the real
  remaining boundaries: schema-driven JSON, standard NEP-141/145/148/297,
  TokenSpec artifact closure, sandbox evidence, receipt/network execution, and
  formal preservation.
- Verification recorded by the original task: documentation checks, i18n link
  validation, and `git diff --check`.

## 2026-07-14 - NEAR N-T1: schema-driven JSON ABI

- Status: `done (verified on the unmodified upstream NEAR VM)`.
- Added one validated JSON schema graph to `AbiPlan`; NEAR input decoding,
  output encoding, and generated TypeScript clients consume that plan-owned
  graph. Objects reject unknown/duplicate fields, strings support escapes and
  Unicode surrogate pairs, and U128 remains a checked decimal string.
- Added schema-compiled JSON return helpers for scalar, struct, fixed/dynamic
  array, and optional outputs. Invalid output schemas fail lowering explicitly.
- Corrected aggregate carriers and separated transient U128/JSON memory regions.
- Verification recorded by the original task: affected WasmHost/CLI builds,
  `Tests/NearAbiPlan.lean`, `Tests/ContractClient.lean`, `near-abi-client`, and
  the focused JSON/FT real-VM gates.
- Next: standard `ft_transfer_call` JSON, exact one-yocto guards, and receiver
  registration behavior.

## 2026-07-14 - NEAR N-T2: standard NEP-141 transfer ABI

- Status: `done (verified on the unmodified upstream NEAR VM)`.
- Replaced the receiver-pool compatibility protocol with standard JSON
  `ft_transfer(receiver_id, amount, memo?)` and
  `ft_transfer_call(receiver_id, amount, memo?, msg)`. Both require exactly one
  yoctoNEAR and a registered receiver.
- Extended the canonical crosscall plan with named JSON arguments and runtime
  AccountId targets. Promise and resolver payloads use quoted decimal U128.
- Extended schema-driven decoding with optional fields and JSON U64 resolver
  ids; generated clients serialize the same plan-owned schema.
- Verification recorded by the original task: `near-abi-plan`,
  `near-abi-client`, `near-ft-security`, `near-vm-json-transfer`,
  `wasm-near-ft-transfer-call`, and `near-vm-conformance-ft`.
- Next: complete NEP-145 JSON, unregister/refund semantics, and storage byte
  accounting.

## 2026-07-14 - NEAR N-T3: complete NEP-145 storage management

- Status: `done (verified on the unmodified upstream NEAR VM)`.
- Implemented the five standard JSON storage methods, including optional
  arguments, standard balance/bounds objects, and null for unregistered users.
- Added canonical struct-literal and storage-removal support plus target-owned
  NEAR operations for attached deposit, storage usage, and promise transfer.
  Other backends reject those target operations explicitly.
- Registration measures real storage usage, tracks actual byte deltas, refunds
  repeat deposits, and unregisters with exact locked-deposit refunds and forced
  balance burn semantics.
- Fixed U128 multiplication, canonical jump/phi multiword moves, and JSON struct
  extraction issues exposed by the real VM.
- Verification recorded by the original task: `Tests/NearAbiPlan.lean`, public
  CLI Wasm emission, `near-vm-nep145`, `near-vm-json-transfer`, and
  `near-vm-conformance-ft`.
- Next: NEP-148 metadata and NEP-297 event envelopes.

## 2026-07-14 - IR-B0: target-extension boundary audit and freeze

- Status: `done (verified 2026-07-14)`.
- Audited the legacy shared IR, Canonical Core, interface, and materialization
  records after NEP-145 exposed the cost of adding chain-specific constructors.
- Confirmed that the debt is broader than NEAR: EVM EIP/ERC/ABI operations,
  chain-only context fields, Solidity error layout, fallback/receive dispatch,
  and target string/policy fields also cross the intended shared boundary.
- Accepted D-054 and added the IR/target-extension boundary design plus the
  IR-B0 through IR-B6 migration plan. N-T4 is paused until the NEAR shared-layer
  cleanup reaches IR-B3.
- Added `just ir-target-boundary`. Its counted baseline permits removals but
  rejects new or increased target/protocol identifiers in shared IR/Core files.
- Verification: `just ir-target-boundary`, `just docs-check`, and
  `git diff --check`.
- Next: IR-B1, open extension identities and target-owned catalog composition.

## 2026-07-14 - IR-B1: open target-extension protocol

- Status: `done (verified 2026-07-14)`.
- Moved typed HostOp identity/version ownership from Canonical Core to
  `ProofForge.Target.HostOp` and changed capability identity from a closed
  inductive to an open stable-ID structure.
- Removed the global NEAR catalog from Core. `ProofForge.Target.HostOps.Near`
  now owns NEAR signatures, the NEAR target profile declares the supported
  operation IDs, and canonical pipeline validation resolves handlers from the
  selected profile.
- Canonical requirement derivation now records exact HostOp calls and validates
  their signature/effect/capability contract. Focused tests cover extension IDs,
  target profile ownership, fail-closed resolution, and NEAR plan handlers.
- Verification passed: `just target-registry`, `just hostop-protocol`,
  `just near-promise-hostop`, `just ir-target-boundary`, `just build`, and
  `git diff --check`.
- `just product` was also attempted. It passed the preceding product gates and
  stopped at the independent Soroban spike limitation: `OwnableHash` cannot
  lower 32-byte Hash storage through Soroban's scalar `_get` ABI. No IR-B1
  HostOp/NEAR gate failed.
- Expanded the remaining program to cover EVM, Solana, all implemented
  Wasm-host profiles, Move, Aleo, Psy, Quint, and shared interface records.
- Next: IR-B2, inject target host semantics and remove NEAR promise modes/traces
  from Canonical Core.

## 2026-07-14 - IR-B2: remove NEAR semantics from Canonical Core

- Status: `done (verified 2026-07-14)`.
- Replaced Core's chain-named promise modes with target-neutral
  `namedInvoke` and `continuation` semantics. The legacy adapter temporarily
  maps old source constructors to these modes until IR-B3 removes that source
  compatibility surface.
- Moved the Promise trace type and executable reference handler out of
  `IR.Core.Semantics` into `Target.HostOps.Near.Semantics`. Core now owns only
  the generic injected `HostSemantics` hook.
- Updated NEAR, EVM, and Stylus Core plan consumers. Unsupported-target HostOps
  still fail before plan construction; no fake EVM/Solana promise behavior was
  added.
- Tightened `target-boundary-baseline.txt` to remove all deleted Core NEAR
  catalog, mode, validation, and semantics entries, preventing regression.
- Verification passed: focused `lake build` of Core, adapter, NEAR/EVM/Stylus
  plan modules; `just hostop-protocol`; `just canonical-near-route`;
  `just canonical-evm-route`; `just canonical-solana-route`;
  `just ir-target-boundary`; and `git diff --check`. No full `just check` ran.
- Next: IR-B3, replace legacy shared NEAR `Expr` constructors and materialized
  string-pool fields with neutral calls or target-owned extension payloads.

## 2026-07-14 - IR-B3a: neutral shared crosscall string pool

- Status: `done (verified 2026-07-14)`.
- Renamed legacy `Module.nearCrosscallStrings` and canonical/plan
  `nearHostStrings` to the target-neutral `crosscallStrings`. The pool is
  shared peer/method materialization used by EVM, Solana, NEAR, Soroban, and
  CosmWasm, so NEAR ownership was both misleading and architecturally wrong.
- Updated adapters, deploy maps, target materializers, backends, diagnostics,
  refinement statements, fixtures, tests, and current documentation. The
  source-scan baseline no longer permits either old shared field name.
- Verification passed: `lake build` (802 jobs), Canonical LegacyAdapter,
  CrosscallMaterialize, ProtocolMaterialize, PortableAuthMaterialize,
  IRPortability, WasmNearPlan, SolanaPdaSeeds, `just ir-target-boundary`,
  documentation sync, and `git diff --check`.
- Next: IR-B3b, add a generic legacy extension-call carrier and migrate promise
  result, storage usage, transfer, and typed call-value wrappers.

## 2026-07-14 - IR-B3b: generic legacy extension calls

- Status: `done (verified 2026-07-14)`.
- Added shared `Expr.hostCall`, carrying only an open HostOp ID, typed
  arguments/result, and open capability requirements. The legacy adapter lowers
  it to Canonical Core HostOp instructions, where the selected target catalog
  performs exact signature and capability validation.
- Migrated active NEAR stdlib/facade uses of promise result count/status/U64/U128,
  storage usage, and promise transfer to target-catalog IDs. Removed the
  corresponding internal Builder helpers that still constructed chain-named
  nodes.
- Updated every shared analyzer and backend exhaustiveness boundary. EVM,
  Solana, Aleo, Psy, and other unsupported paths reject extension calls or
  recurse through their arguments; no backend receives fabricated semantics.
- Verification passed: `lake build` (802 jobs), `just hostop-protocol`,
  `just near-abi-plan`, `Tests/NearFtSecurity.lean`, and `just near-vm-nep145`
  on the real upstream NEAR VM. No full `just check` ran.
- Next: IR-B3c, introduce typed target-neutral call-value/continuation forms,
  migrate remaining compatibility fixtures, and delete all legacy `near*`
  `Expr` constructors and match arms.

## 2026-07-14 - IR-B3c: remove legacy NEAR expression constructors

- Status: `done (verified 2026-07-14)`.
- Replaced the last shared NEAR-named call nodes with semantic
  `crosscallInvokeNamedValue`, `crosscallContinue`, and `callValueU128` forms.
  Added the open `crosscall.continue` capability so shared expressions no
  longer request the target-specific `near.promise` capability.
- Deleted promise-result count/status/U64/U128, storage-usage, and transfer
  constructors plus their exhaustive branches from every backend and analyzer.
  `Source.Near` now owns compatibility wrappers that emit generic HostOps.
- Repaired two migration gaps found by focused testing: the Wasm plan now maps
  result-decoding HostOps to the required helper surface, and EmitWat now
  dispatches registered NEAR HostOps directly. Legacy EmitWat string literals
  are populated from the canonical normalized instruction stream.
- Verification passed: `lake build` (804 jobs), `just ir-target-boundary`,
  `just hostop-protocol`, `just canonical-near-route`,
  `just canonical-evm-route`, `just canonical-solana-route`,
  `just near-abi-plan`, `Tests/NearFtSecurity.lean`,
  `just wasm-near-ft-transfer-call`, and `just near-vm-nep145` on the real
  upstream NEAR VM. No full `just check` ran.
- Next: IR-B4, remove EVM ABI/protocol/call-mode constructors from shared IR.

## 2026-07-14 - IR-B4a: EVM effect HostOp boundary

- Status: `done (verified 2026-07-14)`.
- Added result-free generic `Effect.hostCall`, the target-owned
  `Target.HostOps.Evm` catalog, and the `Source.Evm` authoring facade.
- Migrated ERC-721 and ERC-1155 stdlib receiver callbacks to registered EVM
  HostOps. EVM Legacy and Canonical plans lower those IDs to the existing
  receiver plans; other backends reject unknown effect extensions explicitly.
- Corrected Core HostOp result validation so zero-result signatures are owned
  by the catalog rather than a hard-coded one-result assumption. Solana CLI
  now runs the same HostOp handler gate before plan construction.
- Verification passed: full `lake build`, `just evm-semantic-plan`,
  `Tests/Canonical/EvmEffectHostOp.lean`, real CLI compilation of
  `ERC721Probe` to a 2214-hex-character EVM runtime, and explicit
  pre-plan rejection on `solana-sbpf-asm` and `wasm-near`.
- Next: IR-B4b, delete the three legacy ERC receiver `Effect` constructors and
  move EIP-712/ecrecover authoring behind the EVM extension facade.

## 2026-07-14 - IR-B4b: delete legacy EVM receiver effects

- Status: `done (verified 2026-07-14)`.
- Deleted the three ERC-721/ERC-1155 receiver constructors from shared
  `Effect` and removed their portable `Contract.Surface` authoring helpers.
- Removed the corresponding branches from shared semantics, ownership,
  portability, SDK schema, refinement coverage, and every non-EVM backend.
- Reworked EVM IR lowering so registered receiver HostOps lower directly to
  EVM `EffectPlan`/Yul instead of reconstructing a legacy IR effect.
- Migrated the semantic-plan and strict-intent tests to generic HostOps and
  removed obsolete per-constructor coverage rows.
- Verification passed: `just hostop-protocol`, `just evm-semantic-plan`,
  `just strict-intent-materialization`, `just constructor-coverage-smoke`,
  `just ir-target-boundary`, and EVM/NEAR/EmitWat/Psy coverage checks.
- Next: IR-B4c, move EIP-712/ecrecover and remaining EVM-only call forms out
  of shared IR; separately audit and retire the legacy pipeline itself.

## 2026-07-14 - Legacy plan audit: D2 status repair

- Status: `done (documentation repair)`.
- Verified that D2 was already implemented by `1caa87ff`: the reviewed product
  `ContractSpec` allowlist, `Tests/IntentProductBoundary.lean`, and the
  `portable-default` shrinking guard all exist and pass.
- Updated the authoritative incremental replacement plan to mark D2 complete;
  no compiler behavior changed.
- Verification passed: `lake env lean --run Tests/IntentProductBoundary.lean`
  and `just portable-default`.
- Next: D5, migrate Counter as the first existing product family.

## 2026-07-14 - D3: remove advisory canonical fallback

- Status: `removed (verified 2026-07-14)`.
- Confirmed with a repository-wide caller search that
  `runCanonicalValidationGate` had no production or example caller; primary
  artifact paths already use fail-closed canonical target planning.
- Deleted the advisory function, which previously converted adaptation and
  target-builder gaps into success, and removed tests that preserved that
  behavior.
- Added `Frontend.ContractSpec.Normalize` as the single compatibility owner and
  removed direct Legacy Adapter imports from EVM, Solana, Stylus, Wasm module
  assembly, and `CanonicalPipeline`; the production import allowlist shrank
  from 11 files to 9.
- Strict tests now assert terminal adaptation failure and primary-triad target
  success directly.
- Verification passed: `lake build ProofForge.Compiler.CanonicalPipeline`,
  targeted builds for all migrated callers, `just canonical-boundary`,
  `just legacy-replacement-freeze`, `just strict-target-gate`, and
  `just strict-intent-materialization`.
- Remaining Legacy work: remove CLI argument round-trips and eliminate the EVM
  renderer's residual legacy `IR.Module` declaration context before switching
  Surface v2 products such as Counter.

## 2026-07-14 - IR-B7a: target-owned Canonical EVM storage plans

- Status: `done (verified 2026-07-14)`.
- Changed the Canonical Core EVM builder to resolve logical `StateId` values
  against its own `StorageLayout` during planning.
- Scalar, map, and fixed-array loads/stores now emit physical target variants
  carrying slots, packing widths, and bounds. They no longer retain symbolic
  state names for the Yul phase to rediscover through legacy `IR.Module`.
- Added a regression assertion covering real Counter and ValueVault plans;
  either plan fails if any symbolic Legacy storage effect survives.
- Verification passed: `lake build ProofForge.Backend.Evm.Plan.Core`,
  `lake env lean --run Tests/Backend/Evm/CanonicalPlan.lean`, and
  `git diff --check`.
- Next: IR-B7b, add a plan-only Canonical EVM renderer and remove the
  `IR.Module` argument from the strict public route.

## 2026-07-14 - IR-B7b1: EVM plan owns ABI-packed helpers

- Status: `done (verified 2026-07-14)`.
- Added ABI-packed helper specifications to `Evm.Plan.ModulePlan` and populate
  them during full compatibility planning.
- Complete and Canonical lowering now consumes the recorded specifications;
  only incomplete compatibility plans may rescan source IR.
- Removed the Canonical renderer's previous rejection that admitted the plan
  did not own this metadata.
- Verification passed: targeted EVM IR/Core builds,
  `Tests/Backend/Evm/CanonicalPlan.lean`, `just evm-semantic-plan`, and
  `git diff --check`.
- Next: IR-B7b2, make entrypoint/body/dispatch lowering consume the plan alone.

## 2026-07-14 - IR-B7b2: plan-only Canonical EVM rendering

- Status: `done (verified 2026-07-14)`.
- Added `Backend.Evm.Plan.ToYul`, a strict lowering pass that consumes only
  target-owned `ExprPlan`, `EffectPlan`, and `StmtPlan` nodes. Legacy
  expressions and symbolic storage effects fail closed.
- Changed `lowerCanonicalModuleWithPlan` and
  `renderCanonicalModuleWithPlan` to accept `ModulePlan` alone. Removed the
  hand-written legacy EVM declaration contexts from Set and Queue tests.
- Canonical Core events now materialize word plans before rendering instead
  of carrying ABI values that required source-module analysis.
- Verification passed: Counter, ValueVault, Set, and Queue Canonical tests;
  rebuilt `proof-forge`; a real Counter EVM build (360 runtime hex chars);
  `just strict-intent-materialization`; `just strict-target-gate`; and
  `git diff --check`.
- Next: D5, switch Counter's loaded source/default product route away from
  `ContractSpec`; then continue the same cutover for the remaining families.

## 2026-07-14 - N-T4a: NEP-148 metadata on the real NEAR VM

- Status: `done (verified 2026-07-14)`.
- Added the strict JSON `ft_metadata : () -> FungibleTokenMetadata` ABI and a
  structured NEP-148 result with spec, identity, optional URI fields, and
  decimals.
- Extended nested literal collection and canonical JSON aggregate lowering so
  metadata strings reach the Wasm data pool without injecting multi-value
  helper functions that NEAR rejects.
- Verification passed: `lake env lean --run Tests/NearAbiPlan.lean`, a public
  CLI build of `Examples/Backend/WasmNear/FungibleToken.lean`, and
  `just near-vm-nep148` on the unmodified upstream NEAR VM.
- Remaining: N-T4b, emit NEP-297 `EVENT_JSON` envelopes for FT events.

## 2026-07-14 - N-T4b: NEP-297 and standard NEP-141 events

- Status: `done (verified 2026-07-14)`.
- Changed both legacy-compatible and canonical EmitWat event lowering to emit
  NEP-297 `EVENT_JSON` envelopes from the shared layout/event helpers.
- The fungible-token mint, transfer, and burn events now use the `nep141`
  namespace, standard field names, and quoted decimal U128 amounts; other
  events use the `proof_forge` namespace.
- Updated the executable refinement model and real VM runner so the exact log
  bytes are observed rather than merely proving that event calls do not trap.
- Verification: `lake build ProofForge.Backend.WasmHost.Refinement proof-forge`,
  `just near-vm-json-transfer`, `just near-vm-nep297`, and
  `lake env lean --run Tests/Backend/Wasm/EmitWatChainSemantics.lean`.
- Remaining: N-T5 TokenSpec parameterization; N-T6 sandbox differential.

## 2026-07-14 - NEAR-R0a: isolate v1 module-plan compatibility

- Status: `in_progress`; this is the first NEAR canonical-cutover slice.
- Moved every `IR.Module`-accepting NEAR plan builder and lowerer into the
  explicit `NearModulePlan.Legacy` module. Canonical Core planning and
  plan-only lowering continue to import only `NearModulePlan`.
- Extended `canonical-boundary` so Canonical target builders and Wasm-host
  plan lowering reject imports of `IR.Contract`, the `IR.Legacy` namespace,
  and `NearModulePlan.Legacy`; self-tests prove each forbidden import fails.
- Reopened N-T1 through N-T4 for canonical-route replay. Their existing commits
  remain behavior baselines, but the legacy FT source path is no longer counted
  as architecture completion.
- Verification passed: targeted builds for the main, Legacy, Core, and Lower
  modules; `Tests/Canonical/WasmHostPlanPreservation.lean`;
  `Tests/NearModulePlan.lean`; `Tests/NearAbiPlan.lean`; and
  `just canonical-boundary`.
- Next: NEAR-R0b/R1, remove v1 type/layout ownership from the target plan.

## 2026-07-14 - NEAR-R1a: target-owned aggregate layout

- Status: `in_progress`; `StructDecl` and `AllocatorConfig` ownership is
  removed, while `ValueType` extraction remains.
- Added Wasm-host `StructPlan` field/aggregate layouts and changed
  `WasmHostModulePlan.LowerCtxSeed` to store those target plans instead of v1
  IR declarations. Removed allocator configuration from the plan entirely.
- Legacy lowering reads the original declarations and allocator only from its
  explicitly supplied legacy module. Canonical ABI and JSON-return entrypoints
  accept the target-owned layouts through dedicated adapters.
- Extended `canonical-boundary` and its self-test to reject `StructDecl` or
  `AllocatorConfig` fields in the Wasm-host module plan.
- Verification passed: targeted Wasm-host builds,
  `Tests/Canonical/WasmHostPlanPreservation.lean`, `Tests/NearModulePlan.lean`,
  `Tests/NearAbiPlan.lean`, and `just canonical-boundary`.
- Next: extract the Wasm-host value/type model so the plan no longer imports
  v1 `IR.Contract` merely to name scalar and aggregate value shapes.

## 2026-07-14 - NEAR-R1b: portable value types and pure plan modules

- Status: `done (verified 2026-07-14)`.
- Extracted the chain-neutral `ValueType` vocabulary from the v1 contract
  schema into `IR.ValueType`; `IR.Contract` now consumes it rather than owning
  it. The legacy classifier records that it only classifies value shapes when
  they occur inside compatibility contract nodes.
- Made Wasm-host ABI, struct, surface, and module plan data modules depend on
  portable value types instead of `IR.Contract`. Moved old `Module -> Plan`,
  ABI, struct, and JSON-return conversions into explicit `.Legacy` modules.
- Canonical JSON return layout computes target-plan field offsets directly;
  it no longer converts target struct plans back into `StructDecl`.
- Expanded `canonical-boundary` to protect all pure Wasm-host plan modules
  from imports of `IR.Contract`, `IR.Legacy`, or any Wasm-host `.Legacy`
  module.
- Updated EVM, NEAR, and Psy coverage-manifest scanners to read constructors
  from both `IR.ValueType` and the remaining compatibility contract schema.
- Extended the legacy schema freeze to watch `IR.ValueType`, so constructor
  changes still require an explicit compatibility-classification update.
- Verification passed: targeted builds through `Target.BackendRegistry`,
  `Tests/Canonical/WasmHostPlanPreservation.lean`, `Tests/NearAbiPlan.lean`,
  `Tests/NearModulePlan.lean`, all three IR coverage-manifest scanners, and
  `just canonical-boundary`.
- Next: NEAR-R2, replace shared context/promise operation variants with typed
  target HostOps before the TokenSpec cutover.

## 2026-07-14 - IR-B7a: target-owned context HostOps

- Status: `done (verified 2026-07-14)` for the Canonical Core context subtask;
  EVM-R1 and NEAR-R2 remain open.
- Reduced `Core.ContextField` to portable sender/value/block/time/gas/contract
  reads. EVM `origin`/`prevrandao` and NEAR predecessor/current account,
  epoch, random seed, prepaid gas, and used gas are exact typed HostOps.
- Added the read-only HostOp effect class so target context calls are legal in
  view entrypoints without treating promise/receiver calls as read-only.
- Legacy adaptation now translates old target-specific context constructors
  into target HostOps; EVM and NEAR planners consume only their own IDs and the
  handler gate rejects cross-target use.
- Extended `canonical-boundary` and its self-test to reject target-native Core
  context constructors, and added the focused HostOp route test to that gate.
- Verification passed: affected Core/Surface/EVM/Solana/Stylus/NEAR builds,
  `Tests/Canonical/TargetContextHostOps.lean`, `just canonical-boundary`, and
  `git diff --check`.
- Corrected the control-plane status: EVM's plan-only renderer baseline is not
  an end-to-end legacy removal. Work resumes at EVM-R1, then EVM-R2 through
  EVM-R4; NEAR follows only after EVM exits.

## 2026-07-14 - EVM-R1a: no-argument environment HostOps

- Status: `done (verified 2026-07-14)`; EVM-R1 remains in progress.
- Added exact EVM context HostOps for gas price, base fee, and coinbase, all
  classified as read-only context effects with target-owned result types.
- Changed legacy canonicalization from rejection to typed HostOp normalization
  and taught the EVM Core plan to materialize the existing semantic context
  plan nodes. NEAR handler checks reject all three IDs.
- Extended `Tests/Canonical/TargetContextHostOps.lean` with positive EVM plan
  assertions and wrong-target negative assertions.
- Verification passed: targeted EVM HostOp/adapter/Core-plan builds, the focused
  context HostOp test, `just ir-target-boundary`, and `git diff --check`.
- Next: EVM-R1b, migrate parameterized `blockHash(number)` without adding a
  target constructor to Canonical Core.

## 2026-07-14 - EVM-R1b: parameterized block-hash HostOp

- Status: `done (verified 2026-07-14)`; EVM-R1 remains in progress.
- Added `evm.context/block_hash@1.0.0 : u64 -> hash` as a read-only context
  HostOp. Legacy expression normalization preserves the block-number argument
  in ANF before emitting the typed call.
- The EVM Core plan materializes the call to its target-owned
  `ContextExprPlan.blockHash`; NEAR rejects the ID through handler resolution.
- The focused test verifies both the literal binding and the block-hash local
  reference, rather than relying on an invalid inlined-expression assumption.
- Verification passed: targeted adapter/EVM Core-plan builds,
  `Tests/Canonical/TargetContextHostOps.lean`, `just ir-target-boundary`, and
  `git diff --check`.
- Next: audit and migrate EVM-only `ecrecover`/EIP-712 expression constructors.

## 2026-07-14 - EVM-R1c prerequisite: pure HostOp carrier

- Status: `done (verified 2026-07-14)`; EVM crypto migration follows.
- Reconciled Core validation with the accepted HostOp architecture: pure
  target operations may use the same exact typed/versioned HostOp carrier as
  context and external operations.
- Canonical view validation now accepts `.pure` and `.context` HostOps while
  continuing to reject `.external` HostOps. Removed the obsolete
  `pureEffectfulMismatch` error and inverted its fail-closed unit test into a
  positive pure-carrier assertion; arity, argument/result types, version,
  capability, and handler checks remain unchanged.
- Verification passed: targeted Core HostOp/Validate/Canonical builds,
  `Tests/Canonical/HostOpFailClosed.lean`,
  `Tests/Canonical/TargetContextHostOps.lean`, and `git diff --check`.

## 2026-07-14 - EVM-R1c: target-owned recovery and EIP-712

- Status: `done (verified 2026-07-14)` for product/canonical HostOp routing;
  deletion of the two old shared constructors is the next slice.
- Added pure typed `evm.crypto/ecrecover@1.0.0` and
  `evm.crypto/eip712_permit_digest@1.0.0` signatures with exact argument,
  result, and capability contracts.
- Added EVM-owned source helpers and switched `ERC20Permit` away from portable
  `Contract.Surface` crypto helpers. Legacy canonicalization translates old
  constructors to the same HostOps; both canonical and transitional EVM plans
  lower them to the existing semantic helper expressions.
- Added `Tests/Canonical/EvmCryptoHostOps.lean` to `hostop-protocol`; it proves
  strict EVM validation/planning, view-safe pure operations, exact IDs, and
  wrong-target rejection.
- Verification passed: targeted Stdlib/adapter/EVM plan/lower builds,
  `just hostop-protocol`, `Tests/TokenEvm.lean`, `just ir-target-boundary`, and
  `git diff --check`.
- Next: remove `Expr.ecrecover` and `Expr.eip712PermitDigest` plus their stale
  shared/backend reject arms; EVM product authoring must retain only HostOps.

## 2026-07-14 - EVM-R1d: remove portable crypto authoring API

- Status: `done (verified 2026-07-14)`; legacy IR constructor deletion remains.
- Deleted `Contract.Surface.ecrecover` and
  `Contract.Surface.eip712PermitDigest`. Product code now has only the
  target-owned `Contract.Source.Evm` HostOp helpers for these operations.
- Repository caller audit found no remaining use of the removed portable API;
  ERC20Permit had already switched to the EVM facade.
- Verification passed: targeted Surface/Source.Evm/ERC20Permit builds,
  `Tests/Canonical/EvmCryptoHostOps.lean`, `Tests/TokenEvm.lean`, and
  `git diff --check`.

## 2026-07-14 - EVM-R1e: migrate mechanics fixture to HostOp

- Status: `done (verified 2026-07-14)`.
- Replaced the final non-inventory direct construction of legacy
  `Expr.ecrecover` in `ChainAgnosticRoute` with the exact typed EVM HostOp.
  The required capability remains visible to PortableHonesty, so EVM resolves
  and NEAR still rejects through the normal mechanics path.
- Verification passed: `Tests/ChainAgnosticRoute.lean` and `git diff --check`.
- Remaining direct legacy crypto constructors are compatibility inventory and
  exhaustive match arms, not product/test authoring calls.

## 2026-07-14 - EVM-R1f: remove ABI-packed IR producers

- Status: `done (verified 2026-07-14)` for producer/API migration; dead legacy
  constructor cleanup follows.
- Removed every `irAggregate*`, `irFromPlan`, and protocol `aggregateIr*` API
  that encoded EVM Multicall ABI layouts as a shared `IR.Expr`.
- Kept layout and dynamic patch semantics in their owning EVM modules:
  `AbiEncode.Plan`, `AbiPackedHelperSpec`, target/argument offset planners, and
  Yul helper generation.
- Rewrote `Tests/AbiEncode.lean` to directly verify static stores, runtime
  length offset, target patch offsets, ABI argument patch offsets, helper
  parameters, and generated CALL/revert Yul without a portable-IR round trip.
- Verification passed: targeted EVM ABI/Multicall builds,
  `Tests/AbiEncode.lean`, and `git diff --check`.
- Next: delete `Expr.crosscallAbiPacked` and its now-dead shared/backend match
  arms, then tighten the target-boundary baseline.

## 2026-07-14 - EVM-R1g: delete shared ABI-packed call node

- Status: `done (verified 2026-07-14)`; EVM-R1 call/error/dispatch migration
  remains in progress.
- Deleted legacy `Expr.crosscallAbiPacked` and every adapter, analysis,
  refinement, validator, and non-EVM backend arm that existed only for that
  EVM ABI layout.
- Deleted the compatibility `abiPackedHelperSpecsFromExpr` whole-module scanner.
  Packed helper specifications now enter code generation only through the EVM
  `ModulePlan`; the target-owned `ExprPlan.crosscallAbiPacked` and Yul emitter
  remain intact.
- Repaired earlier legacy-freeze inventory omissions for `accountId`, expression
  HostOps, and effect HostOps. HostOp classification tags are stable constructor
  names rather than payload-dependent IDs.
- Verification passed: targeted builds for all affected shared/EVM/non-EVM
  modules, `Tests/AbiEncode.lean`, `just ir-target-boundary`,
  `just legacy-freeze`, and `git diff --check`. No full `just check` ran.
- Next: classify and migrate legacy create/static/delegate call modes.

## 2026-07-14 - EVM-R1h: canonical target-owned CREATE2

- Status: `done (verified 2026-07-14)`; legacy CREATE/CREATE2 IR removal remains
  part of EVM-R1.
- Moved `create2Deploy` from generic `Contract.Surface`/`Contract.Source` to
  `Contract.Source.Evm` and switched `Create2Factory` to the EVM facade. The
  facade emits `evm.create/create2@1.0.0` rather than a legacy CREATE2 node.
- Added the exact external HostOp signature and EVM Core-plan handler. Runtime
  call value/salt remain typed Core values; compile-time init code becomes
  target-plan metadata and is rejected as a general runtime string value.
- Added Canonical-plan CREATE helper discovery without calling the legacy IR
  scanner, so final Yul contains the required CREATE2 helper.
- Added `EvmCreateHostOp` coverage for exact ID, strict EVM acceptance,
  NEAR/Solana rejection, semantic plan shape, and helper discovery.
- Corrected authoring documentation and the backend example wrapper so this
  stdlib is no longer described as portable.
- Verification passed: targeted Source/Source.Evm/Create2Factory/Core-plan
  builds, `Tests/Canonical/EvmCreateHostOp.lean`, the EVM Create2Factory fixture
  build and final bytecode compile smoke, `just hostop-protocol`,
  `just ir-target-boundary`, and `git diff --check`.
- Next: introduce target-owned CREATE/CREATE2 requests in the canonical route,
  then delete the corresponding legacy shared constructors.

## 2026-07-14 - EVM-R1i: remove final crypto constructor producer

- Status: `done (verified 2026-07-14)`; shared constructor deletion follows.
- Switched the canonical EVM crypto route test from legacy
  `Expr.ecrecover`/`Expr.eip712PermitDigest` construction to the public
  `Contract.Source.Evm` HostOp helpers.
- Verification passed: `Tests/Canonical/EvmCryptoHostOps.lean` and
  `git diff --check`.
- Next: delete the two now-unreachable legacy crypto constructors and all
  compatibility/rejection match arms.

## 2026-07-14 - EVM-R1j: delete shared crypto constructors

- Status: `done (verified 2026-07-14)`; EVM-R1 remains in progress.
- Deleted legacy `Expr.ecrecover` and `Expr.eip712PermitDigest` from the shared
  IR schema, adapter, classification inventory, ownership/mutability/
  portability analysis, SDK schema traversal, and refinement coverage.
- Removed their stale EVM compatibility lowering and all non-EVM rejection or
  traversal arms. EVM `ExprPlan` crypto nodes, HostOp handlers, and Yul helpers
  remain target-owned.
- Verification passed: targeted builds for all affected shared/EVM/non-EVM
  modules, `Tests/Canonical/EvmCryptoHostOps.lean`, `Tests/TokenEvm.lean`,
  ERC20Permit build, `just ir-target-boundary`, `just legacy-freeze`, and
  `git diff --check`. No full `just check` ran.
- Next: migrate static/delegate authoring and then Solidity error/dispatch
  metadata before EVM-R2.

## 2026-07-14 - EVM-R1k: target-owned canonical error plan

- Status: `done (verified 2026-07-14)`; removal of the remaining selector/type
  envelope from canonical materialization is the next IR-B7 slice.
- Added `EvmErrorPlan` and canonical-only assert/revert statement variants.
  `Plan.Core.buildFromCore` now lowers `CoreErrorRef.args` directly to
  `ExprPlan` and never reconstructs a Legacy `IR.ErrorRef`.
- Implemented structured Core revert terminators in the EVM planner and direct
  target-plan-to-Yul lowering for ProofForge envelopes plus Solidity custom
  errors with static or runtime arguments.
- Changed Legacy normalization so Solidity static words and runtime expressions
  become typed Core error arguments. Interface error declarations now carry
  the corresponding Core parameter schema; static words are no longer retained
  as the canonical value source.
- Added `Tests/Canonical/EvmErrorPlan.lean` and updated earlier adapter/public
  route assertions to test the current architecture boundary.
- Verification passed: targeted EVM CLI module build,
  `Tests/Canonical/EvmErrorPlan.lean`, `Tests/Canonical/LegacyAdapter.lean`,
  `Tests/Canonical/EvmPublicRoute.lean`, `just ir-target-boundary`,
  `just legacy-freeze`, and `git diff --check`. No full `just check` ran.
- Next: remove `ErrorEncodingForm.solidityCustom` and Solidity selector/type
  fields from canonical materialization by introducing an EVM-owned interface
  attachment, then migrate fallback/receive dispatch metadata.

## 2026-07-14 - EVM-R1l: open interface-extension ownership

- Status: `done (verified 2026-07-14)`; deletion of the superseded canonical
  Solidity fields follows immediately.
- Added a target-neutral `InterfaceExtension` envelope with stable extension
  ID, typed subject, and positional typed values. Shared Core validates only
  identity/subject integrity and never interprets target vocabulary.
- Registered `evm.error/solidity_custom@1.0.0` in the EVM target profile and
  extended strict target gates to reject missing interface-extension handlers.
- Legacy normalization now emits the EVM-owned attachment, and EVM Core
  planning decodes it into `EvmErrorPlan`. NEAR rejects the same checked
  contract before planning.
- Verification passed: targeted Registry/Adapter/EVM Core-plan/Canonical
  pipeline builds, `Tests/Canonical/EvmErrorPlan.lean`, and `git diff --check`.
  No full `just check` ran.
- Next: delete the old Solidity-named error fields and custom form from
  canonical materialization and update all prior canonical tests.

## 2026-07-14 - EVM-R1m: delete canonical Solidity error fields

- Status: `done (verified 2026-07-14)`; IR-B7 item 2 is complete.
- Deleted `ErrorEncodingForm.solidityCustom`, `soliditySelector?`,
  `solidityArgWords`, `solidityArgTypes`, and their Solidity-specific validators
  from shared canonical materialization.
- Portable error encoding now contains only fallback/message/envelope policy.
  Exact EVM selector/type data is decoded exclusively from the registered
  interface extension into `EvmErrorPlan`; unsupported EVM ABI types fail in
  the EVM planner, while generic canonical validation remains target-neutral.
- Updated earlier Core validation and Legacy adapter assertions so they no
  longer require target data in shared records.
- Verification passed: targeted Canonical/Adapter/EVM Core-plan and EVM CLI
  artifact builds, `Tests/Canonical/CoreValidate.lean`,
  `Tests/Canonical/EvmErrorPlan.lean`, `Tests/Canonical/LegacyAdapter.lean`,
  `just ir-target-boundary`, `just legacy-freeze`, and `git diff --check`.
  `EvmPublicRoute` was attempted separately but the local Lean process reached
  its memory limit before producing a test result; no full `just check` ran.
- Next: move fallback/receive dispatch ownership out of the shared interface,
  then move proxy and host-string pools out of canonical materialization.

## 2026-07-14 - EVM-R1n: dispatch interface-extension bridge

- Status: `done (verified 2026-07-14)`; EVM planner consumption and shared-kind
  deletion follow next.
- Registered exact `evm.dispatch/fallback@1.0.0` and
  `evm.dispatch/receive@1.0.0` interface extension IDs.
- Legacy `ContractSpec` and Surface v2 normalization now attach those IDs to
  the canonical function identity. Strict handler resolution accepts them only
  for EVM and rejects them for NEAR/Solana before target planning.
- Added `Tests/Canonical/EvmDispatchExtensions.lean` for exact normalization
  and wrong-target rejection.
- Verification passed: targeted Adapter/Surface/Registry builds,
  `Tests/Canonical/EvmDispatchExtensions.lean`, `just ir-target-boundary`, and
  `git diff --check`. No full `just check` ran.
- Next: make EVM `DispatchPlan` consume the attachments and render their
  function bodies, then delete fallback/receive from `InterfaceEntrypointKind`.

## 2026-07-14 - EVM-R1o: canonical dispatch-plan consumption

- Status: `done (verified 2026-07-14)`; shared interface-kind deletion follows.
- Extended EVM `DispatchPlan` with explicit optional fallback/receive function
  bindings. Core planning resolves those bindings only from registered EVM
  interface extensions; selector dispatch contains ordinary functions only.
- Canonical rendering now emits both special function bodies and a default
  branch that calls only functions that actually exist. Missing fallback or
  receive paths revert instead of calling an undefined hard-coded function.
- Verification passed: targeted EVM Plan/ToYul/IR builds,
  `Tests/Canonical/EvmDispatchExtensions.lean`, and `git diff --check`.
  The broader `EvmSemanticPlan` was attempted but stopped on its existing
  fallback probe diagnostic (`view getValue contains native value read`) before
  reaching the dispatch assertions; no full `just check` ran.
- Next: delete fallback/receive from `InterfaceEntrypointKind` and make the
  shared interface treat every entrypoint uniformly.

## 2026-07-14 - EVM-R1p: delete canonical dispatch kinds

- Status: `done (verified 2026-07-14)`; IR-B7 item 3 is complete.
- Deleted `InterfaceEntrypointKind` and the `kind` field from the shared
  Canonical interface. Generic validation now treats every entrypoint
  uniformly; fallback/receive identity and special-shape validation are owned
  by registered EVM interface extensions and the EVM planner. The planner also
  rejects duplicate fallback or receive attachments instead of overwriting an
  earlier dispatch binding.
- Removed Legacy/Surface adapter writes to the deleted field and updated all
  Canonical fixtures. Legacy `IR.EntrypointKind` and Surface authoring kinds
  remain only on the not-yet-deleted compatibility inputs for EVM-R4.
- Updated the EVM Canonical-plan storage observer for the target-owned
  `assertPlanned` and `revertPlanned` cases introduced by EVM-R1k.
- Verification passed: targeted Canonical, Adapter, Surface, EVM Core-plan,
  and Canonical-pipeline builds; Canonical Core validation/schema/semantics,
  Legacy adapter, EVM dispatch-extension, EVM Canonical-plan, evidence
  isolation, and Solana Canonical-plan tests; `just ir-target-boundary`,
  `just legacy-freeze`, and `git diff --check`. `NestedMapShape` and
  `CanonicalNearPlan` were attempted separately but the local Lean processes
  exited with status 139 and no diagnostic output. No full `just check` ran.
- Next: move proxy and host-string pools out of canonical materialization.

## 2026-07-14 - EVM-R1q: target-owned proxy pattern

- Status: `done (verified 2026-07-14)`; the host-string half of IR-B7 item 4
  remains.
- Registered the contract-scoped
  `evm.dispatch/proxy_pattern@1.0.0` interface extension. Legacy adaptation now
  checks its two old proxy declarations for agreement at the compatibility
  boundary and emits one typed target attachment.
- Deleted `CanonicalProxyPattern`, `proxyPattern?`, and
  `moduleProxyPattern?` from shared canonical materialization. The EVM planner
  selects UUPS dispatch only from the registered attachment and rejects the
  unimplemented transparent pattern explicitly.
- Added `Tests/Canonical/EvmProxyExtension.lean` for UUPS planning,
  wrong-target rejection, transparent rejection, and mismatched legacy input.
  Updated Core and Legacy adapter tests to assert the new ownership boundary.
- Verification passed: targeted Canonical, Adapter, Registry, EVM Core-plan,
  and Canonical-pipeline builds; EVM proxy, EVM dispatch, EVM Canonical-plan,
  Legacy adapter, and Canonical Core validation tests; `just
  ir-target-boundary`, `just legacy-freeze`, and `git diff --check`. No full
  `just check` ran.
- Next: replace indexed `crosscallStrings` with direct portable values or
  target-owned attachments, then delete the shared pool.

## 2026-07-14 - EVM-R1r: detach EVM crosscalls from host-string pools

- Status: `done (verified 2026-07-14)`; NEAR and Solana pool consumers remain.
- Extended the Legacy adapter environment only as a compatibility input so
  ordinary `crosscall.invoke` indices normalize immediately into direct Core
  `addressLit` and `stringLit` values.
- Deleted `crosscallStrings` from the EVM `CorePlanEnv`. EVM target planning
  now parses direct `0x` address literals and resolves direct method names to
  selectors; clearing the Canonical materialization pool no longer changes or
  breaks an EVM plan.
- Added `Tests/Canonical/EvmDirectCrosscall.lean` to prove direct Core values
  and pool-free EVM planning. Updated the EVM Canonical-plan test so valid
  addresses materialize while invalid addresses fail with a target diagnostic.
- Verification passed: targeted Adapter, EVM Core-plan, and Canonical-pipeline
  builds; EVM direct-crosscall, EVM Canonical-plan, Legacy adapter, and EVM
  proxy tests; `just ir-target-boundary`, `just legacy-freeze`, and `git diff
  --check`. No full `just check` ran.
- Next: finish remaining EVM-R1 authoring/constructor deletions, then begin the
  NEAR sequence and remove its named/continuation pool handles.

## 2026-07-14 - EVM-R1s: target-owned plain CREATE

- Status: `done (verified 2026-07-14)`; EVM-R1 is complete and EVM-R2 is next.
- Registered `evm.create/create@1.0.0` beside CREATE2, added
  `Contract.Source.Evm.createDeploy`, and lowered the exact HostOp to
  `ExprPlan.create .create` in the EVM Core planner.
- Expanded `Tests/Canonical/EvmCreateHostOp.lean` to cover CREATE and CREATE2
  IDs, wrong-target handler rejection, both semantic plan nodes, and helper
  collection.
- Confirmed the cleanup boundary: static/delegate remain platform-neutral
  Canonical Core modes. Frozen Legacy EVM constructors are not being reshaped
  into another compatibility API; EVM-R4 deletes them after EVM-R2/R3 switch
  the remaining callers and public routes.
- Verification passed: targeted EVM HostOp/facade/Core-plan builds; EVM create,
  proxy, and direct-crosscall tests; `just ir-target-boundary`, `just
  legacy-freeze`, and `git diff --check`. No full `just check` ran.
- Next: EVM-R2, direct Canonical materialization for Counter, ValueVault,
  Token, RemoteCall, and remaining EVM product families.

## 2026-07-14 - EVM-R2a: direct Counter and ValueVault products

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress for Token,
  RemoteCall, and the remaining product families.
- Completed the existing Surface v2 Counter and ValueVault product definitions
  with their stable EVM selectors.
- Added `Tests/Canonical/EvmDirectProducts.lean`, which imports only the
  Surface products and new compiler path, then runs `normalizeSurface ->
  buildFromCore -> renderCanonicalModuleWithPlan`. It does not import or call
  `ContractSpec`, `Frontend.ContractSpec.Normalize`, or `adaptLegacy`.
- Verified three Counter and seven ValueVault entrypoints reach exact EVM
  dispatch cases and render Yul with the original product identity.
- Verification passed: rebuilt both Surface product modules; EVM direct-product,
  Surface normalization, and EVM Canonical-plan tests; `just
  ir-target-boundary`, `just legacy-freeze`, and `git diff --check`. No full
  `just check` ran.
- Next: add direct Canonical EVM product coverage for RemoteCall, then Token.

## 2026-07-14 - EVM-R2b: direct portable RemoteCall

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress for Token
  and the remaining product families.
- Added the independent `SurfaceCrosscallMode` and a typed Surface crosscall
  expression. Normalization emits the existing target-neutral
  `CoreCrosscallSpec`; the Surface node contains no EVM selector, NEAR promise,
  or Solana account-layout data.
- Added `Examples/Product/Canonical/RemoteCall.lean` with direct address and
  method literals, and included it in the adapter-free EVM direct-product gate.
- Surface reference semantics treats external results as opaque, matching its
  existing HostOp policy while compiler validation and target plans retain the
  exact typed operation.
- Verification passed: rebuilt Surface and the three direct product modules;
  EVM direct-product, Surface normalization/parity, and Canonical Core
  validation tests; `just ir-target-boundary`, `just legacy-freeze`, and `git
  diff --check`. No full `just check` ran.
- Next: model the direct Canonical Token family without reusing the old
  `ContractSpec` token materializer.

## 2026-07-14 - EVM-R2c: direct TokenSpec materialization

- Status: `done (verified 2026-07-14)`; the four named EVM-R2 families are
  direct, while the remaining product inventory still needs closure.
- Added target-owned `Contract.Token.EvmSurface.materialize`, producing a
  Surface v2 contract directly from portable `TokenSpec`. It does not reuse
  `Token.EvmSpec`, Legacy ERC-20 modules, or `ContractSpec` adaptation.
- Implemented total supply, decimals, balances, transfers, hashed composite
  allowances, approvals, transferFrom, and feature-gated mint/burn. The
  initializer is one-shot and mint checks the stored owner.
- Added the portable Surface `hashPair` expression and mapped it to Canonical
  `hashTwoToOne`; allowance layout remains target-plan owned.
- Fixed Surface normalization so generated assert/revert Core errors receive
  matching interface and materialization entries instead of failing Canonical
  validation.
- Added `Examples/Product/Canonical/FungibleToken.lean` and the isolated
  `Tests/Canonical/EvmDirectToken.lean` gate for selectors, balance/allowance
  storage, feature filtering, and Yul rendering.
- Verification passed: targeted Surface/Token builds; direct Token, Surface
  normalization/parity, and Canonical Core validation tests; `just
  ir-target-boundary`, `just legacy-freeze`, and `git diff --check`. The larger
  direct-product test was rebuilt separately after the Surface constructor
  layout changed and passes; no full `just check` ran.
- Next: inventory the remaining EVM product sources, classify aliases/composed
  families, and add direct Surface materializers only where behavior is not
  already covered by these four cores.

## 2026-07-14 - EVM-R2d: direct Ownable policy materialization

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress for the
  remaining EVM product families.
- Added a Surface v2 Ownable product with address-typed owner state, one-shot
  initialization, owner-only transfer/renounce checks, indexed ownership
  events, and explicit EVM selectors.
- The direct product reaches checked Canonical Core and the EVM `ModulePlan`
  without importing the legacy Ownable mixin, `ContractSpec`, or
  `Legacy.Adapter`.
- Verification: `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`
  and `git diff --check`.

## 2026-07-14 - EVM-R2e: direct portable policy stdlib

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Moved the direct Ownable definition out of the example and into the new
  target-neutral `Contract.Stdlib.Surface.Policies` layer, then added direct
  Pausable and ReentrancyGuard state machines beside it.
- Canonical product modules now expose thin Surface v2 values; none of the
  three policies imports the old `contract_source` mixins or produces a
  `ContractSpec`.
- Verification: targeted builds of the policy stdlib and product modules,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2f: complete direct policy product family

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added direct Surface v2 AccessControl, hash-width Ownable, and owner-gated
  Pausable compositions to the portable policy stdlib. AccessControl hashes
  its `(role, account)` key in portable syntax instead of exposing an
  EVM-specific mapping layout in shared IR.
- Added thin Canonical product modules and extended the adapter-free EVM
  product gate to all six policy products.
- Verification: targeted policy/product builds,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2g: direct map-backed aggregate products

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added direct Surface v2 GuestBook and StatusMessage products. They exercise
  scalar/map storage, caller projection, checked counters, indexed/data event
  fields, and map-backed queries without `contract_source` or Legacy
  adaptation.
- Verification: targeted product builds,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2l: direct VestingVault CFG

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added a direct Surface v2 VestingVault preserving timestamp-driven linear
  vesting, the fully-vested fallback, guarded pro-rata branch, scratch state,
  released/claim ledgers, and event output. This exercises Surface branch CFG
  lowering through checked Canonical Core and EVM planning.
- Verification: targeted product build,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2p: direct Soulbound token body

- Status: `done (verified 2026-07-14)`; 26 of 28 EVM catalog products now have
  direct Surface v2 materialization.
- Added the non-transferable balance body with mint, holder-bound burn,
  supply/balance accounting, and Mint/Burn events. The absence of a transfer
  entrypoint remains explicit in the direct interface.
- Verification: targeted product build,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2n: direct deployment-bound protocol products

- Status: `done (verified 2026-07-14)`; 24 of 28 EVM catalog products now have
  direct Surface v2 materialization.
- Added a target-neutral Surface peer reference and direct protocol facade.
  Logical peer IDs remain in Canonical Core; `PeerMap` converts CLI bindings to
  target-plan metadata, and only the EVM planner validates/resolves the bound
  host as an address.
- Added direct AuthRemoteCall, ExternalTokenTransfer, and ExternalVault
  products, including target-owned method selector resolution.
- Verification: targeted frontend/EVM/product builds,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, protocol
  materialization tests, and `git diff --check`.

## 2026-07-14 - EVM-R2o: direct RoleGatedToken composition

- Status: `done (verified 2026-07-14)`; 25 of 28 EVM catalog products now have
  direct Surface v2 materialization.
- Added a direct role-gated token composition with hashed portable membership
  keys, admin/minter authorization, balance/supply accounting, transfers, and
  role/token events. It composes shared semantics without importing the old
  AccessControl or token Builder mixins.
- Verification: targeted product build,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2m: direct ProRataVault accounting

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added a direct Surface v2 ProRataVault with reusable asset/share conversion
  statements, empty-vault fallback, guarded ratio branches, donation skew,
  share ledgers, deposit/withdraw accounting, and exact product events.
- Verification: targeted product build,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2h: direct portable context products

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added a target-neutral Surface v2 context-product module for HostEnvProbe and
  a reusable binary-lock state machine instantiated by HeightLockVault and
  TimelockVault. The lock policy selects only the portable block-number or
  block-timestamp field; no EVM context constructor enters shared syntax.
- Verification: targeted context/product builds,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2i: direct local-memory array product

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added a portable Surface `memoryRef` type and memory-array expression that
  normalize into Canonical Core `memoryAlloc`, `memoryStore`, and `memoryLoad`
  instructions. The EVM Core planner now maps those nodes into its existing
  memory-array plan and Yul helpers; transaction-scoped EVM memory release is
  an explicit no-op.
- Added a direct ArrayExample preserving local array construction/indexing and
  a focused gate that checks exact Core instruction counts plus emitted EVM
  helpers.
- Verification: `lake env lean --run Tests/Canonical/SurfaceMemoryArray.lean`,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, targeted Core
  validation, and `git diff --check`.

## 2026-07-14 - EVM-R2j: direct Escrow lifecycle

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added a direct Surface v2 EscrowVault preserving two-party initialization,
  one-shot funding, mutually exclusive release/refund states, claim ledgers,
  event schemas, query surface, and exact EVM selectors.
- Verification: targeted product build,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2k: direct staking and storage-deposit accounting

- Status: `done (verified 2026-07-14)`; EVM-R2 remains in progress.
- Added direct Surface v2 StakingVault and StorageDeposit products, covering
  native-value narrowing, caller projections, hash-keyed ledgers, checked
  credit/debit accounting, withdrawal authorization, and event materialization.
- Verification: targeted product builds,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`, and `git diff
  --check`.

## 2026-07-14 - EVM-R2q: direct NFT to ERC-721 materialization

- Status: `done (verified 2026-07-14)`; 27 of 28 EVM catalog products now have
  direct Surface v2 materialization.
- Added an EVM-owned `NFTSpec -> SurfaceContract` materializer. Portable NFT
  intent remains target-neutral while ERC-721 selectors, owner storage,
  mint-authority checks, transfer authorization, and indexed Transfer events
  are introduced only in the EVM materializer.
- Unsupported asset models and feature combinations fail with named
  diagnostics instead of silently losing behavior. The direct product route no
  longer passes through `IntentMaterialization`, `ContractSpec`, or Legacy IR.
- Verification: targeted materializer/product builds,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`,
  `lake env lean --run Tests/NftIntent.lean`, and `git diff --check`.

## 2026-07-14 - EVM-R2r: direct ERC-4626 and complete EVM catalog

- Status: `done (verified 2026-07-14)`; an exact comparison of
  `Examples/Product/catalog.json` with the direct-product gate reports 28 of 28
  EVM catalog products and no remaining product.
- Added a direct EVM ERC-4626 Surface v2 body with 23 entrypoints, standard
  selectors/events, initialization guards, reentrancy locking, pro-rata and
  ceiling conversions, entry/exit fees, conservative max limits, share
  balances/allowances, IERC20 pull/push crosscalls, and vault/recipient FOT
  balance-delta accounting.
- Replaced the EVM Core planner's single-level branch assumption with recursive
  structured CFG lowering. Nested branches, shared continuations, branch-local
  early returns, and reverts now lower without adding target nodes to Core.
- Added host ABI carrier metadata to Surface parameters, returns, and event
  fields. It is preserved in Canonical Interface only; executable Core remains
  target-neutral. Direct ERC-20, ERC-721, and ERC-4626 now preserve standard
  `uint256` ABI words and event signatures despite bounded Core carriers.
- Added `just evm-direct-products` and `just evm-direct-erc4626`. The latter
  compiles optimized strict-assembly, enforces the EIP-170 limit, installs the
  6934-byte runtime in Anvil, and verifies initialization, getters, maxDeposit,
  and repeated-init rejection. EVM-R3 must carry the optimizer into the public
  bytecode route; the unoptimized direct runtime is too large.
- Verification: both focused recipes above,
  `lake env lean --run Tests/Canonical/CoreValidate.lean`,
  `lake env lean --run Tests/ERC4626Stdlib.lean`, `just ir-target-boundary`,
  and `git diff --check`.

## 2026-07-14 - EVM-R3a: public canonical Yul route

- Status: `done (verified 2026-07-14)`; EVM-R3 remains in progress for the
  bytecode/artifact route and the remaining public product dispatch surfaces.
- Added a native `evmCanonicalYul` build operation. A target-first EVM build of
  a Lean Surface v2 source now loads `SurfaceContract`, normalizes it directly
  into checked Canonical Core, builds the EVM-owned semantic plan, and renders
  Yul without converting through `ContractSpec` or Legacy IR.
- Fixed the public `--format yul` resolver, which previously selected
  `--evm-bytecode` and consequently required a Legacy `ContractSpec`. The
  native option builder now also sets NFT mode only for actual NFT operations.
- Added `just evm-canonical-yul-route`, covering driver selection, option
  integrity, real CLI compilation of direct Counter, and strict-assembly solc
  acceptance.
- Verification: `just evm-canonical-yul-route` and `git diff --check`.

## 2026-07-14 - EVM-R3b: public canonical bytecode and plan metadata

- Status: `done (verified 2026-07-14)`; EVM-R3 remains in progress for product
  source cutover and the remaining emit/check compatibility surfaces.
- Added native `evmCanonicalBytecode` dispatch for every Lean source. Surface
  v2 sources now compile through checked Canonical Core and the EVM-owned plan,
  use optimized strict-assembly, fail closed above the EIP-170 runtime limit,
  and never synthesize a `ContractSpec` or Legacy IR module.
- Added direct plan-driven ABI, event, capability, mutability, and storage
  metadata. Artifact metadata identifies `surface-v2` honestly and records the
  not-yet-generated canonical SDK schema as `null`; the old ContractSpec client
  generator is not invoked from this route.
- Preserved entrypoint mutability in `ModulePlan`, fixed plan metadata ABI names,
  and admitted the intentional portable U64 carrier for EVM `uint256` ABI
  words. These values now survive source normalization through artifact output.
- Added `just evm-canonical-bytecode-route`. It compiles direct Counter and the
  23-entrypoint ERC-4626 vault, checks metadata shape, and enforces the runtime
  size limit; the optimized ERC-4626 runtime is 6946 bytes with the solc
  metadata tail.
- Verification: `just evm-canonical-bytecode-route`,
  `just evm-direct-products`, and `git diff --check`.

## 2026-07-14 - EVM-R3c: public canonical check route

- Status: `done (verified 2026-07-14)`; EVM-R3 remains in progress for the
  product-source cutover audit.
- The public `proof-forge check --target evm <surface.lean>` command now loads
  Surface v2 directly, normalizes and validates Canonical Core, checks EVM host
  operation ownership, builds the EVM semantic plan, and dry-renders canonical
  Yul. It does not request a `ContractSpec` or invoke Legacy backend validation.
- Legacy source checking remains isolated in `checkLegacyContractSource` only
  for sources not yet migrated during the ordered chain cutover.
- Added `just evm-canonical-check-route`, including machine-readable evidence
  for source version, canonical normalization, plan construction, and lowering.
- Verification: `just evm-canonical-check-route` and `git diff --check`.

## 2026-07-14 - EVM-R3d: canonical product CLI catalog

- Status: `done (verified 2026-07-14)`; EVM-R3 is complete and EVM-R4 is next.
- Defined `Examples/Product/Canonical` as the EVM materialization source set
  during the ordered chain migration. The primary catalog remains the single
  selector: every entry advertising `evm` must have a same-named Surface v2
  source, while focused collection examples are not silently promoted.
- Added a catalog-driven public CLI gate for all 28 EVM products. Each source
  is compiled through target-first canonical Yul dispatch; logical peer names
  are supplied only as EVM target metadata.
- Added the gate to `just product`, so product-first CI now detects missing
  canonical EVM roots and regressions that only appear through the executable
  command surface.
- The sibling Legacy-authored product sources remain temporarily for NEAR and
  Solana only. EVM no longer consumes them in its product catalog gate.
- Verification: `just evm-canonical-product-route` and `git diff --check`.

## 2026-07-14 - EVM-R4a: delete zero-caller EVM field aliases

- Status: `done (verified 2026-07-14)`; EVM-R4 remains in progress.
- Deleted the zero-caller `Entrypoint.paramEvmAbiWords` and
  `Module.evmProxyPattern?` compatibility aliases. All callers already use the
  chain-neutral `paramAbiWords` and target-resolved `proxyPattern?` fields.
- Removed the obsolete EVM alias from the target-boundary baseline; no wrapper
  or replacement Legacy name was introduced.
- Verification: targeted IR build, `just ir-target-boundary`, repository
  caller search, and `git diff --check`.

## 2026-07-14 - EVM-R4b: remove CREATE from shared fixture authoring

- Status: `done (verified 2026-07-14)`; EVM-R4 remains in progress until the
  now-unproduced Legacy constructors and exhaustive compatibility arms are
  deleted.
- Removed CREATE/CREATE2 actions from the portable `CrosscallProbe`; contract
  deployment is not a chain-neutral crosscall semantic.
- Migrated the EVM-specific crosscall probe to `Contract.Source.Evm` and the
  typed `evm.create/create@1.0.0` / `create2@1.0.0` HostOps. Call value is now
  the declared U128 native-value carrier and the result is an address.
- Updated the Quint portable model expectation so verification no longer
  advertises EVM deployment actions.
- Verification: targeted example builds, canonical EVM host-op tests, Quint
  crosscall model, and `git diff --check`.

## 2026-07-14 - EVM-R4c: delete Legacy CREATE constructors

- Status: `done (verified 2026-07-14)`; EVM-R4 continues with remaining
  zero-caller Legacy EVM APIs.
- Deleted `Expr.crosscallCreate` and `Expr.crosscallCreate2` from the shared IR,
  semantics, classification, refinement, analyzers, and every backend
  compatibility match. No non-EVM backend retains rejection logic for an EVM
  constructor in portable IR.
- Made versioned `evm.create/create@1.0.0` and
  `evm.create/create2@1.0.0` HostOps the only CREATE authoring route. Canonical
  EVM planning now validates and normalizes init code before helper discovery.
- Reduced `EvmCrosscallProbe` to portable call semantics only. The legacy
  crosscall smoke no longer advertises deployment; the canonical HostOp gate
  owns CREATE/CREATE2 type, target, plan, and Yul checks.
- Verification: `lake build ProofForge.Cli.EvmFixtures`,
  `lake env lean --run Tests/Canonical/EvmCreateHostOp.lean`,
  `lake env lean --run Tests/Backend/Evm/EvmSemanticPlan.lean`,
  `scripts/evm/crosscall-ir-smoke.sh` (71 Foundry cases),
  `lake env lean --run Tests/IRPortability.lean`, Solana/NEAR/Psy focused
  diagnostics, `lake env lean --run Tests/Quint/CrosscallModel.lean`, and
  `git diff --check`.

## 2026-07-14 - EVM-R4d: delete zero-caller EVM wrappers

- Status: `done (verified 2026-07-14)`; EVM-R4 continues with Legacy context
  and fixture removal.
- Deleted the unused IR-to-ABI parameter reconstruction wrappers
  `entrypointParamPlansForModule`, `entrypointCallArgsWithPlan`,
  `entrypointCallArgs`, and `abiParamValidationStmts`. Canonical plan-to-Yul
  consumers use `AbiParamPlan` directly.
- Deleted the unused total `EvmBytecodeSemantics.step` compatibility alias and
  its reflexivity theorem. The proof seam exposes only relational `Step`, the
  executable `stepF`, and the bounded driver contract.
- Verification: focused EVM validation and bytecode-semantics builds/smokes,
  caller searches, `just legacy-freeze`, and `git diff --check`.

## 2026-07-14 - EVM-R4e: remove EVM context from shared IR

- Status: `done (verified 2026-07-14)`; EVM-R4 continues with the overloaded
  portable-signer/`tx.origin` name split.
- Deleted `gasPrice`, `baseFee`, `prevRandao`, `coinbase`, and parameterized
  `blockHash` from shared `IR.ContextField`, including every Legacy adapter,
  classifier, semantic interpreter, backend rejection arm, coverage entry, and
  target-boundary allowance.
- Added typed `Contract.Source.Evm` authoring functions for the five operations.
  Their exact versioned HostOps lower through Canonical Core into EVM-owned
  `ContextExprPlan` nodes; the EVM plan no longer converts target context plans
  back into shared `ContextField` values for metadata collection.
- Reduced the portable `ContextProbe` to shared context only. EVM-only context
  ownership is checked by the canonical HostOp gate, while the portable fixture
  and its Foundry smoke continue to cover timestamp, chain id, gas budget, and
  signer behavior.
- Corrected the EVM ABI security matrix so the already-supported/default
  `U64 -> uint256` override is tested as valid instead of contradictory invalid
  input.
- Verification: `lake env lean --run Tests/Canonical/TargetContextHostOps.lean`,
  `just evm-semantic-plan`, `scripts/evm/context-ir-smoke.sh` (5 Foundry cases),
  `lake env lean --run Tests/IRPortability.lean`,
  `lake env lean --run Tests/HostRuntime.lean`,
  `lake env lean --run Tests/ChainAgnosticRoute.lean`, `just evm-coverage`,
  `just ir-target-boundary`, `just legacy-freeze`, and `git diff --check`.

## 2026-07-14 - EVM-R4f: separate signer from EVM origin

- Status: `done (verified 2026-07-14)`; EVM-R4 is complete. The next checkpoint
  is the repository-wide Legacy/Surface/version/product-source cleanup required
  before NEAR migration starts.
- Replaced the overloaded shared `ContextField.origin` with the portable
  `ContextField.signer` intent and added Canonical Core `ContextField.signer`.
  EVM maps it to `tx.origin`, Solana maps it to the first signer account, and
  NEAR maps it to `signer_account_id`; immediate caller/predecessor remains the
  separate `sender`/`caller` intent.
- Kept exact EVM `tx.origin` solely behind the typed
  `Contract.Source.Evm.origin` HostOp. `HostEnv.txOrigin` now rejects Solana and
  NEAR instead of claiming a weak alias, while portable `HostEnv.signer`
  materializes on the primary triad.
- Renamed the WasmHost semantic-plan node from `origin` to `signer` and updated
  Legacy fixtures/backends to consume the portable signer spelling. No shared
  IR constructor or target-boundary allowance named `origin` remains.
- Verification: affected Core/EVM/Solana/WasmHost builds,
  `lake env lean --run Tests/HostRuntime.lean`,
  `lake env lean --run Tests/IRPortability.lean`,
  `lake env lean --run Tests/Canonical/LegacyParity.lean`,
  `lake env lean --run Tests/Backend/Solana/SolanaMapContextSafety.lean`,
  `lake env lean --run Tests/Backend/Wasm/EmitWatContext.lean`,
  `scripts/evm/context-ir-smoke.sh` (5 Foundry cases), `just evm-coverage`,
  `just ir-target-boundary`, `just legacy-freeze`, and `git diff --check`.

## 2026-07-14 - Authoring cleanup A-CUT0: remove backend goldens from Product

- Status: `done (verified 2026-07-14)`.
- Moved the live RemoteCall Solana assembly and NEAR WAT expectations from
  `Examples/Product/goldens` to `Examples/Backend/Solana` and
  `Examples/Backend/WasmNear`. Deleted two unused duplicate golden files.
- `Examples/Product` is now reserved for target-neutral authored contracts and
  product metadata; generated or expected target artifacts belong to backend
  fixtures.
- Updated the portable RemoteCall gate to the backend-owned paths and supplied
  the EVM logical-peer binding now required by the strict canonical plan. The
  EVM leg passes; the subsequent Solana leg currently exposes the pre-existing
  canonical-plan gap for logical non-numeric peer addresses, tracked by the
  authoring cutover rather than hidden by a fallback.
- Verification: source/golden caller audit and `git diff --check`.

## 2026-07-14 - Authoring cleanup A-CUT1a: internalize Surface protocol helpers

- Status: `done (verified 2026-07-14)`; the full Product authoring cutover is
  still in progress.
- Moved the transitional `ProofForge.Contract.SurfaceV2.Protocol` module to
  `ProofForge.Frontend.Surface.Protocol`. The helper operates on internal
  normalization AST values and is no longer advertised as a public Contract
  authoring API or as a second version.
- Updated the three temporary Canonical product callers. They remain migration
  inputs only and will be deleted when the original `contract_source` products
  directly enter Canonical Core.
- Verification: targeted builds for AuthRemoteCall, ExternalTokenTransfer, and
  ExternalVault; repository `SurfaceV2` caller search; `git diff --check`.

## 2026-07-14 - Authoring cleanup A-CUT1: enforce one Product authoring tree

- Status: `done (verified 2026-07-14)`; A-CUT2 is the active task.
- Removed the handwritten Surface duplicates from
  `Examples/Product/Canonical`. `Examples/Product` now contains only the
  target-neutral `contract_source` contracts and product metadata; the Counter
  author source and its business logic are unchanged.
- Isolated the temporary direct-Surface inputs under
  `TestFixtures/SurfaceProducts` with an explicit Lake test-fixture root. These
  values remain only to protect the canonical EVM route until A-CUT3 reaches
  the same behavior from the single authored Product sources.
- Extended `canonical-boundary` and its self-test to reject Surface imports in
  `Examples/Product` and public `ProofForge.Contract.Source*` modules, and to
  reject direct `SurfaceContract` construction in Product sources.
- Corrected `SourceLoader` parity assertions to compare target-neutral Core and
  interface shape without treating target-resolved EVM selectors or a target
  HostOp catalog as source-level equality.
- The separate public helper namespace `ProofForge.Contract.Surface` is not the
  internal Surface AST, but its name still violates the one-authoring-language
  model. A-CUT2/A-CUT3 will move those Product helpers into the Source DSL and
  delete the compatibility namespace.
- Verification: `lake build TestFixtures`,
  `lake env lean --run Tests/Canonical/EvmDirectProducts.lean`,
  `lake env lean --run Tests/Canonical/SourceLoader.lean`, Set/Queue normalize
  and parity tests, `lake env lean --run Tests/CliTargetFirst.lean`,
  `scripts/canonical/check-boundary-self-test.sh`, and
  `scripts/canonical/check-boundary.sh`.

## 2026-07-14 - Legacy production audit: remove obsolete test-only modules

- Status: `done (verified 2026-07-14)`; all remaining Legacy modules have
  production callers and are assigned to the direct frontend, version-entry,
  or target-route cutover.
- Moved the superseded Legacy Core model and validator, deprecated partial
  elaborator and smoke, and Legacy/Core observable-refinement harness from
  `ProofForge/**` into the opt-in `TestFixtures.Legacy` library.
- Removed those exports from `ProofForge.IR`, reduced the exact production
  Legacy import baseline, and taught `canonical-boundary` to reject restoration
  of the retired production paths.
- Recorded the remaining caller-owned deletion points in
  `docs/legacy-production-audit-2026-07-14.md`; none is treated as complete
  merely because it was renamed.
- Verification: `lake build TestFixtures`, legacy Core/elaborator positive and
  negative smokes, Canonical Legacy parity/refinement checks,
  `scripts/canonical/check-legacy-freeze.sh`, both canonical boundary gates,
  and `lake build ProofForge.IR proof-forge`.

## 2026-07-14 - Module ownership: isolate Solana SDK compatibility and Psy runtime

- Status: `done (verified 2026-07-14)`.
- Removed the ambiguous top-level `ProofForge/Solana*` ownership. The public
  authoring entry remains `ProofForge.Contract.Source.Solana`; the old
  `Contract.Builder` implementation is explicitly quarantined under
  `ProofForge.Contract.Source.Solana.Legacy` until the Solana canonical cutover.
- Moved target-specific Solana contracts to
  `Examples/Backend/Solana/Contracts` and updated CLI, tests, Learn parity, and
  gate references to their fixture-owned namespace.
- Moved the `Lean.Psy` extern SDK from `ProofForge.Psy` to
  `ProofForge.Runtime.Psy`, reflecting that it is target runtime glue rather
  than portable contract authoring or compiler backend code.
- Recorded why the optional EVM/Solana refinement libraries must remain outside
  the default `ProofForge` Lake library; their unified `ProofForgeFormal`
  namespace is the next structural slice.
- Verification: targeted Lake build of Psy runtime, public Solana Source,
  quarantined builder, protocol facade, and all Solana backend contract
  fixtures; canonical boundary and topology gates.

## 2026-07-14 - Module ownership: unify optional formal libraries

- Status: `done (verified 2026-07-14)`.
- Moved the sibling `EvmRefinement` and `SolanaRefinement` module roots to
  `ProofForgeFormal/Evm` and `ProofForgeFormal/Solana`. Renamed their independent
  Lake targets to `ProofForgeFormalEvm` and `ProofForgeFormalSolana`; neither is
  imported by the default `ProofForge` library.
- Updated proof imports, smoke scripts, gates, and active English documentation
  to the project-owned formal namespace.
- Repaired two stale proof fixtures exposed by the clean rebuild: the EVM
  context obligation now matches the current three scalar reads and one signer
  hash, and the Solana host bridge resolves overlapping sparse ABI cells by the
  most specific address so the writable byte is not overwritten by the account
  marker word.
- Verification: `lake build ProofForge.Backend.Evm.Refinement
  ProofForgeFormalEvm`; `lake build ProofForgeFormalSolana`; and
  `lake env lean --run ProofForgeFormal/Solana/CompileCorrectSmoke.lean`.

## 2026-07-14 - Authoring cleanup A-CUT2a: internalize Surface implementation

- Status: `done (verified 2026-07-14)`; direct Canonical Core normalization is
  still the active A-CUT2 remainder.
- Deleted the public `ProofForge.Contract.Surface` and
  `ProofForge.Solana.Surface` authoring namespaces. Public contracts now use
  `ProofForge.Contract.Source`; compiler helpers live under
  `Contract.Source.Internal` and `Contract.Source.Solana.Internal`.
- Moved direct EVM `SurfaceContract` construction out of `ProofForge.Contract`
  into `ProofForge.Frontend.Materialize.Evm`, and moved policy AST fixtures to
  `TestFixtures.SurfaceProducts`.
- Updated Product, stdlib, protocol, backend fixture, and targeted test callers.
  The boundary gate rejects restoring the old public files or importing the
  internal implementation from Product/stdlib code.
- Verification: targeted Source/Product/stdlib/materializer builds,
  source-DSL arity, protocol tests, canonical boundary self-test and gate, and
  repository search for the retired public module names.

## 2026-07-14 - Authoring cleanup A-CUT4a: remove the public V1/V2 source split

- Status: `done (verified 2026-07-14)`; deleting temporary Surface fixtures
  remains in A-CUT4 after A-CUT3 reaches feature parity.
- Renamed `LoadedContractSource.legacyV1/surfaceV2` to the non-versioned
  internal cases `authored/surfaceFixture`. Loader diagnostics now identify the
  latter as a migration fixture rather than a second authoring language.
- Replaced `contract_source-v1`, `contract_source-v2`, and `surface-v2`
  metadata with the single stable `contract-source` identity. Removed the
  duplicate SDK/source version constants.
- Verification: affected CLI/compiler build, SourceLoader and source arity
  tests, canonical EVM bytecode/check route, boundary scans, and
  `git diff --check`.

## 2026-07-14 - NEAR N-T5a: one parameterized TokenSpec runtime package

- Status: `done (verified 2026-07-14)`; N-T5 remains open for the
  NEAR-R3/R4 removal of `NearSpec` and Legacy normalization.
- Bare `build --target wasm-near` now preserves `init` and materializes the
  TokenSpec name, symbol, decimals, initial supply, deployer balance, feature
  filtering, generated clients, and token artifact metadata into one package.
- Fixed canonical `NearModulePlan` local declaration collection for typed
  target HostOp results. Without it, AccountId string results emitted uses of
  `$vN/$vN_len` without declaring those locals and `wat2wasm` rejected the
  canonical product artifact.
- `product-token-near` no longer proves a plan and an unrelated stdlib body.
  It builds the Product TokenSpec once, validates Wasm/client/metadata, executes
  init/supply/balance/metadata on the upstream NEAR VM, and checks unsupported
  feature rejection.
- Verification: affected Lean builds, `Tests/NearTokenSpecRuntime.lean`,
  `just product-token-near`, unsupported FeeToken diagnostic, and
  `git diff --check`.

## 2026-07-14 - Authoring cleanup A-CUT2b: frontend-owned normalization

- Status: `done (verified 2026-07-14)`; A-CUT2 remains open until
  `contract_source` stops constructing the transitional `ContractSpec` and
  `IR.Module` exchange value.
- Moved the production canonical normalizer and exhaustive source-schema
  classification from `ProofForge.IR.Legacy` to
  `ProofForge.Frontend.Authored`. The default `ProofForge.IR` module no longer
  imports frontend code, and the production Legacy-import baseline is empty.
- Renamed the implementation entry to `normalizeContractSpec`; production
  callers use only the `Frontend.ContractSpec.normalize` facade. Normalization
  and validation errors remain terminal and use one source-normalization
  diagnostic prefix.
- Corrected portable crosscall ownership exposed by the move: Canonical Core
  now retains numeric target/method handles, while NEAR and EVM target plans
  resolve them through `MaterializationContract.crosscallStrings`. EVM direct
  address/selector parsing remains target-owned.
- Updated the freeze and canonical boundary gates for the frontend-owned
  classification file and removed all production `IR.Legacy.Adapter` imports.
- Verification: targeted frontend/CLI/EVM-plan builds; canonical inventory,
  adapter parity, source-loader, EVM/NEAR/Solana public-route, strict intent,
  and affected Stylus tests; legacy-freeze and boundary self-tests;
  `LEGACY_FREEZE_BASE=HEAD scripts/canonical/check-boundary.sh`; production
  obsolete-reference scans; and `git diff --check`.

## 2026-07-14 - Plan A-CUT1d: align optional formal namespaces

- Status: `planned`; execute before continuing the remaining A-CUT2 frontend
  replacement.
- Confirmed that `ProofForgeFormal` should remain a top-level sibling of
  `ProofForge`: it owns the opt-in `ProofForgeFormalEvm` and
  `ProofForgeFormalSolana` Lake libraries and keeps heavyweight powdr/solanalib
  dependencies outside the default compiler library.
- Found an incomplete part of the earlier directory move: optional proof files
  now live under `ProofForgeFormal/{Evm,Solana}` but mostly still declare
  `ProofForge.Backend.Evm.*` and `ProofForge.Backend.Solana.*` namespaces.
- Added A-CUT1d to rename those declarations to the owning formal namespaces,
  update focused callers, forbid backend compatibility aliases, and verify the
  one-way optional-formal-to-compiler dependency.

## 2026-07-14 - Authoring cleanup A-CUT1d: formal namespace ownership

- Status: `done (verified 2026-07-14)`; A-CUT2 is active again.
- Renamed all powdr-owned declarations to `ProofForgeFormal.Evm.*` and all
  solanalib-owned declarations to `ProofForgeFormal.Solana.*`. No backend
  compatibility aliases were added.
- Made the one previously implicit Solana backend reference explicit after the
  formal namespace stopped inheriting the `ProofForge.Backend.Solana` parent.
- Extended the canonical boundary gate and its negative self-tests to reject
  formal files that declare default backend namespaces, default compiler
  imports of optional formal modules, and retired `EvmRefinement` or
  `SolanaRefinement` roots.
- Verification: `lake build ProofForgeFormalEvm ProofForgeFormalSolana`,
  `just evm-powdr-counter-refinement-smoke`,
  `just solana-solanalib-adapter`, canonical boundary self-test and gate, old
  namespace/import scans, and `git diff --check`.

## 2026-07-14 - Authoring cleanup A-CUT2c: independent authored syntax owner

- Status: `done (verified 2026-07-14)`; A-CUT2 remains open for the Source
  builder and loader exchange-value cutover.
- Moved the independent frontend type system and syntax ownership from
  `Frontend.Surface` to `Frontend.Authored`, with explicit `Authored*` names.
  These types do not alias or import `IR.Expr`, `IR.Statement`, `IR.Module`, or
  target ASTs.
- Reduced `Frontend.Surface.Type` and `Frontend.Surface.Syntax` to temporary
  compatibility aliases used only by compiler fixtures. No constructors are
  owned by the Surface namespace.
- Added the `ProofForge.Frontend.Authored` aggregate module and extended the
  canonical boundary gate with negative tests that reject imports from the
  final authored model back into `IR.Contract`, `IR.Legacy`, or Surface.
- Verification: focused Authored/Surface/TestFixtures builds; Surface, Set,
  Queue, and NEAR HostOp normalization tests; canonical boundary self-test and
  gate; dependency scans; and `git diff --check`.

## 2026-07-14 - Authoring cleanup A-CUT2d: direct authored canonicalizer

- Status: `done (verified 2026-07-14)`; A-CUT2 remains open for Source builder
  schema parity and loader cutover.
- Moved validation, normalization environment, expression/statement lowering,
  and top-level checked Canonical Core assembly from Surface ownership to
  `Frontend.Authored.{Validate,Canonicalize}`.
- Added the direct `normalizeAuthored` entrypoint. It consumes
  `AuthoredContract` and returns `CanonicalBundle` without importing
  `IR.Contract`, `IR.Legacy`, or Surface.
- Reduced Surface normalization to one fixture facade and removed its internal
  NormalizeEnv/Expr/Stmt ownership modules.
- Added `Tests/Canonical/AuthoredCanonicalize.lean` to prove the direct Counter
  contract name, state, functions, and interface order through checked Core.
- Verification: focused Authored/Surface/TestFixtures builds; direct Authored
  canonicalization; existing Surface normalization/parity, Set, Queue, and
  NEAR HostOp tests; canonical boundary self-test/gate; dependency scans; and
  `git diff --check`.

## 2026-07-14 - Plan A-CUT1e: Solana source and target ownership cutover

- Status: `planned`; execute before resuming the remaining A-CUT2 Source
  builder cutover.
- Confirmed that the retired top-level `ProofForge/Solana*` and
  `ProofForge/Psy.lean` paths have already moved to explicit owners. Public
  syntax belongs in `Contract.Source.Solana`, target fixtures belong in
  `Examples/Backend/Solana`, and Psy externs belong in `Runtime.Psy`.
- Found that placement is not yet dependency isolation: both the public Solana
  Source module and its Internal implementation still import and forward to
  `Source.Solana.Legacy`, which constructs the old `Contract.Builder` and
  `IR.Module` route.
- Added A-CUT1e to establish `Target.HostOps.Solana` as the stable capability
  catalog, emit open authored HostOps from public syntax, keep validation and
  materialization in `Backend.Solana.Extension`, and remove Legacy imports from
  the public/internal route. Full zero-caller deletion remains in IR-B5/A-CUT5.

## 2026-07-14 - A-CUT1e-a: open Solana operation identity

- Status: `done (verified 2026-07-14)`; A-CUT1e continues with typed
  account/PDA/CPI payloads and the public Source/Internal Legacy cut.
- Replaced the Canonical materialization intent's raw `label` with the open
  `CapabilityOperation` carrier. Direct Authored contracts can now retain a
  versioned target operation, while the old `Contract.Intent` converts to a
  builtin operation only at the compatibility normalizer boundary.
- Added `Target.HostOps.Solana` with exact signatures for remaining compute
  units, SHA-256, Keccak-256, and Blake3. Registered those IDs in the canonical
  Solana target profile and the direct Authored HostOp catalog.
- Made both validation boundaries fail closed: Canonical requirements reject
  unknown HostOp IDs or mismatched required capabilities, and target capability
  plans reject versioned operations absent from the selected profile. The
  focused test proves EVM cannot accept a Solana operation merely because it
  supports the same broad capability.
- Did not invent metadata-only PDA/CPI HostOp signatures. Those operations need
  typed account, seed, and instruction-data payloads before catalog entry.
- Added `Tests/Canonical/SolanaHostOpCatalog.lean` and wired it into
  `hostop-protocol`; it verifies catalog lookup, profile advertisement, and
  Authored-to-Canonical operation preservation.
- Verification: focused Authored/Registry builds; Solana HostOp catalog,
  Authored canonicalization, Core validation, strict intent materialization,
  Surface normalization, and Solana public-route tests; canonical boundary and
  Legacy freeze gates; target-specific constructor scan; and `git diff --check`.

## 2026-07-14 - A-CUT2e-a: typed effects in the authored schema

- Status: `done (verified 2026-07-14)`; A-CUT2e continues with storage paths,
  collection lifecycle operations, and memory lifecycle parity.
- Changed Authored HostOp expressions to carry an explicit result type instead
  of silently producing `u64`. The normalizer preserves that type and the
  Canonical HostOp catalog rejects disagreement with the registered signature.
- Added declared-error assert/revert statements with typed runtime arguments.
  The direct normalizer resolves the error identity, checks arity and argument
  types, and emits a real `CoreErrorRef`; the old message-only statements remain
  temporary Surface fixture compatibility.
- Added `Tests/Canonical/AuthoredStructuredEffects.lean` with positive shape
  assertions and negative HostOp-result/error-argument cases, and wired it into
  `canonical-foundation`.
- Verification: focused Authored/Surface builds; Authored structured-effects,
  authored canonicalization, Surface normalization/parity, canonical boundary,
  Legacy freeze, and `git diff --check`.

## 2026-07-14 - A-CUT2e-b: logical storage and memory lifecycle

- Status: `done (verified 2026-07-14)`; A-CUT2 schema parity continues before
  the direct Source builder cutover.
- Added target-neutral authored storage paths with map-key, array-index, and
  record-field segments. Path operands are ANF-compatible locals or literals;
  no target slot, account offset, storage prefix, or chain-specific constructor
  entered Authored or Canonical Core.
- Added nested-map state plus storage load/contains/store/remove/length/resize,
  and explicit memory alloc/store/release. The direct normalizer resolves every
  path against declaration and struct-field types before emitting Core.
- Added early nested-map arity validation and fail-closed key/index/value type
  checks. Complex source expressions must be bound before they become path
  operands, keeping the authored compiler AST deterministic.
- Added `Tests/Canonical/AuthoredStorageLifecycle.lean` with map, two-key map,
  dynamic-array, record-field, and memory lifecycle coverage plus a wrong-key
  negative case; wired it into `canonical-foundation`.
- Verification: focused Authored/Surface and fixture builds;
  `canonical-foundation`, Set/Queue normalization, canonical boundary, Legacy
  freeze, and `git diff --check`.

## 2026-07-14 - A-CUT2e-c: portable crosscall schema parity

- Status: `done (verified 2026-07-14)`; direct Source builder work can now use
  one Authored crosscall constructor instead of the old NEAR-specific IR forms.
- Extended the target-neutral Authored crosscall schema with named invocation
  and continuation modes, optional gas/value expressions, JSON argument names,
  inferred parameter types, and explicit return type. No target ABI encoding,
  promise scheduling, account layout, or chain-specific constructor entered the
  authored syntax.
- The direct normalizer preserves these fields in `CoreCrosscallSpec`, rejects
  mismatched argument-name counts, and rejects non-`u64` gas before Core
  validation. Existing Surface protocol and EVM ERC4626 fixture helpers now use
  the complete portable constructor.
- Added `Tests/Canonical/AuthoredCrosscall.lean` with named/continuation shape
  assertions and negative argument-name/gas cases, and wired it into
  `canonical-foundation`.
- Verification: focused Authored/Surface/RemoteCall/ERC4626 builds; authored
  effects, storage lifecycle, and crosscall tests; Surface normalization and
  parity; direct EVM crosscall; canonical boundary and Legacy freeze; and
  `git diff --check`. The broader `EvmDirectProducts` test still exposes its
  pre-existing logical peer literal planning failure (`peer.callee`) and was not
  treated as evidence for this slice.

## 2026-07-14 - EVM-R4g: defer logical peer address materialization

- Status: `done (verified 2026-07-14)`; this is follow-up hardening discovered
  by replaying the direct product catalog after the Authored crosscall update.
- The EVM Core planner now identifies value IDs used as crosscall targets per
  function. Their address literals remain logical peer identities until the
  crosscall is lowered and resolved through `CapabilityPlan` target metadata;
  they are no longer rejected early as malformed physical EVM addresses.
- Ordinary address literals still use strict EVM parsing, and an unbound
  logical peer still fails with the named crosscall-target diagnostic.
- Verification: `Tests/Canonical/EvmDirectCrosscall.lean`, the complete
  28-product `Tests/Canonical/EvmDirectProducts.lean`, and
  `Tests/Backend/Evm/CanonicalPlan.lean` including its invalid-address negative
  case; canonical boundary and `git diff --check`.

## 2026-07-14 - A-CUT2e-d: authored structure and evidence parity

- Status: `done (verified 2026-07-14)`; direct Source builder work no longer
  needs the old `ContractSpec` merely to preserve structure or proof metadata.
- Added Authored-owned field ownership and struct semantics, plus public/private
  and storage-derivation metadata. Direct normalization now writes the semantic
  pieces to Core and presentation/layout pieces to canonical materialization.
- Added Authored verification annotations and preserved Quint invariants,
  Quint liveness properties, and Lean invariant references in canonical
  evidence. These annotations remain non-semantic and cannot affect target
  capability derivation or generated runtime behavior.
- Added `Tests/Canonical/AuthoredMetadata.lean`; it verifies exact layout and
  evidence preservation and confirms unsupported reference ownership fails
  closed rather than silently becoming value ownership. The test is wired into
  `canonical-foundation`.
- Verification: focused Authored and representative Surface fixture builds;
  authored canonicalization/effects/storage/crosscall/metadata tests; Surface
  normalization; canonical boundary and Legacy freeze; and `git diff --check`.

## 2026-07-14 - A-CUT2f-a: direct Authored builder foundation

- Status: `done (verified 2026-07-14)`; the next slice switches
  `Contract.Source.Internal` primitives and then the public macro/loader to this
  builder.
- Added `Frontend.Authored.Builder`, whose module and entry state machines own
  Authored declarations and statements and return one `AuthoredContract`.
  The module has no dependency on `Contract.Builder`, `ContractSpec`,
  `IR.Contract`, Surface, or a target backend.
- Added direct declarations for state, maps, structs, events, errors, entrypoint
  mutability, portable statements, intents, and verification annotations. No
  compatibility conversion or second IR module is produced.
- Added `Tests/Canonical/AuthoredBuilder.lean`, which builds the product Counter
  shape directly and verifies checked arithmetic, entrypoint identity, state,
  and Quint/Lean evidence after checked Canonical normalization. Wired into
  `canonical-foundation`.
- Verification: focused Authored builder/frontend builds; direct builder and
  metadata tests; canonical boundary and Legacy freeze; and `git diff --check`.

## 2026-07-14 - A-CUT2f-b: portable Boolean Core operations

- Status: `done (verified 2026-07-14)`; this removes a common-expression blocker
  for switching `Contract.Source` helpers to the direct Authored builder.
- Added target-neutral `Core.BooleanOp` and `PureOp.boolean` for conjunction and
  disjunction. Core validation requires Bool operands/results, dominance tracks
  both operands, the reference semantics evaluates exact Boolean behavior, and
  capability derivation remains target-independent.
- Direct Authored normalization now lowers `boolAnd`/`boolOr` instead of
  rejecting them. EVM maps the operation to Yul bitwise Boolean words, Solana
  to its semantic bit operation plan, and NEAR/Wasm to the neutral Wasm-host
  arithmetic plan; no target constructor entered Authored or Core.
- Added `Tests/Canonical/AuthoredBoolean.lean` with positive Core shape,
  non-Bool rejection, and EVM/Solana/NEAR canonical-plan acceptance. Wired into
  `canonical-foundation`. The canonical boundary now explicitly covers the new
  Authored builder module.
- Verification: focused direct Boolean tri-target planning; canonical Core
  validation and runtime semantics; canonical boundary and Legacy freeze; and
  `git diff --check`.

## 2026-07-14 - A-CUT2f-c: direct Authored event schemas

- Status: `done (verified 2026-07-14)`; Source emit lowering can now preserve
  event field metadata without constructing a `ContractSpec` event table.
- Added Authored event arguments carrying the field name, indexed flag, optional
  interface ABI word, and target-neutral value expression. The canonicalizer
  discovers event identities in declaration/statement order, resolves field
  types from normalized Core values, and produces matching Core and Interface
  declarations from one schema.
- Repeated emits must agree exactly on names, types, indexing, and ABI metadata.
  Explicit event declarations and positional emits remain supported for
  compiler fixtures, while an event with neither declaration nor emit fails
  closed.
- Added `Tests/Canonical/AuthoredEvents.lean` with inferred-schema, explicit
  compatibility, and conflicting-schema cases; wired it into
  `canonical-foundation`.
- Verification: `lake build ProofForge.Frontend.Authored`,
  `lake build ProofForge.Frontend.Surface.Semantics`, `just canonical-foundation`,
  canonical boundary, Legacy freeze, and `git diff --check`.

## 2026-07-14 - A-CUT1e-b: typed Solana operation payloads

- Status: `done (verified 2026-07-14)`; A-CUT1e-c must now switch the public
  Solana macros and remove their direct/internal Legacy imports.
- Added a target-neutral typed operation payload carrier to `Target.Plan` and
  preserved it through Authored intents, Canonical materialization, and derived
  capability calls. The shared carrier has no Solana field names or semantic
  constructors and rejects empty or duplicate field names.
- Added target-owned versioned Solana account-declare, PDA-derive, and CPI-invoke
  identities plus strict typed schemas. Their decoders reject missing, extra,
  wrongly typed, invalid-enum, and length-mismatched fields.
- Added `Contract.Source.Solana.Internal.Authored`, a direct builder adapter that
  emits typed module/entrypoint intents without importing `Contract.Builder`,
  Legacy IR, Surface, or `Source.Solana.Legacy`. The canonical boundary gate now
  enforces that dependency rule.
- Added fail-closed typed parsing to `ProgramExtensions.fromPlanChecked` while
  retaining the metadata-only `fromPlan` entrypoint for explicit Legacy callers.
  Expanded `SolanaHostOpCatalog` coverage through Authored normalization and the
  backend account/PDA/CPI plan. Repaired the stale TargetRegistry assertion so
  EVM, like NEAR and Solana, is checked against its actual target-owned catalog.
- Verification: focused HostOps/Authored/Solana Extension builds;
  `just hostop-protocol`; Canonical Core validation; TargetRegistry; canonical
  boundary; Legacy freeze; and `git diff --check`.

## 2026-07-14 - A-CUT1e-c1: canonical Solana extension materialization

- Status: `done (verified 2026-07-14)`; A-CUT1e-c2 still owns the public/internal
  macro cutover and removal of `Source.Solana.Legacy` imports.
- Changed the canonical Solana planner to require an exact capability-call list,
  decode target-owned typed extensions fail closed, merge declared and CPI
  accounts into a deterministic indexed layout, and retain scoped PDA/CPI
  definitions and actions in the frozen ModulePlan.
- Changed canonical `lowerFromPlan` to reconstruct account and value bindings
  solely from the Solana plan, insert entrypoint-scoped extension actions, emit
  PDA/CPI helpers, and validate the complete output without rebuilding a Legacy
  `IR.Module`.
- Extended `BpfEncode` to encode defined-label calls as relative eBPF
  pseudo-calls while preserving hashed runtime-syscall encoding. Added a direct
  unit theorem plus a typed account/PDA/CPI normalization-to-bytecode smoke.
- Verification: `lake build ProofForge.Backend.Solana.BpfEncode
  ProofForge.Backend.Solana.Plan.Core`;
  `lake env lean --run Tests/Backend/Solana/SolanaBpfEncode.lean`;
  `lake env lean --run Tests/Canonical/SolanaHostOpCatalog.lean`.

## 2026-07-14 - Post-rebase canonical boundary repair

- Status: `done (verified 2026-07-14)`; no task ownership or migration order
  changed.
- Removed the zero-caller `Compiler.adaptContractSpecCanonical` residue. It
  referenced the deleted `adaptLegacy` API and was hidden by a stale pre-rebase
  `.olean`; public target drivers continue through the direct
  `Frontend.ContractSpec.normalize` boundary.
- Extended the canonical boundary gate and its self-test so retired Legacy
  adapter APIs cannot reappear in production code.
- Updated `requireCapabilityPlan_sound` to cover the target-owned HostOp handler
  rejection branch introduced by the open extension protocol.
- Verification: focused CanonicalPipeline, Target.Formal, and Stylus CLI builds;
  canonical boundary self-test; `just canonical-boundary`;
  `just strict-target-gate`; targeted Stylus, NEAR, and Solana gates; and
  `git diff --check`.

## 2026-07-15 - DOC: Soroban honesty + D-056 sequencing before PR #104 depth

- Status: `done` (documentation only)
- Result: refreshed Soroban Counter MVP docs for custom offline-bridge honesty,
  open gap inventory (P0–P3), and S0–S5 slice order. Recorded D-056: land
  primary-triad direct authoring cutover
  ([PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104)) before deep
  Soroban HostABI/Env or CosmWasm M3/M4. Updated agent checkpoint, backlog B3
  state, Wasm-host analysis, targets index, and README Backend Status row.
- Interfaces: `docs/targets/stellar-soroban.md`, `docs/decisions.md` (D-055/D-056),
  `docs/document-status.md`, `docs/implementation-backlog.md`,
  `docs/superpowers/specs/2026-07-12-wasm-host-target-analysis.md`,
  `docs/target-roadmap.md`, `docs/targets/README.md`, `README.md`, `AGENTS.md`.
- Verification: documentation edit only; no code or gate change.
- Remaining: rebase/merge PR #104; then schedule Soroban S0 if desired.
- Documentation: this entry.

## 2026-07-15 - C3: OpenVM research brief (defer)

- Status: `done` (documentation only)
- Result: Wrote a primary-sourced OpenVM target brief and recorded a reviewed
  **defer** on backend, registry id, CLI target, and shared ZK HostOps. Preferred
  future spike (if reopened) is Rust guest sourcegen + `cargo openvm` oracle,
  not hand-written Core→RV32. Upstream Lean FV (openvm-fv, Lean 4.26) is
  documented as a non-drop-in proof boundary relative to ProofForge's v4.31.0.
- Interfaces: `docs/targets/openvm-research.md`; index updates in
  `docs/targets/README.md`, `docs/target-roadmap.md`, `docs/document-status.md`,
  `docs/implementation-backlog.md`, portable-intent plan Task 12, ZK analysis,
  `AGENTS.md`, and zh backlog/targets index.
- Verification: `just docs-check`; `git diff --check` (run with this change).
- Remaining: none for C3; implementation remains closed until reopen checklist
  in the brief is satisfied. Active merge priority is still PR #104.
- Documentation: this entry.

## 2026-07-15 - D-057: Lean/Rust boundary design (docs only)

- Status: `done` (documentation only; implementation deferred)
- Result: Accepted the Lean/Rust ownership boundary as deferred design: Lean
  owns product meaning through checked Core + CapabilityPlan; Rust owns
  evidence runners now and optional later plan/render behind dual-run. Recorded
  Phase 0–4 order, A0/A1 sub-seams, equivalence dimensions, lockfile reality vs
  goal, and companion Artifact Contract v1 + Core export v0 drafts. Did not
  change the active AGENTS checkpoint (still PR #104 / cutover).
- Interfaces: `docs/superpowers/specs/2026-07-15-lean-rust-boundary-design.md`,
  `docs/superpowers/specs/2026-07-15-artifact-contract-v1.md`,
  `docs/superpowers/specs/2026-07-15-core-export-v0-draft.md`, D-057 in
  `docs/decisions.md`, deferred LR-0… slices in backlog, lifecycle index,
  architecture pointer.
- Verification: `just docs-check`; `git diff --check` (run with this change).
- Remaining: implement LR-0 on a dedicated branch/worktree after cutover
  priority allows; do not start LR-2+ while Core single-path is still moving.
- Documentation: this entry.

## 2026-07-15 - D-057: Chinese translations for Lean/Rust boundary specs

- Status: `done` (documentation only)
- Result: Added co-located Chinese translations for the three D-057 specs
  (boundary, artifact contract v1, core export v0), following the existing
  `*.zh.md` sibling pattern used by other superpowers designs. Linked EN↔zh
  and pointed zh architecture/backlog/decisions at the Chinese paths.
- Interfaces:
  `docs/superpowers/specs/2026-07-15-lean-rust-boundary-design.zh.md`,
  `docs/superpowers/specs/2026-07-15-artifact-contract-v1.zh.md`,
  `docs/superpowers/specs/2026-07-15-core-export-v0-draft.zh.md`, plus EN
  Chinese: lines and lifecycle/index zh link updates.
- Verification: `just docs-check`; `git diff --check` (run with this change).
- Remaining: none for translation; LR-0 code still deferred.
- Documentation: this entry.

## 2026-07-15 - LR-0: Artifact Contract v1 (Seam B)

- Status: `done` (verified at `1716904d`; PR [#105](https://github.com/DaviRain-Su/proof_forge/pull/105))
- Result: Froze consumer field allowlist and primary-triad emitter inventory in
  `ProofForge.Target.ArtifactContract`; added Lean inventory/field gate
  `Tests/ArtifactContractV1.lean`; taught testkit core
  `validate_artifact_contract_v1` to fail closed on missing
  `schemaVersion`/`target`/`artifactKind`/`sourceModule` and, for execution
  scenarios, missing `artifacts` + advertised `finalOutput`/`primaryOutput`.
  Nested `ArtifactBundle` honesty rules unchanged. Secondary emitters
  inventoried without forcing full primary-triad shape in this slice.
- Interfaces: `ProofForge/Target/ArtifactContract.lean`,
  `Tests/ArtifactContractV1.lean`, `testkit/core/src/lib.rs`
  (`validate_artifact_contract_v1`), `just artifact-contract-v1`, design
  checklist + observation contract note in
  `docs/superpowers/specs/2026-07-15-artifact-contract-v1.md`.
- Verification: `just artifact-contract-v1`; `cargo test -p proof-forge-testkit-core artifact_contract`;
  `git diff --check`; i18n backlog hash sync (run with this change).
- Remaining: merge PR #105; do not start LR-1 Core export until cutover quiet;
  optional follow-up to add `artifactBundle` to secondary Solana/learn emitters
  when their harnesses need execution metadata.
- Documentation: this entry; backlog LR-0 → done; AGENTS checkpoint → land #105.

## 2026-07-15 - LR-1a: experimental core.v0 export + pf-core-inspect

- Status: `in_progress` (stacked on PR #105; not a product CLI path)
- Result: Added `ProofForge.IR.Core.Export` (validate→deterministic JSON body),
  Lean gate `Tests/Canonical/CoreExport.lean`, and standalone Rust
  `tools/pf-core-inspect` with zero chain SDK deps. Capability-plan companion is
  a stub; full CLI `export-core` and product Counter export remain LR-1.
- Interfaces: `ProofForge/IR/Core/Export.lean`, `tools/pf-core-inspect`,
  `just core-export-v0`.
- Verification: `just core-export-v0`; inspect smoke on
  `build/export/tiny-lr1a/evm` (local, not committed).
- Remaining: wire experimental CLI under non-default flag; fill CapabilityPlan
  via resolveSpec; avoid Examples/Product / authoring paths until #104 quieter.
- Documentation: backlog LR-1a; this entry; core-export draft status note.

## 2026-07-15 - LR-1b: experimental export-core CLI package

- Status: `in_progress`→package path done (PR #105 branch)
- Result: Added `proof-forge export-core --experimental` (fixture counter /
  value-vault) writing `core.v0.json`, `capability-plan.v0.json`,
  `export-meta.json` (contentHash over on-disk bodies), and
  `source-manifest.json`. Fail-closed without `--experimental`. Capability ids
  come from normalize requirements; hostOpHandlers remain stub.
- Interfaces: `ProofForge/Cli/ExportCore.lean`, `just core-export-v0`,
  `tools/pf-core-inspect check`.
- Verification: `lake env lean --run Tests/Canonical/CoreExportPackage.lean`;
  `pf-core-inspect check build/export/lr1b-counter/evm`.
- Remaining: product-source input path; full HostOp handler table; optional
  proof-forge binary e2e once CI recovers. Stay off default product build.
- Documentation: backlog LR-1b; this entry.

## 2026-07-15 - LR-1b+: product-source + ValueVault core export

- Status: `done` (stacked on PR #105)
- Result: `export-core --experimental` accepts fixtures `counter`/`value-vault`
  and product `Examples/Product/Counter.lean`. Clarified in usage that this is
  Seam A Core export for Rust backends, not ABI/SDK JSON. Product Counter and
  IR fixture Counter produced the same contentHash on this pin (39fdcf2f…).
- Verification: `Tests/Canonical/CoreExportPackage.lean`; `pf-core-inspect`
  on counter, value-vault, product-counter packages.
- Remaining: HostOp handler table; more product modules; main merge when ready.

## 2026-07-15 - LR-1c: HostOp handlers + product ValueVault export

- Status: `done` (PR #105 branch)
- Result: capability-plan.v0 now carries `hostOpHandlers` resolved from Core
  hostCalls against target signature catalogs (evm/solana/near). Missing
  handler fail-closed. Product ValueVault export added. Counter/ValueVault
  still have 0 handlers (no hostCalls) which is honest.
- Verification: CoreExport + CoreExportPackage; pf-core-inspect on product
  packages; resolveHostOpHandlers NEAR-on-evm refuse / wasm-near accept.
- Remaining: more hostCall-heavy products; optional full target catalog dump;
  merge main when available. Still not product default compile.

## 2026-07-15 - LR-1d: general Seam A export package

- Status: `done` (PR #105 branch)
- Result: Shifted from example stacking to a **general** export package:
  (1) Normalize HostOp catalog registers EVM+Solana+NEAR; (2) capability-plan
  carries structured `requirements`, used `hostOpHandlers`, and full
  `targetHostOpCatalog`; (3) `interface.v0.json` for entrypoint surface
  (outside contentHash); (4) multi-target property that Core body is identical
  across the primary triad; (5) data-driven product smoke (Counter/ValueVault/
  Ownable). Products are smokes for the general path, not the feature itself.
- Verification: `CoreExport` + `CoreExportPackage` + `CoreExportGeneral`;
  pf-core-inspect on multi-target packages.
- Remaining: hostCall-heavy modules exercise non-empty used handlers;
  optional CLI matrix; merge main when available. Still experimental.

## 2026-07-15 - LR-1e: hostCall stress + inspect compare

- Status: `done` (PR #105 branch)
- Result: (1) Public `exportContractSpec` for programmatic packages;
  (2) CREATE/CREATE2 export yields non-empty `hostOpHandlers` on evm and
  fail-closes on near/solana; (3) `pf-core-inspect compare` checks Core
  identity across targets; (4) general smoke keeps triad identity on
  Counter+ValueVault and multi-product on evm only (memory-bounded).
- Verification: CoreExportHostCall; CoreExportGeneral; inspect check+compare.
- Remaining: optional full catalog sweep in CI lane; main merge as available.

## 2026-07-15 - LR-2a: Rust pf-core read-only package loader

- Status: `done` (PR #105 branch)
- Result: Added `tools/pf-core` library that loads Seam A packages
  (`core.v0`, capability-plan, optional interface), verifies contentHash,
  checks used hostOps ⊆ targetHostOpCatalog, and supports Core identity
  compare. `pf-core-inspect` is now a thin CLI over `pf-core` with
  check/summary/compare. Checked-in fixtures under
  `tools/pf-core/tests/fixtures/`. Still zero chain SDKs; not a compile backend.
- Verification: `cargo test -p pf-core`; inspect check/summary/compare on fixtures.
- Remaining: optional typed Core op walk / interpreter; dual-run hooks later
  (LR-2+). Default product compile remains Lean.

## 2026-07-15 - LR-2b: Core op walker and dual-run readiness

- Status: `done` (PR #105 branch)
- Result: `pf-core` walks Core instruction/terminator kinds, collects hostCalls
  from body, checks body↔plan handler equality, and reports dual-run readiness
  (observeReady yes; rustLowerPilot no). Added explicit `EvmLowererPilot`
  stub that fail-closes with a clear not-implemented error. Inspect `summary`
  prints walk + dualRun lines.
- Verification: `cargo test` in tools/pf-core (6 tests).
- Remaining: real EVM lower pilot (still optional); keep product CLI Lean.

## 2026-07-15 - LR-2c: EVM storage-only lower sketch

- Status: `done` (PR #105 branch)
- Result: First real `buildFromCore` pilot slice: modules whose Core walk is
  pure+storage only (e.g. Counter) produce `evm-storage-sketch.v0.json` with
  provisional scalar slots and entrypoint surface. HostCall modules (CREATE)
  refuse fail-closed. CLI: `pf-core-inspect lower-sketch`. Still not bytecode
  and not product CLI default.
- Verification: cargo test pf-core (7 tests); lower-sketch on counter fixture.
- Remaining: optional Yul/render dual-run later; keep Lean product path.

## 2026-07-15 - LR-2d: observe dual-run Lean plan vs storage sketch

- Status: `done` (PR #105 branch)
- Result: Lean dumps `lean-evm-observe.v0.json` from EVM `buildFromCore`
  (entrypoint names/mutability/selectors + storage slots). Rust
  `pf-core-inspect dual-run-observe` builds storage sketch from the export
  package and checks entrypoint name order and provisional slot alignment.
  Counter green. Not bytecode dual-run.
- Verification: `Tests/Canonical/DualRunObserve.lean`; dual-run-observe CLI.
- Remaining: more modules; optional Yul/bytecode dual-run later.

## 2026-07-15 - GOAL + LR-2e: durable Seam A charter; ValueVault dual-run

- Status: `done` (verified at `842994d6`)
- Result: Added continuous execution charter
  `docs/agent-goal-prompt-lean-rust-seam-a.md`. Extended EVM scalar storage
  sketch to allow Core `contextRead` and `emit` (still no hostCall/memory/
  crosscall; not bytecode). ValueVault observe dual-run green: 7 entrypoints
  + 6 scalar slots align with Lean `buildFromCore`. CREATE still refuses.
  `just core-export-v0` dual-run steps cover Counter and ValueVault.
- Verification: `cargo test --manifest-path tools/pf-core/Cargo.toml`;
  `lake env lean --run Tests/Canonical/DualRunObserve.lean`;
  `pf-core-inspect dual-run-observe` on
  `build/export/lr2d-dual-run/counter-evm` and
  `build/export/lr2e-dual-run/value-vault-evm`.
- Remaining: LR-2f Ownable dual-run; contentHash stability; promote
  core-export-v0 checklist; stop-condition review against goal success.
- Documentation: charter, backlog EN+zh, `AGENTS.md` checkpoint.

## 2026-07-15 - LR-2f: Ownable observe dual-run

- Status: `done` (PR #105 branch)
- Result: Extended scalar storage sketch to allow Core `assert` (Ownable).
  Product Ownable still lacks EVM selectors for full `buildFromCore`; DualRunObserve
  falls back to interface + sequential Core state surface dump for Seam A
  dimensions. dual-run-observe green: 4 entrypoints + 2 slots. CREATE still
  refuses hostCall modules.
- Verification: DualRunObserve + dual-run-observe on
  `build/export/lr2f-dual-run/ownable-evm`.
- Remaining: LR-2g contentHash stability; LR-2h docs; stop review.
  Optional later: fill Ownable selectors for full ModulePlan dump.

## 2026-07-15 - LR-2g/2h: contentHash stability + core-export-v0 docs

- Status: `done` (PR #105 branch)
- Result: Counter re-export asserts identical core/plan/export-meta bytes;
  pf-core unit test reloads fixture contentHash. core-export-v0 draft documents
  package layout, hash rule, dual-run dimensions, and implementation status
  through LR-2g. EN+zh backlog/spec synced.
- Verification: `cargo test` pf-core (9); CoreExportPackage.lean.
- Remaining: optional LR-2i CI note; LR-2j stop-condition review (success
  largely met for Counter+ValueVault dual-run).

## 2026-07-15 - LR-2f…2j: Ownable dual-run through Seam A goal success

- Status: `done` (verified at `5929e3b0`)
- Result: Ownable dual-run with assert-eligible sketch + surface dump fallback;
  contentHash stability gates; core-export-v0 package/dual-run docs; validation-gates
  rows for `just core-export-v0` and `just artifact-contract-v1`. Goal charter
  success condition met: general export-core, pf-core/inspect, Counter+ValueVault
  observe dual-run, CREATE refuse, product CLI remains Lean.
- Verification: DualRunObserve; dual-run-observe Counter/ValueVault/Ownable;
  pf-core tests; CoreExportPackage; docs-check i18n.
- Remaining: land PR #105; optional later Ownable selectors for full ModulePlan;
  no LR-3 default Rust lower without new human goal.

## 2026-07-15 - Seam A goal re-verify (stop condition)

- Status: `done` (code re-verified at `5929e3b0`; docs at `3cdbaf14`)
- Result: Full success-condition re-run on PR #105 branch. No code fix required.
  Stale human paste template that still said “start at LR-2j” updated to success-met
  stop guidance. Pipeline composition / in-process FFI remains out of scope.
- Verification (all exit 0):
  - `just core-export-v0` (export package, triad Core identity, hostCall refuse on
    near/solana, pf-core 9 tests, dual-run Counter/ValueVault/Ownable)
  - CREATE `lower-sketch` refuse: hostCalls not allowed
  - `export-core` requires `--experimental`; product CLI default remains Lean
  - `tools/pf-core` + `pf-core-inspect` Cargo.toml: zero chain SDK deps
- Remaining: land/review PR #105; do not start LR-3 without a new human goal.

## 2026-07-15 - D-058: freeze Rust machine-IR product lower

- Status: `done` (PR #105 branch)
- Result: Decision **D-058** — do not invest in Rust re-implementation of
  primary-triad machine IR printers (sBPF `.s`, WAT, parallel Yul) without a
  ready library or intentional sourcegen strategy. Product lower stays Lean.
  Rust keeps evidence runners + Seam A read-only inspect/sketch only. Updated
  boundary Phase 2/3 to deferred; backlog LR-2/LR-3 deferred; pf-core honesty
  (`EvmStorageSketchPilot`, `ready_for_rust_lower_pilot` always false, dual-run
  notes cite D-058).
- Verification: `cargo test --manifest-path tools/pf-core/Cargo.toml`.
- Remaining: land PR #105; invest Lean product lower / cutover, not Rust printers.

## 2026-07-15 - LR-S1/S2: dual-run selector hydrate + export-inspect (no Rust lower)

- Status: `done` (PR #105 branch)
- Result: Under D-058, improve Seam A **without** product Rust lower:
  (1) `hydrateEvmSelectorsMissing` + DualRunObserve resolve Foundry `cast` so
  portable Ownable fills missing selectors and takes full ModulePlan observe
  dump (surface fallback remains if cast absent);
  (2) `just export-inspect` orchestrates `export-core --experimental` +
  pf-core-inspect check/summary as a one-shot pipeline.
  Backlog LR-S1…S5 records pure Lean keccak / optional observe export / product
  lower quality as next non-Rust-lower work.
- Verification: `lake env lean --run Tests/Canonical/DualRunObserve.lean`
  (Ownable: buildFromCore ModulePlan); dual-run-observe ownable-evm ok.
- Remaining: LR-S3 pure Lean keccak; product Lean lower quality; land PR #105.
