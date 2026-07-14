import ProofForge.Frontend.Surface.Syntax

/-! # Surface Queue Collection

Queue<T, capacity> exists only in Surface. Expansion produces three Core
state declarations: a `fixedArray T capacity` for items, a `scalar u64`
for head, and a `scalar u64` for length. No Core or backend changes.

Generated state names use `$surface.queue.<id>.items`,
`$surface.queue.<id>.head`, and `$surface.queue.<id>.length`.
-/

namespace ProofForge.Frontend.Surface

/-- A Surface Queue declaration. -/
structure SurfaceQueueDecl where
  id : Nat
  elementType : SurfaceType
  capacity : Nat
  deriving Repr

/-- Construct the generated state name for queue items. -/
def SurfaceQueueDecl.itemsName (q : SurfaceQueueDecl) : String :=
  s!"$surface.queue.{q.id}.items"

/-- Construct the generated state name for queue head. -/
def SurfaceQueueDecl.headName (q : SurfaceQueueDecl) : String :=
  s!"$surface.queue.{q.id}.head"

/-- Construct the generated state name for queue length. -/
def SurfaceQueueDecl.lengthName (q : SurfaceQueueDecl) : String :=
  s!"$surface.queue.{q.id}.length"

/-- Expand a Queue declaration into three Surface state declarations:
a fixedArray for items, a scalar u64 for head, and a scalar u64 for length. -/
def SurfaceQueueDecl.expand (q : SurfaceQueueDecl) : Array SurfaceStateDecl :=
  #[
    { name := q.itemsName,
      kind := .fixedArray q.elementType q.capacity, generated := true },
    { name := q.headName,
      kind := .scalar .u64, generated := true },
    { name := q.lengthName,
      kind := .scalar .u64, generated := true }
  ]

/-- Validate a Queue declaration: capacity must be positive. -/
def SurfaceQueueDecl.validate (q : SurfaceQueueDecl) : Except String Unit :=
  if q.capacity == 0 then
    .error s!"Queue {q.id}: capacity must be positive"
  else .ok ()

/-- Build statements for `enqueue value`:
1. load head and length
2. assert length < capacity (simplified)
3. store length + 1
-/
def SurfaceQueueDecl.enqueueStmts (q : SurfaceQueueDecl) (value : SurfaceExpr) :
    Array SurfaceStmt :=
  let head := s!"$surface.queue.{q.id}.enqueue.head"
  let length := s!"$surface.queue.{q.id}.enqueue.length"
  let index := s!"$surface.queue.{q.id}.enqueue.index"
  #[
    .bind head .u64 (.stateRead q.headName),
    .bind length .u64 (.stateRead q.lengthName),
    .assert (.compare .lt (.local length) (.literal (.u64Lit q.capacity))) "QueueFull",
    .bind index .u64 (.arith .mod false
      (.arith .add false (.local head) (.local length)) (.literal (.u64Lit q.capacity))),
    .arrayWrite q.itemsName (.local index) value,
    .stateWrite q.lengthName
      (.arith .add true
        (.local length)
        (.literal (.u64Lit 1)))
  ]

/-- Build statements for `dequeue`:
1. load length
2. assert length > 0 (simplified)
3. store length - 1
4. return value from items[head] (simplified)
-/
def SurfaceQueueDecl.dequeueStmts (q : SurfaceQueueDecl) :
    Array SurfaceStmt :=
  let head := s!"$surface.queue.{q.id}.dequeue.head"
  let length := s!"$surface.queue.{q.id}.dequeue.length"
  let value := s!"$surface.queue.{q.id}.dequeue.value"
  #[
    .bind head .u64 (.stateRead q.headName),
    .bind length .u64 (.stateRead q.lengthName),
    .assert (.compare .gt (.local length) (.literal (.u64Lit 0))) "QueueEmpty",
    .bind value q.elementType (.arrayRead q.itemsName (.local head)),
    .stateWrite q.headName
      (.arith .mod true
        (.arith .add true
          (.local head)
          (.literal (.u64Lit 1)))
        (.literal (.u64Lit q.capacity))),
    .stateWrite q.lengthName
      (.arith .sub true (.local length) (.literal (.u64Lit 1))),
    .returnExpr (.local value)
  ]

/-- Build expression for `peek`: reads items[head] (simplified to head scalar read). -/
def SurfaceQueueDecl.peekExpr (q : SurfaceQueueDecl) : SurfaceExpr :=
  .arrayRead q.itemsName (.stateRead q.headName)

def SurfaceQueueDecl.peekStmts (q : SurfaceQueueDecl) : Array SurfaceStmt :=
  #[
    .assert (.compare .gt (.stateRead q.lengthName) (.literal (.u64Lit 0))) "QueueEmpty",
    .returnExpr q.peekExpr]

/-- Build expression for `length`: reads the length scalar. -/
def SurfaceQueueDecl.lengthExpr (q : SurfaceQueueDecl) : SurfaceExpr :=
  .stateRead q.lengthName

end ProofForge.Frontend.Surface
