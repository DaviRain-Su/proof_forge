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
