# Portable Intent and Target Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a target-neutral intent materialization boundary and a minimal executable NFT product across EVM, Solana, and NEAR, then apply the same strict promotion discipline to Wasm-host and ZK targets.

**Architecture:** Portable specs normalize to `IntentContract`. A registry dispatches `(targetId, IntentFamily)` to target materializers returning ordinary `ContractSpec` values. Canonical Core stays target-neutral; target-specific behavior remains in materializers, plans, protocol contracts, and typed HostOps.

**Tech Stack:** Lean 4, Lake, ProofForge Canonical Core and target plans, `just`, existing EVM/Solana/NEAR harnesses.

## Global Constraints

- The primary advertised `contract_source` targets remain `evm`, `solana-sbpf-asm`, and `wasm-near`.
- Portable frontend and Surface code never branch on `targetId`.
- No target-specific Canonical Core constructors are introduced.
- Existing TokenSpec and primary-triad product behavior remain stable.
- A promoted target fails closed for its declared supported fragment.
- Existing NFT stdlib modules are audited candidates, not assumed compliant.
- Run `just product` before backend-heavy gates and `just check` before merge.
- Stage only task-owned files.

---

## Workstream A: Portable Intent and NFT

### Task 1: Isolate Solana Grammar Ownership

**Files:**
- Modify: `ProofForge/Contract/Source.lean`
- Modify: `ProofForge/Contract/Source/Solana.lean`
- Create: `Tests/SourceDslIsolation.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: portable grammar without Solana PDA/CPI/realloc productions.
- Preserves: existing `Source.Solana` syntax and generated IR.

- [x] Write a failing test proving Solana forms are visible through `Contract.Source`.
- [x] Move Solana seed categories and Solana-only `contractItem`/`entryStmt` productions to `Source/Solana.lean`; retain shared categories in `Source.lean`.
- [x] Verify the portable import rejects the forms and the Solana import accepts them.
- [x] Run `lake env lean --run Tests/SourceDslIsolation.lean`, `just portable-default`, `just solana-light`, `just product`, and `git diff --check`.
- [x] Commit with `git commit -m "refactor(dsl): isolate Solana grammar in Source.Solana"`.

### Task 2: Add the Intent Materializer Contract

**Files:**
- Create: `ProofForge/Contract/Intent.lean`
- Create: `ProofForge/Contract/Intent/Registry.lean`
- Create: `Tests/IntentRegistry.lean`
- Modify: `ProofForge.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `IntentFamily`, `IntentContract`, `IntentMaterialization`, `IntentMaterializer`, `resolveIntentMaterializer`.
- Consumes: `ContractSpec`, capability requirements, target IDs.

- [x] Test duplicate-key rejection, exact lookup, missing materializer diagnostics, and error preservation.
- [x] Implement the exact structures from the companion design.
- [x] Make registry creation reject duplicate `(targetId, family)` keys.
- [x] Run `Tests/IntentRegistry.lean`, `just token-feature-matrix`, `just product`, and `git diff --check`.
- [x] Commit with `git commit -m "feat(intent): add target materializer contract"`.

### Task 3: Define NFT Intent

