import ProofForge.Contract.Examples.Counter
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.Scenario

namespace Tests.Quint.ContractSourceLiveness

open ProofForge.Backend.Quint

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def main : IO UInt32 := do
  let counterLiveness := ProofForge.Contract.Examples.Counter.spec.quintLiveness
  require (counterLiveness.any (fun (n, _) => n == "eventuallyPositive"))
    "Counter spec missing eventuallyPositive quint_liveness"
  let counterScenario : Scenario.Config := {
    maxUint := 3,
    contractInvariants := ProofForge.Contract.Examples.Counter.spec.quintInvariants,
    contractLiveness := counterLiveness
  }
  match Lower.renderModule ProofForge.Contract.Examples.Counter.module counterScenario with
  | .error e => throw (IO.userError s!"Counter lower failed: {e.message}")
  | .ok source =>
      require (source.contains "temporal eventuallyPositive = eventually(count > 0)")
        "Counter model missing eventuallyPositive temporal from contract_source"

  IO.println "PASS"
  return 0

end Tests.Quint.ContractSourceLiveness

def main : IO UInt32 := Tests.Quint.ContractSourceLiveness.main