import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Scenario
import ProofForge.Contract.Examples.Counter
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.WhileProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.AssignmentProbe
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.IR.Examples.StorageNestedAggregateProbe
import ProofForge.IR.Examples.UnboundedIntProbe

namespace ProofForge.Cli.Quint

/-- Portable IR fixtures with Quint lowering + gate coverage in this repo. -/
def supportedFixtureIds : Array String := #[
  "counter",
  "value-vault",
  "conditional",
  "loop",
  "while",
  "array",
  "map",
  "map-path",
  "struct",
  "array-path",
  "struct-path",
  "map-nested-path",
  "map-triple-path",
  "map-nested-dynamic-path",
  "map-path-assign",
  "map-hash-path-assign",
  "struct-dynamic-path",
  "nested-struct-ref",
  "assignment",
  "crosscall",
  "assert",
  "unbounded-int"
]

def supportsFixture (fixtureId : String) : Bool :=
  supportedFixtureIds.contains fixtureId

def outputFileName (fixtureId : String) : String :=
  match fixtureId with
  | "counter" => "Counter.qnt"
  | "value-vault" => "ValueVault.qnt"
  | "conditional" => "ConditionalProbe.qnt"
  | "loop" => "LoopProbe.qnt"
  | "while" => "WhileProbe.qnt"
  | "array" => "ArrayProbe.qnt"
  | "map" => "MapProbe.qnt"
  | "map-path" => "MapPathProbe.qnt"
  | "struct" => "StructProbe.qnt"
  | "array-path" => "ArrayPathProbe.qnt"
  | "struct-path" => "StructPathProbe.qnt"
  | "map-nested-path" => "MapNestedPathProbe.qnt"
  | "map-triple-path" => "MapTriplePathProbe.qnt"
  | "map-nested-dynamic-path" => "MapNestedDynamicPathProbe.qnt"
  | "map-path-assign" => "MapPathAssignProbe.qnt"
  | "map-hash-path-assign" => "MapHashPathAssignProbe.qnt"
  | "struct-dynamic-path" => "StructDynamicPathProbe.qnt"
  | "nested-struct-ref" => "NestedStructRefProbe.qnt"
  | "assignment" => "AssignmentProbe.qnt"
  | "crosscall" => "CrosscallProbe.qnt"
  | "assert" => "AssertProbe.qnt"
  | "unbounded-int" => "UnboundedIntProbe.qnt"
  | _ => s!"{fixtureId}.qnt"

def defaultOutputPath (fixtureId : String) : String :=
  s!"build/quint/{outputFileName fixtureId}"

def scenarioFileName (fixtureId : String) : String :=
  match fixtureId with
  | "counter" => "Counter.scenario.toml"
  | "value-vault" => "ValueVault.scenario.toml"
  | _ =>
      let qnt := outputFileName fixtureId
      if qnt.endsWith ".qnt" then String.Slice.toString (qnt.dropEnd 4) ++ ".scenario.toml"
      else s!"{fixtureId}.scenario.toml"

def defaultScenarioOutputPath (fixtureId : String) : String :=
  s!"build/quint/{scenarioFileName fixtureId}"

/-- Scenario bounds for `emit --format scenario`, including contract liveness when known. -/
def scenarioConfigForEmit (fixtureId : String) : ProofForge.Backend.Quint.Scenario.Config :=
  let base := ProofForge.Backend.Quint.Scenario.defaultForFixture fixtureId
  match fixtureId with
  | "counter" =>
      { base with liveness := ProofForge.Contract.Examples.Counter.spec.quintLiveness }
  | _ => base

/-- Map a fixture id to the IR module lowered into Quint. -/
def fixtureModule? (fixtureId : String) : Option ProofForge.IR.Module :=
  match fixtureId with
  | "counter" => some ProofForge.IR.Examples.Counter.module
  | "value-vault" => some ProofForge.IR.Examples.ValueVault.module
  | "conditional" => some ProofForge.IR.Examples.ConditionalProbe.module
  | "loop" => some ProofForge.IR.Examples.LoopProbe.module
  | "while" => some ProofForge.IR.Examples.WhileProbe.module
  | "array" => some ProofForge.IR.Examples.ArrayProbe.emitWatStorageModule
  | "map" => some ProofForge.IR.Examples.MapProbe.emitQuintStorageModule
  | "map-path" => some ProofForge.IR.Examples.MapProbe.emitQuintPathModule
  | "struct" => some ProofForge.IR.Examples.StructProbe.emitWatStorageModule
  | "array-path" => some ProofForge.IR.Examples.EvmStorageArrayProbe.emitQuintPathModule
  | "struct-path" => some ProofForge.IR.Examples.EvmStorageStructProbe.emitQuintPathModule
  | "map-nested-path" => some ProofForge.IR.Examples.MapProbe.emitQuintNestedPathModule
  | "map-triple-path" => some ProofForge.IR.Examples.MapProbe.emitQuintTriplePathModule
  | "map-nested-dynamic-path" => some ProofForge.IR.Examples.MapProbe.emitQuintNestedDynamicPathModule
  | "map-path-assign" => some ProofForge.IR.Examples.MapProbe.emitQuintPathAssignModule
  | "map-hash-path-assign" => some ProofForge.IR.Examples.MapProbe.emitQuintHashPathAssignModule
  | "struct-dynamic-path" => some ProofForge.IR.Examples.EvmStorageStructProbe.emitQuintDynamicStructPathModule
  | "nested-struct-ref" => some ProofForge.IR.Examples.StorageNestedAggregateProbe.emitQuintNestedStructRefModule
  | "assignment" => some ProofForge.IR.Examples.AssignmentProbe.module
  | "crosscall" => some ProofForge.IR.Examples.CrosscallProbe.module
  | "assert" => some ProofForge.IR.Examples.AssertProbe.module
  | "unbounded-int" => some ProofForge.IR.Examples.UnboundedIntProbe.module
  | _ => none

end ProofForge.Cli.Quint