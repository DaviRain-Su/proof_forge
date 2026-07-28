/-
  ProofForgeV2.Semantic.ProvenanceV1 — S2 SemanticProvenanceV1 builder for the
  supported NormalizeV1 Counter / S1 surface.

  Builds a complete originMap for every semantic entity of a structure-gated
  SemanticProgramV1 carrier, joined to a production SourceNodeInventoryV1
  derived from assignNodeIdsV1 + SpanJoin spans + sourceHashV1.

  Attribution is exact and deterministic for the shipped Counter-like subset:
  each state/callable/block/instruction/value/terminator/type/requirement binds
  to its declaration, expression, statement, or nearest producing source NodeId
  (reconstructed by the same AST walk NormalizeV1 uses). Multi-origin
  requirements collect every producing site and sort uniquely by SourceOrigin
  wire key. Synthetic Unit types and implicit init return terminators bind the
  nearest producing declaration/block node — never an arbitrary inventory pick.

  Inventory construction is exact: duplicate span paths, missing/extra paths,
  duplicate/nonascending NodeIds, and count mismatches fail closed before any
  originMap is emitted.

  Path HashMap keys use length-framed `pathLookupKeyV1` (collision-free; not
  delimiter concatenation). Requirement missing producing sites fail closed
  (no program-root fallback).

  Low-level only (caller-trusted; not complete authority):
    * `buildSourceNodeInventoryV1` / `buildSemanticProvenanceV1` /
      `rebuildSemanticProvenanceV1`
    * `validateSourceNodeInventoryExactV1` (hash + NodeId set/order only —
      does **not** re-check path/start/end against spans)
    * Wire `validateSemanticProvenanceJoinV1` / `semanticProvenanceDigestJoinV1`

  Source-bound authority is exclusively
  `NormalizeV1.validateSemanticProvenanceV1` /
  `NormalizeV1.semanticProvenanceDigestV1` /
  `NormalizeV1.normalizeProgramWithProvenanceV1`, which rebuild inventory from
  trusted `sourcePath + spans` and never accept a caller inventory.
  Formal TASK-D2-06 remains pending.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import Std.Data.HashMap

namespace ProofForgeV2.Semantic.ProvenanceV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private abbrev SrcType := ProofForgeV2.Source.AstV1.TypeV1
private abbrev SrcExpr := ProofForgeV2.Source.AstSpineV1.ExprV1
private abbrev SrcStmt := ProofForgeV2.Source.AstSpineV1.StmtV1
private abbrev SrcPlace := ProofForgeV2.Source.AstSpineV1.PlaceV1
private abbrev SrcBlock := ProofForgeV2.Source.AstSpineV1.BlockV1
private abbrev SrcParam := ProofForgeV2.Source.AstSupportV1.ParamV1
private abbrev SrcVis := ProofForgeV2.Source.AstV1.VisibilityV1

inductive ProvenanceBuildErrorV1 where
  | identity (detail : String)
  | inventory (detail : String)
  | wire (error : SemanticWireErrorV1)
  | unsupported (detail : String)
  deriving Repr

private def failIdentity (detail : String) : Except ProvenanceBuildErrorV1 α :=
  .error (.identity detail)

private def failInventory (detail : String) : Except ProvenanceBuildErrorV1 α :=
  .error (.inventory detail)

private def failUnsupported (detail : String) : Except ProvenanceBuildErrorV1 α :=
  .error (.unsupported detail)

private def mapString (r : Except String α) (tag : String) :
    Except ProvenanceBuildErrorV1 α :=
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

private def compareByteArrayLexLocal (left right : ByteArray) : Ordering :=
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

private def childPath
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    NormalizedSyntacticPathV1 :=
  path.push {
    parentTag := parentTag
    fieldTag := fieldTag
    index := UInt32.ofNat index
  }

private def directChild
    (path : NormalizedSyntacticPathV1) (parentTag fieldTag : String) :
    NormalizedSyntacticPathV1 :=
  childPath path parentTag fieldTag 0

/-- Map source qualified name to Common.QualifiedName. -/
def sourceQualifiedNameToCommonV1 (name : SourceQualifiedNameV1) :
    Except ProvenanceBuildErrorV1 QualifiedName := do
  let comps := (NonEmptyArray.toArray name.components).map (·.raw)
  match parseQualifiedName comps with
  | .ok qn => pure qn
  | .error e => failIdentity e

/-- Map source program identity to Common.QualifiedName (≥2 components). -/
def sourceIdentityToQualifiedNameV1 (identity : SourceQualifiedNameV1) :
    Except ProvenanceBuildErrorV1 QualifiedName := do
  let comps := (NonEmptyArray.toArray identity.components).map (·.raw)
  unless comps.size ≥ 2 do
    return ← failIdentity "provenance qualifiedName requires ≥2 components"
  match parseQualifiedName comps with
  | .ok qn => pure qn
  | .error e => failIdentity e

/-- Join production NodeIds with span-join spans into SourceNodeInventoryV1.

    nodes sorted by NodeId raw bytes unique ascending; inventory.sourceHash is
    sourceHashV1(source). Fail closed on:
    * duplicate span paths (before HashMap insert)
    * missing span for an assignment path
    * extra span path not present in the assignment table
    * NodeId collision / non-unique after sort
    * empty assignment table
    * span-path count ≠ assignment count
