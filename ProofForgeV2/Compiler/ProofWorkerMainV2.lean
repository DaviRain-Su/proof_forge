import ProofForgeV2.Compiler.ProofWorkerControlV2
import ProofForgeV2.Compiler.ProofWorkerV1

namespace ProofForgeV2.Compiler.ProofWorkerMainV2

open ProofForgeV2.Compiler.ProofWorkerControlV2
open ProofForgeV2.Compiler.ProofWorkerProtocolV1
open ProofForgeV2.Compiler.ProofWorkerV1

private def failProcess (token : String) (code : UInt8) : IO α := do
  IO.eprintln token
  IO.Process.exit code

private def failFault : ProofWorkerFaultV1 → IO α
  | .protocol => failProcess protocolStderrTokenV1 protocolExitCodeV1
  | .internal => failProcess internalStderrTokenV1 internalExitCodeV1

private unsafe def prepareResponse : IO (Except ProofWorkerFaultV1 ByteArray) := do
  try
    match ← readControlFrameV2 with
    | .error .invalidControl | .error .invalidStdin | .error .protocol =>
        pure (.error .protocol)
    | .error .native => pure (.error .internal)
    | .ok input => processFrameV1 input
  catch _ =>
    pure (.error .internal)

/-- One-request worker using dedicated control FD 3. stdin is verified as
    `/dev/null`; this transport change alone is not containment. -/
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

end ProofForgeV2.Compiler.ProofWorkerMainV2

unsafe def main (args : List String) : IO Unit :=
  ProofForgeV2.Compiler.ProofWorkerMainV2.run args
