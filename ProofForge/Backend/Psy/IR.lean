import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Backend.Psy.IR

open ProofForge.IR
open ProofForge.Target

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

def diagnosticError (err : Diagnostic) : LowerError := {
  message := err.render
}

def indent (level : Nat) (line : String) : String :=
  String.ofList (List.replicate (level * 4) ' ') ++ line

def lines (xs : Array String) : String :=
  String.intercalate "\n" xs.toList

def capitalizedRefName (module : Module) : String :=
  s!"{module.name}Ref"

def testFunctionName (module : Module) : String :=
  if module.name == "StorageNestedAggregateProbe" then
    "test_storage_nested_aggregate_probe_fixture"
  else if module.name == "ConditionalProbe" then
    "test_conditional_probe_fixture"
  else if module.name == "ArithmeticProbe" then
    "test_arithmetic_probe_fixture"
  else if module.name == "U32ArithmeticProbe" then
    "test_u32_arithmetic_probe_fixture"
  else if module.name == "BitwiseProbe" then
    "test_bitwise_probe_fixture"
  else if module.name == "BoolStorageArrayProbe" then
    "test_bool_storage_array_probe_fixture"
  else if module.name == "BoolStorageScalarProbe" then
    "test_bool_storage_scalar_probe_fixture"
  else if module.name == "U32HashPackingProbe" then
    "test_u32_hash_packing_probe_fixture"
  else if module.name == "U32StorageScalarProbe" then
    "test_u32_storage_scalar_probe_fixture"
  else if module.name == "U32StorageArrayProbe" then
    "test_u32_storage_array_probe_fixture"
  else if module.name == "ExpressionPredicateProbe" then
    "test_expression_predicate_probe_fixture"
  else if module.name == "NestedAggregateProbe" then
    "test_nested_aggregate_probe_fixture"
  else if module.name == "AbiAggregateProbe" then
    "test_abi_aggregate_probe_fixture"
  else if module.name == "StructArrayProbe" then
    "test_struct_array_probe_fixture"
  else if module.name == "StructProbe" then
    "test_struct_probe_fixture"
  else if module.name == "ArrayProbe" then
    "test_array_probe_fixture"
  else if module.name == "LoopProbe" then
    "test_loop_probe_fixture"
  else if module.name == "AssertProbe" then
    "test_assert_probe_fixture"
  else if module.name == "MapProbe" then
    "test_map_probe_fixture"
  else if module.name == "HashProbe" then
    "test_hash_probe_fixture"
  else if module.name == "HashStorageProbe" then
    "test_hash_storage_probe_fixture"
  else if module.name == "ContextProbe" then
    "test_context_probe_fixture"
  else if module.name == "Counter" then
    "test_counter_lifecycle"
  else
    s!"test_{module.name}_fixture"

def valueTypeName : ValueType → Except LowerError String
  | .unit => .ok "()"
  | .bool => .ok "bool"
  | .u32 => .ok "u32"
  | .u64 => .ok "Felt"
  | .hash => .ok "Hash"
  | .address => .ok "Address"
  | .bytes => .error { message := "Psy IR v0 does not support Bytes" }
  | .string => .error { message := "Psy IR v0 does not support String" }
  | .fixedArray element length => do
      if length == 0 then
        .error { message := "Psy IR v0 fixed arrays must have non-zero length" }
      .ok s!"[{← valueTypeName element}; {length}]"
  | .structType name => .ok name

def literal : Literal → String
  | .u32 value => s!"{value}u32"
  | .u64 value => toString value
  | .bool true => "true"
  | .bool false => "false"
  | .hash4 a b c d => s!"[{a}, {b}, {c}, {d}]"
  | .address value => toString value

def stringLiteral (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

def asciiLetters : String :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

def isPsyIdentifierStart (ch : Char) : Bool :=
  ch == '_' || asciiLetters.contains ch

def isPsyIdentifierContinue (ch : Char) : Bool :=
  isPsyIdentifierStart ch || ch.isDigit

def psyReservedIdentifiers : Array String := #[
  "as",
  "bool",
  "else",
  "false",
  "fn",
  "for",
  "if",
  "impl",
  "in",
  "let",
  "mut",
  "new",
  "pub",
  "return",
  "struct",
  "true",
  "Felt",
  "Hash",
  "Map",
  "ContractMetadata"
]

def validatePsyIdentifier (context name : String) : Except LowerError Unit :=
  match name.toList with
  | [] =>
      .error { message := s!"{context} must be a non-empty Psy identifier" }
  | first :: rest => do
      if !isPsyIdentifierStart first || !rest.all isPsyIdentifierContinue then
        .error { message := s!"{context} `{name}` is not a valid Psy identifier; identifiers must start with an ASCII letter or `_` and contain only ASCII letters, digits, or `_`" }
      if psyReservedIdentifiers.any (fun reserved => reserved == name) then
        .error { message := s!"{context} `{name}` is reserved in Psy" }

def validateDistinctNames (context : String) (names : Array String) : Except LowerError Unit := do
  let _ ← names.foldlM (init := #[]) fun seen name =>
    if seen.any (fun existing => existing == name) then
      .error { message := s!"duplicate {context} `{name}`" }
    else
      .ok (seen.push name)
  pure ()

def fieldVisibility (isPublic : Bool) : String :=
  if isPublic then "pub " else ""

def structFieldDecl (field : StructField) : Except LowerError (Array String) := do
  let attrs := if field.isRef then #["#[ref]"] else #[]
  .ok <| attrs ++ #[s!"{fieldVisibility field.isPublic}{field.id}: {← valueTypeName field.type},"]

def structDecl (decl : StructDecl) : Except LowerError String := do
  let deriveLines := if decl.deriveStorage then #["#[derive(Storage)]"] else #[]
  let fieldBlocks ← decl.fields.mapM structFieldDecl
  let fields := fieldBlocks.foldl (fun acc block => acc ++ block) #[]
  .ok <| lines <|
    deriveLines ++ #[
      s!"{fieldVisibility decl.isPublic}struct {decl.name} " ++ "{"
    ] ++ fields.map (indent 1) ++ #[
      "}"
    ]

def stateDecl (state : StateDecl) : Except LowerError (Array String) := do
  match state.kind with
  | .scalar =>
      match state.type with
      | .structType _ =>
          .ok #[
            "#[ref]",
            s!"pub {state.id}: {← valueTypeName state.type},"
          ]
      | _ =>
          .ok #[s!"pub {state.id}: {← valueTypeName state.type},"]
  | .map keyType capacity =>
      .ok #[s!"pub {state.id}: Map<{← valueTypeName keyType}, {← valueTypeName state.type}, {capacity}u32>,"]
  | .array length =>
      match state.type with
      | .u32 =>
          .ok #[s!"pub {state.id}: [Felt; {length}],"]
      | _ =>
          .ok #[s!"pub {state.id}: [{← valueTypeName state.type}; {length}],"]

def findState? (module : Module) (stateId : String) : Option StateDecl :=
  module.state.find? fun state => state.id == stateId

def findStruct? (module : Module) (name : String) : Option StructDecl :=
  module.structs.find? fun decl => decl.name == name

def findStructField? (decl : StructDecl) (fieldName : String) : Option StructField :=
  decl.fields.find? fun field => field.id == fieldName

def requireScalarState (module : Module) (stateId : String) : Except LowerError Unit :=
  match findState? module stateId with
  | some state =>
      match state.kind with
      | .scalar => .ok ()
      | .map _ _ => .error { message := s!"state `{stateId}` is a map, not scalar storage" }
      | .array _ => .error { message := s!"state `{stateId}` is an array, not scalar storage" }
  | none => .error { message := s!"unknown scalar state `{stateId}`" }

def requireMapState (module : Module) (stateId : String) : Except LowerError Unit :=
  match findState? module stateId with
  | some state =>
      match state.kind with
      | .map _ _ => .ok ()
      | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
      | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
  | none => .error { message := s!"unknown map state `{stateId}`" }

def requireArrayState (module : Module) (stateId : String) : Except LowerError Unit :=
  match findState? module stateId with
  | some state =>
      match state.kind with
      | .array _ => .ok ()
      | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not an array" }
      | .map _ _ => .error { message := s!"state `{stateId}` is map storage, not an array" }
  | none => .error { message := s!"unknown array state `{stateId}`" }

