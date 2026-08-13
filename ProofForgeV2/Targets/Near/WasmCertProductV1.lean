/-
# Locked WasmCert product consumer

Isolated consumer for a finalized NEAR Wasm artifact and one canonical
WasmCert invocation. The consumer does not define contract semantics: it runs
only the Tool-Lock-selected provider, then reuses the canonical artifact and
host-replay validators from `WasmCertArtifactsV1`.

The provider is intentionally absent from both platform locks today, so the
activation gate fails before any artifact read or provider execution. Keeping
the complete consumer behind that gate makes the remaining provisioning work
mechanical without allowing a PATH or locally built executable fallback.
-/
import ProofForgeV2.Materialization.ArtifactContentV1
import ProofForgeV2.Materialization.EngineeringDiskClosureV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Targets.Near.FinalizeV1
import ProofForgeV2.Targets.Near.WasmCertArtifactsV1

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.ToolLockV4
open ProofForgeV2.Materialization.LockedToolchainV1
open System

/-- Closed identity assembled only after locked execution, canonical decoding,
    exact digest joins, and deterministic host-trace replay all succeed. This
    is an execution observation, not a universal Wasm theorem or a Reference
    refinement certificate. -/
structure WasmCertLockedExecutionIdentityV1 where
  schema : String
  toolId : String
  toolVersion : String
  executableSha256 : Digest
  toolLockPlatform : String
  toolLockSha256 : Digest
  artifactProgramName : String
  sourceSha256 : Digest
  semanticSha256 : Digest
  finalizedWasmPath : String
  finalizedWasmSha256 : Digest
  fuel : UInt64
  invocationSha256 : Digest
  requestSha256 : Digest
  resultSha256 : Digest
  hostTraceSha256 : Digest
  observationSha256 : Digest
  deriving DecidableEq, Repr

def wasmCertLockedExecutionIdentitySchemaV1 : String :=
  "proof-forge.near.wasmcert-locked-execution.v1"

/-- Private-constructor observation. Retaining `FinalizedArtifactsV1` binds the
    execution identity to the exact capability and materialized artifact set
    accepted by the sole finalization authority. -/
structure WasmCertLockedExecutionObservationV1 where
  private mk ::
  finalized : FinalizedArtifactsV1
  identity : WasmCertLockedExecutionIdentityV1
  invocation : WasmCertInvocationArtifactV1
  trace : WasmCertHostTraceArtifactV1
  observation : WasmCertObservationArtifactV1

namespace WasmCertLockedExecutionObservationV1

def finalizedArtifactsOf
    (result : WasmCertLockedExecutionObservationV1) : FinalizedArtifactsV1 :=
  result.finalized

def identityOf
    (result : WasmCertLockedExecutionObservationV1) : WasmCertLockedExecutionIdentityV1 :=
  result.identity

def invocationOf
    (result : WasmCertLockedExecutionObservationV1) : WasmCertInvocationArtifactV1 :=
  result.invocation

def traceOf
    (result : WasmCertLockedExecutionObservationV1) : WasmCertHostTraceArtifactV1 :=
  result.trace

def observationOf
    (result : WasmCertLockedExecutionObservationV1) : WasmCertObservationArtifactV1 :=
  result.observation

end WasmCertLockedExecutionObservationV1

private def productError (message : String) : IO α :=
  throw <| IO.userError s!"PF-WASMCERT-PRODUCT: {message}"

private def requireProviderActivationV1 : IO Digest :=
  match requireWasmCertProviderProvisionedV1 with
  | .ok digest => pure digest
  | .error .executableUnprovisioned =>
      throw <| IO.userError
        "PF-TOOLCHAIN-MISSING: wasmcert-coq-provider is not provisioned in the active per-platform Tool Lock"
  | .error .unsupportedPlatform =>
      throw <| IO.userError
        "PF-TOOLCHAIN-MISMATCH: wasmcert-coq-provider has no supported Tool Lock platform for this target"

private def requireFinalizedNearIdentityV1
    (finalized : FinalizedArtifactsV1) : IO (String × String) := do
  let capability := FinalizedArtifactsV1.capabilityOf finalized
  unless ResolvedEngineeringBuildV1.targetIdOf capability == TargetId.near do
    productError "finalized artifact target is not NEAR"
  unless ResolvedEngineeringBuildV1.codegenProfileOf capability ==
      CodegenProfileId.nearWasmRawU64V1 do
    productError "finalized artifact profile is not near-wasm-raw-u64-v1"
  unless FinalizedArtifactsV1.deployableOf finalized do
    productError "finalized NEAR artifact is not deployable"
  let artifacts := FinalizedArtifactsV1.artifactsOf finalized
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let wasmPath := s!"{programName}.wasm"
  unless FinalizedArtifactsV1.extraFilesOf finalized == #[wasmPath] do
    productError "finalized NEAR extra-file closure is not the exact Wasm artifact"
  pure (programName, wasmPath)

