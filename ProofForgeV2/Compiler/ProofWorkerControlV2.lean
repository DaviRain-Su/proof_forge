import ProofForgeV2.Compiler.ProofWorkerProtocolV1

/- Linux worker-side reader for the dedicated V2 control descriptor. The
   native owner verifies fixed FD 3 is a blocking read pipe and stdin is the
   package supervisor's `/dev/null` descriptor before reading one bounded
   frame. -/
namespace ProofForgeV2.Compiler.ProofWorkerControlV2

open ProofForgeV2.Compiler.ProofWorkerProtocolV1

inductive ControlReadFaultV2 where
  | invalidControl | invalidStdin | protocol | native
  deriving BEq, DecidableEq, Repr

@[extern "proof_forge_read_proof_worker_control_v2"]
private opaque nativeReadControl (maximumSize : UInt64) :
  IO (Except String ByteArray)

def readControlFrameV2 : IO (Except ControlReadFaultV2 ByteArray) := do
  match ← nativeReadControl (UInt64.ofNat maxProofWorkerProtocolBytesV1) with
  | .ok bytes => pure (.ok bytes)
  | .error "control" => pure (.error .invalidControl)
  | .error "stdin" => pure (.error .invalidStdin)
  | .error "limit" => pure (.error .protocol)
  | .error _ => pure (.error .native)

end ProofForgeV2.Compiler.ProofWorkerControlV2