**Files:**
- Create: `ProofForge/Contract/Nft.lean`
- Create: `Tests/NftIntent.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `NFTAssetModel`, `NFTFeature`, `NFTSpec`, `NFTSpec.validate`, `NFTSpec.toIntentContract`.
- Does not produce target artifacts.

- [ ] Test empty identity, duplicate features, `soulbound + transferable`, defaults, and stable feature IDs.
- [ ] Implement the asset model and feature enum from the design document.
- [ ] Return all deterministic authoring errors before target selection.
- [ ] Run `Tests/NftIntent.lean`, `Tests/IntentRegistry.lean`, `just product`, and `git diff --check`.
- [ ] Commit with `git commit -m "feat(nft): define portable NFT intent"`.

### Task 4: Audit NFT Implementation Candidates

**Files:**
- Modify: `ProofForge/Contract/Stdlib/ERC721.lean`
- Modify: `ProofForge/Contract/Stdlib/MetaplexNft.lean`
- Modify: `ProofForge/Contract/Stdlib/NearNft.lean`
- Create: `Tests/NftImplementationContract.lean`
- Create: `docs/nft-implementation-status.md`

**Interfaces:**
- Produces: one verified `unique + mintable + transferable` lifecycle contract per primary target.
- Produces: explicit unsupported-feature inventory.

- [ ] Assert exact init, mint, transfer, owner/balance, event, parameter, and return contracts from each `ContractSpec`.
- [ ] Test mint authority, duplicate mint rejection, transfer authority, state transition, and event payloads.
- [ ] Repair only the minimal slice; defer royalty, enumeration, collection, and multi-token behavior.
- [ ] Document implemented semantics separately from unverified standards compliance.
- [ ] Run the focused test, `just evm-all`, `just solana-light`, `just wasm-near-plan`, `just product`, and `git diff --check`.
- [ ] Commit with `git commit -m "fix(nft): align primary target implementation contracts"`.

### Task 5: Add Primary-Triad NFT Materializers

**Files:**
- Create: `ProofForge/Contract/Nft/Materialize.lean`
- Create: `Tests/NftMaterialization.lean`
- Modify: `ProofForge/Contract/Intent/Registry.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `evmNftMaterializer`, `solanaNftMaterializer`, `nearNftMaterializer`, `nftIntentRegistry`.
- Returns: `IntentMaterialization` containing a real `ContractSpec`.

- [ ] Test standard IDs and inspect returned specs for the minimal unique slice.
- [ ] Test named rejection for multi-token on unsupported targets and every deferred feature.
- [ ] Implement EVM/ERC-721, Solana/Metaplex, and NEAR/NEP-171-shaped materializers.
- [ ] For every accepted case run `adaptLegacy`, `validateCanonical`, capability planning, and target `buildFromCore` without advisory error swallowing.
- [ ] Run `Tests/NftMaterialization.lean`, `just product`, `just check`, and `git diff --check`.
- [ ] Commit with `git commit -m "feat(nft): materialize portable NFT intent on primary targets"`.

### Task 6: Open the NFT CLI and Product Route

**Files:**
- Modify: `ProofForge/Cli/Args.lean`
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `ProofForge/Cli/ContractSourceArtifacts.lean`
- Create: `Examples/Product/Nft.lean`
- Create: `scripts/portable/nft-multi-target.sh`
- Create: `Tests/NftArtifactSchema.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: one NFT input compiled to three target artifact/SDK bundles.

- [ ] Pin CLI parsing, target resolution, standard metadata, relative artifact references, and rejection diagnostics.
- [ ] Reuse generic TokenSpec loader/artifact patterns without duplicating target emitters.
- [ ] Add lifecycle smoke coverage for mint, owner/balance, authorized transfer, unauthorized rejection, and duplicate mint.
- [ ] Add the smoke to `just product` only after all primary targets pass.
- [ ] Run focused tests, the multi-target script, `just product`, `just check`, and `git diff --check`.
- [ ] Commit with `git commit -m "feat(product): add portable NFT primary-triad route"`.

## Workstream B: Wasm-Host Promotion

### Task 7: Extract a Neutral Wasm-Host Plan

**Files:**
- Create: `ProofForge/Backend/WasmHost/ModulePlan.lean`
- Create: `ProofForge/Backend/WasmHost/ModulePlan/Core.lean`
- Create: `ProofForge/Backend/WasmHost/AbiPlan.lean`
- Modify: `ProofForge/Backend/WasmHost/NearModulePlan.lean`
- Modify: `ProofForge/Backend/WasmHost/NearModulePlan/Core.lean`
- Modify: `ProofForge/Backend/WasmHost/EmitWat.lean`
- Create: `Tests/Canonical/WasmHostPlanPreservation.lean`

**Interfaces:**
- Produces: `WasmHostModulePlan`, `WasmHostAbiPlan`, `HostBridgePlan`.
- Preserves: NEAR canonical WAT and runtime behavior.

- [ ] Pin NEAR plan and WAT preservation before renaming/extraction.
- [ ] Introduce neutral public types and `ModulePlan.Core.buildFromCore` with temporary NEAR compatibility aliases.
- [ ] Move Borsh planning behind a NEAR ABI builder.
- [ ] Update EmitWat to consume the neutral plan.
- [ ] Run canonical parity, NEAR ABI, promise, FT E2E, product, check, and diff gates.
- [ ] Commit the extraction without adding Soroban behavior.

### Task 8: Add a Strict Canonical Target Gate

**Files:**
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Create: `Tests/Canonical/StrictTargetGate.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `runStrictCanonicalTargetGate`.

