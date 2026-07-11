import ProofForge.Frontend.Surface
import ProofForge.IR.Core.Semantics
import Examples.Product.Canonical.BoundedQueue

/-! Task 16 FIFO, wrap-around, and structured-error parity for bounded queues. -/

open ProofForge.Frontend.Surface
open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

def queue := Examples.Product.Canonical.BoundedQueue.queue
def queueContract := Examples.Product.Canonical.BoundedQueue.contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def host : HostSemantics where
  handle call _ _ := .error (.unknownHostOp call.id)
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def surfaceEmpty : SurfaceRuntimeState := { storage := {}, arrays := {}, events := #[] }
def coreEmpty : LogicalState := { storage := fun _ => none }

def secondQueue : SurfaceQueueDecl := { id := 1, elementType := .u64, capacity := 2 }

def isolatedQueues : SurfaceContract := {
  name := "IsolatedQueues", structs := #[],
  state := queue.expand ++ secondQueue.expand, events := #[],
  errors := #[{ name := "QueueFull", message := "queue full", params := #[] }],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit, body := #[
        .stateWrite queue.headName (.literal (.u64Lit 0)),
        .stateWrite queue.lengthName (.literal (.u64Lit 0)),
        .stateWrite secondQueue.headName (.literal (.u64Lit 0)),
        .stateWrite secondQueue.lengthName (.literal (.u64Lit 0))] },
    { name := "enqueueFirst", kind := .function, mutability := .call,
      params := #[{ name := "value", type := .u64 }], retType := .unit,
      body := queue.enqueueStmts (.local "value") },
    { name := "enqueueSecond", kind := .function, mutability := .call,
      params := #[{ name := "value", type := .u64 }], retType := .unit,
      body := secondQueue.enqueueStmts (.local "value") }],
  constructorParams := #[], constructorBindings := #[]
}

def coreScalar (state : LogicalState) (id : Nat) : Option Nat :=
  match state.storage ⟨id⟩ with
  | some (.scalar (.u64 value)) => some value.toNat
  | _ => none

def coreItems (state : LogicalState) : Array Nat :=
  match state.storage ⟨0⟩ with
  | some (.fixedArray .u64 entries) => entries.map fun value =>
      match value with | .u64 n => n.toNat | _ => 0
  | _ => #[0, 0, 0]

def runStep (bundle : ProofForge.IR.Canonical.CanonicalBundle)
    (name : String) (id : Nat) (args : Array Nat)
    (surfaceState : SurfaceRuntimeState) (coreState : LogicalState) :
    IO (SurfaceRuntimeState × LogicalState × CoreValue) := do
  let surface ← match runEntrypoint queueContract name args surfaceState with
    | .ok state => pure state
    | .error e => throw <| IO.userError s!"Surface {name}: {e}"
  let core ← match execute host 200 bundle.contract ⟨id⟩
      (args.map fun value => .u64 value.toUInt64) coreState with
    | .ok result => pure result
    | .error e => throw <| IO.userError s!"Core {name}: {repr e}"
  require (!surface.reverted) s!"Surface {name} unexpectedly reverted"
  require (surface.storage.get? queue.headName == coreScalar core.finalState 1)
    s!"head mismatch after {name}"
  require (surface.storage.get? queue.lengthName == coreScalar core.finalState 2)
    s!"length mismatch after {name}"
  require (surface.arrays.get? queue.itemsName == some (coreItems core.finalState))
    s!"items mismatch after {name}"
  return (surface, core.finalState, core.returnValue)

def main : IO Unit := do
  let bundle ← match normalizeSurface queueContract with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"normalize Queue: {repr e}"
  let (s0, c0, _) ← runStep bundle "initialize" 0 #[] surfaceEmpty coreEmpty
  let (s1, c1, _) ← runStep bundle "enqueue" 1 #[10] s0 c0
  let (s2, c2, _) ← runStep bundle "enqueue" 1 #[20] s1 c1
  let (peek1, cPeek, corePeek) ← runStep bundle "peek" 3 #[] s2 c2
  require (peek1.returnValue == some 10 && corePeek == .u64 10) "peek did not return FIFO head"
  let (s3, c3, first) ← runStep bundle "dequeue" 2 #[] peek1 cPeek
  require (s3.returnValue == some 10 && first == .u64 10) "first dequeue was not FIFO"
  let (s4, c4, _) ← runStep bundle "enqueue" 1 #[30] s3 c3
  let (s5, c5, _) ← runStep bundle "enqueue" 1 #[40] s4 c4
  require (s5.arrays.get? queue.itemsName == some #[40, 20, 30]) "tail did not wrap"

  let surfaceFull ← match runEntrypoint queueContract "enqueue" #[50] s5 with
    | .ok state => pure state
    | .error e => throw <| IO.userError e
  require (surfaceFull.reverted && surfaceFull.error == some "QueueFull")
    "Surface QueueFull was not structured"
  match execute host 200 bundle.contract ⟨1⟩ #[.u64 50] c5 with
  | .error (.assertionFailure error) => require (error.id.value == 0) "Core QueueFull id"
  | result => throw <| IO.userError s!"Core full enqueue did not fail: {repr result}"

  let (s6, c6, second) ← runStep bundle "dequeue" 2 #[] s5 c5
  let (s7, c7, third) ← runStep bundle "dequeue" 2 #[] s6 c6
  let (s8, c8, fourth) ← runStep bundle "dequeue" 2 #[] s7 c7
  require (second == .u64 20 && third == .u64 30 && fourth == .u64 40)
    "wrapped queue violated FIFO order"
  let surfaceEmptyError ← match runEntrypoint queueContract "dequeue" #[] s8 with
    | .ok state => pure state
    | .error e => throw <| IO.userError e
  require (surfaceEmptyError.reverted && surfaceEmptyError.error == some "QueueEmpty")
    "Surface QueueEmpty was not structured"
  match execute host 200 bundle.contract ⟨2⟩ #[] c8 with
  | .error (.assertionFailure error) => require (error.id.value == 1) "Core QueueEmpty id"
  | result => throw <| IO.userError s!"Core empty dequeue did not fail: {repr result}"

  let isolatedInit ← match runEntrypoint isolatedQueues "initialize" #[] surfaceEmpty with
    | .ok state => pure state
    | .error e => throw <| IO.userError s!"isolated initialize: {e}"
  let isolated0 ← match runEntrypoint isolatedQueues "enqueueFirst" #[7] isolatedInit with
    | .ok state => pure state
    | .error e => throw <| IO.userError s!"first isolated queue: {e}"
  let isolated1 ← match runEntrypoint isolatedQueues "enqueueSecond" #[9] isolated0 with
    | .ok state => pure state
    | .error e => throw <| IO.userError s!"second isolated queue: {e}"
  require (isolated1.arrays.get? queue.itemsName == some #[7, 0, 0])
    "second Queue mutated first Queue items"
  require (isolated1.arrays.get? secondQueue.itemsName == some #[9, 0])
    "first Queue aliased second Queue items"
  require (isolated1.storage.get? queue.lengthName == some 1 &&
    isolated1.storage.get? secondQueue.lengthName == some 1)
    "Queue length states were not isolated"
  IO.println "queue-parity: ok"
