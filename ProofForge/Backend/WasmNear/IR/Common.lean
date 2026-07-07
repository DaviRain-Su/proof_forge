import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Diagnostic
import ProofForge.Backend.SharedValidate
import ProofForge.IR.Contract
import ProofForge.Target.Check
import ProofForge.Target.Registry

namespace ProofForge.Backend.WasmNear.IR

open ProofForge.IR
open ProofForge.Target

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

instance : ProofForge.Backend.Diagnostic.LoweringError LowerError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "wasm-near" }

def capabilityError (err : CapabilityError) : LowerError := {
  message := err.render
}

-- ---------------------------------------------------------------------------
-- Source-rendering helpers (Psy IR shape)
-- ---------------------------------------------------------------------------

def indent (level : Nat) (line : String) : String :=
  String.ofList (List.replicate (level * 4) ' ') ++ line

def lines (xs : Array String) : String :=
  String.intercalate "\n" xs.toList

def stringLiteral (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

-- ---------------------------------------------------------------------------
-- Package output structures
-- ---------------------------------------------------------------------------

structure PackageFile where
  path : String
  content : String
  deriving Repr, Inhabited

structure NearPackage where
  files : Array PackageFile
  deriving Repr, Inhabited

-- ---------------------------------------------------------------------------
-- State lookup helpers
-- ---------------------------------------------------------------------------

def findState? (module : Module) (stateId : String) : Option StateDecl :=
  module.state.find? fun state => state.id == stateId

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
  | .dynamicArray => .error { message := s!"state `{stateId}` is a dynamic array, not scalar storage" }

def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let state ← stateDeclOf module stateId "map"
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }

def isMapState (module : Module) (stateId : String) : Bool :=
  match findState? module stateId with
  | some { kind := .map _ _, .. } => true
  | _ => false

def mapShapeName (keyType valueType : ValueType) (capacity : Nat) : String :=
  s!"Map<{keyType.name}, {valueType.name}, {capacity}>"

-- ---------------------------------------------------------------------------
-- Rust identifier validation
-- ---------------------------------------------------------------------------

def asciiLetters : String :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

def isRustIdentifierStart (ch : Char) : Bool :=
  ch == '_' || asciiLetters.contains ch

def isRustIdentifierContinue (ch : Char) : Bool :=
  isRustIdentifierStart ch || ch.isDigit

def rustReservedIdentifiers : Array String := #[
  "as", "async", "await", "break", "const", "continue", "crate",
  "dyn", "else", "enum", "extern", "false", "fn", "for", "if",
  "impl", "in", "let", "loop", "match", "mod", "move", "mut",
  "pub", "ref", "return", "self", "Self", "static", "struct",
  "super", "trait", "true", "type", "unsafe", "use", "where",
  "while"
]

def validateRustIdentifier (context name : String) : Except LowerError Unit :=
  if name.isEmpty then
    .error { message := s!"{context} must be a non-empty Rust identifier" }
  else if name.any (fun ch => Char.toNat ch >= 128) then
    .error { message := s!"{context} `{name}` contains non-ASCII characters; Rust identifiers must be ASCII" }
  else
    match name.toList with
    | first :: rest =>
        if !isRustIdentifierStart first || !rest.all isRustIdentifierContinue then
          .error { message := s!"{context} `{name}` is not a valid Rust identifier; identifiers must start with an ASCII letter or `_` and contain only ASCII letters, digits, or `_`" }
        else if name.startsWith "__pf_" then
          .error { message := s!"{context} `{name}` starts with `__pf_`, which is reserved for generated helpers" }
        else if rustReservedIdentifiers.any (fun reserved => reserved == name) then
          .error { message := s!"{context} `{name}` is a reserved Rust keyword" }
        else
          .ok ()
    | [] => .error { message := s!"{context} must be a non-empty Rust identifier" }

