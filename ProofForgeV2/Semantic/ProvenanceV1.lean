/-
  ProofForgeV2.Semantic.ProvenanceV1 — S2 SemanticProvenanceV1 builder for the
  supported NormalizeV1 Counter / S1 surface.

  Builds a complete originMap for every semantic entity of a structure-gated
  SemanticProgramV1 carrier, joined to a production SourceNodeInventoryV1
  derived from assignNodeIdsV1 + SpanJoin spans + sourceHashV1.

  Attribution is exact and deterministic for the shipped Counter-like subset,
  including expected-UInt64 integer literals: each state/callable/block/
  instruction/value/terminator/type/requirement binds
  to its declaration, expression, statement, or nearest producing source NodeId
  (reconstructed by the same AST walk NormalizeV1 uses). Multi-origin
  requirements collect every producing site and sort uniquely by SourceOrigin
  wire key. Synthetic Unit types and implicit init return terminators bind the
  nearest producing declaration/block node — never an arbitrary inventory pick.

  Inventory construction is exact and Source-owned: `buildSourceNodeInventoryV1`
  is a thin projection of `Source.OriginJoinV1.joinOriginsV1`. Duplicate span
  paths, missing/extra paths, duplicate/nonascending NodeIds, and count
  mismatches fail closed before any originMap is emitted.

  Path HashMap keys use Source length-framed `pathLookupKeyV1` (collision-free;
  not delimiter concatenation). Requirement missing producing sites fail closed
  (no program-root fallback).

  Low-level only (caller-trusted; not complete authority):
    * `buildSourceNodeInventoryV1` (thin Source projection) /
      `buildSemanticProvenanceV1` / `rebuildSemanticProvenanceV1`
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
import ProofForgeV2.Semantic.RequirementIdsV1
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
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import Std.Data.HashMap

namespace ProofForgeV2.Semantic.ProvenanceV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.RequirementIdsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.OriginJoinV1
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

/-- Default for mutual-partial inhabitedness only; never produced by the
    attribution paths (they always fail or succeed explicitly). -/
instance : Inhabited ProvenanceBuildErrorV1 := ⟨.unsupported "unreachable"⟩

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

/-- Thin projection of Source `joinOriginsV1` into wire `SourceNodeInventoryV1`.

    Exact NodeId×span construction and length-framed path keys are owned by
    `ProofForgeV2.Source.OriginJoinV1`. This helper preserves identity-vs-inventory
    error priority and does not re-implement span join.
-/
def buildSourceNodeInventoryV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    Except ProvenanceBuildErrorV1 SourceNodeInventoryV1 :=
  match joinOriginsV1 source sourcePath spans with
  | .ok inv =>
      .ok {
        sourceHash := originInventorySourceHashV1 inv
        nodes := originInventoryOriginsV1 inv
      }
  | .error (.identity detail) => failIdentity detail
  | .error (.inventory detail) => failInventory detail

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
  blockId : Nat
  nextBlockId : Nat
  nextBlockParamOrdinal : Nat
  callableParamCount : Nat
  nextEffectId : UInt32
  env : AttrEnvV1
  acc : AttrAccumV1

/-- Mirror of NormalizeV1.countForLoopsStmtsV1: every lowered `for`
allocates exactly one loop-header block param, so this syntactic count sizes
the canonical block-param ValueId range before instruction results begin. -/
private partial def countForLoopsStmtsV1 (stmts : Array SrcStmt) : Nat :=
  stmts.foldl (fun acc stmt => acc + countForLoopsStmtV1 stmt) 0
where
  countForLoopsStmtV1 : SrcStmt → Nat
    | .if_ _ thenBlock elseBlock? =>
        countForLoopsStmtsV1 thenBlock.statements +
          (elseBlock?.map (fun b => countForLoopsStmtsV1 b.statements)).getD 0
    | .match_ _ arms =>
        arms.foldl (fun acc arm => acc + countForLoopsStmtsV1 arm.body.statements) 0
    | .for_ _ _ _ _ body => 1 + countForLoopsStmtsV1 body.statements
    | _ => 0

