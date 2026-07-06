import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay
import ProofForge.IR.Examples.UnboundedIntProbe

namespace Tests.Quint.UnboundedIntReplay

open ProofForge.Backend.Quint

def scenario : Scenario.Config := {
  maxUint := 3,
  users := #["alice"],
  indexFromZero := true,
  unboundedIntegers := true
}

def generateModel : IO String :=
  match Lower.renderModule ProofForge.IR.Examples.UnboundedIntProbe.module scenario with
  | .ok s => pure s
  | .error e => throw (IO.userError s!"lower failed: {e.message}")

def runQuint (qntPath itfPath : String) : IO Unit := do
  let out ← IO.Process.output {
    cmd := "quint",
    args := #["run", qntPath, "--mbt", s!"--out-itf={itfPath}", "--max-samples=4", "--max-steps=8"]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"quint run failed: {out.stderr}")

def main : IO UInt32 := do
  let qntPath := "build/quint/UnboundedIntReplay.qnt"
  let itfPath := "build/quint/UnboundedIntReplay.itf.json"
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
      match Replay.replayTrace ProofForge.IR.Examples.UnboundedIntProbe.module trace with
      | .error err =>
          IO.eprintln s!"FAIL replay: {err.message}"
          return 1
      | .ok () =>
          IO.println "PASS"
          return 0

end Tests.Quint.UnboundedIntReplay

def main : IO UInt32 := Tests.Quint.UnboundedIntReplay.main