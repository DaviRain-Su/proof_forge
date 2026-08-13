import Examples.VerifiedVaultPF
import ProofForgeV2.Targets.Near.WasmCertArtifactsV1

/-!
Focused external-provider acceptance consumer. It is invoked only by
`scripts/wasmcert_provider_smoke_v1.py` after a real provider executable has
produced artifacts; ordinary tests keep the provider unprovisioned.
-/

namespace Tests.Materialization.WasmCertProviderRuntimeV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.Near

private def liftString {α : Type} (context : String) : Except String α → IO α
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{context}: {error}"

private def liftRepr {ε α : Type} [Repr ε]
    (context : String) : Except ε α → IO α
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{context}: {repr error}"

private def expectError (context : String) : Except String Unit → IO Unit
  | .error _ => pure ()
  | .ok () => throw <| IO.userError s!"{context}: expected fail-closed rejection"

private def subjectProgram : SemanticProgramV1 :=
  Examples.VerifiedVaultPF.Proof.subjectProgramV1

private def subjectData : SemanticProgramDataV1 :=
  Examples.VerifiedVaultPF.Proof.subjectDataV1

private def productionFields : Array StorageField := #[
  {
    sourceId := 0
    name := "reserves"
    key := stateKey 0
    byteWidth := 8
    endianness := .little
  },
  {
    sourceId := 1
    name := "shares"
    key := stateKey 1
    byteWidth := 8
    endianness := .little
  }
]

private def referenceStorageRows
    (values : Array ByteArray) : Except String (Array WasmCertStorageRowV1) := do
  unless values.size = 2 do
    throw "VerifiedVaultPF Reference state must contain exactly two values"
  unless values[0]!.size = 8 && values[1]!.size = 8 do
    throw "VerifiedVaultPF Reference state values must be canonical UInt64 bytes"
  pure #[
    { key := layoutMarkerKey.toUTF8,
      value := encodeU64le (layoutMarker productionFields) },
    { key := (stateKey 0).toUTF8, value := values[0]! },
    { key := (stateKey 1).toUTF8, value := values[1]! }
  ]

private def referencePreState
    (callable : CallableV1)
    (invocation : WasmCertInvocationArtifactV1) :
    Except String LogicalStateV1 := do
  if callable.kind = .initializer && invocation.preStorage.isEmpty then
    match initialLogicalStateV1 subjectProgram with
    | .ok logicalState => pure logicalState
    | .error error => throw s!"initial Reference state failed: {repr error}"
  else
    let state0 ← match invocation.preStorage.find? (fun row =>
        row.key == (stateKey 0).toUTF8) with
      | some row => pure row.value
      | none => throw "WasmCert pre-storage lacks production state field 0"
    let state1 ← match invocation.preStorage.find? (fun row =>
        row.key == (stateKey 1).toUTF8) with
      | some row => pure row.value
      | none => throw "WasmCert pre-storage lacks production state field 1"
    let expected ← referenceStorageRows #[state0, state1]
    unless invocation.preStorage = expected do
      throw "WasmCert pre-storage differs from the production VerifiedVaultPF layout"
    match encodeLogicalStateValuesV1 subjectData true #[state0, state1] with
    | .ok logicalState => pure logicalState
    | .error error => throw s!"WasmCert pre-storage is not a canonical Reference state: {repr error}"

private def referenceCallable
    (invocation : WasmCertInvocationArtifactV1) : Except String CallableV1 := do
  let callable ← match subjectData.callables.find? fun callable =>
      if invocation.exportName = "init" then
        callable.kind = .initializer
      else
        callable.name = some invocation.exportName with
    | some callable => pure callable
    | none => throw s!"WasmCert export '{invocation.exportName}' is not a VerifiedVaultPF callable"
  unless invocation.context.isView = (callable.kind = .view) do
    throw "WasmCert invocation view mode differs from the Reference callable kind"
  pure callable

