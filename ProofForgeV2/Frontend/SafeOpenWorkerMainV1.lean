import ProofForgeV2.Frontend.SafeOpenWorkerV1

namespace ProofForgeV2.Frontend.SafeOpenWorkerMainV1

open ProofForgeV2.Frontend.SafeOpenWorkerV1

private def failProcess (token : String) (code : UInt8) : IO α := do
  IO.eprintln token
  IO.Process.exit code

private def failFault : SafeOpenWorkerFaultV1 → IO α
  | .protocol => failProcess protocolStderrTokenV1 protocolExitCodeV1
  | .internal => failProcess internalStderrTokenV1 internalExitCodeV1

/-- Prepare one complete response before any intentional stdout write. -/
private def prepareResponse : IO (Except SafeOpenWorkerFaultV1 ByteArray) := do
  try
    let stdin ← IO.getStdin
    match ← readProtocolFrameV1 stdin with
    | .error fault => pure (.error fault)
    | .ok input => processFrameV1 input
  catch _ =>
    pure (.error .internal)

/-- Standalone B11b2 safe-open worker entry. Valid SafeOpen.Err.v1 exits zero. -/
def run (args : List String) : IO Unit := do
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

end ProofForgeV2.Frontend.SafeOpenWorkerMainV1

unsafe def main (args : List String) : IO Unit :=
  ProofForgeV2.Frontend.SafeOpenWorkerMainV1.run args
