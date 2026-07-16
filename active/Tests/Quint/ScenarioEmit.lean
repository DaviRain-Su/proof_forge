import ProofForge.Backend.Quint.Scenario
import ProofForge.Contract.Examples.Counter
import ProofForge.Cli.Quint

namespace Tests.Quint.ScenarioEmit

open ProofForge.Backend.Quint.Scenario

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def main : IO UInt32 := do
  let cfg := ProofForge.Cli.Quint.scenarioConfigForEmit "counter"
  let rendered := renderToml "counter" cfg
  require (rendered.contains "max_uint = 3") "counter scenario missing max_uint"
  require (rendered.contains "eventually(count > 0)")
    "counter scenario missing eventuallyPositive liveness"
  match parse rendered with
  | .error err => throw (IO.userError s!"roundtrip parse failed: {err}")
  | .ok parsed =>
      require (parsed.maxUint == 3) "roundtrip maxUint mismatch"
      require (parsed.liveness.size == ProofForge.Contract.Examples.Counter.spec.quintLiveness.size)
        "roundtrip liveness size mismatch"

  let vaultCfg := defaultForFixture "value-vault"
  let vaultRendered := renderToml "value-vault" vaultCfg
  match parse vaultRendered with
  | .error err => throw (IO.userError s!"value-vault parse failed: {err}")
  | .ok vaultParsed =>
      require (vaultParsed.maxUint == 100) "value-vault maxUint expected 100"
      require (vaultParsed.maxSteps == 5) "value-vault maxSteps expected 5"

  IO.println "PASS"
  return 0

end Tests.Quint.ScenarioEmit

def main : IO UInt32 := Tests.Quint.ScenarioEmit.main