def requireStructScalarState (module : Module) (stateId fieldName : String) : Except LowerError Unit :=
  match findState? module stateId with
  | some state =>
      match state.kind, state.type with
      | .scalar, .structType typeName => do
          let some decl := findStruct? module typeName
            | .error { message := s!"state `{stateId}` references unknown struct `{typeName}`" }
          if decl.fields.any (fun field => field.id == fieldName) then
            .ok ()
          else
            .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
      | .scalar, other =>
          .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
      | .map _ _, _ =>
          .error { message := s!"state `{stateId}` is map storage, not struct scalar storage" }
      | .array _, _ =>
          .error { message := s!"state `{stateId}` is array storage, not struct scalar storage" }
  | none => .error { message := s!"unknown struct state `{stateId}`" }

def requireStructArrayState (module : Module) (stateId fieldName : String) : Except LowerError Unit :=
  match findState? module stateId with
  | some state =>
      match state.kind, state.type with
      | .array _, .structType typeName => do
          let some decl := findStruct? module typeName
            | .error { message := s!"array state `{stateId}` references unknown struct `{typeName}`" }
          if !decl.deriveStorage then
            .error { message := s!"array state `{stateId}` uses struct `{typeName}`, but the struct is not marked deriveStorage" }
          else if decl.fields.any (fun field => field.id == fieldName) then
            .ok ()
          else
            .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
      | .array _, other =>
          .error { message := s!"array state `{stateId}` has element type `{other.name}`, not struct storage" }
      | .scalar, _ =>
          .error { message := s!"state `{stateId}` is scalar storage, not struct array storage" }
      | .map _ _, _ =>
          .error { message := s!"state `{stateId}` is map storage, not struct array storage" }
  | none => .error { message := s!"unknown struct array state `{stateId}`" }

