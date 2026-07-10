import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract
import ProofForge.IR.Examples.ArithmeticProbe
import ProofForge.IR.Examples.BitwiseProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.U32ArithmeticProbe
import ProofForge.IR.Examples.U32StorageScalarProbe
import ProofForge.IR.Examples.BoolStorageScalarProbe

/-! Aleo/Leo coverage breadth: existing IR probes lower through the generic
backend.

Beyond the dedicated Counter/PureMath/map/context/record smokes, this gate runs
a batch of pre-existing IR example probes (each exercising a different portable
feature) through `renderModule`. The four pure arithmetic/bitwise/assertion
probes lower. Five stateful control-flow/struct/scalar-storage probes fail closed
because their caller-visible returns depend on Leo mapping reads that only exist
inside `final`. -/

namespace ProofForge.Tests.AleoLeoCoverageSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

/-- All probes in this list must lower to Leo without error. -/
def probes : Array (String × Module) := #[
  ("ArithmeticProbe", Examples.ArithmeticProbe.module),
  ("BitwiseProbe", Examples.BitwiseProbe.module),
  ("AssertProbe", Examples.AssertProbe.module),
  ("U32ArithmeticProbe", Examples.U32ArithmeticProbe.module)
]

def allProbesLower : Bool :=
  probes.all fun (_, m) => match renderModule m with | .ok _ => true | .error _ => false

theorem all_probes_lower : allProbesLower = true := by native_decide

/-- Each probe's output is a well-formed Leo program header. -/
def allProbesEmitProgram : Bool :=
  probes.all fun (_name, m) =>
    match renderModule m with
    | .ok s => s.contains "program " && s.contains ".aleo {"
    | .error _ => false

theorem all_probes_emit_program : allProbesEmitProgram = true := by native_decide

/-- Leo 4.0.2 cannot surface mapping-derived caller returns. -/
def unsupportedStatefulProbesReject : Bool :=
  [ Examples.ConditionalProbe.module,
    Examples.LoopProbe.module,
    Examples.StructProbe.module,
    Examples.U32StorageScalarProbe.module,
    Examples.BoolStorageScalarProbe.module ].all fun module =>
    match renderModule module with
    | .error _ => true
    | .ok _ => false

theorem unsupported_stateful_probes_reject : unsupportedStatefulProbesReject = true := by native_decide

example : True := by
  have _ := @all_probes_lower
  have _ := @all_probes_emit_program
  have _ := @unsupported_stateful_probes_reject
  exact True.intro

end ProofForge.Tests.AleoLeoCoverageSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-coverage-smoke: 4 probes lower; 5 unsupported stateful shapes reject"
  return 0
