import ProofForge.Contract.Examples.ValueVault
import ProofForge.IR.Examples.ValueVault
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay
import ProofForge.Backend.Quint.Scenario

namespace Tests.Quint.ValueVaultReplay

open ProofForge.Backend.Quint

def loadScenario : IO Scenario.Config := do
  let contents ← IO.FS.readFile "Tests/Quint/ValueVault.scenario.toml"
  match Scenario.parse contents with
  | .ok cfg => return cfg
  | .error msg => throw (IO.userError s!"scenario parse failed: {msg}")

def scenario : IO Scenario.Config := do
  let cfg ← loadScenario
  pure { cfg with contractInvariants := ProofForge.Contract.Examples.ValueVault.spec.quintInvariants }

def generateModel : IO String := do
  let s ← scenario
  match Lower.renderModule ProofForge.IR.Examples.ValueVault.module s with
  | .ok s => pure s
  | .error e => throw (IO.userError s!"lower failed: {e.message}")

def runQuint (qntPath itfPath : String) : IO Unit := do
  let out ← IO.Process.output {
    cmd := "quint",
    args := #["run", qntPath, "--mbt", s!"--out-itf={itfPath}", "--max-samples=1", "--max-steps=5"]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"quint run failed: {out.stderr}")

def main : IO UInt32 := do
  let qntPath := "build/quint/ValueVaultReplay.qnt"
  let itfPath := "build/quint/ValueVaultReplay.itf.json"
  let model ← generateModel
  IO.FS.createDirAll "build/quint"
  IO.FS.writeFile qntPath model
  IO.println s!"wrote {qntPath}"
  runQuint qntPath itfPath
  let itfJson ← IO.FS.readFile itfPath
  match ITF.parse itfJson with
  | .error err =>
      IO.eprintln s!"FAIL parse ITF: {err}"
      return 1
  | .ok trace =>
      match Replay.replayTrace ProofForge.IR.Examples.ValueVault.module trace with
      | .error err =>
          IO.eprintln s!"FAIL replay: {err.message}"
          return 1
      | .ok () =>
          IO.println "PASS"
          return 0

end Tests.Quint.ValueVaultReplay

def main : IO UInt32 := Tests.Quint.ValueVaultReplay.main
