import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Collections.Queue

/-! # Queue Normalize Test

Checks that Surface Queue declarations expand to Core state declarations
with the correct generated names and shapes.
-/

open ProofForge.Frontend.Surface

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def testQueue : SurfaceQueueDecl := { id := 0, elementType := .u64, capacity := 10 }

def queueContract : SurfaceContract := {
  name := "BoundedQueue",
  structs := #[],
  state := testQueue.expand.toList.toArray,
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
  /- Check 1: Queue expands to three state declarations. -/
  let expanded := testQueue.expand
  require (expanded.size == 3) "Queue should expand to 3 state declarations"
  require (expanded[0]!.name == "$surface.queue.0.items") "items name mismatch"
  require (expanded[1]!.name == "$surface.queue.0.head") "head name mismatch"
  require (expanded[2]!.name == "$surface.queue.0.length") "length name mismatch"

  /- Check 2: Capacity zero rejects. -/
  match SurfaceQueueDecl.validate { id := 1, elementType := .u64, capacity := 0 } with
  | Except.error _ => pure ()
  | Except.ok _ => throw <| IO.userError "Capacity zero should reject"

  /- Check 3: Valid capacity accepts. -/
  match SurfaceQueueDecl.validate testQueue with
  | Except.ok _ => pure ()
  | Except.error e => throw <| IO.userError s!"Valid queue should accept: {e}"

  /- Check 4: Contract with expanded queue state normalizes. -/
  match normalizeSurface queueContract with
  | Except.ok bundle =>
    require (bundle.contract.contract.module.state.size == 3)
      "Module should have 3 state declarations"
    require (bundle.contract.contract.module.functions.size == 2)
      "Module should have 2 functions"
  | Except.error e => throw <| IO.userError s!"Queue contract normalize failed: {repr e}"

  /- Check 5: Generated names use $surface.queue. prefix. -/
  require (testQueue.itemsName.startsWith "$surface.queue.") "items name should use $surface.queue. prefix"
  require (testQueue.headName.startsWith "$surface.queue.") "head name should use $surface.queue. prefix"
  require (testQueue.lengthName.startsWith "$surface.queue.") "length name should use $surface.queue. prefix"

  IO.println "queue-normalize: ok"