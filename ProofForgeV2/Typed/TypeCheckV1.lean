/-
  ProofForgeV2.Typed.TypeCheckV1 — D2-01 expression and statement/body
  type-checking slice.

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
      `Array` element access with `UInt32` index, `Map` key lookup returning
      `Option V`)
    * unary operators (`neg`, `bitNot` require integer; `not` requires `bool`)
    * binary operators (arithmetic, shift, bitwise, equality, ordering,
      logical)
    * constructor expressions (struct and enum-variant constructors checked
      against declaration order field/payload types)
    * local function calls (checked against `fn` parameter count and types)
    * expression- and statement-level `match` (pattern typing, arm unification,
      result-context checking, enum exhaustiveness)

  Covered statement/body forms:
    * `let` (annotation takes precedence, otherwise inferred from value)
    * `assign` (target type must agree with value)
    * `return` (value must agree with declared result; bare `return` is
      allowed only when the result type is `Unit`)
    * `assert` (condition must be `Bool`)
    * `revert` / `emit` (arguments checked against declared param types)
    * `if` (condition `Bool`, branches checked in the same result context)
    * `for` (endpoints must be the same integer width, binder is scoped to
      the body and does not leak)
    * `call` / `schedule` (argument expressions are type-checked with no
      expected type)
    * declaration bodies wired for `const`, `init` (unit result), `entry`,
      `view`, `fn`, and `invariant` (bool predicate)

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
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
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
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
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

private def isLocalOrParam (scope : TypeCheckScopeV1)
    (name : SourceNameComponentV1) : Option BindingKindV1 :=
  match scope.bindings.find? (fun (n, _, _) => n == name) with
  | some (_, _, .local) => some .local
  | some (_, _, .param) => some .param
  | _ => none

/-- Result of type-checking an expression: an inferred type and any diagnostics.
    The inferred type may be a placeholder (e.g. `Unit`) when diagnostics are
    non-empty; consumers should check `diagnostics.isEmpty` before using it. -/
structure TypeCheckResultV1 where
  type : TypeV1
  diagnostics : Array DiagnosticV1
  deriving Repr, Inhabited

def result (type : TypeV1) (diagnostics : Array DiagnosticV1) :
    TypeCheckResultV1 :=
  { type := type, diagnostics := diagnostics }

/-- Deterministic `expected-vs-actual` diagnostic in left-to-right order. -/
def expectedActualDiagnostic (expected actual : String) : DiagnosticV1 :=
  DiagnosticV1.make .sourceInvalid
    s!"type mismatch: expected {expected}, got {actual}"

/-- Defensive internal diagnostic for invariant violations inside the type
    checker.  Should be unreachable when called from `typeCheckProgramV1`
    because name resolution is performed first. -/
private def internalDiagnostic (message : String) : DiagnosticV1 :=
  DiagnosticV1.make .internal message

/-- Render a type for diagnostics.  This is human-readable only and does not
    enter wire/hash identity. -/
partial def typeName : TypeV1 → String
  | .bool => "Bool"
  | .uint w => s!"UInt{w.toNat}"
  | .int w => s!"Int{w.toNat}"
  | .principal => "Principal"
  | .unit => "Unit"
  | .named n => renderSourceNameComponentV1 n
  | .bytes n => s!"Bytes({n.toNat})"
  | .field id => s!"Field({id.raw})"
  | .option t => s!"Option ({typeName t})"
  | .array t n => s!"Array ({typeName t}) ({n.toNat})"
  | .map k v => s!"Map ({typeName k}) ({typeName v})"

def isIntegerType : TypeV1 → Bool
  | .uint _ | .int _ => true
  | _ => false

/-- Diagnostic emitted when a string literal is used as a pattern.  The
    surface syntax allows string patterns, but `TypeV1` has no `String`
    type, so they are fail-closed here. -/
def stringPatternDiagnostic : DiagnosticV1 :=
  DiagnosticV1.make .sourceInvalid
    "string patterns are not supported (String is not a TypeV1)"

/-- Diagnostic emitted when a later match arm value does not agree with the
    first arm's result type.  The `armIndex` is 0-based and names the arm
    where the mismatch was first observed. -/
def armTypeMismatchDiagnostic (armIndex : Nat) (expected actual : String) : DiagnosticV1 :=
  DiagnosticV1.make .sourceInvalid
    s!"match arm {armIndex}: type mismatch: expected {expected}, got {actual}"

