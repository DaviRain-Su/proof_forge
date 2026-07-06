import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Evm.Plan
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Util.StringUtil

namespace ProofForge.Backend.Evm.Validate

open ProofForge.IR
open ProofForge.Target
open ProofForge.Util.StringUtil

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

def diagnosticError (err : Diagnostic) : LowerError := {
  message := err.render
}

def planError (err : ProofForge.Backend.Evm.Plan.PlanError) : LowerError := {
  message := err.render
}

def toYulError (message : String) : LowerError := {
  message
}

def lowerPlan
    {α : Type}
    (result : Except ProofForge.Backend.Evm.Plan.PlanError α) : Except LowerError α :=
  match result with
  | .ok value => .ok value
  | .error err => .error (planError err)

def stateInfo? (module : Module) (stateId : String) : Option (Nat × StateDecl) :=
  ProofForge.Backend.Evm.Plan.stateInfo? module stateId

def stateSlot? (module : Module) (stateId : String) : Option Nat :=
  match stateInfo? module stateId with
  | some (slot, _) => some slot
  | none => none

def isHexChar (c : Char) : Bool :=
  ('0' <= c && c <= '9') ||
  ('a' <= c && c <= 'f') ||
  ('A' <= c && c <= 'F')

def normalizeInitCodeHex (context initCodeHex : String) : Except LowerError String := do
  let raw := stripHexPrefix initCodeHex
  if raw.isEmpty then
    .error { message := s!"{context} init code must be non-empty hex" }
  else if raw.length % 2 != 0 then
    .error { message := s!"{context} init code hex must have an even number of digits" }
  else if !(raw.all isHexChar) then
    .error { message := s!"{context} init code must contain only hex digits" }
  else
    .ok raw

def twoPow64 : Nat := 18446744073709551616
def maxU64 : Nat := twoPow64 - 1
def maxU32 : Nat := 4294967295

-- ASCII "PROOF_FORGE_MAP_PRESENCE" packed as one EVM word.
def mapPresenceDomain : Nat := 1969478005224772198022937154314036040895674356107534287685

def checkedHashLiteralLimb (name : String) (value : Nat) : Except LowerError Nat :=
  if value <= maxU64 then
    .ok value
  else
    .error { message := s!"Hash literal limb `{name}` exceeds U64 range" }

def packedHashLiteral (a b c d : Nat) : Except LowerError Nat := do
  let a ← checkedHashLiteralLimb "a" a
  let b ← checkedHashLiteralLimb "b" b
  let c ← checkedHashLiteralLimb "c" c
  let d ← checkedHashLiteralLimb "d" d
  .ok ((((a * twoPow64) + b) * twoPow64 + c) * twoPow64 + d)

def validateEventName (name : String) : Except LowerError Unit := do
  if name.toUTF8.size == 0 then
    .error { message := "event name must be non-empty for IR EVM v0" }

def packedUtf8Words (value : String) : Array Nat × Nat := Id.run do
  let bytes := value.toUTF8
  let wordCount := (bytes.size + 31) / 32
  let mut words := #[]
  for _h : wordIdx in [0:wordCount] do
    let mut wordVal := 0
    for _h : byteIdx in [0:32] do
      let pos := wordIdx * 32 + byteIdx
      if pos < bytes.size then
        let b := (bytes.get! pos).toNat
        let shift := (31 - byteIdx) * 8
        wordVal := wordVal + (b * (2 ^ shift))
    words := words.push wordVal
  pure (words, bytes.size)

partial def eventSignatureFieldType (module : Module) (eventName fieldName : String) (type : ValueType) : Except LowerError String :=
  let erc20FieldType? : Option String :=
    if eventName == "Transfer" then
      if fieldName == "from" || fieldName == "to" then some "address"
      else if fieldName == "value" then some "uint256" else none
    else if eventName == "Approval" then
      if fieldName == "owner" || fieldName == "spender" then some "address"
      else if fieldName == "value" then some "uint256" else none
    else none
  match erc20FieldType? with
  | some abiType => .ok abiType
  | none =>
      match type with
      | .u32 => .ok "uint32"
      | .u64 => .ok "uint64"
      | .bool => .ok "bool"
      | .hash => .ok "bytes32"
      | .address => .ok "address"
      | .u8 => .ok "uint8"
      | .u128 => .ok "uint128"
      | .bytes => .ok "bytes"
      | .string => .ok "string"
      | .fixedArray elementType length => do
          if length == 0 then
            .error { message := s!"event `{eventName}` field `{fieldName}` uses Array<{elementType.name},0>; event fixed arrays must have non-zero length" }
          match elementType with
          | .fixedArray _ _ => do
              let elementName ← eventSignatureFieldType module eventName fieldName elementType
              .ok (elementName ++ s!"[{length}]")
          | .structType typeName => do
              let some decl := module.structs.find? fun decl => decl.name == typeName
                | .error { message := s!"event `{eventName}` field `{fieldName}` uses unknown struct `{typeName}`" }
              if decl.fields.isEmpty then
                .error { message := s!"event `{eventName}` field `{fieldName}` uses empty struct `{typeName}`; event structs must have at least one field" }
              let mut parts := #[]
              for field in decl.fields do
                match field.type with
                | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
                    parts := parts.push (← eventSignatureFieldType module eventName s!"{fieldName}.{field.id}" field.type)
                | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
                    .error {
                      message := s!"event `{eventName}` field `{fieldName}` struct `{typeName}` field `{field.id}` has unsupported EVM IR v0 event type `{field.type.name}`; event structs must be flat U32, U64, Bool, or Hash fields"
                    }
              .ok ("(" ++ String.intercalate "," parts.toList ++ ")" ++ s!"[{length}]")
          | _ => do
              let elementName ← eventSignatureFieldType module eventName fieldName elementType
              .ok (elementName ++ s!"[{length}]")
      | .array _ =>
          .error { message := s!"event `{eventName}` field `{fieldName}` has unsupported EVM IR v0 type `Array`; dynamic arrays are not supported in EVM event signatures" }
      | .unit =>
          .error { message := s!"event `{eventName}` field `{fieldName}` has unsupported EVM IR v0 type `Unit`; event fields must be U32, U64, Bool, Hash, Address, Bytes, String, flat structs, or fixed arrays" }
      | .structType typeName => do
          let some decl := module.structs.find? fun decl => decl.name == typeName
            | .error { message := s!"event `{eventName}` field `{fieldName}` uses unknown struct `{typeName}`" }
          if decl.fields.isEmpty then
            .error { message := s!"event `{eventName}` field `{fieldName}` uses empty struct `{typeName}`; event structs must have at least one field" }
          let mut parts := #[]
          for field in decl.fields do
            match field.type with
            | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
                parts := parts.push (← eventSignatureFieldType module eventName s!"{fieldName}.{field.id}" field.type)
            | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
                .error {
                  message := s!"event `{eventName}` field `{fieldName}` struct `{typeName}` field `{field.id}` has unsupported EVM IR v0 event type `{field.type.name}`; event structs must be flat U32, U64, Bool, or Hash fields"
                }
          .ok ("(" ++ String.intercalate "," parts.toList ++ ")")

def ensureIndexedEventFieldType
    (module : Module)
    (eventName fieldName : String)
    (type : ValueType) : Except LowerError Unit := do
  discard <| eventSignatureFieldType module eventName fieldName type

def validateEventFieldName (eventName fieldName : String) : Except LowerError Unit :=
  if fieldName.isEmpty then
    .error { message := s!"event `{eventName}` field name must be non-empty" }
  else
    .ok ()

