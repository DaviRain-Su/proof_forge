import ProofForge.Contract.Examples.ValueVault
import ProofForge.IR.Examples.ValueVault
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.ValueVaultModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := {
  maxUint := 5,
  users := #["alice", "bob"],
  contractInvariants := ProofForge.Contract.Examples.ValueVault.spec.quintInvariants
}

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.ValueVault.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module ValueVaultModel",
        "var balance: int",
        "action initialize",
        "action deposit",
        "action charge_fee",
        "action release",
        "action snapshot",
        "pure def MAX_UINT: int = 5",
        "val totalCoversReleased = balance + released + fees >= released",
        "val totalCoversFees = balance + released + fees >= fees"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.ValueVaultModel

def main : IO UInt32 := Tests.Quint.ValueVaultModel.main
