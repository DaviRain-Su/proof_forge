import Lean.Util.Path
import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.Scenario
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Cli.Options
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

open System

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

namespace ProofForge.Cli

def loadQuintScenarioConfig (opts : CliOptions) : IO ProofForge.Backend.Quint.Scenario.Config := do
  match opts.scenario? with
  | none => return {}
  | some path =>
      let contents ← IO.FS.readFile path
      match ProofForge.Backend.Quint.Scenario.parse contents with
      | .ok cfg => return cfg
      | .error msg => throw <| IO.userError s!"failed to parse scenario {path}: {msg}"

def compileIrQuintModule (opts : CliOptions) (module : ProofForge.IR.Module) (defaultOutput : String)
    (contractInvariants : Array (String × String) := #[])
    (contractLiveness : Array (String × String) := #[]) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk defaultOutput)
  let scenario ← loadQuintScenarioConfig opts
  let scenario := {
    scenario with
      contractInvariants := contractInvariants
      contractLiveness := contractLiveness
  }
  match ProofForge.Backend.Quint.Lower.renderModule module scenario with
  | .ok source =>
      match output.parent with
      | some parent => IO.FS.createDirAll parent
      | none => pure ()
      IO.FS.writeFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

def compileCounterIrQuint (opts : CliOptions) : IO UInt32 :=
  compileIrQuintModule opts ProofForge.IR.Examples.Counter.module "build/quint/Counter.qnt"
    ProofForge.Contract.Examples.Counter.spec.quintInvariants
    ProofForge.Contract.Examples.Counter.spec.quintLiveness

def compileValueVaultIrQuint (opts : CliOptions) : IO UInt32 :=
  compileIrQuintModule opts ProofForge.IR.Examples.ValueVault.module "build/quint/ValueVault.qnt"
    ProofForge.Contract.Examples.ValueVault.spec.quintInvariants
    ProofForge.Contract.Examples.ValueVault.spec.quintLiveness

def compileIrQuint (opts : CliOptions) : IO UInt32 := do
  let fixture ← match opts.fixture? with
    | some f => pure f
    | none => throw <| IO.userError "missing --fixture for --emit-ir-quint"
  let module ← match ProofForge.Cli.Quint.fixtureModule? fixture with
    | some m => pure m
    | none => throw <| IO.userError s!"unknown or unsupported Quint fixture `{fixture}`"
  compileIrQuintModule opts module (ProofForge.Cli.Quint.defaultOutputPath fixture)

def compileIrQuintScenario (opts : CliOptions) : IO UInt32 := do
  let fixture ← match opts.fixture? with
    | some f => pure f
    | none => throw <| IO.userError "missing --fixture for --emit-ir-quint-scenario"
  if !ProofForge.Cli.Quint.supportsFixture fixture then
    throw <| IO.userError s!"unknown or unsupported Quint fixture `{fixture}`"
  let output := opts.output?.getD (FilePath.mk (ProofForge.Cli.Quint.defaultScenarioOutputPath fixture))
  let cfg := ProofForge.Cli.Quint.scenarioConfigForEmit fixture
  let source := ProofForge.Backend.Quint.Scenario.renderToml fixture cfg
  match output.parent with
  | some parent => IO.FS.createDirAll parent
  | none => pure ()
  IO.FS.writeFile output source
  IO.println s!"wrote {output}"
  return 0

end ProofForge.Cli
