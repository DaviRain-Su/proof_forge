/-
  ProofForgeV2.Semantic.NormalizeV1 — S1 Semantic normalizer vertical contract.

  Owns the first ProgramV1 → SemanticProgramV1 lowering seam:
    * consumes ValidatedSourceV1
    * product entry requires `checkProgramTypedLocatedResultV1`; non-product
      fixture/provenance entry retains the exact unlocated erase projection
    * requires ok=true and analysisComplete=true (fail closed otherwise; no
      Semantic carrier on typed failure)
    * lowers the shipped Counter-like ProgramV1 subset into SemanticProgramDataV1
    * returns SemanticProgramV1 only via WireV1 structure-gated
      encodeSemanticProgramDataV1 (authoritative path; no alpha Semantic.Program
      or Typed.Program bridge)

  Supported S1/S2 surface (everything else fails closed at this boundary):
    * declarations: public primitive state (UInt64 only), init, entry, view
    * statements: bare-place assign to state, return (some/none); init may omit
      return (implicit return none); bare `assert` with a Bool condition
      (assert-else still fails closed); `if cond then B (else B)?` lowered to
      branch/jump blocks; `match scrut with` on a UInt64 or Bool scrutinee
      with integer/Bool literal arms plus exactly one wildcard/bind catch-all
      lowered to switch/jump blocks (constructor patterns, string patterns,
      match expressions, and duplicate literals still fail closed; a
      catch-all-only match materializes to a plain jump)
    * expressions: bare place (param or state name), UInt64 integer literal,
      Bool literal, checked binary add/sub/mul/div/mod and bitwise
      and/or/xor on same-width UInt64, shifts (lhs UInt64, count UInt32 —
      the only UInt32 context), and the six UInt64 comparisons plus strict
      logical and/or producing Bool; integer width is supplied by the
      enclosing typed context, comparison operands are always UInt64
    * types: anonymous UInt64 + Unit (init result) + Bool (comparison results,
      Bool literals); one TypeId per distinct shape, interned on first actual
      use in source traversal order. State/parameter positions stay
      UInt64-only; entry/view results may be UInt64, Unit, or Bool
    * callables: multi-block CFG (entryBlock=0, dense block ids,
      invariantSteps=none). Bounded `for i in s .. e bounded N do` loops
      lower to a single-param header block (the induction variable), a
      branch, and a latch with the only back edge; `loopBounds` records
      exactly that (header, latch, N) edge in ascending order. Non-loop
      edges still point forward; block params appear only on loop headers
      * statements: immutable `let` bindings lower to environment entries
      (the RHS evaluates once; reassignment via `assign` fails closed)
    * S2 exact ProgramRequirementsV1 freeze (Counter catalog, SPEC wire order)
      before encode/hash; companion provenance only via
      `normalizeProgramWithProvenanceV1` (source+path+spans rebuild inventory;
      public authority validate/digest never accept caller inventory)

  Product ownership (S3 + B8b):
    * Product path: `normalizeProgramLocatedV1` consumes
      `(ValidatedSourceV1 × OriginInventoryV1)` from the sole product Loader,
      calls `checkProgramTypedLocatedResultV1` exactly once, materializes the
      full located diagnostic array all-or-nothing, and returns
      `DiagnosticResultV1 SemanticProgramV1` via `mkFailureBundleV1` (sole
      sort/dedupe/cap). Does **not** re-run unlocated CheckV1.
    * Non-product library: `normalizeProgramV1` remains for hand-built fixtures
      and provenance helpers; product Compiler/CLI must not call it.
    * This module owns the target-neutral structure gate only; it does not own
      residual alpha `Semantic.Program`, Registry, or target Plan/IR.

  Out of scope for this module:
    * broadening beyond the public UInt64 arithmetic/comparison/bare-assert +
      if/match-literal + revert/emit + pure-fn + immutable-let + bounded-for
      envelope (loop-carried locals beyond the induction variable, mutable
      locals, match expressions, aggregates, external calls)
    * registry / resolver / materializer / OutputSetV1
    * interpreter / target Plan changes
    * formal TASK-D2-05 / TASK-D2-06 / TST-SEM-001 completion
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Semantic.ProvenanceV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.CheckV1

namespace ProofForgeV2.Semantic.NormalizeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Semantic.ProvenanceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.CheckV1

-- Source AST namespaces kept selective/qualified to avoid Wire name clashes
-- (StateDeclV1, BlockV1, VisibilityV1, …).
private abbrev SrcType := ProofForgeV2.Source.AstV1.TypeV1
private abbrev SrcVis := ProofForgeV2.Source.AstV1.VisibilityV1
private abbrev SrcExpr := ProofForgeV2.Source.AstSpineV1.ExprV1
private abbrev SrcStmt := ProofForgeV2.Source.AstSpineV1.StmtV1
private abbrev SrcPlace := ProofForgeV2.Source.AstSpineV1.PlaceV1
private abbrev SrcBlock := ProofForgeV2.Source.AstSpineV1.BlockV1
/-- Fail-closed normalizer errors. Typed-not-ok never yields a carrier. -/
inductive NormalizeErrorV1 where
  | typedNotOk (diagnostics : Array DiagnosticV1)
  | unsupported (detail : String)
  | identity (detail : String)
  | wire (error : SemanticWireErrorV1)
  deriving Repr

/-- Default for mutual-partial inhabitedness only; never produced by the
    lowering paths (they always fail or succeed explicitly). -/
instance : Inhabited NormalizeErrorV1 := ⟨.unsupported "unreachable"⟩

private def failUnsupported (detail : String) : Except NormalizeErrorV1 α :=
  .error (.unsupported detail)

private def failIdentity (detail : String) : Except NormalizeErrorV1 α :=
  .error (.identity detail)

private def raw (n : SourceNameComponentV1) : String := n.raw

/-- Map source program identity to Common.QualifiedName (≥2 components for Wire). -/
def programIdentityToQualifiedNameV1 (identity : SourceQualifiedNameV1) :
    Except NormalizeErrorV1 QualifiedName := do
  let comps := (NonEmptyArray.toArray identity.components).map (·.raw)
  unless comps.size ≥ 2 do
    return ← failIdentity "semantic program qualifiedName requires ≥2 components"
  match parseQualifiedName comps with
  | .ok qn => pure qn
  | .error e => failIdentity e

private def mapVisibility : SrcVis → VisibilityV1
  | .public_ => .public_
  | .private_ => .private_
  | .commitment => .commitment

/-- S1 type interning: only anonymous UInt64 and Unit, first-seen order. -/
structure TypeInternerV1 where
  types : Array TypeDeclV1

private def emptyInterner : TypeInternerV1 := ⟨#[]⟩

private def shapeEq (a b : TypeShapeV1) : Bool :=
  match a, b with
  | .uint wa, .uint wb => wa == wb
  | .unit, .unit => true
  | .bool, .bool => true
  | _, _ => false

private def findTypeId (interner : TypeInternerV1) (shape : TypeShapeV1) :
    Option TypeIdV1 := Id.run do
  let mut i : Nat := 0
  for d in interner.types do
    if shapeEq d.shape shape then
      return some (UInt32.ofNat i)
    i := i + 1
  pure none

private def internShape (interner : TypeInternerV1) (shape : TypeShapeV1) :
    TypeInternerV1 × TypeIdV1 :=
  match findTypeId interner shape with
  | some tid => (interner, tid)
  | none =>
      let tid := UInt32.ofNat interner.types.size
      let decl : TypeDeclV1 := { id := tid, name := none, shape := shape }
      ({ types := interner.types.push decl }, tid)

private def internSourceType (interner : TypeInternerV1) (ty : SrcType) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match ty with
  | .uint 64 => pure (internShape interner (.uint 64))
  | .unit => pure (internShape interner .unit)
  | .bool => pure (internShape interner .bool)
  | .uint w => failUnsupported s!"S1 normalizer supports only UInt64, got UInt{w}"
  | .int w => failUnsupported s!"S1 normalizer does not support Int{w}"
  | .principal => failUnsupported "S1 normalizer does not support Principal"
  | .named n => failUnsupported s!"S1 normalizer does not support named type '{raw n}'"
  | .array _ _ => failUnsupported "S1 normalizer does not support Array"
  | .map _ _ => failUnsupported "S1 normalizer does not support Map"
  | .option _ => failUnsupported "S1 normalizer does not support Option"
  | .bytes _ => failUnsupported "S1 normalizer does not support Bytes"
  | .field _ => failUnsupported "S1 normalizer does not support Field"

/-- Require an already-interned TypeId to resolve to anonymous UInt64. State,
parameter, and entry/view result positions stay UInt64-only in this envelope. -/
private def requireUInt64TypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | some decl =>
      if decl.name.isNone && (match decl.shape with | .uint 64 => true | _ => false) then
        pure ()
      else
        failUnsupported s!"S1 {context} requires UInt64 type"
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"

