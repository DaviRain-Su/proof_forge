import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.WhileProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.AssertProbe

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
  "struct"
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
  | "struct" => "StructProbe.qnt"
  | _ => s!"{fixtureId}.qnt"

def defaultOutputPath (fixtureId : String) : String :=
  s!"build/quint/{outputFileName fixtureId}"

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
  | "struct" => some ProofForge.IR.Examples.StructProbe.emitWatStorageModule
  | "assert" => some ProofForge.IR.Examples.AssertProbe.module
  | _ => none

end ProofForge.Cli.Quint