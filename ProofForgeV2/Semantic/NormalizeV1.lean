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
      Bool literal, checked binary add/sub on UInt64, and the six UInt64
      comparisons (==/!=/</<=/>/>=) producing Bool; integer width is supplied
      by the enclosing typed context, comparison operands are always UInt64
    * types: anonymous UInt64 + Unit (init result) + Bool (comparison results,
      Bool literals); one TypeId per distinct shape, interned on first actual
      use in source traversal order. State/parameter positions stay
      UInt64-only; entry/view results may be UInt64, Unit, or Bool
    * callables: multi-block forward-only CFG (entryBlock=0, dense block ids,
      no block params, empty loopBounds, invariantSteps=none; every emitted
      edge points to a higher block id, so no back edges exist);
      empty constants/events/errors/invariants
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
    * broadening beyond the forward-only public UInt64 add/sub + comparison +
      bare-assert + if/match-literal envelope (block params, loops, let
      bindings, match expressions, aggregates, effects)
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

/-- Multi-block lowering accumulator for one callable body. The interner is
live: comparison/Bool-literal lowering interns shapes on first actual use so
existing programs keep byte-identical type tables. `blocks` holds completed
blocks in id order; `instructions` accumulates the current open block. -/
structure BodyStateV1 where
  blocks : Array BlockV1
  instructions : Array InstructionV1
  nextValueId : ValueIdV1
  env : LocalEnvV1
  interner : TypeInternerV1

