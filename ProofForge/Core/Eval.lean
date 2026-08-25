import ProofForge.Core.Ops
import ProofForge.Core.Schema

namespace ProofForge.Core

inductive CheckedArith where
  | add | sub | mul | div | mod
  deriving BEq, Repr, Inhabited

/-- A source value or an explicitly named checked calculation; no backend accumulator is observable. -/
inductive ValueRef (ValExt : Type) where
  | source (value : Ops.Val ValExt)
  | checked (kind : CheckedArith) (lhs rhs : Ops.Val ValExt)
  deriving BEq, Repr

instance : Inhabited (ValueRef ValExt) := ⟨.source (.lit 0)⟩

/-- A target-neutral write to one statically known source-level state leaf. -/
structure StateWrite (ValExt : Type) where
  place : Place
  value : ValueRef ValExt
  deriving BEq, Repr

instance : Inhabited (StateWrite ValExt) where
  default := { place := default, value := default }

/-- A runtime vector index plus a typed path inside one element. -/
structure DynamicPlace (ValExt : Type) where
  vector : Place
  index : Ops.Val ValExt
  /-- Relative to the element root; empty for a vector of scalar leaves. -/
  elementPath : Array PathStep := #[]
  deriving BEq, Repr

instance : Inhabited (DynamicPlace ValExt) where
  default := { vector := default, index := default }

structure DynamicWrite (ValExt : Type) where
  place : DynamicPlace ValExt
  value : ValueRef ValExt
  deriving BEq, Repr

instance : Inhabited (DynamicWrite ValExt) where
  default := { place := default, value := default }

/-- Successful completion of a mutating source expression and any accompanying static writes. -/
structure Commit (ValExt : Type) where
  writes : Array (StateWrite ValExt) := #[]
  result : ValueRef ValExt
  deriving BEq, Repr

instance : Inhabited (Commit ValExt) where
  default := { result := default }

/-- Target-neutral state effects retain source control structure rather than emitter traversal order. -/
inductive StateEvent (ValExt : Type) where
  | letValue (i : Nat) (value : Ops.Val ValExt)
  | write (write : StateWrite ValExt)
  | dynamicWrite (write : DynamicWrite ValExt)
  | commit (commit : Commit ValExt)
  | branch (cmp : Ops.Cmp) (lhs rhs : Ops.Val ValExt)
      (thenEvents elseEvents : Array (StateEvent ValExt))
  | loop (bound : Nat) (body : Array (StateEvent ValExt))
  deriving BEq, Repr

instance : Inhabited (StateEvent ValExt) := ⟨.loop 0 #[]⟩

structure Evaluation (ValExt : Type) where
  /-- False only for hand-authored legacy fixtures that predate Core evaluation. -/
  explicit : Bool := false
  events : Array (StateEvent ValExt) := #[]
  deriving BEq, Repr, Inhabited

private partial def StateEvent.collectCommits (event : StateEvent ValExt) :
    Array (Commit ValExt) :=
  match event with
  | StateEvent.commit item => #[item]
  | StateEvent.branch _ _ _ thenEvents elseEvents =>
      thenEvents.flatMap StateEvent.collectCommits ++
        elseEvents.flatMap StateEvent.collectCommits
  | StateEvent.loop _ body => body.flatMap StateEvent.collectCommits
  | StateEvent.letValue .. | StateEvent.write _ | StateEvent.dynamicWrite _ => #[]

def Evaluation.commits (evaluation : Evaluation ValExt) : Array (Commit ValExt) :=
  evaluation.events.flatMap StateEvent.collectCommits

private partial def StateEvent.collectDynamicWrites (event : StateEvent ValExt) :
    Array (DynamicWrite ValExt) :=
  match event with
  | StateEvent.dynamicWrite item => #[item]
  | StateEvent.branch _ _ _ thenEvents elseEvents =>
      thenEvents.flatMap StateEvent.collectDynamicWrites ++
        elseEvents.flatMap StateEvent.collectDynamicWrites
  | StateEvent.loop _ body => body.flatMap StateEvent.collectDynamicWrites
  | StateEvent.letValue .. | StateEvent.write _ | StateEvent.commit _ => #[]

def Evaluation.dynamicWrites (evaluation : Evaluation ValExt) : Array (DynamicWrite ValExt) :=
  evaluation.events.flatMap StateEvent.collectDynamicWrites

private def firstPlace (schema : Schema) : Except String Place :=
  match schema.leaves[0]? with
  | some leaf => .ok leaf.place
  | none => .error "extract/unsupported: state schema has no leaves"

private def placeByName (schema : Schema) (name : String) : Except String Place :=
  match schema.leafByName? name with
  | some leaf => .ok leaf.place
  | none => .error s!"extract/unsupported: unknown state leaf {name}"

private def checkedValue? (ops : Array (Ops.Op ValExt OpExt)) :
    Option (Option String × ValueRef ValExt) :=
  ops.findSome? fun
    | .checkedAddU64 lhs rhs =>
        some ((match lhs with | .field _ name => some name | _ => none), .checked .add lhs rhs)
    | .checkedSubU64 lhs rhs =>
        some ((match lhs with | .field _ name => some name | _ => none), .checked .sub lhs rhs)
    | .checkedMulU64 lhs rhs =>
        some ((match lhs with | .field _ name => some name | _ => none), .checked .mul lhs rhs)
    | .checkedDivU64 lhs rhs =>
        some ((match lhs with | .field _ name => some name | _ => none), .checked .div lhs rhs)
    | .checkedModU64 lhs rhs =>
        some ((match lhs with | .field _ name => some name | _ => none), .checked .mod lhs rhs)
    | _ => none

