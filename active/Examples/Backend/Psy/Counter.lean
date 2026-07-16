import ProofForge.Runtime.Psy

open Lean.Psy

namespace Examples.Psy.Counter

def count : Storage.Var Felt := Storage.Var.ofSlot 0

def initCounter : IO Unit :=
  count.writeFelt 0

def increment : IO Unit := do
  let n ← count.readFelt
  count.writeFelt (n + 1)

def get : IO Felt :=
  count.readFelt

end Examples.Psy.Counter