-/
def buildSourceNodeInventoryV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    Except ProvenanceBuildErrorV1 SourceNodeInventoryV1 := do
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
  pure { sourceHash := hash, nodes := sorted }

/-- Low-level NodeId-set inventory check (caller-trusted; **not** full authority).

    Recomputes `sourceHashV1` and `assignNodeIdsV1`; rejects wrong sourceHash,
    wrong node count, missing/extra/duplicate NodeIds, and nonascending order.

    **Limit:** does **not** re-verify each origin's `sourcePath` / `startByte` /
    `endByte` against production spans. Coordinated path/span mutation that
    preserves NodeIds and sourceHash still passes this helper. Full
    path/start/end/nodeId authority is
    `validateSourceNodeInventorySpanBoundExactV1` or
    `NormalizeV1.validateSemanticProvenanceV1` (rebuilds inventory from spans).
-/
def validateSourceNodeInventoryExactV1
    (source : ValidatedSourceV1)
    (inventory : SourceNodeInventoryV1) :
    Except ProvenanceBuildErrorV1 Unit := do
  let expectedHash ← mapString (sourceHashV1 source) "sourceHashV1"
  unless inventory.sourceHash == expectedHash do
    return ← failInventory "inventory.sourceHash does not match sourceHashV1"
  let table ← mapString
    (assignNodeIdsV1 source.moduleName source.programIdentity source.program)
    "assignNodeIdsV1"
  let assignments := nodeAssignmentsPreorderV1 table
  unless inventory.nodes.size == assignments.size do
    return ← failInventory
      s!"inventory node count {inventory.nodes.size} != assignment count {assignments.size}"
  let mut expectedIds : Std.HashMap ByteArray Unit :=
    Std.HashMap.emptyWithCapacity assignments.size
  for a in assignments do
    expectedIds := expectedIds.insert a.nodeId.bytes ()
  let mut seen : Std.HashMap ByteArray Unit :=
    Std.HashMap.emptyWithCapacity inventory.nodes.size
  let mut prevBytes? : Option ByteArray := none
  for n in inventory.nodes do
    match validateSourceOrigin n with
    | .error e => return ← failInventory s!"invalid inventory origin: {e}"
    | .ok () => pure ()
    unless expectedIds.contains n.nodeId.bytes do
      return ← failInventory "inventory contains foreign NodeId not in assignment table"
    if seen.contains n.nodeId.bytes then
      return ← failInventory "duplicate NodeId in inventory"
    seen := seen.insert n.nodeId.bytes ()
    match prevBytes? with
    | none => pure ()
    | some prev =>
        match compareNodeIdBytes prev n.nodeId.bytes with
        | .lt => pure ()
        | .eq | .gt =>
            return ← failInventory "inventory nodes not unique ascending by NodeId"
    prevBytes? := some n.nodeId.bytes
  unless seen.size == assignments.size do
    return ← failInventory "inventory missing NodeIds from assignment table"
  pure ()

/-- Span-bound inventory exactness: rebuild from trusted path+spans and require
    every `(sourcePath,startByte,endByte,nodeId)` field equal (NodeId order).

    Rejects coordinated path/span substitution that preserves NodeId set.
    Still a Provenance helper — public authority is NormalizeV1.
-/
def validateSourceNodeInventorySpanBoundExactV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))
    (inventory : SourceNodeInventoryV1) :
    Except ProvenanceBuildErrorV1 Unit := do
  let expected ← buildSourceNodeInventoryV1 source sourcePath spans
  unless expected.sourceHash == inventory.sourceHash do
    return ← failInventory "inventory.sourceHash does not match rebuilt inventory"
  unless expected.nodes.size == inventory.nodes.size do
    return ← failInventory
      s!"inventory node count {inventory.nodes.size} != rebuilt {expected.nodes.size}"
  for i in [:expected.nodes.size] do
    match expected.nodes[i]?, inventory.nodes[i]? with
    | some e, some a =>
        unless e == a do
          return ← failInventory
            s!"inventory origin field mismatch at sorted index {i} (path/start/end/nodeId)"
    | _, _ =>
        return ← failInventory "inventory origin index out of range"
  pure ()

private def sortOriginsUnique
    (origins : Array SourceOrigin) :
    Except ProvenanceBuildErrorV1 (Array SourceOrigin) := do
  if origins.isEmpty then
    return ← failInventory "origin binding requires nonempty origins"
  let mut keyed : Array (ByteArray × SourceOrigin) := #[]
  for o in origins do
    match encodeSourceOrigin o with
    | .error e => return ← .error (.wire e)
    | .ok kb => keyed := keyed.push (kb, o)
  let sorted := keyed.qsort fun a b =>
    compareByteArrayLexLocal a.1 b.1 == .lt
  let mut out : Array SourceOrigin := #[]
  for (kb, o) in sorted do
    match out.back? with
    | none => out := out.push o
    | some prev =>
        match encodeSourceOrigin prev with
        | .error e => return ← .error (.wire e)
        | .ok prevKb =>
            match compareByteArrayLexLocal prevKb kb with
            | .eq => pure ()
            | .lt => out := out.push o
            | .gt => return ← failInventory "origin sort invariant broken"
  pure out

