import ProofForge.Contract.Examples.Counter
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.EvmReplay
import ProofForge.IR.Examples.Counter

namespace Tests.Quint.CounterEvmReplay

open ProofForge.Backend.Quint

def scenario : Scenario.Config := {
  maxUint := 3,
  users := #["alice", "bob"],
  maxSteps := 5,
  nTraces := 1,
  contractInvariants := ProofForge.Contract.Examples.Counter.spec.quintInvariants
}

def generateModel : IO String :=
  match Lower.renderModule ProofForge.IR.Examples.Counter.module scenario with
  | .ok s => pure s
  | .error e => throw (IO.userError s!"lower failed: {e.message}")

def runQuint (qntPath itfPath : String) : IO Unit := do
  let out ← IO.Process.output {
    cmd := "quint",
    args := #["run", qntPath, "--mbt", s!"--out-itf={itfPath}", "--max-samples=1", "--max-steps=5"]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"quint run failed: {out.stderr}")

def emitBytecode (binPath yulPath : String) : IO Unit := do
  let out ← IO.Process.output {
    cmd := ".lake/build/bin/proof-forge",
    args := #["emit", "--target", "evm", "--fixture", "counter", "--format", "bytecode",
      "--yul-output", yulPath, "-o", binPath]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"proof-forge emit failed: {out.stderr}")

def readBytecodeHex (binPath : String) : IO String := do
  let raw ← IO.FS.readFile binPath
  pure (raw.replace "\n" "")

def runForge (forgeDir : String) : IO Unit := do
  let home := (← IO.getEnv "HOME").getD ""
  let path := (← IO.getEnv "PATH").getD ""
  let out ← IO.Process.output {
    cmd := "forge",
    args := #["test", "--root", forgeDir, "-vv"],
    env := #[("PATH", s!"{home}/.foundry/bin:{path}")]
  }
  if out.exitCode != 0 then
    throw (IO.userError s!"forge test failed:\n{out.stdout}\n{out.stderr}")

def foundryToml : String :=
  "[profile.default]\n" ++
  "src = \"src\"\n" ++
  "test = \"test\"\n" ++
  "out = \"out\"\n" ++
  "libs = [\"lib\"]\n" ++
  "solc_version = \"0.8.30\"\n" ++
  "optimizer = true\n" ++
  "optimizer_runs = 200\n" ++
  "via_ir = true\n"

def main : IO UInt32 := do
  let qntPath := "build/quint/CounterEvmReplay.qnt"
  let itfPath := "build/quint/CounterEvmReplay.itf.json"
  let binPath := "build/quint/CounterEvmReplay.bin"
  let yulPath := "build/quint/CounterEvmReplay.yul"
  let forgeDir := "build/foundry-quint-counter-evm-replay"
  let testPath := s!"{forgeDir}/test/ProofForgeQuintCounterEvmReplay.t.sol"

  IO.FS.createDirAll "build/quint"
  let model ← generateModel
  IO.FS.writeFile qntPath model
  runQuint qntPath itfPath

  emitBytecode binPath yulPath
  let bytecodeHex ← readBytecodeHex binPath

  let itfJson ← IO.FS.readFile itfPath
  let trace ← match ITF.parse itfJson with
    | .error err => throw (IO.userError s!"parse ITF failed: {err}")
    | .ok trace => pure trace

  let cfg : EvmReplay.EvmReplayConfig := {
    bytecodeHex,
    readSignature := "get()",
    primaryStateVar := "count"
  }
  let testSource ← match EvmReplay.renderFoundryTest ProofForge.IR.Examples.Counter.module trace cfg with
    | .error err => throw (IO.userError s!"render Foundry test failed: {err.message}")
    | .ok source => pure source

  IO.FS.createDirAll s!"{forgeDir}/test"
  IO.FS.writeFile s!"{forgeDir}/foundry.toml" foundryToml
  IO.FS.writeFile testPath testSource

  runForge forgeDir
  IO.println "PASS"
  return 0

end Tests.Quint.CounterEvmReplay

def main : IO UInt32 := Tests.Quint.CounterEvmReplay.main