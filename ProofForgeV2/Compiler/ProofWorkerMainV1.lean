import ProofForgeV2.Compiler.ProofWorkerV1
import ProofForgeV2.Core.ProtocolStreamV1

namespace ProofForgeV2.Compiler.ProofWorkerMainV1

open ProofForgeV2.Compiler.ProofWorkerProtocolV1
open ProofForgeV2.Compiler.ProofWorkerV1
open ProofForgeV2.Core.ProtocolStreamV1

private def failProcess (token : String) (code : UInt8) : IO α := do
  IO.eprintln token
  IO.Process.exit code

private def failFault : ProofWorkerFaultV1 → IO α
  | .protocol => failProcess protocolStderrTokenV1 protocolExitCodeV1
  | .internal => failProcess internalStderrTokenV1 internalExitCodeV1

private unsafe def prepareResponse :
    IO (Except ProofWorkerFaultV1 ByteArray) := do
  try
    let stdin ← IO.getStdin
    match ← readBoundedFrameV1 stdin maxProofWorkerProtocolBytesV1 with
    | .error () => pure (.error .protocol)
    | .ok input => processFrameV1 input
  catch _ =>
    pure (.error .internal)

/-- Standalone one-request entry. Valid proof-subject validation failures are
    response frames and exit zero; this process is not claimed as contained. -/
unsafe def run (args : List String) : IO Unit := do
  unless args.isEmpty do
    failProcess usageStderrTokenV1 usageExitCodeV1
  match ← prepareResponse with
  | .error fault => failFault fault
  | .ok response =>
      try
        let stdout ← IO.getStdout
        stdout.write response
        stdout.flush
      catch _ =>
        failProcess internalStderrTokenV1 internalExitCodeV1

end ProofForgeV2.Compiler.ProofWorkerMainV1

unsafe def main (args : List String) : IO Unit :=
  ProofForgeV2.Compiler.ProofWorkerMainV1.run args
