import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay
import ProofForge.IR.Examples.ValueVault

namespace Tests.Quint.ValueVaultIrModelGate

open ProofForge.Backend.Quint

def qntPath := "build/quint/ValueVaultIrModel.qnt"
def itfPath := "build/quint/ValueVaultIrModel.itf.json"

def runQuintMbt : IO Unit := do
  let out ← IO.Process.output {
    cmd := "quint",
    args := #["run", qntPath, "--mbt", s!"--out-itf={itfPath}", "--max-samples=1", "--max-steps=5"]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"quint run --mbt failed: {out.stderr}")

def main : IO UInt32 := do
  runQuintMbt
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

end Tests.Quint.ValueVaultIrModelGate

def main : IO UInt32 := Tests.Quint.ValueVaultIrModelGate.main