private def digestOfLockedExecutableV1
    (tool : VerifiedTool) : IO Digest :=
  match parseDigest ("sha256:" ++ tool.executableSha256) with
  | .ok digest => pure digest
  | .error error => productError s!"locked provider executable digest is invalid ({error})"

private def requireExactVersionProbeV1 (tool : VerifiedTool) : IO Unit := do
  unless tool.id == wasmCertProviderToolIdV1 &&
      tool.version == wasmCertProviderVersionV1 do
    productError "locked provider id/version differs from the frozen WasmCert protocol"
  let probe ← tool.run #["--version"]
  unless probe.exitCode == 0 &&
      probe.stdout == wasmCertProviderExpectedVersionV1 ++ "\n" &&
      probe.stderr.isEmpty do
    productError "locked provider exact version probe failed"

private def requireUnchangedInputV1
    (directory : FilePath) (relative : String) (expected : ByteArray) : IO Unit := do
  let (_size, bytes, digest) ← readStableArtifactLeafBytesV1 directory relative
  unless bytes == expected && digest == sha256Bytes expected do
    productError s!"provider mutated semantics-bearing input '{relative}'"

private def requireFinalizedDiskClosureV1
    (finalized : FinalizedArtifactsV1)
    (stagingDir : FilePath)
    (wasmPath : String) : IO Digest := do
  let inventory ← scanEngineeringArtifactContentOnlyV1 finalized stagingDir
  let descriptors := ArtifactContentInventoryV1.descriptorsOf inventory
  let artifacts := FinalizedArtifactsV1.artifactsOf finalized
  for file in MaterializedArtifactsV1.filesOf artifacts do
    let descriptor ← match descriptors.find? fun descriptor =>
        descriptor.role == .materializedBase && descriptor.path == file.path with
      | some descriptor => pure descriptor
      | none => productError s!"finalized disk closure omitted base artifact '{file.path}'"
    let expectedBytes := file.contents.toUTF8
    unless descriptor.size == expectedBytes.size &&
        descriptor.contentSha256 == sha256Bytes expectedBytes do
      productError s!"finalized base artifact '{file.path}' differs from materialized bytes"
  let wasmDescriptor ← match descriptors.find? fun descriptor =>
      descriptor.role == .finalizedExtra && descriptor.path == wasmPath with
    | some descriptor => pure descriptor
    | none => productError "finalized disk closure omitted the exact Wasm artifact"
  pure wasmDescriptor.contentSha256

/-- Execute one canonical invocation against the exact finalized Wasm bytes.

    Order is fail closed:

    1. bind the private finalization carrier to the sole NEAR profile;
    2. require explicit provider activation and resolve/rehash Tool Lock;
    3. run an exact version probe in the locked isolated environment;
    4. write canonical input/request bytes into an exclusive temporary dir;
    5. run exact argv, reject diagnostics on success, and re-read unchanged
       semantics-bearing inputs;
    6. decode/join result, trace, and observation, including host replay;
    7. mint one private identity-bound execution observation.

    No PATH fallback, ambient provider, caller-selected executable, or partial
    output survives failure. A separate Reference refinement layer must consume
    the returned canonical observation; this function does not copy business
    semantics. -/
