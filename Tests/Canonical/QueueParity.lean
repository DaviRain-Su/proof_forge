import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Collections.Queue

/-! # Queue Parity Test

Checks that Queue enqueue/dequeue/length reference semantics produce
correct results for the initial fragment.
-/

open ProofForge.Frontend.Surface

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def emptyState : SurfaceRuntimeState := { storage := {}, events := #[] }

def queueContract : SurfaceContract := {
  name := "BoundedQueue",
  structs := #[],
  state := #[
    { name := "$surface.queue.0.items", kind := .fixedArray .u64 10 },
    { name := "$surface.queue.0.head", kind := .scalar .u64 },
    { name := "$surface.queue.0.length", kind := .scalar .u64 }
  ],
  events := #[],
  errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "$surface.queue.0.head" (.literal (.u64Lit 0)),
        .stateWrite "$surface.queue.0.length" (.literal (.u64Lit 0))
      ]
    },
    { name := "enqueue", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "$surface.queue.0.length"
          (.arith .add true
            (.stateRead "$surface.queue.0.length")
            (.literal (.u64Lit 1)))
      ]
    },
    { name := "dequeue", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "$surface.queue.0.length"
          (.arith .sub true
            (.stateRead "$surface.queue.0.length")
            (.literal (.u64Lit 1))),
        .stateWrite "$surface.queue.0.head"
          (.arith .mod true
            (.arith .add true
              (.stateRead "$surface.queue.0.head")
              (.literal (.u64Lit 1)))
            (.literal (.u64Lit 10)))
      ]
    },
    { name := "getLength", kind := .function, mutability := .view,
      params := #[], retType := .u64,
      body := #[
        .returnExpr (.stateRead "$surface.queue.0.length")
      ]
    }
  ],
  constructorParams := #[],
  constructorBindings := #[],
  intents := #[]
}

def main : IO Unit := do
  /- Initialize: length = 0, head = 0. -/
  let st0 ← match runEntrypoint queueContract "initialize" #[] emptyState with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"initialize failed: {e}"
  require (st0.storage.get? "$surface.queue.0.length" == some 0)
    "initialize should set length to 0"
  require (st0.storage.get? "$surface.queue.0.head" == some 0)
    "initialize should set head to 0"

  /- Enqueue: length 0 → 1. -/
  let st1 ← match runEntrypoint queueContract "enqueue" #[] st0 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"enqueue failed: {e}"
  require (st1.storage.get? "$surface.queue.0.length" == some 1)
    "enqueue should set length to 1"

  /- Enqueue again: length 1 → 2. -/
  let st2 ← match runEntrypoint queueContract "enqueue" #[] st1 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"enqueue 2 failed: {e}"
  require (st2.storage.get? "$surface.queue.0.length" == some 2)
    "second enqueue should set length to 2"

  /- Dequeue: length 2 → 1, head wraps. -/
  let st3 ← match runEntrypoint queueContract "dequeue" #[] st2 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"dequeue failed: {e}"
  require (st3.storage.get? "$surface.queue.0.length" == some 1)
    "dequeue should set length to 1"
  require (st3.storage.get? "$surface.queue.0.head" == some 1)
    "dequeue should set head to 1"

  /- GetLength: returns 1. -/
  let getResult ← match runEntrypoint queueContract "getLength" #[] st3 with
    | Except.ok st => pure st
    | Except.error e => throw <| IO.userError s!"getLength failed: {e}"
  require (getResult.returnValue == some 1)
    "getLength should return 1"

  IO.println "queue-parity: ok"