/-- Require an already-interned TypeId to resolve to an anonymous scalar
    supported at entry/view results: UInt64, Unit, or Bool. Unit results keep
    flowing to the bare-return gate; richer shapes fail here. -/
private def requireScalarResultTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | some decl =>
      if decl.name.isNone && (match decl.shape with
          | .uint 64 => true | .unit => true | .bool => true | _ => false) then
        pure ()
      else
        failUnsupported s!"S1 {context} requires UInt64/Unit/Bool type"
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"

/-- Require an already-interned expected TypeId to resolve to anonymous UInt64.
    Literal width is never inferred or defaulted inside the expression: the
    assignment target or callable result supplies this TypeId. -/
private def requireExpectedUInt64
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | some decl =>
      if decl.name.isNone && (match decl.shape with | .uint 64 => true | _ => false) then
        pure ()
      else
        failUnsupported s!"S1 {context} requires expected UInt64 type"
  | none =>
      failUnsupported s!"S1 {context} references missing expected TypeId {typeId}"

/-- Require an already-interned expected TypeId to resolve to anonymous
    UInt64 or UInt32. UInt32 values arise only inside shift-count
    expressions in this envelope; every other position stays UInt64/Bool. -/
private def requireExpectedUIntWidth
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | some decl =>
      if decl.name.isNone && (match decl.shape with
          | .uint 64 => true | .uint 32 => true | _ => false) then
        pure ()
      else
        failUnsupported s!"S1 {context} requires expected UInt64/UInt32 type"
  | none =>
      failUnsupported s!"S1 {context} references missing expected TypeId {typeId}"

/-- Param/local env: bare name → (ValueId, TypeId). -/
structure LocalEnvV1 where
  bindings : Array (String × ValueIdV1 × TypeIdV1)

private def emptyEnv : LocalEnvV1 := ⟨#[]⟩

private def envLookup (env : LocalEnvV1) (name : String) :
    Option (ValueIdV1 × TypeIdV1) :=
  env.bindings.findSome? fun (n, vid, tid) =>
    if n == name then some (vid, tid) else none

private def envInsert (env : LocalEnvV1) (name : String) (vid : ValueIdV1)
    (tid : TypeIdV1) : LocalEnvV1 :=
  ⟨env.bindings.push (name, vid, tid)⟩

/-- State name → (StateId, TypeId). -/
structure StateTableV1 where
  rows : Array (String × StateIdV1 × TypeIdV1)

private def stateLookup (table : StateTableV1) (name : String) :
    Option (StateIdV1 × TypeIdV1) :=
  table.rows.findSome? fun (n, sid, tid) =>
    if n == name then some (sid, tid) else none

/-- Event name → (EventId, field TypeIds in declaration order). -/
structure EventTableV1 where
  rows : Array (String × EventIdV1 × Array TypeIdV1)

private def eventLookup (table : EventTableV1) (name : String) :
    Option (EventIdV1 × Array TypeIdV1) :=
  table.rows.findSome? fun (n, eid, tids) =>
    if n == name then some (eid, tids) else none

/-- Error name → (ErrorId, field TypeIds in declaration order). -/
structure ErrorTableV1 where
  rows : Array (String × ErrorIdV1 × Array TypeIdV1)

private def errorLookup (table : ErrorTableV1) (name : String) :
    Option (ErrorIdV1 × Array TypeIdV1) :=
  table.rows.findSome? fun (n, eid, tids) =>
    if n == name then some (eid, tids) else none

/-- Fn name → (CallableId, param TypeIds, result TypeId). -/
structure FnTableV1 where
  rows : Array (String × CallableIdV1 × Array TypeIdV1 × TypeIdV1)

private def fnLookup (table : FnTableV1) (name : String) :
    Option (CallableIdV1 × Array TypeIdV1 × TypeIdV1) :=
  table.rows.findSome? fun (n, cid, ptids, rtid) =>
    if n == name then some (cid, ptids, rtid) else none

/-- Multi-block lowering accumulator for one callable body. The interner is
live: comparison/Bool-literal lowering interns shapes on first actual use so
existing programs keep byte-identical type tables. `blocks` holds completed
blocks in id order; `instructions` accumulates the current open block.
`currentParams` carries the open block's params (only loop headers have any
in this envelope: exactly the induction variable). `loopBounds` accumulates
static loop-bound entries in completion order and is sorted into canonical
ascending (header, backEdgeFrom) order at callable assembly. `nextEffectId`
counts emitted effect instructions (emit) in BlockId/instruction order, which
is exactly the canonical EffectId order. Loop-header block params draw from
`callableParamCount + nextBlockParamOrdinal` (creation order == BlockId
order), and `nextValueId` starts past the syntactically counted header-param
range, so the SPEC §6 canonical three-pass ValueId order (callable params →
block params → instruction results) holds by construction with no remap. -/
structure BodyStateV1 where
  blocks : Array BlockV1
  instructions : Array InstructionV1
  currentParams : Array BlockParameterV1
  loopBounds : Array LoopBoundV1
  nextValueId : ValueIdV1
  nextBlockParamOrdinal : Nat
  callableParamCount : Nat
  nextEffectId : UInt32
  env : LocalEnvV1
  interner : TypeInternerV1

/-- Wire ceiling for a static loop bound (`maxIterations ≤ 4096`). -/
private def maxWireLoopBoundV1 : UInt32 := 4096