private def sortOriginMap
    (bindings : Array OriginBindingV1) :
    Except ProvenanceBuildErrorV1 (Array OriginBindingV1) := do
  let mut keyed : Array (ByteArray × OriginBindingV1) := #[]
  for b in bindings do
    match encodeSemanticEntityRefV1 b.entity with
    | .error e => return ← .error (.wire e)
    | .ok kb => keyed := keyed.push (kb, b)
  let sorted := keyed.qsort fun a b =>
    compareByteArrayLexLocal a.1 b.1 == .lt
  pure (sorted.map (·.2))

/-- Path → SourceOrigin lookup from assignments + inventory (NodeId join). -/
private structure OriginIndexV1 where
  byPath : Std.HashMap String SourceOrigin
  byNodeId : Std.HashMap ByteArray SourceOrigin

private def buildOriginIndexV1
    (source : ValidatedSourceV1)
    (inventory : SourceNodeInventoryV1) :
    Except ProvenanceBuildErrorV1 OriginIndexV1 := do
  let table ← mapString
    (assignNodeIdsV1 source.moduleName source.programIdentity source.program)
    "assignNodeIdsV1"
  let assignments := nodeAssignmentsPreorderV1 table
  let mut byNodeId : Std.HashMap ByteArray SourceOrigin :=
    Std.HashMap.emptyWithCapacity inventory.nodes.size
  for o in inventory.nodes do
    byNodeId := byNodeId.insert o.nodeId.bytes o
  let mut byPath : Std.HashMap String SourceOrigin :=
    Std.HashMap.emptyWithCapacity assignments.size
  for a in assignments do
    match byNodeId.get? a.nodeId.bytes with
    | none =>
        return ← failInventory
          s!"assignment NodeId missing from inventory tag={a.constructorTag}"
    | some origin =>
        byPath := byPath.insert (pathLookupKeyV1 a.path) origin
  pure { byPath, byNodeId }

private def originAt
    (idx : OriginIndexV1) (path : NormalizedSyntacticPathV1) :
    Except ProvenanceBuildErrorV1 SourceOrigin :=
  match idx.byPath.get? (pathLookupKeyV1 path) with
  | some o => pure o
  | none => failInventory s!"no origin for path key={pathLookupKeyV1 path}"

private def raw (n : SourceNameComponentV1) : String := n.raw

/-- Mutable multi-origin accumulator keyed by entity encode bytes. -/
private structure AttrAccumV1 where
  -- entityKey wire bytes → list of origins (unsorted; finalized later)
  table : Std.HashMap ByteArray (SemanticEntityRefV1 × Array SourceOrigin)

private def emptyAttr : AttrAccumV1 := ⟨Std.HashMap.emptyWithCapacity 64⟩

