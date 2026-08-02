import ProofForgeV2.Compiler.ProofWorkerSupervisorV1

namespace Tests.Compiler.ProofWorkerSupervisorV1

open ProofForgeV2.Compiler.ProofWorkerSupervisorV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def isError : Except α β → Bool
  | .error _ => true
  | .ok _ => false

def run : IO Unit := do
  expect (isError (mkDevelopmentSupervisorLimitsV1 0 1 1))
    "zero deadline rejected"
  expect (isError (mkDevelopmentSupervisorLimitsV1 1 0 1))
    "zero stdout cap rejected"
  expect (isError (mkDevelopmentSupervisorLimitsV1 1 1 0))
    "zero stderr cap rejected"
  expect (isError (mkDevelopmentSupervisorLimitsV1
    (hardDevelopmentLimitsV1.wallMillis + 1) 1 1))
    "raised deadline rejected"
  expect (isError (mkDevelopmentSupervisorLimitsV1 1
    (hardDevelopmentLimitsV1.stdoutBytes + 1) 1))
    "raised stdout cap rejected"
  expect (isError (mkDevelopmentSupervisorLimitsV1 1 1
    (hardDevelopmentLimitsV1.stderrBytes + 1)))
    "raised stderr cap rejected"
  expect ((mkDevelopmentSupervisorLimitsV1 1 1 1).isOk)
    "lower nonzero limits accepted"
  let stderrLimits ← match mkDevelopmentSupervisorLimitsV1
      hardDevelopmentLimitsV1.wallMillis
      hardDevelopmentLimitsV1.stdoutBytes 1 with
    | .ok limits => pure limits
    | .error fault => throw <| IO.userError s!"stderr limits: {repr fault}"
  match ← superviseProofWorkerFrameDevelopmentV1 (ByteArray.mk #[0]) stderrLimits with
  | .error fault =>
      throw <| IO.userError s!"stderr-limit run: {repr fault}"
  | .ok outcome =>
      expect (outcome.event == .stderrLimit && outcome.stderrBytes == 2 &&
        outcome.cleanup == .observedEmpty)
        s!"stderr limit and cleanup, got {repr outcome.event}"
  let deadlineLimits ← match mkDevelopmentSupervisorLimitsV1 1
      hardDevelopmentLimitsV1.stdoutBytes hardDevelopmentLimitsV1.stderrBytes with
    | .ok limits => pure limits
    | .error fault => throw <| IO.userError s!"deadline limits: {repr fault}"
  match ← superviseProofWorkerFrameDevelopmentV1 (ByteArray.mk #[0]) deadlineLimits with
  | .error fault =>
      throw <| IO.userError s!"deadline run: {repr fault}"
  | .ok outcome =>
      expect (outcome.event == .deadline && outcome.cleanup == .observedEmpty)
        s!"deadline and cleanup, got {repr outcome.event}"
  match ← superviseProofWorkerFrameDevelopmentV1 (ByteArray.mk #[0]) with
  | .error fault =>
      throw <| IO.userError s!"native malformed-frame run: {repr fault}"
  | .ok outcome => do
      expect (outcome.event == .nonzeroExit)
        s!"malformed worker classified nonzero, got {repr outcome.event}"
      expect (outcome.cleanup == .observedEmpty)
        "malformed worker fully reaped"
      expect (outcome.stderrBytes > 0 && outcome.response.isNone)
        "stderr counted but response withheld"
  IO.println "Tests.Compiler.ProofWorkerSupervisorV1: ok"

end Tests.Compiler.ProofWorkerSupervisorV1
