import ProofForge.IR.Contract
import TestFixtures.Legacy.Core
import ProofForge.IR.Core.Error
import TestFixtures.Legacy.Elaborate
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

namespace TestFixtures.Legacy.ElaborateSmoke

open ProofForge.IR
open TestFixtures.Legacy.Core
open TestFixtures.Legacy.Elaborate
open ProofForge.IR.Core.Error

/-- Round-trip smoke for the Counter surface → Core elaboration path. -/
def counterElaborationSmoke : Except ElabError CoreModule :=
  elaborateModule ProofForge.IR.Examples.Counter.module

/-- Round-trip smoke for the ValueVault surface → Core elaboration path.
Exercises `contextRead` in expression position and multi-slot scalar storage. -/
def valueVaultElaborationSmoke : Except ElabError CoreModule :=
  elaborateModule ProofForge.IR.Examples.ValueVault.module

/-- Run both elaboration smokes and print a summary. Returns `0` on success. -/
def smoke : IO UInt32 := do
  let mut failures : List String := []
  match counterElaborationSmoke with
  | .error e => failures := ("Counter: " ++ reprStr e) :: failures
  | .ok core =>
    IO.println s!"Counter elaboration OK: {core.name} ({core.state.length} state vars, {core.entrypoints.length} entrypoints)"
  match valueVaultElaborationSmoke with
  | .error e => failures := ("ValueVault: " ++ reprStr e) :: failures
  | .ok core =>
    IO.println s!"ValueVault elaboration OK: {core.name} ({core.state.length} state vars, {core.entrypoints.length} entrypoints)"
  if failures.isEmpty then
    IO.println "TestFixtures.Legacy.ElaborateSmoke OK"
    return (0 : UInt32)
  else
    for msg in failures do
      IO.println s!"FAIL: {msg}"
    return (1 : UInt32)

end TestFixtures.Legacy.ElaborateSmoke
