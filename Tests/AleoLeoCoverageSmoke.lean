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
feature) through `renderModule` to prove the generic lowering handles a broad IR
subset — arithmetic, bitwise, assertions, conditionals, bounded loops, structs,
U32 arithmetic, and U64/U32/Bool scalar storage (rewritten to single-slot Leo
mappings). Probes that use features Aleo honestly rejects (hash, events,
crosscall, memory/dynamic arrays, while loops) are intentionally not listed. -/

namespace ProofForge.Tests.AleoLeoCoverageSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

/-- All probes in this list must lower to Leo without error. -/
def probes : Array (String × Module) := #[
  ("ArithmeticProbe", Examples.ArithmeticProbe.module),
  ("BitwiseProbe", Examples.BitwiseProbe.module),
  ("AssertProbe", Examples.AssertProbe.module),
  ("ConditionalProbe", Examples.ConditionalProbe.module),
  ("LoopProbe", Examples.LoopProbe.module),
  ("StructProbe", Examples.StructProbe.module),
  ("U32ArithmeticProbe", Examples.U32ArithmeticProbe.module),
  ("U32StorageScalarProbe", Examples.U32StorageScalarProbe.module),
  ("BoolStorageScalarProbe", Examples.BoolStorageScalarProbe.module)
]

def allProbesLower : Bool :=
  probes.all fun (_, m) => match renderModule m with | .ok _ => true | .error _ => false

theorem all_probes_lower : allProbesLower = true := by native_decide

/-- Each probe's output is a well-formed Leo program header. -/
def allProbesEmitProgram : Bool :=
  probes.all fun (name, m) =>
    match renderModule m with
    | .ok s => s.contains "program " && s.contains ".aleo {"
    | .error _ => false

theorem all_probes_emit_program : allProbesEmitProgram = true := by native_decide

example : True := by
  have _ := @all_probes_lower
  have _ := @all_probes_emit_program
  exact True.intro

end ProofForge.Tests.AleoLeoCoverageSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-coverage-smoke: 9 IR probes lower through the generic backend"
  return 0
