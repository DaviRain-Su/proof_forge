/-
  ProofForgeV2.Typed.TypeCheckV1 — D2-01 core expression type-checking slice.

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

  Deliberately outside this slice (fail closed with a type-mismatch
  diagnostic):
    * constructor expressions, local function calls, expression-level `match`,
      and statement forms/effects/requirements.
-/import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.TypeCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

instance : Inhabited TypeV1 := ⟨.unit⟩

/-- Local type-checking scope: source-order name-to-type bindings.
    Resolution priority is the order of the list (locals shadow params, etc.). -/
structure TypeCheckScopeV1 where
  bindings : List (SourceNameComponentV1 × TypeV1)

def emptyScope : TypeCheckScopeV1 := ⟨[]⟩

def addBinding (scope : TypeCheckScopeV1) (name : SourceNameComponentV1)
    (type_ : TypeV1) : TypeCheckScopeV1 :=
  ⟨ (name, type_) :: scope.bindings ⟩

def lookupType (scope : TypeCheckScopeV1) (name : SourceNameComponentV1) :
    Option TypeV1 :=
  match scope.bindings.find? (fun (n, _) => n == name) with
  | some (_, type_) => some type_
  | none => none

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
  { code := .sourceInvalid,
    message := s!"type mismatch: expected {expected}, got {actual}",
    origins := emptyOrigins }

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
    | .constructor _ _ =>
        result .unit #[expectedActualDiagnostic
          (typeName (expected?.getD .unit)) "constructor expression"]
    | .localCall _ _ =>
        result .unit #[expectedActualDiagnostic
          (typeName (expected?.getD .unit)) "local call expression"]
    | .match_ _ _ =>
        result .unit #[expectedActualDiagnostic
          (typeName (expected?.getD .unit)) "match expression"]
end

def scopeFromTables (tables : TypedDeclTablesV1) : TypeCheckScopeV1 :=
  let stateBindings := tables.state.entries.map fun (n, _, d) => (n, d.type_)
  let constBindings := tables.const.entries.map fun (n, _, d) => (n, d.type_)
  ⟨ stateBindings.toList ++ constBindings.toList ⟩

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
  let stateBindings := tables.state.entries.map fun (n, _, d) => (n, d.type_)
  let constBindings := tables.const.entries.map fun (n, _, d) => (n, d.type_)
  let paramBindings := params.map (fun p => (p.name, p.type_))
  let bindings := paramBindings.toList ++ stateBindings.toList ++ constBindings.toList
  pure ⟨ bindings ⟩

end ProofForgeV2.Typed.TypeCheckV1
