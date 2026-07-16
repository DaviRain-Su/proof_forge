import Lean.Util.Path
import ProofForge.Backend.Aleo.IR
import ProofForge.Backend.Aleo.Instructions
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Target.HostBridge
import ProofForge.Cli.Artifact
import ProofForge.Cli.FileUtil
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec
import ProofForge.IR
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.PureMath

open System
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

/-- Z2.3: emit Counter Aleo Instructions (`.aleo`) via direct lower bootstrap. -/
def compileCounterIrAleo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (System.FilePath.mk "build/aleo/Counter.aleo")
  let prog := ProofForge.Backend.Aleo.Instructions.Lower.lowerCounterFixture
  let text := ProofForge.Backend.Aleo.Instructions.Printer.renderProgram prog
  writeTextFile output text
  IO.println s!"wrote {output} (Aleo Instructions via Z2.3 Counter lower)"
  return 0

def compileCounterIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/Counter.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError <|
        "aleo-leo fixture `counter` is unsupported on Leo 4.0.2 because its " ++
        "mapping-backed `get() -> U64` result cannot cross `final`; " ++ err.render

def compilePureMathIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/PureMath.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.PureMath.module with
  | .ok source =>
      writeTextFile output (source ++ "\n")
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

/-- Fixture-only CosmWasm Counter **spike** adapter (region ABI + cosmwasm-check).
Product `contract_source` builds use HostBridge.cosmWasm via
`--contract-source-emitwat` instead (PF-P3-02). -/
def compileCounterIrCosmWasm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/cosmwasm/Counter.wat")
  match ProofForge.Backend.WasmHost.CosmWasm.EmitWat.renderModule
      ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

end ProofForge.Cli