def executeLockedWasmCertV1
    (finalized : FinalizedArtifactsV1)
    (stagingDir : FilePath)
    (invocation : WasmCertInvocationArtifactV1)
    (fuel : UInt64) : IO WasmCertLockedExecutionObservationV1 := do
  let (programName, finalizedWasmPath) ← requireFinalizedNearIdentityV1 finalized
  let activatedDigest ← requireProviderActivationV1
  let provider ← resolve wasmCertProviderToolIdV1
  requireExactVersionProbeV1 provider
  let executableDigest ← digestOfLockedExecutableV1 provider
  unless executableDigest == activatedDigest do
    productError "resolved provider executable differs from the activation identity"
  let toolLockIdentity ← match embeddedToolLockV4Identity with
    | .ok identity => pure identity
    | .error error => productError s!"active Tool Lock identity is invalid ({error})"

  let artifacts := FinalizedArtifactsV1.artifactsOf finalized
  let closureWasmDigest ←
    requireFinalizedDiskClosureV1 finalized stagingDir finalizedWasmPath
  let (_wasmSize, wasmBytes, wasmDigest) ←
    readStableArtifactLeafBytesV1 stagingDir finalizedWasmPath
  unless wasmDigest == closureWasmDigest do
    productError "finalized Wasm changed after exact disk-closure observation"
  FinalizeV1.requireValidWasmBinaryEnvelope wasmBytes
  let invocationText ← match encodeWasmCertInvocationArtifactV1 invocation with
    | .ok text => pure text
    | .error error => productError s!"invalid invocation ({error})"
  let invocationBytes := invocationText.toUTF8
  let invocationDigest := sha256Bytes invocationBytes

  IO.FS.withTempDir fun workDir => do
    let wasmRel := "input.wasm"
    let invocationRel := "invocation.pf-jcs.json"
    let requestRel := "request.pf-jcs.json"
    let resultRel := "result.pf-jcs.json"
    let traceRel := wasmCertProviderHostTracePathV1 resultRel
    let observationRel := wasmCertProviderObservationPathV1 resultRel
    let request : WasmCertProviderRequestV1 := {
      schema := wasmCertProviderRequestSchemaV1
      providerRevision := wasmCertCoqRevisionV1
      inputWasmPath := wasmRel
      inputWasmSha256 := wasmDigest
      invocationPath := invocationRel
      invocationSha256 := invocationDigest
      fuel
    }
    let requestText ← match encodeWasmCertProviderRequestV1 request with
      | .ok text => pure text
      | .error error => productError s!"invalid provider request ({error})"
    let requestBytes := requestText.toUTF8
    IO.FS.writeBinFile (workDir / wasmRel) wasmBytes
    IO.FS.writeBinFile (workDir / invocationRel) invocationBytes
    IO.FS.writeBinFile (workDir / requestRel) requestBytes

    let argv := wasmCertProviderArgvV1 requestRel resultRel
    let process ← provider.run argv (some workDir)
    unless process.exitCode == 0 do
      productError s!"provider exited {process.exitCode} ({process.stderr.trimAscii.copy})"
    unless process.stdout.isEmpty && process.stderr.isEmpty do
      productError "successful provider execution emitted diagnostics"

    let _ ← scanArtifactContentClosureV1 workDir #[
      { role := .materializedBase, path := wasmRel },
      { role := .materializedBase, path := invocationRel },
      { role := .materializedBase, path := requestRel },
      { role := .finalizedExtra, path := resultRel },
      { role := .finalizedExtra, path := traceRel },
      { role := .finalizedExtra, path := observationRel }
    ] #[]
    requireUnchangedInputV1 workDir wasmRel wasmBytes
    requireUnchangedInputV1 workDir invocationRel invocationBytes
    requireUnchangedInputV1 workDir requestRel requestBytes
    let (_resultSize, resultBytes, resultDigest) ←
      readStableArtifactLeafBytesV1 workDir resultRel
    let (_traceSize, traceBytes, traceDigest) ←
      readStableArtifactLeafBytesV1 workDir traceRel
    let (_observationSize, observationBytes, observationDigest) ←
      readStableArtifactLeafBytesV1 workDir observationRel
    let record ← match decodeWasmCertProviderResultRecordV1 resultBytes with
      | .ok record => pure record
      | .error error => productError s!"invalid provider result ({error})"
    unless record.executableSha256 == executableDigest do
      productError "provider self-reported executable digest differs from Tool Lock"
    let joined ← match validateWasmCertProviderArtifactsForRequestV1 request
        requestRel resultRel record invocationBytes traceBytes observationBytes with
      | .ok joined => pure joined
      | .error error => productError s!"provider artifact join failed ({error})"
    unless joined.1 == invocation do
      productError "decoded invocation differs from the canonical product input"
    unless record.hostTraceSha256 == traceDigest &&
        record.observationSha256 == observationDigest do
      productError "provider record output digests differ from stable product reads"

    let identity : WasmCertLockedExecutionIdentityV1 := {
      schema := wasmCertLockedExecutionIdentitySchemaV1
      toolId := provider.id
      toolVersion := provider.version
      executableSha256 := executableDigest
      toolLockPlatform := toolLockIdentity.platform.wire
      toolLockSha256 := toolLockIdentity.digest
      artifactProgramName := programName
      sourceSha256 := MaterializedArtifactsV1.sourceDigestOf artifacts
      semanticSha256 := MaterializedArtifactsV1.semanticDigestOf artifacts
      finalizedWasmPath
      finalizedWasmSha256 := wasmDigest
      fuel
      invocationSha256 := invocationDigest
      requestSha256 := sha256Bytes requestBytes
      resultSha256 := resultDigest
      hostTraceSha256 := traceDigest
      observationSha256 := observationDigest
    }
    pure (WasmCertLockedExecutionObservationV1.mk
      finalized identity joined.1 joined.2.1 joined.2.2)

end ProofForgeV2.Targets.Near
