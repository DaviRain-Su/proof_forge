import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay
import ProofForge.Backend.Quint.EvmReplay
import ProofForge.IR.Examples.Counter

namespace Tests.Quint.CounterIrModelGate

open ProofForge.Backend.Quint

def qntPath := "build/quint/CounterIrModel.qnt"
def itfPath := "build/quint/CounterIrModel.itf.json"
def binPath := "build/quint/CounterIrModel.bin"
def yulPath := "build/quint/CounterIrModel.yul"
def forgeDir := "build/foundry-quint-counter-ir-model-gate"

def runQuintMbt : IO Unit := do
  let out ← IO.Process.output {
    cmd := "quint",
    args := #["run", qntPath, "--mbt", s!"--out-itf={itfPath}", "--max-samples=1", "--max-steps=5"]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"quint run --mbt failed: {out.stderr}")

def replayIr (trace : ITF.Trace) : IO Unit :=
  match Replay.replayTrace ProofForge.IR.Examples.Counter.module trace with
  | .error err => throw (IO.userError s!"IR replay failed: {err.message}")
  | .ok () => pure ()

def commandAvailable (name : String) : IO Bool := do
  let out ← IO.Process.output { cmd := "command", args := #["-v", name] }
  pure (out.exitCode == 0)

def emitBytecode : IO Unit := do
  let out ← IO.Process.output {
    cmd := ".lake/build/bin/proof-forge",
    args := #["emit", "--target", "evm", "--fixture", "counter", "--format", "bytecode",
      "--yul-output", yulPath, "-o", binPath]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"proof-forge emit failed: {out.stderr}")

def runForgeTest (testSource : String) : IO Unit := do
  let home := (← IO.getEnv "HOME").getD ""
  let path := (← IO.getEnv "PATH").getD ""
  let testPath := s!"{forgeDir}/test/ProofForgeQuintCounterIrModelGate.t.sol"
  let toml :=
    "[profile.default]\n" ++
    "src = \"src\"\n" ++
    "test = \"test\"\n" ++
    "out = \"out\"\n" ++
    "libs = [\"lib\"]\n" ++
    "solc_version = \"0.8.30\"\n" ++
    "optimizer = true\n" ++
    "optimizer_runs = 200\n" ++
    "via_ir = true\n"
  IO.FS.createDirAll s!"{forgeDir}/test"
  IO.FS.writeFile s!"{forgeDir}/foundry.toml" toml
  IO.FS.writeFile testPath testSource
  let out ← IO.Process.output {
    cmd := "forge",
    args := #["test", "--root", forgeDir, "-vv"],
    env := #[("PATH", s!"{home}/.foundry/bin:{path}")]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"forge test failed:\n{out.stdout}\n{out.stderr}")

def replayEvm (trace : ITF.Trace) : IO Unit := do
  let forgeOk ← commandAvailable "forge"
  let solcOk ← commandAvailable "solc"
  if !forgeOk || !solcOk then
    let ci := (← IO.getEnv "CI").getD "" == "true" || (← IO.getEnv "GITHUB_ACTIONS").getD "" == "true"
    if ci then
      throw (IO.userError "EVM backend replay requires forge and solc in CI")
    else
      IO.println "SKIP: EVM backend replay (forge or solc missing)"
      return ()
  emitBytecode
  let raw ← IO.FS.readFile binPath
  let bytecodeHex := raw.replace "\n" ""
  let cfg : EvmReplay.EvmReplayConfig := {
    bytecodeHex,
    readSignature := "get()",
    primaryStateVar := "count"
  }
  let testSource ← match EvmReplay.renderFoundryTest ProofForge.IR.Examples.Counter.module trace cfg with
    | .error err => throw (IO.userError s!"render Foundry test failed: {err.message}")
    | .ok source => pure source
  runForgeTest testSource

def main : IO UInt32 := do
  runQuintMbt
  let itfJson ← IO.FS.readFile itfPath
  let trace ← match ITF.parse itfJson with
    | .error err => throw (IO.userError s!"parse ITF failed: {err}")
    | .ok trace => pure trace
  replayIr trace
  replayEvm trace
  IO.println "PASS"
  return 0

end Tests.Quint.CounterIrModelGate

def main : IO UInt32 := Tests.Quint.CounterIrModelGate.main