/-- Mirror of the normalizer's per-path status for attribution. -/
private inductive AttrPathStatusV1 where
  | open_
  | closed
  deriving BEq

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
            SemanticEntityRefV1.instruction callableId (UInt32.ofNat st.blockId) (UInt32.ofNat st.nextInstr)
          let valEntity := SemanticEntityRefV1.value callableId vid
          let acc1 ← attrPushPath st.acc idx instrEntity placePath
          let acc2 ← attrPushPath acc1 idx valEntity placePath
          pure (vid, { st with
            nextValueId := vid + 1
            nextInstr := st.nextInstr + 1
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
      let srcOp := op
      let isSupported := srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.add ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.sub ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mul ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.div ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mod ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.eq ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ne ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.lt ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.le ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.gt ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ge ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitAnd ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitOr ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitXor ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shl ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shr ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalAnd ||
        srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalOr
      if isSupported then do
        let lhsPath := directChild exprPath "Expr.Binary" "lhs"
        let rhsPath := directChild exprPath "Expr.Binary" "rhs"
        let (lVid, st1) ← attrExpr callableId lhs lhsPath st states idx
        let (rVid, st2) ← attrExpr callableId rhs rhsPath st1 states idx
        let _ := lVid; let _ := rVid
        let vid := st2.nextValueId
        let instrEntity :=
          SemanticEntityRefV1.instruction callableId (UInt32.ofNat st2.blockId) (UInt32.ofNat st2.nextInstr)
        let valEntity := SemanticEntityRefV1.value callableId vid
        -- Binary instruction/result bind the binary expression node.
        let acc1 ← attrPushPath st2.acc idx instrEntity exprPath
        let acc2 ← attrPushPath acc1 idx valEntity exprPath
        pure (vid, { st2 with
          nextValueId := vid + 1
          nextInstr := st2.nextInstr + 1
          acc := acc2
        })
      else
        failUnsupported "S2 provenance supports only binary arithmetic, bitwise, shift, comparison, and logical operators"
  | .literal literal =>
      match literal with
      | .integer magnitude => do
          unless magnitude < UInt64.size do
            return ← failUnsupported "S2 provenance UInt64 literal out of range"
          let vid := st.nextValueId
          let instrEntity :=
            SemanticEntityRefV1.instruction callableId (UInt32.ofNat st.blockId) (UInt32.ofNat st.nextInstr)
          let valEntity := SemanticEntityRefV1.value callableId vid
          -- Op.Literal and its result bind the literal expression itself.
          let acc1 ← attrPushPath st.acc idx instrEntity exprPath
          let acc2 ← attrPushPath acc1 idx valEntity exprPath
          pure (vid, { st with
            nextValueId := vid + 1
            nextInstr := st.nextInstr + 1
            acc := acc2
          })
      | .bool _ => do
          let vid := st.nextValueId
          let instrEntity :=
            SemanticEntityRefV1.instruction callableId (UInt32.ofNat st.blockId) (UInt32.ofNat st.nextInstr)
          let valEntity := SemanticEntityRefV1.value callableId vid
          -- Bool Op.Literal and its result bind the literal expression itself.
          let acc1 ← attrPushPath st.acc idx instrEntity exprPath
          let acc2 ← attrPushPath acc1 idx valEntity exprPath
          pure (vid, { st with
            nextValueId := vid + 1
            nextInstr := st.nextInstr + 1
            acc := acc2
          })
      | .string _ =>
          failUnsupported "S2 provenance supports only UInt64/Bool literals"
  | .constructor _ _ => failUnsupported "S2 provenance does not support constructors"
  | .unary op operand => do
      let operandPath := directChild exprPath "Expr.Unary" "operand"
      let (_vid, st1) ← attrExpr callableId operand operandPath st states idx
      match op with
      | .neg =>
          -- Checked negation desugars to `0 - x` in the normalizer: the
          -- synthesized zero literal and the subtraction instruction/value
          -- entities both bind the unary expression node, in evaluation
          -- order (literal first, then the binary).
          let zeroVid := st1.nextValueId
          let zeroInstrEntity :=
            SemanticEntityRefV1.instruction callableId (UInt32.ofNat st1.blockId)
              (UInt32.ofNat st1.nextInstr)
          let zeroValEntity := SemanticEntityRefV1.value callableId zeroVid
          let acc1 ← attrPushPath st1.acc idx zeroInstrEntity exprPath
          let acc2 ← attrPushPath acc1 idx zeroValEntity exprPath
          let vid := zeroVid + 1
          let subInstrEntity :=
            SemanticEntityRefV1.instruction callableId (UInt32.ofNat st1.blockId)
              (UInt32.ofNat (st1.nextInstr + 1))
          let subValEntity := SemanticEntityRefV1.value callableId vid
          let acc3 ← attrPushPath acc2 idx subInstrEntity exprPath
          let acc4 ← attrPushPath acc3 idx subValEntity exprPath
          pure (vid, { st1 with
            nextValueId := vid + 1
            nextInstr := st1.nextInstr + 2
            acc := acc4
          })
      | _ => do
          -- Op.Unary and its result bind the unary expression itself (operand
          -- attributes first, mirroring the normalizer's evaluation order).
          let vid := st1.nextValueId
          let instrEntity :=
            SemanticEntityRefV1.instruction callableId (UInt32.ofNat st1.blockId) (UInt32.ofNat st1.nextInstr)
          let valEntity := SemanticEntityRefV1.value callableId vid
          let acc1 ← attrPushPath st1.acc idx instrEntity exprPath
          let acc2 ← attrPushPath acc1 idx valEntity exprPath
          pure (vid, { st1 with
            nextValueId := vid + 1
            nextInstr := st1.nextInstr + 1
            acc := acc2
          })
  | .localCall _ args => do
      -- PureCall instruction and its result bind the local-call expression;
      -- each argument attributes in call order (mirroring the normalizer).
      let mut st' := st
      let mut i := 0
      for arg in args do
        let argPath := childPath exprPath "Expr.LocalCall" "args" i
        let (_avid, st1) ← attrExpr callableId arg argPath st' states idx
        st' := st1
        i := i + 1
      let vid := st'.nextValueId
      let instrEntity :=
        SemanticEntityRefV1.instruction callableId (UInt32.ofNat st'.blockId) (UInt32.ofNat st'.nextInstr)
      let valEntity := SemanticEntityRefV1.value callableId vid
      let acc1 ← attrPushPath st'.acc idx instrEntity exprPath
      let acc2 ← attrPushPath acc1 idx valEntity exprPath
      pure (vid, { st' with
        nextValueId := vid + 1
        nextInstr := st'.nextInstr + 1
        acc := acc2
      })
  | .match_ _ _ => failUnsupported "S2 provenance does not support match expr"

mutual

/-- Attribute one statement list in the current open block (mirrors
    NormalizeV1.lowerStmts: closed path + trailing statements fail). -/
private partial def attrStmts
    (callableId : CallableIdV1)
    (stmts : Array SrcStmt) (blockPath : NormalizedSyntacticPathV1)
    (st : BodyAttrV1) (states : StateNamesV1) (idx : OriginIndexV1) :
    Except ProvenanceBuildErrorV1 (BodyAttrV1 × AttrPathStatusV1) := do
  let mut st := st
  let mut si : Nat := 0
  for stmt in stmts do
    let stmtPath := childPath blockPath "Block" "statements" si
    let (st', status) ← attrStmt callableId stmt stmtPath st states idx
    st := st'
    if status == .closed then
      if si + 1 < stmts.size then
        return ← failUnsupported "S2 provenance: statement after return"
      else
        return (st, .closed)
    si := si + 1
  pure (st, .open_)

private partial def attrStmt
    (callableId : CallableIdV1)
    (stmt : SrcStmt) (stmtPath : NormalizedSyntacticPathV1)
    (st : BodyAttrV1) (states : StateNamesV1) (idx : OriginIndexV1) :
    Except ProvenanceBuildErrorV1 (BodyAttrV1 × AttrPathStatusV1) := do
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
                SemanticEntityRefV1.instruction callableId
                  (UInt32.ofNat st.blockId) (UInt32.ofNat st1.nextInstr)
              -- StateStore binds the assign statement node.
              let acc1 ← attrPushPath st1.acc idx instrEntity stmtPath
              pure ({ st1 with
                nextInstr := st1.nextInstr + 1
                acc := acc1
              }, .open_)
      | .field _ _ => failUnsupported "S2 provenance assign field"
      | .index _ _ => failUnsupported "S2 provenance assign index"
  | .return_ none =>
      failUnsupported "S2 provenance does not support bare return"
  | .return_ (some e) => do
      let valuePath := directChild stmtPath "Stmt.Return" "value"
      let (_vid, st1) ← attrExpr callableId e valuePath st states idx
      let termEntity := SemanticEntityRefV1.terminator callableId
        (UInt32.ofNat st.blockId)
      let acc1 ← attrPushPath st1.acc idx termEntity stmtPath
      pure ({ st1 with acc := acc1 }, .closed)
  | .assert_ condition errorRef => do
      match errorRef with
      | some _ =>
          failUnsupported "S2 provenance does not support assert-else"
      | none => do
          let condPath := directChild stmtPath "Stmt.Assert" "condition"
          let (_vid, st1) ← attrExpr callableId condition condPath st states idx
          let instrEntity :=
            SemanticEntityRefV1.instruction callableId
              (UInt32.ofNat st.blockId) (UInt32.ofNat st1.nextInstr)
          -- Void Op.Assert binds the assert statement node (no value entity).
          let acc1 ← attrPushPath st1.acc idx instrEntity stmtPath
          pure ({ st1 with
            nextInstr := st1.nextInstr + 1
            acc := acc1
          }, .open_)
  | .if_ condition thenBlock elseBlock? => do
      let condPath := directChild stmtPath "Stmt.If" "condition"
      let (_condVid, st1) ← attrExpr callableId condition condPath st states idx
      -- Branch terminator binds the if statement.
      let branchEntity := SemanticEntityRefV1.terminator callableId
        (UInt32.ofNat st.blockId)
      let accB ← attrPushPath st1.acc idx branchEntity stmtPath
      -- Arms start from the pre-branch env; lets stay scoped to their arm
      -- (mirroring the normalizer's env save/restore).
      let savedEnv := st1.env
      -- Then block: fresh block id in creation order.
      let thenId := st1.nextBlockId
      let thenPath := directChild stmtPath "Stmt.If" "thenBlock"
      let accT ← attrPushPath accB idx
        (SemanticEntityRefV1.block callableId (UInt32.ofNat thenId)) thenPath
      let stT0 : BodyAttrV1 := { st1 with
        blockId := thenId, nextBlockId := thenId + 1, nextInstr := 0,
        env := savedEnv, acc := accT }
      let (stT, thenStatus) ← attrStmts callableId
        thenBlock.statements thenPath stT0 states idx
      let (stT, thenOpen) ← match thenStatus with
        | .closed => pure (stT, false)
        | .open_ => do
            -- Open then-branch gets a jump terminator bound to the if statement.
            let jumpEntity := SemanticEntityRefV1.terminator callableId
              (UInt32.ofNat stT.blockId)
            let accJ ← attrPushPath stT.acc idx jumpEntity stmtPath
            pure ({ stT with acc := accJ }, true)
      -- Else path: an absent else falls into the join without a block or
      -- terminator entity (matching the normalizer exactly).
      let (stE, elseJumpBinds, elseClosed) ← match elseBlock? with
        | some elseBlock => do
            let elseId := stT.nextBlockId
            let elsePath := directChild stmtPath "Stmt.If" "elseBlock"
            let accE ← attrPushPath stT.acc idx
              (SemanticEntityRefV1.block callableId (UInt32.ofNat elseId)) elsePath
            let stE0 : BodyAttrV1 := { stT with
              blockId := elseId, nextBlockId := elseId + 1, nextInstr := 0,
              env := savedEnv, acc := accE }
            let (stE1, status) ← attrStmts callableId
              elseBlock.statements elsePath stE0 states idx
            match status with
            | .closed => pure (stE1, false, true)
            | .open_ => do
                let jumpEntity := SemanticEntityRefV1.terminator callableId
                  (UInt32.ofNat stE1.blockId)
                let accJ ← attrPushPath stE1.acc idx jumpEntity stmtPath
                pure ({ stE1 with acc := accJ }, true, false)
        | none => pure (stT, false, false)
      if !thenOpen && elseClosed then
        pure (stE, .closed)
      else
        -- Join block: nearest producing node is the if statement itself.
        let joinId := stE.nextBlockId
        let accJoin ← attrPushPath stE.acc idx
          (SemanticEntityRefV1.block callableId (UInt32.ofNat joinId)) stmtPath
        pure ({ stE with
          blockId := joinId, nextBlockId := joinId + 1, nextInstr := 0,
          env := savedEnv, acc := accJoin }, .open_)
  | .match_ scrutinee arms => do
      if arms.isEmpty then
        return ← failUnsupported "S2 provenance match requires at least one arm"
      let scrutPath := directChild stmtPath "Stmt.Match" "scrutinee"
      let (_scrutVid, st1) ← attrExpr callableId scrutinee scrutPath st states idx
      -- Split arms exactly like the normalizer (literal cases / catch-all).
      let mut caseIdxs : Array Nat := #[]
      let mut defaultIdx? : Option Nat := none
      let mut ai : Nat := 0
      for arm in arms do
        match arm.pattern with
        | .literal _ =>
            caseIdxs := caseIdxs.push ai
        | .wildcard | .bind _ =>
            if defaultIdx?.isSome then
              return ← failUnsupported "S2 provenance match has multiple catch-alls"
            defaultIdx? := some ai
        | .constructor _ _ =>
            return ← failUnsupported "S2 provenance does not support constructor patterns"
        ai := ai + 1
      let defaultIdx ← match defaultIdx? with
        | some d => pure d
        | none =>
            return ← failUnsupported
              "S2 provenance match on UInt64/Bool requires a catch-all arm"
      -- Switch terminator binds the match statement (a catch-all-only match
      -- is straight-line: no block or terminator entity is produced).
      let termEntity := SemanticEntityRefV1.terminator callableId
        (UInt32.ofNat st.blockId)
      let accS ← if caseIdxs.isEmpty then pure st1.acc
        else attrPushPath st1.acc idx termEntity stmtPath
      let stS := { st1 with acc := accS }
      -- Arms start from the pre-match env; lets stay scoped to their arm.
      let savedEnv := st1.env
      if caseIdxs.isEmpty then
        -- Catch-all-only match: straight-line — the arm body attributes inline
        -- into the current block (binder env only; no block/terminator entity).
        let some arm := arms[defaultIdx]? |
          return ← failUnsupported "S2 provenance match arm index out of range"
        let armPath := childPath stmtPath "Stmt.Match" "arms" defaultIdx
        let bodyPath := directChild armPath "StmtMatchArm" "body"
        let envD := match arm.pattern with
          | .bind name => envInsertAttr savedEnv (raw name) _scrutVid
          | _ => savedEnv
        let stD := { stS with env := envD }
        let (stR, rStatus) ← attrStmts callableId arm.body.statements bodyPath stD states idx
        pure ({ stR with env := savedEnv }, rStatus)
      else
        let orderedArmIdxs := caseIdxs ++ #[defaultIdx]
        let mut stA := stS
        let mut openCount : Nat := 0
        for armIdx in orderedArmIdxs do
          let some arm := arms[armIdx]? |
            return ← failUnsupported "S2 provenance match arm index out of range"
          let armPath := childPath stmtPath "Stmt.Match" "arms" armIdx
          let armBlockId := stA.nextBlockId
          let bodyPath := directChild armPath "StmtMatchArm" "body"
          let accA ← attrPushPath stA.acc idx
            (SemanticEntityRefV1.block callableId (UInt32.ofNat armBlockId)) bodyPath
          -- A bind arm's binder maps to the scrutinee value (same env slot).
          let envA := match arm.pattern with
            | .bind name => envInsertAttr savedEnv (raw name) _scrutVid
            | _ => savedEnv
          let stA0 : BodyAttrV1 := { stA with
            blockId := armBlockId, nextBlockId := armBlockId + 1, nextInstr := 0,
            env := envA, acc := accA }
          let (stB, status) ← attrStmts callableId arm.body.statements bodyPath stA0 states idx
          stA := stB
          match status with
          | .closed => pure ()
          | .open_ => do
              let jumpEntity := SemanticEntityRefV1.terminator callableId
                (UInt32.ofNat stA.blockId)
              let accJ ← attrPushPath stA.acc idx jumpEntity stmtPath
              stA := { stA with acc := accJ }
              openCount := openCount + 1
        if openCount == 0 then
          pure (stA, .closed)
        else
          let joinId := stA.nextBlockId
          let accJoin ← attrPushPath stA.acc idx
            (SemanticEntityRefV1.block callableId (UInt32.ofNat joinId)) stmtPath
          pure ({ stA with
            blockId := joinId, nextBlockId := joinId + 1, nextInstr := 0,
            env := savedEnv, acc := accJoin }, .open_)
  | .let_ name _ value => do
      -- Immutable binding: the RHS attributes its own entities; the let
      -- itself emits no instruction (mirroring the normalizer's env insert).
      let valuePath := directChild stmtPath "Stmt.Let" "value"
      let (vid, st1) ← attrExpr callableId value valuePath st states idx
      pure ({ st1 with env := envInsertAttr st1.env (raw name) vid }, .open_)
  | .for_ binder start endExclusive _bound body => do
      let startPath := directChild stmtPath "Stmt.For" "start"
      let (_sVid, st1) ← attrExpr callableId start startPath st states idx
      let endPath := directChild stmtPath "Stmt.For" "endExclusive"
      let (_eVid, st2) ← attrExpr callableId endExclusive endPath st1 states idx
      -- Pre-header jump terminator binds the for statement.
      let jumpEntity := SemanticEntityRefV1.terminator callableId
        (UInt32.ofNat st2.blockId)
      let accJ ← attrPushPath st2.acc idx jumpEntity stmtPath
      -- Header block and induction param (value id from the canonical
      -- block-param range) both bind the for statement.
      let headerId := st2.nextBlockId
      let iVid := UInt32.ofNat (st2.callableParamCount + st2.nextBlockParamOrdinal)
      let accH ← attrPushPath accJ idx
        (SemanticEntityRefV1.block callableId (UInt32.ofNat headerId)) stmtPath
      let accI ← attrPushPath accH idx
        (SemanticEntityRefV1.value callableId iVid) stmtPath
      -- Header condition (i < endExclusive): instruction and result value
      -- bind the for statement (synthesized comparison).
      let condVid := st2.nextValueId
      let condInstrEntity := SemanticEntityRefV1.instruction callableId
        (UInt32.ofNat headerId) 0
      let condValEntity := SemanticEntityRefV1.value callableId condVid
      let accC1 ← attrPushPath accI idx condInstrEntity stmtPath
      let accC2 ← attrPushPath accC1 idx condValEntity stmtPath
      -- Header branch terminator binds the for statement.
      let branchEntity := SemanticEntityRefV1.terminator callableId
        (UInt32.ofNat headerId)
      let accB ← attrPushPath accC2 idx branchEntity stmtPath
      -- Body block: the binder scopes to the induction param.
      let bodyId := headerId + 1
      let bodyPath := directChild stmtPath "Stmt.For" "body"
      let accBody ← attrPushPath accB idx
        (SemanticEntityRefV1.block callableId (UInt32.ofNat bodyId)) bodyPath
      let stB0 : BodyAttrV1 := { st2 with
        blockId := bodyId
        nextBlockId := bodyId + 1
        nextInstr := 0
        nextValueId := condVid + 1
        nextBlockParamOrdinal := st2.nextBlockParamOrdinal + 1
        env := envInsertAttr st2.env (raw binder) iVid
        acc := accBody
      }
      let (stB, bodyStatus) ← attrStmts callableId body.statements bodyPath stB0 states idx
      let stL ← match bodyStatus with
        | .open_ => do
            -- Latch: synthesized literal 1, increment, and back-edge jump
            -- all bind the for statement.
            let oneVid := stB.nextValueId
            let oneInstrEntity := SemanticEntityRefV1.instruction callableId
              (UInt32.ofNat stB.blockId) (UInt32.ofNat stB.nextInstr)
            let oneValEntity := SemanticEntityRefV1.value callableId oneVid
            let acc1 ← attrPushPath stB.acc idx oneInstrEntity stmtPath
            let acc2 ← attrPushPath acc1 idx oneValEntity stmtPath
            let incVid := oneVid + 1
            let incInstrEntity := SemanticEntityRefV1.instruction callableId
              (UInt32.ofNat stB.blockId) (UInt32.ofNat (stB.nextInstr + 1))
            let incValEntity := SemanticEntityRefV1.value callableId incVid
            let acc3 ← attrPushPath acc2 idx incInstrEntity stmtPath
            let acc4 ← attrPushPath acc3 idx incValEntity stmtPath
            let latchJumpEntity := SemanticEntityRefV1.terminator callableId
              (UInt32.ofNat stB.blockId)
            let acc5 ← attrPushPath acc4 idx latchJumpEntity stmtPath
            pure { stB with
              nextValueId := incVid + 1
              nextBlockId := stB.blockId + 1
              acc := acc5
            }
        -- Body returns/reverts on every path: no latch, no back edge.
        | .closed => pure stB
      -- Exit block binds the for statement; the env is restored so the
      -- binder and body lets stay scoped to the loop.
      let exitId := stL.nextBlockId
      let accX ← attrPushPath stL.acc idx
        (SemanticEntityRefV1.block callableId (UInt32.ofNat exitId)) stmtPath
      pure ({ stL with
        blockId := exitId
        nextBlockId := exitId + 1
        nextInstr := 0
        env := st2.env
        acc := accX
      }, .open_)
  | .revert _ args => do
      -- Args attribute in declaration order; the revert terminator binds the
      -- statement node and closes the path (mirroring the normalizer).
      let mut st' := st
      let mut i := 0
      for arg in args do
        let argPath := childPath stmtPath "Stmt.Revert" "args" i
        let (_vid, st1) ← attrExpr callableId arg argPath st' states idx
        st' := st1
        i := i + 1
      let termEntity := SemanticEntityRefV1.terminator callableId
        (UInt32.ofNat st'.blockId)
      let acc1 ← attrPushPath st'.acc idx termEntity stmtPath
      pure ({ st' with acc := acc1 }, .closed)
  | .emit _ args => do
      -- Args attribute in declaration order; the void Op.Emit instruction and
      -- its EffectId both bind the emit statement node.
      let mut st' := st
      let mut i := 0
      for arg in args do
        let argPath := childPath stmtPath "Stmt.Emit" "args" i
        let (_vid, st1) ← attrExpr callableId arg argPath st' states idx
        st' := st1
        i := i + 1
      let instrEntity := SemanticEntityRefV1.instruction callableId
        (UInt32.ofNat st'.blockId) (UInt32.ofNat st'.nextInstr)
      let acc1 ← attrPushPath st'.acc idx instrEntity stmtPath
      let effectEntity := SemanticEntityRefV1.effect callableId st'.nextEffectId
      let acc2 ← attrPushPath acc1 idx effectEntity stmtPath
      pure ({ st' with
        nextInstr := st'.nextInstr + 1
        nextEffectId := st'.nextEffectId + 1
        acc := acc2
      }, .open_)
  | .call call => do
      -- Args attribute under the nested ExternalCallExpr; the void
      -- Op.ExternalCall instruction and its EffectId both bind the call
      -- statement (same shape as emit).
      let mut st' := st
      let mut i := 0
      let callPath := directChild stmtPath "Stmt.Call" "call"
      for arg in call.args do
        let argPath := childPath callPath "ExternalCallExpr" "args" i
        let (_vid, st1) ← attrExpr callableId arg argPath st' states idx
        st' := st1
        i := i + 1
      let instrEntity := SemanticEntityRefV1.instruction callableId
        (UInt32.ofNat st'.blockId) (UInt32.ofNat st'.nextInstr)
      let acc1 ← attrPushPath st'.acc idx instrEntity stmtPath
      let effectEntity := SemanticEntityRefV1.effect callableId st'.nextEffectId
      let acc2 ← attrPushPath acc1 idx effectEntity stmtPath
      pure ({ st' with
        nextInstr := st'.nextInstr + 1
        nextEffectId := st'.nextEffectId + 1
        acc := acc2
      }, .open_)
  | .schedule call => do
      -- Args attribute under the nested ExternalCallExpr; the void
      -- Op.Schedule instruction and its EffectId both bind the schedule
      -- statement (same shape as emit/call).
      let mut st' := st
      let mut i := 0
      let callPath := directChild stmtPath "Stmt.Schedule" "call"
      for arg in call.args do
        let argPath := childPath callPath "ExternalCallExpr" "args" i
        let (_vid, st1) ← attrExpr callableId arg argPath st' states idx
        st' := st1
        i := i + 1
      let instrEntity := SemanticEntityRefV1.instruction callableId
        (UInt32.ofNat st'.blockId) (UInt32.ofNat st'.nextInstr)
      let acc1 ← attrPushPath st'.acc idx instrEntity stmtPath
      let effectEntity := SemanticEntityRefV1.effect callableId st'.nextEffectId
      let acc2 ← attrPushPath acc1 idx effectEntity stmtPath
      pure ({ st' with
        nextInstr := st'.nextInstr + 1
        nextEffectId := st'.nextEffectId + 1
        acc := acc2
      }, .open_)

end

private def attrBlock
    (callableId : CallableIdV1)
    (body : SrcBlock) (blockPath : NormalizedSyntacticPathV1)
    (params : Array (String × ValueIdV1))
    (states : StateNamesV1) (idx : OriginIndexV1)
    (acc0 : AttrAccumV1)
    (allowImplicitReturnNone : Bool) :
    Except ProvenanceBuildErrorV1 AttrAccumV1 := do
  -- Block 0 entity
  let accB ← attrPushPath acc0 idx (SemanticEntityRefV1.block callableId 0) blockPath
  let mut env : AttrEnvV1 := ⟨#[]⟩
  for (name, vid) in params do
    env := envInsertAttr env name vid
  let st : BodyAttrV1 := {
    nextValueId := UInt32.ofNat (params.size + countForLoopsStmtsV1 body.statements)
    nextInstr := 0
    blockId := 0
    nextBlockId := 1
    nextBlockParamOrdinal := 0
    callableParamCount := params.size
    nextEffectId := 0
    env := env
    acc := accB
  }
  let (st', status) ← attrStmts callableId body.statements blockPath st states idx
  match status with
  | .closed => pure st'.acc
  | .open_ =>
      if allowImplicitReturnNone then
        -- Implicit return none: terminator binds the body block (nearest producer).
        let termEntity := SemanticEntityRefV1.terminator callableId
          (UInt32.ofNat st'.blockId)
        attrPushPath st'.acc idx termEntity blockPath
      else
        failUnsupported "S2 provenance requires explicit return for entry/view"

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
          let rs3 := reqPush rs2 s2ValueCheckedArithmeticIdV1 exprPath
          reqPush rs3 s2FailureAtomicRollbackIdV1 exprPath
        else
          rs2
    | .unary op operand =>
        let rs1 := reqExprSites operand
          (directChild exprPath "Expr.Unary" "operand") rs
        if op == ProofForgeV2.Source.AstV1.UnaryOpV1.neg then
          let rs2 := reqPush rs1 s2ValueCheckedArithmeticIdV1 exprPath
          reqPush rs2 s2FailureAtomicRollbackIdV1 exprPath
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
        reqPush rs1 s2FailureAtomicRollbackIdV1 stmtPath
    | .revert _ args =>
        Id.run do
          let mut r := reqPush rs s2FailureAtomicRollbackIdV1 stmtPath
          let mut i := 0
          for a in args do
            r := reqExprSites a (childPath stmtPath "Stmt.Revert" "args" i) r
            i := i + 1
          pure r
    | .emit _ args =>
        Id.run do
          let mut r := reqPush rs s2EffectEventIdV1 stmtPath
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
          -- Mirror RequirementsInferV1: structured call contributes
          -- effect.synchronous-call + failure.atomic-rollback at the statement
          -- path (emit → effect.event only; assert/revert → rollback).
          let mut r := reqPush rs s2EffectSyncCallIdV1 stmtPath
          r := reqPush r s2FailureAtomicRollbackIdV1 stmtPath
          let callPath := directChild stmtPath "Stmt.Call" "call"
          let mut i := 0
          for a in call.args do
            r := reqExprSites a
              (childPath callPath "ExternalCallExpr" "args" i) r
            i := i + 1
          pure r
    | .schedule call =>
        Id.run do
          -- Mirror RequirementsInferV1: structured schedule contributes
          -- effect.asynchronous-workflow at the statement path.
          let mut r := reqPush rs s2EffectAsyncWorkflowIdV1 stmtPath
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
  let mut eventItemIdxs : Array Nat := #[]
  let mut errorItemIdxs : Array Nat := #[]
  let mut itemIdx : Nat := 0
  for item in program.items do
    match item with
    | .state s =>
        stateNames := stateNames.push (raw s.name)
        stateItemIdxs := stateItemIdxs.push itemIdx
    | .event _ =>
        eventItemIdxs := eventItemIdxs.push itemIdx
    | .error _ =>
        errorItemIdxs := errorItemIdxs.push itemIdx
    | _ => pure ()
    itemIdx := itemIdx + 1
  let states : StateNamesV1 := ⟨stateNames⟩
  unless stateItemIdxs.size == data.logicalState.size do
    return ← failUnsupported
      "S2 provenance: state count mismatch vs semantic logicalState"
  unless eventItemIdxs.size == data.events.size do
    return ← failUnsupported
      "S2 provenance: event count mismatch vs semantic events"
  unless errorItemIdxs.size == data.errors.size do
    return ← failUnsupported
      "S2 provenance: error count mismatch vs semantic errors"

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

  -- Events + errors: declaration entities and first-seen field type nodes.
  let mut ei : Nat := 0
  for itemI in eventItemIdxs do
    let itemPath := childPath #[] "Program" "items" itemI
    let some eventRow := data.events[ei]? |
      return ← failUnsupported "S2 provenance: missing event row"
    acc ← attrPushPath acc idx (.event eventRow.id) itemPath
    match program.items[itemI]? with
    | some (.event d) =>
        let mut fi : Nat := 0
        for f in d.params do
          let some sf := eventRow.fields[fi]? |
            return ← failUnsupported "S2 provenance: event field count mismatch"
          let fieldPath := directChild
            (childPath itemPath "EventDecl" "params" fi) "Param" "type"
          match f.type_ with
          | .uint 64 =>
              let (accF, tbF) ← tryBindType acc idx typeBound sf.typeId fieldPath
              acc := accF
              typeBound := tbF
          | _ => pure ()
          fi := fi + 1
    | _ => pure ()
    ei := ei + 1
  let mut zi : Nat := 0
  for itemI in errorItemIdxs do
    let itemPath := childPath #[] "Program" "items" itemI
    let some errorRow := data.errors[zi]? |
      return ← failUnsupported "S2 provenance: missing error row"
    acc ← attrPushPath acc idx (.errorRef errorRow.id) itemPath
    match program.items[itemI]? with
    | some (.error d) =>
        let mut fi : Nat := 0
        for f in d.params do
          let some sf := errorRow.fields[fi]? |
            return ← failUnsupported "S2 provenance: error field count mismatch"
          let fieldPath := directChild
            (childPath itemPath "ErrorDecl" "params" fi) "Param" "type"
          match f.type_ with
          | .uint 64 =>
              let (accF, tbF) ← tryBindType acc idx typeBound sf.typeId fieldPath
              acc := accF
              typeBound := tbF
          | _ => pure ()
          fi := fi + 1
    | _ => pure ()
    zi := zi + 1

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
    | .fn d =>
        let some c := data.callables[callableId]? |
          return ← failUnsupported "S2 provenance: missing fn callable"
        unless c.kind == .pureFn do
          return ← failUnsupported "S2 provenance: callable kind mismatch (fn)"
        let cid : CallableIdV1 := UInt32.ofNat callableId
        acc ← attrPushPath acc idx (.callable cid) itemPath
        let mut params : Array (String × ValueIdV1) := #[]
        let mut pi : Nat := 0
        for p in d.params do
          let paramPath := childPath itemPath "FnDecl" "params" pi
          let some sp := c.params[pi]? |
            return ← failUnsupported "S2 provenance: fn param count mismatch"
          acc ← attrPushPath acc idx (.value cid sp.valueId) paramPath
          let pTypePath := directChild paramPath "Param" "type"
          let (accP, tbP) ← tryBindType acc idx typeBound sp.typeId pTypePath
          acc := accP
          typeBound := tbP
          params := params.push (raw p.name, sp.valueId)
          pi := pi + 1
        let resultPath := directChild itemPath "FnDecl" "result"
        let (accR, tbR) ← tryBindType acc idx typeBound c.result.typeId resultPath
        acc := accR
        typeBound := tbR
        -- Fn purity: the body attributes against an empty state-name table,
        -- so any state place fails closed (mirroring the normalizer).
        let bodyPath := directChild itemPath "FnDecl" "body"
        acc ← attrBlock cid d.body bodyPath params ⟨#[]⟩ idx acc false
        callableId := callableId + 1
    | .event _ | .error _ => pure ()
    | .struct _ | .enum _ | .const _
    | .invariant _ | .extensionReq _ | .proof _ =>
        return ← failUnsupported
          "S2 provenance attribution only supports state/event/error/init/entry/view/fn"
    itemIdx := itemIdx + 1
  unless callableId == data.callables.size do
    return ← failUnsupported "S2 provenance: callable count mismatch"

  -- Implicitly body-interned types (Bool from comparisons/Bool literals) have
  -- no annotation node: bind each unbound type to the first producing
  -- instruction's recorded origin, in canonical callable/block/instruction
  -- order. Annotation-bound types (UInt64/Unit) are already marked, so this
  -- is a no-op for comparison-free programs and never moves their
  -- attribution.
  for c in data.callables do
    for blk in c.blocks do
      let mut ii : Nat := 0
      for instr in blk.instructions do
        match instr.result with
        | none => pure ()
        | some r =>
            let ti := r.typeId.toNat
            if ti < typeBound.size && !typeBound[ti]! then
              let entity := SemanticEntityRefV1.instruction c.id blk.id (UInt32.ofNat ii)
              let kb ← match encodeSemanticEntityRefV1 entity with
                | .ok b => pure b
                | .error e => return ← .error (.wire e)
              match acc.table.get? kb with
              | some (_, origins) =>
                  match origins[0]? with
                  | some o =>
                      acc ← attrPush acc (.typeRef r.typeId) o
                      typeBound := typeBound.set! ti true
                  | none =>
                      return ← failUnsupported
                        s!"S2 provenance: type TypeId {ti} has no producing source node"
              | none =>
                  return ← failUnsupported
                    s!"S2 provenance: instruction for TypeId {ti} has no recorded origin"
            else pure ()
        ii := ii + 1

  -- Ensure every type got a binding (fail closed if interned type unused).
  for i in [:data.types.size] do
    unless typeBound[i]! do
      return ← failUnsupported
        s!"S2 provenance: type TypeId {i} has no producing source node"

  -- Requirements: collect all producing sites, map catalog id → requirement index.
  let mut rs := emptyReqSites
  for itemI in stateItemIdxs do
    let itemPath := childPath #[] "Program" "items" itemI
    rs := reqPush rs s2StatePersistentIdV1 itemPath
  -- Type-annotation producing sites for value.bool (mirrors the contribution
  -- engine's type carriers: state/param/result Bool types).
  itemIdx := 0
  for item in program.items do
    let itemPath := childPath #[] "Program" "items" itemIdx
    match item with
    | .state s =>
        match s.type_ with
        | .bool =>
            rs := reqPush rs s2ValueBoolIdV1 (directChild itemPath "StateDecl" "type")
        | _ => pure ()
    | .init d =>
        let mut pi : Nat := 0
        for p in d.params do
          match p.type_ with
          | .bool =>
              let paramPath := childPath itemPath "InitDecl" "params" pi
              rs := reqPush rs s2ValueBoolIdV1 (directChild paramPath "Param" "type")
          | _ => pure ()
          pi := pi + 1
    | .entry e =>
        let mut pi : Nat := 0
        for p in e.params do
          match p.type_ with
          | .bool =>
              let paramPath := childPath itemPath "EntryDecl" "params" pi
              rs := reqPush rs s2ValueBoolIdV1 (directChild paramPath "Param" "type")
          | _ => pure ()
          pi := pi + 1
        match e.result with
        | .bool =>
            rs := reqPush rs s2ValueBoolIdV1 (directChild itemPath "EntryDecl" "result")
        | _ => pure ()
    | .view v =>
        let mut pi : Nat := 0
        for p in v.params do
          match p.type_ with
          | .bool =>
              let paramPath := childPath itemPath "ViewDecl" "params" pi
              rs := reqPush rs s2ValueBoolIdV1 (directChild paramPath "Param" "type")
          | _ => pure ()
          pi := pi + 1
        match v.result with
        | .bool =>
            rs := reqPush rs s2ValueBoolIdV1 (directChild itemPath "ViewDecl" "result")
        | _ => pure ()
    | .fn d =>
        let mut pi : Nat := 0
        for p in d.params do
          match p.type_ with
          | .bool =>
              let paramPath := childPath itemPath "FnDecl" "params" pi
              rs := reqPush rs s2ValueBoolIdV1 (directChild paramPath "Param" "type")
          | _ => pure ()
          pi := pi + 1
        match d.result with
        | .bool =>
            rs := reqPush rs s2ValueBoolIdV1 (directChild itemPath "FnDecl" "result")
        | _ => pure ()
    | _ => pure ()
    itemIdx := itemIdx + 1
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
    | .fn d =>
        rs := reqBlockSites d.body (directChild itemPath "FnDecl" "body") rs
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
        let desc := match entity with
          | .typeRef i => s!"typeRef {i}"
          | .constant i => s!"constant {i}"
          | .state i => s!"state {i}"
          | .event i => s!"event {i}"
          | .errorRef i => s!"errorRef {i}"
          | .callable i => s!"callable {i}"
          | .block c b => s!"block {c}/{b}"
          | .instruction c b i => s!"instruction {c}/{b}/{i}"
          | .terminator c b => s!"terminator {c}/{b}"
          | .value c v => s!"value {c}/{v}"
          | .effect c e => s!"effect {c}/{e}"
          | .invariant i => s!"invariant {i}"
          | .requirement i => s!"requirement {i}"
        return ← failUnsupported
          s!"S2 provenance missing attribution for entity {desc}"
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
