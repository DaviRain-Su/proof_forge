/-
  ProofForgeV2.Frontend.WorkerV1 — B10 standalone one-request frontend worker.

  This module owns deterministic request processing for the future contained
  frontend boundary. It is deliberately not a product caller and does not claim
  containment: no file open, network, subprocess, target/profile input, cache,
  output staging, supervisor, receipt, fallback, or second ProgramV1 decoder.

  One process handles one already-opened stdin request:
    decode Frontend.Req.v1
      → exact static language version (sole enabled 1.0.0)
      → source UTF-8 validation
      → Loader.selectProgramV1FrontendPayload (single parser snapshot)
      → complete Frontend.Ok.v1 or Frontend.Err.v1 bytes.

  Valid request failures are protocol Err frames, not abnormal worker exits.
  Malformed protocol and impossible response construction are closed worker
  faults; WorkerMainV1 maps them to stable stderr tokens/nonzero exits.
-/
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Language.Loader

namespace ProofForgeV2.Frontend.WorkerV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Language.Loader

/-- Closed abnormal worker classes. Details are intentionally not retained: the
    future supervisor maps controller/protocol events, never stderr prose. -/
inductive FrontendWorkerFaultV1 where
  | protocol
  | internal
  deriving BEq, DecidableEq, Repr

/-- Sole enabled exact parser version for the B10 worker. No ranges/default
    negotiation is performed inside the worker protocol. -/
def languageVersion100V1 : SemVer :=
  LanguageParserDescriptorV1.version languageParser100V1

/-- Stable public-safe stderr tokens used only for abnormal process exits. -/
def usageStderrTokenV1 : String := "frontend-worker: usage"
def protocolStderrTokenV1 : String := "frontend-worker: protocol"
def internalStderrTokenV1 : String := "frontend-worker: internal"

/-- Stable standalone process exit values (not product CLI diagnostic exits). -/
def usageExitCodeV1 : UInt8 := 64
def protocolExitCodeV1 : UInt8 := 65
def internalExitCodeV1 : UInt8 := 70

private def internalResult (result : Except String α) : Except FrontendWorkerFaultV1 α :=
  match result with
  | .ok value => .ok value
  | .error _ => .error .internal

private def encodeFailure
    (request : FrontendRequestV1) (diagnostics : Array DiagnosticV1) :
    Except FrontendWorkerFaultV1 ByteArray := do
  let failure ← internalResult (mkFrontendFailureV1 request diagnostics)
  internalResult (encodeFrontendFailureV1 failure)

private def languageVersionDiagnostic
    (actual : SemVer) : Except FrontendWorkerFaultV1 DiagnosticV1 := do
  let expected ← internalResult (renderSemVer languageVersion100V1)
  let actual ← internalResult (renderSemVer actual)
  pure <| DiagnosticV1.make .languageVersionUnknown
    s!"language version '{actual}' is not registered"
    (expected := some (.string expected))
    (actual := some (.string actual))

private def invalidUtf8Diagnostic : DiagnosticV1 :=
  DiagnosticV1.make .sourceInvalid "source is not valid UTF-8"
    (expected := some (.string "valid UTF-8 source bytes"))
    (actual := some (.string "invalid UTF-8"))

/-- Process one already-decoded request. The Loader is invoked at most once and
    only for exact language version 1.0.0 plus valid UTF-8 source bytes. -/
unsafe def processRequestV1
    (request : FrontendRequestV1) :
    IO (Except FrontendWorkerFaultV1 ByteArray) := do
  if FrontendRequestV1.languageVersion request != languageVersion100V1 then
    match languageVersionDiagnostic (FrontendRequestV1.languageVersion request) with
    | .error fault => pure (.error fault)
    | .ok diagnostic => pure (encodeFailure request #[diagnostic])
  else
    match String.fromUTF8? (FrontendRequestV1.sourceBytes request) with
    | none => pure (encodeFailure request #[invalidUtf8Diagnostic])
    | some source =>
        let logicalPath ←
          match renderProjectRelativePath (FrontendRequestV1.sourcePath request) with
          | .ok path => pure path
          | .error _ => return .error .internal
        let session ← ParserSession.create
        match ← session.selectProgramV1FrontendPayload
            source logicalPath (FrontendRequestV1.moduleSelector request)
            (FrontendRequestV1.programSelector request) with
        | .error bundle =>
            pure (encodeFailure request (DiagnosticBundleV1.diagnostics bundle))
        | .ok (validated, spans) =>
            match mkFrontendSuccessV1 request validated spans with
            | .error _ => pure (.error .internal)
            | .ok success => pure (internalResult (encodeFrontendSuccessV1 success))

/-- Decode and process one complete request frame. Decode failures are protocol
    faults; all valid source/parser failures are encoded Frontend.Err.v1 bytes. -/
unsafe def processFrameV1
    (input : ByteArray) : IO (Except FrontendWorkerFaultV1 ByteArray) := do
  match decodeFrontendRequestV1 input with
  | .error _ => pure (.error .protocol)
  | .ok request => processRequestV1 request

/-- Read stdin in bounded chunks, probing exactly one byte beyond the 64 MiB
    protocol hard maximum. Never uses unbounded read-to-end. Timeout/process
    containment is intentionally owned by the future B11 supervisor. -/
def readProtocolFrameV1
    (stream : IO.FS.Stream) : IO (Except FrontendWorkerFaultV1 ByteArray) := do
  let probeLimit := maxProtocolBytes + 1
  let chunkSize := 64 * 1024
  let mut bytes := ByteArray.empty
  let mut done := false
  while !done do
    let remainingBudget := probeLimit - bytes.size
    if remainingBudget == 0 then
      return .error .protocol
    let wanted := Nat.min chunkSize remainingBudget
    let chunk ← stream.read (USize.ofNat wanted)
    if chunk.isEmpty then
      done := true
    else
      bytes := bytes.append chunk
      if bytes.size > maxProtocolBytes then
        return .error .protocol
  pure (.ok bytes)

end ProofForgeV2.Frontend.WorkerV1
