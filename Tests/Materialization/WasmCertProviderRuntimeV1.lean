import Examples.VerifiedVaultPF
import ProofForgeV2.Compiler.InlineProofCertifierV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Near.WasmCertReferenceJoinV1

/-!
Focused locked-provider product acceptance consumer. Ordinary tests perform no
WasmCert IO; `scripts/wasmcert_provider_smoke_v1.py` runs this file against an
exact provisioned Tool Root.

The positive path is the real product chain:

* exact source snapshot + inline-proof certification;
* NEAR capability authorization, materialization, and locked wat2wasm finalize;
* `executeLockedWasmCertV1` over the finalized artifact;
* `joinLockedWasmCertReferenceV1` against the sole ReferenceMachineV1.

No Python or Lean fixture supplies a business post-state oracle.
-/

namespace Tests.Materialization.WasmCertProviderRuntimeV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Compiler.InlineProofCertifierV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Materialization.LockedToolchainV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Near

private def liftCompile {α : Type} (context : String) : CompileResult α → IO α
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{context}: {error.render}"

private def liftString {α : Type} (context : String) : Except String α → IO α
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{context}: {error}"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

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
    (data : SemanticProgramDataV1)
    (callable : CallableV1)
    (invocation : WasmCertInvocationArtifactV1) :
    Except String LogicalStateV1 := do
  unless data == subjectData do
    throw "locked semantic subject is not the exact VerifiedVaultPF program"
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
    match encodeLogicalStateValuesV1 data true #[state0, state1] with
    | .ok logicalState => pure logicalState
    | .error error =>
        throw s!"WasmCert pre-storage is not a canonical Reference state: {repr error}"

private def referenceCallable
    (data : SemanticProgramDataV1)
    (invocation : WasmCertInvocationArtifactV1) : Except String CallableV1 := do
  let callable ← match data.callables.find? fun callable =>
      if invocation.exportName = "init" then
        callable.kind = .initializer
      else
        callable.name = some invocation.exportName with
    | some callable => pure callable
    | none =>
        throw s!"WasmCert export '{invocation.exportName}' is not a VerifiedVaultPF callable"
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

private def verifiedVaultAdapter : WasmCertReferenceAdapterV1 := {
  schema := wasmCertReferenceAdapterSchemaV1
  prepare := fun data invocation => do
    let callable ← referenceCallable data invocation
    let preState ← referencePreState data callable invocation
    let referenceInvocation ← referenceInvocation callable invocation
    pure { preState, invocation := referenceInvocation }
  encodePostStorage := fun data post => do
    unless data == subjectData do
      throw "locked semantic subject changed during post-state encoding"
    let values ← match decodeLogicalStateValuesV1 data post with
      | .ok values => pure values
      | .error error => throw s!"Reference post-state decode failed: {repr error}"
    referenceStorageRows values
}

/-- Re-run only the already-admitted sole Reference outcome comparator. This is
    used for tampered-observation negatives after the positive private product
    join has succeeded; it introduces no target or business step. -/
private def validateReferenceObservation
    (admitted : AdmittedReferenceSliceV1)
    (invocation : WasmCertInvocationArtifactV1)
    (observation : WasmCertObservationArtifactV1) : Except String Unit := do
  let prepared ← verifiedVaultAdapter.prepare admitted.data invocation
  let outcome := stepReferenceSliceV1 admitted prepared.preState
    prepared.invocation prepared.externalResponses prepared.vaultSeed
  validateWasmCertEffectFreeReferenceOutcomeV1 verifiedVaultAdapter admitted.data
    prepared.preState outcome invocation observation

private def invocationContext (isView : Bool) : WasmCertNearContextV1 := {
  currentAccountId := "vault.test.near"
  signerAccountId := "alice.test.near"
  signerAccountPk := ByteArray.mk (Array.replicate 33 (1 : UInt8))
  predecessorAccountId := "alice.test.near"
  blockHeight := 42
  blockTimestampNanos := 1700000000000000000
  epochHeight := 7
  accountBalance := ByteArray.mk (Array.replicate 16 (0 : UInt8))
  accountLockedBalance := ByteArray.mk (Array.replicate 16 (0 : UInt8))
  storageUsage := 128
  attachedDeposit := ByteArray.mk (Array.replicate 16 (0 : UInt8))
  prepaidGas := 300000000000000
  randomSeed := ByteArray.mk (Array.replicate 32 (2 : UInt8))
  isView
  outputDataReceivers := #[]
  promiseResults := #[]
}

private def invocationFor
    (exportName : String)
    (input : ByteArray)
    (preStorage : Array WasmCertStorageRowV1)
    (isView : Bool) : WasmCertInvocationArtifactV1 := {
  schema := wasmCertInvocationArtifactSchemaV1
  hostProfile := wasmCertProviderHostProfileV1
  observationPolicy := wasmCertObservationPolicyV1
  exportName
  input
  context := invocationContext isView
  preStorage
}

/-- Reproduce the product's exact proof-bearing source pipeline, then invoke
    the sole target finalizer. The returned private carrier therefore retains
    the exact certified semantic subject consumed by the Reference join. -/
