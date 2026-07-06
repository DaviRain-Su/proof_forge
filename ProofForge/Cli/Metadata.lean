import ProofForge.Backend.Psy.Metadata
import ProofForge.Backend.Psy.MetadataJson
import ProofForge.Cli.Options
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.StructArrayProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.HashStorageProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.ArithmeticProbe
import ProofForge.IR.Examples.BitwiseProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.ElseIfProbe
import ProofForge.IR.Examples.ExpressionPredicateProbe
import ProofForge.IR.Examples.GenericEntrypointProbe
import ProofForge.IR.Examples.AbiAggregateProbe
import ProofForge.IR.Examples.NestedAggregateProbe
import ProofForge.IR.Examples.StorageNestedAggregateProbe
import ProofForge.IR.Examples.U32ArithmeticProbe
import ProofForge.IR.Examples.U32HashPackingProbe
import ProofForge.IR.Examples.U32StorageArrayProbe
import ProofForge.IR.Examples.U32StorageScalarProbe
import ProofForge.IR.Examples.BoolStorageArrayProbe
import ProofForge.IR.Examples.BoolStorageScalarProbe

namespace ProofForge.Cli.Metadata

open ProofForge.Backend.Psy.Metadata
open ProofForge.Backend.Psy.Plan (PlanError)
open ProofForge.IR

structure MetadataOptions where
  targetId : String
  fixture : String
  output? : Option System.FilePath
  pretty : Bool
  deriving Repr

private def fixtureModule? (fixtureId : String) : Option Module :=
  match fixtureId with
  | "counter" => some Examples.Counter.module
  | "map" => some Examples.MapProbe.module
  | "event" => some Examples.EventProbe.module
  | "context" => some Examples.ContextProbe.module
  | "crosscall" => some Examples.CrosscallProbe.psyModule
  | "struct" => some Examples.StructProbe.module
  | "struct-array" => some Examples.StructArrayProbe.module
  | "array" => some Examples.ArrayProbe.module
  | "assert" => some Examples.AssertProbe.module
  | "hash" => some Examples.HashProbe.module
  | "hash-storage" => some Examples.HashStorageProbe.module
  | "loop" => some Examples.LoopProbe.module
  | "arithmetic" => some Examples.ArithmeticProbe.module
  | "bitwise" => some Examples.BitwiseProbe.module
  | "conditional" => some Examples.ConditionalProbe.module
  | "else-if" => some Examples.ElseIfProbe.module
  | "expression-predicate" => some Examples.ExpressionPredicateProbe.module
  | "generic-entrypoint" => some Examples.GenericEntrypointProbe.module
  | "abi-aggregate" => some Examples.AbiAggregateProbe.module
  | "nested-aggregate" => some Examples.NestedAggregateProbe.module
  | "storage-nested-aggregate" => some Examples.StorageNestedAggregateProbe.module
  | "u32-arithmetic" => some Examples.U32ArithmeticProbe.module
  | "u32-hash-packing" => some Examples.U32HashPackingProbe.module
  | "u32-storage-array" => some Examples.U32StorageArrayProbe.module
  | "u32-storage-scalar" => some Examples.U32StorageScalarProbe.module
  | "bool-storage-array" => some Examples.BoolStorageArrayProbe.module
  | "bool-storage-scalar" => some Examples.BoolStorageScalarProbe.module
  | _ => none

def parseMetadataOptions (args : List String) : Except String MetadataOptions := do
  let rec loop (args : List String) (acc : MetadataOptions) : Except String MetadataOptions :=
    match args with
    | [] =>
        if acc.fixture.isEmpty then
          .error "metadata requires --fixture <id>"
        else
          .ok acc
    | "--target" :: target :: rest => loop rest { acc with targetId := target }
    | "--fixture" :: fixture :: rest => loop rest { acc with fixture := fixture }
    | "-o" :: out :: rest | "--output" :: out :: rest => loop rest { acc with output? := some out }
    | "--pretty" :: rest => loop rest { acc with pretty := true }
    | flag :: _ => .error s!"unknown metadata flag: {flag}"
  loop args { targetId := "psy-dpn", fixture := "", output? := none, pretty := false }

def metadataOptionsFromCliOptions (opts : ProofForge.Cli.CliOptions) : Except String MetadataOptions := do
  let fixture ←
    match opts.fixture? with
    | some fixture => pure fixture
    | none => .error "metadata requires --fixture <id>"
  .ok {
    targetId := opts.targetId?.getD "psy-dpn"
    fixture
    output? := opts.output?
    pretty := false
  }

def metadataCommand (opts : MetadataOptions) : IO UInt32 := do
  if opts.targetId != "psy-dpn" then
    IO.eprintln s!"metadata command currently only supports --target psy-dpn, got {opts.targetId}"
    return 1
  let module ← match fixtureModule? opts.fixture with
    | some m => pure m
    | none => throw <| IO.userError s!"metadata: unknown fixture '{opts.fixture}'"
  let artifactMeta ← match buildPlanArtifactMetadata module with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"metadata: failed to build plan: {PlanError.render e}"
  let json :=
    if opts.pretty then
      ProofForge.Backend.Psy.MetadataJson.renderArtifactMetadataPretty artifactMeta
    else
      ProofForge.Backend.Psy.MetadataJson.renderArtifactMetadata artifactMeta
  match opts.output? with
  | some path =>
      if let some parent := path.parent then
        IO.FS.createDirAll parent
      IO.FS.writeFile path (json ++ "\n")
      IO.eprintln s!"metadata: wrote {path}"
  | none =>
      IO.println json
  pure 0

def metadataCommandFromCliOptions (opts : ProofForge.Cli.CliOptions) : IO UInt32 := do
  match metadataOptionsFromCliOptions opts with
  | .ok metadataOpts => metadataCommand metadataOpts
  | .error msg => throw <| IO.userError msg

end ProofForge.Cli.Metadata
