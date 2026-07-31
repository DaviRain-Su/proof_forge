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
    * declarations: public primitive state/params/event/error fields
      (anonymous legal UInt widths {8,16,32,64,128,256}), init, entry, view
    * statements: bare-place assign to state, return (some/none); init may omit
      return (implicit return none); bare `assert` with a Bool condition
      (assert-else still fails closed); `if cond then B (else B)?` lowered to
      branch/jump blocks; `match scrut with` on a legal-UInt or Bool scrutinee
      with integer/Bool literal arms plus exactly one wildcard/bind catch-all
      lowered to switch/jump blocks (constructor patterns, string patterns,
      match expressions, and duplicate literals still fail closed; a
      catch-all-only match materializes to a plain jump)
    * expressions: bare place (param or state name), expected-type integer
      literals (legal UInt/Int widths, LE valueBytes of width/8), Bool literal,
      checked binary add/sub/mul/div/mod and bitwise and/or/xor on same-width
      legal UInt, shifts (lhs legal UInt, count UInt32), and the six same-width
      UInt/Int comparisons plus strict logical and/or producing Bool; integer
      width is supplied by the enclosing typed context (or by the lhs place
      for comparisons). Unary `-` on UInt desugars to `0 - x`; Int/Field
      `Op.Unary.neg` remains fail closed. call/schedule args and for endpoints
      stay UInt64 in this slice
    * types: named Struct/Enum (Pass0 contiguous prefix, source order) then
      anonymous legal UInt/Int widths + Unit (init result) + Bool; one TypeId
      per distinct anonymous shape, interned on first actual use after named
      registration. State/parameter positions are public legal-UInt only
      (named/aggregate state still fail closed); entry/view/fn results may be
      legal UInt/Int, Unit, or Bool. Constructor/field-place lowering deferred
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
    * Int/Field `Op.Unary.neg`, Int arithmetic/shift, private/commitment state,
      non-UInt64 call/schedule args and for endpoints, Array/Map/Option/Bytes
      aggregate *values* (named Struct/Enum *type registration* is in scope),
      constructor/field-place lowering, ContextRead/Commit, match expressions,
      mutable locals
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

/-- S1 type interning: named Struct/Enum (contiguous prefix, Pass0) then
    anonymous legal UInt/Int widths, Unit, Bool; first-seen. -/
structure TypeInternerV1 where
  types : Array TypeDeclV1

private def emptyInterner : TypeInternerV1 := ⟨#[]⟩

/-- SPEC §5 integer widths shared with Wire/TypeCheck. -/
private def legalIntegerWidthV1 (width : Nat) : Bool :=
  width == 8 || width == 16 || width == 32 || width == 64 ||
  width == 128 || width == 256

private abbrev WireStructFieldV1 := ProofForgeV2.Semantic.WireV1.StructFieldV1
private abbrev WireEnumVariantV1 := ProofForgeV2.Semantic.WireV1.EnumVariantV1

private def structFieldsEq (a b : Array WireStructFieldV1) : Bool :=
  a.size == b.size && Id.run do
    let mut i : Nat := 0
    for _ in a do
      match a[i]?, b[i]? with
      | some fa, some fb =>
          unless fa.name == fb.name && fa.typeId == fb.typeId do
            return false
      | _, _ => return false
      i := i + 1
    pure true

private def enumVariantsEq (a b : Array WireEnumVariantV1) : Bool :=
  a.size == b.size && Id.run do
    let mut i : Nat := 0
    for _ in a do
      match a[i]?, b[i]? with
      | some va, some vb =>
          unless va.name == vb.name && va.payloadTypes == vb.payloadTypes do
            return false
      | _, _ => return false
      i := i + 1
    pure true

private def shapeEq (a b : TypeShapeV1) : Bool :=
  match a, b with
  | .uint wa, .uint wb => wa == wb
  | .int wa, .int wb => wa == wb
  | .unit, .unit => true
  | .bool, .bool => true
  | .struct fa, .struct fb => structFieldsEq fa fb
  | .enum va, .enum vb => enumVariantsEq va vb
  | _, _ => false

private def findTypeId (interner : TypeInternerV1) (shape : TypeShapeV1) :
    Option TypeIdV1 := Id.run do
  let mut i : Nat := 0
  for d in interner.types do
    -- Anonymous interning only: named Struct/Enum are Pass0-owned and must not
    -- be re-discovered by shape (they are never name=none).
    if d.name.isNone && shapeEq d.shape shape then
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

