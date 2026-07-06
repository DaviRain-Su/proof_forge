import Lean.Util.Path
import ProofForge.Backend.Psy.IR
import ProofForge.Cli.FileUtil
import ProofForge.Cli.Options
import ProofForge.IR.Examples.AbiAggregateProbe
import ProofForge.IR.Examples.ArithmeticProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.BitwiseProbe
import ProofForge.IR.Examples.BoolStorageArrayProbe
import ProofForge.IR.Examples.BoolStorageScalarProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.IR.Examples.ElseIfProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.ExpressionPredicateProbe
import ProofForge.IR.Examples.GenericEntrypointProbe
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.HashStorageProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.NestedAggregateProbe
import ProofForge.IR.Examples.StorageNestedAggregateProbe
import ProofForge.IR.Examples.StructArrayProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.U32ArithmeticProbe
import ProofForge.IR.Examples.U32HashPackingProbe
import ProofForge.IR.Examples.U32StorageArrayProbe
import ProofForge.IR.Examples.U32StorageScalarProbe

open System

namespace ProofForge.Cli

def compileCounterIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/Counter.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileEventIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/EventProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.EventProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileCrosscallIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/CrosscallProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.CrosscallProbe.psyModule with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileExpressionPredicateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ExpressionPredicateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ExpressionPredicateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileGenericEntrypointIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/GenericEntrypointProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.GenericEntrypointProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileArithmeticIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ArithmeticProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ArithmeticProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBitwiseIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BitwiseProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BitwiseProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBoolStorageArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BoolStorageArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BoolStorageArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBoolStorageScalarIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BoolStorageScalarProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BoolStorageScalarProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileConditionalIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ConditionalProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileElseIfIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ElseIfProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ElseIfProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileContextIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ContextProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ContextProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/HashProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.HashProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashStorageIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/HashStorageProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.HashStorageProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileMapIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/MapProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.MapProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileAssertIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/AssertProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.AssertProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileLoopIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/LoopProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.LoopProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStructIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StructProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StructProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStructArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StructArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StructArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileAbiAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/AbiAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.AbiAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileNestedAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/NestedAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.NestedAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStorageNestedAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StorageNestedAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StorageNestedAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32ArithmeticIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32ArithmeticProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32ArithmeticProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32HashPackingIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32HashPackingProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32HashPackingProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32StorageScalarIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32StorageScalarProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32StorageScalarProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32StorageArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32StorageArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32StorageArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render
end ProofForge.Cli
