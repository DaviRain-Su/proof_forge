import ProofForge.Backend.WasmHost.IR.Common

namespace ProofForge.Backend.WasmHost.IR

open ProofForge.IR

-- ---------------------------------------------------------------------------
-- Value type and literal lowering
-- ---------------------------------------------------------------------------

def valueTypeName : ValueType → Except LowerError String
  | .unit => .ok "()"
  | .bool => .ok "bool"
  | .u32 => .ok "u32"
  | .u64 => .ok "u64"
  | .hash => .ok "[u64; 4]"
  | .u8 => .ok "u32"
  | .address => .ok "u64"
  | .u128 => .error { message := "wasm-near IR v0 does not support U128" }
  | .bytes => .error { message := "wasm-near IR v0 does not support Bytes" }
  | .string => .error { message := "wasm-near IR v0 does not support String" }
  | .fixedArray element length =>
      .error { message := s!"fixed array type `{element.name}`x{length} is not supported by wasm-near IR v0" }
  | .structType name =>
      .error { message := s!"struct type `{name}` is not supported by wasm-near IR v0" }
  | .array _ =>
      .error { message := "dynamic array type is not supported by wasm-near IR v0" }

def literal : Literal → String
  | .u32 value => s!"{value}u32"
  | .u64 value => s!"{value}u64"
  | .u128 _ => "0"
  | .bool true => "true"
  | .bool false => "false"
  | .hash4 a b c d => s!"[{a}u64, {b}u64, {c}u64, {d}u64]"
  | .u8 value => s!"{value}u32"
  | .address value => s!"{value}u64"

def literalType : Literal → ValueType
  | .u32 _ => .u32
  | .u64 _ => .u64
  | .u128 _ => .u128
  | .bool _ => .bool
  | .hash4 _ _ _ _ => .hash
  | .u8 _ => .u8
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
  | .u128 value => checkedLiteralLimb "value" value 340282366920938463463374607431768211455
  | .bool _ => .ok ()
  | .hash4 a b c d => do
      checkedLiteralLimb "a" a maxU64
      checkedLiteralLimb "b" b maxU64
      checkedLiteralLimb "c" c maxU64
      checkedLiteralLimb "d" d maxU64
  | .u8 value => checkedLiteralLimb "value" value 255
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
    | .memoryArrayNew _ _ =>
        .error { message := "memory arrays are not supported by wasm-near IR v0" }
    | .memoryArrayLength _ =>
        .error { message := "memory arrays are not supported by wasm-near IR v0" }
    | .memoryArrayGet _ _ =>
        .error { message := "memory arrays are not supported by wasm-near IR v0" }
    | .structLit _ _ =>
        .error { message := "struct literals are not supported by wasm-near IR v0" }
    | .field _ _ =>
        .error { message := "struct field access is not supported by wasm-near IR v0" }
    | .ecrecover _ _ _ _ =>
        .error { message := "ecrecover (secp256k1) is EVM-specific and not supported by wasm-near IR v0" }
    | .eip712PermitDigest _ _ _ _ _ _ =>
        .error { message := "EIP-712 permit digest is EVM-specific and not supported by wasm-near IR v0" }
    | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ =>
        .error { message := "ABI-packed crosscall (Call[]) is EVM-specific and not supported by wasm-near IR v0" }
    | .add lhs rhs _ => do .ok s!"({← lowerExpr module lhs} + {← lowerExpr module rhs})"
    | .sub lhs rhs _ => do .ok s!"({← lowerExpr module lhs} - {← lowerExpr module rhs})"
    | .mul lhs rhs _ => do .ok s!"({← lowerExpr module lhs} * {← lowerExpr module rhs})"
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
    | .crosscallNamed _ _ _ _ =>
        .error { message := "named-callee cross-program calls (crosscallNamed) are not supported by wasm-near Rust sourcegen v0" }
    | .nearPromiseThen _ _ _ _
    | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported by wasm-near Rust sourcegen v0" }
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
        lowerStoragePathRead module stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is not supported by wasm-near IR v0" }
    | .contextRead .userId =>
        .ok "__pf_account_id_hash_u64(&env::predecessor_account_id())"
    | .contextRead .userIdHash =>
        .ok "__pf_predecessor_account_hash(&env::predecessor_account_id())"
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
    | .checkErc721Received _ _ _ _ =>
        .error { message := "checkErc721Received is EVM-only (PF-P2-02); not an expression on wasm-near" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not an expression on wasm-near" }

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
            | .u8 | .u32 | .u64 | .bool | .address => .ok value
            | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .u128 | .array _ =>
                .error { message := s!"event `{name}` field `{field.fst}` has unsupported wasm-near IR v0 type; event fields must be U32, U64, Bool, Hash, or Address" }
          .ok s!"\"{field.fst}\":{jsonValue}"
        let jsonParts := #[s!"\"event\":\"{name}\""] ++ fieldJson
        let logLine := "near_sdk::log!(\"{" ++ String.intercalate "," jsonParts.toList ++ "}\");"
        .ok #[logLine]
    | .eventEmitIndexed _ _ _ =>
        .error { message := "indexed events are not supported by wasm-near Rust sourcegen v0" }
    | .checkErc721Received _ _ _ _ =>
        .error { message := "checkErc721Received is EVM-only (PF-P2-02); not supported by wasm-near" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not supported by wasm-near" }

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
    | .revert message =>
        .ok #[s!"panic!({stringLiteral message});"]
    | .revertWithError _ =>
        .ok #["panic!(\"revertWithError\");"]
    | .ifElse _ _ _ =>
        .error { message := "if/else statements are not supported by wasm-near IR v0" }
    | .boundedFor _ _ _ _ =>
        .error { message := "bounded for loops are not supported by wasm-near IR v0" }
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by wasm-near IR v0" }
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

end ProofForge.Backend.WasmHost.IR
