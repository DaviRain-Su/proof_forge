import ProofForge.Backend.Psy.Metadata
import ProofForge.Backend.Psy.MetadataJson
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

namespace ProofForge.Tests.PsyMetadataExport

open ProofForge.Backend.Psy.Metadata
open ProofForge.Backend.Psy.MetadataJson
open ProofForge.Backend.Psy.Plan (PlanError)
open ProofForge.IR

def moduleByName (name : String) : Option Module :=
  match name with
  | "Counter" => some Examples.Counter.module
  | "MapProbe" => some Examples.MapProbe.module
  | "EventProbe" => some Examples.EventProbe.module
  | "ContextProbe" => some Examples.ContextProbe.module
  | "CrosscallProbe" => some Examples.CrosscallProbe.module
  | "StructProbe" => some Examples.StructProbe.module
  | "StructArrayProbe" => some Examples.StructArrayProbe.module
  | "ArrayProbe" => some Examples.ArrayProbe.module
  | "AssertProbe" => some Examples.AssertProbe.module
  | "HashProbe" => some Examples.HashProbe.module
  | "HashStorageProbe" => some Examples.HashStorageProbe.module
  | "LoopProbe" => some Examples.LoopProbe.module
  | "ArithmeticProbe" => some Examples.ArithmeticProbe.module
  | "BitwiseProbe" => some Examples.BitwiseProbe.module
  | "ConditionalProbe" => some Examples.ConditionalProbe.module
  | "ElseIfProbe" => some Examples.ElseIfProbe.module
  | "ExpressionPredicateProbe" => some Examples.ExpressionPredicateProbe.module
  | "GenericEntrypointProbe" => some Examples.GenericEntrypointProbe.module
  | "AbiAggregateProbe" => some Examples.AbiAggregateProbe.module
  | "NestedAggregateProbe" => some Examples.NestedAggregateProbe.module
  | "StorageNestedAggregateProbe" => some Examples.StorageNestedAggregateProbe.module
  | "U32ArithmeticProbe" => some Examples.U32ArithmeticProbe.module
  | "U32HashPackingProbe" => some Examples.U32HashPackingProbe.module
  | "U32StorageArrayProbe" => some Examples.U32StorageArrayProbe.module
  | "U32StorageScalarProbe" => some Examples.U32StorageScalarProbe.module
  | "BoolStorageArrayProbe" => some Examples.BoolStorageArrayProbe.module
  | "BoolStorageScalarProbe" => some Examples.BoolStorageScalarProbe.module
  | _ => none

def main (args : List String) : IO UInt32 :=
  match args with
  | [name] =>
      match moduleByName name with
      | some module =>
          match buildPlanArtifactMetadata module with
          | .ok m => do
              IO.println (renderArtifactMetadata m)
              pure 0
          | .error e => do
              IO.eprintln s!"failed to build metadata for {name}: {PlanError.render e}"
              pure 1
      | none => do
          IO.eprintln s!"unknown fixture: {name}"
          pure 1
  | _ => do
      IO.eprintln "usage: PsyMetadataExport <fixture-name>"
      pure 1

end ProofForge.Tests.PsyMetadataExport

def main (args : List String) : IO UInt32 :=
  ProofForge.Tests.PsyMetadataExport.main args