def validateDistinctEventFieldName (eventName : String) (seen : Array String) (fieldName : String) : Except LowerError (Array String) := do
  validateEventFieldName eventName fieldName
  if seen.contains fieldName then
    .error { message := s!"duplicate event `{eventName}` field name `{fieldName}`" }
  else
    .ok (seen.push fieldName)

def storagePathMapKeys? (path : Array StoragePathSegment) : Option (Array ProofForge.IR.Expr) :=
  if path.isEmpty then
    none
  else
    path.foldl (init := some #[]) fun acc segment =>
      match acc, segment with
      | some keys, .mapKey key => some (keys.push key)
      | _, _ => none

def validateIndexedEventFieldCount (eventName : String) (count : Nat) : Except LowerError Unit :=
  if count > 3 then
    .error { message := s!"event `{eventName}` has {count} indexed field(s); EVM IR v0 supports at most 3 indexed fields" }
  else
    .ok ()

def eventIndexedTopicName (index : Nat) : String :=
  s!"_indexed_topic{index}"

def eventLogBuiltinName (indexedFieldCount : Nat) : Except LowerError String :=
  if indexedFieldCount <= 3 then
    .ok s!"log{indexedFieldCount + 1}"
  else
    .error { message := s!"EVM IR v0 supports at most 3 indexed event fields" }

/-- Whether `op` is an arithmetic op that needs checked helpers. -/
def needsCheckedArithmetic (op : AssignOp) : Bool :=
  match op with
  | .add | .sub | .mul => true
  | _ => false

def arrayLocalElementName (name : String) (index : Nat) : String :=
  s!"__proof_forge_array_{name}_{index}"

def arrayStructLocalFieldName (name : String) (index : Nat) (fieldName : String) : String :=
  s!"__proof_forge_array_struct_{name}_{index}_{fieldName}"

def natPathSuffix (path : Array Nat) : String :=
  Id.run do
    let mut suffix := ""
    for h : idx in [0:path.size] do
      let part := toString path[idx]
      suffix := if idx == 0 then part else s!"{suffix}_{part}"
    suffix

def arrayLocalPathName (name : String) (path : Array Nat) : String :=
  match path.toList with
  | [index] => arrayLocalElementName name index
  | _ => s!"__proof_forge_array_{name}_{natPathSuffix path}"

def arrayStructLocalPathFieldName (name : String) (path : Array Nat) (fieldName : String) : String :=
  match path.toList with
  | [index] => arrayStructLocalFieldName name index fieldName
  | _ => s!"__proof_forge_array_struct_{name}_{natPathSuffix path}_{fieldName}"

def structLocalFieldName (name fieldName : String) : String :=
  s!"__proof_forge_struct_{name}_{fieldName}"

def ensureAbiWordType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} has unsupported EVM IR v0 ABI word type `{type.name}`; ABI aggregate words support U32, U64, Bool, Hash, or Address"
      }

def ensureCrosscallWordType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} has unsupported EVM IR v0 crosscall word type `{type.name}`; crosscall scalar words support U32, U64, Bool, Hash, or Address"
      }

def isCrosscallWordType : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

def abiStructWordTypes (module : Module) (context typeName : String) : Except LowerError (Array ValueType) := do
  let some decl := module.structs.find? fun decl => decl.name == typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; IR EVM v0 ABI structs must have at least one field" }
  let mut words : Array ValueType := #[]
  for field in decl.fields do
    ensureAbiWordType s!"{context} struct `{typeName}` field `{field.id}`" field.type
    words := words.push field.type
  .ok words

def crosscallStructWordTypes (module : Module) (context typeName : String) : Except LowerError (Array ValueType) := do
  let some decl := module.structs.find? fun decl => decl.name == typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; IR EVM v0 crosscall structs must have at least one field" }
  let mut words : Array ValueType := #[]
  for field in decl.fields do
    ensureCrosscallWordType s!"{context} struct `{typeName}` field `{field.id}`" field.type
    words := words.push field.type
  .ok words

partial def abiNestedFixedArrayWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u8 => .ok #[.u8]
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .u128 => .ok #[.u128]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .bytes | .string | .array _ =>
      .error { message := s!"{context} uses a dynamic type; IR EVM v0 ABI nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 ABI nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 ABI fixed arrays must have non-zero length" }
      let elementWords ← abiNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      abiStructWordTypes module context typeName

def isStorageWordType : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

partial def abiValueWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u8 => .ok #[.u8]
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .u128 => .ok #[.u128]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .bytes => .ok #[.bytes]
  | .string => .ok #[.string]
  | .array elementType =>
      if isStorageWordType elementType then
        .ok #[.array elementType]
      else
        .error { message := s!"{context} uses a dynamic array of `{elementType.name}`; IR EVM v0 ABI dynamic arrays support word-sized elements only" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 ABI values must use U32, U64, Bool, Hash, Address, Bytes, String, fixed arrays, or structs" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 ABI fixed arrays must have non-zero length" }
      let elementWords ←
        match elementType with
        | .fixedArray _ _ =>
            abiNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
        | .structType _ =>
            abiValueWordTypes module s!"{context} fixed-array element" elementType
        | _ => do
            ensureAbiWordType s!"{context} fixed-array element" elementType
            .ok #[elementType]
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      abiStructWordTypes module context typeName

partial def crosscallNestedFixedArrayWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u8 => .ok #[.u8]
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .u128 => .ok #[.u128]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .bytes | .string | .array _ =>
      .error { message := s!"{context} uses a dynamic type; IR EVM v0 crosscall nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 crosscall nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 crosscall fixed arrays must have non-zero length" }
      let elementWords ← crosscallNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      crosscallStructWordTypes module context typeName

partial def crosscallValueWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u8 => .ok #[.u8]
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .u128 => .ok #[.u128]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .bytes | .string | .array _ =>
      .error { message := s!"{context} uses a dynamic type; IR EVM v0 crosscall values must use U32, U64, Bool, Hash, Address, fixed arrays, or structs" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 crosscall values must use U32, U64, Bool, Hash, Address, fixed arrays, or structs" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 crosscall fixed arrays must have non-zero length" }
      let elementWords ←
        match elementType with
        | .fixedArray _ _ =>
            crosscallNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
        | .structType _ =>
            crosscallValueWordTypes module s!"{context} fixed-array element" elementType
        | _ => do
            ensureCrosscallWordType s!"{context} fixed-array element" elementType
            .ok #[elementType]
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      crosscallStructWordTypes module context typeName

def crosscallReturnWordTypes (module : Module) (context : String) (returnType : ValueType) : Except LowerError (Array ValueType) := do
  if isCrosscallWordType returnType then
    .ok #[returnType]
  else
    crosscallValueWordTypes module context returnType

def crosscallArgWordTypes (module : Module) (context : String) (type : ValueType) : Except LowerError (Array ValueType) :=
  crosscallValueWordTypes module context type

partial def abiValueParamNamesAt
    (module : Module)
    (context name : String)
    (path : Array Nat) : ValueType → Except LowerError (Array String)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      if path.isEmpty then
        .ok #[name]
      else
        .ok #[arrayLocalPathName name path]
  | .bytes | .string | .array _ =>
      if path.isEmpty then
        .ok #[name]
      else
        .error { message := s!"{context} parameter `{name}` uses a dynamic type nested in a fixed array; IR EVM v0 ABI parameters do not support nested dynamic arrays" }
  | .unit => do
      discard <| abiValueWordTypes module context .unit
      .ok #[]
  | .fixedArray elementType length => do
      discard <| abiValueWordTypes module context (.fixedArray elementType length)
      let mut names : Array String := #[]
      for _h : index in [0:length] do
        names := names ++ (← abiValueParamNamesAt module context name (path.push index) elementType)
      .ok names
  | .structType typeName => do
      discard <| abiValueWordTypes module context (.structType typeName)
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error { message := s!"{context} uses unknown struct `{typeName}`" }
      .ok (decl.fields.map fun field =>
        if path.isEmpty then
          structLocalFieldName name field.id
        else
          arrayStructLocalPathFieldName name path field.id)

