import Lean.Util.Path
import ProofForge.Cli.Evm
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.EvmArtifacts
import ProofForge.Cli.FileUtil
import ProofForge.Cli.Options
import ProofForge.Compiler.TS.Emit
import ProofForge.Compiler.TS.Printer
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.IR
import ProofForge.IR.Examples.AbiAggregateProbe
import ProofForge.IR.Examples.AbiScalarProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.AssignmentProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ErrorRefProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.EvmAbiAggregateProbe
import ProofForge.IR.Examples.EvmArrayAbiProbe
import ProofForge.IR.Examples.EvmArrayValueProbe
import ProofForge.IR.Examples.EvmAssignOpProbe
import ProofForge.IR.Examples.EvmContextProbe
import ProofForge.IR.Examples.EvmCrosscallProbe
import ProofForge.IR.Examples.EvmDynamicAbiProbe
import ProofForge.IR.Examples.EvmDynamicArrayProbe
import ProofForge.IR.Examples.EvmErrorsProbe
import ProofForge.IR.Examples.EvmExpressionProbe
import ProofForge.IR.Examples.EvmFallbackProbe
import ProofForge.IR.Examples.EvmHashProbe
import ProofForge.IR.Examples.EvmLoopProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmMemoryArrayProbe
import ProofForge.IR.Examples.EvmPackedStorageProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.IR.Examples.EvmStructArrayValueProbe
import ProofForge.IR.Examples.EvmStructValueProbe
import ProofForge.IR.Examples.EvmTypedMapProbe
import ProofForge.IR.Examples.EvmTypedStorageProbe

open System

namespace ProofForge.Cli

def compileCounterIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/Counter.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.Counter.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileErrorRefIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ErrorRefProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderCounterIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.Counter.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileCounterIrTs (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ts/Counter.ts")
  match ProofForge.Compiler.TS.Emit.emitModule ProofForge.IR.Examples.Counter.module with
  | .ok tsModule =>
    let source := ProofForge.Compiler.TS.Printer.render tsModule
    writeTextFile output source
    IO.println s!"wrote {output}"
    return 0
  | .error msg =>
    IO.eprintln s!"compileCounterIrTs: {msg}"
    return 1

def compileCounterIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/Counter.yul")
  let yul ← renderCounterIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/Counter.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "Counter" "ProofForge.IR.Examples.Counter" ProofForge.IR.Examples.Counter.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def renderErrorRefIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileErrorRefIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ErrorRefProbe.yul")
  let yul ← renderErrorRefIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ErrorRefProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module
  let (_, _, specArtifact, clientArtifact) ←
    writeEvmContractSdkClientArtifacts spec output "ErrorRefProbe"
  writeEvmIrArtifactMetadata opts "ErrorRefProbe" "ProofForge.IR.Examples.ErrorRefProbe"
    ProofForge.IR.Examples.ErrorRefProbe.module yulOutput output #[
    ("contractSpec", specArtifact),
    ("client", clientArtifact)
  ]
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileValueVaultIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ValueVault.yul")
  let module ← hydrateEvmSelectors opts.cast ProofForge.Contract.Examples.ValueVault.module
  match ProofForge.Cli.Evm.renderYul module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderValueVaultIrYul (opts : CliOptions) : IO (String × ProofForge.IR.Module) := do
  let module ← hydrateEvmSelectors opts.cast ProofForge.Contract.Examples.ValueVault.module
  match ProofForge.Cli.Evm.renderYul module with
  | .ok yul => return (yul, module)
  | .error err => throw <| IO.userError err.render

def compileValueVaultIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ValueVault.yul")
  let (yul, module) ← renderValueVaultIrYul opts
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ValueVault.bin")
  writeTextFile output (bytecode ++ "\n")
  let spec := ProofForge.Contract.ContractSpec.fromIR module
  writeEvmContractSdkArtifactMetadata opts "ValueVault" {
    moduleName := "ProofForge.Contract.Examples.ValueVault"
    kind := "portable-ir"
    leanElaborated := false
  } spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAbiScalarIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AbiScalarProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AbiScalarProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAbiScalarIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AbiScalarProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAbiScalarIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AbiScalarProbe.yul")
  let yul ← renderAbiScalarIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AbiScalarProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AbiScalarProbe" "ProofForge.IR.Examples.AbiScalarProbe" ProofForge.IR.Examples.AbiScalarProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAssertIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AssertProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssertProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAssertIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssertProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAssertIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AssertProbe.yul")
  let yul ← renderAssertIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AssertProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AssertProbe" "ProofForge.IR.Examples.AssertProbe" ProofForge.IR.Examples.AssertProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAssignmentIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AssignmentProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssignmentProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAssignmentIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssignmentProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAssignmentIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AssignmentProbe.yul")
  let yul ← renderAssignmentIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AssignmentProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AssignmentProbe" "ProofForge.IR.Examples.AssignmentProbe" ProofForge.IR.Examples.AssignmentProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmAssignOpIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAssignOpProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmAssignOpIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAssignOpProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmAssignOpIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.yul")
  let yul ← renderEvmAssignOpIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmAssignOpProbe" "ProofForge.IR.Examples.EvmAssignOpProbe" ProofForge.IR.Examples.EvmAssignOpProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileConditionalIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ConditionalProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderConditionalIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileConditionalIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ConditionalProbe.yul")
  let yul ← renderConditionalIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ConditionalProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "ConditionalProbe" "ProofForge.IR.Examples.ConditionalProbe" ProofForge.IR.Examples.ConditionalProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileContextIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ContextProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmContextProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderContextIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmContextProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileContextIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ContextProbe.yul")
  let yul ← renderContextIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ContextProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "ContextProbe" "ProofForge.IR.Examples.EvmContextProbe" ProofForge.IR.Examples.EvmContextProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmEventIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EventProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EventProbe.evmModule with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmEventIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EventProbe.evmModule with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmEventIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EventProbe.yul")
  let yul ← renderEvmEventIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EventProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EventProbe" "ProofForge.IR.Examples.EventProbe.evmModule" ProofForge.IR.Examples.EventProbe.evmModule yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmCrosscallIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmCrosscallProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmCrosscallIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmCrosscallProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmCrosscallIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.yul")
  let yul ← renderEvmCrosscallIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmCrosscallProbe" "ProofForge.IR.Examples.EvmCrosscallProbe" ProofForge.IR.Examples.EvmCrosscallProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmExpressionIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmExpressionProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmExpressionProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmExpressionIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmExpressionProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmExpressionIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmExpressionProbe.yul")
  let yul ← renderEvmExpressionIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmExpressionProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmExpressionProbe" "ProofForge.IR.Examples.EvmExpressionProbe" ProofForge.IR.Examples.EvmExpressionProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmHashIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmHashProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmHashProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmHashIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmHashProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmHashIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmHashProbe.yul")
  let yul ← renderEvmHashIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmHashProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmHashProbe" "ProofForge.IR.Examples.EvmHashProbe" ProofForge.IR.Examples.EvmHashProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmLoopIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmLoopProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmLoopProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmLoopIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmLoopProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmLoopIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmLoopProbe.yul")
  let yul ← renderEvmLoopIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmLoopProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmLoopProbe" "ProofForge.IR.Examples.EvmLoopProbe" ProofForge.IR.Examples.EvmLoopProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmMapIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMapProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMapProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmMapIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMapProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmMapIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmMapProbe.yul")
  let yul ← renderEvmMapIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMapProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmMapProbe" "ProofForge.IR.Examples.EvmMapProbe" ProofForge.IR.Examples.EvmMapProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStorageArrayIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageArrayProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStorageArrayIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageArrayProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStorageArrayIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.yul")
  let yul ← renderEvmStorageArrayIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStorageArrayProbe" "ProofForge.IR.Examples.EvmStorageArrayProbe" ProofForge.IR.Examples.EvmStorageArrayProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStorageStructIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageStructProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStorageStructIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageStructProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStorageStructIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.yul")
  let yul ← renderEvmStorageStructIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStorageStructProbe" "ProofForge.IR.Examples.EvmStorageStructProbe" ProofForge.IR.Examples.EvmStorageStructProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmTypedMapIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedMapProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmTypedMapIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedMapProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmTypedMapIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.yul")
  let yul ← renderEvmTypedMapIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmTypedMapProbe" "ProofForge.IR.Examples.EvmTypedMapProbe" ProofForge.IR.Examples.EvmTypedMapProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmTypedStorageIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedStorageProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmTypedStorageIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedStorageProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmTypedStorageIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.yul")
  let yul ← renderEvmTypedStorageIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmTypedStorageProbe" "ProofForge.IR.Examples.EvmTypedStorageProbe" ProofForge.IR.Examples.EvmTypedStorageProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmArrayValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmArrayValueIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmArrayValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.yul")
  let yul ← renderEvmArrayValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmArrayValueProbe" "ProofForge.IR.Examples.EvmArrayValueProbe" ProofForge.IR.Examples.EvmArrayValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStructArrayValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructArrayValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStructArrayValueIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructArrayValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStructArrayValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.yul")
  let yul ← renderEvmStructArrayValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStructArrayValueProbe" "ProofForge.IR.Examples.EvmStructArrayValueProbe" ProofForge.IR.Examples.EvmStructArrayValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStructValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructValueProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStructValueIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStructValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStructValueProbe.yul")
  let yul ← renderEvmStructValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStructValueProbe" "ProofForge.IR.Examples.EvmStructValueProbe" ProofForge.IR.Examples.EvmStructValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmAbiAggregateIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAbiAggregateProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmAbiAggregateIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAbiAggregateProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmAbiAggregateIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.yul")
  let yul ← renderEvmAbiAggregateIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmAbiAggregateProbe" "ProofForge.IR.Examples.EvmAbiAggregateProbe" ProofForge.IR.Examples.EvmAbiAggregateProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmDynamicAbiIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicAbiProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicAbiProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmDynamicAbiIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicAbiProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmDynamicAbiIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmDynamicAbiProbe.yul")
  let yul ← renderEvmDynamicAbiIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicAbiProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmDynamicAbiProbe" "ProofForge.IR.Examples.EvmDynamicAbiProbe" ProofForge.IR.Examples.EvmDynamicAbiProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmArrayAbiIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayAbiProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayAbiProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmArrayAbiIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayAbiProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmArrayAbiIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmArrayAbiProbe.yul")
  let yul ← renderEvmArrayAbiIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayAbiProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmArrayAbiProbe" "ProofForge.IR.Examples.EvmArrayAbiProbe" ProofForge.IR.Examples.EvmArrayAbiProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmDynamicArrayIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicArrayProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicArrayProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmDynamicArrayIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicArrayProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmDynamicArrayIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmDynamicArrayProbe.yul")
  let yul ← renderEvmDynamicArrayIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicArrayProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmDynamicArrayProbe" "ProofForge.IR.Examples.EvmDynamicArrayProbe" ProofForge.IR.Examples.EvmDynamicArrayProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmMemoryArrayIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMemoryArrayProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMemoryArrayProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmMemoryArrayIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMemoryArrayProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmMemoryArrayIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmMemoryArrayProbe.yul")
  let yul ← renderEvmMemoryArrayIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMemoryArrayProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmMemoryArrayProbe" "ProofForge.IR.Examples.EvmMemoryArrayProbe" ProofForge.IR.Examples.EvmMemoryArrayProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmPackedStorageIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmPackedStorageProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmPackedStorageProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmPackedStorageIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmPackedStorageProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmPackedStorageIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmPackedStorageProbe.yul")
  let yul ← renderEvmPackedStorageIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmPackedStorageProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmPackedStorageProbe" "ProofForge.IR.Examples.EvmPackedStorageProbe" ProofForge.IR.Examples.EvmPackedStorageProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmErrorsIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmErrorsProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmErrorsProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmErrorsIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmErrorsProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmErrorsIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmErrorsProbe.yul")
  let module := ProofForge.IR.Examples.EvmErrorsProbe.module
  let yul ← renderEvmErrorsIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmErrorsProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  let spec := ProofForge.Contract.ContractSpec.fromIR module
  writeEvmContractSdkArtifactMetadata opts "EvmErrorsProbe" {
    moduleName := "ProofForge.IR.Examples.EvmErrorsProbe"
    kind := "portable-ir"
    leanElaborated := false
  } spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmFallbackIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmFallbackProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmFallbackProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmFallbackIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmFallbackProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmFallbackIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmFallbackProbe.yul")
  let yul ← renderEvmFallbackIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmFallbackProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmFallbackProbe" "ProofForge.IR.Examples.EvmFallbackProbe" ProofForge.IR.Examples.EvmFallbackProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

end ProofForge.Cli