/-- Seal the current open block with a terminator and start a fresh one. Block
ids are dense (`id == blocks.size` at seal time). Non-loop edges emitted by
this normalizer point forward; the only back edge is a loop latch jumping to
its header, recorded in `loopBounds`. -/
private def sealCurrentBlock (st : BodyStateV1) (term : TerminatorV1) : BodyStateV1 :=
  { st with
    blocks := st.blocks.push {
      id := UInt32.ofNat st.blocks.size
      params := st.currentParams
      instructions := st.instructions
      terminator := term
    }
    instructions := #[]
    currentParams := #[] }

/-- Whether the current control-flow path is still open (can take more
statements / needs an explicit or implicit return) or closed (already ended
in return; a following statement is dead code). -/
inductive PathStatusV1 where
  | open_
  | closed
  deriving BEq

/-- Rewrite the terminator of an already-sealed block (back-patch target used
by control-flow lowering; out-of-range indices are a no-op by construction
discipline and never occur from the paths below). -/
private def patchTerminatorAt (st : BodyStateV1) (blockIdx : Nat)
    (f : TerminatorV1 → TerminatorV1) : BodyStateV1 :=
  match st.blocks[blockIdx]? with
  | none => st
  | some blk =>
      { st with blocks := st.blocks.set! blockIdx { blk with terminator := f blk.terminator } }

/-- Back-patch the else target of a branch terminator. -/
private def patchBranchElse (st : BodyStateV1) (blockIdx : Nat) (elseId : BlockIdV1) :
    BodyStateV1 :=
  patchTerminatorAt st blockIdx fun
    | .branch cond thenT _ => .branch cond thenT { blockId := elseId, args := #[] }
    | t => t

/-- Back-patch a jump terminator's target block. -/
private def patchJumpTarget (st : BodyStateV1) (blockIdx : Nat) (targetId : BlockIdV1) :
    BodyStateV1 :=
  patchTerminatorAt st blockIdx fun
    | .jump _ => .jump { blockId := targetId, args := #[] }
    | t => t

/-- Back-patch a switch terminator's cases and default target. -/
private def patchSwitch (st : BodyStateV1) (blockIdx : Nat)
    (cases : Array SwitchCaseV1) (defaultTarget : Option JumpTargetV1) : BodyStateV1 :=
  patchTerminatorAt st blockIdx fun
    | .switch scrut _ _ => .switch scrut cases defaultTarget
    | t => t

/-- Count the `for` statements in a statement list, recursing through branch
and loop bodies. Every lowered `for` allocates exactly one loop-header block
param, so this syntactic count sizes the canonical block-param ValueId range
(`params.size .. params.size + count`) before instruction results begin. -/
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

/-- Require an already-interned TypeId to resolve to anonymous UInt64 or Bool:
the only types an immutable `let` binding can carry in this envelope. -/
private def requireLetTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | some decl =>
      if decl.name.isNone && (match decl.shape with
          | .uint 64 => true | .bool => true | _ => false) then
        pure ()
      else
        failUnsupported s!"S1 {context} requires UInt64/Bool type"
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"

/-- Derive the expected TypeId for an unannotated `let` RHS from its head
shape. CheckV1 has already rejected integer literals without an expected
type, so every remaining pilot shape carries an intrinsic result type. -/
private partial def synthLetExpectedV1
    (value : SrcExpr) (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match value with
  | .literal (.integer _) =>
      failUnsupported "S1 let integer literal requires a type annotation"
  | .literal (.bool _) => pure (internShape st.interner .bool)
  | .literal (.string _) =>
      failUnsupported "S1 normalizer supports only UInt64/Bool literals"
  | .place (.name n) =>
      let key := raw n
      match envLookup st.env key with
      | some (_, tid) => pure (st.interner, tid)
      | none =>
          match stateLookup states key with
          | some (_, tid) => pure (st.interner, tid)
          | none => failUnsupported s!"S1 bare place '{key}' is neither param nor state"
  | .place (.field ..) =>
      failUnsupported "S1 normalizer does not support field places"
  | .place (.index ..) =>
      failUnsupported "S1 normalizer does not support index places"
  | .binary op _ _ =>
      let srcOp := op
      if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.add ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.sub ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mul ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.div ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mod then
        pure (internShape st.interner (.uint 64))
      else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.eq ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ne ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.lt ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.le ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.gt ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ge then
        pure (internShape st.interner .bool)
      else
        failUnsupported "S1 normalizer supports only binary arithmetic, bitwise, shift, comparison, and logical operators"
  | .unary .not _ => pure (internShape st.interner .bool)
  | .unary _ _ => pure (internShape st.interner (.uint 64))
  | .constructor _ _ =>
      failUnsupported "S1 normalizer does not support constructors"
  | .localCall callee _ =>
      let key := raw callee
      match fnLookup fns key with
      | none => failUnsupported s!"S1 localCall '{key}' is not a declared fn"
      | some (_, _, fnResultTid) => pure (st.interner, fnResultTid)
  | .match_ _ _ =>
      failUnsupported "S1 normalizer does not support match expressions"

private def lowerPlace
    (place : SrcPlace) (st : BodyStateV1) (states : StateTableV1) :
    Except NormalizeErrorV1 (ValueIdV1 × TypeIdV1 × BodyStateV1) :=
  match place with
  | .name n =>
      let key := raw n
      match envLookup st.env key with
      | some (vid, tid) => pure (vid, tid, st)
      | none =>
          match stateLookup states key with
          | none =>
              failUnsupported s!"S1 bare place '{key}' is neither param nor state"
          | some (sid, tid) =>
              let vid := st.nextValueId
              let instr : InstructionV1 := {
                result := some { valueId := vid, typeId := tid }
                op := .stateLoad sid
              }
              pure (vid, tid, { st with
                instructions := st.instructions.push instr
                nextValueId := vid + 1
              })
  | .field _ _ => failUnsupported "S1 normalizer does not support field places"
  | .index _ _ => failUnsupported "S1 normalizer does not support index places"

private partial def lowerExpr
    (expr : SrcExpr) (expectedTid : TypeIdV1)
    (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (ValueIdV1 × TypeIdV1 × BodyStateV1) :=
  match expr with
  | .place p => do
      let (vid, tid, st1) ← lowerPlace p st states
      unless tid == expectedTid do
        return ← failUnsupported "S1 place type does not match enclosing expected type"
      pure (vid, tid, st1)
  | .binary op lhs rhs => do
      let srcOp := op
      -- Same-width integer ops (arithmetic and bitwise share one path).
      let arithOp? : Option BinaryOpV1 :=
        if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.add then some BinaryOpV1.add
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.sub then some BinaryOpV1.sub
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mul then some BinaryOpV1.mul
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.div then some BinaryOpV1.div
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mod then some BinaryOpV1.mod
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitAnd then some BinaryOpV1.bitAnd
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitOr then some BinaryOpV1.bitOr
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitXor then some BinaryOpV1.bitXor
        else none
      let shiftOp? : Option BinaryOpV1 :=
        if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shl then some BinaryOpV1.shl
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shr then some BinaryOpV1.shr
        else none
      let cmpOp? : Option BinaryOpV1 :=
        if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.eq then some BinaryOpV1.eq
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ne then some BinaryOpV1.ne
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.lt then some BinaryOpV1.lt
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.le then some BinaryOpV1.le
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.gt then some BinaryOpV1.gt
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ge then some BinaryOpV1.ge
        else none
      let logicalOp? : Option BinaryOpV1 :=
        if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalAnd then some BinaryOpV1.and
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalOr then some BinaryOpV1.or
        else none
      match arithOp? with
      | some semanticOp => do
        requireExpectedUIntWidth st.interner.types expectedTid "binary arithmetic/bitwise"
        -- Preserve source evaluation / ValueId order: lhs, then rhs, then op.
        let (lVid, lTid, st1) ← lowerExpr lhs expectedTid st states fns
        let (rVid, rTid, st2) ← lowerExpr rhs expectedTid st1 states fns
        unless lTid == expectedTid && rTid == expectedTid do
          return ← failUnsupported
            "S1 binary arithmetic/bitwise requires same-width expected operands"
        let vid := st2.nextValueId
        let instr : InstructionV1 := {
          result := some { valueId := vid, typeId := expectedTid }
          op := .binary semanticOp lVid rVid
        }
        pure (vid, expectedTid, { st2 with
          instructions := st2.instructions.push instr
          nextValueId := vid + 1
        })
      | none =>
        match shiftOp? with
        | some semanticOp => do
          requireExpectedUInt64 st.interner.types expectedTid "shift"
          -- Shift counts are UInt32 (the only UInt32 context in this
          -- envelope); the wire reverts invalidShift for counts ≥ 64 and
          -- arithmeticOverflow on shl overflow.
          let (iU32, u32Tid) := internShape st.interner (.uint 32)
          let st0 := { st with interner := iU32 }
          let (lVid, lTid, st1) ← lowerExpr lhs expectedTid st0 states fns
          unless lTid == expectedTid do
            return ← failUnsupported "S1 shift requires a UInt64 operand"
          let (rVid, rTid, st2) ← lowerExpr rhs u32Tid st1 states fns
          unless rTid == u32Tid do
            return ← failUnsupported "S1 shift count must be UInt32"
          let vid := st2.nextValueId
          let instr : InstructionV1 := {
            result := some { valueId := vid, typeId := expectedTid }
            op := .binary semanticOp lVid rVid
          }
          pure (vid, expectedTid, { st2 with
            instructions := st2.instructions.push instr
            nextValueId := vid + 1
          })
        | none =>
        match logicalOp? with
        | some semanticOp => do
            -- Strict Bool binary (both operands always evaluate; there is no
            -- short-circuit in the wire semantics).
            let (i1, boolTid) := internShape st.interner .bool
            unless boolTid == expectedTid do
              return ← failUnsupported
                "S1 logical operator requires an enclosing Bool expected type"
            let st0 := { st with interner := i1 }
            let (lVid, lTid, st1) ← lowerExpr lhs boolTid st0 states fns
            unless lTid == boolTid do
              return ← failUnsupported "S1 logical operator requires Bool operands"
            let (rVid, rTid, st2) ← lowerExpr rhs boolTid st1 states fns
            unless rTid == boolTid do
              return ← failUnsupported "S1 logical operator requires Bool operands"
            let vid := st2.nextValueId
            let instr : InstructionV1 := {
              result := some { valueId := vid, typeId := boolTid }
              op := .binary semanticOp lVid rVid
            }
            pure (vid, boolTid, { st2 with
              instructions := st2.instructions.push instr
              nextValueId := vid + 1
            })
        | none =>
        match cmpOp? with
        | some semanticOp => do
            -- Comparison operands are UInt64; the result is Bool. Both shapes
            -- intern on first actual use, in source traversal order.
            let (i1, u64Tid) := internShape st.interner (.uint 64)
            let (i2, boolTid) := internShape i1 .bool
            let st0 := { st with interner := i2 }
            let (lVid, lTid, st1) ← lowerExpr lhs u64Tid st0 states fns
            unless lTid == u64Tid do
              return ← failUnsupported
                "S1 comparison requires UInt64 operands"
            let (rVid, rTid, st2) ← lowerExpr rhs u64Tid st1 states fns
            unless rTid == u64Tid do
              return ← failUnsupported
                "S1 comparison requires UInt64 operands"
            let vid := st2.nextValueId
            let instr : InstructionV1 := {
              result := some { valueId := vid, typeId := boolTid }
              op := .binary semanticOp lVid rVid
            }
            pure (vid, boolTid, { st2 with
              instructions := st2.instructions.push instr
              nextValueId := vid + 1
            })
        | none =>
            failUnsupported "S1 normalizer supports only binary arithmetic, bitwise, shift, comparison, and logical operators"
  | .literal literal =>
      match literal with
      | .integer magnitude => do
          -- UInt64 or UInt32 expected (UInt32 arises only as a shift count).
          -- CheckV1 owns the user-facing width diagnostic. This defensive seam
          -- still rejects direct lowerProgramDataV1 misuse instead of allowing
          -- truncation modulo the width.
          let width? : Option Nat :=
            match st.interner.types[expectedTid.toNat]? with
            | some decl =>
                if decl.name.isNone then
                  match decl.shape with
                  | .uint 64 => some 64
                  | .uint 32 => some 32
                  | _ => none
                else none
            | none => none
          let some width := width? |
            return ← failUnsupported
              "S1 integer literal requires expected UInt64/UInt32 type"
          let limit : Nat := if width == 64 then 18446744073709551616 else 4294967296
          unless magnitude < limit do
            return ← failUnsupported s!"S1 UInt{width} integer literal is out of range"
          let bytes :=
            if width == 64 then encodeU64le (UInt64.ofNat magnitude)
            else encodeU32le (UInt32.ofNat magnitude)
          let vid := st.nextValueId
          let instr : InstructionV1 := {
            result := some { valueId := vid, typeId := expectedTid }
            op := .literal expectedTid bytes
          }
          pure (vid, expectedTid, { st with
            instructions := st.instructions.push instr
            nextValueId := vid + 1
          })
      | .bool value => do
          let (i1, boolTid) := internShape st.interner .bool
          unless boolTid == expectedTid do
            return ← failUnsupported
              "S1 Bool literal requires an enclosing Bool expected type"
          let st0 := { st with interner := i1 }
          let vid := st0.nextValueId
          let instr : InstructionV1 := {
            result := some { valueId := vid, typeId := boolTid }
            op := .literal boolTid (encodeBool value)
          }
          pure (vid, boolTid, { st0 with
            instructions := st0.instructions.push instr
            nextValueId := vid + 1
          })
      | .string _ =>
          failUnsupported "S1 normalizer supports only UInt64/Bool literals"
  | .constructor _ _ => failUnsupported "S1 normalizer does not support constructors"
  | .unary op operand => do
      match op with
      | .neg => do
          requireExpectedUInt64 st.interner.types expectedTid "unary checked negation"
          -- Checked unsigned negation desugars to `0 - x` (the wire reserves
          -- Op.Unary.neg for Int/Field; checked sub underflows on any nonzero).
          let (oVid, oTid, st1) ← lowerExpr operand expectedTid st states fns
          unless oTid == expectedTid do
            return ← failUnsupported
              "S1 unary checked negation requires a UInt64 operand"
          let zeroVid := st1.nextValueId
          let zeroInstr : InstructionV1 := {
            result := some { valueId := zeroVid, typeId := expectedTid }
            op := .literal expectedTid (encodeU64le 0)
          }
          let vid := zeroVid + 1
          let subInstr : InstructionV1 := {
            result := some { valueId := vid, typeId := expectedTid }
            op := .binary .sub zeroVid oVid
          }
          pure (vid, expectedTid, { st1 with
            instructions := st1.instructions.push zeroInstr |>.push subInstr
            nextValueId := vid + 1
          })
      | .bitNot => do
          requireExpectedUInt64 st.interner.types expectedTid "unary bit-not"
          let (oVid, oTid, st1) ← lowerExpr operand expectedTid st states fns
          unless oTid == expectedTid do
            return ← failUnsupported
              "S1 unary bit-not requires a UInt64 operand"
          let vid := st1.nextValueId
          let instr : InstructionV1 := {
            result := some { valueId := vid, typeId := expectedTid }
            op := .unary .bitNot oVid
          }
          pure (vid, expectedTid, { st1 with
            instructions := st1.instructions.push instr
            nextValueId := vid + 1
          })
      | .not => do
          let (i1, boolTid) := internShape st.interner .bool
          unless boolTid == expectedTid do
            return ← failUnsupported
              "S1 unary not requires an enclosing Bool expected type"
          let st0 := { st with interner := i1 }
          let (oVid, oTid, st1) ← lowerExpr operand boolTid st0 states fns
          unless oTid == boolTid do
            return ← failUnsupported
              "S1 unary not requires a Bool operand"
          let vid := st1.nextValueId
          let instr : InstructionV1 := {
            result := some { valueId := vid, typeId := boolTid }
            op := .unary .not oVid
          }
          pure (vid, boolTid, { st1 with
            instructions := st1.instructions.push instr
            nextValueId := vid + 1
          })
  | .localCall callee args => do
      let key := raw callee
      match fnLookup fns key with
      | none =>
          failUnsupported s!"S1 localCall '{key}' is not a declared fn"
      | some (callableId, paramTids, fnResultTid) => do
          unless fnResultTid == expectedTid do
            return ← failUnsupported
              s!"S1 localCall '{key}' result type does not match the enclosing expected type"
          unless args.size == paramTids.size do
            return ← failUnsupported
              s!"S1 localCall '{key}' expects {paramTids.size} arguments, got {args.size}"
          let mut st' := st
          let mut argIds : Array ValueIdV1 := #[]
          for (arg, paramTid) in args.zip paramTids do
            let (vid, argTid, st1) ← lowerExpr arg paramTid st' states fns
            unless argTid == paramTid do
              return ← failUnsupported s!"S1 localCall '{key}' argument type mismatch"
            argIds := argIds.push vid
            st' := st1
          let vid := st'.nextValueId
          let instr : InstructionV1 := {
            result := some { valueId := vid, typeId := fnResultTid }
            op := .pureCall callableId argIds
          }
          pure (vid, fnResultTid, { st' with
            instructions := st'.instructions.push instr
            nextValueId := vid + 1
          })
  | .match_ _ _ => failUnsupported "S1 normalizer does not support match expressions"

mutual

private partial def lowerStmts
    (stmts : Array SrcStmt) (resultTid : TypeIdV1)
    (st : BodyStateV1) (states : StateTableV1)
    (events : EventTableV1) (errors : ErrorTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (BodyStateV1 × PathStatusV1) := do
  let mut st := st
  let mut i : Nat := 0
  for stmt in stmts do
    let (st', status) ← lowerStmt stmt resultTid st states events errors fns
    st := st'
    if status == .closed then
      if i + 1 < stmts.size then
        return ← failUnsupported
          "S1 normalizer does not support statements after return"
      else
        return (st, .closed)
    i := i + 1
  pure (st, .open_)

/-- Lower one statement into the current open block, sealing blocks for
control-flow. Returns the builder and whether this path is closed. -/
private partial def lowerStmt
    (stmt : SrcStmt) (resultTid : TypeIdV1)
    (st : BodyStateV1) (states : StateTableV1)
    (events : EventTableV1) (errors : ErrorTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (BodyStateV1 × PathStatusV1) := do
  match stmt with
  | .assign target value => do
      match target with
      | .name n =>
          let key := raw n
          -- Match Typed/EffectCheck param-before-state resolution: a bare name
          -- that is bound as a param/local is not a state write target. S1 only
          -- lowers unshadowed state assigns; param assigns fail closed.
          match envLookup st.env key with
          | some _ =>
              return (← failUnsupported
                s!"S1 assign target must be a state place, not a param '{key}'")
          | none =>
              match stateLookup states key with
              | none =>
                  return (← failUnsupported s!"S1 assign target '{key}' must be a state place")
              | some (sid, expectedTid) =>
                  let (vid, tid, st1) ←
                    lowerExpr value expectedTid st states fns
                  unless tid == expectedTid do
                    return ← failUnsupported
                      s!"S1 assign type mismatch for state '{key}'"
                  let instr : InstructionV1 := {
                    result := none
                    op := .stateStore sid vid
                  }
                  pure ({ st1 with
                    instructions := st1.instructions.push instr
                  }, .open_)
      | .field _ _ => failUnsupported "S1 assign does not support field targets"
      | .index _ _ => failUnsupported "S1 assign does not support index targets"
  -- Explicit bare `return` is rejected at the S1 gate so product compile never
  -- succeeds Normalize and then fails residual alpha `validateBlockShapeV1`
  -- (`Stmt.Return`). Init may still end with implicit terminator-none when the
  -- source omits a return (allowImplicitReturnNone).
  | .return_ none =>
      failUnsupported "S1 normalizer does not support bare return"
  | .return_ (some e) => do
      let (vid, tid, st1) ← lowerExpr e resultTid st states fns
      unless tid == resultTid do
        return ← failUnsupported "S1 return expression type mismatch"
      pure (sealCurrentBlock st1 (TerminatorV1.return_ (some vid)), .closed)
  | .assert_ condition errorRef => do
      match errorRef with
      | some _ =>
          failUnsupported "S1 normalizer does not support assert-else"
      | none => do
          let (i1, boolTid) := internShape st.interner .bool
          let st0 := { st with interner := i1 }
          let (condVid, condTid, st1) ← lowerExpr condition boolTid st0 states fns
          unless condTid == boolTid do
            return ← failUnsupported "S1 assert condition must be Bool"
          let instr : InstructionV1 := {
            result := none
            op := .assert_ condVid none #[]
          }
          pure ({ st1 with
            instructions := st1.instructions.push instr
          }, .open_)
  | .if_ condition thenBlock elseBlock? => do
      let (i1, boolTid) := internShape st.interner .bool
      let st0 := { st with interner := i1 }
      let (condVid, condTid, st1) ← lowerExpr condition boolTid st0 states fns
      unless condTid == boolTid do
        return ← failUnsupported "S1 if condition must be Bool"
      -- Seal the condition block with a placeholder else target; nested
      -- control-flow inside a branch may seal many blocks, so exact else/join
      -- ids are only known after each branch completes (back-patch below).
      let condIdx := st1.blocks.size
      let thenId := UInt32.ofNat (condIdx + 1)
      let st2 := sealCurrentBlock st1 (.branch condVid
        { blockId := thenId, args := #[] } { blockId := 0, args := #[] })
      -- Arms start from the pre-branch env; lets stay scoped to their arm.
      let savedEnv := st1.env
      let (stT, thenStatus) ← lowerStmts thenBlock.statements resultTid
        { st2 with env := savedEnv } states events errors fns
      let (stT, thenJump?) := match thenStatus with
        | .closed => (stT, none)
        | .open_ =>
            let jumpIdx := stT.blocks.size
            (sealCurrentBlock stT (.jump { blockId := 0, args := #[] }), some jumpIdx)
      -- elseId is only known AFTER the then block completes (nested control
      -- flow may have sealed many blocks in between).
      let elseId := UInt32.ofNat stT.blocks.size
      let (stE, elseJump?, elseClosed) ← match elseBlock? with
        | some elseBlock => do
            let (stE0, status) ← lowerStmts elseBlock.statements resultTid
              { stT with env := savedEnv } states events errors fns
            match status with
            | .closed => pure (stE0, none, true)
            | .open_ =>
                let jumpIdx := stE0.blocks.size
                pure (sealCurrentBlock stE0 (.jump { blockId := 0, args := #[] }),
                  some jumpIdx, false)
        -- Absent else: no block at all; the branch else target is the join.
        | none => pure (stT, none, false)
      match thenStatus, elseClosed with
      | .closed, true =>
          -- Both branches returned: no join block; only the else target needs
          -- a back-patch. Ids stay dense (no slot is burned for a join).
          pure (patchBranchElse stE condIdx elseId, .closed)
      | _, _ =>
          let joinId := UInt32.ofNat stE.blocks.size
          -- Without an else block the else path falls directly into the join.
          let elseTarget := if elseBlock?.isSome then elseId else joinId
          let stP := patchBranchElse stE condIdx elseTarget
          let stP := match thenJump? with
            | some j => patchJumpTarget stP j joinId
            | none => stP
          let stP := match elseJump? with
            | some j => patchJumpTarget stP j joinId
            | none => stP
          pure ({ stP with env := savedEnv }, .open_)
  | .match_ scrutinee arms => do
      if arms.isEmpty then
        return ← failUnsupported "S1 match requires at least one arm"
      let (iU, u64Tid) := internShape st.interner (.uint 64)
      let (iB, boolTid) := internShape iU .bool
      let st0 := { st with interner := iB }
      -- Scrutinee must be UInt64 or Bool in this envelope.
      let (scrutVid, scrutTid, st1) ←
        match scrutinee with
        | .literal (.bool _) =>
            lowerExpr scrutinee boolTid st0 states fns
        | _ =>
            lowerExpr scrutinee u64Tid st0 states fns
      unless scrutTid == u64Tid || scrutTid == boolTid do
        return ← failUnsupported "S1 match scrutinee must be UInt64 or Bool"
      -- Split arms into literal cases and exactly-one catch-all (wildcard or
      -- bind); CheckV1 already requires a catch-all for UInt64/Bool scrutinee.
      let mut caseArms : Array (UInt64 × Bool × SrcBlock) := #[]
      let mut defaultArm? : Option (Option SourceNameComponentV1 × SrcBlock) := none
      for arm in arms do
        match arm.pattern with
        | .literal lit =>
            match lit with
            | .integer magnitude =>
                unless scrutTid == u64Tid do
                  return ← failUnsupported
                    "S1 match integer literal requires a UInt64 scrutinee"
                unless magnitude < UInt64.size do
                  return ← failUnsupported "S1 match integer literal is out of range"
                if caseArms.any (fun (v, _, _) => v == UInt64.ofNat magnitude) then
                  return ← failUnsupported "S1 match has duplicate literal cases"
                caseArms := caseArms.push (UInt64.ofNat magnitude, false, arm.body)
            | .bool value =>
                unless scrutTid == boolTid do
                  return ← failUnsupported
                    "S1 match Bool literal requires a Bool scrutinee"
                if caseArms.any (fun (_, b, _) => b == value) then
                  return ← failUnsupported "S1 match has duplicate literal cases"
                caseArms := caseArms.push (UInt64.ofNat (if value then 1 else 0), true, arm.body)
            | .string _ =>
                return ← failUnsupported "S1 match does not support string literal patterns"
        | .wildcard =>
            if defaultArm?.isSome then
              return ← failUnsupported "S1 match has more than one catch-all arm"
            defaultArm? := some (none, arm.body)
        | .bind name =>
            if defaultArm?.isSome then
              return ← failUnsupported "S1 match has more than one catch-all arm"
            defaultArm? := some (some name, arm.body)
        | .constructor _ _ =>
            return ← failUnsupported "S1 match does not support constructor patterns"
      let (defaultBinder?, defaultBody) ← match defaultArm? with
        | some da => pure da
        | none =>
            return ← failUnsupported
              "S1 match on UInt64/Bool requires a catch-all arm"
      -- Case order on the wire follows literal-arm source order. A catch-all-
      -- only match is straight-line: the binder binds the scrutinee and the
      -- arm body lowers inline into the current block (no block, no jump;
      -- the structure gate requires nonempty switch cases, so a switch would
      -- be invalid here anyway).
      if caseArms.isEmpty then
        let stD := match defaultBinder? with
          | none => st1
          | some name => { st1 with env := envInsert st1.env (raw name) scrutVid scrutTid }
        let (stR, rStatus) ← lowerStmts defaultBody.statements resultTid stD
          states events errors fns
        -- The catch-all binder and body lets stay scoped to the arm.
        pure ({ stR with env := st1.env }, rStatus)
      else
        let scrutIdx := st1.blocks.size
        let st2 := sealCurrentBlock st1 (.switch scrutVid #[] none)
        -- Lower each literal arm body into its own block; record exact case
        -- targets and jump-back-patch slots as we go. Every arm starts from
        -- the pre-match env so lets stay scoped to their arm.
        let savedEnv := st1.env
        let mut stA := st2
        let mut caseTargets : Array BlockIdV1 := #[]
        let mut jumpSlots : Array Nat := #[]
        let mut closedCount : Nat := 0
        for (_, _, body) in caseArms do
          caseTargets := caseTargets.push (UInt32.ofNat stA.blocks.size)
          let (stB, status) ← lowerStmts body.statements resultTid
            { stA with env := savedEnv } states events errors fns
          stA := stB
          match status with
          | .closed => closedCount := closedCount + 1
          | .open_ =>
              jumpSlots := jumpSlots.push stA.blocks.size
              stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
        -- Default arm: optional binder maps to the scrutinee value.
        let defaultId := UInt32.ofNat stA.blocks.size
        let stD := match defaultBinder? with
          | none => { stA with env := savedEnv }
          | some name => { stA with env := envInsert savedEnv (raw name) scrutVid scrutTid }
        let (stD, dStatus) ← lowerStmts defaultBody.statements resultTid stD states events errors fns
        stA := stD
        match dStatus with
        | .closed => closedCount := closedCount + 1
        | .open_ =>
            jumpSlots := jumpSlots.push stA.blocks.size
            stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
        let switchCases : Array SwitchCaseV1 := caseArms.mapIdx fun i (value, isBool, _) =>
          {
            typeId := if isBool then boolTid else u64Tid
            valueBytes :=
              if isBool then encodeBool (value == 1)
              else encodeU64le value
            target := { blockId := caseTargets[i]!, args := #[] }
          }
        if closedCount == caseArms.size + 1 then
          -- Every arm returned: no join block; only the switch needs the
          -- final case/default targets.
          let stP := patchSwitch stA scrutIdx switchCases (some {
            blockId := defaultId, args := #[] })
          pure (stP, .closed)
        else
          let joinId := UInt32.ofNat stA.blocks.size
          let stP := patchSwitch stA scrutIdx switchCases (some {
            blockId := defaultId, args := #[] })
          let stP := jumpSlots.foldl (fun acc j => patchJumpTarget acc j joinId) stP
          pure ({ stP with env := savedEnv }, .open_)
  | .let_ name typeAnn value => do
      -- Immutable SSA binding: the RHS evaluates exactly once and the name is
      -- scoped to the enclosing block (branch/loop bodies save and restore
      -- the env). Reassignment via `assign` fails closed at the assign arm
      -- because env-bound names are never state targets.
      let (i1, tid) ← match typeAnn with
        | some ann => internSourceType st.interner ann
        | none => synthLetExpectedV1 value st states fns
      requireLetTypeId i1.types tid "let binding"
      let st0 := { st with interner := i1 }
      let (vid, vtid, st1) ← lowerExpr value tid st0 states fns
      unless vtid == tid do
        return ← failUnsupported s!"S1 let '{raw name}' type mismatch"
      pure ({ st1 with env := envInsert st1.env (raw name) vid tid }, .open_)
  | .for_ binder start endExclusive bound body => do
      let (iU, u64Tid) := internShape st.interner (.uint 64)
      let (iB, boolTid) := internShape iU .bool
      let st0 := { st with interner := iB }
      let (sVid, sTid, st1) ← lowerExpr start u64Tid st0 states fns
      unless sTid == u64Tid do
        return ← failUnsupported "S1 for start must be UInt64"
      let (eVid, eTid, st2) ← lowerExpr endExclusive u64Tid st1 states fns
      unless eTid == u64Tid do
        return ← failUnsupported "S1 for end must be UInt64"
      unless bound ≤ maxWireLoopBoundV1 do
        return ← failUnsupported "S1 for bound exceeds the wire loop maximum"
      -- Pre-header: enter the loop with the start value. The header id is
      -- the next block after the sealed pre-header. The induction param
      -- draws from the canonical block-param range (creation order ==
      -- BlockId order), keeping instruction results above it.
      let headerIdx := st2.blocks.size + 1
      let headerId := UInt32.ofNat headerIdx
      let iVid := UInt32.ofNat (st2.callableParamCount + st2.nextBlockParamOrdinal)
      let st3 := { st2 with nextBlockParamOrdinal := st2.nextBlockParamOrdinal + 1 }
      let st4 := sealCurrentBlock st3 (.jump { blockId := headerId, args := #[sVid] })
      -- Header: the induction variable is the sole block param; the condition
      -- `i < endExclusive` gates the body. The latch's `i + 1` cannot
      -- overflow: the body only runs while i < end ≤ UInt64.max.
      let st5 := { st4 with currentParams := #[{ valueId := iVid, typeId := u64Tid }] }
      let condVid := st5.nextValueId
      let condInstr : InstructionV1 := {
        result := some { valueId := condVid, typeId := boolTid }
        op := .binary BinaryOpV1.lt iVid eVid
      }
      let bodyId := UInt32.ofNat (st5.blocks.size + 1)
      let st6 := sealCurrentBlock { st5 with
        instructions := st5.instructions.push condInstr
        nextValueId := condVid + 1 } (.branch condVid
          { blockId := bodyId, args := #[] } { blockId := 0, args := #[] })
      -- Body: the binder scopes to the induction param; the pre-loop env is
      -- restored at the exit so body lets never leak past the loop.
      let savedEnv := st2.env
      let (stB, bodyStatus) ← lowerStmts body.statements resultTid
        { st6 with env := envInsert savedEnv (raw binder) iVid u64Tid }
        states events errors fns
      let stL ← match bodyStatus with
        | .open_ =>
            let latchIdx := stB.blocks.size
            let oneVid := stB.nextValueId
            let oneInstr : InstructionV1 := {
              result := some { valueId := oneVid, typeId := u64Tid }
              op := .literal u64Tid (encodeU64le 1)
            }
            let incVid := oneVid + 1
            let incInstr : InstructionV1 := {
              result := some { valueId := incVid, typeId := u64Tid }
              op := .binary BinaryOpV1.add iVid oneVid
            }
            let stSealed := sealCurrentBlock { stB with
              instructions := (stB.instructions.push oneInstr).push incInstr
              nextValueId := incVid + 1 }
              (.jump { blockId := headerId, args := #[incVid] })
            pure { stSealed with
              loopBounds := stSealed.loopBounds.push {
                header := headerId
                backEdgeFrom := UInt32.ofNat latchIdx
                maxIterations := bound
              } }
        -- Body returns/reverts on every path: no back edge exists, so no
        -- loop-bound entry is recorded (the header degenerates to a one-shot).
        | .closed => pure stB
      -- Exit: back-patch the header's else target and restore the env.
      let exitId := UInt32.ofNat stL.blocks.size
      pure ({ patchBranchElse stL headerIdx exitId with env := savedEnv }, .open_)
  | .revert errorName args => do
      let key := raw errorName
      match errorLookup errors key with
      | none =>
          failUnsupported s!"S1 revert error '{key}' is not declared"
      | some (errorId, fieldTids) => do
          unless args.size == fieldTids.size do
            return ← failUnsupported
              s!"S1 revert '{key}' expects {fieldTids.size} arguments, got {args.size}"
          let mut st' := st
          let mut argIds : Array ValueIdV1 := #[]
          for (arg, fieldTid) in args.zip fieldTids do
            let (vid, argTid, st1) ← lowerExpr arg fieldTid st' states fns
            unless argTid == fieldTid do
              return ← failUnsupported s!"S1 revert '{key}' argument type mismatch"
            argIds := argIds.push vid
            st' := st1
          pure (sealCurrentBlock st' (TerminatorV1.revert errorId argIds), .closed)
  | .emit eventName args => do
      let key := raw eventName
      match eventLookup events key with
      | none =>
          failUnsupported s!"S1 emit event '{key}' is not declared"
      | some (eventId, fieldTids) => do
          unless args.size == fieldTids.size do
            return ← failUnsupported
              s!"S1 emit '{key}' expects {fieldTids.size} arguments, got {args.size}"
          let mut st' := st
          let mut argIds : Array ValueIdV1 := #[]
          for (arg, fieldTid) in args.zip fieldTids do
            let (vid, argTid, st1) ← lowerExpr arg fieldTid st' states fns
            unless argTid == fieldTid do
              return ← failUnsupported s!"S1 emit '{key}' argument type mismatch"
            argIds := argIds.push vid
            st' := st1
          let instr : InstructionV1 := {
            result := none
            op := .emit st'.nextEffectId eventId argIds
          }
          pure ({ st' with
            instructions := st'.instructions.push instr
            nextEffectId := st'.nextEffectId + 1
          }, .open_)
  | .call externalCall => do
      -- Sync external call: a statement effect with no result value (v1).
      -- The callee is an opaque qualified name (at least two components per
      -- the wire shape gate), resolved at deployment, never by the compiler.
      let callee := externalCall.callee
      let calleeComponents := (NonEmptyArray.toArray callee.components).map (·.raw)
      unless calleeComponents.size ≥ 2 do
        return ← failUnsupported
          s!"S1 call callee must have at least two components"
      let qn ← match parseQualifiedName calleeComponents with
        | .ok qn => pure qn
        | .error e => failUnsupported s!"S1 call callee: {e}"
      let (iU, u64Tid) := internShape st.interner (.uint 64)
      let st0 := { st with interner := iU }
      let mut st' := st0
      let mut argIds : Array ValueIdV1 := #[]
      for arg in externalCall.args do
        let (vid, tid, st1) ← lowerExpr arg u64Tid st' states fns
        unless tid == u64Tid do
          return ← failUnsupported s!"S1 call argument must be UInt64"
        argIds := argIds.push vid
        st' := st1
      let instr : InstructionV1 := {
        result := none
        op := .externalCall st'.nextEffectId qn argIds
      }
      pure ({ st' with
        instructions := st'.instructions.push instr
        nextEffectId := st'.nextEffectId + 1
      }, .open_)
  | .schedule externalCall => do
      -- Async workflow schedule: same statement-effect shape as call.
      let callee := externalCall.callee
      let calleeComponents := (NonEmptyArray.toArray callee.components).map (·.raw)
      unless calleeComponents.size ≥ 2 do
        return ← failUnsupported
          s!"S1 schedule callee must have at least two components"
      let qn ← match parseQualifiedName calleeComponents with
        | .ok qn => pure qn
        | .error e => failUnsupported s!"S1 schedule callee: {e}"
      let (iU, u64Tid) := internShape st.interner (.uint 64)
      let st0 := { st with interner := iU }
      let mut st' := st0
      let mut argIds : Array ValueIdV1 := #[]
      for arg in externalCall.args do
        let (vid, tid, st1) ← lowerExpr arg u64Tid st' states fns
        unless tid == u64Tid do
          return ← failUnsupported s!"S1 schedule argument must be UInt64"
        argIds := argIds.push vid
        st' := st1
      let instr : InstructionV1 := {
        result := none
        op := .schedule st'.nextEffectId qn argIds
      }
      pure ({ st' with
        instructions := st'.instructions.push instr
        nextEffectId := st'.nextEffectId + 1
      }, .open_)

end

private def lowerBlock
    (body : SrcBlock) (params : Array ParameterV1) (resultTid : TypeIdV1)
    (interner : TypeInternerV1) (states : StateTableV1)
    (events : EventTableV1) (errors : ErrorTableV1) (fns : FnTableV1)
    (allowImplicitReturnNone : Bool) :
    Except NormalizeErrorV1 (Array BlockV1 × Array LoopBoundV1 × TypeInternerV1) := do
  let mut env := emptyEnv
  for p in params do
    env := envInsert env p.name p.valueId p.typeId
  let st : BodyStateV1 := {
    blocks := #[]
    instructions := #[]
    currentParams := #[]
    loopBounds := #[]
    nextValueId := UInt32.ofNat (params.size + countForLoopsStmtsV1 body.statements)
    nextBlockParamOrdinal := 0
    callableParamCount := params.size
    nextEffectId := 0
    env := env
    interner := interner
  }
  let (st', status) ← lowerStmts body.statements resultTid st states events errors fns
  -- Canonical ascending (header, backEdgeFrom) loop-bound order.
  let finish := fun (stF : BodyStateV1) =>
    (stF.blocks,
      stF.loopBounds.qsort (fun a b =>
        a.header < b.header || (a.header == b.header && a.backEdgeFrom < b.backEdgeFrom)),
      stF.interner)
  match status with
  | .closed =>
      -- Body ended in return on every path; the trailing open block (if any
      -- instructions were sealed already) is complete.
      pure (finish st')
  | .open_ =>
      if allowImplicitReturnNone then
        let st'' := sealCurrentBlock st' (TerminatorV1.return_ none)
        pure (finish st'')
      else
        failUnsupported "S1 normalizer requires explicit return for entry/view"

private def lowerParams
    (ps : Array ParamV1) (interner : TypeInternerV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × Array ParameterV1) := do
  let mut interner := interner
  let mut out : Array ParameterV1 := #[]
  let mut i : Nat := 0
  for p in ps do
    let (interner', tid) ← internSourceType interner p.type_
    interner := interner'
    requireUInt64TypeId interner.types tid s!"parameter '{raw p.name}'"
    out := out.push {
      valueId := UInt32.ofNat i
      name := raw p.name
      typeId := tid
      visibility := mapVisibility p.visibility
    }
    i := i + 1
  pure (interner, out)

private def mkCallable
    (id : CallableIdV1) (kind : CallableKindV1) (name : Option String)
    (params : Array ParameterV1) (result : CallableResultV1)
    (blocks : Array BlockV1) (loopBounds : Array LoopBoundV1) :
    CallableV1 :=
  {
    id
    kind
    name
    params
    result
    entryBlock := 0
    blocks
    loopBounds
    invariantSteps := none
  }

/-- Core lowering after Typed CheckV1 has succeeded.

  Two-pass over ProgramV1 items (not NameResolution tables):
  1. Collect/validate all public UInt64 states into a complete logicalState table
     (IDs are source-order among state decls, independent of callable position).
  2. Lower init/entry/view bodies against that complete table.
-/
def lowerProgramDataV1 (source : ValidatedSourceV1) :
    Except NormalizeErrorV1 SemanticProgramDataV1 := do
  let qn ← programIdentityToQualifiedNameV1 source.programIdentity
  let program := source.program
  let mut interner := emptyInterner
  let mut stateRows : Array StateDeclV1 := #[]
  let mut stateTable : StateTableV1 := ⟨#[]⟩
  let mut eventRows : Array EventDeclV1 := #[]
  let mut eventTable : EventTableV1 := ⟨#[]⟩
  let mut errorRows : Array ErrorDeclV1 := #[]
  let mut errorTable : ErrorTableV1 := ⟨#[]⟩

  -- Pass 1: complete state/event/error tables (source order among those
  -- items only). Event/error fields stay public UInt64 in this envelope.
  for item in program.items do
    match item with
    | .state s =>
        unless s.visibility == ProofForgeV2.Source.AstV1.VisibilityV1.public_ do
          return ← failUnsupported
            s!"S1 normalizer supports only public state, got non-public '{raw s.name}'"
        let (interner', tid) ← internSourceType interner s.type_
        interner := interner'
        requireUInt64TypeId interner.types tid s!"state '{raw s.name}'"
        let sid := UInt32.ofNat stateRows.size
        stateRows := stateRows.push {
          id := sid
          name := raw s.name
          typeId := tid
          visibility := VisibilityV1.public_
        }
        stateTable := {
          rows := stateTable.rows.push (raw s.name, sid, tid)
        }
    | .event d =>
        let mut fieldTids : Array TypeIdV1 := #[]
        let mut fields : Array InterfaceFieldV1 := #[]
        for f in d.params do
          unless f.visibility == ProofForgeV2.Source.AstV1.VisibilityV1.public_ do
            return ← failUnsupported
              s!"S1 event '{raw d.name}' field '{raw f.name}' must be public"
          let (interner', tid) ← internSourceType interner f.type_
          interner := interner'
          requireUInt64TypeId interner.types tid
            s!"event '{raw d.name}' field '{raw f.name}'"
          fieldTids := fieldTids.push tid
          fields := fields.push {
            name := raw f.name
            typeId := tid
            visibility := VisibilityV1.public_
          }
        let eid := UInt32.ofNat eventRows.size
        eventRows := eventRows.push { id := eid, name := raw d.name, fields }
        eventTable := { rows := eventTable.rows.push (raw d.name, eid, fieldTids) }
    | .error d =>
        let mut fieldTids : Array TypeIdV1 := #[]
        let mut fields : Array InterfaceFieldV1 := #[]
        for f in d.params do
          unless f.visibility == ProofForgeV2.Source.AstV1.VisibilityV1.public_ do
            return ← failUnsupported
              s!"S1 error '{raw d.name}' field '{raw f.name}' must be public"
          let (interner', tid) ← internSourceType interner f.type_
          interner := interner'
          requireUInt64TypeId interner.types tid
            s!"error '{raw d.name}' field '{raw f.name}'"
          fieldTids := fieldTids.push tid
          fields := fields.push {
            name := raw f.name
            typeId := tid
            visibility := VisibilityV1.public_
          }
        let eid := UInt32.ofNat errorRows.size
        errorRows := errorRows.push { id := eid, name := raw d.name, fields }
        errorTable := { rows := errorTable.rows.push (raw d.name, eid, fieldTids) }
    | _ => pure ()

  -- Pass 2a: fn signature table for localCall resolution. CallableIds follow
  -- the unified source order of init/entry/view/fn items (the same order
  -- pass 2 lowers them). Fn params/results stay public scalars.
  let mut fnTable : FnTableV1 := ⟨#[]⟩
  let mut fnCallableOrdinal : Nat := 0
  for item in program.items do
    match item with
    | .fn d =>
        let mut paramTids : Array TypeIdV1 := #[]
        for p in d.params do
          unless p.visibility == ProofForgeV2.Source.AstV1.VisibilityV1.public_ do
            return ← failUnsupported
              s!"S1 fn '{raw d.name}' param '{raw p.name}' must be public"
          let (interner', tid) ← internSourceType interner p.type_
          interner := interner'
          requireUInt64TypeId interner.types tid
            s!"fn '{raw d.name}' param '{raw p.name}'"
          paramTids := paramTids.push tid
        let (interner', resultTid) ← internSourceType interner d.result
        interner := interner'
        requireScalarResultTypeId interner.types resultTid s!"fn '{raw d.name}' result"
        let fnRow := (raw d.name, UInt32.ofNat fnCallableOrdinal, paramTids, resultTid)
        fnTable := { rows := fnTable.rows.push fnRow }
    | _ => pure ()
    match item with
    | .init _ | .entry _ | .view _ | .fn _ =>
        fnCallableOrdinal := fnCallableOrdinal + 1
    | _ => pure ()

  -- Pass 2: lower supported callables; reject unsupported item kinds.
  let mut callables : Array CallableV1 := #[]
  let mut callableId : Nat := 0
  for item in program.items do
    match item with
    | .state _ => pure ()
    | .init d =>
        let (interner', params) ← lowerParams d.params interner
        interner := interner'
        let (interner'', unitTid) := internShape interner .unit
        interner := interner''
        let (blocks, loopBounds, interner''') ←
          lowerBlock d.body params unitTid interner stateTable eventTable errorTable fnTable true
        interner := interner'''
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .initializer none params
          { typeId := unitTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .entry e =>
        let (interner', params) ← lowerParams e.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner e.result
        interner := interner''
        requireScalarResultTypeId interner.types resultTid s!"entry '{raw e.name}' result"
        let (blocks, loopBounds, interner''') ←
          lowerBlock e.body params resultTid interner stateTable eventTable errorTable fnTable false
        interner := interner'''
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .entry (some (raw e.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .view v =>
        let (interner', params) ← lowerParams v.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner v.result
        interner := interner''
        requireScalarResultTypeId interner.types resultTid s!"view '{raw v.name}' result"
        let (blocks, loopBounds, interner''') ←
          lowerBlock v.body params resultTid interner stateTable eventTable errorTable fnTable false
        interner := interner'''
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .view (some (raw v.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .struct _ =>
        return ← failUnsupported "S1 normalizer does not support struct"
    | .enum _ =>
        return ← failUnsupported "S1 normalizer does not support enum"
    | .const _ =>
        return ← failUnsupported "S1 normalizer does not support const"
    | .event _ => pure ()
    | .error _ => pure ()
    | .fn d =>
        let (interner', params) ← lowerParams d.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner d.result
        interner := interner''
        requireScalarResultTypeId interner.types resultTid s!"fn '{raw d.name}' result"
        -- Fn purity: the body resolves bare places against an empty state
        -- table, so any state name fails closed (fn effects are revert-only).
        let emptyStates : StateTableV1 := ⟨#[]⟩
        let (blocks, loopBounds, interner''') ←
          lowerBlock d.body params resultTid interner emptyStates eventTable errorTable fnTable false
        interner := interner'''
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .pureFn (some (raw d.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .invariant _ =>
        return ← failUnsupported "S1 normalizer does not support invariant"
    | .extensionReq _ =>
        return ← failUnsupported "S1 normalizer does not support extension"
    | .proof _ =>
        return ← failUnsupported "S1 normalizer does not support proof"

  -- S2: freeze exact ProgramRequirementsV1 before encode/hash.
  let requirements ← match freezeProgramRequirementsV1 program with
    | .ok r => pure r
    | .error detail => failUnsupported s!"S2 requirements freeze: {detail}"
  pure {
    qualifiedName := qn
    types := interner.types
    constants := #[]
    logicalState := stateRows
    events := eventRows
    errors := errorRows
    callables := callables
    invariants := #[]
    requirements
  }

/-- Structure-gated encode is the sole path to a SemanticProgramV1 carrier. -/
def encodeCarrierV1 (data : SemanticProgramDataV1) :
    Except NormalizeErrorV1 SemanticProgramV1 :=
  match encodeSemanticProgramDataV1 data with
  | .ok bytes => pure ⟨bytes⟩
  | .error e => .error (.wire e)

/-- Non-product S1/S2 normalizer entry: unlocated CheckV1 gate → lower → encode.

  Hand-built fixtures and provenance helpers only. Product Compiler/CLI must use
  `normalizeProgramLocatedV1` (located CheckV1 + DiagnosticResultV1).
-/
def normalizeProgramV1 (source : ValidatedSourceV1) :
    Except NormalizeErrorV1 SemanticProgramV1 := do
  let typed := checkProgramTypedResultV1 source
  unless typed.ok && typed.analysisComplete do
    return ← .error (.typedNotOk typed.diagnostics)
  let data ← lowerProgramDataV1 source
  encodeCarrierV1 data

/-- Closed wire-error summary for product diagnostics (no Lean `repr`). -/
private def renderSemanticWireErrorSummaryV1 : SemanticWireErrorV1 → String
  | .truncated => "truncated"
  | .limitExceeded => "limitExceeded"
  | .badMagic => "badMagic"
  | .badTag => "badTag"
  | .badFieldCount => "badFieldCount"
  | .badScalar => "badScalar"
  | .nonCanonical => "nonCanonical"
  | .duplicate => "duplicate"
  | .badReference => "badReference"
  | .badType => "badType"
  | .badCfg => "badCfg"
  | .badRequirement => "badRequirement"
  | .badProvenance => "badProvenance"
  | .trailingBytes => "trailingBytes"

/-- Map post-CheckV1 Normalize failures into a failure bundle. -/
private def normalizeFailureBundle (err : NormalizeErrorV1) : DiagnosticBundleV1 :=
  match err with
  | .typedNotOk diags => mkFailureBundleV1 diags
  | .unsupported detail =>
      mkFailureBundleV1 #[DiagnosticV1.make .sourceInvalid detail]
  | .identity detail =>
      mkFailureBundleV1 #[DiagnosticV1.make .sourceInvalid detail]
  | .wire e =>
      mkFailureBundleV1 #[
        DiagnosticV1.make .sourceInvalid
          s!"semantic structure gate: {renderSemanticWireErrorSummaryV1 e}"]

/-- Public-safe PF-INTERNAL when located materialization is impossible
    (foreign inventory / hash mismatch / path locate failure). No input leak. -/
private def locateInternalBundle : DiagnosticBundleV1 :=
  mkFailureBundleV1 #[
    DiagnosticV1.make .internal "located typed analysis failed"
      (actual := some (PfJson.string "typedLocate"))]

/-- Sole product Normalize entry (B8b).

    Consumes the exact product Loader pair. Calls
    `checkProgramTypedLocatedResultV1` **exactly once** (all-or-nothing locate;
    no unlocated CheckV1 re-run). On typed failure, preserves the complete
    located diagnostic set and lets `mkFailureBundleV1` perform the sole
    normative sort/dedupe/cap. On located success, lowers S1 and structure-gated encodes.
    Locate/hash impossibilities → PF-INTERNAL. Does not call `normalizeProgramV1`.
-/
def normalizeProgramLocatedV1
    (source : ValidatedSourceV1) (inv : OriginInventoryV1) :
    DiagnosticResultV1 SemanticProgramV1 :=
  match checkProgramTypedLocatedResultV1 source inv with
  | .error _ => .error locateInternalBundle
  | .ok located =>
      if !(located.ok && located.analysisComplete) then
        .error (mkFailureBundleV1 located.diagnostics)
      else
        match lowerProgramDataV1 source with
        | .error e => .error (normalizeFailureBundle e)
        | .ok data =>
            match encodeCarrierV1 data with
            | .ok carrier => .ok carrier
            | .error e => .error (normalizeFailureBundle e)

private def mapProvenanceError (e : ProvenanceBuildErrorV1) :
    NormalizeErrorV1 :=
  match e with
  | .identity d => .identity d
  | .inventory d => .unsupported s!"provenance inventory: {d}"
  | .unsupported d => .unsupported d
  | .wire w => .wire w

/-- Internally rebuild production inventory from immutable frontend inputs.

    Authority never accepts a caller-supplied `SourceNodeInventoryV1`.
-/
private def rebuildTrustedInventoryV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    Except NormalizeErrorV1 SourceNodeInventoryV1 :=
  match buildSourceNodeInventoryV1 source sourcePath spans with
  | .ok inv => pure inv
  | .error e => .error (mapProvenanceError e)

/-- Source-bound authoritative provenance validation (SPEC §6.1 engineering).

    Consumes only trusted immutable inputs:
      * `ValidatedSourceV1` (module + identity + ProgramV1)
      * production `ProjectRelativePath`
      * production span table from the same frontend snapshot

    Never accepts a caller-supplied `SourceNodeInventoryV1`. Internally:
      1. `buildSourceNodeInventoryV1 source sourcePath spans`
      2. `normalizeProgramV1 source` and require exact carrier byte identity
      3. rebuild expected provenance from that trusted inventory and require
         exact equality with the supplied companion

    Coordinated inventory path/span substitution that preserves NodeId set
    cannot self-certify: authority rebuilds path/start/end/nodeId from spans.
    Low-level `buildSemanticProvenanceV1` / Wire `*JoinV1` remain
    caller-trusted helpers only.
-/
def validateSemanticProvenanceV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))
    (program : SemanticProgramV1)
    (provenance : SemanticProvenanceV1) :
    Except NormalizeErrorV1 Unit := do
  let trustedInventory ← rebuildTrustedInventoryV1 source sourcePath spans
  let expectedCarrier ← normalizeProgramV1 source
  unless expectedCarrier.canonicalBytes == program.canonicalBytes do
    return ← failIdentity
      "semantic carrier does not match normalizeProgramV1 of source snapshot"
  match rebuildSemanticProvenanceV1 source program trustedInventory with
  | .error e => return ← .error (mapProvenanceError e)
  | .ok expected =>
      unless provenance == expected do
        return ← failIdentity
          "provenance does not exactly match rebuilt attribution for source snapshot"
      pure ()

/-- Source-bound authoritative provenance digest: validate then SHA-256 envelope.

    Same trusted inputs as `validateSemanticProvenanceV1` (no caller inventory).
-/
def semanticProvenanceDigestV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))
    (program : SemanticProgramV1)
    (p : SemanticProvenanceV1) :
    Except NormalizeErrorV1 Digest := do
  validateSemanticProvenanceV1 source sourcePath spans program p
  match encodeSemanticProvenanceV1 p with
  | .error e => .error (.wire e)
  | .ok bytes =>
      match decodeSemanticProvenanceV1 bytes with
      | .error e => .error (.wire e)
      | .ok _ => pure (sha256Bytes bytes)

/-- Sole authoritative construction path for S2 Counter carrier + provenance.

    Builds inventory internally from `source + sourcePath + spans`, normalizes,
    builds provenance, and runs public authority validation. Does not accept a
    caller inventory. Transient inventory can be rebuilt from the same immutable
    inputs via `buildSourceNodeInventoryV1` when tests need it.
-/
def normalizeProgramWithProvenanceV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    Except NormalizeErrorV1 (SemanticProgramV1 × SemanticProvenanceV1) := do
  let trustedInventory ← rebuildTrustedInventoryV1 source sourcePath spans
  let carrier ← normalizeProgramV1 source
  let provenance ← match buildSemanticProvenanceV1 source carrier trustedInventory with
    | .ok p => pure p
    | .error e => return ← .error (mapProvenanceError e)
  validateSemanticProvenanceV1 source sourcePath spans carrier provenance
  pure (carrier, provenance)

end ProofForgeV2.Semantic.NormalizeV1
