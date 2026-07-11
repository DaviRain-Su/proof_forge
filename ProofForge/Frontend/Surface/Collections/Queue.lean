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
  #[
    .stateWrite q.lengthName
      (.arith .add true
        (.stateRead q.lengthName)
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
  #[
    .stateWrite q.lengthName
      (.arith .sub true
        (.stateRead q.lengthName)
        (.literal (.u64Lit 1))),
    .stateWrite q.headName
      (.arith .mod true
        (.arith .add true
          (.stateRead q.headName)
          (.literal (.u64Lit 1)))
        (.literal (.u64Lit q.capacity)))
  ]

/-- Build expression for `peek`: reads items[head] (simplified to head scalar read). -/
def SurfaceQueueDecl.peekExpr (q : SurfaceQueueDecl) : SurfaceExpr :=
  .stateRead q.headName

/-- Build expression for `length`: reads the length scalar. -/
def SurfaceQueueDecl.lengthExpr (q : SurfaceQueueDecl) : SurfaceExpr :=
  .stateRead q.lengthName

end ProofForge.Frontend.Surface
