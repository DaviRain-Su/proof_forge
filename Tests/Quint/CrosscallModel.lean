import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.CrosscallModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 20, users := #["alice"], indexFromZero := true }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.CrosscallProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module CrosscallProbeModel",
        "action call_remote",
        "action call_with_args",
        "action call_remote_bool",
        "action call_remote_u32",
        "action call_remote_hash",
        "action call_remote_value",
        "action call_remote_static",
        "action call_remote_delegate",
        "nondet target",
        "nondet method",
        "nondet amount",
        "nondet fee",
        "nondet flag",
        "nondet x",
        "nondet value",
        "target + method",
        "target + method + amount + fee",
        "target + method + 1000000",
        "target + method + 2000000",
        "% 2",
        "% 4294967296",
        "hash:1001:0:0:0",
        "hash:2002:0:0:0",
        "hash:3003:0:0:0"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      if source.contains "crosscallCreate" || source.contains "not supported in Quint lowering" then
        IO.eprintln "FAIL lowering must support crosscallInvoke stub"
        return 1
      IO.println "PASS"
      return 0

end Tests.Quint.CrosscallModel

def main : IO UInt32 := Tests.Quint.CrosscallModel.main