# Wasm-Host Target Family Analysis

## Status

Refreshed after the 2026-07-12 merge. This is a promotion analysis, not a
claim that Soroban or CosmWasm is equivalent to the primary `wasm-near` route.

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

Available:

- `contract_source` build routing through EmitWat.
- `_get`/`_put`, event, return, auth, and invoke-contract bridge code.
- host interpreter and Counter refinement anchors.

Not sufficient for promotion:

- no Soroban canonical `buildFromCore` branch;
- no Soroban-native parameter/result ABI plan;
- auth behavior is not yet production evidence;
- no fail-closed canonical public route;
- no TokenSpec/NFTSpec materializer;
- fixture `emit` routing remains limited.

### Soroban Promotion Gates

1. Neutral Wasm-host plan extraction passes all NEAR gates.
2. Soroban ABI/auth contract has explicit tests.
3. Counter canonical plan builds fail closed.
4. Counter runtime/host-interpreter parity passes.
5. ValueVault is added only if every capability it uses is supported.
6. Portable remote call is tested through `invoke_contract`.
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
