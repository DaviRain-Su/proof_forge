import ProofForgeV2.Compiler.ProofWorkerProtocolV1

/- Development-only Linux supervision for one package-built proof-worker
   process. This boundary enforces a monotonic deadline and bounded output,
   drains stdout/stderr concurrently, starts a fresh process group, and performs
   bounded group termination/reaping. It deliberately does not claim memory or
   process accounting, network/write/exec confinement, setsid-escape control,
   containment, or receipt evidence. -/
namespace ProofForgeV2.Compiler.ProofWorkerSupervisorV1

open ProofForgeV2.Compiler.ProofWorkerProtocolV1
open System

inductive DevelopmentSupervisorEventV1 where
  | success | stdoutLimit | stderrLimit | deadline | signaled | nonzeroExit
  | workerProtocol | supervisorFault
  deriving BEq, DecidableEq, Repr

inductive DevelopmentCleanupV1 where
  | observedEmpty | incomplete
  deriving BEq, DecidableEq, Repr

inductive DevelopmentSupervisorFaultV1 where
  | unsupportedHost | invalidLimits | inputTooLarge | invalidWorker
  | nativeProtocol | native
  deriving BEq, DecidableEq, Repr

structure DevelopmentSupervisorLimitsV1 where
  private mk ::
  wallMillis_ : UInt64
  stdoutBytes_ : UInt64
  stderrBytes_ : UInt64

namespace DevelopmentSupervisorLimitsV1

def wallMillis (limits : DevelopmentSupervisorLimitsV1) := limits.wallMillis_
def stdoutBytes (limits : DevelopmentSupervisorLimitsV1) := limits.stdoutBytes_
def stderrBytes (limits : DevelopmentSupervisorLimitsV1) := limits.stderrBytes_

end DevelopmentSupervisorLimitsV1

/-- Fixed compiler-core development limits. Only lower, nonzero limits can be
    constructed; unimplemented ResourceProfile fields are not represented. -/
def hardDevelopmentLimitsV1 : DevelopmentSupervisorLimitsV1 :=
  ⟨30000, UInt64.ofNat maxProofWorkerProtocolBytesV1, 64 * 1024⟩

def mkDevelopmentSupervisorLimitsV1
    (wallMillis stdoutBytes stderrBytes : UInt64) :
    Except DevelopmentSupervisorFaultV1 DevelopmentSupervisorLimitsV1 := do
  unless 0 < wallMillis && wallMillis ≤ hardDevelopmentLimitsV1.wallMillis &&
      0 < stdoutBytes && stdoutBytes ≤ hardDevelopmentLimitsV1.stdoutBytes &&
      0 < stderrBytes && stderrBytes ≤ hardDevelopmentLimitsV1.stderrBytes do
    throw .invalidLimits
  pure ⟨wallMillis, stdoutBytes, stderrBytes⟩

structure DevelopmentSupervisorOutcomeV1 where
  private mk ::
  event_ : DevelopmentSupervisorEventV1
  cleanup_ : DevelopmentCleanupV1
  response_ : Option ProofWorkerResponseV1
  stdoutBytes_ : UInt64
  stderrBytes_ : UInt64

namespace DevelopmentSupervisorOutcomeV1

def event (outcome : DevelopmentSupervisorOutcomeV1) := outcome.event_
def cleanup (outcome : DevelopmentSupervisorOutcomeV1) := outcome.cleanup_
def response (outcome : DevelopmentSupervisorOutcomeV1) := outcome.response_
def stdoutBytes (outcome : DevelopmentSupervisorOutcomeV1) := outcome.stdoutBytes_
def stderrBytes (outcome : DevelopmentSupervisorOutcomeV1) := outcome.stderrBytes_

end DevelopmentSupervisorOutcomeV1

@[extern "proof_forge_supervise_proof_worker_v1"]
private opaque nativeSupervise (path : @& String) (input : @& ByteArray)
    (wall stdoutCap stderrCap : UInt64) : IO (Except String ByteArray)

private def decodeU32le (bytes : ByteArray) (offset : Nat) : Option UInt32 := do
  guard (offset + 4 ≤ bytes.size)
  pure <| UInt32.ofNat (bytes[offset]!.toNat |||
    (bytes[offset + 1]!.toNat <<< 8) |||
    (bytes[offset + 2]!.toNat <<< 16) |||
    (bytes[offset + 3]!.toNat <<< 24))

private def decodeU64le (bytes : ByteArray) (offset : Nat) : Option UInt64 := do
  guard (offset + 8 ≤ bytes.size)
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := value ||| (UInt64.ofNat bytes[offset + index]!.toNat <<<
      UInt64.ofNat (8 * index))
  pure value

private def requireSome (value : Option α) :
    Except DevelopmentSupervisorFaultV1 α :=
  match value with
  | some result => pure result
  | none => throw .nativeProtocol

