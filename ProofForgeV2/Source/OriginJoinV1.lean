/-
  ProofForgeV2.Source.OriginJoinV1 — sole Source-owned exact join of production
  ProgramV1 NodeIds and same-snapshot spans into an opaque path→SourceOrigin
  inventory.

  The sole constructor path is `joinOriginsV1`, which consumes a validated
  source unit, a project-relative path, and the canonical span table from the
  same immutable parser snapshot (SpanJoin). It fails closed on:

    * invalid project-relative path (`.identity`)
    * sourceHash / NodeId assignment failures (`.identity`)
    * empty assignment table, duplicate/missing/extra span paths, count
      mismatch, invalid origins, duplicate or non-ascending NodeIds
      (`.inventory`)

  Exposed observations:
    * `originInventorySourceHashV1` — production `sourceHashV1`
    * `originInventoryOriginsV1` — unique ascending NodeId-ordered origins
    * `originInventoryLookupPathV1` — exact path → SourceOrigin (length-framed)

  Path HashMap keys use collision-free length-framed `pathLookupKeyV1` (not
  delimiter concatenation). There is no caller-trusted arbitrary-origin
  constructor and no Semantic import.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import Std.Data.HashMap

namespace ProofForgeV2.Source.OriginJoinV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

inductive OriginJoinErrorV1 where
  | identity (detail : String)
  | inventory (detail : String)
  deriving Repr

/-- Opaque production origin inventory. Sole constructor is `joinOriginsV1`. -/
structure OriginInventoryV1 where
  private mk ::
  private sourceHash_ : Digest
  private origins_ : Array SourceOrigin
  private byPath_ : Std.HashMap String SourceOrigin

private def failIdentity (detail : String) : Except OriginJoinErrorV1 α :=
  .error (.identity detail)

private def failInventory (detail : String) : Except OriginJoinErrorV1 α :=
  .error (.inventory detail)

private def mapString (r : Except String α) (tag : String) :
    Except OriginJoinErrorV1 α :=
  match r with
  | .ok v => .ok v
  | .error e => .error (.identity s!"{tag}: {e}")