/-- Diagnostic emitted when a match is not exhaustive.  For enum-typed
    scrutinees, `missing` lists the variant raw names in declaration order. -/
def nonExhaustiveDiagnostic (missing : List String) : DiagnosticV1 :=
  DiagnosticV1.make .sourceInvalid
    (if missing.isEmpty then "match is not exhaustive"
     else "match is not exhaustive; missing variants: " ++ String.intercalate ", " missing)

/-- Result of checking a pattern against a scrutinee type: the binders
    introduced into the arm scope and any diagnostics in source order. -/
structure PatternCheckResultV1 where
  bindings : List (SourceNameComponentV1 × TypeV1)
  diagnostics : Array DiagnosticV1
  deriving Inhabited

def patternResult (bindings : List (SourceNameComponentV1 × TypeV1))
    (diagnostics : Array DiagnosticV1) : PatternCheckResultV1 :=
  { bindings := bindings, diagnostics := diagnostics }

/-- Maximum magnitude allowed for an integer literal of `type_`.
    `isNegated` is true for literals immediately under unary `neg`. -/
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

def integerLiteralDiagnostic (expected : TypeV1) (magnitude : Nat)
    (isNegated : Bool) : DiagnosticV1 :=
  let sign := if isNegated then "-" else ""
  expectedActualDiagnostic (typeName expected)
    s!"integer literal {sign}{magnitude} out of range"

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

/-- Resolve a constructor path to its result type and expected argument types.
    Mirrors `NameResolutionV1.resolveConstructorName`. -/
def resolveConstructorType (tables : TypedDeclTablesV1)
    (ctor : SourceQualifiedNameV1) :
    Except DiagnosticV1 (TypeV1 × Array TypeV1) :=
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
  | #[enumName, variantName] =>
      match tables.enum.find? enumName with
      | some (_, enumDecl) =>
          match enumDecl.variants.find? (·.name == variantName) with
          | some variant => pure (.named enumDecl.name, variant.payloadTypes)
          | none => .error (unknownNameDiagnostic variantName "constructor variant")
      | none =>
          match findFirstMatchingKind tables enumName with
          | some (kind, _) => .error (wrongCategoryDiagnostic enumName kind "constructor")
          | none => .error (unknownNameDiagnostic enumName "constructor enum")
  | _ =>
      .error (unknownQualifiedNameDiagnostic ctor "constructor")

/-- Resolve a local callee to a `fn` declaration, using the same precedence as
    `NameResolutionV1.resolveLocalCall`. -/
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

/-- Add pattern binders to the arm-local scope. -/
private def addBindings (scope : TypeCheckScopeV1)
    (bindings : List (SourceNameComponentV1 × TypeV1)) : TypeCheckScopeV1 :=
  bindings.foldl (fun acc (name, type_) => addBinding acc name type_) scope

/-- Check a pattern against a scrutinee type, returning the binders introduced
    into the arm scope and diagnostics in source order. -/
