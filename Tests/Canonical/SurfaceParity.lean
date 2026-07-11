import ProofForge.Frontend.Surface
import ProofForge.IR.Core.Semantics

/-! # Surface Parity Test

Executes Surface reference semantics for Counter initialize/increment/get
and compares results. The initial fragment covers scalar state read/write,
arithmetic, and return.
-/

open ProofForge.Frontend.Surface

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A minimal Surface Counter contract for semantics testing. -/
def surfaceCounter : SurfaceContract := {
  name := "Counter"
  structs := #[]
  state := #[{ name := "count", kind := .scalar .u64 }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count" (.literal (.u64Lit 0))
      ]
    },
    { name := "increment", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count"
          (.arith .add true
            (.stateRead "count")
            (.literal (.u64Lit 1)))
      ]
    },
    { name := "get", kind := .function, mutability := .view,
      params := #[], retType := .u64,
      body := #[
        .returnExpr (.stateRead "count")
      ]
    }
  ]
  constructorParams := #[]
  constructorBindings := #[]
  intents := #[]
}

def emptyState : SurfaceRuntimeState := { storage := {}, events := #[] }

def main : IO Unit := do
  /- Initialize: sets count to 0. -/
  let initResult ← match runEntrypoint surfaceCounter "initialize" #[] emptyState with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"initialize failed: {e}"
  require (initResult.storage.get? "count" == some 0)
    "initialize should set count to 0"
  require (!initResult.reverted) "initialize should not revert"

  /- Increment from 0 → 1. -/
  let incResult ← match runEntrypoint surfaceCounter "increment" #[] initResult with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"increment failed: {e}"
  require (incResult.storage.get? "count" == some 1)
    "increment should set count to 1"
  require (!incResult.reverted) "increment should not revert"

  /- Get: returns 1. -/
  let getResult ← match runEntrypoint surfaceCounter "get" #[] incResult with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"get failed: {e}"
  require (getResult.returnValue == some 1)
    "get should return 1"

  /- Two increments from 0 → 2. -/
  let st1 ← match runEntrypoint surfaceCounter "initialize" #[] emptyState with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"initialize failed: {e}"
  let st2 ← match runEntrypoint surfaceCounter "increment" #[] st1 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"increment 1 failed: {e}"
  let st3 ← match runEntrypoint surfaceCounter "increment" #[] st2 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"increment 2 failed: {e}"
  require (st3.storage.get? "count" == some 2)
    "two increments should set count to 2"

  IO.println "surface-parity: ok"