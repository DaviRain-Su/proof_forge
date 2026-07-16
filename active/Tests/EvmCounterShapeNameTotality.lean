import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Refinement.Core

/-! PF-P3-01 computational free-name totality smoke.

Machine-checks that `lowerModule (counterShapeModule n)` succeeds for a dense
set of names (including empty/short/renamed). Complements the formal finite
family theorems; general `∀ String` remains the lowerer name-independence
obligation.
-/

open ProofForge.Backend.Refinement
open ProofForge.Backend.Evm.IR

def checkName (n : String) : IO Bool := do
  match lowerModule (counterShapeModule n) with
  | .ok _ => pure true
  | .error e =>
      IO.eprintln s!"counterShapeModule name={n.quote} failed: {e.message}"
      pure false

def main : IO UInt32 := do
  let names := #[
    "Counter", "CounterRenamed", "C", "shape", "VaultCounter",
    "", "a", "Foo", "Vault2", "m", "x", "y", "z", "0", "test",
    "MyCounter", "app", "n", "lib", "core"
  ]
  let mut ok := true
  for n in names do
    unless (← checkName n) do
      ok := false
  if ok then
    IO.println s!"evm-counter-shape-name-totality: ok ({names.size} names)"
    return 0
  else
    IO.println "evm-counter-shape-name-totality: FAIL"
    return 1
