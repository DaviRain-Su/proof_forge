import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.BoundedQueue

def queue : SurfaceQueueDecl := { id := 0, elementType := .u64, capacity := 3 }

def contract : SurfaceContract := {
  name := "BoundedQueue", structs := #[], state := queue.expand, events := #[],
  errors := #[
    { name := "QueueFull", message := "queue full", params := #[] },
    { name := "QueueEmpty", message := "queue empty", params := #[] }],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c", params := #[], retType := .unit,
      body := #[
        .stateWrite queue.headName (.literal (.u64Lit 0)),
        .stateWrite queue.lengthName (.literal (.u64Lit 0))] },
    { name := "enqueue", kind := .function, mutability := .call,
      selector? := some "a2e62045", params := #[{ name := "value", type := .u64 }],
      retType := .unit, body := queue.enqueueStmts (.local "value") },
    { name := "dequeue", kind := .function, mutability := .call,
      selector? := some "2e17de78", params := #[], retType := .u64,
      body := queue.dequeueStmts },
    { name := "peek", kind := .function, mutability := .view,
      selector? := some "59e02dd7", params := #[], retType := .u64,
      body := queue.peekStmts },
    { name := "length", kind := .function, mutability := .view,
      selector? := some "1f7b6d32", params := #[], retType := .u64,
      body := #[.returnExpr queue.lengthExpr] }
  ], constructorParams := #[], constructorBindings := #[]
}

end Examples.Product.Canonical.BoundedQueue
