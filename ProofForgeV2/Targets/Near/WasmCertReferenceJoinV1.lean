import ProofForgeV2.Targets.Near.WasmCertProductV1

/-!
# Locked WasmCert → sole ReferenceMachine join

This module owns the product-side dynamic comparison between one locked
WasmCert execution and `ReferenceMachineV1`. Contract-specific code supplies
only representation adapters for the exported ABI and physical storage. It
does not supply an outcome function: `stepReferenceSliceV1` remains the sole
business transition.

The first strict provider profile deliberately admits only effect-free
Reference outcomes. A successful join is an identity-bound engineering
observation, not a kernel theorem about arbitrary Wasm or NEAR execution.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Frozen interface version for contract-specific ABI/storage representation
    adapters. Adapter functions prepare Reference inputs and encode Reference
    post-state; they never choose or compute the business outcome. -/
def wasmCertReferenceAdapterSchemaV1 : String :=
  "proof-forge.near.wasmcert-reference-adapter.v1"

/-- Complete input to the sole Reference step after target ABI/context/storage
    representation has been decoded. -/
structure WasmCertReferencePreparedCallV1 where
  preState : LogicalStateV1
  invocation : InvocationV1
  externalResponses : ExternalResponsesV1 := #[]
  vaultSeed : ReferenceVaultSeedV1 := {}

/-- Contract-specific representation boundary. `prepare` may only decode the
    target call boundary into existing Reference carriers; `encodePostStorage`
    may only project a Reference logical state into the production target
    layout. Neither callback receives or returns an `OutcomeV1`. -/
structure WasmCertReferenceAdapterV1 where
  schema : String
  prepare : SemanticProgramDataV1 → WasmCertInvocationArtifactV1 →
    Except String WasmCertReferencePreparedCallV1
  encodePostStorage : SemanticProgramDataV1 → LogicalStateV1 →
    Except String (Array WasmCertStorageRowV1)

private def requireReferenceAdapterSchemaV1
    (adapter : WasmCertReferenceAdapterV1) : Except String Unit := do
  unless adapter.schema = wasmCertReferenceAdapterSchemaV1 do
    throw "WasmCert Reference adapter schema differs from the frozen product interface"

/-- Compare an already-produced sole Reference outcome with one canonical
    WasmCert invocation/observation pair. This helper introduces no execution
    semantics; the locked product entry below is the only function in this
    module that calls `stepReferenceSliceV1`.

    The current strict profile is intentionally effect-free. Returned outcomes
    require exact result bytes and encoded post-storage. Revert/trap outcomes
    require exact Reference state preservation and target rollback. -/
def validateWasmCertEffectFreeReferenceOutcomeV1
    (adapter : WasmCertReferenceAdapterV1)
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (outcome : OutcomeV1)
    (invocation : WasmCertInvocationArtifactV1)
    (observation : WasmCertObservationArtifactV1) : Except String Unit := do
  requireReferenceAdapterSchemaV1 adapter
  match outcome with
  | .returned post value effects =>
      unless observation.status = .returned do
        throw "Wasm execution failed while the sole Reference machine returned"
      unless effects.isEmpty do
        throw "WasmCert strict Reference join does not map nonempty ordered effects"
      unless observation.logs.isEmpty && observation.promises.isEmpty do
        throw "effect-free Reference return produced target logs or promises"
      unless observation.returnData = value.map (·.valueBytes) do
        throw "Wasm return data differs from the sole Reference result"
      let expectedStorage ← adapter.encodePostStorage data post
      unless observation.postStorage = expectedStorage do
        throw "Wasm post-storage differs from the sole Reference post-state"
  | .reverted _ unchanged | .trapped _ unchanged =>
      unless unchanged == pre do
        throw "Reference failure did not preserve the exact pre-state"
      unless observation.status = .trapped do
        throw "Wasm execution returned while the sole Reference machine failed"
      unless observation.returnData.isNone && observation.logs.isEmpty &&
          observation.promises.isEmpty do
        throw "Wasm failure differs from the effect-free Reference failure boundary"
      unless observation.postStorage = invocation.preStorage do
        throw "Wasm failure did not expose exact transactional rollback"

/-- Private-constructor carrier minted only after the locked executable
    observation has been joined to the exact semantic program retained by its
    finalized build capability and to the sole Reference outcome. -/
structure WasmCertReferenceJoinV1 where
  private mk ::
  lockedExecution : WasmCertLockedExecutionObservationV1
  admittedReference : AdmittedReferenceSliceV1
  adapterSchema : String
  preparedCall : WasmCertReferencePreparedCallV1
  outcome : OutcomeV1

namespace WasmCertReferenceJoinV1

def lockedExecutionOf
    (joined : WasmCertReferenceJoinV1) : WasmCertLockedExecutionObservationV1 :=
  joined.lockedExecution

def admittedReferenceOf
    (joined : WasmCertReferenceJoinV1) : AdmittedReferenceSliceV1 :=
  joined.admittedReference

def adapterSchemaOf (joined : WasmCertReferenceJoinV1) : String :=
  joined.adapterSchema

def preparedCallOf
    (joined : WasmCertReferenceJoinV1) : WasmCertReferencePreparedCallV1 :=
  joined.preparedCall

def outcomeOf (joined : WasmCertReferenceJoinV1) : OutcomeV1 :=
  joined.outcome

end WasmCertReferenceJoinV1

/-- Execute and compare the sole Reference program corresponding to an exact
    locked WasmCert product observation.

    The semantic subject is not caller-selected: it is recovered from the
    retained compiler carrier inside the exact `FinalizedArtifactsV1` held by
    the locked observation, then admitted by `admitReferenceProgramSliceV1`.
    The adapter handles only contract ABI/context/storage representation. No
    alternate DSL state, effect carrier, or business step is introduced. -/
def joinLockedWasmCertReferenceV1
    (locked : WasmCertLockedExecutionObservationV1)
    (adapter : WasmCertReferenceAdapterV1) :
    Except String WasmCertReferenceJoinV1 := do
  requireReferenceAdapterSchemaV1 adapter
  let finalized :=
    WasmCertLockedExecutionObservationV1.finalizedArtifactsOf locked
  let capability := FinalizedArtifactsV1.capabilityOf finalized
  let program := ProofForgeV2.Compiler.CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  let admitted ← match admitReferenceProgramSliceV1 program with
    | .ok admitted => pure admitted
    | .error error =>
        throw s!"locked semantic program failed Reference admission: {repr error}"
  let invocation := WasmCertLockedExecutionObservationV1.invocationOf locked
  let observation := WasmCertLockedExecutionObservationV1.observationOf locked
  let prepared ← match adapter.prepare admitted.data invocation with
    | .ok prepared => pure prepared
    | .error error => throw s!"WasmCert Reference adapter preparation failed: {error}"
  let outcome := stepReferenceSliceV1 admitted prepared.preState
    prepared.invocation prepared.externalResponses prepared.vaultSeed
  validateWasmCertEffectFreeReferenceOutcomeV1 adapter admitted.data
    prepared.preState outcome invocation observation
  pure (WasmCertReferenceJoinV1.mk locked admitted adapter.schema prepared outcome)

end ProofForgeV2.Targets.Near