private def attrPush
    (acc : AttrAccumV1) (entity : SemanticEntityRefV1) (origin : SourceOrigin) :
    Except ProvenanceBuildErrorV1 AttrAccumV1 := do
  let kb ← match encodeSemanticEntityRefV1 entity with
    | .ok b => pure b
    | .error e => return ← .error (.wire e)
  match acc.table.get? kb with
  | none =>
      pure { table := acc.table.insert kb (entity, #[origin]) }
  | some (_, origins) =>
      pure { table := acc.table.insert kb (entity, origins.push origin) }

private def attrPushPath
    (acc : AttrAccumV1) (idx : OriginIndexV1)
    (entity : SemanticEntityRefV1) (path : NormalizedSyntacticPathV1) :
    Except ProvenanceBuildErrorV1 AttrAccumV1 := do
  let o ← originAt idx path
  attrPush acc entity o

/-- Local env for body attribution (mirrors Normalize bare-name resolution). -/
private structure AttrEnvV1 where
  -- name → ValueId (params only; state loads create new values)
  bindings : Array (String × ValueIdV1)

private def envLookupAttr (env : AttrEnvV1) (name : String) : Option ValueIdV1 :=
  env.bindings.findSome? fun (n, vid) => if n == name then some vid else none

private def envInsertAttr (env : AttrEnvV1) (name : String) (vid : ValueIdV1) :
    AttrEnvV1 :=
  ⟨env.bindings.push (name, vid)⟩

/-- State name set for bare-place resolution. -/
private structure StateNamesV1 where
  names : Array String

private def stateHas (s : StateNamesV1) (name : String) : Bool :=
  s.names.contains name

/-- Body attribution state: next ValueId + instruction index + env. -/
private structure BodyAttrV1 where
  nextValueId : ValueIdV1
  nextInstr : Nat
  env : AttrEnvV1
  acc : AttrAccumV1

private def attrPlace
    (callableId : CallableIdV1)
    (place : SrcPlace) (placePath : NormalizedSyntacticPathV1)
    (st : BodyAttrV1) (states : StateNamesV1) (idx : OriginIndexV1) :
    Except ProvenanceBuildErrorV1 (ValueIdV1 × BodyAttrV1) := do
  match place with
  | .name n =>
      let key := raw n
      match envLookupAttr st.env key with
      | some vid => pure (vid, st)
      | none =>
          unless stateHas states key do
            return ← failUnsupported
              s!"S2 provenance place '{key}' is neither param nor state"
          -- State load instruction + result value at the Place.Name node.
          let vid := st.nextValueId
          let instrEntity :=
            SemanticEntityRefV1.instruction callableId 0 (UInt32.ofNat st.nextInstr)
          let valEntity := SemanticEntityRefV1.value callableId vid
          let acc1 ← attrPushPath st.acc idx instrEntity placePath
          let acc2 ← attrPushPath acc1 idx valEntity placePath
          pure (vid, {
            nextValueId := vid + 1
            nextInstr := st.nextInstr + 1
            env := st.env
            acc := acc2
          })
  | .field _ _ => failUnsupported "S2 provenance does not support field places"
  | .index _ _ => failUnsupported "S2 provenance does not support index places"

private partial def attrExpr
    (callableId : CallableIdV1)
    (expr : SrcExpr) (exprPath : NormalizedSyntacticPathV1)
    (st : BodyAttrV1) (states : StateNamesV1) (idx : OriginIndexV1) :
    Except ProvenanceBuildErrorV1 (ValueIdV1 × BodyAttrV1) := do
  match expr with
  | .place p =>
      let placePath := directChild exprPath "Expr.Place" "place"
      attrPlace callableId p placePath st states idx
  | .binary op lhs rhs =>
      if op == ProofForgeV2.Source.AstV1.BinaryOpV1.add then do
        let lhsPath := directChild exprPath "Expr.Binary" "lhs"
        let rhsPath := directChild exprPath "Expr.Binary" "rhs"
        let (lVid, st1) ← attrExpr callableId lhs lhsPath st states idx
        let (rVid, st2) ← attrExpr callableId rhs rhsPath st1 states idx
        let _ := lVid; let _ := rVid
        let vid := st2.nextValueId
        let instrEntity :=
          SemanticEntityRefV1.instruction callableId 0 (UInt32.ofNat st2.nextInstr)
        let valEntity := SemanticEntityRefV1.value callableId vid
        -- Binary instruction/result bind the binary expression node.
        let acc1 ← attrPushPath st2.acc idx instrEntity exprPath
        let acc2 ← attrPushPath acc1 idx valEntity exprPath
        pure (vid, {
          nextValueId := vid + 1
          nextInstr := st2.nextInstr + 1
          env := st2.env
          acc := acc2
        })
      else
        failUnsupported "S2 provenance supports only binary add"
  | .literal _ => failUnsupported "S2 provenance does not support literals"
  | .constructor _ _ => failUnsupported "S2 provenance does not support constructors"
  | .unary _ _ => failUnsupported "S2 provenance does not support unary"
  | .localCall _ _ => failUnsupported "S2 provenance does not support localCall"
  | .match_ _ _ => failUnsupported "S2 provenance does not support match expr"

private def attrStmt
    (callableId : CallableIdV1)
    (stmt : SrcStmt) (stmtPath : NormalizedSyntacticPathV1)
    (st : BodyAttrV1) (states : StateNamesV1) (idx : OriginIndexV1) :
    Except ProvenanceBuildErrorV1 (BodyAttrV1 × Option Unit) := do
  match stmt with
  | .assign target value => do
      match target with
      | .name n =>
          let key := raw n
          match envLookupAttr st.env key with
          | some _ =>
              failUnsupported
                s!"S2 provenance assign target must be state, not param '{key}'"
          | none =>
              unless stateHas states key do
                return ← failUnsupported
                  s!"S2 provenance assign target '{key}' must be a state place"
              let valuePath := directChild stmtPath "Stmt.Assign" "value"
              let (_vid, st1) ← attrExpr callableId value valuePath st states idx
              let instrEntity :=
                SemanticEntityRefV1.instruction callableId 0
                  (UInt32.ofNat st1.nextInstr)
              -- StateStore binds the assign statement node.
              let acc1 ← attrPushPath st1.acc idx instrEntity stmtPath
              pure ({
                nextValueId := st1.nextValueId
                nextInstr := st1.nextInstr + 1
                env := st1.env
                acc := acc1
              }, none)
      | .field _ _ => failUnsupported "S2 provenance assign field"
      | .index _ _ => failUnsupported "S2 provenance assign index"
  | .return_ none =>
      -- Terminator binds the return statement.
      let termEntity := SemanticEntityRefV1.terminator callableId 0
      let acc1 ← attrPushPath st.acc idx termEntity stmtPath
      pure ({ st with acc := acc1 }, some ())
  | .return_ (some e) => do
      let valuePath := directChild stmtPath "Stmt.Return" "value"
      let (_vid, st1) ← attrExpr callableId e valuePath st states idx
      let termEntity := SemanticEntityRefV1.terminator callableId 0
      let acc1 ← attrPushPath st1.acc idx termEntity stmtPath
      pure ({ st1 with acc := acc1 }, some ())
  | .let_ _ _ _ => failUnsupported "S2 provenance does not support let"
  | .if_ _ _ _ => failUnsupported "S2 provenance does not support if"
  | .match_ _ _ => failUnsupported "S2 provenance does not support match stmt"
  | .for_ _ _ _ _ _ => failUnsupported "S2 provenance does not support for"
  | .assert_ _ _ => failUnsupported "S2 provenance does not support assert"
  | .revert _ _ => failUnsupported "S2 provenance does not support revert"
  | .emit _ _ => failUnsupported "S2 provenance does not support emit"
  | .call _ => failUnsupported "S2 provenance does not support call"
  | .schedule _ => failUnsupported "S2 provenance does not support schedule"

private def attrBlock
    (callableId : CallableIdV1)
    (body : SrcBlock) (blockPath : NormalizedSyntacticPathV1)
    (params : Array (String × ValueIdV1))
    (states : StateNamesV1) (idx : OriginIndexV1)
    (acc0 : AttrAccumV1)
    (allowImplicitReturnNone : Bool) :
    Except ProvenanceBuildErrorV1 AttrAccumV1 := do
  -- Block entity
  let accB ← attrPushPath acc0 idx (SemanticEntityRefV1.block callableId 0) blockPath
  let mut env : AttrEnvV1 := ⟨#[]⟩
  for (name, vid) in params do
    env := envInsertAttr env name vid
  let mut st : BodyAttrV1 := {
    nextValueId := UInt32.ofNat params.size
    nextInstr := 0
    env := env
    acc := accB
  }
  let mut returned := false
  let mut si : Nat := 0
  for stmt in body.statements do
    if returned then
      return ← failUnsupported "S2 provenance: statement after return"
    let stmtPath := childPath blockPath "Block" "statements" si
    let (st', ret?) ← attrStmt callableId stmt stmtPath st states idx
    st := st'
    match ret? with
    | some _ => returned := true
    | none => pure ()
    si := si + 1
  if !returned then
    if allowImplicitReturnNone then
      -- Implicit return none: terminator binds the body block (nearest producer).
      let termEntity := SemanticEntityRefV1.terminator callableId 0
      attrPushPath st.acc idx termEntity blockPath
    else
      failUnsupported "S2 provenance requires explicit return for entry/view"
  else
    pure st.acc

/-- Collect requirement contribution origin paths (all producing sites). -/
private structure ReqSitesV1 where
  -- catalog id → origin paths
  sites : Std.HashMap String (Array NormalizedSyntacticPathV1)

private def emptyReqSites : ReqSitesV1 := ⟨Std.HashMap.emptyWithCapacity 8⟩

private def reqPush
    (rs : ReqSitesV1) (id : String) (path : NormalizedSyntacticPathV1) :
    ReqSitesV1 :=
  match rs.sites.get? id with
  | none => { sites := rs.sites.insert id #[path] }
  | some arr => { sites := rs.sites.insert id (arr.push path) }

mutual
  private partial def reqExprSites
      (expr : SrcExpr) (exprPath : NormalizedSyntacticPathV1)
      (rs : ReqSitesV1) : ReqSitesV1 :=
    match expr with
    | .place p =>
        match p with
        | .name _ => rs
        | .field base _ =>
            reqExprSites (.place base)
              (directChild (directChild exprPath "Expr.Place" "place")
                "Place.Field" "base") rs
        | .index base idx =>
            let placePath := directChild exprPath "Expr.Place" "place"
            let rs1 := reqExprSites (.place base)
              (directChild placePath "Place.Index" "base") rs
            reqExprSites idx (directChild placePath "Place.Index" "index") rs1
    | .binary op lhs rhs =>
        let rs1 := reqExprSites lhs (directChild exprPath "Expr.Binary" "lhs") rs
        let rs2 := reqExprSites rhs (directChild exprPath "Expr.Binary" "rhs") rs1
        if op == ProofForgeV2.Source.AstV1.BinaryOpV1.add ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.sub ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.mul ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.div ||
            op == ProofForgeV2.Source.AstV1.BinaryOpV1.mod then
          let rs3 := reqPush rs2 "value.checked-arithmetic" exprPath
          reqPush rs3 "failure.atomic-rollback" exprPath
        else
          rs2
    | .unary op operand =>
        let rs1 := reqExprSites operand
          (directChild exprPath "Expr.Unary" "operand") rs
        if op == ProofForgeV2.Source.AstV1.UnaryOpV1.neg then
          let rs2 := reqPush rs1 "value.checked-arithmetic" exprPath
          reqPush rs2 "failure.atomic-rollback" exprPath
        else
          rs1
    | .literal _ => rs
    | .constructor _ args =>
        Id.run do
          let mut r := rs
          let mut i := 0
          for a in args do
            r := reqExprSites a (childPath exprPath "Expr.Constructor" "args" i) r
            i := i + 1
          pure r
    | .localCall _ args =>
        Id.run do
          let mut r := rs
          let mut i := 0
          for a in args do
            r := reqExprSites a (childPath exprPath "Expr.LocalCall" "args" i) r
            i := i + 1
          pure r
    | .match_ scrutinee arms =>
        Id.run do
          let mut r := reqExprSites scrutinee
            (directChild exprPath "Expr.Match" "scrutinee") rs
          let mut i := 0
          for arm in arms do
            let armPath := childPath exprPath "Expr.Match" "arms" i
            r := reqExprSites arm.value
              (directChild armPath "ExprMatchArm" "value") r
            i := i + 1
          pure r

  private partial def reqStmtSites
      (stmt : SrcStmt) (stmtPath : NormalizedSyntacticPathV1)
      (rs : ReqSitesV1) : ReqSitesV1 :=
    match stmt with
    | .let_ _ _ value =>
        reqExprSites value (directChild stmtPath "Stmt.Let" "value") rs
    | .assign _ value =>
        reqExprSites value (directChild stmtPath "Stmt.Assign" "value") rs
    | .if_ cond thenB elseB? =>
        let rs1 := reqExprSites cond
          (directChild stmtPath "Stmt.If" "condition") rs
        let rs2 := reqBlockSites thenB
          (directChild stmtPath "Stmt.If" "thenBlock") rs1
        match elseB? with
        | some b =>
            reqBlockSites b (directChild stmtPath "Stmt.If" "elseBlock") rs2
        | none => rs2
    | .match_ scrutinee arms =>
        Id.run do
          let mut r := reqExprSites scrutinee
            (directChild stmtPath "Stmt.Match" "scrutinee") rs
          let mut i := 0
          for arm in arms do
            let armPath := childPath stmtPath "Stmt.Match" "arms" i
            r := reqBlockSites arm.body
              (directChild armPath "StmtMatchArm" "body") r
            i := i + 1
          pure r
    | .for_ _ start endEx _ body =>
        let rs1 := reqExprSites start
          (directChild stmtPath "Stmt.For" "start") rs
        let rs2 := reqExprSites endEx
          (directChild stmtPath "Stmt.For" "endExclusive") rs1
        reqBlockSites body (directChild stmtPath "Stmt.For" "body") rs2
    | .assert_ cond _ =>
        let rs1 := reqExprSites cond
          (directChild stmtPath "Stmt.Assert" "condition") rs
        reqPush rs1 "failure.atomic-rollback" stmtPath
    | .revert _ args =>
        Id.run do
          let mut r := reqPush rs "failure.atomic-rollback" stmtPath
          let mut i := 0
          for a in args do
            r := reqExprSites a (childPath stmtPath "Stmt.Revert" "args" i) r
            i := i + 1
          pure r
    | .emit _ args =>
        Id.run do
          let mut r := rs
          let mut i := 0
          for a in args do
            r := reqExprSites a (childPath stmtPath "Stmt.Emit" "args" i) r
            i := i + 1
          pure r
    | .return_ value? =>
        match value? with
        | some e =>
            reqExprSites e (directChild stmtPath "Stmt.Return" "value") rs
        | none => rs
    | .call call =>
        Id.run do
          let mut r := rs
          let callPath := directChild stmtPath "Stmt.Call" "call"
          let mut i := 0
          for a in call.args do
            r := reqExprSites a
              (childPath callPath "ExternalCallExpr" "args" i) r
            i := i + 1
          pure r
    | .schedule call =>
        Id.run do
          let mut r := rs
          let callPath := directChild stmtPath "Stmt.Schedule" "call"
          let mut i := 0
          for a in call.args do
            r := reqExprSites a
              (childPath callPath "ExternalCallExpr" "args" i) r
            i := i + 1
          pure r

  private partial def reqBlockSites
      (block : SrcBlock) (blockPath : NormalizedSyntacticPathV1)
      (rs : ReqSitesV1) : ReqSitesV1 :=
    Id.run do
      let mut r := rs
      let mut i := 0
      for stmt in block.statements do
        r := reqStmtSites stmt (childPath blockPath "Block" "statements" i) r
        i := i + 1
      pure r
end

private def tryBindType
    (acc : AttrAccumV1) (idx : OriginIndexV1)
    (typeBound : Array Bool) (tid : TypeIdV1)
    (path : NormalizedSyntacticPathV1) :
    Except ProvenanceBuildErrorV1 (AttrAccumV1 × Array Bool) := do
  let i := tid.toNat
  if i < typeBound.size && !(typeBound[i]!) then
    let acc' ← attrPushPath acc idx (.typeRef tid) path
    pure (acc', typeBound.set! i true)
  else
    pure (acc, typeBound)

/-- Attribute all S1 Counter-surface entities from source AST + semantic data. -/
private def attributeCounterEntitiesV1
    (source : ValidatedSourceV1)
    (data : SemanticProgramDataV1)
    (idx : OriginIndexV1) :
    Except ProvenanceBuildErrorV1 AttrAccumV1 := do
  let program := source.program
  let mut acc := emptyAttr
  let mut stateNames : Array String := #[]
  let mut stateItemIdxs : Array Nat := #[]
  let mut itemIdx : Nat := 0
  for item in program.items do
    match item with
    | .state s =>
        stateNames := stateNames.push (raw s.name)
        stateItemIdxs := stateItemIdxs.push itemIdx
    | _ => pure ()
    itemIdx := itemIdx + 1
  let states : StateNamesV1 := ⟨stateNames⟩
  unless stateItemIdxs.size == data.logicalState.size do
    return ← failUnsupported
      "S2 provenance: state count mismatch vs semantic logicalState"

  -- Types: first-seen UInt64 from first public state type node; Unit from first
  -- init decl (nearest producing; no source Type.Unit on S1 init result).
  let mut typeBound : Array Bool := Array.replicate data.types.size false

  -- States + first UInt64 type
  let mut si : Nat := 0
  for itemI in stateItemIdxs do
    let itemPath := childPath #[] "Program" "items" itemI
    let some stateRow := data.logicalState[si]? |
      return ← failUnsupported "S2 provenance: missing logicalState row"
    acc ← attrPushPath acc idx (.state stateRow.id) itemPath
    let typePath := directChild itemPath "StateDecl" "type"
    match program.items[itemI]? with
    | some (.state s) =>
        match s.type_ with
        | .uint 64 =>
            let (acc', tb) ← tryBindType acc idx typeBound stateRow.typeId typePath
            acc := acc'
            typeBound := tb
        | _ => pure ()
    | _ => pure ()
    si := si + 1

  -- Callables in source order among init/entry/view
  let mut callableId : Nat := 0
  itemIdx := 0
  for item in program.items do
    let itemPath := childPath #[] "Program" "items" itemIdx
    match item with
    | .state _ => pure ()
    | .init d =>
        let some c := data.callables[callableId]? |
          return ← failUnsupported "S2 provenance: missing init callable"
        unless c.kind == .initializer do
          return ← failUnsupported "S2 provenance: callable kind mismatch (init)"
        let cid : CallableIdV1 := UInt32.ofNat callableId
        acc ← attrPushPath acc idx (.callable cid) itemPath
        -- Unit result type (synthetic): nearest producer is InitDecl.
        let (accU, tbU) ← tryBindType acc idx typeBound c.result.typeId itemPath
        acc := accU
        typeBound := tbU
        let mut params : Array (String × ValueIdV1) := #[]
        let mut pi : Nat := 0
        for p in d.params do
          let paramPath := childPath itemPath "InitDecl" "params" pi
          let some sp := c.params[pi]? |
            return ← failUnsupported "S2 provenance: init param count mismatch"
          acc ← attrPushPath acc idx (.value cid sp.valueId) paramPath
          let pTypePath := directChild paramPath "Param" "type"
          let (accP, tbP) ← tryBindType acc idx typeBound sp.typeId pTypePath
          acc := accP
          typeBound := tbP
          params := params.push (raw p.name, sp.valueId)
          pi := pi + 1
        let bodyPath := directChild itemPath "InitDecl" "body"
        acc ← attrBlock cid d.body bodyPath params states idx acc true
        callableId := callableId + 1
    | .entry e =>
        let some c := data.callables[callableId]? |
          return ← failUnsupported "S2 provenance: missing entry callable"
        unless c.kind == .entry do
          return ← failUnsupported "S2 provenance: callable kind mismatch (entry)"
        let cid : CallableIdV1 := UInt32.ofNat callableId
        acc ← attrPushPath acc idx (.callable cid) itemPath
        let mut params : Array (String × ValueIdV1) := #[]
        let mut pi : Nat := 0
        for p in e.params do
          let paramPath := childPath itemPath "EntryDecl" "params" pi
          let some sp := c.params[pi]? |
            return ← failUnsupported "S2 provenance: entry param count mismatch"
          acc ← attrPushPath acc idx (.value cid sp.valueId) paramPath
          let pTypePath := directChild paramPath "Param" "type"
          let (accP, tbP) ← tryBindType acc idx typeBound sp.typeId pTypePath
          acc := accP
          typeBound := tbP
          params := params.push (raw p.name, sp.valueId)
          pi := pi + 1
        let resultPath := directChild itemPath "EntryDecl" "result"
        let (accR, tbR) ← tryBindType acc idx typeBound c.result.typeId resultPath
        acc := accR
        typeBound := tbR
        let bodyPath := directChild itemPath "EntryDecl" "body"
        acc ← attrBlock cid e.body bodyPath params states idx acc false
        callableId := callableId + 1
    | .view v =>
        let some c := data.callables[callableId]? |
          return ← failUnsupported "S2 provenance: missing view callable"
        unless c.kind == .view do
          return ← failUnsupported "S2 provenance: callable kind mismatch (view)"
        let cid : CallableIdV1 := UInt32.ofNat callableId
        acc ← attrPushPath acc idx (.callable cid) itemPath
        let mut params : Array (String × ValueIdV1) := #[]
        let mut pi : Nat := 0
        for p in v.params do
          let paramPath := childPath itemPath "ViewDecl" "params" pi
          let some sp := c.params[pi]? |
            return ← failUnsupported "S2 provenance: view param count mismatch"
          acc ← attrPushPath acc idx (.value cid sp.valueId) paramPath
          let pTypePath := directChild paramPath "Param" "type"
          let (accP, tbP) ← tryBindType acc idx typeBound sp.typeId pTypePath
          acc := accP
          typeBound := tbP
          params := params.push (raw p.name, sp.valueId)
          pi := pi + 1
        let resultPath := directChild itemPath "ViewDecl" "result"
        let (accR, tbR) ← tryBindType acc idx typeBound c.result.typeId resultPath
        acc := accR
        typeBound := tbR
        let bodyPath := directChild itemPath "ViewDecl" "body"
        acc ← attrBlock cid v.body bodyPath params states idx acc false
        callableId := callableId + 1
    | .struct _ | .enum _ | .const _ | .event _ | .error _ | .fn _
    | .invariant _ | .extensionReq _ | .proof _ =>
        return ← failUnsupported
          "S2 provenance attribution only supports state/init/entry/view"
    itemIdx := itemIdx + 1
  unless callableId == data.callables.size do
    return ← failUnsupported "S2 provenance: callable count mismatch"

  -- Ensure every type got a binding (fail closed if interned type unused).
  for i in [:data.types.size] do
    unless typeBound[i]! do
      return ← failUnsupported
        s!"S2 provenance: type TypeId {i} has no producing source node"

  -- Requirements: collect all producing sites, map catalog id → requirement index.
  let mut rs := emptyReqSites
  for itemI in stateItemIdxs do
    let itemPath := childPath #[] "Program" "items" itemI
    rs := reqPush rs "state.persistent" itemPath
  itemIdx := 0
  for item in program.items do
    let itemPath := childPath #[] "Program" "items" itemIdx
    match item with
    | .init d =>
        rs := reqBlockSites d.body (directChild itemPath "InitDecl" "body") rs
    | .entry e =>
        rs := reqBlockSites e.body (directChild itemPath "EntryDecl" "body") rs
    | .view v =>
        rs := reqBlockSites v.body (directChild itemPath "ViewDecl" "body") rs
    | _ => pure ()
    itemIdx := itemIdx + 1

  let mut ri : Nat := 0
  for req in data.requirements.items do
    match rs.sites.get? req.id with
    | none =>
        return ← failUnsupported
          s!"S2 provenance requirement missing producing site id={req.id} index={ri}"
    | some paths =>
        if paths.isEmpty then
          return ← failUnsupported
            s!"S2 provenance requirement empty producing sites id={req.id} index={ri}"
        for p in paths do
          acc ← attrPushPath acc idx (.requirement (UInt32.ofNat ri)) p
    ri := ri + 1

  pure acc

private def finalizeOriginMap
    (acc : AttrAccumV1)
    (expected : Array SemanticEntityRefV1) :
    Except ProvenanceBuildErrorV1 (Array OriginBindingV1) := do
  -- Ensure every expected entity was attributed.
  let mut bindings : Array OriginBindingV1 := #[]
  for entity in expected do
    let kb ← match encodeSemanticEntityRefV1 entity with
      | .ok b => pure b
      | .error e => return ← .error (.wire e)
    match acc.table.get? kb with
    | none =>
        return ← failUnsupported
          s!"S2 provenance missing attribution for entity"
    | some (_, origins) =>
        let sorted ← sortOriginsUnique origins
        bindings := bindings.push { entity, origins := sorted }
  -- Reject extra attributed entities not in expected set.
  unless acc.table.size == expected.size do
    return ← failUnsupported
      s!"S2 provenance attribution size {acc.table.size} != expected {expected.size}"
  sortOriginMap bindings

/-- Low-level provenance builder (caller-trusted inventory; **not** authority).

    Reconstructs the NormalizeV1 Counter-surface producing path for every
    semantic entity, joins each path to the supplied inventory origin, and
    revalidates via Wire `validateSemanticProvenanceJoinV1`. Callers that
    supply a mutated inventory can self-certify at this layer. Complete
    authority is `NormalizeV1.validateSemanticProvenanceV1`, which rebuilds
    inventory from trusted path+spans before rebuild/compare.
-/
def buildSemanticProvenanceV1
    (source : ValidatedSourceV1)
    (program : SemanticProgramV1)
    (inventory : SourceNodeInventoryV1) :
    Except ProvenanceBuildErrorV1 SemanticProvenanceV1 := do
  let data ← match validateSemanticProgramV1 program with
    | .ok d => pure d
    | .error e => return ← .error (.wire e)
  let qn ← sourceIdentityToQualifiedNameV1 source.programIdentity
  unless qn == data.qualifiedName do
    return ← failIdentity
      "source identity does not match semantic program qualifiedName"
  let moduleQn ← sourceQualifiedNameToCommonV1 source.moduleName
  -- Authoritative sourceHash from ValidatedSourceV1 (module+identity+AST).
  let sourceHash ← mapString (sourceHashV1 source) "sourceHashV1"
  -- Inventory must exact-join the same snapshot (hash, NodeId set, order).
  validateSourceNodeInventoryExactV1 source inventory
  unless sourceHash == inventory.sourceHash do
    return ← failInventory "inventory.sourceHash does not match sourceHashV1"
  let semanticHash ← match semanticHashV1 program with
    | .ok h => pure h
    | .error e => return ← .error (.wire e)
  let schema ← match parseSchemaId semanticProvenanceSchemaIdV1 with
    | .ok s => pure s
    | .error e => return ← failIdentity e
  let idx ← buildOriginIndexV1 source inventory
  let acc ← attributeCounterEntitiesV1 source data idx
  let expected := collectProgramEntityRefsV1 data
  let originMap ← finalizeOriginMap acc expected
  let provenance : SemanticProvenanceV1 := {
    schema
    qualifiedName := qn
    sourceHash
    semanticHash
    originMap
  }
  -- Low-level Wire join helper (not source-bound authority; rebuild identity).
  match validateSemanticProvenanceJoinV1
      moduleQn qn sourceHash originMap inventory program provenance with
  | .ok () => pure provenance
  | .error e => .error (.wire e)

/-- Low-level attribution rebuild (caller-trusted inventory; **not** authority).

    Does **not** re-normalize the carrier and does **not** rebuild inventory
    from spans. Source-bound authority is `NormalizeV1.validateSemanticProvenanceV1`.
-/
def rebuildSemanticProvenanceV1
    (source : ValidatedSourceV1)
    (program : SemanticProgramV1)
    (inventory : SourceNodeInventoryV1) :
    Except ProvenanceBuildErrorV1 SemanticProvenanceV1 :=
  buildSemanticProvenanceV1 source program inventory

end ProofForgeV2.Semantic.ProvenanceV1