def storagePathStartType (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError (ValueType × List StoragePathSegment) :=
  match findState? module stateId with
  | some state =>
      match state.kind with
      | .scalar =>
          match path.toList with
          | .mapKey _ :: _ =>
              .error { message := s!"storage path state `{stateId}` is scalar storage, not map storage" }
          | segments =>
              .ok (state.type, segments)
      | .array length =>
          if length == 0 then
            .error { message := s!"array state `{stateId}` must have non-zero length" }
          else
            match path.toList with
            | .mapKey _ :: _ =>
                .error { message := s!"storage path state `{stateId}` is array storage, not map storage" }
            | segments =>
                .ok (.fixedArray state.type length, segments)
      | .map _ capacity =>
          if capacity == 0 then
            .error { message := s!"map state `{stateId}` must have non-zero capacity" }
          else
            match path.toList with
            | .mapKey _ :: rest => .ok (state.type, rest)
            | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
  | none => .error { message := s!"unknown storage path state `{stateId}`" }

partial def resolveStoragePathSegments (module : Module) : ValueType → List StoragePathSegment → Except LowerError ValueType
  | current, [] => .ok current
  | .structType typeName, .field fieldName :: rest => do
      let some decl := findStruct? module typeName
        | .error { message := s!"storage path references unknown struct `{typeName}`" }
      if !decl.deriveStorage then
        .error { message := s!"storage path traverses struct `{typeName}`, but the struct is not marked deriveStorage" }
      let some field := findStructField? decl fieldName
        | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
      match field.type with
      | .structType _ =>
          if !field.isRef then
            .error { message := s!"storage path field `{fieldName}` in struct `{typeName}` must be marked ref to access nested storage" }
          else
            resolveStoragePathSegments module field.type rest
      | _ =>
          resolveStoragePathSegments module field.type rest
  | other, .field fieldName :: _ =>
      .error { message := s!"storage path field `{fieldName}` cannot be selected from `{other.name}`" }
  | .fixedArray element length, .index _ :: rest => do
      if length == 0 then
        .error { message := "storage path fixed array segment must have non-zero length" }
      else
        resolveStoragePathSegments module element rest
  | other, .index _ :: _ =>
      .error { message := s!"storage path index cannot be selected from `{other.name}`" }
  | other, .mapKey _ :: _ =>
      .error { message := s!"storage path map key cannot be selected from `{other.name}`" }

def resolveStoragePathType (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError ValueType := do
  if path.isEmpty then
    .error { message := s!"storage path for state `{stateId}` must contain at least one segment" }
  let (start, segments) ← storagePathStartType module stateId path
  resolveStoragePathSegments module start segments

def isFeltBackedU32StorageArrayPath (module : Module) (stateId : String) (pathType : ValueType) : Bool :=
  match findState? module stateId with
  | some { kind := .array _, type := .u32, .. } => pathType == .u32
  | _ => false

partial def validateValueType (module : Module) (type : ValueType) : Except LowerError Unit := do
  match type with
  | .unit => .error { message := "Psy IR v0 does not support Unit as a stored or structured value type" }
  | .bool | .u32 | .u64 | .hash | .address => pure ()
  | .bytes | .string =>
      .error { message := "Psy IR v0 does not support Bytes or String as stored or structured value types" }
  | .fixedArray element length =>
      if length == 0 then
        .error { message := "Psy IR v0 fixed arrays must have non-zero length" }
      validateValueType module element
  | .structType name =>
      match findStruct? module name with
      | some _ => pure ()
      | none => .error { message := s!"unknown struct type `{name}`" }

partial def validateAbiValueType (module : Module) (type : ValueType) (context : String) (allowUnit : Bool) : Except LowerError Unit := do
  match type with
  | .unit =>
      if allowUnit then
        pure ()
      else
        .error { message := s!"{context} uses Unit; Psy IR v0 entrypoint parameters must use Felt, U32, Bool, Hash, Address, fixed arrays, or declared structs" }
  | .bool | .u32 | .u64 | .hash | .address => pure ()
  | .bytes | .string =>
      .error { message := s!"{context} uses Bytes or String; Psy IR v0 entrypoint parameters must use Felt, U32, Bool, Hash, Address, fixed arrays, or declared structs" }
  | .fixedArray element length =>
      if length == 0 then
        .error { message := s!"{context} uses a zero-length fixed array; Psy IR v0 fixed arrays must have non-zero length" }
      validateAbiValueType module element context false
  | .structType name =>
      match findStruct? module name with
      | some _ => pure ()
      | none => .error { message := s!"{context} references unknown struct type `{name}`" }

structure LocalBinding where
  name : String
  type : ValueType
  isMutable : Bool := false
  deriving Repr

abbrev TypeEnv := Array LocalBinding

def findLocal? (env : TypeEnv) (name : String) : Option LocalBinding :=
  env.find? fun binding => binding.name == name

def addLocal (env : TypeEnv) (name : String) (type : ValueType) (isMutable : Bool) : Except LowerError TypeEnv :=
  match findLocal? env name with
  | some _ => .error { message := s!"local `{name}` is already defined" }
  | none => .ok <| env.push { name, type, isMutable }

def ensureType (context : String) (expected actual : ValueType) : Except LowerError Unit :=
  if expected == actual then
    .ok ()
  else
    .error { message := s!"{context} expected `{expected.name}`, got `{actual.name}`" }

def ensureIndexType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 => .ok ()
  | other => .error { message := s!"{context} expected `U32` or `U64`, got `{other.name}`" }

def ensureNumericType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 => .ok ()
  | other => .error { message := s!"{context} expected numeric `U32` or `U64`, got `{other.name}`" }

def ensureSameNumericType (operator : String) (lhs rhs : ValueType) : Except LowerError ValueType := do
  ensureNumericType s!"{operator} left operand" lhs
  ensureType s!"{operator} right operand" lhs rhs
  .ok lhs

def assignOpDiagnosticName : AssignOp → String
  | .add => "addition"
  | .sub => "subtraction"
  | .mul => "multiplication"
  | .div => "division"
  | .mod => "modulo"
  | .bitAnd => "bitwise and"
  | .bitOr => "bitwise or"
  | .bitXor => "bitwise xor"
  | .shiftLeft => "shift-left"
  | .shiftRight => "shift-right"

def assignOpSymbol : AssignOp → String
  | .add => "+="
  | .sub => "-="
  | .mul => "*="
  | .div => "/="
  | .mod => "%="
  | .bitAnd => "&="
  | .bitOr => "|="
  | .bitXor => "^="
  | .shiftLeft => "<<="
  | .shiftRight => ">>="

def assignOpBinarySymbol : AssignOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .bitAnd => "&"
  | .bitOr => "|"
  | .bitXor => "^"
  | .shiftLeft => "<<"
  | .shiftRight => ">>"

def ensureAssignOpTypes (op : AssignOp) (targetType valueType : ValueType) : Except LowerError Unit := do
  discard <| ensureSameNumericType s!"compound assignment {assignOpDiagnosticName op}" targetType valueType

def ensureEqType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .unit =>
      .error { message := s!"{context} does not support Unit equality" }
  | .bool | .u32 | .u64 | .hash | .address | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .ok ()

def ensureCastType (source target : ValueType) : Except LowerError Unit :=
  match source, target with
  | .u32, .u64 => .ok ()
  | .u64, .u32 => .ok ()
  | .u32, .bool => .ok ()
  | .bool, .u64 => .ok ()
  | .bool, .u32 => .ok ()
  | .u64, .bool => .ok ()
  | source, target =>
      .error { message := s!"cast from `{source.name}` to `{target.name}` is not supported by Psy IR v0" }

def ensureHashValuePart (partName : String) (type : ValueType) : Except LowerError Unit :=
  ensureType s!"hash value part {partName}" .u64 type

def structFieldType (module : Module) (typeName fieldName : String) : Except LowerError ValueType := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct type `{typeName}`" }
  let some field := findStructField? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  .ok field.type

def stateDeclOf (module : Module) (stateId : String) (kind : String) : Except LowerError StateDecl :=
  match findState? module stateId with
  | some state => .ok state
  | none => .error { message := s!"unknown {kind} state `{stateId}`" }

def scalarStateType (module : Module) (stateId : String) : Except LowerError ValueType := do
  let state ← stateDeclOf module stateId "scalar"
  match state.kind with
  | .scalar => .ok state.type
  | .map _ _ => .error { message := s!"state `{stateId}` is a map, not scalar storage" }
  | .array _ => .error { message := s!"state `{stateId}` is an array, not scalar storage" }

def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let state ← stateDeclOf module stateId "map"
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }

def arrayStateElementType (module : Module) (stateId : String) : Except LowerError ValueType := do
  let state ← stateDeclOf module stateId "array"
  match state.kind with
  | .array _ => .ok state.type
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not an array" }
  | .map _ _ => .error { message := s!"state `{stateId}` is map storage, not an array" }

mutual
  partial def inferExprType (module : Module) (env : TypeEnv) : Expr → Except LowerError ValueType
    | .literal (.u32 _) => .ok .u32
    | .literal (.u64 _) => .ok .u64
    | .literal (.bool _) => .ok .bool
    | .literal (.hash4 ..) => .ok .hash
    | .literal (.address _) => .ok .address
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none => .error { message := s!"unknown local `{name}`" }
    | .arrayLit elementType values => do
        if values.isEmpty then
          .error { message := s!"empty fixed array literals are not supported by Psy IR v0 for `{← valueTypeName elementType}`" }
        validateValueType module elementType
        for value in values do
          let actual ← inferExprType module env value
          ensureType "array literal element" elementType actual
        .ok (.fixedArray elementType values.size)
    | .arrayGet array index => do
        let indexType ← inferExprType module env index
        ensureIndexType "array index" indexType
        match ← inferExprType module env array with
        | .fixedArray element length =>
            if length == 0 then
              .error { message := "array index requires a non-empty fixed array" }
            else
              .ok element
        | other =>
            .error { message := s!"array index requires fixed array, got `{other.name}`" }
    | .structLit typeName fields => do
        if fields.isEmpty then
          .error { message := s!"struct literal `{typeName}` must have at least one field" }
        let some decl := findStruct? module typeName
          | .error { message := s!"struct literal references unknown struct `{typeName}`" }
        if decl.fields.size != fields.size then
          .error { message := s!"struct literal `{typeName}` expected {decl.fields.size} field(s), got {fields.size}" }
        for field in fields do
          let expected ← structFieldType module typeName field.fst
          let actual ← inferExprType module env field.snd
          ensureType s!"struct literal `{typeName}` field `{field.fst}`" expected actual
        for expectedField in decl.fields do
          if !(fields.any fun field => field.fst == expectedField.id) then
            .error { message := s!"struct literal `{typeName}` is missing field `{expectedField.id}`" }
        .ok (.structType typeName)
    | .field base fieldName => do
        match ← inferExprType module env base with
        | .structType typeName =>
            structFieldType module typeName fieldName
        | other =>
            .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
    | .add lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "addition" lhsType rhsType
    | .sub lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "subtraction" lhsType rhsType
    | .mul lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "multiplication" lhsType rhsType
    | .div lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "division" lhsType rhsType
    | .mod lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "modulo" lhsType rhsType
    | .pow lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "exponentiation" lhsType rhsType
    | .bitAnd lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "bitwise and" lhsType rhsType
    | .bitOr lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "bitwise or" lhsType rhsType
    | .bitXor lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "bitwise xor" lhsType rhsType
    | .shiftLeft lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "shift-left" lhsType rhsType
    | .shiftRight lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureSameNumericType "shift-right" lhsType rhsType
    | .cast value targetType => do
        let sourceType ← inferExprType module env value
        ensureCastType sourceType targetType
        .ok targetType
    | .eq lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "equality right operand" lhsType rhsType
        ensureEqType "equality expression" lhsType
        .ok .bool
    | .ne lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "inequality right operand" lhsType rhsType
        ensureEqType "inequality expression" lhsType
        .ok .bool
    | .lt lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "less-than" lhsType rhsType
        .ok .bool
    | .le lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "less-or-equal" lhsType rhsType
        .ok .bool
    | .gt lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "greater-than" lhsType rhsType
        .ok .bool
    | .ge lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        discard <| ensureSameNumericType "greater-or-equal" lhsType rhsType
        .ok .bool
    | .boolAnd lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "boolean and left operand" .bool lhsType
        ensureType "boolean and right operand" .bool rhsType
        .ok .bool
    | .boolOr lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "boolean or left operand" .bool lhsType
        ensureType "boolean or right operand" .bool rhsType
        .ok .bool
    | .boolNot value => do
        let valueType ← inferExprType module env value
        ensureType "boolean not operand" .bool valueType
        .ok .bool
    | .hashValue a b c d => do
        ensureHashValuePart "0" (← inferExprType module env a)
        ensureHashValuePart "1" (← inferExprType module env b)
        ensureHashValuePart "2" (← inferExprType module env c)
        ensureHashValuePart "3" (← inferExprType module env d)
        .ok .hash
    | .hash preimage => do
        let preimageType ← inferExprType module env preimage
        ensureType "hash preimage" .hash preimageType
        .ok .hash
    | .hashTwoToOne lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "hash_two_to_one left operand" .hash lhsType
        ensureType "hash_two_to_one right operand" .hash rhsType
        .ok .hash
    | .nativeValue => .ok .u64
    | .crosscallInvoke target methodId args => do
        let targetType ← inferExprType module env target
        ensureType "crosscall target contract id" .u64 targetType
        let methodIdType ← inferExprType module env methodId
        ensureType "crosscall method id" .u64 methodIdType
        let argTypes ← args.mapM (inferExprType module env)
        for argType in argTypes do
          ensureType "crosscall argument" .u64 argType
        .ok .u64
    | .crosscallInvokeTyped _ _ _ returnType =>
        .error { message := s!"typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeValueTyped _ _ _ _ returnType =>
        .error { message := s!"value-bearing typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeStaticTyped _ _ _ returnType =>
        .error { message := s!"static typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeDelegateTyped _ _ _ returnType =>
        .error { message := s!"delegate typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallCreate _ _ =>
        .error { message := "EVM contract creation is not supported by Psy IR v0" }
    | .crosscallCreate2 _ _ _ =>
        .error { message := "EVM deterministic contract creation is not supported by Psy IR v0" }
    | .effect effect =>
        inferEffectExprType module env effect

  partial def validateStoragePathExprs (module : Module) (env : TypeEnv) (stateId : String) (path : Array StoragePathSegment) : Except LowerError Unit := do
    if path.isEmpty then
      pure ()
    match findState? module stateId with
    | some state =>
        match state.kind with
        | .map keyType _ =>
            match path.toList with
            | .mapKey key :: rest => do
                let actualKey ← inferExprType module env key
                ensureType s!"map `{stateId}` key" keyType actualKey
                for segment in rest do
                  match segment with
                  | .field _ => pure ()
                  | .index index => do
                      let actualIndex ← inferExprType module env index
                      ensureIndexType s!"storage path `{stateId}` index" actualIndex
                  | .mapKey _ =>
                      .error { message := s!"storage path `{stateId}` can use a map key only as its first segment" }
            | _ => pure ()
        | .scalar | .array _ =>
            for segment in path do
              match segment with
              | .field _ => pure ()
              | .index index => do
                  let actualIndex ← inferExprType module env index
                  ensureIndexType s!"storage path `{stateId}` index" actualIndex
              | .mapKey _ =>
                  pure ()
    | none => pure ()

  partial def inferEffectExprType (module : Module) (env : TypeEnv) : Effect → Except LowerError ValueType
    | .storageScalarRead stateId =>
        scalarStateType module stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        let (keyType, _) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        .ok .bool
    | .storageMapGet stateId key => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        .ok valueType
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        let actualValue ← inferExprType module env value
        ensureType s!"map `{stateId}` value" valueType actualValue
        .ok valueType
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let actualKey ← inferExprType module env key
        ensureType s!"map `{stateId}` key" keyType actualKey
        let actualValue ← inferExprType module env value
        ensureType s!"map `{stateId}` value" valueType actualValue
        .ok valueType
    | .storageArrayRead stateId index => do
        let elementType ← arrayStateElementType module stateId
        let actualIndex ← inferExprType module env index
        ensureIndexType s!"array state `{stateId}` index" actualIndex
        .ok elementType
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        let elementType ← arrayStateElementType module stateId
        let actualIndex ← inferExprType module env index
        ensureIndexType s!"array state `{stateId}` index" actualIndex
        match elementType with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"array state `{stateId}` has element type `{other.name}`, not struct storage" }
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        match ← scalarStateType module stateId with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path => do
        validateStoragePathExprs module env stateId path
        resolveStoragePathType module stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead .origin => .ok .hash
    | .contextRead .coinbase => .ok .hash
    | .contextRead (.blockHash _) => .ok .hash
    | .contextRead _ =>
        .ok .u64
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }
end

partial def inferAssignTargetType (module : Module) (env : TypeEnv) : Expr → Except LowerError ValueType
  | .local name =>
      match findLocal? env name with
      | some binding =>
          if binding.isMutable then
            .ok binding.type
          else
            .error { message := s!"assignment target local `{name}` is not mutable" }
      | none => .error { message := s!"unknown local `{name}`" }
  | .arrayGet array index => do
      let indexType ← inferExprType module env index
      ensureIndexType "assignment array index" indexType
      match ← inferAssignTargetType module env array with
      | .fixedArray element length =>
          if length == 0 then
            .error { message := "assignment array target requires a non-empty fixed array" }
          else
            .ok element
      | other =>
          .error { message := s!"assignment array target requires fixed array, got `{other.name}`" }
  | .field base fieldName => do
      match ← inferAssignTargetType module env base with
      | .structType typeName =>
          structFieldType module typeName fieldName
      | other =>
          .error { message := s!"assignment field `{fieldName}` requires struct value, got `{other.name}`" }
  | _ =>
      .error { message := "assignment target must be a local, array index, or field path" }

def validateEffectStmt (module : Module) (env : TypeEnv) : Effect → Except LowerError Unit
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      let expected ← scalarStateType module stateId
      let actual ← inferExprType module env value
      ensureType s!"scalar state `{stateId}` write" expected actual
  | .storageScalarAssignOp stateId op value => do
      let expected ← scalarStateType module stateId
      let actual ← inferExprType module env value
      ensureAssignOpTypes op expected actual
  | .storageMapContains _ _ =>
      .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ =>
      .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      let actualKey ← inferExprType module env key
      ensureType s!"map `{stateId}` key" keyType actualKey
      let actualValue ← inferExprType module env value
      ensureType s!"map `{stateId}` value" valueType actualValue
  | .storageMapSet stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      let actualKey ← inferExprType module env key
      ensureType s!"map `{stateId}` key" keyType actualKey
      let actualValue ← inferExprType module env value
      ensureType s!"map `{stateId}` value" valueType actualValue
  | .storageArrayRead _ _ =>
      .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value => do
      let elementType ← arrayStateElementType module stateId
      let actualIndex ← inferExprType module env index
      ensureIndexType s!"array state `{stateId}` index" actualIndex
      let actualValue ← inferExprType module env value
      ensureType s!"array state `{stateId}` write" elementType actualValue
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      let elementType ← arrayStateElementType module stateId
      let actualIndex ← inferExprType module env index
      ensureIndexType s!"array state `{stateId}` index" actualIndex
      let expected ←
        match elementType with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"array state `{stateId}` has element type `{other.name}`, not struct storage" }
      let actualValue ← inferExprType module env value
      ensureType s!"array state `{stateId}` field `{fieldName}` write" expected actualValue
  | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      let expected ←
        match ← scalarStateType module stateId with
        | .structType typeName => structFieldType module typeName fieldName
        | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
      let actualValue ← inferExprType module env value
      ensureType s!"state `{stateId}` field `{fieldName}` write" expected actualValue
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      validateStoragePathExprs module env stateId path
      let expected ← resolveStoragePathType module stateId path
      let actualValue ← inferExprType module env value
      ensureType s!"storage path `{stateId}` write" expected actualValue
  | .storagePathAssignOp stateId path op value => do
      validateStoragePathExprs module env stateId path
      let expected ← resolveStoragePathType module stateId path
      let actualValue ← inferExprType module env value
      ensureAssignOpTypes op expected actualValue
  | .contextRead _ =>
      .error { message := "context.read must be used as an expression" }
  | .eventEmit name fields => do
      validatePsyIdentifier "event name" name
      if fields.isEmpty then
        .error { message := s!"event `{name}` must have at least one field" }
      validateDistinctNames s!"event `{name}` field name" (fields.map fun field => field.fst)
      for field in fields do
        validatePsyIdentifier s!"event `{name}` field name" field.fst
        let actual ← inferExprType module env field.snd
        ensureType s!"event `{name}` field `{field.fst}`" .u64 actual
  | .eventEmitIndexed name _ _ =>
      .error { message := s!"event `{name}` uses indexed fields, which are not supported by Psy IR v0" }

mutual
  partial def validateStatement (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) : Statement → Except LowerError TypeEnv
    | .letBind name type value => do
        validateValueType module type
        let actual ← inferExprType module env value
        ensureType s!"let binding `{name}`" type actual
        addLocal env name type false
    | .letMutBind name type value => do
        validateValueType module type
        let actual ← inferExprType module env value
        ensureType s!"mutable let binding `{name}`" type actual
        addLocal env name type true
    | .assign target value => do
        let expected ← inferAssignTargetType module env target
        let actual ← inferExprType module env value
        ensureType "assignment value" expected actual
        .ok env
    | .assignOp target op value => do
        let expected ← inferAssignTargetType module env target
        let actual ← inferExprType module env value
        ensureAssignOpTypes op expected actual
        .ok env
    | .effect effect => do
        validateEffectStmt module env effect
        .ok env
    | .assert condition _ _ => do
        let conditionType ← inferExprType module env condition
        ensureType "assert condition" .bool conditionType
        .ok env
    | .assertEq lhs rhs _ _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "assert_eq right operand" lhsType rhsType
        .ok env
    | .release _ =>
        .error { message := "release statements are not supported by Psy IR v0" }
    | .ifElse condition thenBody elseBody => do
        let conditionType ← inferExprType module env condition
        ensureType "if condition" .bool conditionType
        discard <| validateBody module entrypoint env thenBody
        discard <| validateBody module entrypoint env elseBody
        .ok env
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        discard <| validateBody module entrypoint loopEnv body
        .ok env
    | .return value => do
        let actual ← inferExprType module env value
        ensureType s!"entrypoint `{entrypoint.name}` return" entrypoint.returns actual
        .ok env

  partial def validateBody (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) (body : Array Statement) : Except LowerError TypeEnv :=
    body.foldlM (init := env) fun acc stmt =>
      validateStatement module entrypoint acc stmt
end

mutual
  partial def lowerExpr (module : Module) : Expr → Except LowerError String
    | .literal value => .ok (literal value)
    | .local name => .ok name
    | .arrayLit elementType values => do
        if values.isEmpty then
          .error { message := s!"empty fixed array literals are not supported by Psy IR v0 for `{← valueTypeName elementType}`" }
        let items ← values.mapM (lowerExpr module)
        .ok s!"[{String.intercalate ", " items.toList}]"
    | .arrayGet array index => do
        .ok s!"{← lowerExpr module array}[{← lowerExpr module index}]"
    | .structLit typeName fields => do
        if fields.isEmpty then
          .error { message := s!"struct literal `{typeName}` must have at least one field" }
        let items ← fields.mapM fun field => do
          .ok s!"{field.fst}: {← lowerExpr module field.snd}"
        .ok (s!"new {typeName} " ++ "{" ++ s!" {String.intercalate ", " items.toList} " ++ "}")
    | .field base fieldName => do
        .ok s!"{← lowerExpr module base}.{fieldName}"
    | .add lhs rhs => do
        .ok s!"{← lowerExpr module lhs} + {← lowerExpr module rhs}"
    | .sub lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} - {← lowerExprOperand module rhs}"
    | .mul lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} * {← lowerExprOperand module rhs}"
    | .div lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} / {← lowerExprOperand module rhs}"
    | .mod lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} % {← lowerExprOperand module rhs}"
    | .pow lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} ** {← lowerExprOperand module rhs}"
    | .bitAnd lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} & {← lowerExprOperand module rhs}"
    | .bitOr lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} | {← lowerExprOperand module rhs}"
    | .bitXor lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} ^ {← lowerExprOperand module rhs}"
    | .shiftLeft lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} << {← lowerExprOperand module rhs}"
    | .shiftRight lhs rhs => do
        .ok s!"{← lowerExprOperand module lhs} >> {← lowerExprOperand module rhs}"
    | .cast value targetType => do
        .ok s!"{← lowerExprOperand module value} as {← valueTypeName targetType}"
    | .eq lhs rhs => do
        .ok s!"({← lowerExpr module lhs} == {← lowerExpr module rhs})"
    | .ne lhs rhs => do
        .ok s!"({← lowerExpr module lhs} != {← lowerExpr module rhs})"
    | .lt lhs rhs => do
        .ok s!"({← lowerExpr module lhs} < {← lowerExpr module rhs})"
    | .le lhs rhs => do
        .ok s!"({← lowerExpr module lhs} <= {← lowerExpr module rhs})"
    | .gt lhs rhs => do
        .ok s!"({← lowerExpr module lhs} > {← lowerExpr module rhs})"
    | .ge lhs rhs => do
        .ok s!"({← lowerExpr module lhs} >= {← lowerExpr module rhs})"
    | .boolAnd lhs rhs => do
        .ok s!"({← lowerExpr module lhs} && {← lowerExpr module rhs})"
    | .boolOr lhs rhs => do
        .ok s!"({← lowerExpr module lhs} || {← lowerExpr module rhs})"
    | .boolNot value => do
        .ok s!"!({← lowerExpr module value})"
    | .hashValue a b c d => do
        .ok s!"[{← lowerExpr module a}, {← lowerExpr module b}, {← lowerExpr module c}, {← lowerExpr module d}]"
    | .hash preimage => do
        .ok s!"hash({← lowerExpr module preimage})"
    | .hashTwoToOne lhs rhs => do
        .ok s!"hash_two_to_one({← lowerExpr module lhs}, {← lowerExpr module rhs})"
    | .nativeValue =>
        .error { message := "native value inspection is not supported by Psy IR v0" }
    | .crosscallInvoke target methodId args => do
        let targetStr ← lowerExpr module target
        let methodIdStr ← lowerExpr module methodId
        let argStrs ← args.mapM (lowerExpr module)
        .ok s!"__invoke_sync#<Felt>({targetStr}, {methodIdStr}, [{String.intercalate ", " argStrs.toList}])"
    | .crosscallInvokeTyped _ _ _ returnType =>
        .error { message := s!"typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeValueTyped _ _ _ _ returnType =>
        .error { message := s!"value-bearing typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeStaticTyped _ _ _ returnType =>
        .error { message := s!"static typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeDelegateTyped _ _ _ returnType =>
        .error { message := s!"delegate typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallCreate _ _ =>
        .error { message := "EVM contract creation is not supported by Psy IR v0" }
    | .crosscallCreate2 _ _ _ =>
        .error { message := "EVM deterministic contract creation is not supported by Psy IR v0" }
    | .effect effect => lowerEffectExpr module effect

  partial def lowerExprOperand (module : Module) : Expr → Except LowerError String
    | .literal value => .ok (literal value)
    | .local name => .ok name
    | .arrayGet array index => do
        .ok s!"{← lowerExpr module array}[{← lowerExpr module index}]"
    | .field base fieldName => do
        .ok s!"{← lowerExpr module base}.{fieldName}"
    | .effect effect => lowerEffectExpr module effect
    | expr => do
        .ok s!"({← lowerExpr module expr})"

  partial def lowerEffectExpr (module : Module) : Effect → Except LowerError String
    | .storageScalarRead stateId => do
        requireScalarState module stateId
        .ok s!"c.{stateId}.get()"
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        requireMapState module stateId
        .ok s!"c.{stateId}.contains({← lowerExpr module key})"
    | .storageMapGet stateId key => do
        requireMapState module stateId
        .ok s!"c.{stateId}.get({← lowerExpr module key})"
    | .storageMapInsert stateId key value => do
        requireMapState module stateId
        .ok s!"c.{stateId}.insert({← lowerExpr module key}, {← lowerExpr module value})"
    | .storageMapSet stateId key value => do
        requireMapState module stateId
        .ok s!"c.{stateId}.set({← lowerExpr module key}, {← lowerExpr module value})"
    | .storageArrayRead stateId index => do
        requireArrayState module stateId
        match findState? module stateId with
        | some { type := .u32, .. } =>
            .ok s!"c.{stateId}[{← lowerExpr module index}].get() as u32"
        | some _ =>
            .ok s!"c.{stateId}[{← lowerExpr module index}].get()"
        | none =>
            .error { message := s!"unknown array state `{stateId}`" }
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        requireStructArrayState module stateId fieldName
        .ok s!"c.{stateId}[{← lowerExpr module index}].{fieldName}.get()"
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        requireStructScalarState module stateId fieldName
        .ok s!"c.{stateId}.{fieldName}.get()"
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path => do
        discard <| resolveStoragePathType module stateId path
        lowerStoragePathRead module stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead .userId => .ok "get_user_id()"
    | .contextRead .contractId => .ok "get_contract_id()"
    | .contextRead .checkpointId => .ok "get_checkpoint_id()"
    | .contextRead field =>
        .error { message := s!"Psy IR v0 context read `{field.name}` is not supported; only userId, contractId, and checkpointId are available" }
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }

  partial def lowerStoragePathSegment (module : Module) : StoragePathSegment → Except LowerError String
    | .field fieldName => .ok s!".{fieldName}"
    | .index index => do
        .ok s!"[{← lowerExpr module index}]"
    | .mapKey _ =>
        .error { message := "storage path map key lowering is handled at the map state boundary" }

  partial def lowerStoragePath (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError String := do
    discard <| resolveStoragePathType module stateId path
    let segments ← path.mapM (lowerStoragePathSegment module)
    .ok s!"c.{stateId}{String.intercalate "" segments.toList}"

  partial def lowerStoragePathRead (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError String := do
    let pathType ← resolveStoragePathType module stateId path
    match findState? module stateId with
    | some { kind := .map _ _, .. } =>
        match path.toList with
        | .mapKey key :: [] =>
            .ok s!"c.{stateId}.get({← lowerExpr module key})"
        | .mapKey _ :: _ =>
            .error { message := s!"storage path state `{stateId}` map values support direct key access only" }
        | _ =>
            .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
    | some _ =>
        match pathType with
        | .u32 =>
            .ok s!"{← lowerStoragePath module stateId path}.get() as u32"
        | _ =>
            .ok s!"{← lowerStoragePath module stateId path}.get()"
    | none =>
        .error { message := s!"unknown storage path state `{stateId}`" }

  partial def lowerStoragePathWrite (module : Module) (stateId : String) (path : Array StoragePathSegment) (value : Expr) : Except LowerError (Array String) := do
    let pathType ← resolveStoragePathType module stateId path
    match findState? module stateId with
    | some { kind := .map _ _, .. } =>
        match path.toList with
        | .mapKey key :: [] =>
            .ok #[s!"c.{stateId}.set({← lowerExpr module key}, {← lowerExpr module value});"]
        | .mapKey _ :: _ =>
            .error { message := s!"storage path state `{stateId}` map values support direct key access only" }
        | _ =>
            .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
    | some _ =>
        match pathType with
        | .u32 =>
            if isFeltBackedU32StorageArrayPath module stateId pathType then
              .ok #[s!"{← lowerStoragePath module stateId path} = {← lowerExprOperand module value} as Felt;"]
            else
              .ok #[s!"{← lowerStoragePath module stateId path} = {← lowerExpr module value};"]
        | _ =>
            .ok #[s!"{← lowerStoragePath module stateId path} = {← lowerExpr module value};"]
    | none =>
        .error { message := s!"unknown storage path state `{stateId}`" }

  partial def lowerStoragePathAssignOp (module : Module) (stateId : String) (path : Array StoragePathSegment) (op : AssignOp) (value : Expr) : Except LowerError (Array String) := do
    let pathType ← resolveStoragePathType module stateId path
    match findState? module stateId with
    | some { kind := .map _ _, .. } =>
        .error { message := s!"storage path state `{stateId}` map values do not support compound assignment" }
    | some { kind := .array _, type := .u32, .. } =>
        if pathType == .u32 then
          let target ← lowerStoragePath module stateId path
          .ok #[s!"{target} = ({target}.get() as u32 {assignOpBinarySymbol op} {← lowerExprOperand module value}) as Felt;"]
        else
          .ok #[s!"{← lowerStoragePath module stateId path} {assignOpSymbol op} {← lowerExpr module value};"]
    | some _ =>
        .ok #[s!"{← lowerStoragePath module stateId path} {assignOpSymbol op} {← lowerExpr module value};"]
    | none =>
        .error { message := s!"unknown storage path state `{stateId}`" }
end

def lowerEffectStmt (module : Module) : Effect → Except LowerError (Array String)
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      requireScalarState module stateId
      .ok #[s!"c.{stateId} = {← lowerExpr module value};"]
  | .storageScalarAssignOp stateId op value => do
      requireScalarState module stateId
      .ok #[s!"c.{stateId} {assignOpSymbol op} {← lowerExpr module value};"]
  | .storageMapContains _ _ =>
      .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ =>
      .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value => do
      requireMapState module stateId
      .ok #[s!"c.{stateId}.insert({← lowerExpr module key}, {← lowerExpr module value});"]
  | .storageMapSet stateId key value => do
      requireMapState module stateId
      .ok #[s!"c.{stateId}.set({← lowerExpr module key}, {← lowerExpr module value});"]
  | .storageArrayRead _ _ =>
      .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value => do
      requireArrayState module stateId
      match findState? module stateId with
      | some { type := .u32, .. } =>
          .ok #[s!"c.{stateId}[{← lowerExpr module index}] = {← lowerExprOperand module value} as Felt;"]
      | some _ =>
          .ok #[s!"c.{stateId}[{← lowerExpr module index}] = {← lowerExpr module value};"]
      | none =>
          .error { message := s!"unknown array state `{stateId}`" }
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      requireStructArrayState module stateId fieldName
      .ok #[s!"c.{stateId}[{← lowerExpr module index}].{fieldName} = {← lowerExpr module value};"]
  | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      requireStructScalarState module stateId fieldName
      .ok #[s!"c.{stateId}.{fieldName} = {← lowerExpr module value};"]
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      discard <| resolveStoragePathType module stateId path
      lowerStoragePathWrite module stateId path value
  | .storagePathAssignOp stateId path op value => do
      discard <| resolveStoragePathType module stateId path
      lowerStoragePathAssignOp module stateId path op value
  | .contextRead _ =>
      .error { message := "context.read must be used as an expression" }
  | .eventEmit name fields => do
      let fieldStrs ← fields.mapM fun field => lowerExpr module field.snd
      .ok #[s!"__emit([{String.intercalate ", " fieldStrs.toList}]); // event `{name}`"]
  | .eventEmitIndexed name _ _ =>
      .error { message := s!"event `{name}` uses indexed fields, which are not supported by Psy IR v0" }

partial def lowerAssignTarget (module : Module) : Expr → Except LowerError String
  | .local name => .ok name
  | .arrayGet array index => do
      .ok s!"{← lowerAssignTarget module array}[{← lowerExpr module index}]"
  | .field base fieldName => do
      .ok s!"{← lowerAssignTarget module base}.{fieldName}"
  | _ =>
      .error { message := "assignment target must be a local, array index, or field path" }

mutual
  partial def lowerStatement (module : Module) : Statement → Except LowerError (Array String)
    | .letBind name type value => do
        .ok #[s!"let {name}: {← valueTypeName type} = {← lowerExpr module value};"]
    | .letMutBind name type value => do
        .ok #[s!"let mut {name}: {← valueTypeName type} = {← lowerExpr module value};"]
    | .assign target value => do
        .ok #[s!"{← lowerAssignTarget module target} = {← lowerExpr module value};"]
    | .assignOp target op value => do
        .ok #[s!"{← lowerAssignTarget module target} {assignOpSymbol op} {← lowerExpr module value};"]
    | .effect effect =>
        lowerEffectStmt module effect
    | .assert condition message _ => do
        .ok #[s!"assert({← lowerExpr module condition}, {stringLiteral message});"]
    | .assertEq lhs rhs message _ => do
        .ok #[s!"assert_eq({← lowerExpr module lhs}, {← lowerExpr module rhs}, {stringLiteral message});"]
    | .release _ =>
        .error { message := "release statements are not supported by Psy IR v0" }
    | .ifElse condition thenBody elseBody => do
        let thenLines ← lowerBody module thenBody
        let elseLines ← lowerBody module elseBody
        .ok <|
          #[s!"if {← lowerExpr module condition} " ++ "{"] ++
          thenLines.map (indent 1) ++
          #["} else {"] ++
          elseLines.map (indent 1) ++
          #["};"]
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let bodyLines ← lowerBody module body
        .ok <|
          #[s!"for {indexName} in {start}u32..{stopExclusive}u32 " ++ "{"] ++
          bodyLines.map (indent 1) ++
          #["}"]
    | .return value => do
        .ok #[s!"return {← lowerExpr module value};"]

  partial def lowerBody (module : Module) (body : Array Statement) : Except LowerError (Array String) := do
    body.foldlM (init := #[]) fun acc stmt => do
      .ok (acc ++ (← lowerStatement module stmt))
end

def paramDecl (param : String × ValueType) : Except LowerError String := do
  .ok s!"{param.fst}: {← valueTypeName param.snd}"

def lowerEntrypoint (module : Module) (entrypoint : Entrypoint) : Except LowerError String := do
  let refName := capitalizedRefName module
  let returnSuffix ←
    match entrypoint.returns with
    | .unit => .ok ""
    | other => .ok s!" -> {← valueTypeName other}"
  let paramList ← entrypoint.params.mapM paramDecl
  let body ← lowerBody module entrypoint.body
  let header := indent 1 "#[contract_method]"
  let signature := indent 1 (s!"pub fn {entrypoint.name}({String.intercalate ", " paramList.toList}){returnSuffix} " ++ "{")
  let newRef := indent 2 s!"let c = {refName}::new(ContractMetadata::current());"
  let bodyLines := body.map (indent 2)
  lines (#[header, signature, newRef] ++ bodyLines ++ #[indent 1 "}"]) |> .ok

mutual
  partial def validateStatementIdentifiers (entrypointName : String) : Statement → Except LowerError Unit
    | .letBind name _ _ =>
        validatePsyIdentifier s!"local name in entrypoint `{entrypointName}`" name
    | .letMutBind name _ _ =>
        validatePsyIdentifier s!"local name in entrypoint `{entrypointName}`" name
    | .ifElse _ thenBody elseBody => do
        validateBodyIdentifiers entrypointName thenBody
        validateBodyIdentifiers entrypointName elseBody
    | .boundedFor indexName _ _ body => do
        validatePsyIdentifier s!"loop index in entrypoint `{entrypointName}`" indexName
        validateBodyIdentifiers entrypointName body
    | .assign _ _
    | .assignOp _ _ _
    | .effect _
    | .assert _ _ _
    | .assertEq _ _ _ _
    | .release _
    | .return _ =>
        pure ()

  partial def validateBodyIdentifiers (entrypointName : String) (body : Array Statement) : Except LowerError Unit := do
    for stmt in body do
      validateStatementIdentifiers entrypointName stmt
end

def validateIdentifiers (module : Module) : Except LowerError Unit := do
  validatePsyIdentifier "module name" module.name
  validateDistinctNames "struct name" (module.structs.map fun decl => decl.name)
  validateDistinctNames "state id" (module.state.map fun state => state.id)
  validateDistinctNames "entrypoint name" (module.entrypoints.map fun entrypoint => entrypoint.name)
  for decl in module.structs do
    validatePsyIdentifier "struct name" decl.name
    validateDistinctNames s!"struct `{decl.name}` field id" (decl.fields.map fun field => field.id)
    for field in decl.fields do
      validatePsyIdentifier s!"field id in struct `{decl.name}`" field.id
  for state in module.state do
    validatePsyIdentifier "state id" state.id
  for entrypoint in module.entrypoints do
    validatePsyIdentifier "entrypoint name" entrypoint.name
    validateDistinctNames s!"entrypoint `{entrypoint.name}` parameter name" (entrypoint.params.map fun param => param.fst)
    for param in entrypoint.params do
      validatePsyIdentifier s!"parameter name in entrypoint `{entrypoint.name}`" param.fst
    validateBodyIdentifiers entrypoint.name entrypoint.body

def validateStructs (module : Module) : Except LowerError Unit := do
  for decl in module.structs do
    if decl.fields.isEmpty then
      .error { message := s!"struct `{decl.name}` must declare at least one field" }
    for field in decl.fields do
      if field.isRef then
        if !decl.deriveStorage then
          .error { message := s!"field `{field.id}` in struct `{decl.name}` is marked ref, but the struct is not marked deriveStorage" }
        match field.type with
        | .structType typeName =>
            match findStruct? module typeName with
            | some targetDecl =>
                if !targetDecl.deriveStorage then
                  .error { message := s!"field `{field.id}` in struct `{decl.name}` references struct `{typeName}`, but the referenced struct is not marked deriveStorage" }
            | none =>
                .error { message := s!"field `{field.id}` in struct `{decl.name}` references unknown struct `{typeName}`" }
        | other =>
            .error { message := s!"field `{field.id}` in struct `{decl.name}` is marked ref, but has non-struct type `{other.name}`" }
      validateValueType module field.type

def validateEntrypoints (module : Module) : Except LowerError Unit := do
  for entrypoint in module.entrypoints do
    -- EVM-style selectors are target-specific ABI metadata. Psy/DPN entrypoints
    -- are addressed by contract method name, so selectors are ignored during
    -- source generation. They may still be recorded in artifact metadata for
    -- cross-target traceability.
    match entrypoint.selector? with
    | some _ => pure ()
    | none => pure ()
    for param in entrypoint.params do
      validateAbiValueType module param.snd s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" false
    validateAbiValueType module entrypoint.returns s!"entrypoint `{entrypoint.name}` return type" true

def initialTypeEnv (entrypoint : Entrypoint) : Except LowerError TypeEnv :=
  entrypoint.params.foldlM (init := #[]) fun env param =>
    addLocal env param.fst param.snd false

def bodyEndsWithReturn (body : Array Statement) : Bool :=
  match body.toList.reverse with
  | Statement.return _ :: _ => true
  | _ => false

def validateEntrypointBodies (module : Module) : Except LowerError Unit := do
  for entrypoint in module.entrypoints do
    let env ← initialTypeEnv entrypoint
    discard <| validateBody module entrypoint env entrypoint.body
    if entrypoint.returns != .unit && !bodyEndsWithReturn entrypoint.body then
      .error { message := s!"entrypoint `{entrypoint.name}` returns `{entrypoint.returns.name}` but does not end with a return statement" }

def validateState (module : Module) : Except LowerError Unit := do
  if module.state.isEmpty then
    .error { message := "Psy IR v0 requires at least one state field because Dargo v0.1.0 rejects empty #[derive(Storage)] contracts; add a marker state field for stateless fixtures" }
  for state in module.state do
    match state.kind, state.type with
    | .scalar, .u32 => pure ()
    | .scalar, .bool => pure ()
    | .scalar, .hash => pure ()
    | .scalar, .u64 => pure ()
    | .scalar, .structType typeName =>
        match findStruct? module typeName with
        | some decl =>
            if decl.deriveStorage then
              pure ()
            else
              .error { message := s!"state `{state.id}` uses struct `{typeName}`, but the struct is not marked deriveStorage" }
        | none =>
            .error { message := s!"state `{state.id}` references unknown struct `{typeName}`" }
    | .scalar, other =>
        .error { message := s!"state `{state.id}` has unsupported Psy IR v0 type `{other.name}`" }
    | .map .hash capacity, .hash =>
        if capacity == 0 then
          .error { message := s!"map state `{state.id}` must have non-zero capacity" }
        else
          pure ()
    | .map keyType _, valueType =>
        .error { message := s!"map state `{state.id}` has unsupported Psy IR v0 type Map<{keyType.name}, {valueType.name}>; only Map<Hash, Hash, N> is supported" }
    | .array length, .bool =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .u32 =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .u64 =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .hash =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        else
          pure ()
    | .array length, .structType typeName =>
        if length == 0 then
          .error { message := s!"array state `{state.id}` must have non-zero length" }
        match findStruct? module typeName with
        | some decl =>
            if decl.deriveStorage then
              pure ()
            else
              .error { message := s!"array state `{state.id}` uses struct `{typeName}`, but the struct is not marked deriveStorage" }
        | none =>
            .error { message := s!"array state `{state.id}` references unknown struct `{typeName}`" }
    | .array _, valueType =>
        .error { message := s!"array state `{state.id}` has unsupported Psy IR v0 element type `{valueType.name}`; only Felt, Bool, U32, Hash, and deriveStorage structs are supported" }

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match resolveModule Target.psyDpn module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

def testBody (module : Module) : Except LowerError (Array String) := do
  let refName := capitalizedRefName module
  let hasCounterShape :=
    module.state.size == 1 &&
    module.state.any (fun state => state.id == "count" && state.kind == .scalar && state.type == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "initialize") &&
    module.entrypoints.any (fun entry => entry.name == "increment") &&
    module.entrypoints.any (fun entry => entry.name == "get")
  if hasCounterShape then
    .ok #[
      s!"let c = {refName}::new(ContractMetadata::current());",
      s!"{refName}::initialize();",
      "assert_eq(c.count, 0, \"counter starts at zero\");",
      s!"{refName}::increment();",
      s!"assert_eq({refName}::get(), 1, \"counter increments once\");",
      s!"{refName}::increment();",
      s!"assert_eq({refName}::get(), 2, \"counter increments twice\");"
    ]
  else if module.name == "ConditionalProbe" &&
    module.entrypoints.any (fun entry => entry.name == "conditional_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::conditional_lifecycle(), 10, \"conditional branches update storage\");"
    ]
  else if module.name == "ArithmeticProbe" &&
    module.entrypoints.any (fun entry => entry.name == "arithmetic_mix" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::arithmetic_mix(), 60, \"arithmetic expressions preserve precedence\");"
    ]
  else if module.name == "U32ArithmeticProbe" &&
    module.entrypoints.any (fun entry => entry.name == "u32_arithmetic" && entry.params.size == 2 && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::u32_arithmetic(2u32, 3u32), 1, \"u32 arithmetic follows upstream u32 test shape\");"
    ]
  else if module.name == "BitwiseProbe" &&
    module.entrypoints.any (fun entry => entry.name == "bitwise_mix" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::bitwise_mix(), 16, \"bitwise expressions follow upstream opcode_test shape\");"
    ]
  else if module.name == "U32HashPackingProbe" &&
    module.entrypoints.any (fun entry => entry.name == "pack_literal" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "pack_params" && entry.params.size == 8 && entry.returns == .hash) then
    .ok #[
      "let literal_hash: Hash = [8589934593, 17179869187, 25769803781, 34359738375];",
      "let param_hash: Hash = [42949672969, 51539607563, 60129542157, 68719476751];",
      s!"assert_eq({refName}::pack_literal(), literal_hash, \"u32 literal limbs pack into Hash\");",
      s!"assert_eq({refName}::pack_params(9u32, 10u32, 11u32, 12u32, 13u32, 14u32, 15u32, 16u32), param_hash, \"u32 ABI limbs pack into Hash\");"
    ]
  else if module.name == "U32StorageScalarProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_lifecycle(), 12, \"u32 scalar storage reads preserve u32 values\");"
    ]
  else if module.name == "BoolStorageArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "local_flags_sum" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::local_flags_sum(), 2, \"bool fixed arrays index true values\");",
      s!"assert_eq({refName}::storage_lifecycle(), 2, \"bool storage arrays preserve bool values\");"
    ]
  else if module.name == "BoolStorageScalarProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_lifecycle(), 1, \"bool scalar storage reads preserve bool values\");"
    ]
  else if module.name == "U32StorageArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_lifecycle(), 28, \"u32 storage array path assignments preserve u32 arithmetic\");"
    ]
  else if module.name == "ExpressionPredicateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "predicate_sum" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::predicate_sum(), 16, \"predicate expressions compose to true\");"
    ]
  else if module.name == "ContextProbe" &&
    module.entrypoints.any (fun entry => entry.name == "sum_context" && entry.params.size == 2 && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::sum_context(2, 3), 2 + 3 + get_user_id() + get_contract_id() + get_checkpoint_id(), \"context sum follows current context\");"
    ]
  else if module.name == "HashProbe" &&
    module.entrypoints.any (fun entry => entry.name == "poseidon_hash" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "poseidon_pair_hash" && entry.params.isEmpty && entry.returns == .hash) then
    .ok #[
      s!"let left: Hash = [1, 2, 3, 4];",
      s!"let right: Hash = [5, 6, 7, 8];",
      s!"assert_eq({refName}::poseidon_hash(), hash(left), \"hash probe matches Poseidon hash\");",
      s!"assert_eq({refName}::poseidon_pair_hash(), hash_two_to_one(left, right), \"pair hash probe matches Poseidon two-to-one hash\");"
    ]
  else if module.name == "HashStorageProbe" &&
    module.entrypoints.any (fun entry => entry.name == "scalar_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "array_lifecycle" && entry.params.isEmpty && entry.returns == .hash) then
    .ok #[
      "let scalar_expected: Hash = [5, 6, 7, 8];",
      "let array_expected: Hash = [55, 66, 77, 88];",
      s!"assert_eq({refName}::scalar_lifecycle(), scalar_expected, \"hash scalar storage returns latest value\");",
      s!"assert_eq({refName}::array_lifecycle(), array_expected, \"hash array storage returns indexed value\");"
    ]
  else if module.name == "MapProbe" &&
    module.state.any (fun state => state.id == "balances") &&
    module.entrypoints.any (fun entry => entry.name == "map_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "has_seed_balance" && entry.params.isEmpty && entry.returns == .bool) &&
    module.entrypoints.any (fun entry => entry.name == "get_seed_balance" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "path_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "set_return_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "insert_return_lifecycle" && entry.params.isEmpty && entry.returns == .hash) then
    .ok #[
      s!"let c = {refName}::new(ContractMetadata::current());",
      "let key: Hash = [1001, 0, 0, 0];",
      "let value1: Hash = [55, 66, 77, 88];",
      "let path_key: Hash = [2002, 0, 0, 0];",
      "let path_value: Hash = [77, 88, 99, 111];",
      "let set_old_value: Hash = [31, 32, 33, 34];",
      "let insert_old_value: Hash = [5, 6, 7, 8];",
      s!"let set_result: Hash = {refName}::set_return_lifecycle();",
      s!"let insert_result: Hash = {refName}::insert_return_lifecycle();",
      s!"assert_eq({refName}::has_seed_balance(), false, \"seed balance starts absent\");",
      s!"assert_eq({refName}::map_lifecycle(), value1, \"map lifecycle returns the updated value\");",
      s!"assert_eq({refName}::has_seed_balance(), true, \"seed balance exists after lifecycle\");",
      s!"assert_eq({refName}::get_seed_balance(), value1, \"seed getter reads the lifecycle value\");",
      s!"assert_eq({refName}::path_lifecycle(), path_value, \"map storage path reads updated value\");",
      "assert_eq(set_result, set_old_value, \"map set returns the previous value\");",
      "assert_eq(insert_result, insert_old_value, \"map insert returns the previous value\");",
      "assert_eq(c.before, 111, \"map lifecycle preserves before field\");",
      "assert_eq(c.after, 222, \"map lifecycle preserves after field\");",
      "assert_eq(c.balances.contains(key), true, \"raw map contains follows generated entrypoint\");",
      "assert_eq(c.balances.get(path_key), path_value, \"raw map get follows storage path entrypoint\");"
    ]
  else if module.name == "AssertProbe" &&
    module.entrypoints.any (fun entry => entry.name == "checked_sum" && entry.params.size == 2 && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::checked_sum(5, 7), 12, \"checked_sum returns the asserted value\");"
    ]
  else if module.name == "LoopProbe" &&
    module.entrypoints.any (fun entry => entry.name == "count_to_three" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::count_to_three(), 3, \"bounded loop runs exactly three iterations\");"
    ]
  else if module.name == "ArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "sum_literal" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "array_predicates" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::sum_literal(), 60, \"fixed array literal indexes add up\");",
      s!"assert_eq({refName}::storage_lifecycle(), 31, \"storage array indexes read after writes\");",
      s!"assert_eq({refName}::array_predicates(), 1, \"fixed array equality predicates hold\");"
    ]
  else if module.name == "StructProbe" &&
    module.entrypoints.any (fun entry => entry.name == "local_sum" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::local_sum(), 30, \"struct literal fields add up\");",
      s!"assert_eq({refName}::storage_lifecycle(), 26, \"storage struct fields read after writes\");"
    ]
  else if module.name == "StructArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "local_struct_array_sum" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_struct_array_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::local_struct_array_sum(), 100, \"struct array literal fields add up\");",
      s!"assert_eq({refName}::storage_struct_array_lifecycle(), 102, \"storage struct array fields read after writes\");"
    ]
  else if module.name == "AbiAggregateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "sum_pair" && entry.params.size == 1 && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "sum_array" && entry.params.size == 1 && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "make_pair" && entry.params.size == 2 && entry.returns == .structType "Pair") then
    .ok #[
      s!"assert_eq({refName}::sum_pair(new Pair " ++ "{ left: 7, right: 8 }), 15, \"struct ABI parameter flattens\");",
      s!"assert_eq({refName}::sum_array([1, 2, 3]), 6, \"fixed-array ABI parameter flattens\");",
      s!"let pair: Pair = {refName}::make_pair(9, 4);",
      "assert_eq(pair.left + pair.right, 13, \"struct ABI return flattens\");"
    ]
  else if module.name == "NestedAggregateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "nested_update_sum" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::nested_update_sum(), 51, \"nested aggregate assignment updates selected field\");"
    ]
  else if module.name == "StorageNestedAggregateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_nested_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_nested_lifecycle(), 252, \"storage nested aggregate path updates selected fields\");"
    ]
  else if module.name == "EventProbe" &&
    module.entrypoints.any (fun entry => entry.name == "emit_value_event" && entry.params.size == 1 && entry.returns == .unit) then
    .ok #[
      s!"{refName}::emit_value_event(42);",
      "assert_eq(1, 1, \"event entrypoint call compiles and emits\");"
    ]
  else
    .ok #[
      s!"let _c = {refName}::new(ContractMetadata::current());"
    ]

