import ProofForgeV2.Frontend.WorkerV1

namespace ProofForgeV2.Frontend.WorkerMainV1

open ProofForgeV2.Frontend.WorkerV1

private def failProcess (token : String) (code : UInt8) : IO α := do
  IO.eprintln token
  IO.Process.exit code

private def failFault : FrontendWorkerFaultV1 → IO α
  | .protocol => failProcess protocolStderrTokenV1 protocolExitCodeV1
  | .internal => failProcess internalStderrTokenV1 internalExitCodeV1

/-- Prepare one complete response before any intentional stdout write. -/
private unsafe def prepareResponse : IO (Except FrontendWorkerFaultV1 ByteArray) := do
  try
    let stdin ← IO.getStdin
    match ← readProtocolFrameV1 stdin with
    | .error fault => pure (.error fault)
    | .ok input => processFrameV1 input
  catch _ =>
    pure (.error .internal)

/-- Standalone B10 worker entry. Valid Frontend.Err.v1 responses exit zero. -/
unsafe def run (args : List String) : IO Unit := do
  unless args.isEmpty do
    failProcess usageStderrTokenV1 usageExitCodeV1
  match ← prepareResponse with
  | .error fault => failFault fault
  | .ok response =>
      -- `response` is complete before this single binary write. A host-level
      -- broken pipe may truncate transport, which the future supervisor treats
      -- as protocol failure; the worker never intentionally streams a frame.
      try
        let stdout ← IO.getStdout
        stdout.write response
        stdout.flush
      catch _ =>
        failProcess internalStderrTokenV1 internalExitCodeV1

end ProofForgeV2.Frontend.WorkerMainV1

unsafe def main (args : List String) : IO Unit :=
  ProofForgeV2.Frontend.WorkerMainV1.run args
