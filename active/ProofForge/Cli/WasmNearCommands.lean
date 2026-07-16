import Lean.Util.Path
import ProofForge.Backend.WasmHost
import ProofForge.Cli.EmitWatArtifacts
import ProofForge.Cli.Options
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.MapProbe

open System

namespace ProofForge.Cli

def compileCounterIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmHost.IR.renderPackage ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near Counter package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileContextIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmHost.IR.renderPackage ProofForge.IR.Examples.ContextProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near ContextProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmHost.IR.renderPackage ProofForge.IR.Examples.HashProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near HashProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileMapIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmHost.IR.renderPackage ProofForge.IR.Examples.MapProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near MapProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

end ProofForge.Cli
