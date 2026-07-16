import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay
import ProofForge.IR.Examples.MapProbe

namespace Tests.Quint.MapNestedPathReplay

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def generateModel : IO String :=
  match Lower.renderModule ProofForge.IR.Examples.MapProbe.emitQuintNestedPathModule scenario with
  | .ok s => pure s
  | .error e => throw (IO.userError s!"lower failed: {e.message}")

def runQuint (qntPath itfPath : String) : IO Unit := do
  let out ← IO.Process.output {
    cmd := "quint",
    args := #["run", qntPath, "--mbt", s!"--out-itf={itfPath}", "--max-samples=1", "--max-steps=3"]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"quint run failed: {out.stderr}")

def main : IO UInt32 := do
  let qntPath := "build/quint/MapNestedPathReplay.qnt"
  let itfPath := "build/quint/MapNestedPathReplay.itf.json"
  let model ← generateModel
  IO.FS.createDirAll "build/quint"
  IO.FS.writeFile qntPath model
  runQuint qntPath itfPath
  let itfJson ← IO.FS.readFile itfPath
  match ITF.parse itfJson with
  | .error err =>
      IO.eprintln s!"FAIL parse ITF: {err}"
      return 1
  | .ok trace =>
      match Replay.replayTrace ProofForge.IR.Examples.MapProbe.emitQuintNestedPathModule trace with
      | .error err =>
          IO.eprintln s!"FAIL replay: {err.message}"
          return 1
      | .ok () =>
          IO.println "PASS"
          return 0

end Tests.Quint.MapNestedPathReplay

def main : IO UInt32 := Tests.Quint.MapNestedPathReplay.main