private unsafe def finalizeVerifiedVault
    (staging : System.FilePath) : IO FinalizedArtifactsV1 := do
  let sourcePathWire := "Examples/VerifiedVaultPF.lean"
  let moduleSelector := "Examples.VerifiedVaultPF"
  let rawSource ← IO.FS.readFile sourcePathWire
  let productSession ← ProductParserSessionV1.create
  let (source, origins, theorems) ←
    match ← productSession.selectProgramV1ProductWithTheoremInventory
        rawSource sourcePathWire moduleSelector none with
    | .ok value => pure value
    | .error bundle =>
        throw <| IO.userError s!"load VerifiedVaultPF: {bundle.renderHuman}"
  let compiled ← match compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error bundle =>
        throw <| IO.userError s!"compile VerifiedVaultPF: {bundle.renderHuman}"
  expect ((CompiledSemanticV1.semanticV1Of compiled).canonicalBytes ==
      subjectProgram.canonicalBytes)
    "product compile subject differs from the imported VerifiedVaultPF proof subject"
  let sourcePath ← liftString "parse VerifiedVaultPF project path"
    (parseProjectRelativePath sourcePathWire)
  let certificate ← match ← certifyInlineProofV1 productSession rawSource source
      origins theorems compiled sourcePath moduleSelector none with
    | .certified certificate => pure certificate
    | .noProof =>
        throw <| IO.userError "VerifiedVaultPF product proof was unexpectedly not required"
    | .failed phase detail =>
        throw <| IO.userError s!"VerifiedVaultPF proof certification failed: {repr phase}:{repr detail}"
  let selection ← liftCompile "select NEAR"
    (resolveBuildSelectionV1 TargetId.near none)
  let ordinary ← liftCompile "resolve NEAR requirements"
    (resolveEngineeringRequirementsV1 selection compiled)
  let capability ← liftCompile "authorize NEAR invariant erasure"
    (authorizeCertifiedNearInvariantErasureV1 ordinary certificate)
  let artifacts ← liftCompile "materialize VerifiedVaultPF"
    (materializeResult capability)
  for file in MaterializedArtifactsV1.filesOf artifacts do
    IO.FS.writeFile (staging / file.path) file.contents
  let finalized ← finalizeMaterializedArtifactsV1 capability artifacts staging
  expect (FinalizedArtifactsV1.deployableOf finalized)
    "VerifiedVaultPF locked finalization must be deployable"
  expect (FinalizedArtifactsV1.extraFilesOf finalized == #["VerifiedVaultPF.wasm"])
    "VerifiedVaultPF locked finalization must retain exactly one Wasm output"
  pure finalized

private def checkCase
    (finalized : FinalizedArtifactsV1)
    (staging : System.FilePath)
    (name exportName : String)
    (input : ByteArray)
    (preStorage : Array WasmCertStorageRowV1)
    (isView : Bool) : IO Unit := do
  let invocation := invocationFor exportName input preStorage isView
  let locked ← executeLockedWasmCertV1 finalized staging invocation 100000
  let joined ← liftString s!"{name} locked WasmCert/ReferenceMachine join"
    (joinLockedWasmCertReferenceV1 locked verifiedVaultAdapter)
  let admitted := WasmCertReferenceJoinV1.admittedReferenceOf joined
  let observation := WasmCertLockedExecutionObservationV1.observationOf locked
  let identity := WasmCertLockedExecutionObservationV1.identityOf locked
  expect (identity.artifactProgramName == "VerifiedVaultPF")
    s!"{name}: locked execution retained a foreign artifact identity"
  let expectedExecutable ← match wasmCertProviderExecutableSha256V1
      (if System.Platform.isOSX then .darwinArm64 else .linuxX86_64) with
    | some digest => pure digest
    | none => throw <| IO.userError "current platform has no WasmCert activation identity"
  expect (identity.executableSha256.bytes == expectedExecutable.bytes)
    s!"{name}: locked execution retained the wrong platform executable identity"

  let tamperedTerminal := match observation.status with
    | .returned => { observation with
        returnData := if observation.returnData.isSome then none else some ByteArray.empty }
    | .trapped => { observation with status := .returned }
  expectError s!"{name} tampered Reference terminal observation"
    (validateReferenceObservation admitted invocation tamperedTerminal)
  expectError s!"{name} tampered Reference post-storage"
    (validateReferenceObservation admitted invocation {
      observation with postStorage := #[]
    })

unsafe def run : IO Unit := do
  IO.FS.withTempDir fun staging => do
    let finalized ← finalizeVerifiedVault staging
    let preStorage ← liftString "encode VerifiedVaultPF pre-storage"
      (referenceStorageRows #[encodeU64le 10, encodeU64le 10])
    checkCase finalized staging "init" "init" ByteArray.empty #[] false
    checkCase finalized staging "deposit" "deposit" (encodeU64le 5) preStorage false
    checkCase finalized staging "withdraw" "withdraw" (encodeU64le 5) preStorage false
    checkCase finalized staging "status" "status" ByteArray.empty preStorage true
    checkCase finalized staging "withdraw-overdraw" "withdraw"
      (encodeU64le 11) preStorage false
  IO.println "locked WasmCert product + ReferenceMachine joins: 5/5 passed"

unsafe def resolveOnly : IO Unit := do
  let tool ← resolve wasmCertProviderToolIdV1
  expect (tool.id == wasmCertProviderToolIdV1 &&
      tool.version == wasmCertProviderVersionV1)
    "resolved WasmCert Tool Lock identity differs from the frozen provider"
  IO.println s!"locked WasmCert provider resolved sha256={tool.executableSha256}"

end Tests.Materialization.WasmCertProviderRuntimeV1

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | [] => Tests.Materialization.WasmCertProviderRuntimeV1.run
  | ["resolve-only"] => Tests.Materialization.WasmCertProviderRuntimeV1.resolveOnly
  | _ =>
      IO.eprintln "usage: WasmCertProviderRuntimeV1 [resolve-only]"
      return 64
  return 0