partial def validateDistinctNames (context : String) (names : Array String) : Except LowerError Unit := do
  let _ ← names.foldlM (init := #[]) fun seen name =>
    if seen.any (fun existing => existing == name) then
      .error { message := s!"duplicate {context} `{name}`" }
    else
      .ok (seen.push name)
  pure ()

-- ---------------------------------------------------------------------------
-- Type environment
-- ---------------------------------------------------------------------------

structure LocalBinding where
  name : String
  type : ValueType
  isMutable : Bool
  deriving Repr

abbrev TypeEnv := Array LocalBinding

def findLocal? (env : TypeEnv) (name : String) : Option LocalBinding :=
  env.find? fun binding => binding.name == name

def addLocal (env : TypeEnv) (name : String) (type : ValueType) (isMutable : Bool) : Except LowerError TypeEnv :=
  match findLocal? env name with
  | some _ => .error { message := s!"local `{name}` is already defined" }
  | none => .ok <| env.push { name, type, isMutable }

def ensureType (context : String) (expected actual : ValueType) : Except LowerError Unit :=
  match ProofForge.Backend.SharedValidate.ensureType context expected actual with
  | .ok _ => .ok ()
  | .error diag => .error { message := diag.message }

def ensureNumericType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 => .ok ()
  | other => .error { message := s!"{context} expected numeric `U32` or `U64`, got `{other.name}`" }

def ensureSameNumericType (operator : String) (lhs rhs : ValueType) : Except LowerError ValueType := do
  ensureNumericType s!"{operator} left operand" lhs
  ensureType s!"{operator} right operand" lhs rhs
  .ok lhs

def ensureEqType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .unit => .error { message := s!"{context} does not support Unit equality" }
  | .bool | .u8 | .u32 | .u64 | .hash | .address => .ok ()
  | .fixedArray _ _ | .structType _ | .bytes | .string | .u128 | .array _ =>
      .error { message := s!"{context} does not support `{type.name}` equality in wasm-near IR v0" }

def ensureCastType (source target : ValueType) : Except LowerError Unit :=
  match source, target with
  | .u32, .u64 => .ok ()
  | .u64, .u32 => .ok ()
  | .u32, .bool => .ok ()
  | .bool, .u64 => .ok ()
  | .bool, .u32 => .ok ()
  | .u64, .bool => .ok ()
  | source, target =>
      .error { message := s!"cast from `{source.name}` to `{target.name}` is not supported by wasm-near IR v0" }

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

def entrypointTypeEnv (entrypoint : Entrypoint) : TypeEnv :=
  (ProofForge.Backend.SharedValidate.sharedParamBindings entrypoint).map fun binding =>
    { name := binding.name, type := binding.type, isMutable := binding.isMutable : LocalBinding }

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match requireCapabilities Target.wasmNear module.capabilities with
  | .ok () => .ok ()
  | .error err => .error (capabilityError err)

def scalarStateShapeSupported (state : StateDecl) : Bool :=
  match state.type with
  | .u32 | .u64 | .bool | .hash => true
  | _ => false

def mapStateShapeSupported (state : StateDecl) : Bool :=
  match state.kind with
  | .map .u64 capacity
  | .map .hash capacity =>
      match state.type with
      | .u32 | .u64 | .bool | .hash => capacity > 0
      | _ => false
  | _ => false

def validateState (module : Module) : Except LowerError Unit := do
  for state in module.state do
    match state.kind, state.type with
    | .scalar, _ =>
        if !scalarStateShapeSupported state then
          .error { message := s!"state `{state.id}` has unsupported wasm-near IR v0 scalar type `{state.type.name}`; only U32, U64, Bool, and Hash are supported" }
    | .map _ capacity, _ =>
        if capacity == 0 then
          .error { message := s!"map state `{state.id}` must have non-zero capacity" }
        else if !mapStateShapeSupported state then
          let (keyType, valueType) :=
            match state.kind with
            | .map keyType _ => (keyType, state.type)
            | _ => (.unit, state.type)
          .error { message := s!"map state `{state.id}` has unsupported wasm-near IR v0 type `{mapShapeName keyType valueType capacity}`; only Map<U64|Hash, U32|U64|Bool|Hash, N> is supported" }
    | .array _, _ =>
        .error { message := s!"state `{state.id}` is storage.array; wasm-near IR v0 does not lower portable array storage" }
    | .dynamicArray, _ =>
        .error { message := s!"state `{state.id}` is storage.dynamicArray; wasm-near IR v0 does not lower portable dynamic array storage" }

mutual
  partial def validateStatementIdentifiers (entrypointName : String) : Statement → Except LowerError Unit
    | .letBind name _ _ =>
        validateRustIdentifier s!"local name in entrypoint `{entrypointName}`" name
    | .letMutBind name _ _ =>
        validateRustIdentifier s!"local name in entrypoint `{entrypointName}`" name
    | .ifElse _ thenBody elseBody => do
        validateBodyIdentifiers entrypointName thenBody
        validateBodyIdentifiers entrypointName elseBody
    | .boundedFor indexName _ _ body => do
        validateRustIdentifier s!"loop index in entrypoint `{entrypointName}`" indexName
        validateBodyIdentifiers entrypointName body
    | .whileLoop _ body => validateBodyIdentifiers entrypointName body
    | .assign _ _ | .assignOp _ _ _ | .effect _ | .assert _ _ _ | .assertEq _ _ _ _ | .release _ | .revert _ | .revertWithError _ | .return _ =>
        pure ()

  partial def validateBodyIdentifiers (entrypointName : String) (body : Array Statement) : Except LowerError Unit := do
    for stmt in body do
      validateStatementIdentifiers entrypointName stmt

  partial def validateEntrypointIdentifiers (module : Module) : Except LowerError Unit := do
    for entrypoint in module.entrypoints do
      validateRustIdentifier "entrypoint name" entrypoint.name
      validateDistinctNames s!"entrypoint `{entrypoint.name}` parameter name" (entrypoint.params.map fun param => param.fst)
      for param in entrypoint.params do
        validateRustIdentifier s!"parameter name in entrypoint `{entrypoint.name}`" param.fst
      validateBodyIdentifiers entrypoint.name entrypoint.body
end

def validateIdentifiers (module : Module) : Except LowerError Unit := do
  validateRustIdentifier "module name" module.name
  validateDistinctNames "struct name" (module.structs.map fun decl => decl.name)
  validateDistinctNames "state id" (module.state.map fun state => state.id)
  validateDistinctNames "entrypoint name" (module.entrypoints.map fun entrypoint => entrypoint.name)
  for decl in module.structs do
    validateRustIdentifier "struct name" decl.name
    validateDistinctNames s!"struct `{decl.name}` field id" (decl.fields.map fun field => field.id)
    for field in decl.fields do
      validateRustIdentifier s!"field id in struct `{decl.name}`" field.id
  for state in module.state do
    validateRustIdentifier "state id" state.id
  validateEntrypointIdentifiers module


def validateEntrypointParameters (entrypoint : Entrypoint) : Except LowerError Unit := do
  for param in entrypoint.params do
    match param.snd with
    | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .u128 | .array _ =>
        .error { message := s!"entrypoint `{entrypoint.name}` parameter `{param.fst}` uses `{param.snd.name}`; wasm-near IR v0 ABI parameters must use U32, U64, Bool, Hash, or Address" }
    | .u8 | .u32 | .u64 | .bool | .hash | .address => pure ()

def validateEntrypointReturn (entrypoint : Entrypoint) : Except LowerError Unit :=
  match entrypoint.returns with
  | .unit | .u8 | .u32 | .u64 | .bool | .hash | .address => pure ()
  | .fixedArray _ _ | .structType _ | .bytes | .string | .u128 | .array _ =>
      .error { message := s!"entrypoint `{entrypoint.name}` returns `{entrypoint.returns.name}`; wasm-near IR v0 supports only Unit, U32, U64, Bool, Hash, and Address" }

mutual
  partial def inferExprType (module : Module) (env : TypeEnv) : Expr → Except LowerError ValueType
    | .literal (.u32 _) => .ok .u32
    | .literal (.u64 _) => .ok .u64
    | .literal (.u128 _) => .error { message := "wasm-near IR v0 does not support U128 literals" }
    | .literal (.bool _) => .ok .bool
    | .literal (.hash4 ..) => .ok .hash
    | .literal (.u8 _) => .ok .u8
    | .literal (.address _) => .ok .address
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none => .error { message := s!"unknown local `{name}`" }
    | .arrayLit _ _ => .ok (.fixedArray .unit 0)
    | .arrayGet _ _ => .error { message := "fixed array indexing is not supported by wasm-near IR v0" }
    | .memoryArrayNew _ _ => .error { message := "memory arrays are not supported by wasm-near IR v0" }
    | .memoryArrayLength _ => .error { message := "memory arrays are not supported by wasm-near IR v0" }
    | .memoryArrayGet _ _ => .error { message := "memory arrays are not supported by wasm-near IR v0" }
    | .structLit typeName _ => .ok (.structType typeName)
    | .field _ _ => .error { message := "struct field access is not supported by wasm-near IR v0" }
    | .add lhs rhs => do ensureSameNumericType "addition" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .sub lhs rhs => do ensureSameNumericType "subtraction" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .mul lhs rhs => do ensureSameNumericType "multiplication" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .div lhs rhs => do ensureSameNumericType "division" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .mod lhs rhs => do ensureSameNumericType "modulo" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .pow lhs rhs => do ensureSameNumericType "exponentiation" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .bitAnd lhs rhs => do ensureSameNumericType "bitwise and" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .bitOr lhs rhs => do ensureSameNumericType "bitwise or" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .bitXor lhs rhs => do ensureSameNumericType "bitwise xor" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .shiftLeft lhs rhs => do ensureSameNumericType "shift-left" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .shiftRight lhs rhs => do ensureSameNumericType "shift-right" (← inferExprType module env lhs) (← inferExprType module env rhs)
    | .cast value targetType => do
        ensureCastType (← inferExprType module env value) targetType
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
    | .lt lhs rhs => do discard <| ensureSameNumericType "less-than" (← inferExprType module env lhs) (← inferExprType module env rhs); .ok .bool
    | .le lhs rhs => do discard <| ensureSameNumericType "less-or-equal" (← inferExprType module env lhs) (← inferExprType module env rhs); .ok .bool
    | .gt lhs rhs => do discard <| ensureSameNumericType "greater-than" (← inferExprType module env lhs) (← inferExprType module env rhs); .ok .bool
    | .ge lhs rhs => do discard <| ensureSameNumericType "greater-or-equal" (← inferExprType module env lhs) (← inferExprType module env rhs); .ok .bool
    | .boolAnd lhs rhs => do
        ensureType "boolean and left operand" .bool (← inferExprType module env lhs)
        ensureType "boolean and right operand" .bool (← inferExprType module env rhs)
        .ok .bool
    | .boolOr lhs rhs => do
        ensureType "boolean or left operand" .bool (← inferExprType module env lhs)
        ensureType "boolean or right operand" .bool (← inferExprType module env rhs)
        .ok .bool
    | .boolNot value => do
        ensureType "boolean not operand" .bool (← inferExprType module env value)
        .ok .bool
    | .hashValue a b c d => do
        ensureType "hash value part 0" .u64 (← inferExprType module env a)
        ensureType "hash value part 1" .u64 (← inferExprType module env b)
        ensureType "hash value part 2" .u64 (← inferExprType module env c)
        ensureType "hash value part 3" .u64 (← inferExprType module env d)
        .ok .hash
    | .hash preimage => do
        ensureType "hash preimage" .hash (← inferExprType module env preimage)
        .ok .hash
    | .hashTwoToOne lhs rhs => do
        ensureType "hash_two_to_one left operand" .hash (← inferExprType module env lhs)
        ensureType "hash_two_to_one right operand" .hash (← inferExprType module env rhs)
        .ok .hash
    | .nativeValue => .ok .u64
    | .crosscallInvoke _ _ _ => .ok .u64
    | .crosscallInvokeTyped _ _ _ returnType => .ok returnType
    | .crosscallInvokeValueTyped _ _ _ _ returnType => .ok returnType
    | .crosscallInvokeStaticTyped _ _ _ returnType => .ok returnType
    | .crosscallInvokeDelegateTyped _ _ _ returnType => .ok returnType
    | .crosscallCreate _ _ => .ok .u64
    | .crosscallCreate2 _ _ _ => .ok .u64
    | .nearCrosscallInvokePool _ _ _ _ => .ok .u64
    | .nearPromiseThen _ _ _ _ => .ok .u64
    | .nearPromiseResultsCount => .ok .u64
    | .nearPromiseResultStatus _ => .ok .u64
    | .nearPromiseResultU64 _ => .ok .u64
    | .effect effect => inferEffectExprType module env effect

  partial def inferEffectExprType (module : Module) (env : TypeEnv) : Effect → Except LowerError ValueType
    | .storageScalarRead stateId => scalarStateType module stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is not supported by wasm-near IR v0" }
    | .storageMapContains stateId key => do
        let (keyType, _) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok .bool
    | .storageMapGet stateId key => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok valueType
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
        .ok valueType
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
        .ok valueType
    | .storageArrayRead _ _ =>
        .error { message := "storage.array.read is not supported by wasm-near IR v0" }
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is not supported by wasm-near IR v0" }
    | .storageArrayStructFieldRead _ _ _ =>
        .error { message := "storage.array.struct.field.read is not supported by wasm-near IR v0" }
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is not supported by wasm-near IR v0" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is not supported by wasm-near IR v0" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is not supported by wasm-near IR v0" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory.array.set is a statement effect, not an expression" }
    | .storageStructFieldRead _ _ =>
        .error { message := "storage.struct.field.read is not supported by wasm-near IR v0" }
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is not supported by wasm-near IR v0" }
    | .storagePathRead stateId path =>
        inferStoragePathType module env stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is not supported by wasm-near IR v0" }
    | .contextRead .userIdHash => .ok .hash
    | .contextRead .origin => .ok .hash
    | .contextRead .randomSeed => .ok .hash
    | .contextRead .coinbase => .ok .hash
    | .contextRead (.blockHash _) => .ok .hash
    | .contextRead _ => .ok .u64
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }

  partial def inferStoragePathType (module : Module) (env : TypeEnv) (stateId : String) (path : Array StoragePathSegment) : Except LowerError ValueType := do
    let state ← stateDeclOf module stateId "storage path"
    match state.kind, path.toList with
    | .map keyType _, .mapKey key :: [] => do
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok state.type
    | .map _ _, .mapKey _ :: _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
    | .map _ _, [] =>
        .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
    | .map _ _, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
    | .scalar, [] =>
        .error { message := s!"storage path state `{stateId}` is scalar storage; empty paths are not supported by wasm-near IR v0" }
    | .scalar, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
    | .array _, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
    | .dynamicArray, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
