import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.Scenario

namespace Tests.Quint.ContractSourceInvariants

open ProofForge.Backend.Quint

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def main : IO UInt32 := do
  let counterInvs := ProofForge.Contract.Examples.Counter.spec.quintInvariants
  require (counterInvs.any (fun (n, _) => n == "countBounded"))
    "Counter spec missing countBounded quint_invariant"
  let counterScenario : Scenario.Config := {
    maxUint := 3,
    contractInvariants := counterInvs
  }
  match Lower.renderModule ProofForge.Contract.Examples.Counter.module counterScenario with
  | .error e => throw (IO.userError s!"Counter lower failed: {e.message}")
  | .ok source =>
      require (source.contains "val countBounded = count <= MAX_UINT")
        "Counter model missing countBounded val from contract_source"

  let vaultInvs := ProofForge.Contract.Examples.ValueVault.spec.quintInvariants
  require (vaultInvs.size == 2) "ValueVault spec should expose two quint_invariant annotations"
  let vaultScenario : Scenario.Config := {
    maxUint := 5,
    contractInvariants := vaultInvs
  }
  match Lower.renderModule ProofForge.Contract.Examples.ValueVault.module vaultScenario with
  | .error e => throw (IO.userError s!"ValueVault lower failed: {e.message}")
  | .ok source =>
      require (source.contains "val totalCoversReleased = balance + released + fees >= released")
        "ValueVault model missing totalCoversReleased"
      require (source.contains "val totalCoversFees = balance + released + fees >= fees")
        "ValueVault model missing totalCoversFees"

  IO.println "PASS"
  return 0

end Tests.Quint.ContractSourceInvariants

def main : IO UInt32 := Tests.Quint.ContractSourceInvariants.main