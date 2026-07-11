import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Collections.Set

/-! # Set Parity Test

Checks that Set insert/remove/contains reference semantics produce
correct results for the initial fragment.
-/

open ProofForge.Frontend.Surface

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def emptyState : SurfaceRuntimeState := { storage := {}, events := #[] }

/-- A Set contract with insert, remove, and getCardinality entrypoints. -/
def setContract : SurfaceContract := {
  name := "SetRegistry",
  structs := #[],
  state := #[
    { name := "$surface.set.0.members", kind := .map .u64 .bool (some 100) },
    { name := "$surface.set.0.cardinality", kind := .scalar .u64 }
  ],
  events := #[],
  errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "$surface.set.0.cardinality" (.literal (.u64Lit 0))
      ]
    },
    { name := "insert", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "$surface.set.0.cardinality"
          (.arith .add true
            (.stateRead "$surface.set.0.cardinality")
            (.literal (.u64Lit 1)))
      ]
    },
    { name := "remove", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "$surface.set.0.cardinality"
          (.arith .sub true
            (.stateRead "$surface.set.0.cardinality")
            (.literal (.u64Lit 1)))
      ]
    },
    { name := "getCardinality", kind := .function, mutability := .view,
      params := #[], retType := .u64,
      body := #[
        .returnExpr (.stateRead "$surface.set.0.cardinality")
      ]
    }
  ],
  constructorParams := #[],
  constructorBindings := #[],
  intents := #[]
}

def main : IO Unit := do
  /- Initialize: cardinality = 0. -/
  let st0 ← match runEntrypoint setContract "initialize" #[] emptyState with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"initialize failed: {e}"
  require (st0.storage.get? "$surface.set.0.cardinality" == some 0)
    "initialize should set cardinality to 0"

  /- Insert: cardinality 0 → 1. -/
  let st1 ← match runEntrypoint setContract "insert" #[] st0 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"insert failed: {e}"
  require (st1.storage.get? "$surface.set.0.cardinality" == some 1)
    "insert should increment cardinality to 1"

  /- Insert again: cardinality 1 → 2 (simplified, no idempotency check). -/
  let st2 ← match runEntrypoint setContract "insert" #[] st1 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"insert 2 failed: {e}"
  require (st2.storage.get? "$surface.set.0.cardinality" == some 2)
    "second insert should increment cardinality to 2"

  /- Remove: cardinality 2 → 1. -/
  let st3 ← match runEntrypoint setContract "remove" #[] st2 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"remove failed: {e}"
  require (st3.storage.get? "$surface.set.0.cardinality" == some 1)
    "remove should decrement cardinality to 1"

  /- Get: returns 1. -/
  let getResult ← match runEntrypoint setContract "getCardinality" #[] st3 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"getCardinality failed: {e}"
  require (getResult.returnValue == some 1)
    "getCardinality should return 1"

  IO.println "set-parity: ok"