private def decodeNative (bytes : ByteArray) (limits : DevelopmentSupervisorLimitsV1) :
    Except DevelopmentSupervisorFaultV1
    (DevelopmentSupervisorEventV1 × DevelopmentCleanupV1 × UInt64 × UInt64 × ByteArray) := do
  let magic : ByteArray := ByteArray.mk #[80, 70, 80, 87, 83, 86, 49, 0]
  unless bytes.size ≥ 30 && bytes.extract 0 8 == magic do
    throw .nativeProtocol
  let event ← match bytes[8]!.toNat with
    | 0 => pure .success
    | 1 => pure .stdoutLimit
    | 2 => pure .stderrLimit
    | 3 => pure .deadline
    | 4 => pure .signaled
    | 5 => pure .nonzeroExit
    | 7 => pure .supervisorFault
    | _ => throw .nativeProtocol
  let cleanup ← match bytes[9]!.toNat with
    | 0 => pure .observedEmpty
    | 1 => pure .incomplete
    | _ => throw .nativeProtocol
  let stdoutBytes ← requireSome (decodeU64le bytes 10)
  let stderrBytes ← requireSome (decodeU64le bytes 18)
  let payloadSize ← requireSome (decodeU32le bytes 26)
  unless 30 + payloadSize.toNat == bytes.size do
    throw .nativeProtocol
  unless stdoutBytes ≤ limits.stdoutBytes + 1 &&
      stderrBytes ≤ limits.stderrBytes + 1 do
    throw .nativeProtocol
  if event == .success then
    unless payloadSize.toNat == stdoutBytes.toNat &&
        stdoutBytes ≤ limits.stdoutBytes do
      throw .nativeProtocol
  else
    unless payloadSize == 0 do throw .nativeProtocol
  if event == .stdoutLimit then
    unless stdoutBytes == limits.stdoutBytes + 1 do throw .nativeProtocol
  if event == .stderrLimit then
    unless stderrBytes == limits.stderrBytes + 1 do throw .nativeProtocol
  pure (event, cleanup, stdoutBytes, stderrBytes,
    bytes.extract 30 bytes.size)

private def proofWorkerPath : IO FilePath := do
  pure ((← IO.appDir) / "proof-forge-compiler-proof-worker-v2")

private def superviseRaw (input : ByteArray)
    (limits : DevelopmentSupervisorLimitsV1) : IO (Except DevelopmentSupervisorFaultV1
      (DevelopmentSupervisorEventV1 × DevelopmentCleanupV1 × UInt64 × UInt64 × ByteArray)) := do
  unless (System.Platform.target.splitOn "-").contains "linux" do
    return .error .unsupportedHost
  if input.size > maxProofWorkerProtocolBytesV1 then
    return .error .inputTooLarge
  let worker ← proofWorkerPath
  match ← nativeSupervise worker.toString input limits.wallMillis
      limits.stdoutBytes limits.stderrBytes with
  | .error fault =>
      pure (.error (if fault == "invalid-worker" then .invalidWorker
        else if fault == "unsupported" then .unsupportedHost else .native))
  | .ok wire => pure (decodeNative wire limits)

def superviseProofWorkerFrameDevelopmentV1 (input : ByteArray)
    (limits : DevelopmentSupervisorLimitsV1 := hardDevelopmentLimitsV1) :
    IO (Except DevelopmentSupervisorFaultV1 DevelopmentSupervisorOutcomeV1) := do
  match ← superviseRaw input limits with
  | .error fault => pure (.error fault)
  | .ok (event, cleanup, stdoutBytes, stderrBytes, _) =>
    pure (.ok ⟨event, cleanup, none, stdoutBytes, stderrBytes⟩)

def superviseProofWorkerDevelopmentV1 (request : ProofWorkerRequestV1)
    (limits : DevelopmentSupervisorLimitsV1 := hardDevelopmentLimitsV1) :
    IO (Except DevelopmentSupervisorFaultV1 DevelopmentSupervisorOutcomeV1) := do
  let input ← match encodeProofWorkerRequestV1 request with
    | .ok bytes => pure bytes
    | .error _ => return .error .nativeProtocol
  match ← superviseRaw input limits with
  | .error fault => pure (.error fault)
  | .ok (event, cleanup, stdoutBytes, stderrBytes, bytes) =>
    if event == .success && cleanup == .observedEmpty && stderrBytes == 0 then
      match decodeProofWorkerResponseV1 bytes >>= bindProofWorkerResponseV1 request with
      | .ok response =>
          pure (.ok ⟨event, cleanup, some response, stdoutBytes, stderrBytes⟩)
      | .error _ =>
          pure (.ok ⟨.workerProtocol, cleanup, none, stdoutBytes, stderrBytes⟩)
    else
      pure (.ok ⟨event, cleanup, none, stdoutBytes, stderrBytes⟩)

end ProofForgeV2.Compiler.ProofWorkerSupervisorV1
