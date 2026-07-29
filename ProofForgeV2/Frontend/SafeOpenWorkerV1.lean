/-
  ProofForgeV2.Frontend.SafeOpenWorkerV1 — B11b2 standalone safe-open helper.

  One process handles one already-buffered stdin request:
    decode SafeOpen.Req.v1
      → sole safeOpenSourceV1
      → complete SafeOpen.Ok.v1 or SafeOpen.Err.v1 bytes.

  Abnormal process faults are closed (protocol/internal); WorkerMain maps them
  to stable stderr tokens and nonzero exits without path leakage.
-/
import ProofForgeV2.Frontend.SafeOpenV1
import ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1

namespace ProofForgeV2.Frontend.SafeOpenWorkerV1

open ProofForgeV2.Frontend.SafeOpenV1
open ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1

/-- Closed abnormal worker classes (same taxonomy as B10). -/
inductive SafeOpenWorkerFaultV1 where
  | protocol
  | internal
  deriving BEq, DecidableEq, Repr

def usageStderrTokenV1 : String := "safe-open-worker: usage"
def protocolStderrTokenV1 : String := "safe-open-worker: protocol"
def internalStderrTokenV1 : String := "safe-open-worker: internal"

def usageExitCodeV1 : UInt8 := 64
def protocolExitCodeV1 : UInt8 := 65
def internalExitCodeV1 : UInt8 := 70

private def internalResult (result : Except String α) :
    Except SafeOpenWorkerFaultV1 α :=
  match result with
  | .ok value => .ok value
  | .error _ => .error .internal

/-- Process one decoded request via the sole B11a safe-open primitive. -/
def processRequestV1
    (request : SafeOpenWorkerRequestV1) :
    IO (Except SafeOpenWorkerFaultV1 ByteArray) := do
  match ← safeOpenSourceV1
      (SafeOpenWorkerRequestV1.root request)
      (SafeOpenWorkerRequestV1.path request) with
  | .error fault =>
      match mkSafeOpenWorkerFailureV1 fault with
      | .error _ => pure (.error .internal)
      | .ok failure =>
          pure (internalResult (encodeSafeOpenWorkerFailureV1 failure))
  | .ok snapshot =>
      match mkSafeOpenWorkerSuccessV1 (SafeSourceSnapshotV1.bytes snapshot) with
      | .error _ => pure (.error .internal)
      | .ok success =>
          pure (internalResult (encodeSafeOpenWorkerSuccessV1 success))

/-- Decode and process one complete request frame. -/
def processFrameV1
    (input : ByteArray) : IO (Except SafeOpenWorkerFaultV1 ByteArray) := do
  match decodeSafeOpenWorkerRequestV1 input with
  | .error _ => pure (.error .protocol)
  | .ok request => processRequestV1 request

/-- Read stdin in bounded chunks and probe exactly one byte beyond the closed
    safe-open protocol maximum. This implementation is intentionally independent
    of the frontend parser worker and therefore cannot acquire a Loader import. -/
def readProtocolFrameV1
    (stream : IO.FS.Stream) : IO (Except SafeOpenWorkerFaultV1 ByteArray) := do
  let probeLimit := maxSafeOpenProtocolBytesV1 + 1
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
      if bytes.size > maxSafeOpenProtocolBytesV1 then
        return .error .protocol
  pure (.ok bytes)

end ProofForgeV2.Frontend.SafeOpenWorkerV1