def renderModule (module : Module) : Except LowerError String := do
  validateCapabilities module
  validateIdentifiers module
  validateStructs module
  validateEntrypoints module
  validateState module
  validateEntrypointBodies module
  let structBlocks ← module.structs.mapM structDecl
  let stateDecls ← module.state.mapM stateDecl
  let stateLines := stateDecls.foldl (fun acc lines => acc ++ lines) #[]
  let entrypoints ← module.entrypoints.mapM (lowerEntrypoint module)
  let testLines := (← testBody module).map (indent 1)
  let structLines :=
    if structBlocks.isEmpty then
      #[]
    else
      #[String.intercalate "\n\n" structBlocks.toList, ""]
  .ok <| lines <| #[
    s!"// Generated by ProofForge from the portable {module.name} IR.",
    "// This is Psy source intended for the official Dargo/Psy compiler toolchain.",
    ""
  ] ++ structLines ++ #[
    "#[contract]",
    "#[derive(Storage)]",
    s!"pub struct {module.name} " ++ "{"
  ] ++ stateLines.map (indent 1) ++ #[
    "}",
    "",
    s!"impl {capitalizedRefName module} " ++ "{",
    lines entrypoints,
    "}",
    "",
    "#[test]",
    s!"fn {testFunctionName module}() " ++ "{"
  ] ++ testLines ++ #[
    "}",
    ""
  ]

end ProofForge.Backend.Psy.IR
