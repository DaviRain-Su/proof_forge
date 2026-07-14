# Portable Intent Abstraction and Target Materialization

## Status

Accepted direction, refreshed after the 2026-07-12 `origin/main` merge and
Task 22 integration. This document defines the architecture. The companion
implementation plan defines reviewable delivery tasks.

## Goal

Portable product authors describe business intent once. Target selection
happens only at the compiler boundary, and each target either materializes the
intent through its native plan or rejects it with a named, testable diagnostic.

This design does not use Lean as a replacement assembler. Lean defines and
checks the contracts between authoring intent, Canonical Core, capability
planning, target materialization, and emitted artifacts.

## Current Baseline

The repository now has the direct architectural foundation:

- `contract_source` Counter authoring emits one `AuthoredContract`.
- Public loading normalizes directly to
  `CheckedCanonicalContract -> CapabilityPlan -> buildFromCore`.
- EVM, Solana, and NEAR target plans with canonical parity gates.
- Typed, versioned HostOps for target-specific operations.
- Portable remote calls with target-specific materialization.
- `Stdlib.ERC721`, `Stdlib.ERC1155`, `Stdlib.MetaplexNft`, and
  `Stdlib.NearNft` implementation candidates.
- A target-neutral `WasmHostModulePlan` with NEAR and Soroban bridge ownership.
- Solana runtime account graph, instruction-data length, duplicate/exact account
  count, signer, writable, and owner checks.

Remaining relevant gaps:

- Only Counter has completed the direct public Source/Loader cutover; remaining
  Product and stdlib callers are explicitly quarantined under `Source.Legacy`.
- Existing NFT and Token intent materializers still return deletion-bound
  `ContractSpec` values and must move to direct Authored/Canonical outputs.
- Temporary Surface fixtures, old loaders, and Legacy target routes remain until
  their callers move, then must be deleted rather than maintained as compatibility.
- PSy and Aleo remain fixture/research routes without canonical public-product
  promotion.

## Non-Negotiable Boundaries

1. Portable frontend normalization never switches on `targetId`.
2. Target-specific semantics do not become ad hoc Canonical Core constructors.
3. Shared semantics use existing Core instructions; genuinely target-specific
   semantics use typed, versioned HostOps.
4. Intent resolution is not materialization. A standard name alone is not a
   compiled product.
5. A promoted target must fail closed for its declared supported fragment.
6. Secondary targets remain honest about maturity and input modes.
7. External protocols are invoked through protocol contracts and peer binding,
   not hard-coded chain addresses in portable sources.

## Layer Model

```text
Portable authoring
  contract_source | TokenSpec | NFTSpec
                 |
                 v
Intent validation and target-neutral IntentContract
                 |
                 v
AuthoredContract -> checked Canonical Core
                 |
                 v
Target Materializer Registry
  (target, intent family, feature set) -> materializer or named rejection
                 |
                 v
CapabilityPlan + typed target extensions
                 |
                 v
Evm.Plan | Solana.Plan | WasmHostModulePlan | research target plan
                 |
                 v
Target artifact + metadata + client + runtime evidence
```

## Intent Contracts

An intent spec is author input. An `IntentContract` is the checked,
target-neutral compiler contract consumed by materializers.

```lean
inductive IntentFamily where
  | fungibleToken
  | nonFungibleToken
  | governance
  | vault
  deriving BEq, Repr

structure IntentContract where
  family : IntentFamily
  name : String
  symbol? : Option String := none
  requirements : Array ProofForge.Target.CapabilityCall := #[]
  featureIds : Array String := #[]
  deriving Repr

structure IntentMaterialization where
  targetId : String
  standardId : String
  canonical : ProofForge.IR.Canonical.CanonicalBundle
  evidence : Array String := #[]

structure IntentMaterializer where
  targetId : String
  family : IntentFamily
  materialize : IntentContract -> Except String IntentMaterialization
```

`CapabilityCall` is the existing target-neutral requirement record used by
canonical contracts and target planning. A separate `CapabilityRequirement`
type is intentionally not introduced.

The registry owns the only `(targetId, intent family)` dispatch. Frontend DSL,
Surface helpers, Canonical Core, and reusable product sources do not.

## NFT Model

ERC-721 and ERC-1155 are not the same asset model. `batch` must not silently
change standards as an incidental feature.

```lean
inductive NFTAssetModel where
  | unique
  | multiToken
  deriving BEq, Repr

inductive NFTFeature where
  | mintable
  | burnable
  | transferable
  | soulbound
  | approvals
  | enumerable
  | metadataMutable
  | royalties
  | collection
  deriving BEq, Repr

structure NFTSpec where
  name : String
  symbol : String
  assetModel : NFTAssetModel := .unique
  features : Array NFTFeature := #[.transferable]
  deriving Repr
```

Target standards are materializer results:

