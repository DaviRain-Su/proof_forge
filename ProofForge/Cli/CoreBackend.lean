import Init.System.IO
import Lean.Util.Path
import ProofForge.Backend.Evm.CoreLower
import ProofForge.Backend.Evm.CorePlan
import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.CoreLower
import ProofForge.Backend.Solana.CorePlan
import ProofForge.Backend.WasmHost.CoreLower
import ProofForge.Backend.WasmHost.CorePlan
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.FileUtil
import ProofForge.Cli.Options
import ProofForge.Compiler.Yul.Printer
import ProofForge.Compiler.Wasm.Printer
import ProofForge.IR.Core
import ProofForge.IR.Core.Validate
import ProofForge.IR.Elaborate

open System
open ProofForge.IR.Core

namespace ProofForge.Cli

def coreOutputPath (opts : CliOptions) (defaultDir defaultFile : String) : FilePath :=
  match opts.output? with
  | none => FilePath.mk defaultDir / defaultFile
  | some out =>
      if out.extension.isNone then out / defaultFile else out

def renderElabError (e : ProofForge.IR.Core.Error.ElabError) : String :=
  reprStr e

def renderValidationError (e : ProofForge.IR.Core.Error.ValidationError) : String :=
  reprStr e

/-- Build a contract_source module through the EVM core-IR plan lane and emit
a Yul object under `build/evm-core/`.

Marked `unsafe` because it calls `ContractLoader.loadSpec`, which runs the
Lean frontend on the input module and therefore needs the unsafe
`Environment`/`IO` interface used by the CLI loader. -/
unsafe def compileEvmCoreYul (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | throw <| IO.userError "proof-forge build --target evm-core requires a contract_source .lean input"
  let spec ← ContractLoader.loadSpec input opts.root? opts.moduleName?
  let core ← match ProofForge.IR.Elaborate.elaborateModule spec.module with
    | .ok core => pure core
    | .error err => throw <| IO.userError s!"core IR elaboration failed: {renderElabError err}"
  match Validate.validateModule core with
  | .error err => throw <| IO.userError s!"core IR validation failed: {renderValidationError err}"
  | .ok () => pure ()
  let plan := ProofForge.Backend.Evm.CorePlan.buildEvmCorePlan core
  let code := ProofForge.Backend.Evm.CoreLower.lowerEvmCorePlan plan
  let yul := Lean.Compiler.Yul.Printer.render code
  let output := coreOutputPath opts "build/evm-core" s!"{spec.name}.yul"
  writeTextFile output yul
  IO.println s!"wrote {output}"
  return 0

/-- Build a contract_source module through the Solana core-IR plan lane and emit
sBPF assembly under `build/solana-core/`.

Marked `unsafe` because it calls `ContractLoader.loadSpec`; see
`compileEvmCoreYul` for the rationale. -/
unsafe def compileSolanaCoreSbpf (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | throw <| IO.userError "proof-forge build --target solana-sbpf-asm-core requires a contract_source .lean input"
  let spec ← ContractLoader.loadSpec input opts.root? opts.moduleName?
  let core ← match ProofForge.IR.Elaborate.elaborateModule spec.module with
    | .ok core => pure core
    | .error err => throw <| IO.userError s!"core IR elaboration failed: {renderElabError err}"
  match Validate.validateModule core with
  | .error err => throw <| IO.userError s!"core IR validation failed: {renderValidationError err}"
  | .ok () => pure ()
  let plan := ProofForge.Backend.Solana.CorePlan.buildSolanaCorePlan core
  let nodes := ProofForge.Backend.Solana.CoreLower.lowerSolanaCorePlan plan
  let source := ProofForge.Backend.Solana.Asm.renderNodes nodes.toArray
  let output := coreOutputPath opts "build/solana-core" s!"{spec.name}.s"
  writeTextFile output source
  IO.println s!"wrote {output}"
  return 0

/-- Build a contract_source module through the Wasm-host core-IR plan lane and
emit WAT under `build/wasm-core/`.

Marked `unsafe` because it calls `ContractLoader.loadSpec`; see
`compileEvmCoreYul` for the rationale. -/
unsafe def compileWasmCoreWat (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | throw <| IO.userError "proof-forge build --target wasm-near-core requires a contract_source .lean input"
  let spec ← ContractLoader.loadSpec input opts.root? opts.moduleName?
  let core ← match ProofForge.IR.Elaborate.elaborateModule spec.module with
    | .ok core => pure core
    | .error err => throw <| IO.userError s!"core IR elaboration failed: {renderElabError err}"
  match Validate.validateModule core with
  | .error err => throw <| IO.userError s!"core IR validation failed: {renderValidationError err}"
  | .ok () => pure ()
  let plan := ProofForge.Backend.WasmHost.CorePlan.buildWasmCorePlan core
  let module := ProofForge.Backend.WasmHost.CoreLower.lowerWasmCorePlan plan
  let wat := ProofForge.Compiler.Wasm.Printer.render module
  let output := coreOutputPath opts "build/wasm-core" s!"{spec.name}.wat"
  writeTextFile output wat
  IO.println s!"wrote {output}"
  return 0

end ProofForge.Cli