private def referenceInvocation
    (callable : CallableV1)
    (artifact : WasmCertInvocationArtifactV1) : Except String InvocationV1 := do
  let args ← match callable.params.toList with
    | [] =>
        unless artifact.input.isEmpty do
          throw "nullary VerifiedVaultPF callable received nonempty Wasm input"
        pure #[]
    | [parameter] =>
        pure #[{ typeId := parameter.typeId, valueBytes := artifact.input }]
    | _ => throw "WasmCert Reference join supports at most one parameter"
  pure { callableId := callable.id, args, context := #[] }

/-- Execute the sole admitted Reference machine for the exact external
    invocation and compare its result with the replay-validated Wasm
    observation. This is a concrete refinement join, not a second contract
    evaluator or a universal Wasm correctness theorem. -/
private def validateReferenceObservation
    (admitted : AdmittedReferenceSliceV1)
    (invocation : WasmCertInvocationArtifactV1)
    (observation : WasmCertObservationArtifactV1) : Except String Unit := do
  let callable ← referenceCallable invocation
  let pre ← referencePreState callable invocation
  let referenceInvocation ← referenceInvocation callable invocation
  let outcome := stepReferenceSliceV1 admitted pre referenceInvocation #[] {}
  match outcome with
  | .returned post value effects =>
      unless observation.status = .returned do
        throw "Wasm execution failed while the sole Reference machine returned"
      unless effects.isEmpty do
        throw "VerifiedVaultPF WasmCert slice does not map nonempty Reference effects"
      unless observation.logs.isEmpty && observation.promises.isEmpty do
        throw "effect-free Reference return produced target logs or promises"
      unless observation.returnData = value.map (·.valueBytes) do
        throw "Wasm return data differs from the sole Reference result"
      let values ← match decodeLogicalStateValuesV1 subjectData post with
        | .ok values => pure values
        | .error error => throw s!"Reference post-state decode failed: {repr error}"
      let expectedStorage ← referenceStorageRows values
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

private def checkCase
    (admitted : AdmittedReferenceSliceV1) (directory name : String) : IO Unit := do
  let base := s!"{directory}/{name}"
  let requestBytes ← IO.FS.readBinFile s!"{base}.request.json"
  let resultBytes ← IO.FS.readBinFile s!"{base}.result.json"
  let invocationBytes ← IO.FS.readBinFile s!"{base}.invocation.json"
  let traceBytes ← IO.FS.readBinFile (wasmCertProviderHostTracePathV1 s!"{base}.result.json")
  let observationBytes ← IO.FS.readBinFile
    (wasmCertProviderObservationPathV1 s!"{base}.result.json")
  let request ← liftString s!"{name} request"
    (decodeWasmCertProviderRequestV1 requestBytes)
  let result ← liftString s!"{name} result"
    (decodeWasmCertProviderResultRecordV1 resultBytes)
  let artifacts ← liftString s!"{name} provider artifact join"
    (validateWasmCertProviderArtifactsForRequestV1 request
      s!"{base}.request.json" s!"{base}.result.json" result
      invocationBytes traceBytes observationBytes)
  liftString s!"{name} ReferenceMachine observation join"
    (validateReferenceObservation admitted artifacts.1 artifacts.2.2)
  let tamperedTerminal := match artifacts.2.2.status with
    | .returned => { artifacts.2.2 with
        returnData := if artifacts.2.2.returnData.isSome then none else some ByteArray.empty }
    | .trapped => { artifacts.2.2 with status := .returned }
  expectError s!"{name} tampered Reference terminal observation"
    (validateReferenceObservation admitted artifacts.1 tamperedTerminal)
  expectError s!"{name} tampered Reference post-storage"
    (validateReferenceObservation admitted artifacts.1 {
      artifacts.2.2 with postStorage := #[]
    })

def run (directory : String) : IO Unit := do
  let admitted ← liftRepr "admit VerifiedVaultPF Reference program"
    (admitReferenceProgramSliceV1 subjectProgram)
  for name in ["init", "deposit", "withdraw", "status", "withdraw-overdraw"] do
    checkCase admitted directory name
  IO.println "WasmCert canonical + ReferenceMachine joins: 5/5 passed"

end Tests.Materialization.WasmCertProviderRuntimeV1

unsafe def main (args : List String) : IO UInt32 := do
  let directory ← match args with
    | [directory] => pure directory
    | _ =>
        IO.eprintln "usage: WasmCertProviderRuntimeV1 <project-relative-artifact-directory>"
        return 64
  Tests.Materialization.WasmCertProviderRuntimeV1.run directory
  return 0
