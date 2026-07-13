# IR and Target Extension Boundary Implementation Plan

Status: **active (2026-07-14)**

Design authority:
[IR and Target Extension Boundary](../specs/2026-07-14-ir-target-extension-boundary-design.md)
and D-054. This plan is a prerequisite for N-T4 because adding metadata/events
on top of the current NEAR-specific `Expr` surface would enlarge the coupling.

## Task Index

| ID | State | Task | Acceptance evidence |
|---|---|---|---|
| IR-B0 | done (verified 2026-07-14) | Audit all target leakage and freeze the boundary | accepted design, inventory, `just ir-target-boundary`, docs gate |
| IR-B1 | done (verified 2026-07-14) | Open the capability/HostOp identity and split target catalogs | Core build, catalog/handler tests, unsupported-target diagnostic |
| IR-B2 | pending | Remove NEAR promise modes and semantics from Canonical Core | canonical adapter/plan tests, no `near*` Core constructors |
| IR-B3 | pending | Remove NEAR constructors and fields from legacy shared IR | Near SDK compatibility, NEP-141/145 focused VM gates |
| IR-B4 | pending | Move EVM protocol/ABI operations out of shared IR | EVM focused plan/Foundry gates and non-EVM diagnostics |
| IR-B5 | pending | Audit and migrate Solana-native PDA/CPI/account behavior | Solana grammar-isolation, intent, manifest, and light sBPF gates |
| IR-B6 | pending | Audit and migrate other implemented target families | focused Wasm-host, Move, Aleo, Psy, and Quint gates |
| IR-B7 | pending | Move target environment, error, dispatch, and materialization fields | interface/materialization tests across registered targets |
| IR-B8 | pending | Enforce the boundary and close compatibility debt | empty source-scan allowlist, product gate, affected runtime gates |

## IR-B0 - Audit and Freeze

- [x] Inventory target-named and protocol-specific nodes in legacy IR.
- [x] Inventory target-specific syntax, catalogs, and semantics in Core.
- [x] Define allowed and forbidden ownership paths.
- [x] Add a machine-readable baseline gate that fails on any new shared-layer
  violation while IR-B1 through IR-B5 remove the current allowlist.
- [x] Record the accepted decision and agent routing updates.

## IR-B1 - Open Extension Protocol

1. Move `HostOpId` and version types into a target-neutral shared identity
   module that neither legacy IR nor Core owns.
2. Replace the global `canonicalHostOpCatalog` with catalog composition supplied
   by the selected target profile/materializer.
3. Separate portable semantic capabilities from target-native extension IDs;
   adding an extension must not modify a closed shared inductive.
4. Preserve exact signature, result, effect-class, and capability validation.

Completion evidence (2026-07-14):

- `HostOpId` and version ownership moved to `ProofForge.Target.HostOp`.
- `Capability` is an open stable-ID structure; extensions no longer edit a
  shared closed inductive.
- the NEAR catalog is target-owned and selected target profiles declare their
  HostOps; canonical validation derives exact HostOp capability calls.
- `just target-registry`, `just hostop-protocol`, `just near-promise-hostop`,
  and `just build` pass. `just product` reaches the independent existing
  Soroban `OwnableHash` limitation and fails because that spike does not
  support 32-byte Hash storage through its scalar `_get` ABI.

## IR-B2 - Canonical Core Cleanup

1. Replace `nearPoolInvoke` and `nearPromiseThen` with neutral async invocation
   and continuation semantics or typed HostOps where no common contract exists.
2. Move NEAR signatures, handlers, traces, and reference execution into the
   Wasm-NEAR target namespace.
3. Inject host semantics into the Core evaluator rather than matching NEAR IDs
   in Core.
4. Prove EVM/Solana reject unhandled async extensions before plan construction.

## IR-B3 - Legacy NEAR Cleanup

1. Add neutral call-value context and typed extension-call compatibility nodes.
2. Reimplement public Near SDK helpers as wrappers over those nodes.
3. Migrate all promise/result/storage-usage/transfer call sites.
4. Replace `nearCrosscallStrings` with neutral constant materialization or a
   target-owned plan pool.
5. Delete all nine `near*` `Expr` constructors and exhaustive match arms.

## IR-B4 - Legacy EVM Cleanup

1. Move EIP-712 and ERC receiver behavior into the EVM SDK/stdlib layer.
2. Replace EVM ABI-packed call payloads with a semantic call description whose
   ABI layout is built in the EVM plan.
3. Classify create/static/delegate behavior as portable semantics or explicit
   target extensions and migrate accordingly.
4. Delete EVM/protocol-specific `Expr` and `Effect` constructors.

## IR-B5 - Solana Extension Audit and Cleanup

1. Verify that PDA derivation, CPI account metas/signer seeds, sysvars,
   account ownership, realloc, and instruction packing are owned by
   `Source.Solana`, `ProofForge.Solana`, or the Solana backend.
2. Replace any remaining shared constructors or records that encode Solana
   account layout with typed extension requests and target plan data.
3. Keep portable invocation, authorization, storage, and resource-budget
   semantics shared where their contract is genuinely cross-target.
4. Prove unsupported targets reject Solana extensions before materialization.

## IR-B6 - Other Implemented Target Families

Audit every registered or CLI-only implemented family, not only the primary
triad:

1. Wasm-host profiles: CosmWasm, Soroban, Cloudflare Workers, and Stylus host
   imports, storage bridges, ABI conventions, and execution context.
2. Move targets: Aptos/Sui resources, signer/object semantics, entry functions,
   abilities, and transaction context.
3. Aleo and Psy: record/mapping/privacy, proof/public-input, metadata, and
   execution-model fields.
4. Quint: keep verification projection and replay configuration outside the
   executable portable IR contract.

Each family must either use a portable semantic operation or register a typed
target extension. Research/fixture maturity is not permission to leak a target
constructor into shared IR.

## IR-B7 - Interface and Materialization Cleanup

1. Replace chain-only `ContextField` variants with neutral fields or extension
   environment reads.
2. Move Solidity error ABI data to `EvmPlan`.
3. Move fallback/receive dispatch to target interface metadata.
4. Move proxy and host-string pools out of portable `Module` and canonical
   materialization records.

## IR-B8 - Enforcement and Sign-off

- The allowlist from IR-B0 is empty.
- Shared IR/Core source scan rejects chain/protocol constructors and fields.
- Target extension SDKs remain usable and generate named metadata.
- Unsupported targets fail at capability or handler resolution.
- Run focused Core/adapter tests, `just ir-portability-smoke`, `just product`,
  the affected NEAR VM gates, and affected EVM runtime gates.
- Resume N-T4 only after IR-B3. IR-B4 through IR-B7 remain required for the
  repository-wide boundary sign-off even if NEAR feature work resumes earlier.
