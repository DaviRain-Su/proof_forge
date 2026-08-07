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
      (state/params admit anonymous legal UInt/Int widths {8,16,32,64,128,256},
      sole catalog Field, Principal, String, and the documented aggregates;
      event/error fields admit public anonymous legal UInt/Int or String),
      init, entry, view
    * statements: bare-place assign to state, return (some/none); init may omit
      return (implicit return none); bare `assert` with a Bool condition, and
      `assert cond else Err` referencing a declared zero-argument error (lowered
      to `Op.Assert cond (some eid) #[]`); referencing a parameterized error
      fails closed because the source `assert Expr else Ident` carries no args;
      `if cond then B (else B)?` lowered to
      branch/jump blocks; `match scrut with` on a legal-UInt/Bool scrutinee
      (integer/Bool literal arms) or Enum/Option scrutinee (constructor arms
      via `Op.VariantTag` → switch on UInt32 tag + arm-local
      `Op.VariantPayload` binds); exactly one wildcard/bind catch-all when
      required by TypeCheck; string literal patterns on String scrutinee
      (N4; exact valueBytes identity); nested constructor/literal
      sub-patterns open (recursive bind/wildcard/constructor/literal);
      multi-arm same outer constructor is allowed when sub-patterns are
      structurally distinguishable (first-match sequential nested guards:
      VariantTag eq for nested ctors, value eq for nested literals;
      fallthrough to outer catch-all or trap.unreachable); identical
      structural pattern keys (bind≡wildcard, ctor by variant index,
      literal by valueBytes) still fail closed as duplicates; a
      catch-all-only match materializes inline; expression-level match
      shares the same pattern set (see expressions)
    * expressions: bare place (param, state, or **const** name — N-CONST-REF:
      env → state → const; each const read emits independent value-producing
      `Op.Constant` with `result.typeId == ConstantV1.typeId`; constants table
      complete before any body so forward refs resolve; dense source-order
      ConstantIds; valueBytes sole via `evalConstDeclValueV1`), expected-type
      integer literals (legal UInt/Int widths, LE valueBytes of width/8; Int
      negatives enter as `unary neg (integer literal)` folded to two's-complement LE
      including intMin; **no Field or Principal source literal** — Field and
      Principal values enter via params/state), Bool literal, checked binary
      add/sub/mul/div/mod and bitwise and/or/xor on same-width legal UInt/Int,
      Field add/sub/mul/div (exact mod-p; `mod` on Field fails closed matching
      Reference `.invalidCore`), shifts (lhs legal UInt/Int, count UInt32;
      Int `>>` is arithmetic), six same-width UInt/Int comparisons plus Field
      and Principal `==`/`!=` (ordering on Field/Principal fails closed), and
      strict logical and/or producing Bool. Unary `-` on UInt desugars to
      `0 - x`; on Int/Field emits `Op.Unary.neg` (intMin overflow is a runtime
      revert; Field neg = `(p - v) % p`; Principal has no unary). call/schedule
      args and for endpoints admit legal UInt/Int widths (N-8/N-FOR-INT)
    * types: named Struct/Enum (Pass0 contiguous prefix, source order) then
      anonymous legal UInt/Int, Unit, Bool, Principal, String, Bytes, Array,
      Map, Option, Field(bn254-fr); one TypeId per distinct anonymous shape,
      interned on first actual use after named registration. State/parameter
      positions admit public legal-UInt/Int/Field/Principal/String **or named
      Struct/Enum** (N3/N4) **or anonymous Array/Map/Bytes/Option** (N3 ArrayState +
      N-A4 Option; default valueBytes = Option-none `0x00`). Unit/Bool state still
      fail closed). Entry/view/fn results admit legal
      UInt/Int/Unit/Bool/Field/Principal/String, named Struct/Enum (N-4), and
      anonymous Array/Map/Bytes/Option (N-ANON-RESULT). Local `let` may hold
      named/aggregate values (including Principal/String)
    * expressions (aggregate values): `StructName.new` / `Enum.Variant` /
      `Option.some` / `Option.none` constructors → `Op.Construct`; field places
      → `Op.FieldGet`; index places → `Op.IndexGet` (Array/Bytes/Map); field
      and index assign on place chains → `Op.FieldSet`/`Op.IndexSet` with
      outward rebind (N3 nested `x.f`, `x[i]`, `x.f[0].g = v`, including
      state roots: load → chain → write → store). **MapBytesAssign (N-A3)**:
      single-step `map[k] = v` → `Op.IndexSet` (key exact, value = map value);
      single-step `bytes[i] = b` → `Op.IndexSet` (UInt32 index, UInt8 value);
      Map/Bytes **state** already admitted (ArrayState); empty Map default +
      IndexSet upsert; **N-1** product nonempty Map = empty default or
      `Map.empty()` Construct + successive IndexSet (Wire Construct stays
      empty-only); fixed Bytes default zeros + IndexSet. Nested assign
      *through* a Map element (`m[k].x = v`) or Bytes element still fail
      closed (Option intermediate / UInt8 scalar). Bare-local field/index
      assign rebinds the local; param roots still fail closed
    * callables: multi-block CFG (entryBlock=0, dense block ids).
      init/entry/view/pureFn carry `invariantSteps=none` unless a pureFn is
      in an invariant PureCall closure (then sole Wire exact steps).
      `invariant name : BoolExpr` lowers to a zero-arg `.invariant` callable
      (public Bool result, empty loopBounds, return of the lowered predicate on
      the final open block — may be multi-block when the predicate is e.g.
      expression `match`) plus a dense source-order `InvariantDecl` row;
      ContextRead/Commit/effect ops stay fail closed on invariant roots.
      Exact `invariantSteps` (including pureFn closure metadata) are produced
      by sole `computeInvariantStepsExactWithMembersV1` before encode.
      `.proof` stays certification-only and never enters business IR.
      Bounded `for i in s .. e bounded N do` loops
      lower to a single-param header block (the induction variable), a
      branch, and a latch with the only back edge; `loopBounds` records
      exactly that (header, latch, N) edge in ascending order. Non-loop
      edges still point forward; block params appear on loop headers and on
      expression-match join blocks (arm value → join via jump args)
      * expression-level `match Expr with | Pattern => Expr` (T4/T5): same
      literal (UInt/Bool/String) + Enum/Option constructor + catch-all pattern
      set as statement match; each arm value lowers in its own block and jumps
      to a join block carrying the result as a single block param;
      catch-all-only matches inline without a switch
      * statements: `let` bindings lower to environment entries (RHS evaluates
      once); **N-6** bare `x := e` on a let-local rebinds the name (SSA fresh
      ValueId, same TypeId); parameters remain immutable; field/index update
      of a local still rebinds via FieldSet/IndexSet
    * N5/N-2 ContextRead/Commit (init/entry/view only; pureFn fail closed):
      place `context.unixTimeSeconds` → `Op.ContextRead`
      `proof-forge.context.unix-time-seconds.v1` (UInt64);
      place `context.caller` → `Op.ContextRead` `proof-forge.context.caller.v1`
      (Principal); bare local-call `commit(x)` (no user `fn commit`) →
      `Op.Commit` label-only identity. Wire-owned requirement rows merged
      after S2 freeze (UTF-8 id order).
    * S2 exact ProgramRequirementsV1 freeze (Counter catalog, SPEC wire order)
      before encode/hash; non-product companion provenance uses
      `normalizeProgramWithProvenanceV1` (source+path+spans), while product
      proof joining uses `buildSemanticProvenanceFromOriginInventoryV1` with
      Source's opaque inventory and located normalization. Neither authority
      accepts a caller-built `SourceNodeInventoryV1`.

  Product ownership (S3 + B8b):
    * Product path: `normalizeProgramLocatedV1` consumes
      `(ValidatedSourceV1 × OriginInventoryV1)` from the sole product Loader,
      calls `checkProgramTypedLocatedResultV1` exactly once, materializes the
      full located diagnostic array all-or-nothing, and returns
      `DiagnosticResultV1 SemanticProgramV1` via `mkFailureBundleV1` (sole
      sort/dedupe/cap). Does **not** re-run unlocated CheckV1.
    * Non-product library: `normalizeProgramV1` remains for hand-built fixtures
      and provenance helpers; product Compiler/CLI must not call it.
    * Proof-bearing product calls may re-run `normalizeProgramLocatedV1` with
      the same opaque inventory to close the retained semantic/provenance join.
    * This module owns the target-neutral structure gate only; it does not own
      residual alpha `Semantic.Program`, Registry, or target Plan/IR.

  Out of scope for this module:
    * Field/Principal source literals, Field/Principal/String ordering
      comparisons, Field `mod`, Principal/String arithmetic/bitwise/unary,
      anonymous Unit/Bool as state or param types (Array/Map/Bytes/Option
      state admitted; Option default is none-tag `0x00` via InvariantFoundation),
      cumulative whole-step work accounting across multi-arg Map *Construct*
      (product `Map.of` is lowered and Reference evaluates sequential upserts;
      each Wire helper keeps its own shared-cap budget, not one step receipt),
      nested assign through Bytes elements (fail closed — Bytes elements are
      UInt8 leaves with no deeper structure); nested assign through **Map**
      elements is open (N-NEST-IDX: `IndexGet` → `VariantPayload` some-unwrap
      (absent key traps `invalidCore`) → payload update → `IndexSet`),
      identical multi-arm same-outer patterns (structural duplicate keys),
      param-root bare/field/index assign (params immutable; lets mutable N-6),
      target-specific String event/error ABI materialization (shared Semantic and
      Reference accept canonical String payloads; every target remains fail closed),
      ContextRead keys other than `context.unixTimeSeconds` / `context.caller`,
      Commit/ContextRead inside pureFn (fail closed; init/entry/view only)
    * registry / resolver / materializer / OutputSetV1
    * interpreter / target Plan changes
    * formal TASK-D2-05 / TASK-D2-06 / TST-SEM-001 completion
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Semantic.ProvenanceV1
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ContextCommitSurfaceV1
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
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.ContextCommitSurfaceV1
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
private abbrev SrcPattern := ProofForgeV2.Source.AstPatternV1.PatternV1
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

private def sourceQualifiedNameStringV1 (name : SourceQualifiedNameV1) : String :=
  String.intercalate "."
    ((NonEmptyArray.toArray name.components).map (·.raw) |>.toList)

/-- Exact target-neutral engineering extension declaration (closed Core table).
    Recognition here mints only a wire-owned requirement row; target/profile
    admission is owned by RequirementResolverV1. -/
private def isExactEngineeringExtensionV1
    (declaration : ProofForgeV2.Source.AstDeclV1.ExtensionReqV1) : Bool :=
  isExactEngineeringExtensionTripleV1
    (sourceQualifiedNameStringV1 declaration.id)
    declaration.version
    declaration.digest

/-- Wire requirement id for an exact closed engineering extension, if any. -/
private def wireIdOfExactEngineeringExtensionV1
    (declaration : ProofForgeV2.Source.AstDeclV1.ExtensionReqV1) : Option String :=
  wireRequirementIdOfExactExtensionTripleV1
    (sourceQualifiedNameStringV1 declaration.id)
    declaration.version
    declaration.digest

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
    anonymous legal scalars/aggregates; first-seen. -/
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

private def fieldSpecEq (a b : FieldSpecV1) : Bool :=
  a.id.value == b.id.value && a.modulusBE == b.modulusBE

/-- T14 catalog v2: is this FieldSpec one of the three closed catalog entries?
    Wire structure validation (`validateFieldSpecCatalogV1`) is the sole
    authority; Normalize mirrors the exact membership here so a FieldSpec that
    passes the catalog gate is admitted by every Normalize field gate, and any
    non-catalog spec fails closed. -/
private def isCatalogFieldSpec (spec : FieldSpecV1) : Bool :=
  fieldSpecCatalogV1.any (fun entry => fieldSpecEq spec entry)

/-- T14 catalog v2: map a source Field type identifier token to its closed
    catalog FieldSpec. `bn254_fr` → bn254 Fr, `bls12_377_fr` → BLS12-377 Fr,
    `goldilocks` → Goldilocks. Any other token fails closed (the parser already
    rejects unknown tokens; this is defense in depth). -/
private def fieldSpecOfToken? (raw : String) : Option FieldSpecV1 :=
  match raw with
  | "bn254_fr" => some bn254FrFieldSpecV1
  | "bls12_377_fr" => some bls12377FrFieldSpecV1
  | "goldilocks" => some goldilocksFieldSpecV1
  | _ => none

private def shapeEq (a b : TypeShapeV1) : Bool :=
  match a, b with
  | .uint wa, .uint wb => wa == wb
  | .int wa, .int wb => wa == wb
  | .unit, .unit => true
  | .bool, .bool => true
  | .principal, .principal => true
  | .string, .string => true
  | .bytes la, .bytes lb => la == lb
  | .array ea la, .array eb lb => ea == eb && la == lb
  | .map ka va, .map kb vb => ka == kb && va == vb
  | .option ea, .option eb => ea == eb
  | .field sa, .field sb => fieldSpecEq sa sb
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

private partial def internSourceType (interner : TypeInternerV1) (ty : SrcType) :
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
  | .principal => pure (internShape interner .principal)
  | .string => pure (internShape interner .string)
  | .named n =>
      -- Named types are registered only in Pass0; body/declaration sites only
      -- look up. Never push a named TypeDecl here (would break named prefix).
      match lookupNamedTypeId interner (raw n) with
      | some tid => pure (interner, tid)
      | none =>
          failUnsupported s!"S1 named type '{raw n}' is not declared"
  | .bytes len =>
      if len.toNat ≤ maxTypeLengthV1 then
        pure (internShape interner (.bytes len))
      else
        failUnsupported
          s!"S1 Bytes length {len} exceeds maxTypeLengthV1 ({maxTypeLengthV1})"
  | .array el len => do
      if len.toNat > maxTypeLengthV1 then
        return ← failUnsupported
          s!"S1 Array length {len} exceeds maxTypeLengthV1 ({maxTypeLengthV1})"
      let (interner, elTid) ← internSourceType interner el
      pure (internShape interner (.array elTid len))
  | .option el => do
      let (interner, elTid) ← internSourceType interner el
      pure (internShape interner (.option elTid))
  | .map k v => do
      let (interner, kTid) ← internSourceType interner k
      let (interner, vTid) ← internSourceType interner v
      -- Wire map-key legality (Bool|UInt|Int|Principal|Bytes|Struct-of-legal-keys).
      match checkLegalMapKeyTypeV1 interner.types kTid interner.types.size with
      | .ok () => pure (internShape interner (.map kTid vTid))
      | .error _ =>
          failUnsupported "S1 Map key type is not a legal map key"
  | .field id =>
      -- T14 catalog v2: source token → closed catalog FieldSpec. The three
      -- admitted specs are bn254 Fr (EVM/Noir), BLS12-377 Fr (Aleo), and
      -- Goldilocks (Psy); target-owned type-closure selects which spec each
      -- target admits, so a spec accepted here may still fail closed at a
      -- target that does not own it.
      match fieldSpecOfToken? (raw id) with
      | some spec => pure (internShape interner (.field spec))
      | none =>
          failUnsupported
            s!"S1 Field catalog supports bn254_fr, bls12_377_fr, goldilocks; got '{raw id}'"

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

/-- Two's-complement little-endian encoding of a signed `Int` at `width` bits.
    Mirrors ReferenceMachineV1 `intToLeBytes` (no import). Precondition: value
    is in `[−2^(w−1), 2^(w−1)−1]`; callers enforce range. -/
private def encodeIntLeBytes (value : Int) (width : Nat) : ByteArray :=
  let bits : Nat :=
    if value < 0 then
      (value + Int.ofNat (Nat.pow 2 width)).toNat
    else
      value.toNat
  encodeNatLeBytes bits (width / 8)