/-- Lookup a Pass0-registered named Struct/Enum by exact raw name. -/
private def lookupNamedTypeId (interner : TypeInternerV1) (name : String) :
    Option TypeIdV1 := Id.run do
  let mut i : Nat := 0
  for d in interner.types do
    match d.name with
    | some n =>
        if n == name then
          return some (UInt32.ofNat i)
    | none => pure ()
    i := i + 1
  pure none

/-- Replace the shape of an already-allocated TypeDecl (Pass0 field fill). -/
private def setTypeShapeAt (interner : TypeInternerV1) (idx : Nat)
    (shape : TypeShapeV1) : TypeInternerV1 :=
  match interner.types[idx]? with
  | some decl =>
      { types := interner.types.set! idx { decl with shape := shape } }
  | none => interner

private def internSourceType (interner : TypeInternerV1) (ty : SrcType) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match ty with
  | .uint w =>
      if legalIntegerWidthV1 w.toNat then
        pure (internShape interner (.uint w))
      else
        failUnsupported s!"S1 normalizer supports only legal UInt widths, got UInt{w}"
  | .int w =>
      if legalIntegerWidthV1 w.toNat then
        pure (internShape interner (.int w))
      else
        failUnsupported s!"S1 normalizer supports only legal Int widths, got Int{w}"
  | .unit => pure (internShape interner .unit)
  | .bool => pure (internShape interner .bool)
  | .principal => failUnsupported "S1 normalizer does not support Principal"
  | .named n =>
      -- Named types are registered only in Pass0; body/declaration sites only
      -- look up. Never push a named TypeDecl here (would break named prefix).
      match lookupNamedTypeId interner (raw n) with
      | some tid => pure (interner, tid)
      | none =>
          failUnsupported s!"S1 named type '{raw n}' is not declared"
  | .array _ _ => failUnsupported "S1 normalizer does not support Array"
  | .map _ _ => failUnsupported "S1 normalizer does not support Map"
  | .option _ => failUnsupported "S1 normalizer does not support Option"
  | .bytes _ => failUnsupported "S1 normalizer does not support Bytes"
  | .field _ => failUnsupported "S1 normalizer does not support Field"

/-- Kind of source-order named declaration collected in Pass0. -/
private inductive NamedDeclKindV1 where
  | struct_ (fields : Array ProofForgeV2.Source.AstSupportV1.FieldDeclV1)
  | enum_ (variants : Array ProofForgeV2.Source.AstSupportV1.EnumVariantV1)

/-- Pass0: register every source-order `.struct`/`.enum` as a named TypeDecl
    occupying a contiguous prefix of `types`.

    Two phases:
      1. Allocate one named slot per declaration (placeholder empty shape) so
         later-declared names already have TypeIds for mutual field references.
      2. Fill fields/variants via `internSourceType` (named → lookup only;
         anonymous scalars push *after* the named prefix).

    Empty field/variant tables fail closed (Wire requires nonempty). Duplicate
    names fail closed (defense in depth; Loader already rejects them). -/
