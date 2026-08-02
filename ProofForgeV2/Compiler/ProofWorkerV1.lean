import ProofForgeV2.Compiler.ProofWorkerProtocolV1

/-
  Deterministic direct proof worker. This reads the fixed proof-subject pair but
  is not a containment/supervisor boundary and does not load `.olean` files.
-/

namespace ProofForgeV2.Compiler.ProofWorkerV1

open ProofForgeV2.Compiler.ProofSubjectFilesV1
open ProofForgeV2.Compiler.ProofWorkerProtocolV1
open ProofForgeV2.Frontend.ProtocolV1

inductive ProofWorkerFaultV1 where
  | protocol
  | internal
  deriving BEq, DecidableEq, Repr

def usageStderrTokenV1 : String := "compiler-proof-worker: usage"
def protocolStderrTokenV1 : String := "compiler-proof-worker: protocol"
def internalStderrTokenV1 : String := "compiler-proof-worker: internal"

def usageExitCodeV1 : UInt8 := 64
def protocolExitCodeV1 : UInt8 := 65
def internalExitCodeV1 : UInt8 := 70

private def internalResult (result : Except String α) :
    Except ProofWorkerFaultV1 α :=
  match result with
  | .ok value => .ok value
  | .error _ => .error .internal

/-- Process one canonical, already-decoded request. Frontend reconstruction is
    completed before fixed-file access; ordinary filesystem/authority failures
    are canonical response frames rather than abnormal exits. -/
def processRequestV1
    (request : ProofWorkerRequestV1) :
    IO (Except ProofWorkerFaultV1 ByteArray) := do
  let frontendRequest := ProofWorkerRequestV1.frontendRequest request
  let frontendSuccess := ProofWorkerRequestV1.frontendSuccess request
  let (source, spans) ← match
      reconstructFrontendSourceSpansV1 frontendRequest frontendSuccess with
    | .ok value => pure value
    | .error _ => return .error .internal
  let result ← loadProofSubjectFilesV1
    (ProofWorkerRequestV1.root request)
    source (FrontendRequestV1.sourcePath frontendRequest) spans
  let response ← match result with
    | .ok subject =>
        match mkProofWorkerSuccessV1 request subject with
        | .ok value => pure (.success value)
        | .error _ => return .error .internal
    | .error error =>
        match mkProofWorkerFailureV1 request error with
        | .ok value => pure (.failure value)
        | .error _ => return .error .internal
  pure (internalResult (encodeProofWorkerResponseV1 response))

def processFrameV1
    (input : ByteArray) : IO (Except ProofWorkerFaultV1 ByteArray) := do
  match decodeProofWorkerRequestV1 input with
  | .error _ => pure (.error .protocol)
  | .ok request => processRequestV1 request

end ProofForgeV2.Compiler.ProofWorkerV1