private def compareNodeIdBytes (left right : ByteArray) : Ordering :=
  let n := Nat.min left.size right.size
  let rec loop (i : Nat) : Ordering :=
    if i < n then
      let bl := left.get! i
      let br := right.get! i
      if bl.toNat < br.toNat then .lt
      else if bl.toNat > br.toNat then .gt
      else loop (i + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

/-- Collision-free length-framed path key for HashMap lookup.

    Each segment is encoded as `p=<utf8Len>:<parentTag>;f=<utf8Len>:<fieldTag>;i=<index>;`
    prefixed by segment count. Delimiter characters inside tags cannot forge
    another path (lengths frame every field). Replaces the unsafe
    `\x1f`/`\x1e` concatenation that admitted cross-field collisions.
-/
def pathLookupKeyV1 (path : NormalizedSyntacticPathV1) : String :=
  Id.run do
    let mut out := s!"n={path.size};"
    for seg in path do
      let pt := seg.parentTag
      let ft := seg.fieldTag
      out := out ++
        s!"p={pt.utf8ByteSize}:{pt};f={ft.utf8ByteSize}:{ft};i={seg.index.toNat};"
    pure out

/-- Join production NodeIds with span-join spans into an opaque origin inventory.

    `origins_` is sorted by NodeId raw bytes unique ascending; `sourceHash_` is
    `sourceHashV1(source)`. Path lookup uses length-framed keys. Fail closed on:
    * invalid project-relative path
    * duplicate span paths (before HashMap insert)
    * missing span for an assignment path
    * extra span path not present in the assignment table
    * NodeId collision / non-unique after sort
    * empty assignment table
    * span-path count ≠ assignment count
    * invalid SourceOrigin (path / NodeId / start>end)
-/
def joinOriginsV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    Except OriginJoinErrorV1 OriginInventoryV1 := do
  match validateProjectRelativePath sourcePath with
  | .error e => return ← failIdentity s!"sourcePath: {e}"
  | .ok () => pure ()
  let hash ← mapString (sourceHashV1 source) "sourceHashV1"
  let table ← mapString
    (assignNodeIdsV1 source.moduleName source.programIdentity source.program)
    "assignNodeIdsV1"
  let assignments := nodeAssignmentsPreorderV1 table
  if assignments.isEmpty then
    return ← failInventory "NodeId assignment table is empty"
  -- Path → span map once; reject duplicate paths before insert (linear).
  let mut spanByPath : Std.HashMap String SourceByteSpanV1 :=
    Std.HashMap.emptyWithCapacity spans.size
  let mut spanPathKeys : Array String := Array.mkEmpty spans.size
  for (p, sp) in spans do
    let key := pathLookupKeyV1 p
    if spanByPath.contains key then
      return ← failInventory s!"duplicate span path key={key}"
    spanByPath := spanByPath.insert key sp
    spanPathKeys := spanPathKeys.push key
  -- Assignment coverage: every assignment path has a span; track used keys.
  let mut usedSpanKeys : Std.HashMap String Unit :=
    Std.HashMap.emptyWithCapacity assignments.size
  let mut nodes : Array SourceOrigin := #[]
  let mut byPath : Std.HashMap String SourceOrigin :=
    Std.HashMap.emptyWithCapacity assignments.size
  for a in assignments do
    let key := pathLookupKeyV1 a.path
    match spanByPath.get? key with
    | none =>
        return ← failInventory
          s!"missing span for NodeId assignment tag={a.constructorTag}"
    | some span =>
        let origin : SourceOrigin := {
          sourcePath := sourcePath
          startByte := span.startByte
          endByte := span.endByte
          nodeId := a.nodeId
        }
        match validateSourceOrigin origin with
        | .error e => return ← failInventory s!"invalid origin: {e}"
        | .ok () => pure ()
        usedSpanKeys := usedSpanKeys.insert key ()
        nodes := nodes.push origin
        byPath := byPath.insert key origin
  -- Extra span paths (present in spans but not in assignment preorder) fail closed.
  for key in spanPathKeys do
    unless usedSpanKeys.contains key do
      return ← failInventory s!"extra span path not in NodeId assignment table key={key}"
  unless spans.size == assignments.size do
    return ← failInventory
      s!"span count {spans.size} != assignment count {assignments.size}"
  unless usedSpanKeys.size == assignments.size do
    return ← failInventory "span/assignment path coverage incomplete"
  let sorted :=
    nodes.qsort fun a b => compareNodeIdBytes a.nodeId.bytes b.nodeId.bytes == .lt
  -- Unique ascending NodeIds (reject duplicates and non-ascending after sort).
  for i in [1:sorted.size] do
    match sorted[i - 1]?, sorted[i]? with
    | some prev, some cur =>
        match compareNodeIdBytes prev.nodeId.bytes cur.nodeId.bytes with
        | .eq => return ← failInventory "duplicate NodeId in inventory"
        | .gt => return ← failInventory "inventory NodeIds not ascending after sort"
        | .lt => pure ()
    | _, _ => pure ()
  pure ⟨hash, sorted, byPath⟩

def originInventorySourceHashV1 (inv : OriginInventoryV1) : Digest :=
  inv.sourceHash_

/-- Deterministic NodeId-ordered unique ascending origin projection. -/
def originInventoryOriginsV1 (inv : OriginInventoryV1) : Array SourceOrigin :=
  inv.origins_

/-- Exact path → SourceOrigin lookup using length-framed path keys. -/
def originInventoryLookupPathV1
    (inv : OriginInventoryV1) (path : NormalizedSyntacticPathV1) :
    Option SourceOrigin :=
  inv.byPath_.get? (pathLookupKeyV1 path)

end ProofForgeV2.Source.OriginJoinV1