- [ ] Test adapter, validator, HostOp, builder, and unknown-target failures.
- [ ] Implement strict behavior without changing the legacy advisory route.
- [ ] Add positive primary-triad fixture tests.
- [ ] Run canonical, product, check, and diff gates; commit.

### Task 9: Promote Soroban Counter

**Files:**
- Modify: `ProofForge/Backend/WasmHost/ModulePlan/Core.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Create: `Tests/Canonical/SorobanPublicRoute.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: strict canonical Counter planning and artifact routing for Soroban.
- Rejects: NEAR-only HostOps and unsupported ABI/auth operations.

- [ ] Add failing strict-gate tests.
- [ ] Implement Soroban ABI, auth, and bridge-plan selection.
- [ ] Add Counter host-interpreter parity and artifact checks.
- [ ] Add RemoteCall only after `invoke_contract` parity passes.
- [ ] Run Soroban, canonical, product, docs, check, and diff gates; commit without changing primary-triad status.

## Workstream C: ZK Target Promotion

### Task 10: Add PSy Canonical Planning

**Files:**
- Create: `ProofForge/Backend/Psy/Plan/Core.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Create: `Tests/Canonical/PsyPublicRoute.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `Psy.Plan.Core.buildFromCore` and a strict Counter fixture gate.
- Does not change registry maturity or public input modes.

- [ ] Test supported Core operations and stable rejection diagnostics.
- [ ] Implement the supported Core-to-Psy plan subset.
- [ ] Compare canonical and legacy metadata/capability inventories.
- [ ] Run all Psy, product, check, and diff gates; commit.

### Task 11: Add an Aleo Semantic Plan

**Files:**
- Create: `ProofForge/Backend/Aleo/Plan.lean`
- Create: `ProofForge/Backend/Aleo/Plan/Core.lean`
- Modify: `ProofForge/Backend/Aleo/IR.lean`
- Create: `Tests/Canonical/AleoPublicRoute.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: an inspectable plan between Canonical Core and Leo AST.
- Does not open public `contract_source` routing.

- [ ] Pin current Counter output.
- [ ] Define plan storage, function, context, and crosscall contracts.
- [ ] Implement strict Core-to-plan lowering and render Leo from the plan.
- [ ] Run Aleo source/printer gates and the real Leo gate when installed.
- [ ] Run product/check/diff gates and commit with maturity unchanged.

### Task 12: Write the OpenVM Target Brief

**Files:**
- Create: `docs/targets/openvm-research.md`
- Modify after approval only: `docs/target-roadmap.md`

**Interfaces:**
- Produces: a sourced go/defer decision, not code or registry entries.

- [ ] Pin release, ISA, executable, proof, verifier, I/O, license, and tool commands from primary sources.
- [ ] Record exact CI hardware/time requirements.
- [ ] Identify the pinned Lean semantics dependency and proof boundary.
- [ ] Compare direct RV32 lowering with generated Rust guest approaches.
- [ ] Obtain design approval before creating implementation tasks.

## Deferred Work

- Additional NFT features and multi-token support.
- DAO and Vault intent families.
- Protocol-wrapper expansion.
- CosmWasm message/reply and CW-20/CW-721 lanes.
- PSy/Aleo public product promotion.
- OpenVM backend implementation and shared ZK HostOps.

## Per-Task Review Gate

Every task runs its focused tests, then:

```bash
git diff --check
just product
```

Run `just check` before merge. Review each commit against its declared
interfaces before starting the next task.

## Self-Review

- The plan delivers a working NFT vertical slice rather than only enums.
- Frontend and Canonical Core remain target-neutral.
- Existing NFT candidates are audited rather than recreated.
- Wasm-host extraction precedes Soroban promotion.
- Strict gates replace advisory success for promoted fragments.
- PSy/Aleo plan work is separate from public maturity changes.
- OpenVM begins with a sourced brief.