- EVM unique -> ERC-721.
- EVM multi-token -> ERC-1155.
- Solana unique -> the repository's Metaplex plan.
- NEAR unique -> the repository's NEP-171-shaped plan.
- Unsupported model/feature combinations reject by stable feature ID.

The first vertical slice supports only `unique + mintable + transferable`.
Additional features are promoted one at a time with runtime evidence.

`NFTSpec.toIntentContract` validates the author identity and feature
combination before conversion. The resulting `featureIds` includes exactly one
stable asset-model discriminator (`nft.asset_model.unique` or
`nft.asset_model.multi_token`) so target materializers cannot lose the choice
between unique and multi-token standards at the generic intent boundary.

## NFT Materialization

Each primary target materializer consumes the same `IntentContract`, selects a
native implementation candidate, and returns direct checked Canonical output.
The current `ContractSpec` result in the first NFT implementation is migration
debt owned by A-CUT3/A-CUT5, not part of this design contract.

The initial candidates are:

- EVM: `Stdlib.ERC721`.
- Solana: `Stdlib.MetaplexNft`.
- NEAR: `Stdlib.NearNft`.

These files are existing implementation candidates, not proof of standard
compliance. Before exposure through `NFTSpec`, each must pass:

- interface/entrypoint identity checks;
- feature-specific semantic tests;
- primary-triad build and artifact checks;
- runtime lifecycle tests for mint, transfer, owner/balance, and rejection;
- honest-reject checks for every unimplemented feature.

## Portable Intent Operations

No `transfer_token`/`mint_token` syntax is added in the first NFT slice.
Operations belong to the selected implementation contract produced by the
materializer. A future intent-operation layer may be added only if it can
normalize to a target-neutral protocol operation contract.

For deployed external assets, the correct path remains:

```text
portable protocol call -> protocol materialization -> PeerMap binding
```

It is not frontend `targetId` dispatch.

## Solana Grammar Isolation

`Source.lean` owns the direct portable grammar and emits `AuthoredContract`.
Solana-specific productions, seed categories, and handlers live in
`Source/Solana.lean` and emit typed target extension payloads.

This is a grammar ownership change only. It must not change generated IR or
Solana fixtures. Product modules importing only `Contract.Source` must be
unable to parse Solana PDA/CPI/realloc forms.

## Wasm-Host Boundary

NEAR, Soroban, and CosmWasm share Wasm emission machinery, but they do not
share ABI, auth, storage lifecycle, or crosscall semantics. Promotion requires
a neutral plan contract:

```text
WasmHostModulePlan
  + WasmHostAbiPlan
  + HostBridgePlan
  + target HostOp registry
```

The neutral module-plan boundary is implemented. NEAR-specific ABI, promise,
receipt, and host behavior remains target-owned; sharing Wasm emission never
permits a target to route through another target's semantic plan.

## ZK Target Boundary

PSy and Aleo are separate target-family promotions. They consume Canonical
Core where their semantics match it and reject unsupported operations.

ZK-specific operations use HostOps such as a future namespaced
`zk.commitment.verify@1.0.0`; they do not add chain-specific constructors to
Canonical Core. OpenVM remains research until an independently sourced target
brief fixes its toolchain, ISA, proof, artifact, and verification contracts.

## Failure Model

Diagnostics must identify:

- intent family;
- stable feature ID;
- target ID;
- selected standard when selection succeeded;
- missing capability or materializer;
- maturity/input-mode limitation when applicable.

No target promotion test may convert a `buildFromCore` error to success for a
fixture declared inside that target's supported fragment.

## Verification Strategy

Every vertical slice requires:

1. Unit tests for intent validation and registry resolution.
2. Feature x target honest-reject matrix.
3. Direct Authored normalization and canonical validation tests.
4. Target plan assertions.
5. Artifact metadata/client checks.
6. Runtime lifecycle evidence where local tooling exists.
7. `just product`, targeted backend gates, and `just check`.
8. Documentation/i18n and `git diff --check`.

## Delivery Order

1. Refresh baseline and isolate Solana grammar.
2. Add the generic intent materializer contract.
3. Deliver the minimal NFT vertical slice across the primary triad.
4. Promote additional NFT features individually.
5. Extract the neutral Wasm-host plan boundary.
6. Evaluate Soroban canonical promotion on that boundary.
7. Add PSy canonical planning without changing its public maturity.
8. Consider DAO, Vault, CosmWasm protocol lanes, Aleo, and OpenVM only after
   the preceding boundaries have runtime evidence.

## Non-Goals

- Replacing external assemblers, solc, wat2wasm, or chain toolchains with Lean.
- Claiming full ERC/Metaplex/NEP compliance from method-name similarity.
- Making all targets accept all intent features.
- Promoting PSy, Aleo, Soroban, or CosmWasm to the primary triad by documentation.
- Adding DAO/Vault/OpenVM implementation to the first NFT plan.