def abiValueParamNames
    (module : Module)
    (context name : String)
    (type : ValueType) : Except LowerError (Array String) :=
  abiValueParamNamesAt module context name #[] type

def entrypointParamWordTypes (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array ValueType) := do
  let mut words : Array ValueType := #[]
  for param in entrypoint.params do
    words := words ++ (← abiValueWordTypes module s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" param.snd)
  .ok words

def mapShapeName (keyType valueType : ValueType) (capacity : Nat) : String :=
  s!"Map<{keyType.name}, {valueType.name}, {capacity}>"

def requireStorageMapState (module : Module) (stateId : String) : Except LowerError (Nat × ValueType × ValueType) :=
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown map state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .map keyType capacity, valueType =>
          if isStorageWordType keyType && isStorageWordType valueType then
            .ok (slot, keyType, valueType)
          else
            .error {
              message := s!"map state `{stateId}` has unsupported EVM IR v0 type `{mapShapeName keyType valueType capacity}`; storage maps support key/value word types U32, U64, Bool, or Hash"
            }
      | .scalar, _ => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
      | .array _, _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
      | .dynamicArray, _ => .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }

def requireStorageArrayState (module : Module) (stateId : String) : Except LowerError (Nat × Nat × ValueType) :=
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown array state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .array length, elementType =>
          if length == 0 then
            .error { message := s!"array state `{stateId}` must have non-zero length" }
          else if isStorageWordType elementType then
            .ok (slot, length, elementType)
          else
            match elementType with
            | .structType _ =>
                .error { message := s!"array state `{stateId}` is struct storage; use storage.array.struct.field.read/write" }
            | other =>
                .error { message := s!"array state `{stateId}` has unsupported EVM IR v0 element type `{other.name}`; storage arrays support U32, U64, Bool, Hash, or flat struct arrays" }
      | .scalar, _ => .error { message := s!"state `{stateId}` is scalar storage, not an array" }
      | .map _ _, _ => .error { message := s!"state `{stateId}` is map storage, not an array" }
      | .dynamicArray, _ => .error { message := s!"state `{stateId}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage" }

structure LocalBinding where
  name : String
  type : ValueType
  isMutable : Bool
  deriving Repr

abbrev TypeEnv := Array LocalBinding

def findLocal? (env : TypeEnv) (name : String) : Option LocalBinding :=
  env.find? fun binding => binding.name == name

def addLocal (env : TypeEnv) (name : String) (type : ValueType) (isMutable : Bool) : Except LowerError TypeEnv :=
  if (findLocal? env name).isSome then
    .error { message := s!"duplicate local `{name}`" }
  else
    .ok (env.push { name, type, isMutable })

def ensureType (context : String) (expected actual : ValueType) : Except LowerError Unit :=
  if expected == actual then
    .ok ()
  else
    .error { message := s!"{context} expected `{expected.name}`, got `{actual.name}`" }

def ensureNumericType (context : String) (lhs rhs : ValueType) : Except LowerError ValueType :=
  match lhs, rhs with
  | .u8, .u8 => .ok .u8
  | .u32, .u32 => .ok .u32
  | .u64, .u64 => .ok .u64
  | .u128, .u128 => .ok .u128
  | _, _ => .error { message := s!"{context} expects matching numeric operands, got `{lhs.name}` and `{rhs.name}`" }

def ensureArrayIndexType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 => .ok ()
  | _ => .error { message := s!"{context} expected U32 or U64 index, got `{type.name}`" }

def literalArrayIndex? : ProofForge.IR.Expr → Option Nat
  | .literal (.u32 value) => some value
  | .literal (.u64 value) => some value
  | _ => none

def requireStaticArrayIndex (context : String) (index : ProofForge.IR.Expr) : Except LowerError Nat :=
  match literalArrayIndex? index with
  | some value => .ok value
  | none =>
      .error {
        message := s!"{context} in IR EVM v0 requires a U32/U64 literal index for local fixed-array values"
      }

def requireLocalFixedArray
    (context : String)
    (env : TypeEnv)
    (name : String) : Except LowerError (ValueType × Nat) :=
  match findLocal? env name with
  | none => .error { message := s!"unknown local `{name}`" }
  | some binding =>
      match binding.type with
      | .fixedArray elementType length => .ok (elementType, length)
      | other => .error { message := s!"{context} local `{name}` expected fixed-array value, got `{other.name}`" }

def ensureFixedArrayIndexInBounds (context : String) (index length : Nat) : Except LowerError Unit :=
  if index < length then
    .ok ()
  else
    .error { message := s!"{context} {index} is out of bounds for length {length}" }