/-- Seal the current open block with a terminator and start a fresh one. Block
ids are dense (`id == blocks.size` at seal time) and every edge emitted by
this normalizer points forward, so `loopBounds` stays empty. -/
private def sealCurrentBlock (st : BodyStateV1) (term : TerminatorV1) : BodyStateV1 :=
  { st with
    blocks := st.blocks.push {
      id := UInt32.ofNat st.blocks.size
      params := #[]
      instructions := st.instructions
      terminator := term
    }
    instructions := #[] }

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
    (st : BodyStateV1) (states : StateTableV1) :
    Except NormalizeErrorV1 (ValueIdV1 × TypeIdV1 × BodyStateV1) :=
  match expr with
  | .place p => do
      let (vid, tid, st1) ← lowerPlace p st states
      unless tid == expectedTid do
        return ← failUnsupported "S1 place type does not match enclosing expected type"
      pure (vid, tid, st1)
  | .binary op lhs rhs => do
      let srcOp := op
      let isAdd := srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.add
      let isSub := srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.sub
      let cmpOp? : Option BinaryOpV1 :=
        if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.eq then some BinaryOpV1.eq
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ne then some BinaryOpV1.ne
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.lt then some BinaryOpV1.lt
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.le then some BinaryOpV1.le
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.gt then some BinaryOpV1.gt
        else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ge then some BinaryOpV1.ge
        else none
      if isAdd || isSub then do
        let semanticOp := if isAdd then BinaryOpV1.add else BinaryOpV1.sub
        requireExpectedUInt64 st.interner.types expectedTid "binary checked arithmetic"
        -- Preserve source evaluation / ValueId order: lhs, then rhs, then op.
        let (lVid, lTid, st1) ← lowerExpr lhs expectedTid st states
        let (rVid, rTid, st2) ← lowerExpr rhs expectedTid st1 states
        unless lTid == expectedTid && rTid == expectedTid do
          return ← failUnsupported
            "S1 binary checked arithmetic requires expected UInt64 operands"
        let vid := st2.nextValueId
        let instr : InstructionV1 := {
          result := some { valueId := vid, typeId := expectedTid }
          op := .binary semanticOp lVid rVid
        }
        pure (vid, expectedTid, { st2 with
          instructions := st2.instructions.push instr
          nextValueId := vid + 1
        })
      else
        match cmpOp? with
        | some semanticOp => do
            -- Comparison operands are UInt64; the result is Bool. Both shapes
            -- intern on first actual use, in source traversal order.
            let (i1, u64Tid) := internShape st.interner (.uint 64)
            let (i2, boolTid) := internShape i1 .bool
            let st0 := { st with interner := i2 }
            let (lVid, lTid, st1) ← lowerExpr lhs u64Tid st0 states
            unless lTid == u64Tid do
              return ← failUnsupported
                "S1 comparison requires UInt64 operands"
            let (rVid, rTid, st2) ← lowerExpr rhs u64Tid st1 states
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
            failUnsupported "S1 normalizer supports only binary add/sub/comparisons"
  | .literal literal =>
      match literal with
      | .integer magnitude => do
          requireExpectedUInt64 st.interner.types expectedTid "integer literal"
          -- CheckV1 owns the user-facing width diagnostic. This defensive seam
          -- still rejects direct lowerProgramDataV1 misuse instead of allowing
          -- UInt64.ofNat to truncate modulo 2^64.
          unless magnitude < UInt64.size do
            return ← failUnsupported "S1 UInt64 integer literal is out of range"
          let vid := st.nextValueId
          let instr : InstructionV1 := {
            result := some { valueId := vid, typeId := expectedTid }
            op := .literal expectedTid (encodeU64le (UInt64.ofNat magnitude))
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
  | .unary _ _ => failUnsupported "S1 normalizer does not support unary expressions"
  | .localCall _ _ => failUnsupported "S1 normalizer does not support localCall"
  | .match_ _ _ => failUnsupported "S1 normalizer does not support match expressions"

mutual

private partial def lowerStmts
    (stmts : Array SrcStmt) (resultTid : TypeIdV1)
    (st : BodyStateV1) (states : StateTableV1) :
    Except NormalizeErrorV1 (BodyStateV1 × PathStatusV1) := do
  let mut st := st
  let mut i : Nat := 0
  for stmt in stmts do
    let (st', status) ← lowerStmt stmt resultTid st states
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
    (st : BodyStateV1) (states : StateTableV1) :
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
                    lowerExpr value expectedTid st states
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
      let (vid, tid, st1) ← lowerExpr e resultTid st states
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
          let (condVid, condTid, st1) ← lowerExpr condition boolTid st0 states
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
      let (condVid, condTid, st1) ← lowerExpr condition boolTid st0 states
      unless condTid == boolTid do
        return ← failUnsupported "S1 if condition must be Bool"
      -- Seal the condition block with a placeholder else target; nested
      -- control-flow inside a branch may seal many blocks, so exact else/join
      -- ids are only known after each branch completes (back-patch below).
      let condIdx := st1.blocks.size
      let thenId := UInt32.ofNat (condIdx + 1)
      let st2 := sealCurrentBlock st1 (.branch condVid
        { blockId := thenId, args := #[] } { blockId := 0, args := #[] })
      let (stT, thenStatus) ← lowerStmts thenBlock.statements resultTid st2 states
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
            let (stE0, status) ← lowerStmts elseBlock.statements resultTid stT states
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
          pure (stP, .open_)
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
            lowerExpr scrutinee boolTid st0 states
        | _ =>
            lowerExpr scrutinee u64Tid st0 states
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
        lowerStmts defaultBody.statements resultTid stD states
      else
        let scrutIdx := st1.blocks.size
        let st2 := sealCurrentBlock st1 (.switch scrutVid #[] none)
        -- Lower each literal arm body into its own block; record exact case
        -- targets and jump-back-patch slots as we go.
        let mut stA := st2
        let mut caseTargets : Array BlockIdV1 := #[]
        let mut jumpSlots : Array Nat := #[]
        let mut closedCount : Nat := 0
        for (_, _, body) in caseArms do
          caseTargets := caseTargets.push (UInt32.ofNat stA.blocks.size)
          let (stB, status) ← lowerStmts body.statements resultTid stA states
          stA := stB
          match status with
          | .closed => closedCount := closedCount + 1
          | .open_ =>
              jumpSlots := jumpSlots.push stA.blocks.size
              stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
        -- Default arm: optional binder maps to the scrutinee value.
        let defaultId := UInt32.ofNat stA.blocks.size
        let stD := match defaultBinder? with
          | none => stA
          | some name => { stA with env := envInsert stA.env (raw name) scrutVid scrutTid }
        let (stD, dStatus) ← lowerStmts defaultBody.statements resultTid stD states
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
          pure (stP, .open_)
  | .let_ _ _ _ => failUnsupported "S1 normalizer does not support let"
  | .for_ _ _ _ _ _ => failUnsupported "S1 normalizer does not support for"
  | .revert _ _ => failUnsupported "S1 normalizer does not support revert"
  | .emit _ _ => failUnsupported "S1 normalizer does not support emit"
  | .call _ => failUnsupported "S1 normalizer does not support call"
  | .schedule _ => failUnsupported "S1 normalizer does not support schedule"

end

private def lowerBlock
    (body : SrcBlock) (params : Array ParameterV1) (resultTid : TypeIdV1)
    (interner : TypeInternerV1) (states : StateTableV1)
    (allowImplicitReturnNone : Bool) :
    Except NormalizeErrorV1 (Array BlockV1 × TypeInternerV1) := do
  let mut env := emptyEnv
  for p in params do
    env := envInsert env p.name p.valueId p.typeId
  let st : BodyStateV1 := {
    blocks := #[]
    instructions := #[]
    nextValueId := UInt32.ofNat params.size
    env := env
    interner := interner
  }
  let (st', status) ← lowerStmts body.statements resultTid st states
  match status with
  | .closed =>
      -- Body ended in return on every path; the trailing open block (if any
      -- instructions were sealed already) is complete.
      pure (st'.blocks, st'.interner)
  | .open_ =>
      if allowImplicitReturnNone then
        let st'' := sealCurrentBlock st' (TerminatorV1.return_ none)
        pure (st''.blocks, st''.interner)
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
    (blocks : Array BlockV1) :
    CallableV1 :=
  {
    id
    kind
    name
    params
    result
    entryBlock := 0
    blocks
    loopBounds := #[]
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

  -- Pass 1: complete state table (source order among state items only).
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
        let (blocks, interner''') ←
          lowerBlock d.body params unitTid interner stateTable true
        interner := interner'''
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .initializer none params
          { typeId := unitTid, visibility := VisibilityV1.public_ } blocks)
        callableId := callableId + 1
    | .entry e =>
        let (interner', params) ← lowerParams e.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner e.result
        interner := interner''
        requireScalarResultTypeId interner.types resultTid s!"entry '{raw e.name}' result"
        let (blocks, interner''') ←
          lowerBlock e.body params resultTid interner stateTable false
        interner := interner'''
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .entry (some (raw e.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks)
        callableId := callableId + 1
    | .view v =>
        let (interner', params) ← lowerParams v.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner v.result
        interner := interner''
        requireScalarResultTypeId interner.types resultTid s!"view '{raw v.name}' result"
        let (blocks, interner''') ←
          lowerBlock v.body params resultTid interner stateTable false
        interner := interner'''
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .view (some (raw v.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks)
        callableId := callableId + 1
    | .struct _ =>
        return ← failUnsupported "S1 normalizer does not support struct"
    | .enum _ =>
        return ← failUnsupported "S1 normalizer does not support enum"
    | .const _ =>
        return ← failUnsupported "S1 normalizer does not support const"
    | .event _ =>
        return ← failUnsupported "S1 normalizer does not support event"
    | .error _ =>
        return ← failUnsupported "S1 normalizer does not support error"
    | .fn _ =>
        return ← failUnsupported "S1 normalizer does not support fn"
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
    events := #[]
    errors := #[]
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
