# Wasm-Host Target Family Analysis

## Status

Refreshed **2026-07-15**. This is a promotion analysis, not a claim that
Soroban or CosmWasm is equivalent to the primary `wasm-near` route.

**Scheduling:** deep Soroban/CosmWasm host work is **queued after** the
primary-triad direct authoring cutover
([PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104); D-056).
Parallel work allowed: documentation honesty and pure design notes only.

## Baseline

The repository has one broad Wasm emission family with bridge-dispatched
storage and host calls:

- `wasm-near`: primary `contract_source` compiler.
- `wasm-stellar-soroban`: Counter-MVP `contract_source` route.
- `wasm-cosmwasm`: Counter-MVP `contract_source`/fixture route.

Shared components include EmitWat, scalar/map helpers, import selection, host
interpreters, and abstract Wasm execution. Target semantics remain different.

## Architectural Finding

The current canonical plan is not yet a neutral Wasm-host plan.
`NearModulePlan.Core.buildFromCore`:

- accepts only `wasm-near`;
- builds NEAR Borsh parameter plans;
- lowers NEAR promise HostOps;
- assumes NEAR-shaped context and return behavior.

Therefore Soroban/CosmWasm promotion must not be implemented by merely
allowing another target ID.

## Required Neutral Boundary

```lean
inductive WasmHostKind where
  | near
  | soroban
  | cosmWasm

structure WasmHostAbiPlan where
  params : Array WasmHostParamPlan
  result? : Option WasmHostResultPlan
  decoderId : String
  encoderId : String

structure HostBridgePlan where
  kind : WasmHostKind
  storageModel : String
  authModel : String
  crosscallModel : String

structure WasmHostModulePlan where
  targetId : String
  bridge : HostBridgePlan
  abi : Array WasmHostAbiPlan
  layout : NearLayoutPlan
  functions : Array NearFunctionPlan
```

The existing layout/function types may be reused initially. The public plan
and ABI contracts must no longer imply NEAR semantics.

## NEAR Preservation Phase

Before adding a target, extract the neutral names and keep NEAR output byte-for-
byte stable except for explicitly reviewed golden changes.

Required evidence:

- Counter and ValueVault canonical parity.
- NEAR FT transfer-call callback runtime.
- promise create/then/result gates.
- Borsh ABI/client gates.
- existing NEAR deployment-honesty metadata.

## Soroban Current State

Available (Counter MVP, custom bridge — not real Env):

- `contract_source` `build`/`check` via EmitWat + `HostBridge.soroban`.
- Canonical `ModulePlan.Core.buildFromCore` accepts `.soroban` (NEAR layout
  builder + bridge tag); Counter `lowerFromPlan` emits `_get`/`_put` /
  `set_return_data` (see `just soroban-public-route`).
- Offline-host lifecycle (`just soroban-promotion` / `soroban-counter-offline`).
- Host interpreter + `SorobanHost` lemmas + Counter refinement anchors.
- Portable crosscall label `soroban-invoke`; EmitWat can emit stub
  `invoke_contract` (returns handle `0`).

Not sufficient for Experimental / production claims:

- HostABI is still hybrid (Soroban storage names + retained NEAR helpers).
- No Soroban-native parameter/result ABI (XDR / contract-spec / ScVal).
- Auth is always-auth; `invoke_contract` is a stub; no real Env harness
  (`tools/soroban-vm-runner` placeholder only).
- Registry capabilities are wider than proven product evidence (`env.block`
  rejects ValueVault; maps/crypto/crosscall depth incomplete).
- No TokenSpec/NFTSpec materializer; fixture `emit` unmapped.
- Dual EmitWat vs plan paths not yet collapsed to one product route.

### Soroban promotion order (post–authoring cutover)

Align with [stellar-soroban.md](../../targets/stellar-soroban.md) S0–S5:

1. **S0** Capability/docs honesty and fail-closed diagnostics.
2. **S1** De-NEAR HostABI for the supported fragment.
3. **S2** Single Authored → canonical plan → lower product path.
4. **S3** Offline crosscall depth (still custom bridge).
5. **S4** Real Soroban Env + (later) Stellar CLI deploy.
6. **S5** ValueVault / Token / SDK only after Env truth.

Gates that remain required before maturity promotion:

1. Neutral Wasm-host plan extraction continues to preserve NEAR gates.
2. Soroban ABI/auth contract has explicit tests matching HostABI.
3. Counter canonical plan builds and lowers fail closed on unsupported shapes.
4. Counter runtime evidence on **Env-faithful** harness (not only offline-host).
5. ValueVault only if every used capability is implemented.
6. Portable remote call evidence beyond stub `invoke_contract`.
7. NEAR-only HostOps reject with `missingHostOpHandler`.
8. CLI route, artifact, SDK, and maturity metadata agree.

## CosmWasm Current State

Available:

- `contract_source` and Counter fixture routing.
- `db_read`/`db_write` bridge code.
- host interpreter/refinement anchors.
- a placeholder `execute_msg` path.

Blocking gaps:

- no neutral canonical `buildFromCore` branch;
- non-empty message ABI is not a complete CosmWasm contract ABI;
- `execute_msg` is not production WasmMsg/SubMsg/reply encoding;
- no runtime evidence against a real CosmWasm VM;
- no CW-20/CW-721 intent materializers.

CosmWasm canonical storage promotion can follow the neutral plan extraction,
but crosscall/product promotion must wait for a concrete message/reply model.

## Fail-Closed Promotion Policy

The existing `runCanonicalValidationGate` is advisory during migration. A
secondary target promotion requires an additional strict gate:

```lean
def runStrictCanonicalTargetGate
    (targetId : String) (spec : ContractSpec) : Except String Unit
```

For fixtures declared supported, adapter, validation, HostOp resolution, and
`buildFromCore` failures are errors. Advisory behavior may remain on unrelated
legacy public routes until cutover.

## Revised Order

1. Extract `WasmHostModulePlan` and preserve NEAR behavior.
2. Add strict canonical target-gate infrastructure.
3. Model Soroban ABI/auth and promote Counter.
4. Add Soroban RemoteCall evidence.
5. Decide ValueVault support from its actual capability inventory.
6. Research and specify CosmWasm message/reply ABI.
7. Promote CosmWasm storage-only Counter.
8. Add real CosmWasm crosscall before product/protocol claims.
9. Add TokenSpec/NFTSpec lanes only through the shared IntentMaterializer
   registry.

## Explicit Non-Claims

- Sharing EmitWat does not mean the three chains share an ABI.
- A host interpreter stub is not chain-runtime compatibility.
- Counter-MVP maturity is not primary-triad maturity.
- Soroban and CosmWasm are not new codegen cores; they are host adapters whose
  promotion still requires target-native contracts and evidence.