partial def typeCheckPattern (tables : TypedDeclTablesV1)
    (scrutineeType : TypeV1) (pattern : PatternV1) : PatternCheckResultV1 :=
  match pattern with
  | .wildcard => patternResult [] #[]
  | .bind name => patternResult [(name, scrutineeType)] #[]
  | .literal (.bool _) =>
      if scrutineeType == .bool then
        patternResult [] #[]
      else
        patternResult [] #[expectedActualDiagnostic "Bool" (typeName scrutineeType)]
  | .literal (.integer magnitude) =>
      if isIntegerType scrutineeType then
        match integerLiteralBound scrutineeType false with
        | some bound =>
            if magnitude <= bound then
              patternResult [] #[]
            else
              patternResult [] #[integerLiteralDiagnostic scrutineeType magnitude false]
        | none =>
            patternResult [] #[expectedActualDiagnostic (typeName scrutineeType) "integer literal"]
      else
        patternResult [] #[expectedActualDiagnostic (typeName scrutineeType) "integer literal"]
  | .literal (.string _) =>
      patternResult [] #[stringPatternDiagnostic]
  | .constructor ctor args =>
      match resolveConstructorType tables ctor with
      | .error diag => patternResult [] #[diag]
      | .ok (ctorResultType, expectedTypes) =>
          let typeDiag :=
            if ctorResultType != scrutineeType then
              #[expectedActualDiagnostic (typeName scrutineeType) (typeName ctorResultType)]
            else #[]
          let arityDiag :=
            if expectedTypes.size != args.size then
              #[expectedActualDiagnostic
                s!"{expectedTypes.size} constructor arguments"
                s!"{args.size} constructor arguments"]
            else #[]
          let baseDiags := typeDiag ++ arityDiag
          let (bindings, subDiags) := (List.range args.size).foldl
            (fun (bs, ds) i =>
              match args[i]? with
              | none => (bs, ds)
              | some sub =>
                let expectedType? := if i < expectedTypes.size then some expectedTypes[i]! else none
                let subRes :=
                  match expectedType? with
                  | some expectedType => typeCheckPattern tables expectedType sub
                  | none => typeCheckPattern tables .unit sub
                (bs ++ subRes.bindings, ds ++ subRes.diagnostics))
            ([], #[])
          patternResult bindings (baseDiags ++ subDiags)

/-- True for wildcard or bind patterns, which make any match exhaustive. -/
private def isCatchAll : PatternV1 → Bool
  | .wildcard | .bind _ => true
  | _ => false

/-- If `pattern` is a constructor pattern resolving to a variant of `enumName`,
    return that variant name. -/
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

/-- Check match exhaustiveness and return either an empty array or a single
    diagnostic naming the missing variants (in declaration order for enums).
    A wildcard or bind arm makes any scrutinee exhaustive. -/
def checkExhaustiveness (tables : TypedDeclTablesV1) (scrutineeType : TypeV1)
    (patterns : Array PatternV1) : Array DiagnosticV1 :=
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
            else #[nonExhaustiveDiagnostic (missing.map (·.name.raw)).toList]
        | none =>
            -- Named scrutinee that is not an enum (e.g. struct) or unknown:
            -- without a catch-all it cannot be exhaustive.
            #[nonExhaustiveDiagnostic []]
    | _ =>
        -- Non-enum scrutinees require a catch-all arm.
        #[nonExhaustiveDiagnostic []]

mutual
  /-- Infer/check the type of a place.  Struct field chains and `Array`/`Map`
      index suffixes are resolved against `tables`. -/
  partial def typeCheckPlace (scope : TypeCheckScopeV1)
      (tables : TypedDeclTablesV1) (place : PlaceV1) : TypeCheckResultV1 :=
    match place with
    | .name name =>
        match lookupType scope name with
        | some type_ => result type_ #[]
        | none =>
            result .unit #[expectedActualDiagnostic "binding in scope"
              (s!"unknown name '{renderSourceNameComponentV1 name}'")]
    | .field base field =>
        let baseRes := typeCheckPlace scope tables base
        if !baseRes.diagnostics.isEmpty then
          baseRes
        else
          match baseRes.type with
          | .named structName =>
              match tables.struct.find? structName with
              | some structDecl =>
                  match structDecl.2.fields.find? (fun f => f.name == field) with
                  | some fieldDecl => result fieldDecl.type_ #[]
                  | none =>
                      result .unit #[expectedActualDiagnostic
                        (s!"field '{renderSourceNameComponentV1 field}' of {typeName baseRes.type}")
                        (typeName baseRes.type)]
              | none =>
                  result .unit #[expectedActualDiagnostic "struct type"
                    (typeName baseRes.type)]
          | other =>
              result .unit #[expectedActualDiagnostic "struct type"
                (typeName other)]
    | .index base idx =>
        let baseRes := typeCheckPlace scope tables base
        if !baseRes.diagnostics.isEmpty then
          baseRes
        else
          match baseRes.type with
          | .array elem _ =>
              let idxRes := typeCheckExpr scope tables (some (.uint 32)) idx
              let diags := baseRes.diagnostics ++ idxRes.diagnostics
              if idxRes.type == .uint 32 then
                result elem diags
              else
                result elem (diags.push (expectedActualDiagnostic "UInt32"
                  (typeName idxRes.type)))
          | .map key value =>
              let idxRes := typeCheckExpr scope tables (some key) idx
              let diags := baseRes.diagnostics ++ idxRes.diagnostics
              if idxRes.type == key then
                result (TypeV1.option value) diags
              else
                result (TypeV1.option value) (diags.push (expectedActualDiagnostic (typeName key)
                  (typeName idxRes.type)))
          | other =>
              result .unit #[expectedActualDiagnostic "Array or Map"
                (typeName other)]

  /-- Infer/check the type of an expression.
      `expected?` is propagated left-to-right; integer literals are only
      accepted when an expected integer type is available. -/
  partial def typeCheckExpr (scope : TypeCheckScopeV1)
      (tables : TypedDeclTablesV1) (expected? : Option TypeV1) (expr : ExprV1) :
      TypeCheckResultV1 :=
    match expr with
    | .literal (.bool _) =>
        result .bool (checkExpected .bool expected? #[]).2
    | .literal (.integer magnitude) =>
        match expected? with
        | none =>
            result .unit #[expectedActualDiagnostic "integer type"
              "integer literal"]
        | some expected =>
            if isIntegerType expected then
              match integerLiteralBound expected false with
              | some bound =>
                  if magnitude <= bound then
                    result expected #[]
                  else
                    result expected #[integerLiteralDiagnostic expected magnitude false]
              | none =>
                  result expected #[expectedActualDiagnostic (typeName expected)
                    "integer literal"]
            else
              result expected #[expectedActualDiagnostic (typeName expected)
                "integer literal"]
    | .literal (.string _) =>
        match expected? with
        | none =>
            result .unit #[expectedActualDiagnostic "expected type" "string literal"]
        | some expected =>
            result expected #[expectedActualDiagnostic (typeName expected)
              "string literal"]
    | .place p =>
        let pRes := typeCheckPlace scope tables p
        let (type_, diags) := checkExpected pRes.type expected? pRes.diagnostics
        result type_ diags
    | .unary .neg (.literal (.integer magnitude)) =>
        match expected? with
        | none =>
            result .unit #[expectedActualDiagnostic "integer type"
              "integer literal"]
        | some expected =>
            if isIntegerType expected then
              match expected with
              | .uint _ =>
                  if magnitude == 0 then
                    result expected #[]
                  else
                    result expected #[integerLiteralDiagnostic expected magnitude true]
              | _ =>
                  match integerLiteralBound expected true with
                  | some bound =>
                      if magnitude <= bound then
                        result expected #[]
                      else
                        result expected #[integerLiteralDiagnostic expected magnitude true]
                  | none =>
                      result expected #[expectedActualDiagnostic (typeName expected)
                        "integer literal"]
            else
              result expected #[expectedActualDiagnostic (typeName expected)
                "integer literal"]
    | .unary .bitNot (.literal (.integer magnitude)) =>
        match expected? with
        | none =>
            result .unit #[expectedActualDiagnostic "integer type"
              "integer literal"]
        | some expected =>
            if isIntegerType expected then
              match integerLiteralBound expected false with
              | some bound =>
                  if magnitude <= bound then
                    result expected #[]
                  else
                    result expected #[integerLiteralDiagnostic expected magnitude false]
              | none =>
                  result expected #[expectedActualDiagnostic (typeName expected)
                    "integer literal"]
            else
              result expected #[expectedActualDiagnostic (typeName expected)
                "integer literal"]
    | .unary op operand =>
        match op with
        | .neg | .bitNot =>
            let opRes := typeCheckExpr scope tables none operand
            let (resType, diags) :=
              if isIntegerType opRes.type then
                (opRes.type, opRes.diagnostics)
              else
                (opRes.type, opRes.diagnostics.push
                  (expectedActualDiagnostic "integer type" (typeName opRes.type)))
            let (type_, diags) := checkExpected resType expected? diags
            result type_ diags
        | .not =>
            let opRes := typeCheckExpr scope tables (some .bool) operand
            let diags :=
              if opRes.type == .bool then
                opRes.diagnostics
              else
                opRes.diagnostics.push
                  (expectedActualDiagnostic "Bool" (typeName opRes.type))
            let (type_, diags) := checkExpected .bool expected? diags
            result type_ diags
    | .binary op lhs rhs =>
        if isArithmeticOp op || isBitwiseOp op then
          let lhsExpected? := expected?.filter isIntegerType
          let lhsRes := typeCheckExpr scope tables lhsExpected? lhs
          let (diags, lhsType) :=
            if isIntegerType lhsRes.type then
              (lhsRes.diagnostics, lhsRes.type)
            else
              (lhsRes.diagnostics.push (expectedActualDiagnostic "integer type"
                (typeName lhsRes.type)), lhsRes.type)
          let rhsRes := typeCheckExpr scope tables (some lhsType) rhs
          let (diags, resType) :=
            if lhsType == rhsRes.type then
              (diags ++ rhsRes.diagnostics, lhsType)
            else
              (diags ++ rhsRes.diagnostics ++ #[expectedActualDiagnostic
                (typeName lhsType) (typeName rhsRes.type)], lhsType)
          let (type_, diags) := checkExpected resType expected? diags
          result type_ diags
        else if isShiftOp op then
          let lhsExpected? := expected?.filter isIntegerType
          let lhsRes := typeCheckExpr scope tables lhsExpected? lhs
          let (diags, lhsType) :=
            if isIntegerType lhsRes.type then
              (lhsRes.diagnostics, lhsRes.type)
            else
              (lhsRes.diagnostics.push (expectedActualDiagnostic "integer type"
                (typeName lhsRes.type)), lhsRes.type)
          let rhsRes := typeCheckExpr scope tables (some (.uint 32)) rhs
          let diags := diags ++ rhsRes.diagnostics
          let diags :=
            if rhsRes.type == .uint 32 then
              diags
            else
              diags.push (expectedActualDiagnostic "UInt32" (typeName rhsRes.type))
          -- Literal shift counts must be strictly less than the lhs integer width.
          let diags :=
            match lhsType, rhs with
            | .uint w, .literal (.integer magnitude) =>
                if magnitude < w.toNat then diags
                else diags.push (expectedActualDiagnostic
                  s!"shift count < {w.toNat}" s!"shift count {magnitude}")
            | .int w, .literal (.integer magnitude) =>
                if magnitude < w.toNat then diags
                else diags.push (expectedActualDiagnostic
                  s!"shift count < {w.toNat}" s!"shift count {magnitude}")
            | _, _ => diags
          let (type_, diags) := checkExpected lhsType expected? diags
          result type_ diags
        else if isEqualityOp op then
          let lhsRes := typeCheckExpr scope tables none lhs
          let rhsRes := typeCheckExpr scope tables (some lhsRes.type) rhs
          let diags := lhsRes.diagnostics ++ rhsRes.diagnostics
          let diags :=
            if lhsRes.type == rhsRes.type then
              diags
            else
              diags.push (expectedActualDiagnostic (typeName lhsRes.type)
                (typeName rhsRes.type))
          let (type_, diags) := checkExpected .bool expected? diags
          result type_ diags
        else if isComparisonOp op then
          let lhsRes := typeCheckExpr scope tables none lhs
          let (diags, lhsType) :=
            if isIntegerType lhsRes.type then
              (lhsRes.diagnostics, lhsRes.type)
            else
              (lhsRes.diagnostics.push (expectedActualDiagnostic "integer type"
                (typeName lhsRes.type)), lhsRes.type)
          let rhsRes := typeCheckExpr scope tables (some lhsType) rhs
          let (diags, resType) :=
            if isIntegerType lhsType && lhsType == rhsRes.type then
              (diags ++ rhsRes.diagnostics, .bool)
            else
              (diags ++ rhsRes.diagnostics ++ #[expectedActualDiagnostic
                (typeName lhsType) (typeName rhsRes.type)], .bool)
          let (type_, diags) := checkExpected resType expected? diags
          result type_ diags
        else if isLogicalOp op then
          let lhsRes := typeCheckExpr scope tables (some .bool) lhs
          let rhsRes := typeCheckExpr scope tables (some .bool) rhs
          let diags := lhsRes.diagnostics ++ rhsRes.diagnostics
          let diags :=
            if lhsRes.type == .bool && rhsRes.type == .bool then
              diags
            else
              let lhsDiag := if lhsRes.type == .bool then #[] else
                #[expectedActualDiagnostic "Bool" (typeName lhsRes.type)]
              let rhsDiag := if rhsRes.type == .bool then #[] else
                #[expectedActualDiagnostic "Bool" (typeName rhsRes.type)]
              diags ++ lhsDiag ++ rhsDiag
          let (type_, diags) := checkExpected .bool expected? diags
          result type_ diags
        else
          result .unit #[expectedActualDiagnostic (typeName (expected?.getD .unit))
            "binary expression"]
    | .constructor ctor args =>
        let pathRes := resolveConstructorType tables ctor
        match pathRes with
        | .error diag =>
            let argDiags := args.foldl (fun acc arg =>
              acc ++ (typeCheckExpr scope tables none arg).diagnostics) #[diag]
            result (expected?.getD .unit) argDiags
        | .ok (resType, expectedTypes) =>
            let diags : Array DiagnosticV1 := #[]
            let diags :=
              if expectedTypes.size == args.size then diags
              else diags.push (expectedActualDiagnostic
                s!"{expectedTypes.size} constructor arguments"
                s!"{args.size} constructor arguments")
            let diags :=
              if expectedTypes.size == args.size then
                (expectedTypes.zip args).foldl (fun acc (expectedType, arg) =>
                  acc ++ (typeCheckExpr scope tables (some expectedType) arg).diagnostics) diags
              else diags
            let (type_, diags) := checkExpected resType expected? diags
            result type_ diags
    | .localCall callee args =>
        match resolveLocalCallType scope tables callee with
        | .error diag =>
            let argDiags := args.foldl (fun acc arg =>
              acc ++ (typeCheckExpr scope tables none arg).diagnostics) #[diag]
            result (expected?.getD .unit) argDiags
        | .ok fnDecl =>
            let diags : Array DiagnosticV1 := #[]
            let diags :=
              if fnDecl.params.size == args.size then diags
              else diags.push (expectedActualDiagnostic
                s!"{fnDecl.params.size} arguments" s!"{args.size} arguments")
            let diags :=
              if fnDecl.params.size == args.size then
                (fnDecl.params.zip args).foldl (fun acc (param, arg) =>
                  acc ++ (typeCheckExpr scope tables (some param.type_) arg).diagnostics) diags
              else diags
            let (type_, diags) := checkExpected fnDecl.result expected? diags
            result type_ diags
    | .match_ scrutinee arms =>
        match arms.toList with
        | [] =>
            result (expected?.getD .unit) #[internalDiagnostic "empty match expression"]
        | firstArm :: restArms =>
            let scrutineeRes := typeCheckExpr scope tables none scrutinee
            let scrutineeType := scrutineeRes.type
            let firstPatternRes := typeCheckPattern tables scrutineeType firstArm.pattern
            let firstArmScope := addBindings scope firstPatternRes.bindings
            let firstValueRes := typeCheckExpr firstArmScope tables expected? firstArm.value
            let firstArmType := firstValueRes.type
            let (restDiags, _) := restArms.foldl
              (fun (acc, i) arm =>
                let patternRes := typeCheckPattern tables scrutineeType arm.pattern
                let armScope := addBindings scope patternRes.bindings
                let valueRes := typeCheckExpr armScope tables expected? arm.value
                let typeDiag :=
                  if valueRes.type == firstArmType then #[]
                  else #[armTypeMismatchDiagnostic i (typeName firstArmType) (typeName valueRes.type)]
                (acc ++ patternRes.diagnostics ++ valueRes.diagnostics ++ typeDiag, i + 1))
              (#[], 1)
            let armDiags := scrutineeRes.diagnostics ++ firstPatternRes.diagnostics ++
              firstValueRes.diagnostics ++ restDiags
            let exhaustDiags := checkExhaustiveness tables scrutineeType (arms.map (·.pattern))
            let (type_, diags) := checkExpected firstArmType expected? armDiags
            result type_ (diags ++ exhaustDiags)
end

def scopeFromTables (tables : TypedDeclTablesV1) : TypeCheckScopeV1 :=
  let base := emptyScope
  let base := tables.state.entries.foldl
    (fun acc (n, _, d) => addStateConst acc n d.type_ .state) base
  tables.const.entries.foldl
    (fun acc (n, _, d) => addStateConst acc n d.type_ .const) base

/-- Build a scope containing all state/const bindings plus the parameters of a
    named callable (`fn`/`entry`/`view`).  Used by tests and future consumers
    that want to type-check an expression inside a callable body. -/
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

/-- Result of type-checking a whole ProgramV1 source unit. -/
structure TypeCheckProgramResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  deriving Repr, Inhabited

private def emptyTypeCheckProgramResult : TypeCheckProgramResultV1 :=
  { diagnostics := #[], ok := true }

private def resultRequiredDiagnostic (expected : TypeV1) : DiagnosticV1 :=
  expectedActualDiagnostic (typeName expected) "empty return"

mutual
  /-- Type-check a statement inside a declared result-type context.
      Returns the updated scope (bindings introduced by this statement that are
      visible to later statements) and any diagnostics in source order.

      Precondition: name resolution has already succeeded, so every referenced
      error/event name is present in `tables`.  The `none` branches below are
      defensive and emit an internal diagnostic. -/
  partial def typeCheckStmt (scope : TypeCheckScopeV1) (tables : TypedDeclTablesV1)
      (result : TypeV1) (stmt : StmtV1) : TypeCheckScopeV1 × Array DiagnosticV1 :=
    match stmt with
    | .let_ name typeAnn value =>
        match typeAnn with
        | some ann =>
            let valueRes := typeCheckExpr scope tables (some ann) value
            (addBinding scope name ann, valueRes.diagnostics)
        | none =>
            let valueRes := typeCheckExpr scope tables none value
            (addBinding scope name valueRes.type, valueRes.diagnostics)
    | .assign target value =>
        let targetRes := typeCheckPlace scope tables target
        let valueExpected? := if targetRes.diagnostics.isEmpty then some targetRes.type else none
        let valueRes := typeCheckExpr scope tables valueExpected? value
        let diags := targetRes.diagnostics ++ valueRes.diagnostics
        let diags :=
          if targetRes.diagnostics.isEmpty && targetRes.type != valueRes.type then
            diags.push (expectedActualDiagnostic (typeName targetRes.type) (typeName valueRes.type))
          else
            diags
        (scope, diags)
    | .return_ (some value) =>
        let valueRes := typeCheckExpr scope tables (some result) value
        let diags :=
          if valueRes.diagnostics.isEmpty && valueRes.type != result then
            valueRes.diagnostics.push (expectedActualDiagnostic (typeName result) (typeName valueRes.type))
          else
            valueRes.diagnostics
        (scope, diags)
    | .return_ none =>
        let diags :=
          if result == .unit then #[]
          else #[resultRequiredDiagnostic result]
        (scope, diags)
    | .assert_ condition error? =>
        let condRes := typeCheckExpr scope tables (some .bool) condition
        let diags :=
          if condRes.diagnostics.isEmpty && condRes.type != .bool then
            condRes.diagnostics.push (expectedActualDiagnostic "Bool" (typeName condRes.type))
          else
            condRes.diagnostics
        let _ := error?
        (scope, diags)
    | .revert name args =>
        match tables.error.find? name with
        | none =>
            (scope, #[internalDiagnostic s!"unresolved error name '{name.raw}' in revert"])
        | some (_, decl) =>
            let diags : Array DiagnosticV1 :=
              if decl.params.size == args.size then #[]
              else #[expectedActualDiagnostic
                s!"{decl.params.size} arguments" s!"{args.size} arguments"]
            let diags :=
              if decl.params.size == args.size then
                (decl.params.zip args).foldl (fun acc (param, arg) =>
                  acc ++ (typeCheckExpr scope tables (some param.type_) arg).diagnostics) diags
              else
                args.foldl (fun acc arg =>
                  acc ++ (typeCheckExpr scope tables none arg).diagnostics) diags
            (scope, diags)
    | .emit name args =>
        match tables.event.find? name with
        | none =>
            (scope, #[internalDiagnostic s!"unresolved event name '{name.raw}' in emit"])
        | some (_, decl) =>
            let diags : Array DiagnosticV1 :=
              if decl.params.size == args.size then #[]
              else #[expectedActualDiagnostic
                s!"{decl.params.size} arguments" s!"{args.size} arguments"]
            let diags :=
              if decl.params.size == args.size then
                (decl.params.zip args).foldl (fun acc (param, arg) =>
                  acc ++ (typeCheckExpr scope tables (some param.type_) arg).diagnostics) diags
              else
                args.foldl (fun acc arg =>
                  acc ++ (typeCheckExpr scope tables none arg).diagnostics) diags
            (scope, diags)
    | .if_ condition thenBlock elseBlock? =>
        let condRes := typeCheckExpr scope tables (some .bool) condition
        let condDiags :=
          if condRes.diagnostics.isEmpty && condRes.type != .bool then
            condRes.diagnostics.push (expectedActualDiagnostic "Bool" (typeName condRes.type))
          else
            condRes.diagnostics
        let thenDiags := typeCheckBlock scope tables result thenBlock
        let elseDiags := match elseBlock? with
          | some elseBlock => typeCheckBlock scope tables result elseBlock
          | none => #[]
        (scope, condDiags ++ thenDiags ++ elseDiags)
    | .for_ binder start endExclusive _ body =>
        let startRes := typeCheckExpr scope tables none start
        let (startDiags, startType) :=
          if isIntegerType startRes.type then
            (startRes.diagnostics, startRes.type)
          else
            (startRes.diagnostics.push (expectedActualDiagnostic "integer type" (typeName startRes.type)), .unit)
        let endExpected? := if startType == .unit then none else some startType
        let endRes := typeCheckExpr scope tables endExpected? endExclusive
        let endDiags :=
          if endRes.diagnostics.isEmpty && !isIntegerType endRes.type then
            endRes.diagnostics.push (expectedActualDiagnostic "integer type" (typeName endRes.type))
          else
            endRes.diagnostics
        let widthDiags :=
          if isIntegerType startRes.type && isIntegerType endRes.type && startRes.type != endRes.type then
            #[expectedActualDiagnostic (typeName startRes.type) (typeName endRes.type)]
          else
            #[]
        let iterType := if isIntegerType startType then startType else .unit
        let bodyDiags := typeCheckBlock (addBinding scope binder iterType) tables result body
        (scope, startDiags ++ endDiags ++ widthDiags ++ bodyDiags)
    | .call externalCall | .schedule externalCall =>
        let diags := externalCall.args.foldl (fun acc arg =>
          acc ++ (typeCheckExpr scope tables none arg).diagnostics) #[]
        (scope, diags)
    | .match_ scrutinee arms =>
        let scrutineeRes := typeCheckExpr scope tables none scrutinee
        let scrutineeType := scrutineeRes.type
        let armDiags := arms.foldl (fun acc arm =>
          let patternRes := typeCheckPattern tables scrutineeType arm.pattern
          let armScope := addBindings scope patternRes.bindings
          let bodyDiags := typeCheckBlock armScope tables result arm.body
          acc ++ patternRes.diagnostics ++ bodyDiags) scrutineeRes.diagnostics
        let exhaustDiags := checkExhaustiveness tables scrutineeType (arms.map (·.pattern))
        (scope, armDiags ++ exhaustDiags)

  /-- Type-check a block of statements in source order, threading scope through. -/
  partial def typeCheckBlock (scope : TypeCheckScopeV1) (tables : TypedDeclTablesV1)
      (result : TypeV1) (block : BlockV1) : Array DiagnosticV1 :=
    let (_, diags) := block.statements.foldl (fun (accScope, accDiags) stmt =>
      let (nextScope, stmtDiags) := typeCheckStmt accScope tables result stmt
      (nextScope, accDiags ++ stmtDiags)) (scope, #[])
    diags
end

/-- Build a scope from state/const bindings plus a callable's parameters.
    Shared by `init`, `entry`, `view`, and `fn` body checking. -/
private def scopeFromCallableParams (tables : TypedDeclTablesV1)
    (params : Array ParamV1) : TypeCheckScopeV1 :=
  params.foldl (fun acc p => addParam acc p.name p.type_) (scopeFromTables tables)

/-- Type-check a single top-level declaration body.  State/struct/enum/event/error
    declarations need no expression typing here; const/init/entry/view/fn/invariant
    bodies are checked against their declared types. -/
def typeCheckItem (tables : TypedDeclTablesV1) (item : ProgramItemV1) :
    Array DiagnosticV1 :=
  match item with
  | .const decl =>
      (typeCheckExpr (scopeFromTables tables) tables (some decl.type_) decl.value).diagnostics
  | .init decl =>
      typeCheckBlock (scopeFromCallableParams tables decl.params) tables .unit decl.body
  | .entry decl | .view decl | .fn decl =>
      typeCheckBlock (scopeFromCallableParams tables decl.params) tables decl.result decl.body
  | .invariant decl =>
      (typeCheckExpr (scopeFromTables tables) tables (some .bool) decl.predicate).diagnostics
  | _ => #[]

/-- Type-check a fully name-resolved ProgramV1 source unit.
    If name resolution produced diagnostics, those are returned verbatim and body
    type checking is skipped to avoid cascading errors. -/
def typeCheckProgramV1 (program : ProgramV1) (resolved : NameResolutionResultV1) :
    TypeCheckProgramResultV1 :=
  if !resolved.ok then
    { diagnostics := resolved.diagnostics, ok := false }
  else
    let diags := program.items.foldl (fun acc item =>
      acc ++ typeCheckItem resolved.tables item) resolved.diagnostics
    { diagnostics := diags, ok := diags.isEmpty }

end ProofForgeV2.Typed.TypeCheckV1