/-- Look up any TypeDecl shape by TypeId (named or anonymous). -/
private def shapeOf? (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    Option TypeShapeV1 :=
  match types[typeId.toNat]? with
  | some decl => some decl.shape
  | none => none

/-- Look up an anonymous type shape by TypeId. -/
private def anonShapeOf? (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    Option TypeShapeV1 :=
  match types[typeId.toNat]? with
  | some decl => if decl.name.isNone then some decl.shape else none
  | none => none

/-- Find struct field index by exact name. -/
private def findStructFieldIndex (fields : Array WireStructFieldV1) (name : String) :
    Option (Nat × TypeIdV1) := Id.run do
  let mut i : Nat := 0
  for f in fields do
    if f.name == name then
      return some (i, f.typeId)
    i := i + 1
  pure none

/-- Find enum variant index by exact name. -/
private def findEnumVariantIndex (variants : Array WireEnumVariantV1) (name : String) :
    Option (Nat × Array TypeIdV1) := Id.run do
  let mut i : Nat := 0
  for v in variants do
    if v.name == name then
      return some (i, v.payloadTypes)
    i := i + 1
  pure none

/-- Require anonymous legal UInt or Int width at integer-only sites. -/
private def requireAnonymousIntegerTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt/Int width"
  | some _ =>
      failUnsupported s!"S1 {context} requires anonymous UInt/Int type"
  | none =>
      failUnsupported s!"S1 {context} references missing or named TypeId {typeId}"

/-- Target-neutral external `call`/`schedule` argument gate (N-8 + Principal).
    Admits legal UInt/Int and Principal only. String/Field/aggregates stay
    fail closed here; target-owned QN/account binding is not consulted. -/
private def requireAnonymousIntegerOrPrincipalTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt/Int/Principal type"
  | some .principal => pure ()
  | some _ =>
      failUnsupported s!"S1 {context} requires anonymous UInt/Int/Principal type"
  | none =>
      failUnsupported s!"S1 {context} references missing or named TypeId {typeId}"

/-- N-STR-EVENT: target-neutral event/error payloads admit the existing
    canonical String valueBytes shape in addition to legal integer scalars.
    Target-owned interface ABIs remain independently fail closed. -/
private def requireEventErrorFieldTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt/Int/String type"
  | some .string => pure ()
  | some _ =>
      failUnsupported s!"S1 {context} requires anonymous UInt/Int/String type"
  | none =>
      failUnsupported s!"S1 {context} references missing or named TypeId {typeId}"

/-- Catalog Field shape recognition (T14 catalog v2): the anonymous TypeDecl
    at `typeId` carries one of the three closed catalog FieldSpecs. -/
private def isAnonCatalogField
    (types : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match anonShapeOf? types typeId with
  | some (.field spec) => isCatalogFieldSpec spec
  | _ => false

/-- Require anonymous legal UInt/Int, sole catalog Field, or Principal
    (state / params). Principal is identity-only at later expression gates. -/
private def requireAnonymousIntegerOrFieldTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires legal UInt/Int/Field/Principal type"
  | some (.field spec) =>
      if isCatalogFieldSpec spec then pure ()
      else failUnsupported s!"S1 {context} requires a closed-catalog Field spec"
  | some .principal | some .string => pure ()
  | some _ =>
      failUnsupported s!"S1 {context} requires anonymous UInt/Int/Field/Principal/String type"
  | none =>
      failUnsupported s!"S1 {context} references missing or named TypeId {typeId}"

/-- N3/N4 + ArrayState + N-A4 state/param admission: anonymous legal
    UInt/Int/Field/Principal/String **or** named Struct/Enum **or** anonymous
    Array/Map/Bytes/Option. Unit/Bool still fail closed at declaration sites
    (locals may still hold them via let). Option default is wire none-tag. -/
private def requireStateOrParamTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"
  | some decl =>
      match decl.name, decl.shape with
      | some _, .struct _ => pure ()
      | some _, .enum _ => pure ()
      | some _, _ =>
          failUnsupported
            s!"S1 {context} named type must be Struct or Enum"
      | none, .uint w | none, .int w =>
          if legalIntegerWidthV1 w.toNat then pure ()
          else
            failUnsupported
              s!"S1 {context} requires legal UInt/Int/Field/Principal/String, named Struct/Enum, or Array/Map/Bytes/Option"
      | none, .field spec =>
          if isCatalogFieldSpec spec then pure ()
          else failUnsupported s!"S1 {context} requires a closed-catalog Field spec"
      | none, .principal | none, .string => pure ()
      | none, .array _ len =>
          if len.toNat ≤ maxTypeLengthV1 then pure ()
          else
            failUnsupported
              s!"S1 {context} Array length {len} exceeds maxTypeLengthV1 ({maxTypeLengthV1})"
      | none, .map _ _ => pure ()
      | none, .bytes len =>
          if len.toNat ≤ maxTypeLengthV1 then pure ()
          else
            failUnsupported
              s!"S1 {context} Bytes length {len} exceeds maxTypeLengthV1 ({maxTypeLengthV1})"
      | none, .option _ => pure ()
      | none, _ =>
          failUnsupported
            s!"S1 {context} requires anonymous UInt/Int/Field/Principal/String, named Struct/Enum, or Array/Map/Bytes/Option"

/-- Require entry/view/fn result type: anonymous legal UInt/Int, Unit,
    Bool, catalog Field, Principal, String, Array/Map/Bytes/Option, or named
    Struct/Enum. This is target-neutral Semantic admission; target-owned result
    ABIs independently fail closed on unsupported container shapes. -/
private def requireCallableResultTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"
  | some decl =>
      match decl.name, decl.shape with
      | some _, .struct _ => pure ()
      | some _, .enum _ => pure ()
      | some _, _ =>
          failUnsupported
            s!"S1 {context} named result type must be Struct or Enum"
      | none, .uint w | none, .int w =>
          if legalIntegerWidthV1 w.toNat then pure ()
          else
            failUnsupported
              s!"S1 {context} requires legal UInt/Int/Unit/Bool/Field/Principal/String, named Struct/Enum, or Array/Map/Bytes/Option"
      | none, .unit | none, .bool | none, .principal | none, .string => pure ()
      | none, .field spec =>
          if isCatalogFieldSpec spec then pure ()
          else failUnsupported s!"S1 {context} requires a closed-catalog Field spec"
      | none, .array _ len =>
          if len.toNat ≤ maxTypeLengthV1 then pure ()
          else
            failUnsupported
              s!"S1 {context} Array length {len} exceeds maxTypeLengthV1 ({maxTypeLengthV1})"
      | none, .map _ _ => pure ()
      | none, .bytes len =>
          if len.toNat ≤ maxTypeLengthV1 then pure ()
          else
            failUnsupported
              s!"S1 {context} Bytes length {len} exceeds maxTypeLengthV1 ({maxTypeLengthV1})"
      | none, .option _ => pure ()
      | none, _ =>
          failUnsupported
            s!"S1 {context} requires UInt/Int/Unit/Bool/Field/Principal/String, named Struct/Enum, or Array/Map/Bytes/Option"

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

/-- Require anonymous legal UInt/Int or sole catalog Field expected type
    (binary arithmetic). Field `mod` is rejected separately. -/
private def requireExpectedIntegerOrFieldWidth
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match anonShapeOf? types typeId with
  | some (.uint w) | some (.int w) =>
      if legalIntegerWidthV1 w.toNat then pure ()
      else failUnsupported s!"S1 {context} requires expected legal UInt/Int/Field type"
  | some (.field spec) =>
      if isCatalogFieldSpec spec then pure ()
      else failUnsupported s!"S1 {context} requires a closed-catalog Field spec"
  | some _ =>
      failUnsupported s!"S1 {context} requires expected legal UInt/Int/Field type"
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

/-- Signed negated magnitude max inclusive `2^(width-1)` (intMin magnitude). -/
private def intNegatedInclusiveMax (width : Nat) : Nat :=
  Nat.pow 2 (width - 1)

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

/-- Rebind the most-recent binding of `name` (field/index local update).
    If the name is absent, inserts a fresh binding (should not happen for
    field/index assign which first requires an env hit). -/
private def envRebind (env : LocalEnvV1) (name : String) (vid : ValueIdV1)
    (tid : TypeIdV1) : LocalEnvV1 := Id.run do
  let mut lastIdx? : Option Nat := none
  let mut i : Nat := 0
  for (n, _, _) in env.bindings do
    if n == name then lastIdx? := some i
    i := i + 1
  match lastIdx? with
  | some idx => ⟨env.bindings.set! idx (name, vid, tid)⟩
  | none => ⟨env.bindings.push (name, vid, tid)⟩

/-- State name → (StateId, TypeId). -/
structure StateTableV1 where
  rows : Array (String × StateIdV1 × TypeIdV1)

private def stateLookup (table : StateTableV1) (name : String) :
    Option (StateIdV1 × TypeIdV1) :=
  table.rows.findSome? fun (n, sid, tid) =>
    if n == name then some (sid, tid) else none

/-- Const name → (ConstantId, TypeId). Built complete before any callable body
    so forward references resolve; IDs are dense source-order among const decls. -/
structure ConstantTableV1 where
  rows : Array (String × ConstantIdV1 × TypeIdV1)

private def constLookup (table : ConstantTableV1) (name : String) :
    Option (ConstantIdV1 × TypeIdV1) :=
  table.rows.findSome? fun (n, cid, tid) =>
    if n == name then some (cid, tid) else none

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
`currentParams` carries the open block's params (loop headers: induction
variable; expression-match joins: the matched arm value). `loopBounds`
accumulates static loop-bound entries in completion order and is sorted into
canonical ascending (header, backEdgeFrom) order at callable assembly.
`nextEffectId` counts emitted effect instructions (emit) in BlockId/
instruction order, which is exactly the canonical EffectId order. Loop-header
and expression-match join block params draw from
`callableParamCount + nextBlockParamOrdinal` (creation order == BlockId order
of param-bearing blocks), and `nextValueId` starts past the syntactically
counted block-param range, so the SPEC §6 canonical three-pass ValueId order
(callable params → block params → instruction results) holds by construction
with no remap. -/
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
  /-- Callable parameter names (immutable). Bare assign rebinds only non-param
      env names (let locals and for binders) — N-6. -/
  paramNames : Array String := #[]
  /-- Complete const table (source-order dense IDs). Locals/params shadow via
      `env`; bare names resolve env → state → const. Available in pureFn too. -/
  constants : ConstantTableV1 := ⟨#[]⟩
  interner : TypeInternerV1
  /-- N5: true for init/entry/view; false for pureFn (ContextRead/Commit fail closed). -/
  allowContextCommit : Bool := false
  /-- N5/N-2: Op.ContextRead unix-time-seconds used (wire requirement merge). -/
  usedContextUnixTime : Bool := false
  /-- N-2: Op.ContextRead caller used (wire requirement merge). -/
  usedContextCaller : Bool := false
  /-- ADR-0031 S2: Op.ContextRead block-height used (wire requirement merge). -/
  usedContextBlockHeight : Bool := false
  /-- N5: any Op.Commit emitted in this program (for wire requirement merge). -/
  usedCommit : Bool := false

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

/-- Back-patch a jump terminator's target block, preserving jump args (needed
    for expression-match arm → join value-passing). -/
private def patchJumpTarget (st : BodyStateV1) (blockIdx : Nat) (targetId : BlockIdV1) :
    BodyStateV1 :=
  patchTerminatorAt st blockIdx fun
    | .jump t => .jump { blockId := targetId, args := t.args }
    | t => t

/-- Back-patch a switch terminator's cases and default target. -/
private def patchSwitch (st : BodyStateV1) (blockIdx : Nat)
    (cases : Array SwitchCaseV1) (defaultTarget : Option JumpTargetV1) : BodyStateV1 :=
  patchTerminatorAt st blockIdx fun
    | .switch scrut _ _ => .switch scrut cases defaultTarget
    | t => t

/-- Unique-preserving append of strings (O(n²) small-n). -/
private def uniquePushString (xs : Array String) (x : String) : Array String :=
  if xs.any (· == x) then xs else xs.push x

private def uniqueStringsV1 (xs : Array String) : Array String :=
  xs.foldl uniquePushString #[]

/-- Place root raw name (no Except; used for static N-6 carried analysis). -/
private partial def placeRootRawNameV1 (place : SrcPlace) : String :=
  match place with
  | .name n => raw n
  | .field base _ => placeRootRawNameV1 base
  | .index base _ => placeRootRawNameV1 base

/-- Collect assign-target root names under a statement tree (N-6 loop-carried). -/
private partial def collectAssignRootsStmtsV1 (stmts : Array SrcStmt) : Array String :=
  stmts.foldl (fun acc stmt => acc ++ collectAssignRootsStmtV1 stmt) #[]
where
  collectAssignRootsStmtV1 : SrcStmt → Array String
    | .assign target _ => #[placeRootRawNameV1 target]
    | .if_ _ thenBlock elseBlock? =>
        collectAssignRootsStmtsV1 thenBlock.statements ++
          (elseBlock?.map (fun b => collectAssignRootsStmtsV1 b.statements)).getD #[]
    | .match_ _ arms =>
        arms.foldl (fun acc arm => acc ++ collectAssignRootsStmtsV1 arm.body.statements) #[]
    | .for_ _ _ _ _ body => collectAssignRootsStmtsV1 body.statements
    | _ => #[]

/-- Names a for-body may rebind from an outer live set (excludes binder + params). -/
private def loopCarriedNamesV1
    (body : SrcBlock) (live : Array String) (binder : String)
    (paramNames : Array String) : Array String :=
  let roots := collectAssignRootsStmtsV1 body.statements
  uniqueStringsV1 (roots.filterMap fun n =>
    if n != binder && live.any (· == n) && !(paramNames.any (· == n)) then
      some n
    else none)

/-- Count loop-header block params: each `for` contributes `1 + |carried|`
    (induction + N-6 loop-carried mutable outer locals) plus nested fors.
    Thread `live` let/param names so carried detection matches lowering. -/
private partial def countLoopBlockParamsStmtsV1
    (stmts : Array SrcStmt) (live : Array String) (paramNames : Array String) :
    Nat :=
  (countLoopBlockParamsStmtsGo stmts live paramNames).1
where
  countLoopBlockParamsStmtsGo (stmts : Array SrcStmt) (live : Array String)
      (paramNames : Array String) : Nat × Array String :=
    stmts.foldl
      (fun (acc, live) stmt =>
        let (c, live') := countLoopBlockParamsStmtV1 stmt live paramNames
        (acc + c, live'))
      (0, live)

  countLoopBlockParamsStmtV1 (stmt : SrcStmt) (live : Array String)
      (paramNames : Array String) : Nat × Array String :=
    match stmt with
    | .let_ name _ _ =>
        (0, uniquePushString live (raw name))
    | .if_ _ thenBlock elseBlock? =>
        let cT := countLoopBlockParamsStmtsV1 thenBlock.statements live paramNames
        let cE := match elseBlock? with
          | some b => countLoopBlockParamsStmtsV1 b.statements live paramNames
          | none => 0
        (cT + cE, live)
    | .match_ _ arms =>
        let c := arms.foldl
          (fun acc arm =>
            acc + countLoopBlockParamsStmtsV1 arm.body.statements live paramNames)
          0
        (c, live)
    | .for_ binder _ _ _ body =>
        let bname := raw binder
        let carried := loopCarriedNamesV1 body live bname paramNames
        let liveBody := uniquePushString live bname
        let nested := countLoopBlockParamsStmtsV1 body.statements liveBody paramNames
        (1 + carried.size + nested, live)
    | _ => (0, live)

/-- Whether an expression match has at least one switch case (integer/Bool
    literal or constructor) and therefore allocates a join block param.
    Catch-all-only matches inline without a join. -/
private def exprMatchNeedsJoinV1
    (arms : Array ProofForgeV2.Source.AstSpineV1.ExprMatchArmV1) : Bool :=
  arms.any fun arm =>
    match arm.pattern with
    | .literal (.integer _) | .literal (.bool _) | .constructor _ _ => true
    | _ => false

/-- Count expression-match join block params reachable from expressions
    (including nested matches and place indices). Each join-needing match
    contributes exactly one block param. -/
private partial def countExprMatchJoinsInExprV1 (expr : SrcExpr) : Nat :=
  match expr with
  | .match_ scrutinee arms =>
      let self := if exprMatchNeedsJoinV1 arms then 1 else 0
      self + countExprMatchJoinsInExprV1 scrutinee +
        arms.foldl (fun acc arm => acc + countExprMatchJoinsInExprV1 arm.value) 0
  | .binary _ lhs rhs =>
      countExprMatchJoinsInExprV1 lhs + countExprMatchJoinsInExprV1 rhs
  | .unary _ operand => countExprMatchJoinsInExprV1 operand
  | .localCall _ args =>
      args.foldl (fun acc a => acc + countExprMatchJoinsInExprV1 a) 0
  | .externalCall call =>
      call.args.foldl (fun acc a => acc + countExprMatchJoinsInExprV1 a) 0
  | .constructor _ args =>
      args.foldl (fun acc a => acc + countExprMatchJoinsInExprV1 a) 0
  | .place p => countExprMatchJoinsInPlaceV1 p
  | .literal _ => 0
where
  countExprMatchJoinsInPlaceV1 : SrcPlace → Nat
    | .name _ => 0
    | .field base _ => countExprMatchJoinsInPlaceV1 base
    | .index base idx =>
        countExprMatchJoinsInPlaceV1 base + countExprMatchJoinsInExprV1 idx

/-- Count expression-match joins in statement lists (let/return/if/for/… values). -/
private partial def countExprMatchJoinsInStmtsV1 (stmts : Array SrcStmt) : Nat :=
  stmts.foldl (fun acc stmt => acc + countExprMatchJoinsInStmtV1 stmt) 0
where
  countExprMatchJoinsInStmtV1 : SrcStmt → Nat
    | .let_ _ _ value => countExprMatchJoinsInExprV1 value
    | .assign target value =>
        countExprMatchJoinsInExprV1 (.place target) + countExprMatchJoinsInExprV1 value
    | .if_ condition thenBlock elseBlock? =>
        countExprMatchJoinsInExprV1 condition +
          countExprMatchJoinsInStmtsV1 thenBlock.statements +
          (elseBlock?.map (fun b => countExprMatchJoinsInStmtsV1 b.statements)).getD 0
    | .match_ scrutinee arms =>
        countExprMatchJoinsInExprV1 scrutinee +
          arms.foldl (fun acc arm =>
            acc + countExprMatchJoinsInStmtsV1 arm.body.statements) 0
    | .for_ _ start endExclusive _ body =>
        countExprMatchJoinsInExprV1 start + countExprMatchJoinsInExprV1 endExclusive +
          countExprMatchJoinsInStmtsV1 body.statements
    | .assert_ condition _ => countExprMatchJoinsInExprV1 condition
    | .return_ (some e) => countExprMatchJoinsInExprV1 e
    | .return_ none => 0
    | .revert _ args =>
        args.foldl (fun acc a => acc + countExprMatchJoinsInExprV1 a) 0
    | .emit _ args =>
        args.foldl (fun acc a => acc + countExprMatchJoinsInExprV1 a) 0
    | .call externalCall =>
        externalCall.args.foldl (fun acc a => acc + countExprMatchJoinsInExprV1 a) 0
    | .schedule externalCall =>
        externalCall.args.foldl (fun acc a => acc + countExprMatchJoinsInExprV1 a) 0

/-- Require an already-interned TypeId for a `let` binding: any registered
    scalar, named Struct/Enum, or anonymous aggregate (Array/Map/Option/Bytes/
    Principal/Field) is allowed. Missing TypeId fails closed. -/
private def requireLetTypeId
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (context : String) :
    Except NormalizeErrorV1 Unit :=
  match types[typeId.toNat]? with
  | some _ => pure ()
  | none =>
      failUnsupported s!"S1 {context} references missing TypeId {typeId}"

/-- Type-only walk of a place chain (env/state/const root + field/index).
    N5/N-2: ContextRead surfaces are not env/state/const roots.
    Lookup priority: locals/params → state → const (Typed fail-closes top-level
    state/const name clashes; body locals shadow both). -/
private partial def synthPlaceTypeV1
    (place : SrcPlace) (interner : TypeInternerV1)
    (env : LocalEnvV1) (states : StateTableV1) (constants : ConstantTableV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match place with
  | .name n =>
      let key := raw n
      match envLookup env key with
      | some (_, tid) => pure (interner, tid)
      | none =>
          match stateLookup states key with
          | some (_, tid) => pure (interner, tid)
          | none =>
              match constLookup constants key with
              | some (_, tid) => pure (interner, tid)
              | none =>
                  if key == "context" then
                    failUnsupported
                      "S1 context place must be context.unixTimeSeconds, context.caller or context.blockHeight (field chain)"
                  else
                    failUnsupported
                      s!"S1 bare place '{key}' is neither param, state, nor const"
  | .field base fieldName => do
      match base with
      | .name root =>
          if raw root == "context" && raw fieldName == "unixTimeSeconds" then
            pure (internShape interner (.uint 64))
          else if raw root == "context" && raw fieldName == "caller" then
            pure (internShape interner .principal)
          else if raw root == "context" && raw fieldName == "blockHeight" then
            pure (internShape interner (.uint 64))
          else do
            let (interner, baseTid) ←
              synthPlaceTypeV1 base interner env states constants
            match shapeOf? interner.types baseTid with
            | some (.struct fields) =>
                match findStructFieldIndex fields (raw fieldName) with
                | none =>
                    failUnsupported
                      s!"S1 field '{raw fieldName}' not found on struct"
                | some (_, fieldTid) => pure (interner, fieldTid)
            | _ =>
                failUnsupported "S1 field place requires a struct base"
      | _ => do
          let (interner, baseTid) ←
            synthPlaceTypeV1 base interner env states constants
          match shapeOf? interner.types baseTid with
          | some (.struct fields) =>
              match findStructFieldIndex fields (raw fieldName) with
              | none =>
                  failUnsupported
                    s!"S1 field '{raw fieldName}' not found on struct"
              | some (_, fieldTid) => pure (interner, fieldTid)
          | _ =>
              failUnsupported "S1 field place requires a struct base"
  | .index base _idxExpr => do
      let (interner, baseTid) ←
        synthPlaceTypeV1 base interner env states constants
      match shapeOf? interner.types baseTid with
      | some (.array elTid _) => pure (interner, elTid)
      | some (.bytes _) =>
          let (iU8, u8Tid) := internShape interner (.uint 8)
          pure (iU8, u8Tid)
      | some (.map _keyTid valTid) =>
          let (iOpt, optTid) := internShape interner (.option valTid)
          pure (iOpt, optTid)
      | _ =>
          failUnsupported "S1 index place requires Array, Bytes, or Map base"

/-- When an expression is a place (bare / field / index), synthesize its TypeId
    via the full place walk (env → state → const). Non-place heads return none
    so callers can fall back to the other operand or a UInt64 default. -/
private def trySynthPlaceExprTypeV1
    (expr : SrcExpr) (st : BodyStateV1) (states : StateTableV1) :
    Except NormalizeErrorV1 (Option (TypeInternerV1 × TypeIdV1)) :=
  match expr with
  | .place p => do
      let pair ← synthPlaceTypeV1 p st.interner st.env states st.constants
      pure (some pair)
  | .unary _ (.place p) => do
      let pair ← synthPlaceTypeV1 p st.interner st.env states st.constants
      pure (some pair)
  | _ => pure none

/-- Operand TypeId for arithmetic/bitwise/shift binary synthesis and comparison:
    lhs place first (TypeCheck order); if lhs is not a place, use rhs place
    (env/state/const, including field/index when synthPlaceType admits it).
    Both places still lower lhs-first; same-type gate rejects mismatches. -/
private def synthBinaryOperandTypeV1
    (lhs rhs : SrcExpr) (st : BodyStateV1) (states : StateTableV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) := do
  match ← trySynthPlaceExprTypeV1 lhs st states with
  | some pair => pure pair
  | none =>
      match ← trySynthPlaceExprTypeV1 rhs st states with
      | some pair => pure pair
      | none => pure (internShape st.interner (.uint 64))

/-- Derive the expected TypeId for an unannotated `let` RHS from its head
shape. CheckV1 has already rejected integer literals without an expected
type, so every remaining pilot shape carries an intrinsic result type.

Unannotated arithmetic/bitwise/unary still default to UInt64 only when
neither operand is an env/state/const place. Prefer lhs place width, else
rhs place width (N-CONST-REF), so `1 + NARROW` / comparison with const rhs
keep exact width when TypeCheck has already accepted the program under an
enclosing expected type or annotated let. -/
private partial def synthLetExpectedV1
    (value : SrcExpr) (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match value with
  | .literal (.integer _) =>
      failUnsupported "S1 let integer literal requires a type annotation"
  | .literal (.bool _) => pure (internShape st.interner .bool)
  | .literal (.string _) => pure (internShape st.interner .string)
  | .place p =>
      synthPlaceTypeV1 p st.interner st.env states st.constants
  | .binary op lhs rhs =>
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
        synthBinaryOperandTypeV1 lhs rhs st states
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
  | .unary _ operand => do
      match ← trySynthPlaceExprTypeV1 operand st states with
      | some pair => pure pair
      | none => pure (internShape st.interner (.uint 64))
  | .constructor _ _ =>
      -- Constructor result type is supplied by the let annotation (or enclosing
      -- expected context); unannotated constructor lets fail closed here.
      failUnsupported "S1 let constructor requires a type annotation"
  | .localCall callee _ =>
      let key := raw callee
      match fnLookup fns key with
      | none => failUnsupported s!"S1 localCall '{key}' is not a declared fn"
      | some (_, _, fnResultTid) => pure (st.interner, fnResultTid)
  | .match_ _ arms =>
      -- Unannotated let of a match expression: prefer an explicit annotation.
      -- Without one, try the first arm value head (place / Bool / comparison).
      match arms[0]? with
      | none => failUnsupported "S1 match expression requires at least one arm"
      | some arm => synthLetExpectedV1 arm.value st states fns
  | .externalCall _ =>
      -- Value-position call cannot synthesize a result type from nothing:
      -- the type must come from the let annotation or an enclosing expected
      -- context (N-CALL-RET).
      failUnsupported "S1 value-position call requires a type annotation"

/-- Infer comparison operand TypeId (TypeCheck order: lhs first, then rhs under
    that type). When lhs is not a place, use rhs place (env/state/const) so
    programs TypeCheck already accepts with a const/place rhs keep exact width
    rather than defaulting to UInt64. -/
private def synthComparisonOperandTypeV1
    (lhs rhs : SrcExpr) (st : BodyStateV1) (states : StateTableV1) :
    Except NormalizeErrorV1 (TypeInternerV1 × TypeIdV1) :=
  match lhs with
  | .place p =>
      synthPlaceTypeV1 p st.interner st.env states st.constants
  | .unary _ operand => do
      match ← trySynthPlaceExprTypeV1 operand st states with
      | some pair => pure pair
      | none => synthBinaryOperandTypeV1 lhs rhs st states
  | .binary op l r =>
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
        synthComparisonOperandTypeV1 l r st states
      else
        synthBinaryOperandTypeV1 lhs rhs st states
  | .localCall callee _ =>
      failUnsupported
        s!"S1 comparison operand localCall '{raw callee}' needs an explicit integer place"
  | _ =>
      -- Literal / other non-place lhs: exact width from rhs place when present.
      synthBinaryOperandTypeV1 lhs rhs st states

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

/-- Resolve a Phase-1 constructor path to (result TypeId, ctorIndex, arg TypeIds).
    Identities: `StructName.new`, `EnumName.Variant`, bare struct name (compat),
    bare unique enum variant, `Option.some`/`Option.none` (need expected Option),
    `Map.empty` (need expected Map; empty construct only — N-1). -/
private def resolveConstructorLoweringV1
    (interner : TypeInternerV1) (ctor : SourceQualifiedNameV1)
    (expectedTid : TypeIdV1) :
    Except NormalizeErrorV1 (TypeIdV1 × UInt32 × Array TypeIdV1) := do
  let comps := (NonEmptyArray.toArray ctor.components).map (·.raw)
  match comps with
  | #[structName, "new"] =>
      match lookupNamedTypeId interner structName with
      | none =>
          failUnsupported s!"S1 constructor '{structName}.new' is not a declared struct"
      | some tid =>
          match shapeOf? interner.types tid with
          | some (.struct fields) =>
              pure (tid, 0, fields.map (·.typeId))
          | _ =>
              failUnsupported s!"S1 '{structName}.new' requires a struct type"
  | #[typeName, variantName] =>
      -- EnumName.Variant, Option.some/none, or Map.empty
      if typeName == "Option" then
        match shapeOf? interner.types expectedTid with
        | some (.option elTid) =>
            -- Accept both source-style Some/None and lowercase some/none.
            if variantName == "none" || variantName == "None" then
              pure (expectedTid, 0, #[])
            else if variantName == "some" || variantName == "Some" then
              pure (expectedTid, 1, #[elTid])
            else
              failUnsupported
                s!"S1 Option constructor must be Option.some/none (or Some/None), got '{variantName}'"
        | _ =>
            failUnsupported
              "S1 Option constructor requires an enclosing Option expected type"
      else if typeName == "Map" then
        -- N-1: empty Map construct only (ctorIndex 0, no args). Nonempty maps
        -- are product-built via IndexSet upsert, not multi-arg Construct.
        match shapeOf? interner.types expectedTid with
        | some (.map _ _) =>
            if variantName == "empty" || variantName == "Empty" then
              pure (expectedTid, 0, #[])
            else
              failUnsupported
                s!"S1 Map constructor must be Map.empty (or Empty), got '{variantName}'"
        | _ =>
            failUnsupported
              "S1 Map.empty requires an enclosing Map expected type"
      else
        match lookupNamedTypeId interner typeName with
        | none =>
            failUnsupported s!"S1 constructor type '{typeName}' is not declared"
        | some tid =>
            match shapeOf? interner.types tid with
            | some (.enum variants) =>
                match findEnumVariantIndex variants variantName with
                | none =>
                    failUnsupported
                      s!"S1 enum '{typeName}' has no variant '{variantName}'"
                | some (idx, payloads) =>
                    pure (tid, UInt32.ofNat idx, payloads)
            | some (.struct _) =>
                failUnsupported
                  s!"S1 struct '{typeName}' constructor must use '{typeName}.new'"
            | _ =>
                failUnsupported s!"S1 '{typeName}.{variantName}' is not a constructible type"
  | #[name] =>
      match lookupNamedTypeId interner name with
      | some tid =>
          match shapeOf? interner.types tid with
          | some (.struct fields) =>
              pure (tid, 0, fields.map (·.typeId))
          | _ =>
              failUnsupported s!"S1 bare constructor '{name}' is not a struct"
      | none =>
          let mut hits : Array (TypeIdV1 × Nat × Array TypeIdV1) := #[]
          let mut i : Nat := 0
          for d in interner.types do
            match d.name, d.shape with
            | some _, .enum variants =>
                match findEnumVariantIndex variants name with
                | some (vIdx, payloads) =>
                    hits := hits.push (UInt32.ofNat i, vIdx, payloads)
                | none => pure ()
            | _, _ => pure ()
            i := i + 1
          match hits.toList with
          | [(tid, vIdx, payloads)] =>
              pure (tid, UInt32.ofNat vIdx, payloads)
          | _ :: _ :: _ =>
              failUnsupported s!"S1 bare constructor '{name}' is ambiguous"
          | _ =>
              failUnsupported s!"S1 constructor '{name}' is not declared"
  | _ =>
      failUnsupported
        "S1 constructor path must be Struct.new, Enum.Variant, Option.some/none, or Map.empty"

/-- Resolve a constructor *pattern* against an already-known scrutinee TypeId.
    Returns (variantIndex, payload TypeIds). Result type must equal scrutTid. -/
private def resolveCtorPatternV1
    (interner : TypeInternerV1) (ctor : SourceQualifiedNameV1) (scrutTid : TypeIdV1) :
    Except NormalizeErrorV1 (UInt32 × Array TypeIdV1) := do
  let (resultTid, idx, payloads) ←
    resolveConstructorLoweringV1 interner ctor scrutTid
  unless resultTid == scrutTid do
    return ← failUnsupported
      "S1 constructor pattern type does not match match scrutinee"
  pure (idx, payloads)

/-- True when the scrutinee TypeId is Enum or Option (constructor-matchable). -/
private def isCtorMatchScrutineeV1 (types : Array TypeDeclV1) (tid : TypeIdV1) : Bool :=
  match shapeOf? types tid with
  | some (.enum _) | some (.option _) => true
  | _ => false

/-- Bind constructor-arm payload sub-patterns into the local env (N4).

    Supported (single outer-ctor arm, no competing same-outer refinement):
    * `wildcard` — skip
    * `bind` — `Op.VariantPayload` into env
    * nested `constructor` — recursive on the extracted payload when the
      payload TypeId is Enum/Option (no runtime tag guard here; multi-arm
      same-outer refinement uses `lowerCtorArgGuardsCollectFailsV1`)
    * nested `literal` — ignored at bind time for the single-arm path;
      multi-arm same-outer uses eq guards via the guard collector

    Nested constructor assumes a single outer-ctor arm owns this payload path;
    it does not re-switch on the outer tag. -/
private partial def bindCtorArgPatternsV1
    (scrutVid : ValueIdV1) (variantIndex : UInt32)
    (payloadTids : Array TypeIdV1) (argPatterns : Array SrcPattern)
    (st : BodyStateV1) : Except NormalizeErrorV1 BodyStateV1 := do
  unless argPatterns.size == payloadTids.size do
    return ← failUnsupported
      s!"S1 constructor pattern expects {payloadTids.size} arguments, got {argPatterns.size}"
  let mut st := st
  let mut i : Nat := 0
  for pat in argPatterns do
    let some pTid := payloadTids[i]? |
      return ← failUnsupported "S1 constructor pattern payload index out of range"
    match pat with
    | .wildcard => pure ()
    | .bind name =>
        let (st1, vid) := emitValue st pTid
          (.variantPayload scrutVid variantIndex (UInt32.ofNat i))
        st := { st1 with env := envInsert st1.env (raw name) vid pTid }
    | .literal _ =>
        -- Nested literal guards are applied by multi-arm same-outer refinement.
        pure ()
    | .constructor nestedCtor nestedArgs => do
        unless isCtorMatchScrutineeV1 st.interner.types pTid do
          return ← failUnsupported
            "S1 nested constructor pattern requires Enum or Option payload"
        let (nIdx, nPayloads) ←
          resolveCtorPatternV1 st.interner nestedCtor pTid
        let (st1, pVid) := emitValue st pTid
          (.variantPayload scrutVid variantIndex (UInt32.ofNat i))
        st ← bindCtorArgPatternsV1 pVid nIdx nPayloads nestedArgs st1
    i := i + 1
  pure st

/-- Encode a source literal to canonical valueBytes under an expected TypeId.
    Used by match case materialization and nested-literal guards. -/
private def encodeLiteralValueBytesV1
    (types : Array TypeDeclV1) (expectedTid : TypeIdV1)
    (lit : ProofForgeV2.Source.AstV1.LiteralV1) :
    Except NormalizeErrorV1 ByteArray := do
  match lit with
  | .bool value =>
      match anonShapeOf? types expectedTid with
      | some .bool => pure (encodeBool value)
      | _ => failUnsupported "S1 Bool literal requires Bool type"
  | .integer magnitude =>
      match anonShapeOf? types expectedTid with
      | some (.uint w) =>
          let width := w.toNat
          unless legalIntegerWidthV1 width do
            return ← failUnsupported "S1 integer literal requires legal UInt width"
          unless magnitude < uintExclusiveLimit width do
            return ← failUnsupported "S1 UInt integer literal is out of range"
          pure (encodeNatLeBytes magnitude (width / 8))
      | some (.int w) =>
          let width := w.toNat
          unless legalIntegerWidthV1 width do
            return ← failUnsupported "S1 integer literal requires legal Int width"
          unless magnitude ≤ intPositiveInclusiveMax width do
            return ← failUnsupported "S1 Int integer literal is out of range"
          pure (encodeNatLeBytes magnitude (width / 8))
      | _ => failUnsupported "S1 integer literal requires legal UInt/Int type"
  | .string value =>
      match anonShapeOf? types expectedTid with
      | some .string => do
          let bytes ← match encodeString value with
            | .ok b => pure b
            | .error _ =>
                failUnsupported "S1 String literal is not NFC UTF-8"
          unless bytes.size ≤ 4 + maxTypeLengthV1 do
            return ← failUnsupported "S1 String literal exceeds maxTypeLengthV1"
          pure bytes
      | _ => failUnsupported "S1 String literal requires String type"

/-- Structural pattern key for multi-arm same-outer duplicate detection.
    Bind and wildcard are equivalent catch-alls; constructors key by resolved
    variant index; literals by canonical valueBytes under the expected type. -/
private inductive PatternShapeKeyV1 where
  | catchAll
  | lit (bytes : ByteArray)
  | ctor (vIdx : UInt32) (args : Array PatternShapeKeyV1)

private partial def patternShapeKeyEqV1 :
    PatternShapeKeyV1 → PatternShapeKeyV1 → Bool
  | .catchAll, .catchAll => true
  | .lit a, .lit b => a == b
  | .ctor i as, .ctor j bs =>
      i == j && as.size == bs.size &&
        (List.range as.size).all fun k =>
          match as[k]?, bs[k]? with
          | some a, some b => patternShapeKeyEqV1 a b
          | _, _ => false
  | _, _ => false

private partial def patternShapeKeyV1
    (interner : TypeInternerV1) (expectedTid : TypeIdV1) (pat : SrcPattern) :
    Except NormalizeErrorV1 PatternShapeKeyV1 := do
  match pat with
  | .wildcard | .bind _ => pure .catchAll
  | .literal lit => do
      let bytes ← encodeLiteralValueBytesV1 interner.types expectedTid lit
      pure (.lit bytes)
  | .constructor ctor args => do
      let (vIdx, payloads) ← resolveCtorPatternV1 interner ctor expectedTid
      unless args.size == payloads.size do
        return ← failUnsupported
          s!"S1 constructor pattern expects {payloads.size} arguments, got {args.size}"
      let mut ks : Array PatternShapeKeyV1 := #[]
      let mut i : Nat := 0
      for arg in args do
        let some pTid := payloads[i]? |
          return ← failUnsupported "S1 constructor pattern payload index out of range"
        let k ← patternShapeKeyV1 interner pTid arg
        ks := ks.push k
        i := i + 1
      pure (.ctor vIdx ks)

/-- Shape key for a resolved outer constructor arm (variant index + arg shapes). -/
private partial def ctorArmShapeKeyV1
    (interner : TypeInternerV1) (vIdx : UInt32)
    (payloads : Array TypeIdV1) (args : Array SrcPattern) :
    Except NormalizeErrorV1 PatternShapeKeyV1 := do
  unless args.size == payloads.size do
    return ← failUnsupported
      s!"S1 constructor pattern expects {payloads.size} arguments, got {args.size}"
  let mut ks : Array PatternShapeKeyV1 := #[]
  let mut i : Nat := 0
  for arg in args do
    let some pTid := payloads[i]? |
      return ← failUnsupported "S1 constructor pattern payload index out of range"
    let k ← patternShapeKeyV1 interner pTid arg
    ks := ks.push k
    i := i + 1
  pure (.ctor vIdx ks)

/-- True when `shape` matches any prior arm key (structural duplicate). -/
private def ctorArmShapeIsDuplicateV1
    (shape : PatternShapeKeyV1) (prior : Array PatternShapeKeyV1) : Bool :=
  prior.any (fun k => patternShapeKeyEqV1 shape k)

/-- True when every arg pattern is wildcard/bind only (arm always matches the
    outer constructor without nested discrimination). -/
private def ctorArgPatternsUnconditionalV1 (argPatterns : Array SrcPattern) : Bool :=
  argPatterns.all fun p =>
    match p with
    | .wildcard | .bind _ => true
    | .literal _ | .constructor _ _ => false

/-- Group constructor arms by outer variant index (first-seen order of the
    variant; source order preserved within each group). -/
private def groupCtorArmsByVariantV1
    (ctorArms : Array (UInt32 × Array TypeIdV1 × Array SrcPattern × α)) :
    Array (UInt32 × Array (Array TypeIdV1 × Array SrcPattern × α)) := Id.run do
  let mut order : Array UInt32 := #[]
  let mut groups : Array (Array (Array TypeIdV1 × Array SrcPattern × α)) := #[]
  for (vIdx, payloads, args, body) in ctorArms do
    let mut found : Option Nat := none
    let mut j : Nat := 0
    for ov in order do
      if ov == vIdx then found := some j
      j := j + 1
    match found with
    | some gi =>
        groups := groups.set! gi (groups[gi]!.push (payloads, args, body))
    | none =>
        order := order.push vIdx
        groups := groups.push #[(payloads, args, body)]
  let mut out :
      Array (UInt32 × Array (Array TypeIdV1 × Array SrcPattern × α)) := #[]
  let mut i : Nat := 0
  for vIdx in order do
    out := out.push (vIdx, groups[i]!)
    i := i + 1
  pure out

/-- Lower nested constructor/literal guards for one arm. Else-branches of
    discriminating tests use placeholder block id 0; the caller patches them
    to the next arm or outer fallthrough. Success leaves an open block with
    binds applied. -/
private partial def lowerCtorArgGuardsCollectFailsV1
    (baseVid : ValueIdV1) (variantIndex : UInt32)
    (payloadTids : Array TypeIdV1) (argPatterns : Array SrcPattern)
    (st : BodyStateV1) :
    Except NormalizeErrorV1 (BodyStateV1 × Array Nat) := do
  unless argPatterns.size == payloadTids.size do
    return ← failUnsupported
      s!"S1 constructor pattern expects {payloadTids.size} arguments, got {argPatterns.size}"
  go 0 st #[]
where
  go (i : Nat) (st : BodyStateV1) (fails : Array Nat) :
      Except NormalizeErrorV1 (BodyStateV1 × Array Nat) := do
    if i ≥ argPatterns.size then
      pure (st, fails)
    else
      let some pat := argPatterns[i]? |
        return ← failUnsupported "S1 constructor pattern arg index out of range"
      let some pTid := payloadTids[i]? |
        return ← failUnsupported "S1 constructor pattern payload index out of range"
      match pat with
      | .wildcard => go (i + 1) st fails
      | .bind name =>
          let (st1, vid) := emitValue st pTid
            (.variantPayload baseVid variantIndex (UInt32.ofNat i))
          go (i + 1)
            { st1 with env := envInsert st1.env (raw name) vid pTid } fails
      | .literal lit => do
          let (st1, pVid) := emitValue st pTid
            (.variantPayload baseVid variantIndex (UInt32.ofNat i))
          let bytes ← encodeLiteralValueBytesV1 st1.interner.types pTid lit
          let (st2, litVid) := emitValue st1 pTid (.literal pTid bytes)
          let (iB, boolTid) := internShape st2.interner .bool
          let st2b := { st2 with interner := iB }
          let (st3, eqVid) :=
            emitValue st2b boolTid (.binary BinaryOpV1.eq pVid litVid)
          let condIdx := st3.blocks.size
          let thenId := UInt32.ofNat (condIdx + 1)
          let st4 := sealCurrentBlock st3 (.branch eqVid
            { blockId := thenId, args := #[] }
            { blockId := 0, args := #[] })
          go (i + 1) st4 (fails.push condIdx)
      | .constructor nestedCtor nestedArgs => do
          unless isCtorMatchScrutineeV1 st.interner.types pTid do
            return ← failUnsupported
              "S1 nested constructor pattern requires Enum or Option payload"
          let (nIdx, nPayloads) ←
            resolveCtorPatternV1 st.interner nestedCtor pTid
          let (st1, pVid) := emitValue st pTid
            (.variantPayload baseVid variantIndex (UInt32.ofNat i))
          let (iU32, u32Tid) := internShape st1.interner (.uint 32)
          let st1b := { st1 with interner := iU32 }
          let (st2, tagVid) := emitValue st1b u32Tid (.variantTag pVid)
          let (st3, expVid) :=
            emitValue st2 u32Tid (.literal u32Tid (encodeU32le nIdx))
          let (iB, boolTid) := internShape st3.interner .bool
          let st3b := { st3 with interner := iB }
          let (st4, eqVid) :=
            emitValue st3b boolTid (.binary BinaryOpV1.eq tagVid expVid)
          let condIdx := st4.blocks.size
          let thenId := UInt32.ofNat (condIdx + 1)
          let st5 := sealCurrentBlock st4 (.branch eqVid
            { blockId := thenId, args := #[] }
            { blockId := 0, args := #[] })
          let (stN, failsN) ←
            lowerCtorArgGuardsCollectFailsV1 pVid nIdx nPayloads nestedArgs st5
          go (i + 1) stN (fails.push condIdx ++ failsN)

/-- One step along an assign place chain after the root name (N3). -/
private inductive PlaceStepV1 where
  | field (name : SourceNameComponentV1)
  | index (idx : SrcExpr)

/-- Peel `root.f[i].g` into `(root, #[.field f, .index i, .field g])`. -/
private partial def peelPlaceRootV1 (place : SrcPlace) :
    Except NormalizeErrorV1 (SourceNameComponentV1 × Array PlaceStepV1) :=
  match place with
  | .name n => pure (n, #[])
  | .field base fieldName => do
      let (root, steps) ← peelPlaceRootV1 base
      pure (root, steps.push (.field fieldName))
  | .index base idxExpr => do
      let (root, steps) ← peelPlaceRootV1 base
      pure (root, steps.push (.index idxExpr))

mutual

/-- Lower a place to a value: bare name (env / stateLoad / Op.Constant),
    fieldGet, indexGet. Each const read emits an independent `Op.Constant`. -/
private partial def lowerPlace
    (place : SrcPlace) (st : BodyStateV1) (states : StateTableV1)
    (fns : FnTableV1) :
    Except NormalizeErrorV1 (ValueIdV1 × TypeIdV1 × BodyStateV1) :=
  match place with
  | .name n =>
      let key := raw n
      match envLookup st.env key with
      | some (vid, tid) => pure (vid, tid, st)
      | none =>
          match stateLookup states key with
          | some (sid, tid) =>
              let (st1, vid) := emitValue st tid (.stateLoad sid)
              pure (vid, tid, st1)
          | none =>
              match constLookup st.constants key with
              | some (cid, tid) =>
                  -- result.typeId == ConstantV1.typeId (wire step-j contract).
                  let (st1, vid) := emitValue st tid (.constant cid)
                  pure (vid, tid, st1)
              | none =>
                  if key == "context" then
                    failUnsupported
                      "S1 context place must be context.unixTimeSeconds, context.caller or context.blockHeight (field chain)"
                  else
                    failUnsupported
                      s!"S1 bare place '{key}' is neither param, state, nor const"
  | .field base fieldName => do
      -- N5/N-2: ContextRead surfaces `context.unixTimeSeconds` (UInt64) and
      -- `context.caller` (Principal). PureFn fail closed.
      -- Match on base+field directly (same shape as ContextCommitSurface helpers).
      match base with
      | .name root =>
          if raw root == "context" && raw fieldName == "unixTimeSeconds" then
            unless st.allowContextCommit do
              return ← failUnsupported
                "S1 ContextRead is not admitted in pureFn (init/entry/view only)"
            let (iU64, u64Tid) := internShape st.interner (.uint 64)
            let st0 := { st with interner := iU64, usedContextUnixTime := true }
            let (st1, vid) :=
              emitValue st0 u64Tid (.contextRead unixTimeSecondsContextKeyV1)
            pure (vid, u64Tid, st1)
          else if raw root == "context" && raw fieldName == "caller" then
            unless st.allowContextCommit do
              return ← failUnsupported
                "S1 ContextRead is not admitted in pureFn (init/entry/view only)"
            let (iP, pTid) := internShape st.interner .principal
            let st0 := { st with interner := iP, usedContextCaller := true }
            let (st1, vid) :=
              emitValue st0 pTid (.contextRead callerContextKeyV1)
            pure (vid, pTid, st1)
          else if raw root == "context" && raw fieldName == "blockHeight" then
            unless st.allowContextCommit do
              return ← failUnsupported
                "S1 ContextRead is not admitted in pureFn (init/entry/view only)"
            let (iH, hTid) := internShape st.interner (.uint 64)
            let st0 := { st with interner := iH, usedContextBlockHeight := true }
            let (st1, vid) :=
              emitValue st0 hTid (.contextRead blockHeightContextKeyV1)
            pure (vid, hTid, st1)
          else if raw root == "context" then
            failUnsupported
              s!"S1 unsupported context field '{raw fieldName}' (admitted: unixTimeSeconds, caller, blockHeight)"
          else do
            let (baseVid, baseTid, st1) ← lowerPlace base st states fns
            match shapeOf? st1.interner.types baseTid with
            | some (.struct fields) =>
                match findStructFieldIndex fields (raw fieldName) with
                | none =>
                    failUnsupported
                      s!"S1 field '{raw fieldName}' not found on struct"
                | some (idx, fieldTid) =>
                    let (st2, vid) :=
                      emitValue st1 fieldTid
                        (.fieldGet baseVid (UInt32.ofNat idx))
                    pure (vid, fieldTid, st2)
            | _ =>
                failUnsupported "S1 field place requires a struct base"
      | _ => do
          let (baseVid, baseTid, st1) ← lowerPlace base st states fns
          match shapeOf? st1.interner.types baseTid with
          | some (.struct fields) =>
              match findStructFieldIndex fields (raw fieldName) with
              | none =>
                  failUnsupported
                    s!"S1 field '{raw fieldName}' not found on struct"
              | some (idx, fieldTid) =>
                  let (st2, vid) :=
                    emitValue st1 fieldTid
                      (.fieldGet baseVid (UInt32.ofNat idx))
                  pure (vid, fieldTid, st2)
          | _ =>
              failUnsupported "S1 field place requires a struct base"
  | .index base idxExpr => do
      let (baseVid, baseTid, st1) ← lowerPlace base st states fns
      match shapeOf? st1.interner.types baseTid with
      | some (.array elTid _) => do
          let (iU32, u32Tid) := internShape st1.interner (.uint 32)
          let st0 := { st1 with interner := iU32 }
          let (idxVid, idxTid, st2) ← lowerExpr idxExpr u32Tid st0 states fns
          unless idxTid == u32Tid do
            return ← failUnsupported "S1 Array index must be UInt32"
          let (st3, vid) := emitValue st2 elTid (.indexGet baseVid idxVid)
          pure (vid, elTid, st3)
      | some (.bytes _) => do
          let (iU32, u32Tid) := internShape st1.interner (.uint 32)
          let (iU8, u8Tid) := internShape iU32 (.uint 8)
          let st0 := { st1 with interner := iU8 }
          let (idxVid, idxTid, st2) ← lowerExpr idxExpr u32Tid st0 states fns
          unless idxTid == u32Tid do
            return ← failUnsupported "S1 Bytes index must be UInt32"
          let (st3, vid) := emitValue st2 u8Tid (.indexGet baseVid idxVid)
          pure (vid, u8Tid, st3)
      | some (.map keyTid valTid) => do
          let (iOpt, optTid) := internShape st1.interner (.option valTid)
          let st0 := { st1 with interner := iOpt }
          let (idxVid, idxTid, st2) ← lowerExpr idxExpr keyTid st0 states fns
          unless idxTid == keyTid do
            return ← failUnsupported "S1 Map index type mismatch"
          let (st3, vid) := emitValue st2 optTid (.indexGet baseVid idxVid)
          pure (vid, optTid, st3)
      | _ =>
          failUnsupported "S1 index place requires Array, Bytes, or Map base"

/-- N3: apply a nonempty field/index path as a functional update of `baseVid`. -/
private partial def applyNestedUpdateV1
    (baseVid : ValueIdV1) (baseTid : TypeIdV1)
    (steps : Array PlaceStepV1) (value : SrcExpr)
    (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (ValueIdV1 × BodyStateV1) := do
  if steps.isEmpty then
    return ← failUnsupported "S1 nested assign requires at least one field/index step"
  let some first := steps[0]? |
    return ← failUnsupported "S1 nested assign requires at least one field/index step"
  if steps.size == 1 then
    match first with
    | .field fieldName =>
        match shapeOf? st.interner.types baseTid with
        | some (.struct fields) =>
            match findStructFieldIndex fields (raw fieldName) with
            | none =>
                failUnsupported
                  s!"S1 field '{raw fieldName}' not found on struct"
            | some (idx, fieldTid) => do
                let (vVid, vTid, st1) ← lowerExpr value fieldTid st states fns
                unless vTid == fieldTid do
                  return ← failUnsupported "S1 field assign value type mismatch"
                let (st2, newVid) :=
                  emitValue st1 baseTid
                    (.fieldSet baseVid (UInt32.ofNat idx) vVid)
                pure (newVid, st2)
        | _ =>
            failUnsupported "S1 field assign requires a struct base"
    | .index idxExpr =>
        match shapeOf? st.interner.types baseTid with
        | some (.array elTid _) => do
            let (iU32, u32Tid) := internShape st.interner (.uint 32)
            let st0 := { st with interner := iU32 }
            let (idxVid, idxTid, st1) ←
              lowerExpr idxExpr u32Tid st0 states fns
            unless idxTid == u32Tid do
              return ← failUnsupported "S1 Array index must be UInt32"
            let (vVid, vTid, st2) ← lowerExpr value elTid st1 states fns
            unless vTid == elTid do
              return ← failUnsupported "S1 Array index-assign value type mismatch"
            let (st3, newVid) :=
              emitValue st2 baseTid (.indexSet baseVid idxVid vVid)
            pure (newVid, st3)
        | some (.bytes _) => do
            let (iU32, u32Tid) := internShape st.interner (.uint 32)
            let (iU8, u8Tid) := internShape iU32 (.uint 8)
            let st0 := { st with interner := iU8 }
            let (idxVid, idxTid, st1) ←
              lowerExpr idxExpr u32Tid st0 states fns
            unless idxTid == u32Tid do
              return ← failUnsupported "S1 Bytes index must be UInt32"
            let (vVid, vTid, st2) ← lowerExpr value u8Tid st1 states fns
            unless vTid == u8Tid do
              return ← failUnsupported "S1 Bytes index-assign value must be UInt8"
            let (st3, newVid) :=
              emitValue st2 baseTid (.indexSet baseVid idxVid vVid)
            pure (newVid, st3)
        | some (.map keyTid valTid) => do
            let (idxVid, idxTid, st1) ←
              lowerExpr idxExpr keyTid st states fns
            unless idxTid == keyTid do
              return ← failUnsupported "S1 Map index type mismatch"
            let (vVid, vTid, st2) ← lowerExpr value valTid st1 states fns
            unless vTid == valTid do
              return ← failUnsupported "S1 Map index-assign value type mismatch"
            let (st3, newVid) :=
              emitValue st2 baseTid (.indexSet baseVid idxVid vVid)
            pure (newVid, st3)
        | _ =>
            failUnsupported
              "S1 index assign requires Array, Bytes, or Map base"
  else
    let rest := steps.extract 1 steps.size
    match first with
    | .field fieldName =>
        match shapeOf? st.interner.types baseTid with
        | some (.struct fields) =>
            match findStructFieldIndex fields (raw fieldName) with
            | none =>
                failUnsupported
                  s!"S1 field '{raw fieldName}' not found on struct"
            | some (idx, fieldTid) => do
                let (st1, midVid) :=
                  emitValue st fieldTid
                    (.fieldGet baseVid (UInt32.ofNat idx))
                let (newMid, st2) ←
                  applyNestedUpdateV1 midVid fieldTid rest value st1 states fns
                let (st3, newBase) :=
                  emitValue st2 baseTid
                    (.fieldSet baseVid (UInt32.ofNat idx) newMid)
                pure (newBase, st3)
        | _ =>
            failUnsupported "S1 field place requires a struct base"
    | .index idxExpr =>
        match shapeOf? st.interner.types baseTid with
        | some (.array elTid _) => do
            let (iU32, u32Tid) := internShape st.interner (.uint 32)
            let st0 := { st with interner := iU32 }
            let (idxVid, idxTid, st1) ←
              lowerExpr idxExpr u32Tid st0 states fns
            unless idxTid == u32Tid do
              return ← failUnsupported "S1 Array index must be UInt32"
            let (st2, midVid) :=
              emitValue st1 elTid (.indexGet baseVid idxVid)
            let (newMid, st3) ←
              applyNestedUpdateV1 midVid elTid rest value st2 states fns
            let (st4, newBase) :=
              emitValue st3 baseTid (.indexSet baseVid idxVid newMid)
            pure (newBase, st4)
        | some (.bytes _) =>
            failUnsupported
              "S1 nested assign through Bytes element is not supported"
        | some (.map keyTid valTid) => do
            -- N-NEST-IDX: penetrating assign through a Map element
            -- (`m[k].x := v` / deeper). `IndexGet` yields `Option V`; unwrap
            -- via `VariantPayload (some)` — wire semantics trap `invalidCore`
            -- when the key is absent (standard revert, no silent insert of a
            -- fabricated value), then update the payload and `IndexSet` back.
            let (idxVid, idxTid, st1) ←
              lowerExpr idxExpr keyTid st states fns
            unless idxTid == keyTid do
              return ← failUnsupported "S1 Map index type mismatch"
            let (iOpt, optTid) := internShape st1.interner (.option valTid)
            let stOpt := { st1 with interner := iOpt }
            let (st2, optVid) :=
              emitValue stOpt optTid (.indexGet baseVid idxVid)
            let (st3, midVid) :=
              emitValue st2 valTid (.variantPayload optVid 1 (UInt32.ofNat 0))
            let (newMid, st4) ←
              applyNestedUpdateV1 midVid valTid rest value st3 states fns
            let (st5, newBase) :=
              emitValue st4 baseTid (.indexSet baseVid idxVid newMid)
            pure (newBase, st5)
        | _ =>
            failUnsupported "S1 index place requires Array, Bytes, or Map base"

private partial def lowerExpr
    (expr : SrcExpr) (expectedTid : TypeIdV1)
    (st : BodyStateV1) (states : StateTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (ValueIdV1 × TypeIdV1 × BodyStateV1) :=
  match expr with
  | .place p => do
      let (vid, tid, st1) ← lowerPlace p st states fns
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
        -- Same-width legal UInt/Int or sole catalog Field.
        -- UInt/Int: ReferenceMachineV1 overflow / intMin/-1 / div-zero.
        -- Field: exact mod-p add/sub/mul/div; `mod` fails closed (invalidCore).
        -- Bitwise stays integer-only (requireExpectedIntegerWidth).
        let isBitwise :=
          semanticOp == BinaryOpV1.bitAnd ||
          semanticOp == BinaryOpV1.bitOr ||
          semanticOp == BinaryOpV1.bitXor
        if isBitwise then
          requireExpectedIntegerWidth st.interner.types expectedTid
            "binary arithmetic/bitwise"
        else do
          requireExpectedIntegerOrFieldWidth st.interner.types expectedTid
            "binary arithmetic"
          if semanticOp == BinaryOpV1.mod &&
              isAnonCatalogField st.interner.types expectedTid then
            return ← failUnsupported
              "S1 Field does not support mod (remainder); use div"
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
          -- Shift lhs: legal UInt or Int width; count remains sole UInt32.
          -- Int `>>` is arithmetic (ReferenceMachineV1 `ediv` path).
          requireExpectedIntegerWidth st.interner.types expectedTid "shift"
          let (iU32, u32Tid) := internShape st.interner (.uint 32)
          let st0 := { st with interner := iU32 }
          let (lVid, lTid, st1) ← lowerExpr lhs expectedTid st0 states fns
          unless lTid == expectedTid do
            return ← failUnsupported "S1 shift requires a legal UInt/Int operand"
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
            -- Equality: same-type serializable operands (UInt/Int/Field/Principal/Bool…).
            -- Ordering: same-width legal UInt/Int only (Field/Principal ordering fail closed).
            -- Operand type is inferred from the lhs place (TypeCheck order).
            let (iBool, boolTid) := internShape st.interner .bool
            unless boolTid == expectedTid do
              return ← failUnsupported
                "S1 comparison requires an enclosing Bool expected type"
            let stB := { st with interner := iBool }
            let (iOp, opTid) ← synthComparisonOperandTypeV1 lhs rhs stB states
            let isEq :=
              semanticOp == BinaryOpV1.eq || semanticOp == BinaryOpV1.ne
            if isEq then
              -- Equality: admit integer, Field, Principal, or Bool.
              match anonShapeOf? iOp.types opTid with
              | some (.uint w) | some (.int w) =>
                  unless legalIntegerWidthV1 w.toNat do
                    return ← failUnsupported
                      "S1 equality requires legal UInt/Int/Field/Principal operands"
              | some (.field spec) =>
                  unless isCatalogFieldSpec spec do
                    return ← failUnsupported
                      "S1 equality requires a closed-catalog Field spec"
              | some .bool | some .principal | some .string => pure ()
              | _ =>
                  return ← failUnsupported
                    "S1 equality requires UInt/Int/Bool/Field/Principal/String operands"
            else
              -- Ordering: legal UInt/Int only (Field/Principal/String fail closed).
              match anonShapeOf? iOp.types opTid with
              | some .principal =>
                  return ← failUnsupported
                    "S1 Principal does not support ordering comparisons"
              | some .string =>
                  return ← failUnsupported
                    "S1 String does not support ordering comparisons"
              | _ => pure ()
              requireExpectedIntegerWidth iOp.types opTid "ordering comparison"
              if isAnonCatalogField iOp.types opTid then
                return ← failUnsupported
                  "S1 Field does not support ordering comparisons"
            let st0 := { stB with interner := iOp }
            let (lVid, lTid, st1) ← lowerExpr lhs opTid st0 states fns
            unless lTid == opTid do
              return ← failUnsupported
                "S1 comparison requires same-type operands"
            let (rVid, rTid, st2) ← lowerExpr rhs opTid st1 states fns
            unless rTid == opTid do
              return ← failUnsupported
                "S1 comparison requires same-type operands"
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
      | .string value => do
          let (i1, stringTid) := internShape st.interner .string
          unless stringTid == expectedTid do
            return ← failUnsupported
              "S1 String literal requires an enclosing String expected type"
          let st0 := { st with interner := i1 }
          let bytes ← match encodeString value with
            | .ok b => pure b
            | .error _ =>
                failUnsupported "S1 String literal is not NFC UTF-8 or exceeds wire string limit"
          unless bytes.size ≤ 4 + maxTypeLengthV1 do
            return ← failUnsupported
              s!"S1 String literal exceeds maxTypeLengthV1 ({maxTypeLengthV1}) UTF-8 bytes"
          -- encodeString already frames u32le||utf8; reject oversize body.
          let bodyLen := bytes.size - 4
          unless bodyLen ≤ maxTypeLengthV1 do
            return ← failUnsupported
              s!"S1 String literal exceeds maxTypeLengthV1 ({maxTypeLengthV1}) UTF-8 bytes"
          let (st1, vid) := emitValue st0 stringTid (.literal stringTid bytes)
          pure (vid, stringTid, st1)
  | .constructor ctor args => do
      let ctorComps := (NonEmptyArray.toArray ctor.components).map (·.raw)
      let ctorQn := sourceQualifiedNameStringV1 ctor
      -- ADR-0030 E2: env-read catalog QNs (pf.assets.*.balanceOfSelf) lower to
      -- Op.envRead. These are the first non-Unit catalog members
      -- (expression-position only, result UInt64, effect-free, view-callable).
      match pfAssetsEnvReadFamilyOfV1 ctorQn with
      | some family => do
          -- Result is always UInt64; the enclosing expected type must match.
          let (iU64, u64Tid) := internShape st.interner (.uint 64)
          let st0 := { st with interner := iU64 }
          unless u64Tid == expectedTid do
            return ← failUnsupported
              "S1 env-read catalog call result type must be UInt64"
          match family with
          | .nativeBalance => do
              unless args.isEmpty do
                return ← failUnsupported
                  "S1 pf.assets.native.balanceOfSelf takes no arguments"
              let (st1, vid) := emitValue st0 u64Tid
                (.envRead .nativeVaultBalance #[])
              pure (vid, u64Tid, st1)
          | .tokenBalance => do
              unless args.size == 1 do
                return ← failUnsupported
                  "S1 pf.assets.token.balanceOfSelf takes exactly one Principal argument"
              -- Lower the mint argument as a Principal (no expected-type
              -- inference; Principal enters via params/state/const only).
              let (iP, pTid) := internShape st0.interner .principal
              let st1 := { st0 with interner := iP }
              if h : args.size ≥ 1 then
                let mintArg := args[0]
                let (mintVid, mintTid, st2) ← lowerExpr mintArg pTid st1 states fns
                unless mintTid == pTid do
                  return ← failUnsupported
                    "S1 pf.assets.token.balanceOfSelf mint argument must be a Principal"
                let (st3, vid) := emitValue st2 u64Tid
                  (.envRead .tokenVaultBalance #[mintVid])
                pure (vid, u64Tid, st3)
              else
                failUnsupported
                  "S1 pf.assets.token.balanceOfSelf mint argument missing"
      | none =>
      if ctorComps == #["Map", "of"] then
        -- N-MAP-CONSTRUCT: variadic `Map.of(k0, v0, ...)` — flattened key/value
        -- pairs lowered in source order into one Construct. Reference
        -- semantics: empty map + sequential upsert (duplicate key last-wins).
        match shapeOf? st.interner.types expectedTid with
        | some (.map keyTid valTid) => do
            unless args.size % 2 == 0 do
              return ← failUnsupported
                "S1 Map.of requires an even number of key/value arguments"
            let mut argIds : Array ValueIdV1 := #[]
            let mut st' := st
            let mut i : Nat := 0
            for arg in args do
              let expectedArgTid := if i % 2 == 0 then keyTid else valTid
              let (aVid, aTid, st1) ← lowerExpr arg expectedArgTid st' states fns
              unless aTid == expectedArgTid do
                return ← failUnsupported
                  "S1 Map.of argument type mismatch"
              argIds := argIds.push aVid
              st' := st1
              i := i + 1
            let (st2, vid) :=
              emitValue st' expectedTid (.construct expectedTid 0 argIds)
            pure (vid, expectedTid, st2)
        | _ =>
            failUnsupported "S1 Map.of requires an enclosing Map expected type"
      else do
        let (resultTid, ctorIdx, argTids) ←
          resolveConstructorLoweringV1 st.interner ctor expectedTid
        unless resultTid == expectedTid do
          return ← failUnsupported
            "S1 constructor result type does not match enclosing expected type"
        unless args.size == argTids.size do
          return ← failUnsupported
            s!"S1 constructor expects {argTids.size} arguments, got {args.size}"
        let (argIds, st') ← lowerArgs args argTids st states fns
          "S1 constructor argument type mismatch"
        let (st2, vid) :=
          emitValue st' resultTid (.construct resultTid ctorIdx argIds)
        pure (vid, resultTid, st2)
  | .unary op operand => do
      match op with
      | .neg => do
          -- UInt: desugar to `0 - x` with a zero constant of the same width.
          -- Int: emit Op.Unary.neg (Reference reverts on intMin). Fold
          -- `unary neg (integer literal)` to two's-complement LE bytes so
          -- intMin is representable (positive Int literal max is 2^(w-1)-1).
          -- Field: emit Op.Unary.neg (Reference: (p - v) % p).
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
          | some (.int w) => do
              let width := w.toNat
              unless legalIntegerWidthV1 width do
                return ← failUnsupported
                  "S1 unary Int negation requires expected legal Int type"
              match operand with
              | .literal (.integer magnitude) => do
                  unless magnitude ≤ intNegatedInclusiveMax width do
                    return ← failUnsupported
                      s!"S1 Int{width} negated integer literal is out of range"
                  let bytes := encodeIntLeBytes (-Int.ofNat magnitude) width
                  let (st1, vid) :=
                    emitValue st expectedTid (.literal expectedTid bytes)
                  pure (vid, expectedTid, st1)
              | _ => do
                  let (oVid, oTid, st1) ←
                    lowerExpr operand expectedTid st states fns
                  unless oTid == expectedTid do
                    return ← failUnsupported
                      "S1 unary Int negation requires a legal Int operand"
                  let (st2, vid) :=
                    emitValue st1 expectedTid (.unary .neg oVid)
                  pure (vid, expectedTid, st2)
          | some (.field spec) => do
              unless isCatalogFieldSpec spec do
                return ← failUnsupported
                  "S1 unary Field negation requires a closed-catalog Field spec"
              let (oVid, oTid, st1) ←
                lowerExpr operand expectedTid st states fns
              unless oTid == expectedTid do
                return ← failUnsupported
                  "S1 unary Field negation requires a Field operand"
              let (st2, vid) :=
                emitValue st1 expectedTid (.unary .neg oVid)
              pure (vid, expectedTid, st2)
          | _ =>
              failUnsupported
                "S1 unary checked negation requires expected legal UInt/Int/Field type"
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
      -- N5: intrinsic `commit(x)` → Op.Commit (label-only identity).
      -- User `fn commit` still wins via the ordinary fnLookup path.
      if isCommitCalleeNameV1 callee && match fnLookup fns key with | none => true | some _ => false then
        unless st.allowContextCommit do
          return ← failUnsupported
            "S1 Commit is not admitted in pureFn (init/entry/view only)"
        unless args.size == 1 do
          return ← failUnsupported
            s!"S1 commit expects 1 argument, got {args.size}"
        match args[0]? with
        | none =>
            failUnsupported "S1 commit missing argument"
        | some arg0 => do
            let (aVid, aTid, st1) ← lowerExpr arg0 expectedTid st states fns
            unless aTid == expectedTid do
              return ← failUnsupported
                "S1 commit operand type does not match the enclosing expected type"
            let st1 := { st1 with usedCommit := true }
            let (st2, vid) := emitValue st1 expectedTid (.commit aVid)
            pure (vid, expectedTid, st2)
      else
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
  | .match_ scrutinee arms => do
      -- T4/T5 expression-level match: integer/Bool literal cases, Enum/Option
      -- constructor cases (VariantTag → switch UInt32), unique catch-all.
      -- Arm values lower in separate blocks and jump to a join block param.
      if arms.isEmpty then
        return ← failUnsupported "S1 match expression requires at least one arm"
      let (iB, boolTid) := internShape st.interner .bool
      let st0 := { st with interner := iB }
      let (scrutVid, scrutTid, st1) ←
        match scrutinee with
        | .literal (.bool _) =>
            lowerExpr scrutinee boolTid st0 states fns
        | .place p => do
            let (vid, tid, stP) ← lowerPlace p st0 states fns
            pure (vid, tid, stP)
        | .unary .not _ =>
            lowerExpr scrutinee boolTid st0 states fns
        | .binary op _ _ => do
            let srcOp := op
            if srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.eq ||
                srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ne ||
                srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.lt ||
                srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.le ||
                srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.gt ||
                srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.ge ||
                srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalAnd ||
                srcOp == ProofForgeV2.Source.AstV1.BinaryOpV1.logicalOr then
              lowerExpr scrutinee boolTid st0 states fns
            else
              let (iU, u64Tid) := internShape st0.interner (.uint 64)
              let stU := { st0 with interner := iU }
              lowerExpr scrutinee u64Tid stU states fns
        | _ => do
            let (iU, u64Tid) := internShape st0.interner (.uint 64)
            let stU := { st0 with interner := iU }
            lowerExpr scrutinee u64Tid stU states fns
      let scrutIsBool :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some .bool => true
        | _ => false
      let scrutIsString :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some .string => true
        | _ => false
      let scrutUintWidth? : Option Nat :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some (.uint w) =>
            if legalIntegerWidthV1 w.toNat then some w.toNat else none
        | _ => none
      let scrutIsCtor := isCtorMatchScrutineeV1 st1.interner.types scrutTid
      -- Partition arms: literal cases (valueBytes) | constructor cases | one catch-all.
      let mut litArms : Array (ByteArray × SrcExpr) := #[]
      let mut ctorArms : Array (UInt32 × Array TypeIdV1 × Array SrcPattern × SrcExpr) := #[]
      let mut defaultArm? : Option (Option SourceNameComponentV1 × SrcExpr) := none
      for arm in arms do
        match arm.pattern with
        | .literal lit => do
            let bytes ← encodeLiteralValueBytesV1 st1.interner.types scrutTid lit
            if litArms.any (fun (b, _) => b == bytes) then
              return ← failUnsupported
                "S1 match expression has duplicate literal cases"
            match lit with
            | .integer _ =>
                unless scrutUintWidth?.isSome do
                  return ← failUnsupported
                    "S1 match expression integer pattern requires a legal UInt scrutinee"
            | .bool _ =>
                unless scrutIsBool do
                  return ← failUnsupported
                    "S1 match expression Bool pattern requires a Bool scrutinee"
            | .string _ =>
                unless scrutIsString do
                  return ← failUnsupported
                    "S1 match expression String pattern requires a String scrutinee"
            litArms := litArms.push (bytes, arm.value)
        | .wildcard =>
            if defaultArm?.isSome then
              return ← failUnsupported
                "S1 match expression has more than one catch-all arm"
            defaultArm? := some (none, arm.value)
        | .bind name =>
            if defaultArm?.isSome then
              return ← failUnsupported
                "S1 match expression has more than one catch-all arm"
            defaultArm? := some (some name, arm.value)
        | .constructor ctor args => do
            unless scrutIsCtor do
              return ← failUnsupported
                "S1 match expression constructor pattern requires Enum or Option scrutinee"
            let (vIdx, payloads) ←
              resolveCtorPatternV1 st1.interner ctor scrutTid
            -- Multi-arm same outer ctor is legal when sub-patterns differ;
            -- reject only structural pattern-key duplicates (bind≡wildcard).
            let shape ← ctorArmShapeKeyV1 st1.interner vIdx payloads args
            let mut priorKeys : Array PatternShapeKeyV1 := #[]
            for (pv, pp, pa, _) in ctorArms do
              let pk ← ctorArmShapeKeyV1 st1.interner pv pp pa
              priorKeys := priorKeys.push pk
            if ctorArmShapeIsDuplicateV1 shape priorKeys then
              return ← failUnsupported
                "S1 match expression has duplicate constructor cases"
            ctorArms := ctorArms.push (vIdx, payloads, args, arm.value)
      if !litArms.isEmpty && !ctorArms.isEmpty then
        return ← failUnsupported
          "S1 match expression cannot mix literal and constructor patterns"
      -- Catch-all-only: inline (structure gate forbids empty switch cases).
      if litArms.isEmpty && ctorArms.isEmpty then
        let (defaultBinder?, defaultValue) ← match defaultArm? with
          | some da => pure da
          | none =>
              return ← failUnsupported
                "S1 match expression requires at least one case or a catch-all arm"
        let stD := match defaultBinder? with
          | none => st1
          | some name =>
              { st1 with env := envInsert st1.env (raw name) scrutVid scrutTid }
        let (vid, vtid, stR) ← lowerExpr defaultValue expectedTid stD states fns
        unless vtid == expectedTid do
          return ← failUnsupported
            "S1 match expression arm type does not match expected type"
        pure (vid, expectedTid, { stR with env := st1.env })
      else if !litArms.isEmpty then
        unless scrutIsBool || scrutIsString || scrutUintWidth?.isSome do
          return ← failUnsupported
            "S1 match expression literal patterns require legal UInt, Bool, or String scrutinee"
        let (defaultBinder?, defaultValue) ← match defaultArm? with
          | some da => pure da
          | none =>
              return ← failUnsupported
                "S1 match expression on UInt/Bool/String requires a catch-all arm"
        let scrutIdx := st1.blocks.size
        let st2 := sealCurrentBlock st1 (.switch scrutVid #[] none)
        let savedEnv := st1.env
        let mut stA := st2
        let mut caseTargets : Array BlockIdV1 := #[]
        let mut jumpSlots : Array Nat := #[]
        for (_, armValue) in litArms do
          caseTargets := caseTargets.push (UInt32.ofNat stA.blocks.size)
          let (vid, vtid, stB) ←
            lowerExpr armValue expectedTid { stA with env := savedEnv } states fns
          unless vtid == expectedTid do
            return ← failUnsupported
              "S1 match expression arm type does not match expected type"
          jumpSlots := jumpSlots.push stB.blocks.size
          stA := sealCurrentBlock stB (.jump { blockId := 0, args := #[vid] })
        let defaultId := UInt32.ofNat stA.blocks.size
        let stD0 := match defaultBinder? with
          | none => { stA with env := savedEnv }
          | some name =>
              { stA with env := envInsert savedEnv (raw name) scrutVid scrutTid }
        let (dVid, dTid, stD) ← lowerExpr defaultValue expectedTid stD0 states fns
        unless dTid == expectedTid do
          return ← failUnsupported
            "S1 match expression arm type does not match expected type"
        jumpSlots := jumpSlots.push stD.blocks.size
        stA := sealCurrentBlock stD (.jump { blockId := 0, args := #[dVid] })
        let switchCases : Array SwitchCaseV1 :=
          litArms.mapIdx fun i (valueBytes, _) =>
            {
              typeId := scrutTid
              valueBytes := valueBytes
              target := { blockId := caseTargets[i]!, args := #[] }
            }
        let joinId := UInt32.ofNat stA.blocks.size
        let stP := patchSwitch stA scrutIdx switchCases (some {
          blockId := defaultId, args := #[] })
        let stP := jumpSlots.foldl (fun acc j => patchJumpTarget acc j joinId) stP
        let joinVid :=
          UInt32.ofNat (stP.callableParamCount + stP.nextBlockParamOrdinal)
        let stJoin := {
          stP with
          nextBlockParamOrdinal := stP.nextBlockParamOrdinal + 1
          currentParams := #[{ valueId := joinVid, typeId := expectedTid }]
          env := savedEnv
        }
        pure (joinVid, expectedTid, stJoin)
      else
        -- Constructor path: VariantTag → switch on unique outer variant index.
        -- Multi-arm same outer: first-match sequential nested guards inside
        -- the single switch case (switch case-value uniqueness forbids
        -- duplicate outer tags).
        let (iU32, u32Tid) := internShape st1.interner (.uint 32)
        let stTag0 := { st1 with interner := iU32 }
        let (stTag, tagVid) := emitValue stTag0 u32Tid (.variantTag scrutVid)
        let scrutIdx := stTag.blocks.size
        let st2 := sealCurrentBlock stTag (.switch tagVid #[] none)
        let savedEnv := st1.env
        let groups := groupCtorArmsByVariantV1 ctorArms
        let mut stA := st2
        let mut caseTargets : Array BlockIdV1 := #[]
        let mut jumpSlots : Array Nat := #[]
        let mut groupFallthroughFails : Array Nat := #[]
        for (vIdx, group) in groups do
          caseTargets := caseTargets.push (UInt32.ofNat stA.blocks.size)
          match group.toList with
          | [(payloads, argPats, armValue)] => do
              let stBound ← bindCtorArgPatternsV1 scrutVid vIdx payloads argPats
                { stA with env := savedEnv }
              let (vid, vtid, stB) ←
                lowerExpr armValue expectedTid stBound states fns
              unless vtid == expectedTid do
                return ← failUnsupported
                  "S1 match expression arm type does not match expected type"
              jumpSlots := jumpSlots.push stB.blocks.size
              stA := sealCurrentBlock stB (.jump { blockId := 0, args := #[vid] })
          | [] =>
              return ← failUnsupported
                "S1 match expression constructor group must be nonempty"
          | _ => do
            -- Multi-arm same outer: sequential first-match guards.
            let mut gi : Nat := 0
            for (payloads, argPats, armValue) in group do
              let (stG, failSites) ←
                lowerCtorArgGuardsCollectFailsV1 scrutVid vIdx payloads argPats
                  { stA with env := savedEnv }
              let (vid, vtid, stB) ←
                lowerExpr armValue expectedTid stG states fns
              unless vtid == expectedTid do
                return ← failUnsupported
                  "S1 match expression arm type does not match expected type"
              jumpSlots := jumpSlots.push stB.blocks.size
              stA := sealCurrentBlock stB (.jump { blockId := 0, args := #[vid] })
              let nextId := UInt32.ofNat stA.blocks.size
              if gi + 1 < group.size then
                for p in failSites do
                  stA := patchBranchElse stA p nextId
              else
                groupFallthroughFails := groupFallthroughFails ++ failSites
              gi := gi + 1
        let defaultTarget? : Option JumpTargetV1 ← match defaultArm? with
          | none =>
              if groupFallthroughFails.isEmpty then
                pure none
              else do
                -- Nested refinement may miss; seal trap as fallthrough.
                let trapId := UInt32.ofNat stA.blocks.size
                stA := sealCurrentBlock stA
                  (.trap SemanticTrapCodeV1.unreachable)
                for p in groupFallthroughFails do
                  stA := patchBranchElse stA p trapId
                pure none
          | some (defaultBinder?, defaultValue) => do
              let defaultId := UInt32.ofNat stA.blocks.size
              for p in groupFallthroughFails do
                stA := patchBranchElse stA p defaultId
              let stD0 := match defaultBinder? with
                | none => { stA with env := savedEnv }
                | some name =>
                    { stA with env := envInsert savedEnv (raw name) scrutVid scrutTid }
              let (dVid, dTid, stD) ←
                lowerExpr defaultValue expectedTid stD0 states fns
              unless dTid == expectedTid do
                return ← failUnsupported
                  "S1 match expression arm type does not match expected type"
              jumpSlots := jumpSlots.push stD.blocks.size
              stA := sealCurrentBlock stD (.jump { blockId := 0, args := #[dVid] })
              pure (some { blockId := defaultId, args := #[] })
        let switchCases : Array SwitchCaseV1 :=
          groups.mapIdx fun i (vIdx, _) =>
            {
              typeId := u32Tid
              valueBytes := encodeU32le vIdx
              target := { blockId := caseTargets[i]!, args := #[] }
            }
        let joinId := UInt32.ofNat stA.blocks.size
        let stP := patchSwitch stA scrutIdx switchCases defaultTarget?
        let stP := jumpSlots.foldl (fun acc j => patchJumpTarget acc j joinId) stP
        let joinVid :=
          UInt32.ofNat (stP.callableParamCount + stP.nextBlockParamOrdinal)
        let stJoin := {
          stP with
          nextBlockParamOrdinal := stP.nextBlockParamOrdinal + 1
          currentParams := #[{ valueId := joinVid, typeId := expectedTid }]
          env := savedEnv
        }
        pure (joinVid, expectedTid, stJoin)
    | .externalCall call => do
        -- N-CALL-RET: value-position sync call → result-bearing
        -- Op.ExternalCall. Callee/args share the statement discipline
        -- (anonymous integer args; bare integer literals default UInt64); the
        -- result type is the enclosing expected type and must be a
        -- serializable scalar.
        let calleeComponents := (NonEmptyArray.toArray call.callee.components).map (·.raw)
        unless calleeComponents.size ≥ 2 do
          return ← failUnsupported
            "S1 call callee must have at least two components"
        let qn ← match parseQualifiedName calleeComponents with
          | .ok qn => pure qn
          | .error e => failUnsupported s!"S1 call callee: {e}"
        let resultLegal :=
          match shapeOf? st.interner.types expectedTid with
          | some .bool => true
          | some (.uint w) | some (.int w) =>
              w == 8 || w == 16 || w == 32 || w == 64 || w == 128 || w == 256
          | some (.bytes n) => n.toNat ≤ maxTypeLengthV1
          | _ => false
        unless resultLegal do
          return ← failUnsupported
            "S1 call result type must be Bool, a legal UInt/Int width, or Bytes"
        let mut st' := st
        let mut argIds : Array ValueIdV1 := #[]
        for arg in call.args do
          let (i1, expectedArgTid) ← match arg with
            | .place p => synthPlaceTypeV1 p st'.interner st'.env states st'.constants
            | .literal (.integer _) => pure (internShape st'.interner (.uint 64))
            | _ =>
                match synthLetExpectedV1 arg st' states fns with
                | .ok pair => pure pair
                | .error _ => pure (internShape st'.interner (.uint 64))
          requireAnonymousIntegerTypeId i1.types expectedArgTid
            "call argument"
          let st0 := { st' with interner := i1 }
          let (vid, argTid, st1) ← lowerExpr arg expectedArgTid st0 states fns
          unless argTid == expectedArgTid do
            return ← failUnsupported "S1 call argument type mismatch"
          argIds := argIds.push vid
          st' := st1
        let (st1, vid) := emitValue st' expectedTid (.externalCall st'.nextEffectId qn argIds)
        pure (vid, expectedTid, { st1 with nextEffectId := st1.nextEffectId + 1 })

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
    callee (≥2 components), legal UInt/Int **or Principal** args (per-arg type
    from place, UInt64 default for bare integer literals, Principal from place
    synth only — no Principal literal), void op with the shared EffectId
    sequence. String/Field/aggregates stay fail closed. Target QN / account
    binding is not consulted. The only difference between the two is the op
    ctor. -/
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
  let mut st' := st
  let mut argIds : Array ValueIdV1 := #[]
  for arg in externalCall.args do
    let (i1, expectedTid) ← match arg with
      | .place p => synthPlaceTypeV1 p st'.interner st'.env states st'.constants
      | .literal (.integer _) => pure (internShape st'.interner (.uint 64))
      | _ =>
          -- Fall back to place/synth path; reject non-integer/non-Principal
          -- shapes below.
          match synthLetExpectedV1 arg st' states fns with
          | .ok pair => pure pair
          | .error _ => pure (internShape st'.interner (.uint 64))
    requireAnonymousIntegerOrPrincipalTypeId i1.types expectedTid
      s!"{label} argument"
    let st0 := { st' with interner := i1 }
    let (vid, argTid, st1) ← lowerExpr arg expectedTid st0 states fns
    unless argTid == expectedTid do
      return ← failUnsupported s!"S1 {label} argument type mismatch"
    argIds := argIds.push vid
    st' := st1
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
      -- N3/N-6: peel any field/index chain.
      -- Bare env name: let/for-binder rebind (fresh SSA ValueId); params
      -- immutable fail closed. Nested path: FieldSet/IndexSet then env rebind
      -- (local) or StateStore (state). Param roots fail closed even nested.
      let (rootName, steps) ← peelPlaceRootV1 target
      let key := raw rootName
      let isParam := st.paramNames.any (· == key)
      match envLookup st.env key with
      | some (rootVid, rootTid) =>
          if isParam then
            return (← failUnsupported
              s!"S1 assign target cannot reassign parameter '{key}'")
          else if steps.isEmpty then
            -- N-6: true mutable let/for-binder local.
            let (vid, tid, st1) ← lowerExpr value rootTid st states fns
            unless tid == rootTid do
              return ← failUnsupported
                s!"S1 assign type mismatch for local '{key}'"
            pure ({ st1 with
              env := envRebind st1.env key vid rootTid }, .open_)
          else do
            let (newRoot, st1) ←
              applyNestedUpdateV1 rootVid rootTid steps value st states fns
            pure ({ st1 with
              env := envRebind st1.env key newRoot rootTid }, .open_)
      | none =>
          match stateLookup states key with
          | none =>
              return (← failUnsupported
                s!"S1 assign target '{key}' must be a state place or local")
          | some (sid, rootTid) =>
              if steps.isEmpty then
                let (vid, tid, st1) ←
                  lowerExpr value rootTid st states fns
                unless tid == rootTid do
                  return ← failUnsupported
                    s!"S1 assign type mismatch for state '{key}'"
                pure (emitVoid st1 (.stateStore sid vid), .open_)
              else do
                let (st0, rootVid) :=
                  emitValue st rootTid (.stateLoad sid)
                let (newRoot, st1) ←
                  applyNestedUpdateV1 rootVid rootTid steps value st0 states fns
                pure (emitVoid st1 (.stateStore sid newRoot), .open_)
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
      let (i1, boolTid) := internShape st.interner .bool
      let st0 := { st with interner := i1 }
      let (condVid, condTid, st1) ← lowerExpr condition boolTid st0 states fns
      unless condTid == boolTid do
        return ← failUnsupported "S1 assert condition must be Bool"
      match errorRef with
      | none => pure (emitVoid st1 (.assert_ condVid none #[]), .open_)
      | some errorName => do
          let key := raw errorName
          match errorLookup errors key with
          | none =>
              failUnsupported s!"S1 assert-else error '{key}' is not declared"
          | some (errorId, fieldTids) => do
              -- Source `assert Expr else Ident` carries no args, so the
              -- referenced error must be zero-argument; parameterized errors
              -- fail closed (mirrors the revert arity gate).
              unless fieldTids.isEmpty do
                return ← failUnsupported
                  s!"S1 assert-else error '{key}' expects {fieldTids.size} arguments, but the source assert carries none"
              pure (emitVoid st1 (.assert_ condVid (some errorId) #[]), .open_)
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
      -- Scrutinee: Bool/String literal, bare place (UInt/Bool/String/Enum/Option),
      -- or UInt64 fallback for non-place heads (legacy UInt match programs).
      let (scrutVid, scrutTid, st1) ←
        match scrutinee with
        | .literal (.bool _) =>
            lowerExpr scrutinee boolTid st0 states fns
        | .literal (.string _) => do
            let (iS, stringTid) := internShape st0.interner .string
            let stS := { st0 with interner := iS }
            lowerExpr scrutinee stringTid stS states fns
        | .place p => do
            let (vid, tid, stP) ← lowerPlace p st0 states fns
            pure (vid, tid, stP)
        | _ => do
            let (iU, u64Tid) := internShape st0.interner (.uint 64)
            let stU := { st0 with interner := iU }
            lowerExpr scrutinee u64Tid stU states fns
      let scrutIsBool :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some .bool => true
        | _ => false
      let scrutIsString :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some .string => true
        | _ => false
      let scrutUintWidth? : Option Nat :=
        match anonShapeOf? st1.interner.types scrutTid with
        | some (.uint w) =>
            if legalIntegerWidthV1 w.toNat then some w.toNat else none
        | _ => none
      let scrutIsCtor := isCtorMatchScrutineeV1 st1.interner.types scrutTid
      let mut litArms : Array (ByteArray × SrcBlock) := #[]
      let mut ctorArms :
          Array (UInt32 × Array TypeIdV1 × Array SrcPattern × SrcBlock) := #[]
      let mut defaultArm? : Option (Option SourceNameComponentV1 × SrcBlock) := none
      for arm in arms do
        match arm.pattern with
        | .literal lit => do
            let bytes ← encodeLiteralValueBytesV1 st1.interner.types scrutTid lit
            if litArms.any (fun (b, _) => b == bytes) then
              return ← failUnsupported "S1 match has duplicate literal cases"
            match lit with
            | .integer _ =>
                unless scrutUintWidth?.isSome do
                  return ← failUnsupported
                    "S1 match integer literal requires a legal UInt scrutinee"
            | .bool _ =>
                unless scrutIsBool do
                  return ← failUnsupported
                    "S1 match Bool literal requires a Bool scrutinee"
            | .string _ =>
                unless scrutIsString do
                  return ← failUnsupported
                    "S1 match String literal requires a String scrutinee"
            litArms := litArms.push (bytes, arm.body)
        | .wildcard =>
            if defaultArm?.isSome then
              return ← failUnsupported "S1 match has more than one catch-all arm"
            defaultArm? := some (none, arm.body)
        | .bind name =>
            if defaultArm?.isSome then
              return ← failUnsupported "S1 match has more than one catch-all arm"
            defaultArm? := some (some name, arm.body)
        | .constructor ctor args => do
            unless scrutIsCtor do
              return ← failUnsupported
                "S1 match constructor pattern requires Enum or Option scrutinee"
            let (vIdx, payloads) ←
              resolveCtorPatternV1 st1.interner ctor scrutTid
            -- Multi-arm same outer ctor is legal when sub-patterns differ;
            -- reject only structural pattern-key duplicates (bind≡wildcard).
            let shape ← ctorArmShapeKeyV1 st1.interner vIdx payloads args
            let mut priorKeys : Array PatternShapeKeyV1 := #[]
            for (pv, pp, pa, _) in ctorArms do
              let pk ← ctorArmShapeKeyV1 st1.interner pv pp pa
              priorKeys := priorKeys.push pk
            if ctorArmShapeIsDuplicateV1 shape priorKeys then
              return ← failUnsupported "S1 match has duplicate constructor cases"
            ctorArms := ctorArms.push (vIdx, payloads, args, arm.body)
      if !litArms.isEmpty && !ctorArms.isEmpty then
        return ← failUnsupported
          "S1 match cannot mix literal and constructor patterns"
      -- Catch-all-only: inline binder + body (no switch; empty cases illegal).
      if litArms.isEmpty && ctorArms.isEmpty then
        let (defaultBinder?, defaultBody) ← match defaultArm? with
          | some da => pure da
          | none =>
              return ← failUnsupported
                "S1 match requires at least one case or a catch-all arm"
        let stD := match defaultBinder? with
          | none => st1
          | some name => { st1 with env := envInsert st1.env (raw name) scrutVid scrutTid }
        let (stR, rStatus) ← lowerStmts defaultBody.statements resultTid stD
          states events errors fns
        pure ({ stR with env := st1.env }, rStatus)
      else if !litArms.isEmpty then
        unless scrutIsBool || scrutIsString || scrutUintWidth?.isSome do
          return ← failUnsupported
            "S1 match literal patterns require legal UInt, Bool, or String scrutinee"
        let (defaultBinder?, defaultBody) ← match defaultArm? with
          | some da => pure da
          | none =>
              return ← failUnsupported
                "S1 match on UInt/Bool/String requires a catch-all arm"
        let scrutIdx := st1.blocks.size
        let st2 := sealCurrentBlock st1 (.switch scrutVid #[] none)
        let savedEnv := st1.env
        let mut stA := st2
        let mut caseTargets : Array BlockIdV1 := #[]
        let mut jumpSlots : Array Nat := #[]
        let mut closedCount : Nat := 0
        for (_, body) in litArms do
          caseTargets := caseTargets.push (UInt32.ofNat stA.blocks.size)
          let (stB, status) ← lowerStmts body.statements resultTid
            { stA with env := savedEnv } states events errors fns
          stA := stB
          match status with
          | .closed => closedCount := closedCount + 1
          | .open_ =>
              jumpSlots := jumpSlots.push stA.blocks.size
              stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
        let defaultId := UInt32.ofNat stA.blocks.size
        let stD := match defaultBinder? with
          | none => { stA with env := savedEnv }
          | some name => { stA with env := envInsert savedEnv (raw name) scrutVid scrutTid }
        let (stD, dStatus) ← lowerStmts defaultBody.statements resultTid stD
          states events errors fns
        stA := stD
        match dStatus with
        | .closed => closedCount := closedCount + 1
        | .open_ =>
            jumpSlots := jumpSlots.push stA.blocks.size
            stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
        let switchCases : Array SwitchCaseV1 := litArms.mapIdx fun i (valueBytes, _) =>
          {
            typeId := scrutTid
            valueBytes := valueBytes
            target := { blockId := caseTargets[i]!, args := #[] }
          }
        if closedCount == litArms.size + 1 then
          let stP := patchSwitch stA scrutIdx switchCases (some {
            blockId := defaultId, args := #[] })
          pure (stP, .closed)
        else
          let joinId := UInt32.ofNat stA.blocks.size
          let stP := patchSwitch stA scrutIdx switchCases (some {
            blockId := defaultId, args := #[] })
          let stP := jumpSlots.foldl (fun acc j => patchJumpTarget acc j joinId) stP
          pure ({ stP with env := savedEnv }, .open_)
      else
        -- Constructor path: Op.VariantTag → switch on unique outer tag;
        -- multi-arm same outer uses sequential nested guards (N-A2).
        let (iU32, u32Tid) := internShape st1.interner (.uint 32)
        let stTag0 := { st1 with interner := iU32 }
        let (stTag, tagVid) := emitValue stTag0 u32Tid (.variantTag scrutVid)
        let scrutIdx := stTag.blocks.size
        let st2 := sealCurrentBlock stTag (.switch tagVid #[] none)
        let savedEnv := st1.env
        let groups := groupCtorArmsByVariantV1 ctorArms
        let mut stA := st2
        let mut caseTargets : Array BlockIdV1 := #[]
        let mut jumpSlots : Array Nat := #[]
        let mut closedCount : Nat := 0
        let mut groupFallthroughFails : Array Nat := #[]
        let mut terminalClosedExtra : Nat := 0
        for (vIdx, group) in groups do
          caseTargets := caseTargets.push (UInt32.ofNat stA.blocks.size)
          match group.toList with
          | [(payloads, argPats, body)] => do
              let stBound ← bindCtorArgPatternsV1 scrutVid vIdx payloads argPats
                { stA with env := savedEnv }
              let (stB, status) ← lowerStmts body.statements resultTid stBound
                states events errors fns
              stA := stB
              match status with
              | .closed => closedCount := closedCount + 1
              | .open_ =>
                  jumpSlots := jumpSlots.push stA.blocks.size
                  stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
          | [] =>
              return ← failUnsupported
                "S1 match constructor group must be nonempty"
          | _ => do
            let mut gi : Nat := 0
            for (payloads, argPats, body) in group do
              let (stG, failSites) ←
                lowerCtorArgGuardsCollectFailsV1 scrutVid vIdx payloads argPats
                  { stA with env := savedEnv }
              let (stB, status) ← lowerStmts body.statements resultTid stG
                states events errors fns
              stA := stB
              match status with
              | .closed => closedCount := closedCount + 1
              | .open_ =>
                  jumpSlots := jumpSlots.push stA.blocks.size
                  stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
              let nextId := UInt32.ofNat stA.blocks.size
              if gi + 1 < group.size then
                for p in failSites do
                  stA := patchBranchElse stA p nextId
              else
                groupFallthroughFails := groupFallthroughFails ++ failSites
              gi := gi + 1
        let defaultTarget? : Option JumpTargetV1 ← match defaultArm? with
          | none =>
              if groupFallthroughFails.isEmpty then
                pure none
              else do
                let trapId := UInt32.ofNat stA.blocks.size
                stA := sealCurrentBlock stA
                  (.trap SemanticTrapCodeV1.unreachable)
                for p in groupFallthroughFails do
                  stA := patchBranchElse stA p trapId
                terminalClosedExtra := terminalClosedExtra + 1
                pure none
          | some (defaultBinder?, defaultBody) => do
              let defaultId := UInt32.ofNat stA.blocks.size
              for p in groupFallthroughFails do
                stA := patchBranchElse stA p defaultId
              let stD0 := match defaultBinder? with
                | none => { stA with env := savedEnv }
                | some name =>
                    { stA with env := envInsert savedEnv (raw name) scrutVid scrutTid }
              let (stD, dStatus) ← lowerStmts defaultBody.statements resultTid stD0
                states events errors fns
              stA := stD
              match dStatus with
              | .closed => closedCount := closedCount + 1
              | .open_ =>
                  jumpSlots := jumpSlots.push stA.blocks.size
                  stA := sealCurrentBlock stA (.jump { blockId := 0, args := #[] })
              pure (some { blockId := defaultId, args := #[] })
        let switchCases : Array SwitchCaseV1 :=
          groups.mapIdx fun i (vIdx, _) =>
            {
              typeId := u32Tid
              valueBytes := encodeU32le vIdx
              target := { blockId := caseTargets[i]!, args := #[] }
            }
        -- Count terminal paths: each multi-arm body + default/trap.
        let bodyArmCount :=
          groups.foldl (fun acc (_, g) => acc + g.size) 0
        let armTotal :=
          bodyArmCount + (if defaultTarget?.isSome then 1 else 0) +
            terminalClosedExtra
        if closedCount + terminalClosedExtra == armTotal && jumpSlots.isEmpty then
          let stP := patchSwitch stA scrutIdx switchCases defaultTarget?
          pure (stP, .closed)
        else
          let joinId := UInt32.ofNat stA.blocks.size
          let stP := patchSwitch stA scrutIdx switchCases defaultTarget?
          let stP := jumpSlots.foldl (fun acc j => patchJumpTarget acc j joinId) stP
          pure ({ stP with env := savedEnv }, .open_)
  | .let_ name typeAnn value => do
      -- SSA binding: RHS evaluates once; name is scoped to the enclosing block
      -- (branch/loop bodies save and restore the env). N-6: bare reassignment
      -- rebinds the name to a fresh ValueId (same TypeId) without mutating
      -- earlier uses. Parameters are tracked separately and stay immutable.
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
      -- N-FOR-INT: for endpoints are same-width legal UInt or Int. The CFG
      -- contract is target-neutral: signedness is carried by the TypeId, the
      -- header uses typed `<`, and the latch uses typed `+ 1`.
      -- Prefer start place width; when start is a bare integer literal (or other
      -- non-place) and endExclusive is env/state/const place, use end's exact
      -- integer width so `for i in 0 .. LIMIT` does not default to UInt64.
      -- TypeCheck must already accept the program (literal start without an
      -- expected type is rejected today; this fallback keeps future parity).
      let (iStart, startTid) ← match start with
        | .place p =>
            synthPlaceTypeV1 p st.interner st.env states st.constants
        | _ => do
            match ← trySynthPlaceExprTypeV1 endExclusive st states with
            | some pair => pure pair
            | none => pure (internShape st.interner (.uint 64))
      requireAnonymousIntegerTypeId iStart.types startTid "for start"
      let (iB, boolTid) := internShape iStart .bool
      let st0 := { st with interner := iB }
      let (sVid, sTid, st1) ← lowerExpr start startTid st0 states fns
      unless sTid == startTid do
        return ← failUnsupported "S1 for start type mismatch"
      let (eVid, eTid, st2) ← lowerExpr endExclusive startTid st1 states fns
      unless eTid == startTid do
        return ← failUnsupported "S1 for end must match start integer type"
      unless bound ≤ maxWireLoopBoundV1 do
        return ← failUnsupported "S1 for bound exceeds the wire loop maximum"
      let inductionTid := startTid
      -- N-6: outer lets reassigned in the body are loop-carried header params.
      let savedEnv := st2.env
      let liveNames := savedEnv.bindings.foldl
        (fun acc (n, _, _) => uniquePushString acc n) #[]
      let bname := raw binder
      let carriedNames :=
        loopCarriedNamesV1 body liveNames bname st2.paramNames
      -- Resolve initial carried ValueIds/TypeIds from the pre-loop env.
      let mut carriedInit : Array (String × ValueIdV1 × TypeIdV1) := #[]
      for cn in carriedNames do
        match envLookup savedEnv cn with
        | none =>
            return ← failUnsupported
              s!"S1 loop-carried local '{cn}' is not in scope"
        | some (vid, tid) =>
            carriedInit := carriedInit.push (cn, vid, tid)
      -- Pre-header: jump to header with induction start + carried initials.
      let headerIdx := st2.blocks.size + 1
      let headerId := UInt32.ofNat headerIdx
      let iVid := UInt32.ofNat (st2.callableParamCount + st2.nextBlockParamOrdinal)
      let mut ord := st2.nextBlockParamOrdinal + 1
      let mut headerParams : Array BlockParameterV1 :=
        #[{ valueId := iVid, typeId := inductionTid }]
      let mut carriedHeader : Array (String × ValueIdV1 × TypeIdV1) := #[]
      let mut preArgs : Array ValueIdV1 := #[sVid]
      for (cn, initVid, tid) in carriedInit do
        let cVid := UInt32.ofNat (st2.callableParamCount + ord)
        ord := ord + 1
        headerParams := headerParams.push { valueId := cVid, typeId := tid }
        carriedHeader := carriedHeader.push (cn, cVid, tid)
        preArgs := preArgs.push initVid
      let st3 := { st2 with nextBlockParamOrdinal := ord }
      let st4 := sealCurrentBlock st3 (.jump { blockId := headerId, args := preArgs })
      -- Header: induction + carried params; cond `i < end` gates the body.
      let st5 := { st4 with currentParams := headerParams }
      let (st5b, condVid) :=
        emitValue st5 boolTid (.binary BinaryOpV1.lt iVid eVid)
      let bodyId := UInt32.ofNat (st5b.blocks.size + 1)
      let st6 := sealCurrentBlock st5b (.branch condVid
          { blockId := bodyId, args := #[] } { blockId := 0, args := #[] })
      -- Body env: outer names + carried rebound to header params + binder.
      let mut bodyEnv := savedEnv
      for (cn, cVid, tid) in carriedHeader do
        bodyEnv := envRebind bodyEnv cn cVid tid
      bodyEnv := envInsert bodyEnv bname iVid inductionTid
      let (stB, bodyStatus) ← lowerStmts body.statements resultTid
        { st6 with env := bodyEnv } states events errors fns
      let stL ← match bodyStatus with
        | .open_ =>
            let latchIdx := stB.blocks.size
            -- The induction literal is canonical `1` at the exact UInt/Int width.
            let oneBytes := match anonShapeOf? stB.interner.types inductionTid with
              | some (.uint w) | some (.int w) =>
                  encodeNatLeBytes 1 (w.toNat / 8)
              | _ => encodeU64le 1
            let (stB1, oneVid) :=
              emitValue stB inductionTid (.literal inductionTid oneBytes)
            let (stB2, incVid) :=
              emitValue stB1 inductionTid (.binary BinaryOpV1.add iVid oneVid)
            let mut latchArgs : Array ValueIdV1 := #[incVid]
            for (cn, _, tid) in carriedHeader do
              match envLookup stB2.env cn with
              | none =>
                  return ← failUnsupported
                    s!"S1 loop-carried local '{cn}' lost in body"
              | some (vid, tid') =>
                  unless tid' == tid do
                    return ← failUnsupported
                      s!"S1 loop-carried local '{cn}' type changed in body"
                  latchArgs := latchArgs.push vid
            let stSealed := sealCurrentBlock stB2
              (.jump { blockId := headerId, args := latchArgs })
            pure { stSealed with
              loopBounds := stSealed.loopBounds.push {
                header := headerId
                backEdgeFrom := UInt32.ofNat latchIdx
                maxIterations := bound
              } }
        -- Body returns/reverts on every path: no back edge exists, so no
        -- loop-bound entry is recorded (the header degenerates to a one-shot).
        | .closed => pure stB
      -- Exit: false-branch lands here; carried names refer to header params
      -- (values when the condition failed). Body-only lets do not leak.
      let exitId := UInt32.ofNat stL.blocks.size
      let mut exitEnv := savedEnv
      for (cn, cVid, tid) in carriedHeader do
        exitEnv := envRebind exitEnv cn cVid tid
      pure ({ patchBranchElse stL headerIdx exitId with env := exitEnv }, .open_)
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

/-- Lower one callable body. Returns blocks, loopBounds, interner, and N5
    ContextRead/Commit usage flags for program-wide wire requirement merge. -/
private def lowerBlock
    (body : SrcBlock) (params : Array ParameterV1) (resultTid : TypeIdV1)
    (interner : TypeInternerV1) (states : StateTableV1)
    (constants : ConstantTableV1)
    (events : EventTableV1) (errors : ErrorTableV1) (fns : FnTableV1)
    (allowImplicitReturnNone : Bool)
    (allowContextCommit : Bool)
    (usedUnix0 usedCaller0 usedHeight0 usedCommit0 : Bool) :
    Except NormalizeErrorV1
      (Array BlockV1 × Array LoopBoundV1 × TypeInternerV1 × Bool × Bool × Bool × Bool) := do
  let mut env := emptyEnv
  let mut paramNames : Array String := #[]
  for p in params do
    env := envInsert env p.name p.valueId p.typeId
    paramNames := paramNames.push p.name
  let st : BodyStateV1 := {
    blocks := #[]
    instructions := #[]
    currentParams := #[]
    loopBounds := #[]
    nextValueId := UInt32.ofNat
      (params.size +
        countLoopBlockParamsStmtsV1 body.statements paramNames paramNames +
        countExprMatchJoinsInStmtsV1 body.statements)
    nextBlockParamOrdinal := 0
    callableParamCount := params.size
    nextEffectId := 0
    env := env
    paramNames := paramNames
    constants := constants
    interner := interner
    allowContextCommit := allowContextCommit
    usedContextUnixTime := usedUnix0
    usedContextCaller := usedCaller0
    usedContextBlockHeight := usedHeight0
    usedCommit := usedCommit0
  }
  let (st', status) ← lowerStmts body.statements resultTid st states events errors fns
  -- Canonical ascending (header, backEdgeFrom) loop-bound order.
  let finish := fun (stF : BodyStateV1) =>
    (stF.blocks,
      stF.loopBounds.qsort (fun a b =>
        a.header < b.header || (a.header == b.header && a.backEdgeFrom < b.backEdgeFrom)),
      stF.interner,
      stF.usedContextUnixTime,
      stF.usedContextCaller,
      stF.usedContextBlockHeight,
      stF.usedCommit)
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
    requireStateOrParamTypeId interner.types tid
      s!"parameter '{raw p.name}'"
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

/-- Lower `invariant name : BoolExpr` to a zero-arg callable body: evaluate the
    Bool predicate (full state + pureFn table; ContextRead/Commit fail closed)
    and `return some` on the **current open block** after expression lowering.
    Predicates may be multi-block (e.g. expression `match` → arm blocks + join);
    `loopBounds` stay empty by construction (no source `for` in a bare expr). -/
private def lowerInvariantPredicate
    (predicate : SrcExpr)
    (interner : TypeInternerV1) (states : StateTableV1)
    (constants : ConstantTableV1) (fns : FnTableV1) :
    Except NormalizeErrorV1 (Array BlockV1 × TypeInternerV1) := do
  let (i1, boolTid) := internShape interner .bool
  -- Expression-match joins allocate block params in the same pre-counted
  -- ValueId range as statement bodies (params first, then join params).
  let joinReserve := countExprMatchJoinsInExprV1 predicate
  let st : BodyStateV1 := {
    blocks := #[]
    instructions := #[]
    currentParams := #[]
    loopBounds := #[]
    nextValueId := UInt32.ofNat joinReserve
    nextBlockParamOrdinal := 0
    callableParamCount := 0
    nextEffectId := 0
    env := emptyEnv
    paramNames := #[]
    constants := constants
    interner := i1
    allowContextCommit := false
    usedContextUnixTime := false
    usedContextCaller := false
    usedContextBlockHeight := false
    usedCommit := false
  }
  let (vid, tid, st1) ← lowerExpr predicate boolTid st states fns
  unless tid == boolTid do
    return ← failUnsupported
      "S1 invariant predicate must lower to Bool"
  -- Invariant roots must not emit ContextRead/Commit (structure + product).
  if st1.usedContextUnixTime || st1.usedContextCaller ||
      st1.usedContextBlockHeight || st1.usedCommit then
    return ← failUnsupported
      "S1 invariant predicate must not use ContextRead or Commit"
  -- Seal whatever block is open after the predicate (join block for match,
  -- the sole entry block for straight-line predicates).
  let st2 := sealCurrentBlock st1 (TerminatorV1.return_ (some vid))
  pure (st2.blocks, st2.interner)

/-- Assign sole Wire exact `invariantSteps` onto invariant roots and pureFn
    closure members. Membership + totals come from the shared InvariantClosure
    computation (no second formula). -/
private def assignExactInvariantStepsV1
    (callables : Array CallableV1) :
    Except NormalizeErrorV1 (Array CallableV1) := do
  let members ← match invariantClosureMembershipResultV1 callables with
    | .ok m => pure m
    | .error e =>
        return ← failUnsupported
          s!"S1 invariant closure membership failed: {repr e}"
  let totals ← match computeInvariantStepsExactWithMembersV1 callables members with
    | .ok t => pure t
    | .error e =>
        return ← failUnsupported
          s!"S1 invariant exact steps failed: {repr e}"
  unless members.size == callables.size && totals.size == callables.size do
    return ← failUnsupported "S1 invariant steps size mismatch"
  let mut out : Array CallableV1 := #[]
  for i in [:callables.size] do
    match callables[i]?, totals[i]?, members[i]? with
    | some c, some total, some isMember =>
        let steps : Option UInt64 :=
          if c.kind == CallableKindV1.invariant then
            some total
          else if c.kind == CallableKindV1.pureFn && isMember then
            some total
          else
            none
        out := out.push { c with invariantSteps := steps }
    | _, _, _ =>
        return ← failUnsupported "S1 invariant steps index out of range"
  pure out

/-- Insert a requirement row into a UTF-8 id-ordered array. An existing row
    with the same id wins; exact wire-owned row validation remains authoritative.
    Local to N5 wire-owned merge; does not invent a second freeze. -/
private def insertRequirementSortedV1
    (items : Array RequirementRequestV1) (row : RequirementRequestV1) :
    Array RequirementRequestV1 := Id.run do
  let mut out : Array RequirementRequestV1 := #[]
  let mut inserted := false
  for item in items do
    if !inserted then
      match compareByteArrayLex item.id.toUTF8 row.id.toUTF8 with
      | .gt =>
          out := out.push row
          out := out.push item
          inserted := true
      | .lt | .eq =>
          out := out.push item
    else
      out := out.push item
  if !inserted then
    out := out.push row
  pure out

/-- Merge wire-owned ContextRead/Commit/extension exact rows into the S2
    freeze result. Context/Commit rows appear only when the corresponding ops
    were emitted; each closed engineering extension row appears when its exact
    declaration exists, even without a call. All rows retain their own non-S2
    digest domains. -/
private def mergeWireOwnedRequirementsV1
    (s2 : ProgramRequirementsV1)
    (usedUnixTime usedCaller usedBlockHeight usedCommit
      usedSolanaCpiExtension usedPfAssetsExtension : Bool) :
    Except NormalizeErrorV1 ProgramRequirementsV1 := do
  let mut items := s2.items
  if usedUnixTime then
    match unixTimeSecondsContextRequirementV1 with
    | .ok row => items := insertRequirementSortedV1 items row
    | .error e => return ← failUnsupported s!"ContextRead unix-time requirement row: {e}"
  if usedCaller then
    match callerContextRequirementV1 with
    | .ok row => items := insertRequirementSortedV1 items row
    | .error e => return ← failUnsupported s!"ContextRead caller requirement row: {e}"
  if usedBlockHeight then
    match blockHeightContextRequirementV1 with
    | .ok row => items := insertRequirementSortedV1 items row
    | .error e => return ← failUnsupported s!"ContextRead block-height requirement row: {e}"
  if usedCommit then
    match commitmentDisclosureRequirementV1 with
    | .ok row => items := insertRequirementSortedV1 items row
    | .error e => return ← failUnsupported s!"Commit requirement row: {e}"
  if usedSolanaCpiExtension then
    match solanaCpiAccountsExtensionRequirementV1 with
    | .ok row => items := insertRequirementSortedV1 items row
    | .error e => return ← failUnsupported s!"Solana CPI extension requirement row: {e}"
  if usedPfAssetsExtension then
    match pfAssetsExtensionRequirementV1 with
    | .ok row => items := insertRequirementSortedV1 items row
    | .error e => return ← failUnsupported s!"pf.assets extension requirement row: {e}"
  pure { items }

/-- Compile-time constant evaluator for `const` declarations (engineering
    slice). SPEC-LANG: a `const` is evaluated at elaboration time, so it must
    NOT read state/context and must NOT call functions. This first slice
    admits only the self-evaluating forms:
      * a Bool / integer / string literal, or
      * unary `-` applied to an integer literal (Int / negative-Int ranges).
    Every other expression form (place reads, binary ops, constructors,
    local calls, match) fails closed here so a later slice can extend the
    admitted constant grammar with exact range/overflow semantics rather than
    silently approximating. The value is canonicalized to `valueBytes` via the
    same literal encoder used by `Op.Literal`, so const and literal encodings
    agree byte-for-byte. -/
private def evalConstDeclValueV1
    (types : Array TypeDeclV1) (expectedTid : TypeIdV1) (value : SrcExpr) :
    Except NormalizeErrorV1 ByteArray := do
  match value with
  | ProofForgeV2.Source.AstSpineV1.ExprV1.literal lit =>
      encodeLiteralValueBytesV1 types expectedTid lit
  | ProofForgeV2.Source.AstSpineV1.ExprV1.unary
      ProofForgeV2.Source.AstV1.UnaryOpV1.neg
      (ProofForgeV2.Source.AstSpineV1.ExprV1.literal
        (ProofForgeV2.Source.AstV1.LiteralV1.integer magnitude)) =>
      -- `-magnitude` as a two's-complement Int literal (mirrors the lowerer
      -- unary-neg-on-literal folding at the call sites below).
      match anonShapeOf? types expectedTid with
      | some (.int w) =>
          let width := w.toNat
          unless legalIntegerWidthV1 width do
            return ← failUnsupported "S1 const negative literal requires legal Int width"
          let vi : Int := - Int.ofNat magnitude
          let lo : Int := - Int.ofNat (Nat.pow 2 (width - 1))
          let hi : Int := Int.ofNat (Nat.pow 2 (width - 1)) - 1
          unless lo ≤ vi ∧ vi ≤ hi do
            return ← failUnsupported "S1 const negative literal is out of Int range"
          pure (encodeIntLeBytes vi width)
      | _ =>
          failUnsupported "S1 const unary minus requires an Int expected type"
  | _ =>
      failUnsupported
        "S1 const value must be a literal (or `-` integer literal); place reads, binary ops, constructors, calls, and match fail closed"

/-- Core lowering after Typed CheckV1 has succeeded.

  Passes over ProgramV1 items (not NameResolution tables):
  0. Register source-order named Struct/Enum TypeDecls (contiguous prefix).
  1. Collect/validate all legal-UInt/Int states (public/private/commitment)
     into a complete logicalState table (IDs are source-order among state
     decls, independent of callable position). Visibility is retained via
     `mapVisibility`; product disclosure is enforced by CheckV1/DisclosureCheck
     before this lowering (not by the state table gate).
  2a. Fn signature table (param/result types interned).
  2b. Complete constants table (dense source-order IDs + type interning +
     literal valueBytes via sole `evalConstDeclValueV1`) **after** fn
     signatures and **before** any callable body so forward const references
     resolve while preserving the older "all fn signature types before const
     types" interning order. Const types are deterministic; post-declared
     novel const shapes still cut over relative to earlier body-only shapes
     (N-CONST-REF engineering identity — not a claim of full hash stability).
     Const type/value grammar is owned by TypeCheck + `evalConstDeclValueV1`
     (no second allowlist authority here).
  2c. Lower init/entry/view/fn/invariant bodies against complete tables.
     Target note: EVM/Solana/NEAR/Noir fail closed on any nonempty constants
     table; Aleo/Psy fail closed when an `Op.Constant` appears in a body
     (unused table rows alone are not a six-target early reject).
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
  -- items only). Event/error fields stay public anonymous legal UInt/Int/String.
  -- State rows admit legal UInt/Int/Field/Principal or named Struct/Enum and
  -- retain visibility (N1/N2b/N2c/N3).
  for item in program.items do
    match item with
    | .state s =>
        let (interner', tid) ← internSourceType interner s.type_
        interner := interner'
        requireStateOrParamTypeId interner.types tid
          s!"state '{raw s.name}'"
        let sid := UInt32.ofNat stateRows.size
        stateRows := stateRows.push {
          id := sid
          name := raw s.name
          typeId := tid
          visibility := mapVisibility s.visibility
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
          requireEventErrorFieldTypeId interner.types tid
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
          requireEventErrorFieldTypeId interner.types tid
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
  -- the unified source order of **every item that becomes a callable** in
  -- pass 2c: init/entry/view/fn/**invariant** (same order pass 2c lowers them).
  -- Invariants occupy an ordinal so that a pureFn declared after an invariant
  -- still receives the correct PureCall calleeId. Fn params stay public
  -- legal-UInt/Int/Field/Principal; results are public legal
  -- UInt/Int/Unit/Bool/Field/Principal. Signature types intern before const
  -- types (pass 2b below) to keep prior fn-before-const interning order.
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
          requireStateOrParamTypeId interner.types tid
            s!"fn '{raw d.name}' param '{raw p.name}'"
          paramTids := paramTids.push tid
        let (interner', resultTid) ← internSourceType interner d.result
        interner := interner'
        requireCallableResultTypeId interner.types resultTid s!"fn '{raw d.name}' result"
        let fnRow := (raw d.name, UInt32.ofNat fnCallableOrdinal, paramTids, resultTid)
        fnTable := { rows := fnTable.rows.push fnRow }
    | _ => pure ()
    match item with
    | .init _ | .entry _ | .view _ | .fn _ | .invariant _ =>
        fnCallableOrdinal := fnCallableOrdinal + 1
    | _ => pure ()

  -- Pass 2b: complete constants table before any callable body
  -- (N-CONST-REF). Dense ConstantId by const declaration source order;
  -- valueBytes sole path is `evalConstDeclValueV1` (same literal encoder as
  -- Op.Literal). Type/value legality: TypeCheck + evalConstDeclValueV1 only.
  let mut constantRows : Array ConstantV1 := #[]
  let mut constantTable : ConstantTableV1 := ⟨#[]⟩
  for item in program.items do
    match item with
    | .const d =>
        let (interner', tid) ← internSourceType interner d.type_
        interner := interner'
        let valueBytes ← evalConstDeclValueV1 interner.types tid d.value
        let cid := UInt32.ofNat constantRows.size
        constantRows := constantRows.push {
          id := cid
          name := raw d.name
          typeId := tid
          valueBytes }
        constantTable := {
          rows := constantTable.rows.push (raw d.name, cid, tid)
        }
    | _ => pure ()

  -- Pass 2c: lower supported callables; reject unsupported item kinds.
  let mut callables : Array CallableV1 := #[]
  let mut invariantRows : Array WireV1.InvariantDeclV1 := #[]
  let mut callableId : Nat := 0
  let mut usedContextUnixTime := false
  let mut usedContextCaller := false
  let mut usedContextBlockHeight := false
  let mut usedCommit := false
  let mut usedSolanaCpiExtension := false
  let mut usedPfAssetsExtension := false
  for item in program.items do
    match item with
    | .state _ => pure ()
    | .init d =>
        let (interner', params) ← lowerParams d.params interner
        interner := interner'
        let (interner'', unitTid) := internShape interner .unit
        interner := interner''
        let (blocks, loopBounds, interner''', ux, uc, uh, cm) ←
          lowerBlock d.body params unitTid interner stateTable constantTable
            eventTable errorTable fnTable
            true true usedContextUnixTime usedContextCaller usedContextBlockHeight
              usedCommit
        interner := interner'''
        usedContextUnixTime := ux
        usedContextCaller := uc
        usedContextBlockHeight := uh
        usedCommit := cm
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .initializer none params
          { typeId := unitTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .entry e =>
        let (interner', params) ← lowerParams e.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner e.result
        interner := interner''
        requireCallableResultTypeId interner.types resultTid s!"entry '{raw e.name}' result"
        let (blocks, loopBounds, interner''', ux, uc, uh, cm) ←
          lowerBlock e.body params resultTid interner stateTable constantTable
            eventTable errorTable fnTable
            false true usedContextUnixTime usedContextCaller usedContextBlockHeight
              usedCommit
        interner := interner'''
        usedContextUnixTime := ux
        usedContextCaller := uc
        usedContextBlockHeight := uh
        usedCommit := cm
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .entry (some (raw e.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .view v =>
        let (interner', params) ← lowerParams v.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner v.result
        interner := interner''
        requireCallableResultTypeId interner.types resultTid s!"view '{raw v.name}' result"
        let (blocks, loopBounds, interner''', ux, uc, uh, cm) ←
          lowerBlock v.body params resultTid interner stateTable constantTable
            eventTable errorTable fnTable
            false true usedContextUnixTime usedContextCaller usedContextBlockHeight
              usedCommit
        interner := interner'''
        usedContextUnixTime := ux
        usedContextCaller := uc
        usedContextBlockHeight := uh
        usedCommit := cm
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .view (some (raw v.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .struct _ => pure ()  -- registered in Pass0; no callable body
    | .enum _ => pure ()    -- registered in Pass0; no callable body
    | .const _ => pure ()   -- Pass 2b complete constants table
    | .event _ => pure ()
    | .error _ => pure ()
    | .fn d =>
        let (interner', params) ← lowerParams d.params interner
        interner := interner'
        let (interner'', resultTid) ← internSourceType interner d.result
        interner := interner''
        requireCallableResultTypeId interner.types resultTid s!"fn '{raw d.name}' result"
        -- Fn purity: the body resolves bare places against an empty state
        -- table, so any state name fails closed (fn effects are revert-only).
        -- Constants remain visible (compile-time values, not state).
        -- N5: ContextRead/Commit also fail closed (allowContextCommit=false).
        let emptyStates : StateTableV1 := ⟨#[]⟩
        let (blocks, loopBounds, interner''', ux, uc, uh, cm) ←
          lowerBlock d.body params resultTid interner emptyStates constantTable
            eventTable errorTable fnTable
            false false usedContextUnixTime usedContextCaller usedContextBlockHeight
              usedCommit
        interner := interner'''
        usedContextUnixTime := ux
        usedContextCaller := uc
        usedContextBlockHeight := uh
        usedCommit := cm
        callables := callables.push (mkCallable
          (UInt32.ofNat callableId) .pureFn (some (raw d.name)) params
          { typeId := resultTid, visibility := VisibilityV1.public_ } blocks loopBounds)
        callableId := callableId + 1
    | .invariant d =>
        -- N-INVARIANT-IR: lower Bool predicate into a zero-arg `.invariant`
        -- callable + dense InvariantDecl row (source order). Full state table,
        -- constants table, and pureFn table are visible; ContextRead/Commit
        -- fail closed. `.proof` remains certification-only (handled below).
        let (blocks, interner') ←
          lowerInvariantPredicate d.predicate interner stateTable constantTable fnTable
        interner := interner'
        let (interner'', boolTid) := internShape interner .bool
        interner := interner''
        let cid : CallableIdV1 := UInt32.ofNat callableId
        callables := callables.push (mkCallable
          cid CallableKindV1.invariant (some (raw d.name)) #[]
          { typeId := boolTid, visibility := VisibilityV1.public_ }
          blocks #[])
        invariantRows := invariantRows.push ({
          id := UInt32.ofNat invariantRows.size
          name := raw d.name
          callableId := cid
        } : WireV1.InvariantDeclV1)
        callableId := callableId + 1
    | .extensionReq declaration =>
        unless isExactEngineeringExtensionV1 declaration do
          return ← failUnsupported
            "S1 normalizer admits only exact closed engineering extension contracts (solana.cpi.accounts@1.0.0, pf.assets@1.1.0)"
        match wireIdOfExactEngineeringExtensionV1 declaration with
        | some wid =>
            if wid == wireExtensionSolanaCpiAccountsIdV1 then
              usedSolanaCpiExtension := true
            else if wid == wireExtensionPfAssetsIdV1 then
              usedPfAssetsExtension := true
            else
              return ← failUnsupported
                s!"S1 normalizer closed extension wire id not wired for mint: {wid}"
        | none =>
            return ← failUnsupported
              "S1 normalizer closed extension table rejected after exact-triple check"
    | .proof _ =>
        -- INV-1: proof references are certification metadata only; they never
        -- enter Semantic IR / business execution (SPEC-TYPE / SPEC-LANG).
        pure ()

  -- Sole Wire exact invariantSteps (roots + pureFn closure members).
  callables ← assignExactInvariantStepsV1 callables

  -- Target envelope still requires exactly one anonymous UInt64 TypeId.
  -- Int-primary programs (Int64 state/results only) never intern UInt64 via
  -- use; add it once at the end so PilotTypeClosure admission stays stable
  -- without shifting TypeIds of already-used shapes.
  match findTypeId interner (.uint 64) with
  | some _ => pure ()
  | none =>
      let (interner', _) := internShape interner (.uint 64)
      interner := interner'

  -- S2: freeze exact ProgramRequirementsV1 before encode/hash.
  let s2Reqs ← match freezeProgramRequirementsV1 program with
    | .ok r => pure r
    | .error detail => failUnsupported s!"S2 requirements freeze: {detail}"
  -- Merge wire-owned ContextRead/Commit/extension exact rows (non-S2 digest
  -- domains). Each exact extension declaration mints its row even without a
  -- call. Sort by UTF-8 id so the structure gate order holds.
  let requirements ← mergeWireOwnedRequirementsV1 s2Reqs usedContextUnixTime
    usedContextCaller usedContextBlockHeight usedCommit usedSolanaCpiExtension
    usedPfAssetsExtension
  pure {
    qualifiedName := qn
    types := interner.types
    constants := constantRows
    logicalState := stateRows
    events := eventRows
    errors := errorRows
    callables := callables
    invariants := invariantRows
    requirements
  }

/-- Structure-gated encode is the sole path to a SemanticProgramV1 carrier. -/
def encodeCarrierV1 (data : SemanticProgramDataV1) :
    Except NormalizeErrorV1 SemanticProgramV1 :=
  match encodeSemanticProgramDataV1 data with
  | .ok bytes => pure ⟨bytes⟩
  | .error e => .error (.wire e)

/-- Successful carrier encode is exactly the production wire encode of `data`
    packaged as `SemanticProgramV1`. Proof authors use this to recover the
    encode witness without a second encoder. -/
theorem encodeCarrierV1_eq_ok_of_encode
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    encodeCarrierV1 data = .ok ⟨bytes⟩ := by
  simp only [encodeCarrierV1, hencode, Pure.pure, Except.pure]

/-- Invert a successful `encodeCarrierV1`: the carrier bytes are the sole
    production encode of the same data. -/
theorem encodeCarrierV1_ok_implies_encode
    (data : SemanticProgramDataV1) (program : SemanticProgramV1)
    (h : encodeCarrierV1 data = .ok program) :
    encodeSemanticProgramDataV1 data = .ok program.canonicalBytes := by
  simp only [encodeCarrierV1] at h
  split at h
  · next bytes hencode =>
      simp only [Pure.pure, Except.pure] at h
      cases h
      exact hencode
  · next e he =>
      cases h

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

/-- Build source-bound provenance from the opaque production origin inventory.

    Unlike the low-level provenance builder, callers cannot construct or alter
    this inventory: `OriginInventoryV1` is minted only by Source's exact
    same-snapshot path/span join. The retained semantic carrier must also be
    byte-identical to normalization of that source. -/
def buildSemanticProvenanceFromOriginInventoryV1
    (source : ValidatedSourceV1)
    (inventory : OriginInventoryV1)
    (program : SemanticProgramV1) :
    Except NormalizeErrorV1 SemanticProvenanceV1 := do
  let sourceHash ← match sourceHashV1 source with
    | .ok value => pure value
    | .error detail => return ← failIdentity detail
  unless sourceHash == originInventorySourceHashV1 inventory do
    return ← failIdentity "source does not match production origin inventory"
  let expectedProgram ← match normalizeProgramLocatedV1 source inventory with
    | .ok value => pure value
    | .error _ => .error (.identity
        "located normalization failed while closing proof-subject authority")
  unless expectedProgram.canonicalBytes == program.canonicalBytes do
    return ← failIdentity
      "semantic carrier does not match located normalization of source snapshot"
  let trustedInventory : SourceNodeInventoryV1 := {
    sourceHash := originInventorySourceHashV1 inventory
    nodes := originInventoryOriginsV1 inventory }
  match buildSemanticProvenanceV1 source program trustedInventory with
  | .ok provenance => pure provenance
  | .error error => .error (mapProvenanceError error)

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