end

mutual
  partial def validateStatementTypes (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) : Statement → Except LowerError TypeEnv
    | .letBind name type value => do
        ensureType s!"let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type false
    | .letMutBind name type value => do
        ensureType s!"mutable let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type true
    | .assign (.local name) value => do
        let some binding := findLocal? env name
          | .error { message := s!"unknown local `{name}`" }
        if !binding.isMutable then
          .error { message := s!"assignment target local `{name}` is not mutable" }
        ensureType "assignment value" binding.type (← inferExprType module env value)
        .ok env
    | .assign _ _ =>
        .error { message := "assignment target must be a local in wasm-near IR v0" }
    | .assignOp (.local name) op value => do
        let some binding := findLocal? env name
          | .error { message := s!"unknown local `{name}`" }
        if !binding.isMutable then
          .error { message := s!"compound assignment target local `{name}` is not mutable" }
        ensureAssignOpTypes op binding.type (← inferExprType module env value)
        .ok env
    | .assignOp _ _ _ =>
        .error { message := "compound assignment target must be a local in wasm-near IR v0" }
    | .effect effect => do
        validateEffectStmtTypes module env effect
        .ok env
    | .assert condition _ _ => do
        ensureType "assert condition" .bool (← inferExprType module env condition)
        .ok env
    | .assertEq lhs rhs _ _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "assert_eq right operand" lhsType rhsType
        ensureEqType "assert_eq" lhsType
        .ok env
    | .release _ =>
        .error { message := "release statements are not supported by wasm-near Rust sourcegen v0" }
    | .revert _ => .ok env
    | .revertWithError _ => .ok env
    | .ifElse _ _ _ =>
        .error { message := "conditional branches are not supported by wasm-near IR v0" }
    | .boundedFor _ _ _ _ =>
        .error { message := "bounded for loops are not supported by wasm-near IR v0" }
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by wasm-near IR v0" }
    | .return value => do
        ensureType "return value" entrypoint.returns (← inferExprType module env value)
        .ok env


  partial def validateEffectStmtTypes (module : Module) (env : TypeEnv) : Effect → Except LowerError Unit
    | .storageScalarRead _ =>
        .error { message := "storage.scalar.read must be used as an expression" }
    | .storageScalarWrite stateId value => do
        ensureType s!"scalar state `{stateId}` write" (← scalarStateType module stateId) (← inferExprType module env value)
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is not supported by wasm-near IR v0" }
    | .storageMapContains _ _ =>
        .error { message := "storage.map.contains must be used as an expression" }
    | .storageMapGet _ _ =>
        .error { message := "storage.map.get must be used as an expression" }
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
    | .storageArrayRead _ _ =>
        .error { message := "storage.array.read must be used as an expression" }
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is not supported by wasm-near IR v0" }
    | .storageArrayStructFieldRead _ _ _ =>
        .error { message := "storage.array.struct.field.read must be used as an expression" }
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is not supported by wasm-near IR v0" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is not supported by wasm-near IR v0" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is not supported by wasm-near IR v0" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory arrays are not supported by wasm-near IR v0" }
    | .storageStructFieldRead _ _ =>
        .error { message := "storage.struct.field.read must be used as an expression" }
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is not supported by wasm-near IR v0" }
    | .storagePathRead _ _ =>
        .error { message := "storage.path.read must be used as an expression" }
    | .storagePathWrite stateId path value => do
        ensureType s!"storage path `{stateId}` write" (← inferStoragePathType module env stateId path) (← inferExprType module env value)
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is not supported by wasm-near IR v0" }
    | .contextRead _ =>
        .error { message := "context reads must be used as expressions" }
    | .eventEmit name fields => do
        if name.isEmpty then
          .error { message := "event name must be non-empty for wasm-near IR v0" }
        let _ ← fields.foldlM (init := #[]) fun seen field =>
          if seen.contains field.fst then
            .error { message := s!"duplicate event `{name}` field name `{field.fst}`" }
          else
            .ok (seen.push field.fst)
        for field in fields do
          if field.fst.isEmpty then
            .error { message := s!"event `{name}` field name must be non-empty" }
          let actual ← inferExprType module env field.snd
          match actual with
          | .u8 | .u32 | .u64 | .bool | .hash | .address => pure ()
          | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .u128 | .array _ =>
              .error { message := s!"event `{name}` field `{field.fst}` has unsupported wasm-near IR v0 type `{actual.name}`; event fields must be U32, U64, Bool, Hash, or Address" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "indexed events are not supported by wasm-near Rust sourcegen v0" }
  partial def validateStatements (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) (statements : Array Statement) : Except LowerError TypeEnv :=
    statements.foldlM (init := env) fun acc stmt =>
      validateStatementTypes module entrypoint acc stmt
end

def validateEntrypointTypes (module : Module) (entrypoint : Entrypoint) : Except LowerError Unit := do
  discard <| validateStatements module entrypoint (entrypointTypeEnv entrypoint) entrypoint.body

def bodyEndsWithReturn (body : Array Statement) : Bool :=
  match body.toList.reverse with
  | Statement.return _ :: _ => true
  | _ => false

def validateModule (module : Module) : Except LowerError Unit := do
  validateCapabilities module
  validateIdentifiers module
  validateState module
  for entrypoint in module.entrypoints do
    validateEntrypointParameters entrypoint
    validateEntrypointReturn entrypoint
    validateEntrypointTypes module entrypoint
    if entrypoint.returns != .unit && !bodyEndsWithReturn entrypoint.body then
      .error { message := s!"entrypoint `{entrypoint.name}` returns `{entrypoint.returns.name}` but does not end with a return statement" }

end ProofForge.Backend.WasmNear.IR
