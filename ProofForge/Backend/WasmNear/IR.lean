import Init.Data.Array.Basic
import Init.Data.String.Basic
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

def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let state ← stateDeclOf module stateId "map"
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }

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
  if expected == actual then
    .ok ()
  else
    .error { message := s!"{context} expected `{expected.name}`, got `{actual.name}`" }

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
  | .bool | .u32 | .u64 | .hash | .address => .ok ()
  | .fixedArray _ _ | .structType _ | .bytes | .string =>
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
  entrypoint.params.map fun param => {
    name := param.fst
    type := param.snd
    isMutable := false
  }

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
    | .assign _ _ | .assignOp _ _ _ | .effect _ | .assert _ _ _ | .assertEq _ _ _ _ | .release _ | .return _ =>
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
    | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
        .error { message := s!"entrypoint `{entrypoint.name}` parameter `{param.fst}` uses `{param.snd.name}`; wasm-near IR v0 ABI parameters must use U32, U64, Bool, Hash, or Address" }
    | .u32 | .u64 | .bool | .hash | .address => pure ()

def validateEntrypointReturn (entrypoint : Entrypoint) : Except LowerError Unit :=
  match entrypoint.returns with
  | .unit | .u32 | .u64 | .bool | .hash | .address => pure ()
  | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error { message := s!"entrypoint `{entrypoint.name}` returns `{entrypoint.returns.name}`; wasm-near IR v0 supports only Unit, U32, U64, Bool, Hash, and Address" }

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
    | .arrayLit _ _ => .ok (.fixedArray .unit 0)
    | .arrayGet _ _ => .error { message := "fixed array indexing is not supported by wasm-near IR v0" }
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
    | .contextRead .origin => .ok .hash
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
    | .ifElse _ _ _ =>
        .error { message := "conditional branches are not supported by wasm-near IR v0" }
    | .boundedFor _ _ _ _ =>
        .error { message := "bounded for loops are not supported by wasm-near IR v0" }
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
          | .u32 | .u64 | .bool | .hash | .address => pure ()
          | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
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

-- ---------------------------------------------------------------------------
-- Value type and literal lowering
-- ---------------------------------------------------------------------------

def valueTypeName : ValueType → Except LowerError String
  | .unit => .ok "()"
  | .bool => .ok "bool"
  | .u32 => .ok "u32"
  | .u64 => .ok "u64"
  | .hash => .ok "[u64; 4]"
  | .address => .ok "u64"
  | .bytes => .error { message := "wasm-near IR v0 does not support Bytes" }
  | .string => .error { message := "wasm-near IR v0 does not support String" }
  | .fixedArray element length =>
      .error { message := s!"fixed array type `{element.name}`x{length} is not supported by wasm-near IR v0" }
  | .structType name =>
      .error { message := s!"struct type `{name}` is not supported by wasm-near IR v0" }

def literal : Literal → String
  | .u32 value => s!"{value}u32"
  | .u64 value => s!"{value}u64"
  | .bool true => "true"
  | .bool false => "false"
  | .hash4 a b c d => s!"[{a}u64, {b}u64, {c}u64, {d}u64]"
  | .address value => s!"{value}u64"

def literalType : Literal → ValueType
  | .u32 _ => .u32
  | .u64 _ => .u64
  | .bool _ => .bool
  | .hash4 _ _ _ _ => .hash
  | .address _ => .address

def maxU32 : Nat := 4294967295
def maxU64 : Nat := 18446744073709551615

def checkedLiteralLimb (name : String) (value : Nat) (max : Nat) : Except LowerError Unit :=
  if value <= max then
    .ok ()
  else
    .error { message := s!"literal limb `{name}` ({value}) exceeds U64 range" }

def checkLiteralBounds (lit : Literal) : Except LowerError Unit :=
  match lit with
  | .u32 value => checkedLiteralLimb "value" value maxU32
  | .u64 value => checkedLiteralLimb "value" value maxU64
  | .bool _ => .ok ()
  | .hash4 a b c d => do
      checkedLiteralLimb "a" a maxU64
      checkedLiteralLimb "b" b maxU64
      checkedLiteralLimb "c" c maxU64
      checkedLiteralLimb "d" d maxU64
  | .address value => checkedLiteralLimb "value" value maxU64

