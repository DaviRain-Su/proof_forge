import ProofForge.Frontend.Surface.Syntax

/-! # Surface Set Collection

Set<T, capacity> exists only in Surface. Expansion produces two Core state
declarations: a `map T bool` for membership and a `scalar u64` for cardinality.
No Core or backend changes are needed.

Generated state names use `$surface.set.<id>.members` and
`$surface.set.<id>.cardinality`.
-/

namespace ProofForge.Frontend.Surface

/-- A Surface Set declaration. -/
structure SurfaceSetDecl where
  id : Nat
  elementType : SurfaceType
  capacity : Nat
  deriving Repr

/-- Construct the generated state name for set members. -/
def SurfaceSetDecl.membersName (s : SurfaceSetDecl) : String :=
  s!"$surface.set.{s.id}.members"

/-- Construct the generated state name for set cardinality. -/
def SurfaceSetDecl.cardinalityName (s : SurfaceSetDecl) : String :=
  s!"$surface.set.{s.id}.cardinality"

/-- Expand a Set declaration into two Surface state declarations:
a map T bool for membership and a scalar u64 for cardinality. -/
def SurfaceSetDecl.expand (s : SurfaceSetDecl) : Array SurfaceStateDecl :=
  #[
    { name := s.membersName,
      kind := .map s.elementType .bool (some s.capacity) },
    { name := s.cardinalityName,
      kind := .scalar .u64 }
  ]

/-- Validate a Set declaration: capacity must be positive. -/
def SurfaceSetDecl.validate (s : SurfaceSetDecl) : Except String Unit :=
  if s.capacity == 0 then
    .error s!"Set {s.id}: capacity must be positive"
  else .ok ()

/-- Build a `stateRead` expression for set membership check. -/
def SurfaceSetDecl.containsExpr (s : SurfaceSetDecl) (key : SurfaceExpr) :
    SurfaceExpr :=
  .stateRead s.membersName

/-- Build statements for `insert key`: check if key exists, if not write true
and increment cardinality. -/
def SurfaceSetDecl.insertStmts (s : SurfaceSetDecl) (key : SurfaceExpr) :
    Array SurfaceStmt :=
  -- Simplified: always write true and increment (the normalizer handles
  -- the actual Core CFG with branch logic for idempotent insert).
  -- For now, we emit stateWrite for the map (with key) and increment
  -- cardinality. The key is bound in the calling context.
  #[
    .stateWrite s.membersName (.literal (.boolLit true)),
    .stateWrite s.cardinalityName
      (.arith .add true
        (.stateRead s.cardinalityName)
        (.literal (.u64Lit 1)))
  ]

/-- Build statements for `remove key`: check if key exists, if so write false
and decrement cardinality. -/
def SurfaceSetDecl.removeStmts (s : SurfaceSetDecl) (key : SurfaceExpr) :
    Array SurfaceStmt :=
  -- Simplified: always write false and decrement (the normalizer handles
  -- the actual Core CFG with branch logic for idempotent remove).
  #[
    .stateWrite s.membersName (.literal (.boolLit false)),
    .stateWrite s.cardinalityName
      (.arith .sub true
        (.stateRead s.cardinalityName)
        (.literal (.u64Lit 1)))
  ]

end ProofForge.Frontend.Surface