partial def collectStaticLocalArrayGetPath : ProofForge.IR.Expr → Option (String × Array Nat)
  | .arrayGet (.local name) index =>
      match literalArrayIndex? index with
      | some indexValue => some (name, #[indexValue])
      | none => none
  | .arrayGet array index =>
      match collectStaticLocalArrayGetPath array, literalArrayIndex? index with
      | some (name, path), some indexValue => some (name, path.push indexValue)
      | _, _ => none
  | _ => none

partial def collectLocalArrayGetPath : ProofForge.IR.Expr → Option (String × Array ProofForge.IR.Expr)
  | .arrayGet (.local name) index => some (name, #[index])
  | .arrayGet array index =>
      match collectLocalArrayGetPath array with
      | some (name, path) => some (name, path.push index)
      | none => none
  | _ => none

partial def collectLocalArrayFieldGetPath : ProofForge.IR.Expr → Option (String × Array ProofForge.IR.Expr × String)
  | .field base fieldName =>
      match collectLocalArrayGetPath base with
      | some (name, path) => some (name, path, fieldName)
      | none => none
  | _ => none

def arrayIndexPathHasDynamic (path : Array ProofForge.IR.Expr) : Bool :=
  path.any fun index => (literalArrayIndex? index).isNone

partial def fixedArrayPathType
    (context : String)
    (type : ValueType)
    (path : Array Nat) : Except LowerError ValueType :=
  match path.toList with
  | [] => .ok type
  | index :: rest =>
      match type with
      | .fixedArray elementType length => do
          ensureFixedArrayIndexInBounds context index length
          fixedArrayPathType context elementType rest.toArray
      | other =>
          .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

partial def fixedArrayPathShape
    (context : String)
    (type : ValueType)
    (path : Array ProofForge.IR.Expr) : Except LowerError (Array Nat × ValueType) := do
  match path.toList with
  | [] => .ok (#[], type)
  | _ :: rest =>
      match type with
      | .fixedArray elementType length => do
          let (nested, leafType) ← fixedArrayPathShape context elementType rest.toArray
          .ok (#[length] ++ nested, leafType)
      | other =>
          .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

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

def assignOpBuiltinName : AssignOp → String
  | .add => "add"
  | .sub => "sub"
  | .mul => "mul"
  | .div => "div"
  | .mod => "mod"
  | .bitAnd => "and"
  | .bitOr => "or"
  | .bitXor => "xor"
  | .shiftLeft => "shl"
  | .shiftRight => "shr"

def mapAssignFunctionName (op : AssignOp) : String :=
  s!"__proof_forge_map_assign_{assignOpBuiltinName op}"

def ensureAssignOpTypes (op : AssignOp) (targetType valueType : ValueType) : Except LowerError Unit := do
  discard <| ensureNumericType s!"compound assignment {assignOpDiagnosticName op}" targetType valueType

def ensureEqType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .bool | .u8 | .u32 | .u64 | .u128 | .hash | .address | .bytes | .string => .ok ()
  | .unit => .error { message := s!"{context} does not support Unit equality" }
  | .fixedArray _ _ | .structType _ | .array _ =>
      .error { message := s!"{context} does not support `{type.name}` equality in IR EVM v0" }

def ensureCastType (source target : ValueType) : Except LowerError Unit :=
  match source, target with
  | .u8, .u32 | .u8, .u64 | .u8, .u128 | .u8, .bool => .ok ()
  | .u32, .u8 | .u32, .u64 | .u32, .u128 | .u32, .bool => .ok ()
  | .u64, .u8 | .u64, .u32 | .u64, .u128 | .u64, .bool => .ok ()
  | .u64, .address => .ok ()
  | .u128, .u8 | .u128, .u32 | .u128, .u64 => .ok ()
  | .bool, .u8 | .bool, .u32 | .bool, .u64 | .bool, .u128 => .ok ()
  | .address, .u64 => .ok ()
  | .hash, .address => .ok ()
  | .address, .hash => .ok ()
  | _, _ =>
      .error { message := s!"cast from `{source.name}` to `{target.name}` is not supported by IR EVM v0" }

def stateDeclOf (module : Module) (stateId kind : String) : Except LowerError StateDecl :=
  match stateInfo? module stateId with
  | some (_, state) => .ok state
  | none => .error { message := s!"unknown {kind} state `{stateId}`" }

def scalarStateType (module : Module) (stateId : String) : Except LowerError ValueType := do
  let state ← stateDeclOf module stateId "scalar"
  match state.kind with
  | .scalar => .ok state.type
  | .map _ _ => .error { message := s!"state `{stateId}` is a map, not scalar storage" }
  | .array _ => .error { message := s!"state `{stateId}` is an array, not scalar storage" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not scalar storage" }

def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let state ← stateDeclOf module stateId "map"
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }

def findStruct? (module : Module) (name : String) : Option StructDecl :=
  module.structs.find? fun decl => decl.name == name

def findStructField? (decl : StructDecl) (fieldName : String) : Option StructField :=
  decl.fields.find? fun field => field.id == fieldName

def findStructFieldWithOffset? (decl : StructDecl) (fieldName : String) : Option (Nat × StructField) :=
  Id.run do
    let mut found : Option (Nat × StructField) := none
    for h : idx in [0:decl.fields.size] do
      if found.isNone then
        let field := decl.fields[idx]
        if field.id == fieldName then
          found := some (idx, field)
    found

def ensureStructLocalFieldType (structName fieldName : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error {
        message := s!"field `{fieldName}` in struct `{structName}` has unsupported EVM IR v0 local struct field type `{type.name}`; local structs support U32, U64, Bool, Hash, or Address fields"
      }

def ensureLocalFlatStructType (module : Module) (context typeName : String) : Except LowerError StructDecl := do
  let some decl := findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; local fixed arrays of structs require at least one field" }
  for field in decl.fields do
    ensureStructLocalFieldType typeName field.id field.type
  .ok decl

partial def ensureLocalNestedFixedArrayValueType
    (module : Module)
    (context name : String) : ValueType → Except LowerError Unit
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .array _ =>
      .error { message := s!"{context} `{name}` uses a dynamic array; local fixed arrays do not support dynamic array elements" }
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} `{name}` nested fixed-array leaf" typeName
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} `{name}` nested fixed array must have non-zero length in IR EVM v0" }
      else
        pure ()
      ensureLocalNestedFixedArrayValueType module context name elementType
  | .unit | .bytes | .string =>
      .error {
        message := s!"{context} `{name}` has unsupported EVM IR v0 nested fixed-array leaf type; nested local fixed arrays support U32, U64, Bool, Hash, or Address"
      }

def structFieldType (module : Module) (typeName fieldName : String) : Except LowerError ValueType := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct `{typeName}`" }
  let some field := findStructField? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  .ok field.type

def requireLocalFixedStructArrayField
    (module : Module)
    (env : TypeEnv)
    (context name fieldName : String) : Except LowerError (String × Nat × ValueType) := do
  let (elementType, length) ← requireLocalFixedArray context env name
  match elementType with
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} local `{name}` element" typeName
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      .ok (typeName, length, fieldType)
  | other =>
      .error { message := s!"{context} local `{name}` expected fixed-array struct element, got `{other.name}`" }

def requireStructState
    (module : Module)
    (stateId : String) : Except LowerError (Nat × String × StructDecl) := do
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown struct state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .scalar, .structType typeName => do
          let some decl := findStruct? module typeName
            | .error { message := s!"state `{stateId}` uses unknown struct `{typeName}`" }
          if decl.fields.isEmpty then
            .error { message := s!"state `{stateId}` uses empty struct `{typeName}`; EVM IR v0 storage structs must have at least one field" }
          for field in decl.fields do
            ensureStructLocalFieldType typeName field.id field.type
          .ok (slot, typeName, decl)
      | .scalar, other =>
          .error { message := s!"state `{stateId}` has unsupported EVM IR v0 struct storage type `{other.name}`; expected struct storage" }
      | .array _, _ =>
          .error { message := s!"state `{stateId}` is array storage, not scalar struct storage" }
      | .map _ _, _ =>
          .error { message := s!"state `{stateId}` is map storage, not scalar struct storage" }
      | .dynamicArray, _ =>
          .error { message := s!"state `{stateId}` is dynamic array storage, not scalar struct storage" }

def requireStructStateField
    (module : Module)
    (stateId fieldName : String) : Except LowerError (Nat × StructField) := do
  let (slot, typeName, decl) ← requireStructState module stateId
  let some (offset, field) := findStructFieldWithOffset? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  ensureStructLocalFieldType typeName field.id field.type
  .ok (slot + offset, field)

def requireStructArrayStateField
    (module : Module)
    (stateId fieldName : String) : Except LowerError (Nat × Nat × Nat × Nat × StructField) := do
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown struct array state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .array length, .structType typeName => do
          if length == 0 then
            .error { message := s!"array state `{stateId}` must have non-zero length" }
          let some decl := findStruct? module typeName
            | .error { message := s!"array state `{stateId}` uses unknown struct `{typeName}`" }
          let some (offset, field) := findStructFieldWithOffset? decl fieldName
            | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          ensureStructLocalFieldType typeName field.id field.type
          .ok (slot, length, decl.fields.size, offset, field)
      | .array _, other =>
          .error { message := s!"array state `{stateId}` has unsupported EVM IR v0 struct element type `{other.name}`; expected struct storage array" }
      | .scalar, _ =>
          .error { message := s!"state `{stateId}` is scalar storage, not a struct array" }
      | .map _ _, _ =>
          .error { message := s!"state `{stateId}` is map storage, not a struct array" }
      | .dynamicArray, _ =>
          .error { message := s!"state `{stateId}` is dynamic array storage, not a struct array" }

def validateStructLiteralFields
    (module : Module)
    (typeName : String)
    (fields : Array (String × ProofForge.IR.Expr))
    (infer : ProofForge.IR.Expr → Except LowerError ValueType) : Except LowerError Unit := do
  if fields.isEmpty then
    .error { message := s!"struct literal `{typeName}` must have at least one field" }
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct `{typeName}`" }
  if decl.fields.size != fields.size then
    .error { message := s!"struct literal `{typeName}` expected {decl.fields.size} field(s), got {fields.size}" }
  for field in fields do
    let expected ← structFieldType module typeName field.fst
    ensureStructLocalFieldType typeName field.fst expected
    let actual ← infer field.snd
    ensureType s!"struct literal `{typeName}` field `{field.fst}`" expected actual
  for expectedField in decl.fields do
    if !(fields.any fun field => field.fst == expectedField.id) then
      .error { message := s!"struct literal `{typeName}` is missing field `{expectedField.id}`" }

mutual
  partial def inferExprType (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError ValueType
    | .literal (.u32 _) => .ok .u32
    | .literal (.u8 _) => .ok .u8
    | .literal (.u128 _) => .ok .u128
    | .literal (.u64 _) => .ok .u64
    | .literal (.bool _) => .ok .bool
    | .literal (.hash4 ..) => .ok .hash
    | .literal (.address _) => .ok .address
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none => .error { message := s!"unknown local `{name}`" }
    | .arrayLit elementType values => do
        for value in values do
          ensureType "array literal element" elementType (← inferExprType module env value)
        .ok (.fixedArray elementType values.size)
    | .arrayGet array index => do
        ensureArrayIndexType "fixed array index" (← inferExprType module env index)
        match ← inferExprType module env array with
        | .fixedArray elementType length => do
            match literalArrayIndex? index with
            | some indexValue =>
                ensureFixedArrayIndexInBounds "fixed array index" indexValue length
            | none => pure ()
            .ok elementType
        | other => .error { message := s!"fixed array indexing target expected `Array`, got `{other.name}`" }
    | .memoryArrayNew elementType length => do
        if !isStorageWordType elementType then
          .error { message := s!"memory array element type `{elementType.name}` must be a word-sized type" }
        ensureType "memory array length" .u64 (← inferExprType module env length)
        .ok (.array elementType)
    | .memoryArrayLength array => do
        match ← inferExprType module env array with
        | .array _ => .ok .u64
        | other => .error { message := s!"memory array length expected `Array`, got `{other.name}`" }
    | .memoryArrayGet array index => do
        ensureArrayIndexType "memory array index" (← inferExprType module env index)
        match ← inferExprType module env array with
        | .array elementType =>
            if !isStorageWordType elementType then
              .error { message := s!"memory array element type `{elementType.name}` must be a word-sized type" }
            .ok elementType
        | other => .error { message := s!"memory array get expected `Array`, got `{other.name}`" }
    | .structLit typeName fields => do
        validateStructLiteralFields module typeName fields (inferExprType module env)
        .ok (.structType typeName)
    | .field base fieldName => do
        match ← inferExprType module env base with
        | .structType typeName => do
            let fieldType ← structFieldType module typeName fieldName
            ensureStructLocalFieldType typeName fieldName fieldType
            .ok fieldType
        | other => .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
    | .add lhs rhs => do inferBinaryNumericType "addition" module env lhs rhs
    | .sub lhs rhs => do inferBinaryNumericType "subtraction" module env lhs rhs
    | .mul lhs rhs => do inferBinaryNumericType "multiplication" module env lhs rhs
    | .div lhs rhs => do inferBinaryNumericType "division" module env lhs rhs
    | .mod lhs rhs => do inferBinaryNumericType "modulo" module env lhs rhs
    | .pow lhs rhs => do inferBinaryNumericType "exponentiation" module env lhs rhs
    | .bitAnd lhs rhs => do inferBinaryNumericType "bitwise and" module env lhs rhs
    | .bitOr lhs rhs => do inferBinaryNumericType "bitwise or" module env lhs rhs
    | .bitXor lhs rhs => do inferBinaryNumericType "bitwise xor" module env lhs rhs
    | .shiftLeft lhs rhs => do inferBinaryNumericType "shift-left" module env lhs rhs
    | .shiftRight lhs rhs => do inferBinaryNumericType "shift-right" module env lhs rhs
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
    | .lt lhs rhs => do
        discard <| inferBinaryNumericType "less-than" module env lhs rhs
        .ok .bool
    | .le lhs rhs => do
        discard <| inferBinaryNumericType "less-or-equal" module env lhs rhs
        .ok .bool
    | .gt lhs rhs => do
        discard <| inferBinaryNumericType "greater-than" module env lhs rhs
        .ok .bool
    | .ge lhs rhs => do
        discard <| inferBinaryNumericType "greater-or-equal" module env lhs rhs
        .ok .bool
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
    | .crosscallInvoke target methodId args => do
        ensureType "crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "crosscall method id" .u64 (← inferExprType module env methodId)
        for arg in args do
          ensureType "crosscall argument" .u64 (← inferExprType module env arg)
        .ok .u64
    | .crosscallInvokeTyped target methodId args returnType => do
        ensureType "typed crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "typed crosscall method id" .u64 (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "typed crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "typed crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        ensureType "value crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "value crosscall method id" .u64 (← inferExprType module env methodId)
        ensureType "value crosscall call value" .u64 (← inferExprType module env callValue)
        discard <| crosscallReturnWordTypes module "value crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "value crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        ensureType "static crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "static crosscall method id" .u64 (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "static crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "static crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        ensureType "delegate crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "delegate crosscall method id" .u64 (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "delegate crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "delegate crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallCreate callValue initCodeHex => do
        ensureType "contract creation call value" .u64 (← inferExprType module env callValue)
        discard <| normalizeInitCodeHex "contract creation" initCodeHex
        .ok .u64
    | .crosscallCreate2 callValue salt initCodeHex => do
        ensureType "contract creation call value" .u64 (← inferExprType module env callValue)
        ensureType "contract creation salt" .hash (← inferExprType module env salt)
        discard <| normalizeInitCodeHex "contract creation" initCodeHex
        .ok .u64
    | .effect effect => inferEffectExprType module env effect

  partial def inferBinaryNumericType
      (context : String)
      (module : Module)
      (env : TypeEnv)
      (lhs rhs : ProofForge.IR.Expr) : Except LowerError ValueType := do
    ensureNumericType context (← inferExprType module env lhs) (← inferExprType module env rhs)

  partial def inferStoragePathType
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (path : Array StoragePathSegment) : Except LowerError ValueType := do
    let state ← stateDeclOf module stateId "storage path"
    match state.kind, state.type, path.toList with
    | .map keyType _, _, _ => do
        let some keys := storagePathMapKeys? path
          | if path.isEmpty then
              .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
            else
              .error { message := "EVM IR v0 supports map storage paths only as one or more mapKey segments" }
        for key in keys do
          ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok state.type
    | .scalar, .structType _, [StoragePathSegment.field fieldName] => do
        let (_, field) ← requireStructStateField module stateId fieldName
        .ok field.type
    | .scalar, .structType _, [] =>
        .error { message := s!"storage path state `{stateId}` is struct storage; first segment must be a field" }
    | .scalar, .structType _, _ =>
        .error { message := "EVM IR v0 supports struct scalar storage paths only as a single field segment" }
    | .scalar, _, [] =>
        .ok state.type
    | .scalar, _, [StoragePathSegment.field fieldName] =>
        .error { message := s!"state `{stateId}` has unsupported EVM IR v0 struct storage type `{state.type.name}`; expected struct storage for field `{fieldName}`" }
    | .scalar, _, _ =>
        .error { message := "EVM IR v0 supports storage paths only for single-segment mapKey map access" }
    | .array _, .structType _, [StoragePathSegment.index index, StoragePathSegment.field fieldName] => do
        let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
        ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
        .ok field.type
    | .array _, .structType _, [StoragePathSegment.index _] =>
        .error { message := s!"storage path state `{stateId}` is struct array storage; a field segment must follow the index" }
    | .array _, _, [] =>
        .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
    | .array _, .structType _, _ =>
        .error { message := "EVM IR v0 supports struct-array storage paths only as index followed by field" }
    | .array _, _, [StoragePathSegment.index index] => do
        let (_, _, elementType) ← requireStorageArrayState module stateId
        ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .array _, _, _ =>
        .error { message := "EVM IR v0 supports only single-segment index storage paths for arrays" }
    | .dynamicArray, _, [StoragePathSegment.index index] => do
        let (_, elementType) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireDynamicArrayState module stateId
        ensureArrayIndexType s!"dynamic array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .dynamicArray, _, [] =>
        .error { message := s!"storage path state `{stateId}` is dynamic array storage; first segment must be an index" }
    | .dynamicArray, _, _ =>
        .error { message := "EVM IR v0 supports only single-segment index storage paths for dynamic arrays" }

  partial def inferEffectExprType (module : Module) (env : TypeEnv) : Effect → Except LowerError ValueType
    | .storageScalarRead stateId =>
        scalarStateType module stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory.array.set is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
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
    | .storageArrayRead stateId index => do
        let (_, _, elementType) ← requireStorageArrayState module stateId
        ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
        ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
        .ok field.type
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is a statement effect, not an expression" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        let (_, field) ← requireStructStateField module stateId fieldName
        .ok field.type
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path =>
        inferStoragePathType module env stateId path
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

partial def inferEventFieldExprType (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError ValueType
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
      for value in values do
        ensureType "event field array literal element" elementType (← inferEventFieldExprType module env value)
      .ok (.fixedArray elementType values.size)
  | .arrayGet array index => do
      ensureArrayIndexType "fixed array index" (← inferExprType module env index)
      match ← inferEventFieldExprType module env array with
      | .fixedArray elementType length => do
          match literalArrayIndex? index with
          | some indexValue =>
              ensureFixedArrayIndexInBounds "fixed array index" indexValue length
          | none => pure ()
          .ok elementType
      | other => .error { message := s!"fixed array indexing target expected `Array`, got `{other.name}`" }
  | .structLit typeName fields => do
      if fields.isEmpty then
        .error { message := s!"struct literal `{typeName}` must have at least one field" }
      let some decl := findStruct? module typeName
        | .error { message := s!"unknown struct `{typeName}`" }
      if decl.fields.size != fields.size then
        .error { message := s!"struct literal `{typeName}` expected {decl.fields.size} field(s), got {fields.size}" }
      for field in fields do
        let expected ← structFieldType module typeName field.fst
        let actual ← inferEventFieldExprType module env field.snd
        ensureType s!"struct literal `{typeName}` field `{field.fst}`" expected actual
      for expectedField in decl.fields do
        if !(fields.any fun field => field.fst == expectedField.id) then
          .error { message := s!"struct literal `{typeName}` is missing field `{expectedField.id}`" }
      .ok (.structType typeName)
  | .field base fieldName => do
      match ← inferEventFieldExprType module env base with
      | .structType typeName =>
          structFieldType module typeName fieldName
      | other => .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
  | .effect effect =>
      inferEffectExprType module env effect
  | other =>
      inferExprType module env other

def eventSignature
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (fields : Array (String × ProofForge.IR.Expr)) : Except LowerError String := do
  validateEventName name
  let _ ← fields.foldlM (init := #[]) fun seen field =>
    validateDistinctEventFieldName name seen field.fst
  let mut typeNames := #[]
  for field in fields do
    let actual ← inferEventFieldExprType module env field.snd
    typeNames := typeNames.push (← eventSignatureFieldType module name field.fst actual)
  .ok (name ++ "(" ++ String.intercalate "," typeNames.toList ++ ")")

def validateEffectStmtTypes (module : Module) (env : TypeEnv) : Effect → Except LowerError Unit
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      ensureType s!"scalar state `{stateId}` write" (← scalarStateType module stateId) (← inferExprType module env value)
  | .storageScalarAssignOp stateId op value => do
      ensureAssignOpTypes op (← scalarStateType module stateId) (← inferExprType module env value)
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
  | .storageArrayWrite stateId index value => do
      let (_, _, elementType) ← requireStorageArrayState module stateId
      ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
      ensureType s!"array state `{stateId}` write" elementType (← inferExprType module env value)
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
      ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
      ensureType s!"struct array state `{stateId}` field `{fieldName}` write" field.type (← inferExprType module env value)
    | .storageDynamicArrayPush stateId value => do
      let (_, elementType) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireDynamicArrayState module stateId
      ensureType s!"dynamic array state `{stateId}` push" elementType (← inferExprType module env value)
    | .storageDynamicArrayPop stateId => do
      let _ ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireDynamicArrayState module stateId
      .ok ()
    | .memoryArraySet array index value => do
      match ← inferExprType module env array with
      | .array elementType => do
          if !isStorageWordType elementType then
            .error { message := s!"memory array element type `{elementType.name}` must be a word-sized type" }
          ensureArrayIndexType "memory array set index" (← inferExprType module env index)
          ensureType "memory array set value" elementType (← inferExprType module env value)
          .ok ()
      | other => .error { message := s!"memory array set expected `Array`, got `{other.name}`" }
    | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      let (_, field) ← requireStructStateField module stateId fieldName
      ensureType s!"struct state `{stateId}` field `{fieldName}` write" field.type (← inferExprType module env value)
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      ensureType s!"storage path `{stateId}` write" (← inferStoragePathType module env stateId path) (← inferExprType module env value)
  | .storagePathAssignOp stateId path op value => do
      ensureAssignOpTypes op (← inferStoragePathType module env stateId path) (← inferExprType module env value)
  | .contextRead _ =>
      .error { message := "context reads must be used as expressions" }
  | .eventEmit name fields => do
      discard <| eventSignature module env name fields
  | .eventEmitIndexed name indexedFields dataFields => do
      validateIndexedEventFieldCount name indexedFields.size
      for field in indexedFields do
        ensureIndexedEventFieldType module name field.fst (← inferEventFieldExprType module env field.snd)
      discard <| eventSignature module env name (indexedFields ++ dataFields)

def requireMutableLocal (env : TypeEnv) (context name : String) : Except LowerError LocalBinding := do
  let some binding := findLocal? env name
    | .error { message := s!"unknown local `{name}`" }
  if !binding.isMutable then
    .error { message := s!"{context} local `{name}` is not mutable" }
  .ok binding

partial def validateFixedArrayIndexPathTarget
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (type : ValueType)
    (path : Array ProofForge.IR.Expr) : Except LowerError ValueType := do
  match path.toList with
  | [] => .ok type
  | index :: rest =>
      match type with
      | .fixedArray elementType length => do
          ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
          match literalArrayIndex? index with
          | some indexValue => ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
          | none => pure ()
          validateFixedArrayIndexPathTarget module env context elementType rest.toArray
      | .array _ =>
          .error { message := s!"{context} target expected fixed `Array`, got dynamic `Array`" }
      | other =>
          .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

def validateLocalFixedArrayTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (index value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  match binding.type with
  | .fixedArray elementType length => do
      ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
      match literalArrayIndex? index with
      | some indexValue =>
          ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
      | none => pure ()
      ensureType s!"{context} value" elementType (← inferExprType module env value)
      match elementType with
      | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => pure ()
      | .structType _ =>
          .error {
            message := s!"{context} local `{name}` returns struct values; IR EVM v0 requires field assignment such as array[index].field"
          }
      | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
          .error {
            message := s!"{context} local `{name}` has unsupported EVM IR v0 element target type `{elementType.name}`; local fixed-array element targets must resolve to U32, U64, Bool, Hash, or Address leaves"
          }
      .ok elementType
  | other =>
      .error { message := s!"{context} local `{name}` expected fixed-array target, got `{other.name}`" }

def validateLocalFixedArrayStaticPathTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (path : Array ProofForge.IR.Expr)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  let targetType ← validateFixedArrayIndexPathTarget module env context binding.type path
  ensureType s!"{context} value" targetType (← inferExprType module env value)
  match targetType with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok targetType
  | .structType _ =>
      .error {
        message := s!"{context} local `{name}` returns struct values; IR EVM v0 requires field assignment such as array[index].field"
      }
  | .unit | .fixedArray _ _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} local `{name}` has unsupported EVM IR v0 element target type `{targetType.name}`; local fixed-array element targets must resolve to U32, U64, Bool, Hash, or Address leaves"
      }

def validateLocalStructTarget
    (module : Module)
    (env : TypeEnv)
    (context name fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  match binding.type with
  | .structType typeName => do
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      ensureType s!"{context} value" fieldType (← inferExprType module env value)
      .ok fieldType
  | other =>
      .error { message := s!"{context} local `{name}` expected struct target, got `{other.name}`" }

def validateLocalStructArrayFieldTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (index : ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  discard <| requireMutableLocal env context name
  let (_, length, fieldType) ← requireLocalFixedStructArrayField module env context name fieldName
  ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
  match literalArrayIndex? index with
  | some indexValue =>
      ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
  | none => pure ()
  ensureType s!"{context} value" fieldType (← inferExprType module env value)
  .ok fieldType

def validateLocalFixedArrayPathFieldTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (path : Array ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  let targetType ← validateFixedArrayIndexPathTarget module env context binding.type path
  match targetType with
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} local `{name}` fixed-array leaf" typeName
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      ensureType s!"{context} value" fieldType (← inferExprType module env value)
      .ok fieldType
  | other =>
      .error {
        message := s!"{context} local `{name}` field target expected flat struct leaf, got `{other.name}`"
      }

def validateAssignTarget
    (module : Module)
    (env : TypeEnv)
    (target value : ProofForge.IR.Expr) : Except LowerError Unit := do
  let validateDefault : Except LowerError Unit := do
    match target with
    | .local name => do
        let binding ← requireMutableLocal env "assignment target" name
        match binding.type with
        | .fixedArray elementType _ => do
            match elementType with
            | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => pure ()
            | .fixedArray _ _ =>
                ensureLocalNestedFixedArrayValueType module "assignment target" name elementType
            | .structType typeName =>
                discard <| ensureLocalFlatStructType module s!"assignment target `{name}` fixed-array element" typeName
            | .unit | .bytes | .string | .array _ =>
                .error {
                  message := s!"assignment target `{name}` has unsupported EVM IR v0 fixed-array element type `{elementType.name}`; local fixed arrays support U32, U64, Bool, Hash, Address, flat struct elements, or nested fixed arrays with scalar or flat struct leaves"
                }
            ensureType "assignment value" binding.type (← inferExprType module env value)
        | .structType typeName => do
            let some decl := findStruct? module typeName
              | .error { message := s!"unknown struct `{typeName}`" }
            for field in decl.fields do
              ensureStructLocalFieldType typeName field.id field.type
            ensureType "assignment value" binding.type (← inferExprType module env value)
        | _ =>
            ensureType "assignment value" binding.type (← inferExprType module env value)
    | .arrayGet (.local name) index => do
        discard <| validateLocalFixedArrayTarget module env "assignment target" name index value
    | .field (.arrayGet (.local name) index) fieldName => do
        discard <| validateLocalStructArrayFieldTarget module env "assignment target" name index fieldName value
    | .field (.local name) fieldName => do
        discard <| validateLocalStructTarget module env "assignment target" name fieldName value
    | _ =>
        .error { message := "assignment target must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  match collectLocalArrayFieldGetPath target with
  | some (name, path, fieldName) =>
      if path.size > 1 then
        discard <| validateLocalFixedArrayPathFieldTarget module env "assignment target" name path fieldName value
      else
        validateDefault
  | none =>
      match collectLocalArrayGetPath target with
      | some (name, path) =>
          if path.size > 1 then
            discard <| validateLocalFixedArrayStaticPathTarget module env "assignment target" name path value
          else
            validateDefault
      | none =>
          validateDefault

def validateAssignOpTarget
    (module : Module)
    (env : TypeEnv)
    (target : ProofForge.IR.Expr)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Unit := do
  let validateDefault : Except LowerError Unit := do
    match target with
    | .local name => do
        let binding ← requireMutableLocal env "compound assignment target" name
        ensureAssignOpTypes op binding.type (← inferExprType module env value)
    | .arrayGet (.local name) index => do
        let targetType ← validateLocalFixedArrayTarget module env "compound assignment target" name index value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | .field (.arrayGet (.local name) index) fieldName => do
        let targetType ← validateLocalStructArrayFieldTarget module env "compound assignment target" name index fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | .field (.local name) fieldName => do
        let targetType ← validateLocalStructTarget module env "compound assignment target" name fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | _ =>
        .error { message := "compound assignment target must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  match collectLocalArrayFieldGetPath target with
  | some (name, path, fieldName) =>
      if path.size > 1 then
        let targetType ← validateLocalFixedArrayPathFieldTarget module env "compound assignment target" name path fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
      else
        validateDefault
  | none =>
      match collectLocalArrayGetPath target with
      | some (name, path) =>
          if path.size > 1 then
            let targetType ← validateLocalFixedArrayStaticPathTarget module env "compound assignment target" name path value
            ensureAssignOpTypes op targetType (← inferExprType module env value)
          else
            validateDefault
      | none =>
          validateDefault

mutual
  partial def validateStatements (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) (statements : Array Statement) : Except LowerError TypeEnv :=
    statements.foldlM (init := env) fun env stmt =>
      validateStatementTypes module entrypoint env stmt

  partial def validateStatementTypes (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) : Statement → Except LowerError TypeEnv
    | .letBind name type value => do
        ensureType s!"let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type false
    | .letMutBind name type value => do
        ensureType s!"mutable let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type true
    | .assign target value => do
        validateAssignTarget module env target value
        .ok env
    | .assignOp target op value => do
        validateAssignOpTarget module env target op value
        .ok env
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
        .error { message := "release statements are not supported by IR EVM v0" }
    | .revert _ => .ok env
    | .revertWithError _ => .ok env
    | .ifElse condition thenBody elseBody => do
        ensureType "if condition" .bool (← inferExprType module env condition)
        discard <| validateStatements module entrypoint env thenBody
        discard <| validateStatements module entrypoint env elseBody
        .ok env
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        discard <| validateStatements module entrypoint loopEnv body
        .ok env
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by EVM IR v0; use boundedFor" }
    | .return value => do
        ensureType "return value" entrypoint.returns (← inferExprType module env value)
        .ok env
end

def entrypointTypeEnv (entrypoint : Entrypoint) : TypeEnv :=
  entrypoint.params.map fun param => {
    name := param.fst
    type := param.snd
    isMutable := false
  }

def validateEntrypointTypes (module : Module) (entrypoint : Entrypoint) : Except LowerError Unit := do
  discard <| validateStatements module entrypoint (entrypointTypeEnv entrypoint) entrypoint.body

mutual
  partial def statementAlwaysReturns : Statement → Bool
    | .return _ => true
    | .ifElse _ thenBody elseBody =>
        statementsAlwaysReturn thenBody && statementsAlwaysReturn elseBody
    | .boundedFor _ start stopExclusive body =>
        start < stopExclusive && statementsAlwaysReturn body
    | _ => false

  partial def statementsAlwaysReturn (statements : Array Statement) : Bool :=
    statements.any statementAlwaysReturns
end

def validateDistinctStructName (seen : Array String) (name : String) : Except LowerError (Array String) :=
  if name.isEmpty then
    .error { message := "struct name must be non-empty for IR EVM v0" }
  else if seen.contains name then
    .error { message := s!"duplicate struct `{name}`" }
  else
    .ok (seen.push name)

def validateDistinctStructFieldName (structName : String) (seen : Array String) (fieldName : String) : Except LowerError (Array String) :=
  if fieldName.isEmpty then
    .error { message := s!"struct `{structName}` field name must be non-empty" }
  else if seen.contains fieldName then
    .error { message := s!"duplicate field `{fieldName}` in struct `{structName}`" }
  else
    .ok (seen.push fieldName)

def validateStructs (module : Module) : Except LowerError Unit := do
  let _ ← module.structs.foldlM (init := #[]) fun seen decl =>
    validateDistinctStructName seen decl.name
  for decl in module.structs do
    if decl.fields.isEmpty then
      .error { message := s!"struct `{decl.name}` must declare at least one field" }
    let _ ← decl.fields.foldlM (init := #[]) fun seen field =>
      validateDistinctStructFieldName decl.name seen field.id
    for field in decl.fields do
      ensureStructLocalFieldType decl.name field.id field.type

def validateStorageStructState (context typeName : String) (module : Module) : Except LowerError Unit := do
  let some decl := findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; EVM IR v0 storage structs must have at least one field" }
  for field in decl.fields do
    ensureStructLocalFieldType decl.name field.id field.type

def validateState (module : Module) : Except LowerError Unit := do
  for state in module.state do
    match state.kind, state.type with
    | .scalar, .u8 => pure ()
    | .scalar, .u32 => pure ()
    | .scalar, .u64 => pure ()
    | .scalar, .u128 => pure ()
    | .scalar, .bool => pure ()
    | .scalar, .hash => pure ()
    | .scalar, .address => pure ()
    | .scalar, .structType typeName =>
        validateStorageStructState s!"state `{state.id}`" typeName module
    | .scalar, other =>
        .error { message := s!"state `{state.id}` has unsupported EVM IR v0 type `{other.name}`" }
    | .map keyType capacity, valueType =>
        if isStorageWordType keyType && isStorageWordType valueType then
          pure ()
        else
          .error {
            message := s!"map state `{state.id}` has unsupported EVM IR v0 type `{mapShapeName keyType valueType capacity}`; storage maps support key/value word types U32, U64, Bool, or Hash"
          }
    | .array 0, _ =>
        .error { message := s!"array state `{state.id}` must have non-zero length" }
    | .array _, .u8 => pure ()
    | .array _, .u32 => pure ()
    | .array _, .u64 => pure ()
    | .array _, .u128 => pure ()
    | .array _, .bool => pure ()
    | .array _, .hash => pure ()
    | .array _, .address => pure ()
    | .array _, .structType typeName =>
        validateStorageStructState s!"array state `{state.id}`" typeName module
    | .array _, other =>
        .error { message := s!"array state `{state.id}` has unsupported EVM IR v0 element type `{other.name}`; storage arrays support U32, U64, Bool, Hash, or flat struct arrays" }
    | .dynamicArray, _ =>
        .error { message := s!"state `{state.id}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage" }

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match resolveModule Target.evm module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

/-! Detect whether a module uses any `.add`/`.sub`/`.mul` `Expr` or compound
    assignment op that would route to the checked-arithmetic helpers. Used to
    avoid emitting the helpers when a module only uses div/mod/bitwise/shift. -/
mutual
  partial def effectUsesCheckedArithmetic : Effect → Bool
    | .storageScalarWrite _ v => exprUsesCheckedArithmetic v
    | .storageScalarAssignOp _ op v => needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageMapInsert _ _ v => exprUsesCheckedArithmetic v
    | .storageMapSet _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayWrite _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayStructFieldWrite _ _ _ v => exprUsesCheckedArithmetic v
    | .storageDynamicArrayPush _ v => exprUsesCheckedArithmetic v
    | .storageDynamicArrayPop _ => false
    | .memoryArraySet _ i v => exprUsesCheckedArithmetic i || exprUsesCheckedArithmetic v
    | .storageStructFieldWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathAssignOp _ _ op v => needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageScalarRead _ | .storageMapContains _ _ | .storageMapGet _ _
    | .storageArrayRead _ _ | .storageArrayStructFieldRead _ _ _
    | .storageStructFieldRead _ _ | .storagePathRead _ _
    | .contextRead _ | .eventEmit _ _ | .eventEmitIndexed _ _ _ => false

  partial def exprUsesCheckedArithmetic : Expr → Bool
    | .add _ _ | .sub _ _ | .mul _ _ => true
    | .literal _ | .local _ | .nativeValue => false
    | .arrayLit _ xs => xs.any exprUsesCheckedArithmetic
    | .arrayGet a i => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic i
    | .memoryArrayNew _ l => exprUsesCheckedArithmetic l
    | .memoryArrayLength a => exprUsesCheckedArithmetic a
    | .memoryArrayGet a i => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic i
    | .structLit _ fs => fs.any (fun (_, v) => exprUsesCheckedArithmetic v)
    | .field b _ => exprUsesCheckedArithmetic b
    | .div l r | .mod l r | .pow l r
    | .bitAnd l r | .bitOr l r | .bitXor l r
    | .shiftLeft l r | .shiftRight l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .cast v _ => exprUsesCheckedArithmetic v
    | .eq l r | .ne l r | .lt l r | .le l r | .gt l r | .ge l r
    | .boolAnd l r | .boolOr l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .boolNot v => exprUsesCheckedArithmetic v
    | .hashValue a b c d => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b
        || exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d
    | .hash p => exprUsesCheckedArithmetic p
    | .hashTwoToOne l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .crosscallInvoke t m args | .crosscallInvokeTyped t m args _
    | .crosscallInvokeValueTyped t m _ args _
    | .crosscallInvokeStaticTyped t m args _ | .crosscallInvokeDelegateTyped t m args _ =>
        exprUsesCheckedArithmetic t || exprUsesCheckedArithmetic m || args.any exprUsesCheckedArithmetic
    | .crosscallCreate v _ => exprUsesCheckedArithmetic v
    | .crosscallCreate2 v s _ => exprUsesCheckedArithmetic v || exprUsesCheckedArithmetic s
    | .effect e => effectUsesCheckedArithmetic e

  partial def stmtUsesCheckedArithmetic : Statement → Bool
    | .letBind _ _ v | .letMutBind _ _ v | .assign _ v | .assignOp _ _ v | .return v =>
        exprUsesCheckedArithmetic v
    | .assert _ _ _ | .assertEq _ _ _ _ | .release _ | .revert _ | .revertWithError _ => false
    | .effect e => effectUsesCheckedArithmetic e
    | .ifElse c thenBody elseBody =>
        exprUsesCheckedArithmetic c || thenBody.any stmtUsesCheckedArithmetic
          || elseBody.any stmtUsesCheckedArithmetic
    | .boundedFor _ _ _ body => body.any stmtUsesCheckedArithmetic
    | .whileLoop c body => exprUsesCheckedArithmetic c || body.any stmtUsesCheckedArithmetic
end

def moduleUsesCheckedArithmetic (module : Module) : Bool :=
  module.entrypoints.any (fun ep => ep.body.any stmtUsesCheckedArithmetic)

end ProofForge.Backend.Evm.Validate