private partial def hasStoreField (ops : Array (Ops.Op ValExt OpExt)) : Bool :=
  ops.any fun
    | .storeField .. => true
    | .ite _ _ _ thn els => hasStoreField thn || hasStoreField els
    | .forBody _ body => hasStoreField body
    | _ => false

private partial def hasIndexSet (ops : Array (Ops.Op ValExt OpExt)) : Bool :=
  ops.any fun
    | .indexSetLeaf .. | .indexSet .. => true
    | .ite _ _ _ thn els => hasIndexSet thn || hasIndexSet els
    | .forBody _ body => hasIndexSet body
    | _ => false

private def implicitDestination (schema : Schema) (ops : Array (Ops.Op ValExt OpExt))
    (value : Ops.Val ValExt) : Except String Place := do
  if let some (name?, _) := checkedValue? ops then
    match name? with
    | some name => return ← placeByName schema name
    | none => pure ()
  match value with
  | .field _ name =>
      if (schema.leafByName? name).isSome then
        placeByName schema name
      else
        firstPlace schema
  | _ => firstPlace schema

private def implicitValue (ops : Array (Ops.Op ValExt OpExt))
    (value : Ops.Val ValExt) : ValueRef ValExt :=
  match checkedValue? ops with
  | some (_, checked) => checked
  | none =>
      match value with
      | .field _ _ => .source (.arg 0)
      | _ => .source value

private def commitFor (schema : Schema) (ops : Array (Ops.Op ValExt OpExt))
    (value : Ops.Val ValExt) : Except String (Commit ValExt) := do
  if hasStoreField ops then
    return { result := .source value }
  if hasIndexSet ops then
    return { result := .source value }
  if schema.firstOption?.isSome then
    throw "extract/unsupported: Option writeback requires explicit tag and payload stores"
  let place ← implicitDestination schema ops value
  let stored := implicitValue ops value
  return { writes := #[{ place, value := stored }], result := stored }

private def dynamicPlace (schema : Schema) (name : String) (index : Ops.Val ValExt)
    (byteOffset : Nat) : Except String (DynamicPlace ValExt) := do
  let some vector := schema.vector? name
    | throw s!"extract/unsupported: unknown vector {name}"
  let mut offset := 0
  for leaf in schema.vectorElementLeaves vector do
    if offset == byteOffset then
      let relative := leaf.place.steps.extract (vector.place.steps.size + 1)
      return { vector := vector.place, index, elementPath := relative }
    offset := offset + leaf.width
  throw s!"extract/unsupported: vector {name} has no leaf at byte offset {byteOffset}"

private def dynamicLeafPlace (schema : Schema) (name : String) (index : Ops.Val ValExt)
    (leafName : String) : Except String (DynamicPlace ValExt) := do
  let some vector := schema.vector? name
    | throw s!"extract/unsupported: unknown vector {name}"
  for leaf in schema.vectorElementLeaves vector do
    if vector.relativeLeafName leaf == leafName then
      let relative := leaf.place.steps.extract (vector.place.steps.size + 1)
      return { vector := vector.place, index, elementPath := relative }
  throw s!"extract/unsupported: vector {name} has no leaf {leafName}"

private partial def eventsFor (schema : Schema) (ops : Array (Ops.Op ValExt OpExt)) :
    Except String (Array (StateEvent ValExt)) := do
  let mut events := #[]
  for op in ops do
    match op with
    | .letLocal i value =>
        events := events.push (.letValue i value)
    | .joinLocal _ => pure ()
    | .setLocal i value =>
        events := events.push (.letValue i value)
    | .ite cmp lhs rhs thenOps elseOps =>
        let thenEvents ← eventsFor schema thenOps
        let elseEvents ← eventsFor schema elseOps
        if !thenEvents.isEmpty || !elseEvents.isEmpty then
          events := events.push (.branch cmp lhs rhs thenEvents elseEvents)
    | .forBody bound body =>
        let bodyEvents ← eventsFor schema body
        if !bodyEvents.isEmpty then
          events := events.push (.loop bound bodyEvents)
    | .indexSetLeaf name index value _ leafName =>
        let place ← dynamicLeafPlace schema name index leafName
        events := events.push (.dynamicWrite { place, value := .source value })
    | .indexSet name index value _ byteOffset =>
        let place ← dynamicPlace schema name index byteOffset
        events := events.push (.dynamicWrite { place, value := .source value })
    | .storeField name value =>
        let place ←
          match placeByName schema name with
          | .ok place => pure place
          | .error reason => throw s!"storeField {name}: {reason}"
        events := events.push (.write { place, value := .source value })
    | .okState value =>
        let commit ←
          match commitFor schema ops value with
          | .ok commit => pure commit
          | .error reason => throw s!"okState: {reason}"
        events := events.push (.commit commit)
    | _ => pure ()
  return events

/-- Resolve implicit mutation conventions without inspecting or naming any target extension. -/
def evaluate (schema : Schema) (ops : Array (Ops.Op ValExt OpExt)) :
    Except String (Evaluation ValExt) := do
  if schema.isEmpty then
    throw "extract/unsupported: Core evaluation requires a typed state schema"
  return { explicit := true, events := ← eventsFor schema ops }

end ProofForge.Core
