/-
  ProofForgeV2.Typed.TypeCheckV1 — D2-01 expression and statement/body
  type-checking slice.

  B7b2: single path-threaded draft-bearing walk is the authority. Canonical
  ProgramV1 paths use only NodeTraversalV1 childPath helpers. Public
  `typeCheckProgramV1` / `typeCheckExpr` / `typeCheckItem` erase drafts;
  additive `typeCheckProgramDraftsV1` exposes located drafts for
  materialization through B7a OriginInventoryV1.

  Runs after `NameResolutionV1` and assumes every name has already been
  resolved; unresolved names are never reported again from this layer.

  Integer literal rule (pinned):
    * `Bool` literals infer `bool`.
    * Integer literals do NOT default to a width. They must be checked against
      an expected integer type and are exact-range checked for that width.
    * Accepted signed widths: `Int8/16/32/64/128/256` (two's-complement).
    * Accepted unsigned widths: `UInt8/16/32/64/128/256`.
    * Signed minimum values (`-128` for `Int8`, etc.) are accepted because
      the parser represents them as `unary neg (integer literal)`.

  Covered expression forms:
    * literals (`bool`, bounded integer)
    * places (parameter/local/state/const binding, struct field chains,
      `Array` element access with `UInt32` index, `Bytes` element access with
      `UInt32` index returning `UInt8`, `Map` key lookup returning `Option V`)
    * unary operators (`neg`, `bitNot` require integer; `not` requires `bool`)
    * binary operators (arithmetic, shift, bitwise, equality, ordering,
      logical)
    * constructor expressions (struct and enum-variant constructors checked
      against declaration order field/payload types)
    * local function calls (checked against `fn` parameter count and types)
    * expression- and statement-level `match` (pattern typing, arm unification,
      result-context checking, enum exhaustiveness)

  Covered statement/body forms:
    * `let` / `assign` / `return` / `assert` / `revert` / `emit` / `if` /
      `for` / `call` / `schedule` / statement `match`
    * declaration bodies for `const`, `init`, `entry`, `view`, `fn`, `invariant`
    * MapBytesAssign (N-A3): assign targets whose outermost place step is an
      index use the wire IndexSet slot type — `Array` → element, `Bytes` →
      `UInt8`, `Map` → value (not `Option V`). Rvalue Map index stays
      `Option V`. Nested assign through a Map element (`m[k].x := v`) remains
      fail closed at TypeCheck (field on Option) and Normalize.

  Deliberately outside this slice (fail closed with a type-mismatch
  diagnostic):
    * effects and requirements.
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.ContextCommitSurfaceV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.TypeCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.ContextCommitSurfaceV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

instance : Inhabited TypeV1 := ⟨.unit⟩

/-- Local type-checking scope: source-order name-to-type bindings with a
    category tag so that locals and params can be distinguished from
    state/const bindings for local-call diagnostics. -/
inductive BindingKindV1 where
  | local
  | param
  | state
  | const
deriving BEq, DecidableEq

structure TypeCheckScopeV1 where
  bindings : List (SourceNameComponentV1 × TypeV1 × BindingKindV1)

def emptyScope : TypeCheckScopeV1 := ⟨[]⟩

def addBinding (scope : TypeCheckScopeV1) (name : SourceNameComponentV1)
    (type_ : TypeV1) : TypeCheckScopeV1 :=
  ⟨ (name, type_, .local) :: scope.bindings ⟩

def addParam (scope : TypeCheckScopeV1) (name : SourceNameComponentV1)
    (type_ : TypeV1) : TypeCheckScopeV1 :=
  ⟨ (name, type_, .param) :: scope.bindings ⟩

def addStateConst (scope : TypeCheckScopeV1) (name : SourceNameComponentV1)
    (type_ : TypeV1) (kind : BindingKindV1) : TypeCheckScopeV1 :=
  ⟨ (name, type_, kind) :: scope.bindings ⟩

def lookupType (scope : TypeCheckScopeV1) (name : SourceNameComponentV1) :
    Option TypeV1 :=
  match scope.bindings.find? (fun (n, _, _) => n == name) with
  | some (_, type_, _) => some type_
  | none => none

def lookupBinding (scope : TypeCheckScopeV1) (name : SourceNameComponentV1) :
    Option (TypeV1 × BindingKindV1) :=
  match scope.bindings.find? (fun (n, _, _) => n == name) with
  | some (_, type_, kind) => some (type_, kind)
  | none => none

private def isLocalOrParam (scope : TypeCheckScopeV1)
    (name : SourceNameComponentV1) : Option BindingKindV1 :=
  match scope.bindings.find? (fun (n, _, _) => n == name) with
  | some (_, _, .local) => some .local
  | some (_, _, .param) => some .param
  | _ => none

/-- Draft-bearing expression result (authority). -/
structure TypeCheckResultDraftV1 where
  type : TypeV1
  drafts : Array TypedDiagnosticDraftV1
  /-- Declaration origin for the inferred place/binding type, when known. -/
  originPath? : Option NormalizedSyntacticPathV1 := none
  deriving Inhabited

/-- Public unlocated expression result (erase projection). -/
structure TypeCheckResultV1 where
  type : TypeV1
  diagnostics : Array DiagnosticV1
  deriving Repr, Inhabited

def resultDraft (type : TypeV1) (drafts : Array TypedDiagnosticDraftV1)
    (originPath? : Option NormalizedSyntacticPathV1 := none) :
    TypeCheckResultDraftV1 :=
  { type, drafts, originPath? }

def result (type : TypeV1) (diagnostics : Array DiagnosticV1) :
    TypeCheckResultV1 :=
  { type := type, diagnostics := diagnostics }

def eraseResult (r : TypeCheckResultDraftV1) : TypeCheckResultV1 :=
  { type := r.type, diagnostics := eraseArray r.drafts }

/-- Attach primary (+ optional related) when a site path is available. -/
def locateDraft
    (base : TypedDiagnosticDraftV1)
    (sitePath? : Option NormalizedSyntacticPathV1)
    (relatedPaths : Array NormalizedSyntacticPathV1 := #[]) :
    TypedDiagnosticDraftV1 :=
  match sitePath? with
  | none => base
  | some p => withPaths base p relatedPaths

/-- Child path or path-internal draft (no silent drop, no fabricated NodeId). -/
def childPathOrDraft
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    Except TypedDiagnosticDraftV1 NormalizedSyntacticPathV1 :=
  match childPathV1 parent parentTag fieldTag index with
  | .ok p => .ok p
  | .error detail => .error (pathInternalDraft detail)

def directPathOrDraft
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) :
    Except TypedDiagnosticDraftV1 NormalizedSyntacticPathV1 :=
  childPathOrDraft parent parentTag fieldTag 0

/-- Resolve optional child under a parent site; accumulate path-internal drafts. -/
def resolveChild
    (parent? : Option NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    Option NormalizedSyntacticPathV1 × Array TypedDiagnosticDraftV1 :=
  match parent? with
  | none => (none, #[])
  | some parent =>
      match childPathOrDraft parent parentTag fieldTag index with
      | .ok p => (some p, #[])
      | .error d => (none, #[d])

def resolveDirect
    (parent? : Option NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) :
    Option NormalizedSyntacticPathV1 × Array TypedDiagnosticDraftV1 :=
  resolveChild parent? parentTag fieldTag 0

/-- Deterministic `expected-vs-actual` diagnostic draft. -/
def expectedActualDiagnosticDraft (expected actual : String) :
    TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"type mismatch: expected {expected}, got {actual}"

def expectedActualDiagnostic (expected actual : String) : DiagnosticV1 :=
  erase (expectedActualDiagnosticDraft expected actual)

private def internalDiagnosticDraft (message : String) : TypedDiagnosticDraftV1 :=
  make .internal message

private def internalDiagnostic (message : String) : DiagnosticV1 :=
  erase (internalDiagnosticDraft message)

/-- Render a type for diagnostics.  This is human-readable only and does not
    enter wire/hash identity. -/
partial def typeName : TypeV1 → String
  | .bool => "Bool"
  | .uint w => s!"UInt{w.toNat}"
  | .int w => s!"Int{w.toNat}"
  | .principal => "Principal"
  | .unit => "Unit"
  | .string => "String"
  | .named n => renderSourceNameComponentV1 n
  | .bytes n => s!"Bytes({n.toNat})"
  | .field id => s!"Field({id.raw})"
  | .option t => s!"Option ({typeName t})"
  | .array t n => s!"Array ({typeName t}) ({n.toNat})"
  | .map k v => s!"Map ({typeName k}) ({typeName v})"

def isIntegerType : TypeV1 → Bool
  | .uint _ | .int _ => true
  | _ => false

/-- Sole Phase-1 Field catalog spelling (`Field bn254_fr`). -/
def isFieldType : TypeV1 → Bool
  | .field id => id.raw == "bn254_fr"
  | _ => false

/-- Integer or Field (bn254_fr) — numeric surface for arithmetic and unary neg. -/
def isNumericType (t : TypeV1) : Bool :=
  isIntegerType t || isFieldType t

/-- Legacy message kept only for erase-parity tests that pin the historical
    string-pattern rejection; N4 admits string patterns on `TypeV1.string`. -/
def stringPatternDiagnosticDraft : TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    "string patterns are not supported (String is not a TypeV1)"

def stringPatternDiagnostic : DiagnosticV1 :=
  erase stringPatternDiagnosticDraft

def stringPatternOnNonStringDiagnosticDraft (actual : String) :
    TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"type mismatch: expected String, got {actual}"

def armTypeMismatchDiagnosticDraft (armIndex : Nat) (expected actual : String) :
    TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"match arm {armIndex}: type mismatch: expected {expected}, got {actual}"

def armTypeMismatchDiagnostic (armIndex : Nat) (expected actual : String) : DiagnosticV1 :=
  erase (armTypeMismatchDiagnosticDraft armIndex expected actual)

def nonExhaustiveDiagnosticDraft (missing : List String) : TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    (if missing.isEmpty then "match is not exhaustive"
     else "match is not exhaustive; missing variants: " ++ String.intercalate ", " missing)

def nonExhaustiveDiagnostic (missing : List String) : DiagnosticV1 :=
  erase (nonExhaustiveDiagnosticDraft missing)

def duplicatePatternDiagnosticDraft (armIndex : Nat) : TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"match arm {armIndex}: duplicate pattern"

def duplicatePatternDiagnostic (armIndex : Nat) : DiagnosticV1 :=
  erase (duplicatePatternDiagnosticDraft armIndex)

/-- Structural pattern equality for multi-arm duplicate detection: bind and
    wildcard are equivalent catch-alls; literals compare by value; constructors
    compare by qualified-name components and recursive args. Bind names are
    erased so `Some(x)` and `Some(y)` collide. -/
private partial def patternShapeEqualV1 : PatternV1 → PatternV1 → Bool
  | .wildcard, .wildcard => true
  | .wildcard, .bind _ => true
  | .bind _, .wildcard => true
  | .bind _, .bind _ => true
  | .literal a, .literal b => a == b
  | .constructor c1 a1, .constructor c2 a2 =>
      let comps1 := c1.components.toArray.map (·.raw)
      let comps2 := c2.components.toArray.map (·.raw)
      comps1 == comps2 && a1.size == a2.size &&
        (List.range a1.size).all fun i =>
          match a1[i]?, a2[i]? with
          | some pa, some pb => patternShapeEqualV1 pa pb
          | _, _ => false
  | _, _ => false

/-- Report later arms whose structural pattern key equals an earlier arm
    (source-order; first arm keeps the identity). -/
def checkDuplicatePatternsDrafts (patterns : Array PatternV1)
    (matchPath? : Option NormalizedSyntacticPathV1) :
    Array TypedDiagnosticDraftV1 := Id.run do
  let mut drafts : Array TypedDiagnosticDraftV1 := #[]
  let mut i : Nat := 0
  for p in patterns do
    let mut j : Nat := 0
    let mut dup := false
    for q in patterns do
      if j < i && patternShapeEqualV1 p q then
        dup := true
      j := j + 1
    if dup then
      drafts := drafts.push
        (locateDraft (duplicatePatternDiagnosticDraft i) matchPath? #[])
    i := i + 1
  pure drafts

def checkDuplicatePatterns (patterns : Array PatternV1) : Array DiagnosticV1 :=
  eraseArray (checkDuplicatePatternsDrafts patterns none)

structure PatternCheckResultDraftV1 where
  bindings : List (SourceNameComponentV1 × TypeV1)
  drafts : Array TypedDiagnosticDraftV1
  deriving Inhabited

structure PatternCheckResultV1 where
  bindings : List (SourceNameComponentV1 × TypeV1)
  diagnostics : Array DiagnosticV1
  deriving Inhabited

def patternResultDraft (bindings : List (SourceNameComponentV1 × TypeV1))
    (drafts : Array TypedDiagnosticDraftV1) : PatternCheckResultDraftV1 :=
  { bindings, drafts }

def patternResult (bindings : List (SourceNameComponentV1 × TypeV1))
    (diagnostics : Array DiagnosticV1) : PatternCheckResultV1 :=
  { bindings := bindings, diagnostics := diagnostics }

def integerLiteralBound (type_ : TypeV1) (isNegated : Bool) : Option Nat :=
  match type_ with
  | .uint w => some (Nat.pow 2 w.toNat - 1)
  | .int w =>
      let w := w.toNat
      if isNegated then
        some (Nat.pow 2 (w - 1))
      else
        some (Nat.pow 2 (w - 1) - 1)
  | _ => none

def integerLiteralDiagnosticDraft (expected : TypeV1) (magnitude : Nat)
    (isNegated : Bool) : TypedDiagnosticDraftV1 :=
  let sign := if isNegated then "-" else ""
  expectedActualDiagnosticDraft (typeName expected)
    s!"integer literal {sign}{magnitude} out of range"

def integerLiteralDiagnostic (expected : TypeV1) (magnitude : Nat)
    (isNegated : Bool) : DiagnosticV1 :=
  erase (integerLiteralDiagnosticDraft expected magnitude isNegated)

def checkExpectedDraft (actual : TypeV1) (expected? : Option TypeV1)
    (sitePath? : Option NormalizedSyntacticPathV1)
    (relatedPaths : Array NormalizedSyntacticPathV1)
    (drafts : Array TypedDiagnosticDraftV1) :
    TypeV1 × Array TypedDiagnosticDraftV1 :=
  match expected? with
  | none => (actual, drafts)
  | some expected =>
      if expected == actual then (actual, drafts)
      else
        (actual, drafts.push (locateDraft
          (expectedActualDiagnosticDraft (typeName expected) (typeName actual))
          sitePath? relatedPaths))

def checkExpected (actual : TypeV1) (expected? : Option TypeV1)
    (diagnostics : Array DiagnosticV1) : TypeV1 × Array DiagnosticV1 :=
  match expected? with
  | none => (actual, diagnostics)
  | some expected =>
      if expected == actual then (actual, diagnostics)
      else (actual, diagnostics.push (expectedActualDiagnostic (typeName expected) (typeName actual)))

private def isArithmeticOp : BinaryOpV1 → Bool
  | .add | .sub | .mul | .div | .mod => true
  | _ => false

private def isShiftOp : BinaryOpV1 → Bool
  | .shl | .shr => true
  | _ => false

private def isBitwiseOp : BinaryOpV1 → Bool
  | .bitAnd | .bitOr | .bitXor => true
  | _ => false

private def isComparisonOp : BinaryOpV1 → Bool
  | .lt | .le | .gt | .ge => true
  | _ => false

private def isEqualityOp : BinaryOpV1 → Bool
  | .eq | .ne => true
  | _ => false

private def isLogicalOp : BinaryOpV1 → Bool
  | .logicalAnd | .logicalOr => true
  | _ => false

/-- Related path for a constructor result (struct or enum item). -/
def constructorRelatedPaths (tables : TypedDeclTablesV1)
    (ctor : SourceQualifiedNameV1) (resType : TypeV1) :
    Array NormalizedSyntacticPathV1 :=
  match resType with
  | .named n =>
      let comps := ctor.components.toArray
      match comps with
      | #[_] =>
          -- Prefer struct, else enum that owns the bare variant name.
          match itemPathForNamed? tables .struct n with
          | some p => #[p]
          | none => optRelatedPath (itemPathForNamed? tables .enum n)
      | #[typeName, methodOrVariant] =>
          if methodOrVariant.raw == "new" then
            optRelatedPath (itemPathForNamed? tables .struct typeName)
          else
            optRelatedPath (itemPathForNamed? tables .enum typeName)
      | _ => optRelatedPath (itemPathForNamed? tables .struct n) ++
          optRelatedPath (itemPathForNamed? tables .enum n)
  | _ => #[]

/-- Argument-related path for constructor field/payload at index. -/
def constructorArgRelatedPaths (tables : TypedDeclTablesV1)
    (ctor : SourceQualifiedNameV1) (resType : TypeV1) (argIndex : Nat) :
    Array NormalizedSyntacticPathV1 :=
  match resType with
  | .named n =>
      let comps := ctor.components.toArray
      match comps with
      | #[name] =>
          match tables.struct.find? name with
          | some (_, sd) =>
              match sd.fields[argIndex]? with
              | some f => optRelatedPath (structFieldPath? tables name f.name)
              | none => optRelatedPath (itemPathForNamed? tables .struct name)
          | none =>
              -- Bare enum variant
              match tables.enum.find? n with
              | some _ =>
                  let variantName := name
                  optRelatedPath (enumVariantPath? tables n variantName)
              | none =>
                  -- variant name lookup across enums already resolved
                  optRelatedPath (itemPathForNamed? tables .enum n)
      | #[typeName, methodOrVariant] =>
          if methodOrVariant.raw == "new" then
            match tables.struct.find? typeName with
            | some (_, sd) =>
                match sd.fields[argIndex]? with
                | some f => optRelatedPath (structFieldPath? tables typeName f.name)
                | none => optRelatedPath (itemPathForNamed? tables .struct typeName)
            | none => optRelatedPath (itemPathForNamed? tables .struct typeName)
          else
            optRelatedPath (enumVariantPath? tables typeName methodOrVariant)
      | _ => #[]
  | _ => #[]

/-- N-A4: resolve `Option.some` / `Option.none` (and Some/None) when the expected
    or scrutinee type is `Option T`. Without expected Option context, returns none
    so the ordinary enum/struct path can produce a clear diagnostic. -/
private def tryOptionConstructor
    (expected? : Option TypeV1) (ctor : SourceQualifiedNameV1) :
    Option (TypeV1 × Array TypeV1) :=
  let comps := ctor.components.toArray
  match comps, expected? with
  | #[typeName, methodOrVariant], some (.option elem) =>
      if typeName.raw != "Option" then none
      else
        let m := methodOrVariant.raw
        if m == "none" || m == "None" then
          some (.option elem, #[])
        else if m == "some" || m == "Some" then
          some (.option elem, #[elem])
        else none
  | _, _ => none

/-- Resolve a constructor path to its result type and expected argument types.
    Mirrors `NameResolutionV1.resolveConstructorName`. Optional `expected?` unlocks
    N-A4 `Option.some`/`Option.none` when the expected type is `Option T`. -/
def resolveConstructorType (tables : TypedDeclTablesV1)
    (ctor : SourceQualifiedNameV1) (expected? : Option TypeV1 := none) :
    Except DiagnosticV1 (TypeV1 × Array TypeV1) :=
  match tryOptionConstructor expected? ctor with
  | some r => pure r
  | none =>
  let comps := ctor.components.toArray
  match comps with
  | #[name] =>
      let hasEnumVariant :=
        tables.enum.toArray.any fun (_, _, enumDecl) =>
          enumDecl.variants.any (·.name == name)
      if let some (_, structDecl) := tables.struct.find? name then
        if hasEnumVariant then
          .error (ambiguousNameDiagnostic name "constructor")
        else
          pure (.named structDecl.name, structDecl.fields.map (·.type_))
      else
        let candidateMatches :=
          tables.enum.toArray.foldl (fun acc (_, _, enumDecl) =>
            match enumDecl.variants.find? (·.name == name) with
            | some variant => acc.push (enumDecl, variant)
            | none => acc) #[]
        match candidateMatches.toList with
        | [(enumDecl, variant)] =>
            pure (.named enumDecl.name, variant.payloadTypes)
        | _ :: _ :: _ =>
            .error (ambiguousNameDiagnostic name "constructor")
        | _ =>
            match findFirstMatchingKind tables name with
            | some (kind, _) => .error (wrongCategoryDiagnostic name kind "constructor")
            | none => .error (unknownNameDiagnostic name "constructor")
  | #[typeName, methodOrVariant] =>
      -- Phase-1 constructor identity: StructName.new | EnumName.Variant |
      -- Option.some/none (when expected? = some (.option _)).
      if methodOrVariant.raw == "new" then
        match tables.struct.find? typeName with
        | some (_, structDecl) =>
            pure (.named structDecl.name, structDecl.fields.map (·.type_))
        | none =>
            match findFirstMatchingKind tables typeName with
            | some (kind, _) =>
                .error (wrongCategoryDiagnostic typeName kind "constructor")
            | none => .error (unknownNameDiagnostic typeName "constructor struct")
      else
        match tables.enum.find? typeName with
        | some (_, enumDecl) =>
            match enumDecl.variants.find? (·.name == methodOrVariant) with
            | some variant => pure (.named enumDecl.name, variant.payloadTypes)
            | none =>
                .error (unknownNameDiagnostic methodOrVariant "constructor variant")
        | none =>
            match findFirstMatchingKind tables typeName with
            | some (kind, _) =>
                .error (wrongCategoryDiagnostic typeName kind "constructor")
            | none => .error (unknownNameDiagnostic typeName "constructor enum")
  | _ =>
      .error (unknownQualifiedNameDiagnostic ctor "constructor")

/-- Wrap a legacy unlocated DiagnosticV1 as a draft (resolution defensive errors). -/
private def draftFromDiag (diag : DiagnosticV1)
    (sitePath? : Option NormalizedSyntacticPathV1)
    (related : Array NormalizedSyntacticPathV1 := #[]) :
    TypedDiagnosticDraftV1 :=
  locateDraft { diagnostic := diag, location := none } sitePath? related

def resolveLocalCallType (scope : TypeCheckScopeV1)
    (tables : TypedDeclTablesV1) (callee : SourceNameComponentV1) :
    Except DiagnosticV1 FnDeclV1 :=
  match isLocalOrParam scope callee with
  | some .local => .error (localAsFunctionDiagnostic callee "local")
  | some .param => .error (localAsFunctionDiagnostic callee "parameter")
  | _ =>
      if let some (_, decl) := tables.fn.find? callee then
        .ok decl
      else
        match findFirstMatchingKind tables callee with
        | some (kind, _) => .error (wrongCategoryDiagnostic callee kind "function")
        | none => .error (unknownNameDiagnostic callee "function")

private def addBindings (scope : TypeCheckScopeV1)
    (bindings : List (SourceNameComponentV1 × TypeV1)) : TypeCheckScopeV1 :=
  bindings.foldl (fun acc (name, type_) => addBinding acc name type_) scope

/-- Binding-origin path for a bare name in scope (state/const only). -/
def bindingOriginPath? (tables : TypedDeclTablesV1) (scope : TypeCheckScopeV1)
    (name : SourceNameComponentV1) : Option NormalizedSyntacticPathV1 :=
  match lookupBinding scope name with
  | some (_, .state) => itemPathForNamed? tables .state name
  | some (_, .const) => itemPathForNamed? tables .const name
  | _ => none

partial def typeCheckPatternDrafts (tables : TypedDeclTablesV1)
    (scrutineeType : TypeV1)
    (patternPath? : Option NormalizedSyntacticPathV1)
    (pattern : PatternV1) : PatternCheckResultDraftV1 :=
  match pattern with
  | .wildcard => patternResultDraft [] #[]
  | .bind name => patternResultDraft [(name, scrutineeType)] #[]
  | .literal (.bool _) =>
      if scrutineeType == .bool then
        patternResultDraft [] #[]
      else
        patternResultDraft [] #[locateDraft
          (expectedActualDiagnosticDraft "Bool" (typeName scrutineeType))
          patternPath? #[] ]
  | .literal (.integer magnitude) =>
      if isIntegerType scrutineeType then
        match integerLiteralBound scrutineeType false with
        | some bound =>
            if magnitude <= bound then
              patternResultDraft [] #[]
            else
              patternResultDraft [] #[locateDraft
                (integerLiteralDiagnosticDraft scrutineeType magnitude false)
                patternPath? #[] ]
        | none =>
            patternResultDraft [] #[locateDraft
              (expectedActualDiagnosticDraft (typeName scrutineeType) "integer literal")
              patternPath? #[] ]
      else
        patternResultDraft [] #[locateDraft
          (expectedActualDiagnosticDraft (typeName scrutineeType) "integer literal")
          patternPath? #[] ]
  | .literal (.string _) =>
      if scrutineeType == .string then
        patternResultDraft [] #[]
      else
        patternResultDraft [] #[locateDraft
          (stringPatternOnNonStringDiagnosticDraft (typeName scrutineeType))
          patternPath? #[] ]
  | .constructor ctor args =>
      match resolveConstructorType tables ctor (some scrutineeType) with
      | .error diag =>
          patternResultDraft [] #[draftFromDiag diag patternPath?
            (constructorRelatedPaths tables ctor .unit)]
      | .ok (ctorResultType, expectedTypes) =>
          let relatedCtor := constructorRelatedPaths tables ctor ctorResultType
          let typeDiag :=
            if ctorResultType != scrutineeType then
              #[locateDraft
                (expectedActualDiagnosticDraft (typeName scrutineeType)
                  (typeName ctorResultType))
                patternPath? relatedCtor]
            else #[]
          let arityDiag :=
            if expectedTypes.size != args.size then
              #[locateDraft
                (expectedActualDiagnosticDraft
                  s!"{expectedTypes.size} constructor arguments"
                  s!"{args.size} constructor arguments")
                patternPath? relatedCtor]
            else #[]
          let baseDiags := typeDiag ++ arityDiag
          let (bindings, subDiags) := (List.range args.size).foldl
            (fun (bs, ds) i =>
              match args[i]? with
              | none => (bs, ds)
              | some sub =>
                let (ap?, pathDs) :=
                  resolveChild patternPath? "Pattern.Constructor" "args" i
                let expectedType? :=
                  if i < expectedTypes.size then some expectedTypes[i]! else none
                let subRes :=
                  match expectedType? with
                  | some expectedType =>
                      typeCheckPatternDrafts tables expectedType ap? sub
                  | none =>
                      typeCheckPatternDrafts tables .unit ap? sub
                (bs ++ subRes.bindings, ds ++ pathDs ++ subRes.drafts))
            ([], #[])
          patternResultDraft bindings (baseDiags ++ subDiags)

def typeCheckPattern (tables : TypedDeclTablesV1)
    (scrutineeType : TypeV1) (pattern : PatternV1) : PatternCheckResultV1 :=
  let r := typeCheckPatternDrafts tables scrutineeType none pattern
  { bindings := r.bindings, diagnostics := eraseArray r.drafts }

private def isCatchAll : PatternV1 → Bool
  | .wildcard | .bind _ => true
  | _ => false

private def coveredEnumVariant (tables : TypedDeclTablesV1)
    (enumName : SourceNameComponentV1) (pattern : PatternV1) :
    Option SourceNameComponentV1 :=
  match pattern with
  | .constructor ctor _ =>
      match resolveConstructorType tables ctor with
      | .ok (.named name, _) =>
          if name == enumName then
            let comps := ctor.components.toArray
            comps[comps.size - 1]?
          else none
      | _ => none
  | _ => none

def checkExhaustivenessDrafts (tables : TypedDeclTablesV1) (scrutineeType : TypeV1)
    (patterns : Array PatternV1)
    (matchPath? : Option NormalizedSyntacticPathV1) :
    Array TypedDiagnosticDraftV1 :=
  if patterns.any isCatchAll then #[]
  else
    match scrutineeType with
    | .named enumName =>
        match tables.enum.find? enumName with
        | some (_, enumDecl) =>
            let covered := patterns.foldl (fun acc p =>
              match coveredEnumVariant tables enumName p with
              | some v => acc.push v
              | none => acc) #[]
            let coveredList := covered.toList
            let missing := enumDecl.variants.filter (fun v => !coveredList.contains v.name)
            if missing.isEmpty then #[]
            else
              let related := optRelatedPath (itemPathForNamed? tables .enum enumName)
              #[locateDraft
                (nonExhaustiveDiagnosticDraft (missing.map (·.name.raw)).toList)
                matchPath? related]
        | none =>
            #[locateDraft (nonExhaustiveDiagnosticDraft []) matchPath? #[]]
    | _ =>
        #[locateDraft (nonExhaustiveDiagnosticDraft []) matchPath? #[]]

def checkExhaustiveness (tables : TypedDeclTablesV1) (scrutineeType : TypeV1)
    (patterns : Array PatternV1) : Array DiagnosticV1 :=
  eraseArray (checkExhaustivenessDrafts tables scrutineeType patterns none)

mutual
  partial def typeCheckPlaceDrafts (scope : TypeCheckScopeV1)
      (tables : TypedDeclTablesV1)
      (placePath? : Option NormalizedSyntacticPathV1)
      (place : PlaceV1) : TypeCheckResultDraftV1 :=
    match place with
    | .name name =>
        match lookupBinding scope name with
        | some (type_, _) =>
            resultDraft type_ #[] (bindingOriginPath? tables scope name)
        | none =>
            resultDraft .unit #[locateDraft
              (expectedActualDiagnosticDraft "binding in scope"
                (s!"unknown name '{renderSourceNameComponentV1 name}'"))
              placePath? #[]]
    | .field base field =>
        -- N5: sole ContextRead surface types as UInt64 (wire catalog shape).
        -- Enclosing `typeCheckExpr` applies the expected-type check.
        if isContextUnixTimeSecondsPlaceV1 (.field base field) then
          resultDraft (.uint 64) #[] none
        else
          let (bp?, pathDs) := resolveDirect placePath? "Place.Field" "base"
          let baseRes := typeCheckPlaceDrafts scope tables bp? base
          if !baseRes.drafts.isEmpty then
            resultDraft baseRes.type (pathDs ++ baseRes.drafts) none
          else
            match baseRes.type with
            | .named structName =>
                match tables.struct.find? structName with
                | some structDecl =>
                    match structDecl.2.fields.find? (fun f => f.name == field) with
                    | some fieldDecl =>
                        let origin? := structFieldPath? tables structName field
                        resultDraft fieldDecl.type_ pathDs origin?
                    | none =>
                        let related :=
                          optRelatedPath (itemPathForNamed? tables .struct structName)
                        resultDraft .unit (pathDs ++ #[locateDraft
                          (expectedActualDiagnosticDraft
                            (s!"field '{renderSourceNameComponentV1 field}' of {typeName baseRes.type}")
                            (typeName baseRes.type))
                          placePath? related])
                | none =>
                    resultDraft .unit (pathDs ++ #[locateDraft
                      (expectedActualDiagnosticDraft "struct type" (typeName baseRes.type))
                      placePath? #[]])
            | other =>
                resultDraft .unit (pathDs ++ #[locateDraft
                  (expectedActualDiagnosticDraft "struct type" (typeName other))
                  placePath? #[]])
    | .index base idx =>
        let (bp?, pathDs1) := resolveDirect placePath? "Place.Index" "base"
        let (ip?, pathDs2) := resolveDirect placePath? "Place.Index" "index"
        let pathDs := pathDs1 ++ pathDs2
        let baseRes := typeCheckPlaceDrafts scope tables bp? base
        if !baseRes.drafts.isEmpty then
          resultDraft baseRes.type (pathDs ++ baseRes.drafts) none
        else
          match baseRes.type with
          | .array elem _ =>
              let idxRes := typeCheckExprDrafts scope tables (some (.uint 32)) #[] ip? idx
              let drafts := pathDs ++ baseRes.drafts ++ idxRes.drafts
              if idxRes.type == .uint 32 then
                resultDraft elem drafts none
              else
                resultDraft elem (drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft "UInt32" (typeName idxRes.type))
                  ip? #[]])
          | .bytes _ =>
              -- Rvalue Bytes index → UInt8 (wire IndexGet Bytes result).
              let idxRes := typeCheckExprDrafts scope tables (some (.uint 32)) #[] ip? idx
              let drafts := pathDs ++ baseRes.drafts ++ idxRes.drafts
              if idxRes.type == .uint 32 then
                resultDraft (.uint 8) drafts none
              else
                resultDraft (.uint 8) (drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft "UInt32" (typeName idxRes.type))
                  ip? #[]])
          | .map key value =>
              let idxRes := typeCheckExprDrafts scope tables (some key) #[] ip? idx
              let drafts := pathDs ++ baseRes.drafts ++ idxRes.drafts
              if idxRes.type == key then
                resultDraft (TypeV1.option value) drafts none
              else
                resultDraft (TypeV1.option value) (drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft (typeName key) (typeName idxRes.type))
                  ip? #[]])
          | other =>
              resultDraft .unit (pathDs ++ #[locateDraft
                (expectedActualDiagnosticDraft "Array, Bytes, or Map" (typeName other))
                placePath? #[]])

  partial def typeCheckExprDrafts (scope : TypeCheckScopeV1)
      (tables : TypedDeclTablesV1) (expected? : Option TypeV1)
      (expectedRelated : Array NormalizedSyntacticPathV1)
      (exprPath? : Option NormalizedSyntacticPathV1)
      (expr : ExprV1) : TypeCheckResultDraftV1 :=
    match expr with
    | .literal (.bool _) =>
        let (type_, drafts) :=
          checkExpectedDraft .bool expected? exprPath? expectedRelated #[]
        resultDraft type_ drafts
    | .literal (.integer magnitude) =>
        match expected? with
        | none =>
            resultDraft .unit #[locateDraft
              (expectedActualDiagnosticDraft "integer type" "integer literal")
              exprPath? expectedRelated]
        | some expected =>
            if isIntegerType expected then
              match integerLiteralBound expected false with
              | some bound =>
                  if magnitude <= bound then
                    resultDraft expected #[]
                  else
                    resultDraft expected #[locateDraft
                      (integerLiteralDiagnosticDraft expected magnitude false)
                      exprPath? expectedRelated]
              | none =>
                  resultDraft expected #[locateDraft
                    (expectedActualDiagnosticDraft (typeName expected) "integer literal")
                    exprPath? expectedRelated]
            else
              resultDraft expected #[locateDraft
                (expectedActualDiagnosticDraft (typeName expected) "integer literal")
                exprPath? expectedRelated]
    | .literal (.string _) =>
        match expected? with
        | none =>
            -- Intrinsic type of a string literal is String (N4).
            resultDraft .string #[]
        | some expected =>
            if expected == .string then
              resultDraft .string #[]
            else
              resultDraft expected #[locateDraft
                (expectedActualDiagnosticDraft (typeName expected) "String")
                exprPath? expectedRelated]
    | .place p =>
        let (pp?, pathDs) := resolveDirect exprPath? "Expr.Place" "place"
        let pRes := typeCheckPlaceDrafts scope tables pp? p
        let related :=
          if expectedRelated.isEmpty then
            optRelatedPath pRes.originPath?
          else expectedRelated
        let (type_, drafts) :=
          checkExpectedDraft pRes.type expected? exprPath? related (pathDs ++ pRes.drafts)
        resultDraft type_ drafts pRes.originPath?
    | .unary .neg (.literal (.integer magnitude)) =>
        match expected? with
        | none =>
            resultDraft .unit #[locateDraft
              (expectedActualDiagnosticDraft "integer type" "integer literal")
              exprPath? expectedRelated]
        | some expected =>
            if isIntegerType expected then
              match expected with
              | .uint _ =>
                  if magnitude == 0 then
                    resultDraft expected #[]
                  else
                    resultDraft expected #[locateDraft
                      (integerLiteralDiagnosticDraft expected magnitude true)
                      exprPath? expectedRelated]
              | _ =>
                  match integerLiteralBound expected true with
                  | some bound =>
                      if magnitude <= bound then
                        resultDraft expected #[]
                      else
                        resultDraft expected #[locateDraft
                          (integerLiteralDiagnosticDraft expected magnitude true)
                          exprPath? expectedRelated]
                  | none =>
                      resultDraft expected #[locateDraft
                        (expectedActualDiagnosticDraft (typeName expected) "integer literal")
                        exprPath? expectedRelated]
            else
              resultDraft expected #[locateDraft
                (expectedActualDiagnosticDraft (typeName expected) "integer literal")
                exprPath? expectedRelated]
    | .unary .bitNot (.literal (.integer magnitude)) =>
        match expected? with
        | none =>
            resultDraft .unit #[locateDraft
              (expectedActualDiagnosticDraft "integer type" "integer literal")
              exprPath? expectedRelated]
        | some expected =>
            if isIntegerType expected then
              match integerLiteralBound expected false with
              | some bound =>
                  if magnitude <= bound then
                    resultDraft expected #[]
                  else
                    resultDraft expected #[locateDraft
                      (integerLiteralDiagnosticDraft expected magnitude false)
                      exprPath? expectedRelated]
              | none =>
                  resultDraft expected #[locateDraft
                    (expectedActualDiagnosticDraft (typeName expected) "integer literal")
                    exprPath? expectedRelated]
            else
              resultDraft expected #[locateDraft
                (expectedActualDiagnosticDraft (typeName expected) "integer literal")
                exprPath? expectedRelated]
    | .unary op operand =>
        let (opPath?, pathDs) := resolveDirect exprPath? "Expr.Unary" "operand"
        match op with
        | .neg =>
            -- Integer or Field (bn254_fr); Field maps to Op.Unary.neg mod p.
            let opRes := typeCheckExprDrafts scope tables none #[] opPath? operand
            let (resType, drafts) :=
              if isNumericType opRes.type then
                (opRes.type, pathDs ++ opRes.drafts)
              else
                (opRes.type, pathDs ++ opRes.drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft "integer or Field type"
                    (typeName opRes.type))
                  opPath? #[]])
            let (type_, drafts) :=
              checkExpectedDraft resType expected? exprPath? expectedRelated drafts
            resultDraft type_ drafts
        | .bitNot =>
            -- Bitwise not remains integer-only (Field has no bitNot).
            let opRes := typeCheckExprDrafts scope tables none #[] opPath? operand
            let (resType, drafts) :=
              if isIntegerType opRes.type then
                (opRes.type, pathDs ++ opRes.drafts)
              else
                (opRes.type, pathDs ++ opRes.drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft "integer type" (typeName opRes.type))
                  opPath? #[]])
            let (type_, drafts) :=
              checkExpectedDraft resType expected? exprPath? expectedRelated drafts
            resultDraft type_ drafts
        | .not =>
            let opRes := typeCheckExprDrafts scope tables (some .bool) #[] opPath? operand
            let drafts :=
              if opRes.type == .bool then
                pathDs ++ opRes.drafts
              else
                pathDs ++ opRes.drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft "Bool" (typeName opRes.type))
                  opPath? #[]]
            let (type_, drafts) :=
              checkExpectedDraft .bool expected? exprPath? expectedRelated drafts
            resultDraft type_ drafts
    | .binary op lhs rhs =>
        let (lp?, pathDs1) := resolveDirect exprPath? "Expr.Binary" "lhs"
        let (rp?, pathDs2) := resolveDirect exprPath? "Expr.Binary" "rhs"
        let pathDs := pathDs1 ++ pathDs2
        if isArithmeticOp op then
          -- Integer: full add/sub/mul/div/mod. Field bn254_fr: add/sub/mul/div
          -- only (mod → invalidCore / fail closed at Normalize; reject here).
          let lhsExpected? :=
            expected?.filter fun t => isIntegerType t || isFieldType t
          let lhsRes := typeCheckExprDrafts scope tables lhsExpected? expectedRelated lp? lhs
          let (drafts, lhsType) :=
            if isNumericType lhsRes.type then
              if isFieldType lhsRes.type && op == .mod then
                (pathDs ++ lhsRes.drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft "integer type"
                    "Field mod (no field remainder)")
                  lp? #[]], lhsRes.type)
              else
                (pathDs ++ lhsRes.drafts, lhsRes.type)
            else
              (pathDs ++ lhsRes.drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft "integer or Field type"
                  (typeName lhsRes.type))
                lp? #[]], lhsRes.type)
          let rhsRes := typeCheckExprDrafts scope tables (some lhsType) #[] rp? rhs
          let (drafts, resType) :=
            if lhsType == rhsRes.type then
              (drafts ++ rhsRes.drafts, lhsType)
            else
              (drafts ++ rhsRes.drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft (typeName lhsType) (typeName rhsRes.type))
                rp? #[]], lhsType)
          let (type_, drafts) :=
            checkExpectedDraft resType expected? exprPath? expectedRelated drafts
          resultDraft type_ drafts
        else if isBitwiseOp op then
          -- Bitwise remains integer-only.
          let lhsExpected? := expected?.filter isIntegerType
          let lhsRes := typeCheckExprDrafts scope tables lhsExpected? expectedRelated lp? lhs
          let (drafts, lhsType) :=
            if isIntegerType lhsRes.type then
              (pathDs ++ lhsRes.drafts, lhsRes.type)
            else
              (pathDs ++ lhsRes.drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft "integer type" (typeName lhsRes.type))
                lp? #[]], lhsRes.type)
          let rhsRes := typeCheckExprDrafts scope tables (some lhsType) #[] rp? rhs
          let (drafts, resType) :=
            if lhsType == rhsRes.type then
              (drafts ++ rhsRes.drafts, lhsType)
            else
              (drafts ++ rhsRes.drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft (typeName lhsType) (typeName rhsRes.type))
                rp? #[]], lhsType)
          let (type_, drafts) :=
            checkExpectedDraft resType expected? exprPath? expectedRelated drafts
          resultDraft type_ drafts
        else if isShiftOp op then
          let lhsExpected? := expected?.filter isIntegerType
          let lhsRes := typeCheckExprDrafts scope tables lhsExpected? expectedRelated lp? lhs
          let (drafts, lhsType) :=
            if isIntegerType lhsRes.type then
              (pathDs ++ lhsRes.drafts, lhsRes.type)
            else
              (pathDs ++ lhsRes.drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft "integer type" (typeName lhsRes.type))
                lp? #[]], lhsRes.type)
          let rhsRes := typeCheckExprDrafts scope tables (some (.uint 32)) #[] rp? rhs
          let drafts := drafts ++ rhsRes.drafts
          let drafts :=
            if rhsRes.type == .uint 32 then
              drafts
            else
              drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft "UInt32" (typeName rhsRes.type))
                rp? #[]]
          let drafts :=
            match lhsType, rhs with
            | .uint w, .literal (.integer magnitude) =>
                if magnitude < w.toNat then drafts
                else drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft
                    s!"shift count < {w.toNat}" s!"shift count {magnitude}")
                  rp? #[]]
            | .int w, .literal (.integer magnitude) =>
                if magnitude < w.toNat then drafts
                else drafts ++ #[locateDraft
                  (expectedActualDiagnosticDraft
                    s!"shift count < {w.toNat}" s!"shift count {magnitude}")
                  rp? #[]]
            | _, _ => drafts
          let (type_, drafts) :=
            checkExpectedDraft lhsType expected? exprPath? expectedRelated drafts
          resultDraft type_ drafts
        else if isEqualityOp op then
          let lhsRes := typeCheckExprDrafts scope tables none #[] lp? lhs
          let rhsRes := typeCheckExprDrafts scope tables (some lhsRes.type) #[] rp? rhs
          let drafts := pathDs ++ lhsRes.drafts ++ rhsRes.drafts
          let drafts :=
            if lhsRes.type == rhsRes.type then
              drafts
            else
              drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft (typeName lhsRes.type) (typeName rhsRes.type))
                rp? #[]]
          let (type_, drafts) :=
            checkExpectedDraft .bool expected? exprPath? expectedRelated drafts
          resultDraft type_ drafts
        else if isComparisonOp op then
          let lhsRes := typeCheckExprDrafts scope tables none #[] lp? lhs
          let (drafts, lhsType) :=
            if isIntegerType lhsRes.type then
              (pathDs ++ lhsRes.drafts, lhsRes.type)
            else
              (pathDs ++ lhsRes.drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft "integer type" (typeName lhsRes.type))
                lp? #[]], lhsRes.type)
          let rhsRes := typeCheckExprDrafts scope tables (some lhsType) #[] rp? rhs
          let (drafts, resType) :=
            if isIntegerType lhsType && lhsType == rhsRes.type then
              (drafts ++ rhsRes.drafts, .bool)
            else
              (drafts ++ rhsRes.drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft (typeName lhsType) (typeName rhsRes.type))
                rp? #[]], .bool)
          let (type_, drafts) :=
            checkExpectedDraft resType expected? exprPath? expectedRelated drafts
          resultDraft type_ drafts
        else if isLogicalOp op then
          let lhsRes := typeCheckExprDrafts scope tables (some .bool) #[] lp? lhs
          let rhsRes := typeCheckExprDrafts scope tables (some .bool) #[] rp? rhs
          let drafts := pathDs ++ lhsRes.drafts ++ rhsRes.drafts
          let drafts :=
            if lhsRes.type == .bool && rhsRes.type == .bool then
              drafts
            else
              let lhsDiag := if lhsRes.type == .bool then #[] else
                #[locateDraft (expectedActualDiagnosticDraft "Bool" (typeName lhsRes.type))
                  lp? #[]]
              let rhsDiag := if rhsRes.type == .bool then #[] else
                #[locateDraft (expectedActualDiagnosticDraft "Bool" (typeName rhsRes.type))
                  rp? #[]]
              drafts ++ lhsDiag ++ rhsDiag
          let (type_, drafts) :=
            checkExpectedDraft .bool expected? exprPath? expectedRelated drafts
          resultDraft type_ drafts
        else
          resultDraft .unit #[locateDraft
            (expectedActualDiagnosticDraft (typeName (expected?.getD .unit))
              "binary expression")
            exprPath? expectedRelated]
    | .constructor ctor args =>
        let pathRes := resolveConstructorType tables ctor expected?
        match pathRes with
        | .error diag =>
            let (argDrafts, pathDs) := args.zipIdx.foldl
              (fun (acc, pds) (arg, i) =>
                let (ap?, pd) := resolveChild exprPath? "Expr.Constructor" "args" i
                let ar := typeCheckExprDrafts scope tables none #[] ap? arg
                (acc ++ ar.drafts, pds ++ pd))
              (#[], #[])
            resultDraft (expected?.getD .unit)
              (pathDs ++ #[draftFromDiag diag exprPath? #[]] ++ argDrafts)
        | .ok (resType, expectedTypes) =>
            let relatedCtor := constructorRelatedPaths tables ctor resType
            let drafts : Array TypedDiagnosticDraftV1 := #[]
            let drafts :=
              if expectedTypes.size == args.size then drafts
              else drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft
                  s!"{expectedTypes.size} constructor arguments"
                  s!"{args.size} constructor arguments")
                exprPath? relatedCtor]
            -- Arity mismatch: only the arity locateDraft (no arg walk). Resolve-error
            -- and matching-arity paths still walk args; revert/emit keep their walks.
            let (argDrafts, pathDs) :=
              if expectedTypes.size == args.size then
                (expectedTypes.zip args).zipIdx.foldl
                  (fun (acc, pds) ((expectedType, arg), i) =>
                    let (ap?, pd) := resolveChild exprPath? "Expr.Constructor" "args" i
                    let argRelated :=
                      constructorArgRelatedPaths tables ctor resType i
                    let ar := typeCheckExprDrafts scope tables (some expectedType)
                      argRelated ap? arg
                    (acc ++ ar.drafts, pds ++ pd))
                  (#[], #[])
              else
                (#[], #[])
            let drafts := pathDs ++ drafts ++ argDrafts
            let (type_, drafts) :=
              checkExpectedDraft resType expected? exprPath? expectedRelated drafts
            resultDraft type_ drafts
    | .localCall callee args =>
        -- N5: intrinsic `commit(x)` when no user `fn commit` — result type =
        -- operand type (label-only identity; disclosure is a separate phase).
        let noLocalShadow :=
          match isLocalOrParam scope callee with
          | some _ => false
          | none => true
        let noUserFn := (tables.fn.find? callee).isNone
        let intrinsicCommit :=
          isCommitCalleeNameV1 callee && noLocalShadow && noUserFn
        if intrinsicCommit then
          if args.size != 1 then
            resultDraft (expected?.getD .unit)
              #[locateDraft
                (expectedActualDiagnosticDraft "1 arguments" s!"{args.size} arguments")
                exprPath? #[]]
          else
            match args[0]? with
            | none =>
                resultDraft (expected?.getD .unit)
                  #[locateDraft
                    (internalDiagnosticDraft "commit missing argument")
                    exprPath? #[]]
            | some arg0 =>
                let (ap?, pathDs) := resolveChild exprPath? "Expr.LocalCall" "args" 0
                -- Operand type is free; result must match expected if present.
                let ar := typeCheckExprDrafts scope tables expected? expectedRelated ap? arg0
                resultDraft ar.type (pathDs ++ ar.drafts) none
        else match resolveLocalCallType scope tables callee with
        | .error diag =>
            let (argDrafts, pathDs) := args.zipIdx.foldl
              (fun (acc, pds) (arg, i) =>
                let (ap?, pd) := resolveChild exprPath? "Expr.LocalCall" "args" i
                let ar := typeCheckExprDrafts scope tables none #[] ap? arg
                (acc ++ ar.drafts, pds ++ pd))
              (#[], #[])
            let related := optRelatedPath (itemPathForNamed? tables .fn callee)
            resultDraft (expected?.getD .unit)
              (pathDs ++ #[draftFromDiag diag exprPath? related] ++ argDrafts)
        | .ok fnDecl =>
            let relatedFn := optRelatedPath (itemPathForNamed? tables .fn callee)
            let drafts : Array TypedDiagnosticDraftV1 := #[]
            let drafts :=
              if fnDecl.params.size == args.size then drafts
              else drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft
                  s!"{fnDecl.params.size} arguments" s!"{args.size} arguments")
                exprPath? relatedFn]
            -- Arity mismatch: only the arity locateDraft (no arg walk).
            let (argDrafts, pathDs) :=
              if fnDecl.params.size == args.size then
                (fnDecl.params.zip args).zipIdx.foldl
                  (fun (acc, pds) ((param, arg), i) =>
                    let (ap?, pd) := resolveChild exprPath? "Expr.LocalCall" "args" i
                    let argRelated := optRelatedPath (fnParamPath? tables callee i)
                    let ar := typeCheckExprDrafts scope tables (some param.type_)
                      argRelated ap? arg
                    (acc ++ ar.drafts, pds ++ pd))
                  (#[], #[])
              else
                (#[], #[])
            let drafts := pathDs ++ drafts ++ argDrafts
            let (type_, drafts) :=
              checkExpectedDraft fnDecl.result expected? exprPath? expectedRelated drafts
            resultDraft type_ drafts
    | .match_ scrutinee arms =>
        match arms.toList with
        | [] =>
            resultDraft (expected?.getD .unit)
              #[locateDraft (internalDiagnosticDraft "empty match expression")
                exprPath? #[]]
        | firstArm :: restArms =>
            let (sp?, pathDs0) := resolveDirect exprPath? "Expr.Match" "scrutinee"
            let scrutineeRes :=
              typeCheckExprDrafts scope tables none #[] sp? scrutinee
            let scrutineeType := scrutineeRes.type
            let (arm0?, pathDs1) := resolveChild exprPath? "Expr.Match" "arms" 0
            let (pp0?, pathDs2) := resolveDirect arm0? "ExprMatchArm" "pattern"
            let (vp0?, pathDs3) := resolveDirect arm0? "ExprMatchArm" "value"
            let firstPatternRes :=
              typeCheckPatternDrafts tables scrutineeType pp0? firstArm.pattern
            let firstArmScope := addBindings scope firstPatternRes.bindings
            let firstValueRes :=
              typeCheckExprDrafts firstArmScope tables expected? expectedRelated
                vp0? firstArm.value
            let firstArmType := firstValueRes.type
            let (restDrafts, _) := restArms.foldl
              (fun (acc, i) arm =>
                let (armP?, pd1) := resolveChild exprPath? "Expr.Match" "arms" i
                let (pp?, pd2) := resolveDirect armP? "ExprMatchArm" "pattern"
                let (vp?, pd3) := resolveDirect armP? "ExprMatchArm" "value"
                let patternRes :=
                  typeCheckPatternDrafts tables scrutineeType pp? arm.pattern
                let armScope := addBindings scope patternRes.bindings
                let valueRes :=
                  typeCheckExprDrafts armScope tables expected? expectedRelated
                    vp? arm.value
                let typeDiag :=
                  if valueRes.type == firstArmType then #[]
                  else #[locateDraft
                    (armTypeMismatchDiagnosticDraft i (typeName firstArmType)
                      (typeName valueRes.type))
                    vp? #[]]
                (acc ++ pd1 ++ pd2 ++ pd3 ++ patternRes.drafts ++ valueRes.drafts ++
                  typeDiag, i + 1))
              (#[], 1)
            let armDrafts := pathDs0 ++ pathDs1 ++ pathDs2 ++ pathDs3 ++
              scrutineeRes.drafts ++ firstPatternRes.drafts ++
              firstValueRes.drafts ++ restDrafts
            let exhaustDrafts :=
              checkExhaustivenessDrafts tables scrutineeType (arms.map (·.pattern))
                exprPath?
            let dupDrafts :=
              checkDuplicatePatternsDrafts (arms.map (·.pattern)) exprPath?
            let (type_, drafts) :=
              checkExpectedDraft firstArmType expected? exprPath? expectedRelated
                armDrafts
            resultDraft type_ (drafts ++ exhaustDrafts ++ dupDrafts)
end

def typeCheckPlace (scope : TypeCheckScopeV1)
    (tables : TypedDeclTablesV1) (place : PlaceV1) : TypeCheckResultV1 :=
  eraseResult (typeCheckPlaceDrafts scope tables none place)

def typeCheckExpr (scope : TypeCheckScopeV1)
    (tables : TypedDeclTablesV1) (expected? : Option TypeV1) (expr : ExprV1) :
    TypeCheckResultV1 :=
  eraseResult (typeCheckExprDrafts scope tables expected? #[] none expr)

/-- Assign-target place typing (MapBytesAssign / N-A3).

    Wire IndexSet uses the element/slot type, not the IndexGet result type:
      * Array index assign → element type (same as rvalue)
      * Bytes index assign → UInt8 (same as rvalue)
      * Map index assign → value type (rvalue Map index is `Option V`)

    Only the outermost place constructor is special-cased when it is `.index`.
    Nested field/index chains still use ordinary rvalue place typing, so
    `m[k].x := v` stays fail closed (field on Option). Bases of an outermost
    index (including `s.m[k]`) are typed as ordinary places. -/
partial def typeCheckAssignTargetDrafts (scope : TypeCheckScopeV1)
    (tables : TypedDeclTablesV1)
    (placePath? : Option NormalizedSyntacticPathV1)
    (place : PlaceV1) : TypeCheckResultDraftV1 :=
  match place with
  | .index base idx =>
      let (bp?, pathDs1) := resolveDirect placePath? "Place.Index" "base"
      let (ip?, pathDs2) := resolveDirect placePath? "Place.Index" "index"
      let pathDs := pathDs1 ++ pathDs2
      let baseRes := typeCheckPlaceDrafts scope tables bp? base
      if !baseRes.drafts.isEmpty then
        resultDraft baseRes.type (pathDs ++ baseRes.drafts) none
      else
        match baseRes.type with
        | .array elem _ =>
            let idxRes := typeCheckExprDrafts scope tables (some (.uint 32)) #[] ip? idx
            let drafts := pathDs ++ baseRes.drafts ++ idxRes.drafts
            if idxRes.type == .uint 32 then
              resultDraft elem drafts none
            else
              resultDraft elem (drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft "UInt32" (typeName idxRes.type))
                ip? #[]])
        | .bytes _ =>
            let idxRes := typeCheckExprDrafts scope tables (some (.uint 32)) #[] ip? idx
            let drafts := pathDs ++ baseRes.drafts ++ idxRes.drafts
            if idxRes.type == .uint 32 then
              resultDraft (.uint 8) drafts none
            else
              resultDraft (.uint 8) (drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft "UInt32" (typeName idxRes.type))
                ip? #[]])
        | .map key value =>
            let idxRes := typeCheckExprDrafts scope tables (some key) #[] ip? idx
            let drafts := pathDs ++ baseRes.drafts ++ idxRes.drafts
            if idxRes.type == key then
              resultDraft value drafts none
            else
              resultDraft value (drafts ++ #[locateDraft
                (expectedActualDiagnosticDraft (typeName key) (typeName idxRes.type))
                ip? #[]])
        | other =>
            resultDraft .unit (pathDs ++ #[locateDraft
              (expectedActualDiagnosticDraft "Array, Bytes, or Map" (typeName other))
              placePath? #[]])
  | _ =>
      typeCheckPlaceDrafts scope tables placePath? place

def scopeFromTables (tables : TypedDeclTablesV1) : TypeCheckScopeV1 :=
  let base := emptyScope
  let base := tables.state.entries.foldl
    (fun acc (n, _, d) => addStateConst acc n d.type_ .state) base
  tables.const.entries.foldl
    (fun acc (n, _, d) => addStateConst acc n d.type_ .const) base

def scopeFromCallable (tables : TypedDeclTablesV1)
    (name : SourceNameComponentV1) : Except String TypeCheckScopeV1 := do
  let params ←
    if let some decl := tables.fn.find? name then
      pure decl.2.params
    else if let some decl := tables.entry.find? name then
      pure decl.2.params
    else if let some decl := tables.view.find? name then
      pure decl.2.params
    else
      .error s!"no callable named '{renderSourceNameComponentV1 name}'"
  let base := scopeFromTables tables
  let base := params.foldl (fun acc p => addParam acc p.name p.type_) base
  pure base

structure TypeCheckProgramResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  deriving Repr, Inhabited

structure TypeCheckProgramDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
  deriving Inhabited

private def resultRequiredDiagnosticDraft (expected : TypeV1) :
    TypedDiagnosticDraftV1 :=
  expectedActualDiagnosticDraft (typeName expected) "empty return"

private def resultRequiredDiagnostic (expected : TypeV1) : DiagnosticV1 :=
  erase (resultRequiredDiagnosticDraft expected)

mutual
  partial def typeCheckStmtDrafts (scope : TypeCheckScopeV1)
      (tables : TypedDeclTablesV1) (result : TypeV1)
      (resultRelated : Array NormalizedSyntacticPathV1)
      (stmtPath? : Option NormalizedSyntacticPathV1)
      (stmt : StmtV1) :
      TypeCheckScopeV1 × Array TypedDiagnosticDraftV1 :=
    match stmt with
    | .let_ name typeAnn value =>
        let (vp?, pathDs) := resolveDirect stmtPath? "Stmt.Let" "value"
        match typeAnn with
        | some ann =>
            let valueRes :=
              typeCheckExprDrafts scope tables (some ann) #[] vp? value
            (addBinding scope name ann, pathDs ++ valueRes.drafts)
        | none =>
            let valueRes :=
              typeCheckExprDrafts scope tables none #[] vp? value
            (addBinding scope name valueRes.type, pathDs ++ valueRes.drafts)
    | .assign target value =>
        let (tp?, pathDs1) := resolveDirect stmtPath? "Stmt.Assign" "target"
        let (vp?, pathDs2) := resolveDirect stmtPath? "Stmt.Assign" "value"
        -- N-A3: Map/Bytes index assign uses IndexSet slot types (see
        -- `typeCheckAssignTargetDrafts`); rvalue places stay unchanged.
        let targetRes := typeCheckAssignTargetDrafts scope tables tp? target
        let valueExpected? :=
          if targetRes.drafts.isEmpty then some targetRes.type else none
        let valueRelated :=
          if targetRes.drafts.isEmpty then optRelatedPath targetRes.originPath? else #[]
        let valueRes :=
          typeCheckExprDrafts scope tables valueExpected? valueRelated vp? value
        let drafts := pathDs1 ++ pathDs2 ++ targetRes.drafts ++ valueRes.drafts
        let drafts :=
          if targetRes.drafts.isEmpty && targetRes.type != valueRes.type then
            drafts ++ #[locateDraft
              (expectedActualDiagnosticDraft (typeName targetRes.type)
                (typeName valueRes.type))
              vp? valueRelated]
          else
            drafts
        (scope, drafts)
    | .return_ (some value) =>
        let (vp?, pathDs) := resolveDirect stmtPath? "Stmt.Return" "value"
        let valueRes :=
          typeCheckExprDrafts scope tables (some result) resultRelated vp? value
        let drafts :=
          if valueRes.drafts.isEmpty && valueRes.type != result then
            pathDs ++ valueRes.drafts ++ #[locateDraft
              (expectedActualDiagnosticDraft (typeName result) (typeName valueRes.type))
              vp? resultRelated]
          else
            pathDs ++ valueRes.drafts
        (scope, drafts)
    | .return_ none =>
        let drafts :=
          if result == .unit then #[]
          else #[locateDraft (resultRequiredDiagnosticDraft result)
            stmtPath? resultRelated]
        (scope, drafts)
    | .assert_ condition error? =>
        let (cp?, pathDs) := resolveDirect stmtPath? "Stmt.Assert" "condition"
        let condRes := typeCheckExprDrafts scope tables (some .bool) #[] cp? condition
        let drafts :=
          if condRes.drafts.isEmpty && condRes.type != .bool then
            pathDs ++ condRes.drafts ++ #[locateDraft
              (expectedActualDiagnosticDraft "Bool" (typeName condRes.type))
              cp? #[]]
          else
            pathDs ++ condRes.drafts
        let _ := error?
        (scope, drafts)
    | .revert name args =>
        match tables.error.find? name with
        | none =>
            (scope, #[locateDraft
              (internalDiagnosticDraft
                s!"unresolved error name '{name.raw}' in revert")
              stmtPath? #[]])
        | some (_, decl) =>
            let relatedErr := optRelatedPath (itemPathForNamed? tables .error name)
            let drafts : Array TypedDiagnosticDraftV1 :=
              if decl.params.size == args.size then #[]
              else #[locateDraft
                (expectedActualDiagnosticDraft
                  s!"{decl.params.size} arguments" s!"{args.size} arguments")
                stmtPath? relatedErr]
            let (argDrafts, pathDs) :=
              if decl.params.size == args.size then
                (decl.params.zip args).zipIdx.foldl
                  (fun (acc, pds) ((param, arg), i) =>
                    let (ap?, pd) := resolveChild stmtPath? "Stmt.Revert" "args" i
                    let argRelated := optRelatedPath (errorParamPath? tables name i)
                    let ar := typeCheckExprDrafts scope tables (some param.type_)
                      argRelated ap? arg
                    (acc ++ ar.drafts, pds ++ pd))
                  (#[], #[])
              else
                args.zipIdx.foldl
                  (fun (acc, pds) (arg, i) =>
                    let (ap?, pd) := resolveChild stmtPath? "Stmt.Revert" "args" i
                    let ar := typeCheckExprDrafts scope tables none #[] ap? arg
                    (acc ++ ar.drafts, pds ++ pd))
                  (#[], #[])
            (scope, pathDs ++ drafts ++ argDrafts)
    | .emit name args =>
        match tables.event.find? name with
        | none =>
            (scope, #[locateDraft
              (internalDiagnosticDraft
                s!"unresolved event name '{name.raw}' in emit")
              stmtPath? #[]])
        | some (_, decl) =>
            let relatedEv := optRelatedPath (itemPathForNamed? tables .event name)
            let drafts : Array TypedDiagnosticDraftV1 :=
              if decl.params.size == args.size then #[]
              else #[locateDraft
                (expectedActualDiagnosticDraft
                  s!"{decl.params.size} arguments" s!"{args.size} arguments")
                stmtPath? relatedEv]
            let (argDrafts, pathDs) :=
              if decl.params.size == args.size then
                (decl.params.zip args).zipIdx.foldl
                  (fun (acc, pds) ((param, arg), i) =>
                    let (ap?, pd) := resolveChild stmtPath? "Stmt.Emit" "args" i
                    let argRelated := optRelatedPath (eventParamPath? tables name i)
                    let ar := typeCheckExprDrafts scope tables (some param.type_)
                      argRelated ap? arg
                    (acc ++ ar.drafts, pds ++ pd))
                  (#[], #[])
              else
                args.zipIdx.foldl
                  (fun (acc, pds) (arg, i) =>
                    let (ap?, pd) := resolveChild stmtPath? "Stmt.Emit" "args" i
                    let ar := typeCheckExprDrafts scope tables none #[] ap? arg
                    (acc ++ ar.drafts, pds ++ pd))
                  (#[], #[])
            (scope, pathDs ++ drafts ++ argDrafts)
    | .if_ condition thenBlock elseBlock? =>
        let (cp?, pathDs1) := resolveDirect stmtPath? "Stmt.If" "condition"
        let (tp?, pathDs2) := resolveDirect stmtPath? "Stmt.If" "thenBlock"
        let condRes := typeCheckExprDrafts scope tables (some .bool) #[] cp? condition
        let condDrafts :=
          if condRes.drafts.isEmpty && condRes.type != .bool then
            pathDs1 ++ condRes.drafts ++ #[locateDraft
              (expectedActualDiagnosticDraft "Bool" (typeName condRes.type))
              cp? #[]]
          else
            pathDs1 ++ condRes.drafts
        let thenDrafts :=
          typeCheckBlockDrafts scope tables result resultRelated tp? thenBlock
        let (elseDrafts, pathDs3) := match elseBlock? with
          | some elseBlock =>
              let (ep?, pd) := resolveDirect stmtPath? "Stmt.If" "elseBlock"
              (typeCheckBlockDrafts scope tables result resultRelated ep? elseBlock, pd)
          | none => (#[], #[])
        (scope, condDrafts ++ pathDs2 ++ thenDrafts ++ pathDs3 ++ elseDrafts)
    | .for_ binder start endExclusive _ body =>
        let (sp?, pathDs1) := resolveDirect stmtPath? "Stmt.For" "start"
        let (ep?, pathDs2) := resolveDirect stmtPath? "Stmt.For" "endExclusive"
        let (bp?, pathDs3) := resolveDirect stmtPath? "Stmt.For" "body"
        let startRes := typeCheckExprDrafts scope tables none #[] sp? start
        let (startDrafts, startType) :=
          if isIntegerType startRes.type then
            (pathDs1 ++ startRes.drafts, startRes.type)
          else
            (pathDs1 ++ startRes.drafts ++ #[locateDraft
              (expectedActualDiagnosticDraft "integer type" (typeName startRes.type))
              sp? #[]], .unit)
        let endExpected? := if startType == .unit then none else some startType
        let endRes :=
          typeCheckExprDrafts scope tables endExpected? #[] ep? endExclusive
        let endDrafts :=
          if endRes.drafts.isEmpty && !isIntegerType endRes.type then
            pathDs2 ++ endRes.drafts ++ #[locateDraft
              (expectedActualDiagnosticDraft "integer type" (typeName endRes.type))
              ep? #[]]
          else
            pathDs2 ++ endRes.drafts
        let widthDrafts :=
          if isIntegerType startRes.type && isIntegerType endRes.type &&
              startRes.type != endRes.type then
            #[locateDraft
              (expectedActualDiagnosticDraft (typeName startRes.type)
                (typeName endRes.type))
              ep? #[]]
          else
            #[]
        let iterType := if isIntegerType startType then startType else .unit
        let bodyDrafts :=
          typeCheckBlockDrafts (addBinding scope binder iterType) tables
            result resultRelated bp? body
        (scope, startDrafts ++ endDrafts ++ widthDrafts ++ pathDs3 ++ bodyDrafts)
    | .call externalCall =>
        let (cp?, pathDs0) := resolveDirect stmtPath? "Stmt.Call" "call"
        let (argDrafts, pathDs) := externalCall.args.zipIdx.foldl
          (fun (acc, pds) (arg, i) =>
            let (ap?, pd) := resolveChild cp? "ExternalCallExpr" "args" i
            let ar := typeCheckExprDrafts scope tables none #[] ap? arg
            (acc ++ ar.drafts, pds ++ pd))
          (#[], #[])
        (scope, pathDs0 ++ pathDs ++ argDrafts)
    | .schedule externalCall =>
        let (cp?, pathDs0) := resolveDirect stmtPath? "Stmt.Schedule" "call"
        let (argDrafts, pathDs) := externalCall.args.zipIdx.foldl
          (fun (acc, pds) (arg, i) =>
            let (ap?, pd) := resolveChild cp? "ExternalCallExpr" "args" i
            let ar := typeCheckExprDrafts scope tables none #[] ap? arg
            (acc ++ ar.drafts, pds ++ pd))
          (#[], #[])
        (scope, pathDs0 ++ pathDs ++ argDrafts)
    | .match_ scrutinee arms =>
        let (sp?, pathDs0) := resolveDirect stmtPath? "Stmt.Match" "scrutinee"
        let scrutineeRes :=
          typeCheckExprDrafts scope tables none #[] sp? scrutinee
        let scrutineeType := scrutineeRes.type
        let (armDrafts, pathDsArms) := arms.zipIdx.foldl
          (fun (acc, pds) (arm, i) =>
            let (armP?, pd1) := resolveChild stmtPath? "Stmt.Match" "arms" i
            let (pp?, pd2) := resolveDirect armP? "StmtMatchArm" "pattern"
            let (bp?, pd3) := resolveDirect armP? "StmtMatchArm" "body"
            let patternRes :=
              typeCheckPatternDrafts tables scrutineeType pp? arm.pattern
            let armScope := addBindings scope patternRes.bindings
            let bodyDrafts :=
              typeCheckBlockDrafts armScope tables result resultRelated bp? arm.body
            (acc ++ patternRes.drafts ++ bodyDrafts,
              pds ++ pd1 ++ pd2 ++ pd3))
          (#[], #[])
        let exhaustDrafts :=
          checkExhaustivenessDrafts tables scrutineeType (arms.map (·.pattern))
            stmtPath?
        let dupDrafts :=
          checkDuplicatePatternsDrafts (arms.map (·.pattern)) stmtPath?
        (scope, pathDs0 ++ scrutineeRes.drafts ++ pathDsArms ++ armDrafts ++
          exhaustDrafts ++ dupDrafts)

  partial def typeCheckBlockDrafts (scope : TypeCheckScopeV1)
      (tables : TypedDeclTablesV1) (result : TypeV1)
      (resultRelated : Array NormalizedSyntacticPathV1)
      (blockPath? : Option NormalizedSyntacticPathV1)
      (block : BlockV1) : Array TypedDiagnosticDraftV1 :=
    let (_, drafts) := block.statements.zipIdx.foldl
      (fun (accScope, accDrafts) (stmt, idx) =>
        let (stmtPath?, pathDs) :=
          resolveChild blockPath? "Block" "statements" idx
        let (nextScope, stmtDrafts) :=
          typeCheckStmtDrafts accScope tables result resultRelated stmtPath? stmt
        (nextScope, accDrafts ++ pathDs ++ stmtDrafts))
      (scope, #[])
    drafts
end

def typeCheckStmt (scope : TypeCheckScopeV1) (tables : TypedDeclTablesV1)
    (result : TypeV1) (stmt : StmtV1) : TypeCheckScopeV1 × Array DiagnosticV1 :=
  let (s, drafts) := typeCheckStmtDrafts scope tables result #[] none stmt
  (s, eraseArray drafts)

def typeCheckBlock (scope : TypeCheckScopeV1) (tables : TypedDeclTablesV1)
    (result : TypeV1) (block : BlockV1) : Array DiagnosticV1 :=
  eraseArray (typeCheckBlockDrafts scope tables result #[] none block)

private def scopeFromCallableParams (tables : TypedDeclTablesV1)
    (params : Array ParamV1) : TypeCheckScopeV1 :=
  params.foldl (fun acc p => addParam acc p.name p.type_) (scopeFromTables tables)

/-- Path-threaded item body check (authority). -/
def typeCheckItemDrafts (tables : TypedDeclTablesV1)
    (itemPath? : Option NormalizedSyntacticPathV1)
    (item : ProgramItemV1) : Array TypedDiagnosticDraftV1 :=
  match item with
  | .const decl =>
      let (vp?, pathDs1) := resolveDirect itemPath? "ConstDecl" "value"
      let related := optRelatedPath (constTypePath? tables decl.name)
      let res := typeCheckExprDrafts (scopeFromTables tables) tables
        (some decl.type_) related vp? decl.value
      pathDs1 ++ res.drafts
  | .init decl =>
      let (bp?, pathDs) := resolveDirect itemPath? "InitDecl" "body"
      pathDs ++ typeCheckBlockDrafts (scopeFromCallableParams tables decl.params)
        tables .unit #[] bp? decl.body
  | .entry decl =>
      let (bp?, pathDs) := resolveDirect itemPath? "EntryDecl" "body"
      let related := optRelatedPath (callableResultPath? tables .entry decl.name)
      pathDs ++ typeCheckBlockDrafts (scopeFromCallableParams tables decl.params)
        tables decl.result related bp? decl.body
  | .view decl =>
      let (bp?, pathDs) := resolveDirect itemPath? "ViewDecl" "body"
      let related := optRelatedPath (callableResultPath? tables .view decl.name)
      pathDs ++ typeCheckBlockDrafts (scopeFromCallableParams tables decl.params)
        tables decl.result related bp? decl.body
  | .fn decl =>
      let (bp?, pathDs) := resolveDirect itemPath? "FnDecl" "body"
      let related := optRelatedPath (callableResultPath? tables .fn decl.name)
      pathDs ++ typeCheckBlockDrafts (scopeFromCallableParams tables decl.params)
        tables decl.result related bp? decl.body
  | .invariant decl =>
      let (pp?, pathDs) := resolveDirect itemPath? "InvariantDecl" "predicate"
      let res := typeCheckExprDrafts (scopeFromTables tables) tables
        (some .bool) #[] pp? decl.predicate
      pathDs ++ res.drafts
  | _ => #[]

def typeCheckItem (tables : TypedDeclTablesV1) (item : ProgramItemV1) :
    Array DiagnosticV1 :=
  eraseArray (typeCheckItemDrafts tables none item)

/-- Body type-check authority with paths (resolution must already be ok). -/
def typeCheckProgramBodiesDraftsV1 (program : ProgramV1)
    (tables : TypedDeclTablesV1) : Array TypedDiagnosticDraftV1 :=
  program.items.zipIdx.foldl (fun acc (item, itemIndex) =>
    match programItemPathV1 itemIndex with
    | .error detail => acc.push (pathInternalDraft detail)
    | .ok itemPath =>
        acc ++ typeCheckItemDrafts tables (some itemPath) item) #[]

/-- Additive draft-bearing program type-check.
    Short-circuits with resolution drafts when resolution is not ok. -/
def typeCheckProgramDraftsV1 (program : ProgramV1)
    (resolved : NameResolutionDraftResultV1) : TypeCheckProgramDraftResultV1 :=
  if !resolved.ok then
    { drafts := resolved.drafts, ok := false }
  else
    let drafts := typeCheckProgramBodiesDraftsV1 program resolved.tables
    { drafts := drafts, ok := drafts.isEmpty }

/-- Public unlocated projection: erases drafts; preserves code/message/phase/order.
    Resolution-not-ok short-circuits with `resolved.diagnostics` unchanged. -/
def typeCheckProgramV1 (program : ProgramV1) (resolved : NameResolutionResultV1) :
    TypeCheckProgramResultV1 :=
  if !resolved.ok then
    { diagnostics := resolved.diagnostics, ok := false }
  else
    let drafts := typeCheckProgramBodiesDraftsV1 program resolved.tables
    let diags := eraseArray drafts
    { diagnostics := diags, ok := diags.isEmpty }

end ProofForgeV2.Typed.TypeCheckV1
