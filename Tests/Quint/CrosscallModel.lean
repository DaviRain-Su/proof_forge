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
        "action deploy_create",
        "action deploy_create2",
        "action call_remote_pair",
        "action call_remote_pair_arg",
        "action call_remote_array",
        "action call_remote_array_arg",
        "nondet target",
        "nondet method",
        "nondet amount",
        "nondet fee",
        "nondet flag",
        "nondet x",
        "nondet value",
        "nondet salt",
        "nondet small",
        "Map(\"flag\"",
        "target + method + 0",
        "target + method + 1]",
        "[x, y][0]",
        "[x, y][1]",
        "target + method",
        "target + method + amount + fee",
        "target + method + 1000000",
        "target + method + 2000000",
        "value + 3000000",
        "4000000",
        "if (salt == \"hash:1001:0:0:0\")",
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