-- ---------------------------------------------------------------------------
-- Lowering
-- ---------------------------------------------------------------------------

mutual
  partial def lowerExpr (module : Module) : Expr → Except LowerError String
    | .literal value => do
        checkLiteralBounds value
        .ok (literal value)
    | .local name => .ok name
    | .arrayLit _ _ =>
        .error { message := "fixed array literals are not supported by wasm-near IR v0" }
    | .arrayGet _ _ =>
        .error { message := "fixed array indexing is not supported by wasm-near IR v0" }
    | .structLit _ _ =>
        .error { message := "struct literals are not supported by wasm-near IR v0" }
    | .field _ _ =>
        .error { message := "struct field access is not supported by wasm-near IR v0" }
    | .add lhs rhs => do .ok s!"({← lowerExpr module lhs} + {← lowerExpr module rhs})"
    | .sub lhs rhs => do .ok s!"({← lowerExpr module lhs} - {← lowerExpr module rhs})"
    | .mul lhs rhs => do .ok s!"({← lowerExpr module lhs} * {← lowerExpr module rhs})"
    | .div lhs rhs => do .ok s!"({← lowerExpr module lhs} / {← lowerExpr module rhs})"
    | .mod lhs rhs => do .ok s!"({← lowerExpr module lhs} % {← lowerExpr module rhs})"
    | .pow lhs rhs => do
        let lhsType ← inferExprType module #[] lhs
        if lhsType == .u32 || lhsType == .u64 then
          .ok s!"({← lowerExpr module lhs}).pow({← lowerExpr module rhs} as u32)"
        else
          .error { message := "exponentiation base must be U32 or U64 in wasm-near IR v0" }
    | .bitAnd lhs rhs => do .ok s!"({← lowerExpr module lhs} & {← lowerExpr module rhs})"
    | .bitOr lhs rhs => do .ok s!"({← lowerExpr module lhs} | {← lowerExpr module rhs})"
    | .bitXor lhs rhs => do .ok s!"({← lowerExpr module lhs} ^ {← lowerExpr module rhs})"
    | .shiftLeft lhs rhs => do .ok s!"({← lowerExpr module lhs} << {← lowerExpr module rhs})"
    | .shiftRight lhs rhs => do .ok s!"({← lowerExpr module lhs} >> {← lowerExpr module rhs})"
    | .cast value targetType => do
        let sourceType ← inferExprType module #[] value
        match sourceType, targetType with
        | .u32, .u64 => .ok s!"({← lowerExpr module value} as u64)"
        | .u64, .u32 => .ok s!"({← lowerExpr module value} as u32)"
        | .u32, .bool => .ok s!"({← lowerExpr module value} != 0)"
        | .u64, .bool => .ok s!"({← lowerExpr module value} != 0)"
        | .bool, .u32 => .ok s!"({← lowerExpr module value} as u32)"
        | .bool, .u64 => .ok s!"({← lowerExpr module value} as u64)"
        | _, _ => .error { message := s!"cast from `{sourceType.name}` to `{targetType.name}` is not supported by wasm-near IR v0" }
    | .eq lhs rhs => do .ok s!"({← lowerExpr module lhs} == {← lowerExpr module rhs})"
    | .ne lhs rhs => do .ok s!"({← lowerExpr module lhs} != {← lowerExpr module rhs})"
    | .lt lhs rhs => do .ok s!"({← lowerExpr module lhs} < {← lowerExpr module rhs})"
    | .le lhs rhs => do .ok s!"({← lowerExpr module lhs} <= {← lowerExpr module rhs})"
    | .gt lhs rhs => do .ok s!"({← lowerExpr module lhs} > {← lowerExpr module rhs})"
    | .ge lhs rhs => do .ok s!"({← lowerExpr module lhs} >= {← lowerExpr module rhs})"
    | .boolAnd lhs rhs => do .ok s!"({← lowerExpr module lhs} && {← lowerExpr module rhs})"
    | .boolOr lhs rhs => do .ok s!"({← lowerExpr module lhs} || {← lowerExpr module rhs})"
    | .boolNot value => do .ok s!"(!{← lowerExpr module value})"
    | .hashValue a b c d => do
        .ok s!"[{← lowerExpr module a}, {← lowerExpr module b}, {← lowerExpr module c}, {← lowerExpr module d}]"
    | .hash preimage => do
        .ok s!"__pf_hash({← lowerExpr module preimage})"
    | .hashTwoToOne lhs rhs => do
        .ok s!"__pf_hash_two_to_one({← lowerExpr module lhs}, {← lowerExpr module rhs})"
    | .nativeValue =>
        .ok "env::attached_deposit()"
    | .crosscallInvoke _ _ _ =>
        .error { message := "cross-contract calls are not supported by wasm-near Rust sourcegen v0" }
    | .crosscallInvokeTyped _ _ _ _
    | .crosscallInvokeValueTyped _ _ _ _ _
    | .crosscallInvokeStaticTyped _ _ _ _
    | .crosscallInvokeDelegateTyped _ _ _ _
    | .crosscallCreate _ _
    | .crosscallCreate2 _ _ _ =>
        .error { message := "cross-contract calls are not supported by wasm-near Rust sourcegen v0" }
    | .effect effect => lowerEffectExpr module effect

  partial def lowerEffectExpr (module : Module) : Effect → Except LowerError String
    | .storageScalarRead stateId => do
        discard <| scalarStateType module stateId
        .ok s!"self.{stateId}"
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is not supported by wasm-near IR v0" }
    | .storageMapContains stateId key => do
        let (keyType, _) ← mapStateTypes module stateId
        .ok s!"env::storage_has_key(&{← lowerMapKeyExpr module stateId keyType key})"
    | .storageMapGet stateId key => do
        let (keyType, valueType) ← mapStateTypes module stateId
        .ok s!"{← mapDecodeCall valueType (s!"env::storage_read(&{← lowerMapKeyExpr module stateId keyType key})")}"
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let keyStr ← lowerMapKeyExpr module stateId keyType key
        .ok s!"__pf_map_set_{mapValueSuffix valueType}(&{keyStr}, {← lowerExpr module value})"
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let keyStr ← lowerMapKeyExpr module stateId keyType key
        .ok s!"__pf_map_set_{mapValueSuffix valueType}(&{keyStr}, {← lowerExpr module value})"
    | .storageArrayRead _ _ =>
        .error { message := "storage.array.read is not supported by wasm-near IR v0" }
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is not supported by wasm-near IR v0" }
    | .storageArrayStructFieldRead _ _ _ =>
        .error { message := "storage.array.struct.field.read is not supported by wasm-near IR v0" }
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is not supported by wasm-near IR v0" }
    | .storageStructFieldRead _ _ =>
        .error { message := "storage.struct.field.read is not supported by wasm-near IR v0" }
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is not supported by wasm-near IR v0" }
    | .storagePathRead stateId path =>
        lowerStoragePathRead module stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is not supported by wasm-near IR v0" }
    | .contextRead .userId =>
        .ok "__pf_account_id_hash_u64(&env::predecessor_account_id())"
    | .contextRead .contractId =>
        .ok "__pf_account_id_hash_u64(&env::current_account_id())"
    | .contextRead .checkpointId =>
        .ok "env::block_height()"
    | .contextRead .origin =>
        .ok "__pf_account_id_hash_u64(&env::signer_account_id())"
    | .contextRead field =>
        .error { message := s!"wasm-near IR v0 context read `{field.name}` is not supported; only userId, contractId, checkpointId, and origin are available" }
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }

  partial def mapValueSuffix (valueType : ValueType) : String :=
    match valueType with
    | .u32 => "u32"
    | .u64 => "u64"
    | .bool => "bool"
    | .hash => "hash"
    | _ => "unsupported"

  partial def mapDecodeCall (valueType : ValueType) (readExpr : String) : Except LowerError String :=
    match valueType with
    | .u32 => .ok s!"__pf_decode_u32({readExpr})"
    | .u64 => .ok s!"__pf_decode_u64({readExpr})"
    | .bool => .ok s!"__pf_decode_bool({readExpr})"
    | .hash => .ok s!"__pf_decode_hash({readExpr})"
    | _ => .error { message := s!"map value type `{valueType.name}` is not supported by wasm-near IR v0" }

  partial def lowerMapKeyExpr (module : Module) (stateId : String) (keyType : ValueType) (key : Expr) : Except LowerError String := do
    match keyType with
    | .u64 =>
        match key with
        | .literal value => .ok s!"__pf_map_key_u64(\"{stateId}\", {literal value})"
        | _ => .ok s!"__pf_map_key_u64(\"{stateId}\", {← lowerExpr module key})"
    | .hash =>
        match key with
        | .literal value => .ok s!"__pf_map_key_hash(\"{stateId}\", {literal value})"
        | _ => .ok s!"__pf_map_key_hash(\"{stateId}\", {← lowerExpr module key})"
    | _ => .error { message := s!"map key type `{keyType.name}` is not supported by wasm-near IR v0" }

  partial def lowerStoragePathRead (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError String := do
    let state ← stateDeclOf module stateId "storage path"
    match state.kind, path.toList with
    | .map keyType _, .mapKey key :: [] => do
        let (keyType', valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType keyType'
        .ok s!"{← mapDecodeCall valueType (s!"env::storage_read(&{← lowerMapKeyExpr module stateId keyType key})")}"
    | .map _ _, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
    | _, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
  partial def lowerEffectStmt (module : Module) : Effect → Except LowerError (Array String)
    | .storageScalarRead _ =>
        .error { message := "storage.scalar.read must be used as an expression" }
    | .storageScalarWrite stateId value => do
        discard <| scalarStateType module stateId
        .ok #[s!"self.{stateId} = {← lowerExpr module value};"]
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is not supported by wasm-near IR v0" }
    | .storageMapContains _ _ =>
        .error { message := "storage.map.contains must be used as an expression" }
    | .storageMapGet _ _ =>
        .error { message := "storage.map.get must be used as an expression" }
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let keyStr ← lowerMapKeyExpr module stateId keyType key
        .ok #[s!"let _ = __pf_map_set_{mapValueSuffix valueType}(&{keyStr}, {← lowerExpr module value});"]
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        let keyStr ← lowerMapKeyExpr module stateId keyType key
        .ok #[s!"let _ = __pf_map_set_{mapValueSuffix valueType}(&{keyStr}, {← lowerExpr module value});"]
    | .storageArrayRead _ _ =>
        .error { message := "storage.array.read must be used as an expression" }
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is not supported by wasm-near IR v0" }
    | .storageArrayStructFieldRead _ _ _ =>
        .error { message := "storage.array.struct.field.read must be used as an expression" }
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is not supported by wasm-near IR v0" }
    | .storageStructFieldRead _ _ =>
        .error { message := "storage.struct.field.read must be used as an expression" }
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is not supported by wasm-near IR v0" }
    | .storagePathRead _ _ =>
        .error { message := "storage.path.read must be used as an expression" }
    | .storagePathWrite stateId path value => do
        lowerStoragePathWrite module stateId path value
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is not supported by wasm-near IR v0" }
    | .contextRead _ =>
        .error { message := "context reads must be used as expressions" }
    | .eventEmit name fields => do
        if name.isEmpty then
          .error { message := "event name must be non-empty for wasm-near IR v0" }
        let fieldJson ← fields.mapM fun field => do
          if field.fst.isEmpty then
            .error { message := s!"event `{name}` field name must be non-empty" }
          let value ← lowerExpr module field.snd
          let jsonValue ← match ← inferExprType module #[] field.snd with
            | .hash => .ok s!"[{value}[0], {value}[1], {value}[2], {value}[3]]"
            | .u32 | .u64 | .bool | .address => .ok value
            | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
                .error { message := s!"event `{name}` field `{field.fst}` has unsupported wasm-near IR v0 type; event fields must be U32, U64, Bool, Hash, or Address" }
          .ok s!"\"{field.fst}\":{jsonValue}"
        let jsonParts := #[s!"\"event\":\"{name}\""] ++ fieldJson
        let logLine := "near_sdk::log!(\"{" ++ String.intercalate "," jsonParts.toList ++ "}\");"
        .ok #[logLine]
    | .eventEmitIndexed _ _ _ =>
        .error { message := "indexed events are not supported by wasm-near Rust sourcegen v0" }

  partial def lowerStoragePathWrite (module : Module) (stateId : String) (path : Array StoragePathSegment) (value : Expr) : Except LowerError (Array String) := do
    let state ← stateDeclOf module stateId "storage path"
    match state.kind, path.toList with
    | .map keyType _, .mapKey key :: [] => do
        let (actualKeyType, valueType) ← mapStateTypes module stateId
        ensureType (s!"map `" ++ stateId ++ "` key") actualKeyType keyType
        let keyStr ← lowerMapKeyExpr module stateId keyType key
        .ok #[s!"let _ = __pf_map_set_{mapValueSuffix valueType}(&{keyStr}, {← lowerExpr module value});"]
    | .map _ _, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }
    | _, _ =>
        .error { message := "wasm-near IR v0 supports only single-segment mapKey storage paths" }

  partial def lowerStatement (module : Module) : Statement → Except LowerError (Array String)
    | .letBind name type value => do
        .ok #[s!"let {name}: {← valueTypeName type} = {← lowerExpr module value};"]
    | .letMutBind name type value => do
        .ok #[s!"let mut {name}: {← valueTypeName type} = {← lowerExpr module value};"]
    | .assign (.local name) value => do
        .ok #[s!"{name} = {← lowerExpr module value};"]
    | .assign _ _ =>
        .error { message := "assignment target must be a local in wasm-near IR v0" }
    | .assignOp (.local name) op value => do
        .ok #[s!"{name} {assignOpSymbol op} {← lowerExpr module value};"]
    | .assignOp _ _ _ =>
        .error { message := "compound assignment target must be a local in wasm-near IR v0" }
    | .effect effect =>
        lowerEffectStmt module effect
    | .assert condition message _ => do
        .ok #[s!"assert!({← lowerExpr module condition}, {stringLiteral message});"]
    | .assertEq lhs rhs message _ => do
        .ok #[s!"assert_eq!({← lowerExpr module lhs}, {← lowerExpr module rhs}, {stringLiteral message});"]
    | .release _ =>
        .error { message := "release statements are not supported by wasm-near Rust sourcegen v0" }
    | .ifElse _ _ _ =>
        .error { message := "if/else statements are not supported by wasm-near IR v0" }
    | .boundedFor _ _ _ _ =>
        .error { message := "bounded for loops are not supported by wasm-near IR v0" }
    | .return value => do
        .ok #[s!"return {← lowerExpr module value};"]

  partial def lowerBody (module : Module) (body : Array Statement) : Except LowerError (Array String) := do
    body.foldlM (init := #[]) fun acc stmt => do
      .ok (acc ++ (← lowerStatement module stmt))
end

-- ---------------------------------------------------------------------------
-- Helper detection and generation
-- ---------------------------------------------------------------------------

def moduleUsesMap (module : Module) : Bool :=
  module.state.any fun state =>
    match state.kind with | .map _ _ => true | _ => false

def mapValueTypesUsed (module : Module) : Array ValueType :=
  let types := module.state.foldl (init := #[]) fun acc state =>
    match state.kind with
    | .map _ _ => if acc.contains state.type then acc else acc.push state.type
    | _ => acc
  types.filter fun t =>
    match t with | .u32 | .u64 | .bool | .hash => true | _ => false

def moduleUsesHash (module : Module) : Bool :=
  module.capabilities.contains .cryptoHash

def moduleUsesAccountIdHash (module : Module) : Bool :=
  module.capabilities.contains .callerSender || module.capabilities.contains .accountExplicit

def mapKeyTypesUsed (module : Module) : Array ValueType :=
  let types := module.state.foldl (init := #[]) fun acc state =>
    match state.kind with
    | .map keyType _ => if acc.contains keyType then acc else acc.push keyType
    | _ => acc
  types.filter fun t =>
    match t with | .u64 | .hash => true | _ => false

def scalarDefaultValue (type : ValueType) : String :=
  match type with
  | .u32 => "0u32"
  | .u64 => "0u64"
  | .bool => "false"
  | .hash => "[0u64, 0u64, 0u64, 0u64]"
  | _ => "()"

def scalarRustField (state : StateDecl) : String :=
  match state.type with
  | .u32 => s!"pub {state.id}: u32,"
  | .u64 => s!"pub {state.id}: u64,"
  | .bool => s!"pub {state.id}: bool,"
  | .hash => s!"pub {state.id}: [u64; 4],"
  | _ => s!"pub {state.id}: (),"
def accountIdHashHelper : String :=
  "fn __pf_account_id_hash_u64(account_id: &AccountId) -> u64 {\n" ++
  "    let hash = env::sha256(account_id.as_bytes());\n" ++
  "    u64::from_le_bytes(hash[0..8].try_into().unwrap())\n" ++
  "}\n"

def hashHelpers : String :=
  "fn __pf_hash(value: [u64; 4]) -> [u64; 4] {\n" ++
  "    let mut bytes = Vec::with_capacity(32);\n" ++
  "    for limb in value {\n" ++
  "        bytes.extend_from_slice(&limb.to_le_bytes());\n" ++
  "    }\n" ++
  "    let hash = env::sha256(&bytes);\n" ++
  "    [\n" ++
  "        u64::from_le_bytes(hash[0..8].try_into().unwrap()),\n" ++
  "        u64::from_le_bytes(hash[8..16].try_into().unwrap()),\n" ++
  "        u64::from_le_bytes(hash[16..24].try_into().unwrap()),\n" ++
  "        u64::from_le_bytes(hash[24..32].try_into().unwrap()),\n" ++
  "    ]\n" ++
  "}\n" ++
  "\n" ++
  "fn __pf_hash_two_to_one(left: [u64; 4], right: [u64; 4]) -> [u64; 4] {\n" ++
  "    let mut bytes = Vec::with_capacity(64);\n" ++
  "    for limb in left {\n" ++
  "        bytes.extend_from_slice(&limb.to_le_bytes());\n" ++
  "    }\n" ++
  "    for limb in right {\n" ++
  "        bytes.extend_from_slice(&limb.to_le_bytes());\n" ++
  "    }\n" ++
  "    let hash = env::sha256(&bytes);\n" ++
  "    [\n" ++
  "        u64::from_le_bytes(hash[0..8].try_into().unwrap()),\n" ++
  "        u64::from_le_bytes(hash[8..16].try_into().unwrap()),\n" ++
  "        u64::from_le_bytes(hash[16..24].try_into().unwrap()),\n" ++
  "        u64::from_le_bytes(hash[24..32].try_into().unwrap()),\n" ++
  "    ]\n" ++
  "}\n"

def mapKeyHelpers (keyTypes : Array ValueType) : String :=
  let u64Helper :=
    "fn __pf_map_key_u64(prefix: &str, key: u64) -> Vec<u8> {\n" ++
    "    let mut bytes = Vec::with_capacity(prefix.len() + 9);\n" ++
    "    bytes.extend_from_slice(prefix.as_bytes());\n" ++
    "    bytes.push(b':');\n" ++
    "    bytes.extend_from_slice(&key.to_le_bytes());\n" ++
    "    bytes\n" ++
    "}\n"
  let hashHelper :=
    "fn __pf_map_key_hash(prefix: &str, key: [u64; 4]) -> Vec<u8> {\n" ++
    "    let mut bytes = Vec::with_capacity(prefix.len() + 33);\n" ++
    "    bytes.extend_from_slice(prefix.as_bytes());\n" ++
    "    bytes.push(b':');\n" ++
    "    for limb in key {\n" ++
    "        bytes.extend_from_slice(&limb.to_le_bytes());\n" ++
    "    }\n" ++
    "    bytes\n" ++
    "}\n"
  let parts := keyTypes.foldl (init := #[]) fun acc t =>
    match t with
    | .u64 => if acc.contains u64Helper then acc else acc.push u64Helper
    | .hash => if acc.contains hashHelper then acc else acc.push hashHelper
    | _ => acc
  String.intercalate "\n" parts.toList

def codecHelpers (valueTypes : Array ValueType) : String :=
  let u32Encode :=
    "fn __pf_encode_u32(value: u32) -> Vec<u8> {\n" ++
    "    value.to_le_bytes().to_vec()\n" ++
    "}\n" ++
    "\n" ++
    "fn __pf_decode_u32(bytes: Option<Vec<u8>>) -> u32 {\n" ++
    "    match bytes {\n" ++
    "        Some(b) if b.len() >= 4 => u32::from_le_bytes(b[0..4].try_into().unwrap()),\n" ++
    "        _ => 0u32,\n" ++
    "    }\n" ++
    "}\n"
  let u64Encode :=
    "fn __pf_encode_u64(value: u64) -> Vec<u8> {\n" ++
    "    value.to_le_bytes().to_vec()\n" ++
    "}\n" ++
    "\n" ++
    "fn __pf_decode_u64(bytes: Option<Vec<u8>>) -> u64 {\n" ++
    "    match bytes {\n" ++
    "        Some(b) if b.len() >= 8 => u64::from_le_bytes(b[0..8].try_into().unwrap()),\n" ++
    "        _ => 0u64,\n" ++
    "    }\n" ++
    "}\n"
  let boolEncode :=
    "fn __pf_encode_bool(value: bool) -> Vec<u8> {\n" ++
    "    vec![if value { 1 } else { 0 }]\n" ++
    "}\n" ++
    "\n" ++
    "fn __pf_decode_bool(bytes: Option<Vec<u8>>) -> bool {\n" ++
    "    match bytes {\n" ++
    "        Some(b) if !b.is_empty() => b[0] != 0,\n" ++
    "        _ => false,\n" ++
    "    }\n" ++
    "}\n"
  let hashEncode :=
    "fn __pf_encode_hash(value: [u64; 4]) -> Vec<u8> {\n" ++
    "    let mut bytes = Vec::with_capacity(32);\n" ++
    "    for limb in value {\n" ++
    "        bytes.extend_from_slice(&limb.to_le_bytes());\n" ++
    "    }\n" ++
    "    bytes\n" ++
    "}\n" ++
    "\n" ++
    "fn __pf_decode_hash(bytes: Option<Vec<u8>>) -> [u64; 4] {\n" ++
    "    match bytes {\n" ++
    "        Some(b) if b.len() >= 32 => [\n" ++
    "            u64::from_le_bytes(b[0..8].try_into().unwrap()),\n" ++
    "            u64::from_le_bytes(b[8..16].try_into().unwrap()),\n" ++
    "            u64::from_le_bytes(b[16..24].try_into().unwrap()),\n" ++
    "            u64::from_le_bytes(b[24..32].try_into().unwrap()),\n" ++
    "        ],\n" ++
    "        _ => [0u64; 4],\n" ++
    "    }\n" ++
    "}\n"
  let parts := valueTypes.foldl (init := #[]) fun acc t =>
    match t with
    | .u32 => if acc.contains u32Encode then acc else acc.push u32Encode
    | .u64 => if acc.contains u64Encode then acc else acc.push u64Encode
    | .bool => if acc.contains boolEncode then acc else acc.push boolEncode
    | .hash => if acc.contains hashEncode then acc else acc.push hashEncode
    | _ => acc
  String.intercalate "\n" parts.toList

def mapSetHelpers (module : Module) : String :=
  let helperPairs := module.state.foldl (init := #[]) fun acc state =>
    match state.kind with
    | .map _ _ =>
        let suffix := mapValueSuffix state.type
        let rustType := match state.type with | .u32 => "u32" | .u64 => "u64" | .bool => "bool" | .hash => "[u64; 4]" | _ => "()"
        let decodeFn := match state.type with | .u32 => "__pf_decode_u32" | .u64 => "__pf_decode_u64" | .bool => "__pf_decode_bool" | .hash => "__pf_decode_hash" | _ => ""
        let encodeFn := match state.type with | .u32 => "__pf_encode_u32" | .u64 => "__pf_encode_u64" | .bool => "__pf_encode_bool" | .hash => "__pf_encode_hash" | _ => ""
        let decl :=
          "fn __pf_map_set_" ++ suffix ++ "(key: &[u8], value: " ++ rustType ++ ") -> " ++ rustType ++ " {\n" ++
          "    let old = " ++ decodeFn ++ "(env::storage_read(key));\n" ++
          "    env::storage_write(key, &" ++ encodeFn ++ "(value));\n" ++
          "    old\n" ++
          "}\n"
        if acc.any (fun existing => existing == decl) then acc else acc.push decl
    | _ => acc
  String.intercalate "\n" helperPairs.toList

def moduleHelpers (module : Module) : String :=
  let parts :=
    (if moduleUsesMap module then
      #[mapKeyHelpers (mapKeyTypesUsed module), codecHelpers (mapValueTypesUsed module), mapSetHelpers module]
    else #[]) ++
    (if moduleUsesAccountIdHash module then #[accountIdHashHelper] else #[]) ++
    (if moduleUsesHash module then #[hashHelpers] else #[])
  let nonEmpty := parts.filter fun s => s != ""
  if nonEmpty.isEmpty then
    ""
  else
    "\n" ++ String.intercalate "\n" nonEmpty.toList ++ "\n"

-- ---------------------------------------------------------------------------
-- Module rendering
-- ---------------------------------------------------------------------------

def sanitizedPackageName (moduleName : String) : String :=
  let kebab := moduleName.toLower
  kebab

def paramDecl (param : String × ValueType) : Except LowerError String := do
  .ok s!"{param.fst}: {← valueTypeName param.snd}"

def lowerEntrypoint (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array String) := do
  let returnSuffix ←
    match entrypoint.returns with
    | .unit => .ok ""
    | other => .ok s!" -> {← valueTypeName other}"
  let paramList ← entrypoint.params.mapM paramDecl
  let body ← lowerBody module entrypoint.body
  let header := indent 1 (s!"pub fn {entrypoint.name}({String.intercalate ", " paramList.toList}){returnSuffix} " ++ "{")
  let bodyLines := body.map (indent 2)
  let closer := indent 1 "}"
  .ok <| #[header] ++ bodyLines ++ #[closer]

def cargoToml (module : Module) : String :=
  let packageName := sanitizedPackageName module.name
  "[package]\n" ++
  "name = \"" ++ packageName ++ "\"\n" ++
  "version = \"0.1.0\"\n" ++
  "edition = \"2021\"\n" ++
  "\n" ++
  "[lib]\n" ++
  "crate-type = [\"cdylib\", \"rlib\"]\n" ++
  "\n" ++
  "[dependencies]\n" ++
  "near-sdk = \"5\"\n" ++
  "borsh = \"1\"\n" ++
  "serde = { version = \"1\", features = [\"derive\"] }\n" ++
  "serde_json = \"1\"\n"

def renderLibRs (module : Module) : Except LowerError String := do
  validateModule module
  let scalarFields := module.state.filter fun state =>
    match state.kind with | .scalar => true | _ => false
  let scalarFieldLines := scalarFields.map scalarRustField
  let defaultFieldLines := scalarFields.map fun state =>
    indent 2 s!"{state.id}: {scalarDefaultValue state.type},"
  let entrypointBlocks ← module.entrypoints.mapM (lowerEntrypoint module)
  let entrypoints := entrypointBlocks.foldl (fun acc block => acc ++ block) #[]
  let helpers := moduleHelpers module
  let header := #[
    s!"// Generated by ProofForge from the portable {module.name} IR.",
    "// This is Rust source intended for near-sdk-rs and wasm32-unknown-unknown.",
    "",
    "use near_sdk::{env, near, AccountId};",
    "use near_sdk::borsh::{BorshDeserialize, BorshSerialize};",
    "use near_sdk::serde::{Deserialize, Serialize};",
    ""
  ]
  let contractStateAttr := "#[near(contract_state)]"
  let deriveAttr := "#[derive(BorshDeserialize, BorshSerialize)]"
  let structOpen := "pub struct " ++ module.name ++ " {"
  let structBody := header ++ #[contractStateAttr, deriveAttr, structOpen] ++ scalarFieldLines.map (indent 1) ++ #["}"]
  let defaultImpl := #[
    "",
    "impl Default for " ++ module.name ++ " {",
    indent 1 "fn default() -> Self {",
    indent 2 "Self {"
  ] ++ defaultFieldLines ++ #[
    indent 2 "}",
    indent 1 "}",
    "}"
  ]
  let nearAttr := "#[near]"
  let implOpen := "impl " ++ module.name ++ " {"
  let implBlock := #["", nearAttr, implOpen] ++ entrypoints ++ #["}"]
  let trailer := if helpers.isEmpty then #[] else #["", helpers]
  .ok <| lines <| structBody ++ defaultImpl ++ implBlock ++ trailer

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

def renderPackage (module : Module) : Except LowerError NearPackage := do
  let libRs ← renderLibRs module
  .ok {
    files := #[
      { path := "Cargo.toml", content := cargoToml module },
      { path := "src/lib.rs", content := libRs }
    ]
  }

def renderModule (module : Module) : Except LowerError String := do
  let pkg ← renderPackage module
  let some libRs := pkg.files.find? (fun file => file.path == "src/lib.rs")
    | .error { message := "internal: renderPackage did not produce src/lib.rs" }
  .ok libRs.content

end ProofForge.Backend.WasmNear.IR