private def registerNamedTypesV1
    (items : Array ProofForgeV2.Source.AstProgramItemV1.ProgramItemV1)
    (interner : TypeInternerV1) :
    Except NormalizeErrorV1 TypeInternerV1 := do
  -- Collect (rawName, kind) in source order; reject empty / duplicate names.
  let mut collected : Array (String × NamedDeclKindV1) := #[]
  let mut seenNames : Array String := #[]
  for item in items do
    match item with
    | .struct s =>
        let name := raw s.name
        if seenNames.any (· == name) then
          return ← failUnsupported s!"S1 duplicate named type '{name}'"
        if s.fields.isEmpty then
          return ← failUnsupported
            s!"S1 struct '{name}' requires at least one field"
        seenNames := seenNames.push name
        collected := collected.push (name, .struct_ s.fields)
    | .enum e =>
        let name := raw e.name
        if seenNames.any (· == name) then
          return ← failUnsupported s!"S1 duplicate named type '{name}'"
        if e.variants.isEmpty then
          return ← failUnsupported
            s!"S1 enum '{name}' requires at least one variant"
        seenNames := seenNames.push name
        collected := collected.push (name, .enum_ e.variants)
    | _ => pure ()

  -- Phase 1: allocate named slots (placeholders; filled below).
  let mut interner := interner
  let mut slotIdxs : Array Nat := #[]
  for (name, kind) in collected do
    let tid := UInt32.ofNat interner.types.size
    let placeholder : TypeShapeV1 :=
      match kind with
      | .struct_ _ => .struct #[]
      | .enum_ _ => .enum #[]
    interner := {
      types := interner.types.push {
        id := tid
        name := some name
        shape := placeholder
      }
    }
    slotIdxs := slotIdxs.push tid.toNat

  -- Phase 2: fill fields/variants. Anonymous field types land after named
  -- prefix; named field types resolve via Pass0 slots (any order).
  let mut i : Nat := 0
  for (name, kind) in collected do
    let idx := slotIdxs[i]!
    match kind with
    | .struct_ fields => do
        let mut outFields : Array WireStructFieldV1 := #[]
        let mut fieldNames : Array String := #[]
        for f in fields do
          let fname := raw f.name
          if fieldNames.any (· == fname) then
            return ← failUnsupported
              s!"S1 struct '{name}' has duplicate field '{fname}'"
          fieldNames := fieldNames.push fname
          let (interner', tid) ← internSourceType interner f.type_
          interner := interner'
          outFields := outFields.push { name := fname, typeId := tid }
        interner := setTypeShapeAt interner idx (.struct outFields)
    | .enum_ variants => do
        let mut outVars : Array WireEnumVariantV1 := #[]
        let mut varNames : Array String := #[]
        for v in variants do
          let vname := raw v.name
          if varNames.any (· == vname) then
            return ← failUnsupported
              s!"S1 enum '{name}' has duplicate variant '{vname}'"
          varNames := varNames.push vname
          let mut payloads : Array TypeIdV1 := #[]
          for pty in v.payloadTypes do
            let (interner', tid) ← internSourceType interner pty
            interner := interner'
            payloads := payloads.push tid
          outVars := outVars.push { name := vname, payloadTypes := payloads }
        interner := setTypeShapeAt interner idx (.enum outVars)
    i := i + 1
  pure interner

/-- Little-endian fixed-width encoding of a natural (private; no Reference import).
    Matches Wire `encodeU64le`/`encodeU32le` for lengths 8 and 4. -/
private def encodeNatLeBytes (n : Nat) (byteLen : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity byteLen
  let mut v := n
  for _ in [:byteLen] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

/-- Look up an anonymous type shape by TypeId. -/
private def anonShapeOf? (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    Option TypeShapeV1 :=
  match types[typeId.toNat]? with
  | some decl => if decl.name.isNone then some decl.shape else none
  | none => none

/-- Require anonymous legal UInt width (state/param/event/error/fn params). -/
private def requireAnonymousUIntTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt width, got UInt{w}"
  | some _ =>
      failUnsupported s!"S1 {context} requires anonymous UInt type"
  | none =>
      failUnsupported s!"S1 {context} references missing or named TypeId {typeId}"

/-- Backward-compatible UInt64-only pin used by call/schedule/for endpoints. -/
private def requireUInt64TypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint 64) => pure ()
  | some _ => failUnsupported s!"S1 {context} requires UInt64 type"
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"

/-- Require anonymous scalar at entry/view/fn results: legal UInt/Int, Unit, Bool. -/
private def requireScalarResultTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt/Int/Unit/Bool type"
  | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt/Int/Unit/Bool type"
  | some .unit | some .bool => pure ()
  | some _ =>
      failUnsupported s!"S1 {context} requires UInt/Int/Unit/Bool type"
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"

/-- Require anonymous legal UInt expected type (arith/bitwise/shift lhs). -/
private def requireExpectedUIntWidth
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires expected legal UInt type"
  | some _ =>
      failUnsupported s!"S1 {context} requires expected legal UInt type"
  | none =>
      failUnsupported s!"S1 {context} references missing expected TypeId {typeId}"

/-- Require anonymous legal UInt or Int expected type (comparisons, bitNot). -/
private def requireExpectedIntegerWidth
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires expected legal UInt/Int type"
  | some _ =>
      failUnsupported s!"S1 {context} requires expected legal UInt/Int type"
  | none =>
      failUnsupported s!"S1 {context} references missing expected TypeId {typeId}"

/-- UInt64-only expected pin retained for call sites that must stay UInt64. -/
private def requireExpectedUInt64
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint 64) => pure ()
  | some _ => failUnsupported s!"S1 {context} requires expected UInt64 type"
  | none =>
      failUnsupported s!"S1 {context} references missing expected TypeId {typeId}"

/-- Unsigned max exclusive bound `2^width` for range checks. -/
private def uintExclusiveLimit (width : Nat) : Nat := Nat.pow 2 width

/-- Signed positive magnitude max inclusive `2^(width-1) - 1` (TypeCheck align). -/
private def intPositiveInclusiveMax (width : Nat) : Nat :=
  Nat.pow 2 (width - 1) - 1

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

/-- Require an already-interned TypeId to resolve to anonymous legal UInt/Int or
    Bool: the only types an immutable `let` binding can carry in this envelope. -/
private def requireLetTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt/Int/Bool type"
  | some .bool => pure ()
  | some _ =>
      failUnsupported s!"S1 {context} requires UInt/Int/Bool type"
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"

/-- Derive the expected TypeId for an unannotated `let` RHS from its head
shape. CheckV1 has already rejected integer literals without an expected
type, so every remaining pilot shape carries an intrinsic result type.

Unannotated arithmetic/bitwise/unary still default to UInt64 for backward
compatibility with existing tests that omit a type annotation on such lets.
Multi-width arithmetic must use an explicit annotation (or flow through a
typed place/callable result) so width is never silently mis-defaulted. -/
private partial def synthLetExpectedV1
    (value : SrcExpr) (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match value with
  | .literal (.integer _) =>
      failUnsupported "S1 let integer literal requires a type annotation"
  | .literal (.bool _) => pure (internShape st.interner .bool)
  | .literal (.string _) =>
      failUnsupported "S1 normalizer supports only UInt/Int/Bool literals"
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
  | .binary op lhs _ =>
      let srcOp := op
      if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.add ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.sub ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mul ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.div ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mod ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitAnd ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitOr ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitXor ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shl ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shr then
        -- Prefer the lhs place width when available; else keep UInt64 default.
        match lhs with
        | .place (.name n) =>
            let key := raw n
            match envLookup st.env key with
            | some (_, tid) => pure (st.interner, tid)
            | none =>
                match stateLookup states key with
                | some (_, tid) => pure (st.interner, tid)
                | none => pure (internShape st.interner (.uint 64))
        | _ => pure (internShape st.interner (.uint 64))
      else if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.eq ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ne ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.lt ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.le ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.gt ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ge ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalAnd ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalOr then
        pure (internShape st.interner .bool)
      else
        failUnsupported "S1 normalizer supports only binary arithmetic, bitwise, shift, comparison, and logical operators"
  | .unary .not _ => pure (internShape st.interner .bool)
  | .unary _ operand =>
      match operand with
      | .place (.name n) =>
          let key := raw n
          match envLookup st.env key with
          | some (_, tid) => pure (st.interner, tid)
          | none =>
              match stateLookup states key with
              | some (_, tid) => pure (st.interner, tid)
              | none => pure (internShape st.interner (.uint 64))
      | _ => pure (internShape st.interner (.uint 64))
  | .constructor _ _ =>
      failUnsupported "S1 normalizer does not support constructors"
  | .localCall callee _ =>
      let key := raw callee
      match fnLookup fns key with
      | none => failUnsupported s!"S1 localCall '{key}' is not a declared fn"
      | some (_, _, fnResultTid) => pure (st.interner, fnResultTid)
  | .match_ _ _ =>
      failUnsupported "S1 normalizer does not support match expressions"

/-- Infer comparison operand TypeId from the lhs place (TypeCheck order: lhs
    first, then rhs under that type). Non-place lhs heads fall back to UInt64
    so existing UInt64 comparison programs keep lowering. -/
private def synthComparisonOperandTypeV1
    (lhs : SrcExpr) (st : BodyStateV1) (states : StateTableV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match lhs with
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
  | .unary _ operand =>
      match operand with
      | .place (.name n) =>
          let key := raw n
          match envLookup st.env key with
          | some (_, tid) => pure (st.interner, tid)
          | none =>
              match stateLookup states key with
              | some (_, tid) => pure (st.interner, tid)
              | none => pure (internShape st.interner (.uint 64))
      | _ => pure (internShape st.interner (.uint 64))
  | .binary op l _ =>
      let srcOp := op
      if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.add ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.sub ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mul ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.div ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.mod ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitAnd ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitOr ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.bitXor ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shl ||
          srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.shr then
        synthComparisonOperandTypeV1 l st states
      else
        pure (internShape st.interner (.uint 64))
  | .localCall callee _ =>
      failUnsupported
        s!"S1 comparison operand localCall '{raw callee}' needs an explicit integer place"
  | _ => pure (internShape st.interner (.uint 64))

/-- Emit a value-producing instruction: allocate the next ValueId, bind it as
    the instruction result at `typeId`, and advance `nextValueId`. -/
private def emitValue (st : BodyStateV1) (typeId : TypeIdV1) (op : SemanticOpV1) :
    BodyStateV1 × ValueIdV1 :=
  let vid := st.nextValueId
  let instr : InstructionV1 := {
    result := some { valueId := vid, typeId := typeId }
    op := op
  }
  ({ st with
    instructions := st.instructions.push instr
    nextValueId := vid + 1
  }, vid)

/-- Emit a void instruction (`result = none`); does not touch ValueId/EffectId. -/
private def emitVoid (st : BodyStateV1) (op : SemanticOpV1) : BodyStateV1 :=
  { st with
    instructions := st.instructions.push { result := none, op := op }
  }

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
              let (st1, vid) := emitValue st tid (.stateLoad sid)
              pure (vid, tid, st1)
  | .field _ _ => failUnsupported "S1 normalizer does not support field places"
  | .index _ _ => failUnsupported "S1 normalizer does not support index places"

mutual
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
        -- Same-width legal UInt only in this slice (Int arith deferred).
        requireExpectedUIntWidth st.interner.types expectedTid "binary arithmetic/bitwise"
        -- Preserve source evaluation / ValueId order: lhs, then rhs, then op.
        let (lVid, lTid, st1) ← lowerExpr lhs expectedTid st states fns
        let (rVid, rTid, st2) ← lowerExpr rhs expectedTid st1 states fns
        unless lTid == expectedTid && rTid == expectedTid do
          return ← failUnsupported
            "S1 binary arithmetic/bitwise requires same-width expected operands"
        let (st3, vid) := emitValue st2 expectedTid (.binary semanticOp lVid rVid)
        pure (vid, expectedTid, st3)
      | none =>
        match shiftOp? with
        | some semanticOp => do
          -- Shift lhs: legal UInt width; count remains sole UInt32 context.
          requireExpectedUIntWidth st.interner.types expectedTid "shift"
          let (iU32, u32Tid) := internShape st.interner (.uint 32)
          let st0 := { st with interner := iU32 }
          let (lVid, lTid, st1) ← lowerExpr lhs expectedTid st0 states fns
          unless lTid == expectedTid do
            return ← failUnsupported "S1 shift requires a legal UInt operand"
          let (rVid, rTid, st2) ← lowerExpr rhs u32Tid st1 states fns
          unless rTid == u32Tid do
            return ← failUnsupported "S1 shift count must be UInt32"
          let (st3, vid) := emitValue st2 expectedTid (.binary semanticOp lVid rVid)
          pure (vid, expectedTid, st3)
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
            let (st3, vid) := emitValue st2 boolTid (.binary semanticOp lVid rVid)
            pure (vid, boolTid, st3)
        | none =>
        match cmpOp? with
        | some semanticOp => do
            -- Comparison operands are same-width legal UInt/Int; result is Bool.
            -- Operand width is inferred from the lhs place (TypeCheck order).
            let (iBool, boolTid) := internShape st.interner .bool
            unless boolTid == expectedTid do
              return ← failUnsupported
                "S1 comparison requires an enclosing Bool expected type"
            let stB := { st with interner := iBool }
            let (iOp, opTid) ← synthComparisonOperandTypeV1 lhs stB states
            requireExpectedIntegerWidth iOp.types opTid "comparison"
            let st0 := { stB with interner := iOp }
            let (lVid, lTid, st1) ← lowerExpr lhs opTid st0 states fns
            unless lTid == opTid do
              return ← failUnsupported
                "S1 comparison requires same-width integer operands"
            let (rVid, rTid, st2) ← lowerExpr rhs opTid st1 states fns
            unless rTid == opTid do
              return ← failUnsupported
                "S1 comparison requires same-width integer operands"
            let (st3, vid) := emitValue st2 boolTid (.binary semanticOp lVid rVid)
            pure (vid, boolTid, st3)
        | none =>
            failUnsupported "S1 normalizer supports only binary arithmetic, bitwise, shift, comparison, and logical operators"
  | .literal literal =>
      match literal with
      | .integer magnitude => do
          -- Expected type supplies the width (UInt or positive Int). CheckV1
          -- owns user-facing diagnostics; this seam still rejects truncation.
          let shape? := anonShapeOf? st.interner.types expectedTid
          match shape? with
          | some (.uint w) => do
              let width := w.toNat
              unless legalIntegerWidthV1 width do
                return ← failUnsupported
                  s!"S1 integer literal requires legal UInt width, got UInt{width}"
              unless magnitude < uintExclusiveLimit width do
                return ← failUnsupported
                  s!"S1 UInt{width} integer literal is out of range"
              let bytes := encodeNatLeBytes magnitude (width / 8)
              let (st1, vid) := emitValue st expectedTid (.literal expectedTid bytes)
              pure (vid, expectedTid, st1)
          | some (.int w) => do
              let width := w.toNat
              unless legalIntegerWidthV1 width do
                return ← failUnsupported
                  s!"S1 integer literal requires legal Int width, got Int{width}"
              -- Align with TypeCheckV1: non-negated magnitude ≤ 2^(w-1)-1.
              unless magnitude ≤ intPositiveInclusiveMax width do
                return ← failUnsupported
                  s!"S1 Int{width} integer literal is out of range"
              let bytes := encodeNatLeBytes magnitude (width / 8)
              let (st1, vid) := emitValue st expectedTid (.literal expectedTid bytes)
              pure (vid, expectedTid, st1)
          | _ =>
              failUnsupported
                "S1 integer literal requires expected legal UInt/Int type"
      | .bool value => do
          let (i1, boolTid) := internShape st.interner .bool
          unless boolTid == expectedTid do
            return ← failUnsupported
              "S1 Bool literal requires an enclosing Bool expected type"
          let st0 := { st with interner := i1 }
          let (st1, vid) := emitValue st0 boolTid (.literal boolTid (encodeBool value))
          pure (vid, boolTid, st1)
      | .string _ =>
          failUnsupported "S1 normalizer supports only UInt/Int/Bool literals"
  | .constructor _ _ => failUnsupported "S1 normalizer does not support constructors"
  | .unary op operand => do
      match op with
      | .neg => do
          -- UInt: desugar to `0 - x` with a zero constant of the same width.
          -- Int/Field: Op.Unary.neg is deferred — fail closed rather than
          -- incorrectly reusing the unsigned desugar.
          match anonShapeOf? st.interner.types expectedTid with
          | some (.uint w) => do
              unless legalIntegerWidthV1 w.toNat do
                return ← failUnsupported
                  "S1 unary checked negation requires expected legal UInt type"
              let (oVid, oTid, st1) ← lowerExpr operand expectedTid st states fns
              unless oTid == expectedTid do
                return ← failUnsupported
                  "S1 unary checked negation requires a legal UInt operand"
              let zeroBytes := encodeNatLeBytes 0 (w.toNat / 8)
              let (st2, zeroVid) :=
                emitValue st1 expectedTid (.literal expectedTid zeroBytes)
              let (st3, vid) := emitValue st2 expectedTid (.binary .sub zeroVid oVid)
              pure (vid, expectedTid, st3)
          | some (.int _) =>
              failUnsupported
                "S1 unary Int negation (Op.Unary.neg) is not yet supported"
          | _ =>
              failUnsupported
                "S1 unary checked negation requires expected legal UInt type"
      | .bitNot => do
          requireExpectedIntegerWidth st.interner.types expectedTid "unary bit-not"
          let (oVid, oTid, st1) ← lowerExpr operand expectedTid st states fns
          unless oTid == expectedTid do
            return ← failUnsupported
              "S1 unary bit-not requires a legal UInt/Int operand"
          let (st2, vid) := emitValue st1 expectedTid (.unary .bitNot oVid)
          pure (vid, expectedTid, st2)
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
          let (st2, vid) := emitValue st1 boolTid (.unary .not oVid)
          pure (vid, boolTid, st2)
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
          let (argIds, st') ← lowerArgs args paramTids st states fns
            s!"S1 localCall '{key}' argument type mismatch"
          let (st2, vid) := emitValue st' fnResultTid (.pureCall callableId argIds)
          pure (vid, fnResultTid, st2)
  | .match_ _ _ => failUnsupported "S1 normalizer does not support match expressions"

/-- Lower a positional argument list under expected TypeIds (arity already
    checked by the caller). Evaluation order is source order; each argument's
    produced type must equal its expected TypeId. -/
private partial def lowerArgs
    (args : Array SrcExpr) (expectedTids : Array TypeIdV1)
    (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1)
    (typeMismatch : String) :
    Except NormalizeErrorV1 (Array ValueIdV1 × BodyStateV1) := do
  let mut st' := st
  let mut argIds : Array ValueIdV1 := #[]
  for (arg, expectedTid) in args.zip expectedTids do
    let (vid, argTid, st1) ← lowerExpr arg expectedTid st' states fns
    unless argTid == expectedTid do
      return ← failUnsupported typeMismatch
    argIds := argIds.push vid
    st' := st1
  pure (argIds, st')
end

/-- Lower a statement-level external effect (`call` / `schedule`): qualified
    callee (≥2 components), UInt64 args, void op with the shared EffectId
    sequence. The only difference between the two is the op constructor. -/
private partial def lowerExternalEffect
    (label : String)
    (mkOp : EffectIdV1 → QualifiedName → Array ValueIdV1 → SemanticOpV1)
    (externalCall : ProofForgeV2.Source.AstSpineV1.ExternalCallExprV1)
    (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (BodyStateV1 × PathStatusV1) := do
  let callee := externalCall.callee
  let calleeComponents := (NonEmptyArray.toArray callee.components).map (·.raw)
  unless calleeComponents.size ≥ 2 do
    return ← failUnsupported
      s!"S1 {label} callee must have at least two components"
  let qn ← match parseQualifiedName calleeComponents with
    | .ok qn => pure qn
    | .error e => failUnsupported s!"S1 {label} callee: {e}"
  let (iU, u64Tid) := internShape st.interner (.uint 64)
  let st0 := { st with interner := iU }
  let expectedTids := externalCall.args.map (fun _ => u64Tid)
  let (argIds, st') ← lowerArgs externalCall.args expectedTids st0 states fns
    s!"S1 {label} argument must be UInt64"
  let st1 := emitVoid st' (mkOp st'.nextEffectId qn argIds)
  pure ({ st1 with nextEffectId := st1.nextEffectId + 1 }, .open_)

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
                  pure (emitVoid st1 (.stateStore sid vid), .open_)
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
          pure (emitVoid st1 (.assert_ condVid none #[]), .open_)
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
      let (iB, boolTid) := internShape st.interner .bool
      let st0 := { st with interner := iB }
      -- Scrutinee: Bool literal, bare place (legal UInt or Bool), or UInt64
      -- fallback for non-place heads (preserves prior UInt64 match programs).
      let (scrutVid, scrutTid, st1) ←
        match scrutinee with
        | .literal (.bool _) =>
            lowerExpr scrutinee boolTid st0 states fns
        | .place p => do
            let (vid, tid, stP) ← lowerPlace p st0 states
            pure (vid, tid, stP)
        | _ => do
            let (iU, u64Tid) := internShape st0.interner (.uint 64)
            let stU := { st0 with interner := iU }
            lowerExpr scrutinee u64Tid stU states fns
      let scrutIsBool :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some .bool => true
        | _ => false
      let scrutUintWidth? : Option Nat :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some (.uint w) =>
            if legalIntegerWidthV1 w.toNat then some w.toNat else none
        | _ => none
      unless scrutIsBool || scrutUintWidth?.isSome do
        return ← failUnsupported
          "S1 match scrutinee must be legal UInt or Bool"
      -- Split arms into literal cases and exactly-one catch-all (wildcard or
      -- bind); CheckV1 already requires a catch-all for UInt/Bool scrutinee.
      -- Case magnitudes are Nat (UInt256 range).
      let mut caseArms : Array (Nat × Bool × SrcBlock) := #[]
      let mut defaultArm? : Option (Option SourceNameComponentV1 × SrcBlock) := none
      for arm in arms do
        match arm.pattern with
        | .literal lit =>
            match lit with
            | .integer magnitude =>
                let some width := scrutUintWidth? |
                  return ← failUnsupported
                    "S1 match integer literal requires a legal UInt scrutinee"
                unless magnitude < uintExclusiveLimit width do
                  return ← failUnsupported
                    s!"S1 match UInt{width} integer literal is out of range"
                if caseArms.any (fun (v, isBool, _) => !isBool && v == magnitude) then
                  return ← failUnsupported "S1 match has duplicate literal cases"
                caseArms := caseArms.push (magnitude, false, arm.body)
            | .bool value =>
                unless scrutIsBool do
                  return ← failUnsupported
                    "S1 match Bool literal requires a Bool scrutinee"
                if caseArms.any (fun (v, isBool, _) =>
                    isBool && v == (if value then 1 else 0)) then
                  return ← failUnsupported "S1 match has duplicate literal cases"
                caseArms := caseArms.push (if value then 1 else 0, true, arm.body)
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
              "S1 match on UInt/Bool requires a catch-all arm"
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
            typeId := scrutTid
            valueBytes :=
              if isBool then encodeBool (value == 1)
              else
                let width := scrutUintWidth?.getD 64
                encodeNatLeBytes value (width / 8)
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
      let (st5b, condVid) :=
        emitValue st5 boolTid (.binary BinaryOpV1.lt iVid eVid)
      let bodyId := UInt32.ofNat (st5b.blocks.size + 1)
      let st6 := sealCurrentBlock st5b (.branch condVid
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
            let (stB1, oneVid) :=
              emitValue stB u64Tid (.literal u64Tid (encodeU64le 1))
            let (stB2, incVid) :=
              emitValue stB1 u64Tid (.binary BinaryOpV1.add iVid oneVid)
            let stSealed := sealCurrentBlock stB2
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
          let (argIds, st') ← lowerArgs args fieldTids st states fns
            s!"S1 revert '{key}' argument type mismatch"
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
          let (argIds, st') ← lowerArgs args fieldTids st states fns
            s!"S1 emit '{key}' argument type mismatch"
          let st1 := emitVoid st' (.emit st'.nextEffectId eventId argIds)
          pure ({ st1 with nextEffectId := st1.nextEffectId + 1 }, .open_)
  | .call externalCall =>
      -- Sync external call: a statement effect with no result value (v1).
      -- The callee is an opaque qualified name (at least two components per
      -- the wire shape gate), resolved at deployment, never by the compiler.
      lowerExternalEffect "call"
        (fun effectId qn argIds => .externalCall effectId qn argIds)
        externalCall st states fns
  | .schedule externalCall =>
      -- Async workflow schedule: same statement-effect shape as call.
      lowerExternalEffect "schedule"
        (fun effectId qn argIds => .schedule effectId qn argIds)
        externalCall st states fns

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
    requireAnonymousUIntTypeId interner.types tid s!"parameter '{raw p.name}'"
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

  Passes over ProgramV1 items (not NameResolution tables):
  0. Register source-order named Struct/Enum TypeDecls (contiguous prefix).
  1. Collect/validate all public legal-UInt states into a complete logicalState
     table (IDs are source-order among state decls, independent of callable
     position).
  2. Lower init/entry/view bodies against that complete table.
-/
def lowerProgramDataV1 (source : ValidatedSourceV1) :
    Except NormalizeErrorV1 SemanticProgramDataV1 := do
  let qn ← programIdentityToQualifiedNameV1 source.programIdentity
  let program := source.program
  -- Pass 0: named Struct/Enum occupy types[0..namedCount) before any anonymous.
  let mut interner ← registerNamedTypesV1 program.items emptyInterner
  let mut stateRows : Array StateDeclV1 := #[]
  let mut stateTable : StateTableV1 := ⟨#[]⟩
  let mut eventRows : Array EventDeclV1 := #[]
  let mut eventTable : EventTableV1 := ⟨#[]⟩
  let mut errorRows : Array ErrorDeclV1 := #[]
  let mut errorTable : ErrorTableV1 := ⟨#[]⟩

  -- Pass 1: complete state/event/error tables (source order among those
  -- items only). Event/error fields stay public legal-UInt in this envelope.
  for item in program.items do
    match item with
    | .state s =>
        unless s.visibility == ProofForgeV2.Source.AstV1.VisibilityV1.public_ do
          return ← failUnsupported
            s!"S1 normalizer supports only public state, got non-public '{raw s.name}'"
        let (interner', tid) ← internSourceType interner s.type_
        interner := interner'
        requireAnonymousUIntTypeId interner.types tid s!"state '{raw s.name}'"
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
          requireAnonymousUIntTypeId interner.types tid
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
          requireAnonymousUIntTypeId interner.types tid
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
  -- pass 2 lowers them). Fn params stay public legal-UInt; results are
  -- public legal UInt/Int/Unit/Bool.
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
          requireAnonymousUIntTypeId interner.types tid
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
    | .struct _ => pure ()  -- registered in Pass0; no callable body
    | .enum _ => pure ()    -- registered in Pass0; no callable body
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
