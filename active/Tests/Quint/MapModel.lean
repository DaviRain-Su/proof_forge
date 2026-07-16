import ProofForge.IR.Examples.MapProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.MapModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.MapProbe.emitQuintStorageModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module MapProbeModel",
        "var balances: str -> str",
        "action setBalanceReturn",
        "balances' = balances.put(",
        "action getBalance",
        "key.in(balances.keys())",
        "action hasBalance"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.MapModel

def main : IO UInt32 := Tests.Quint.MapModel.main