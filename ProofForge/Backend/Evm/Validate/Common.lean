import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Diagnostic
import ProofForge.Backend.Evm.AbiType
import ProofForge.Backend.Evm.Names
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.SharedValidate
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

instance : ProofForge.Backend.Diagnostic.LoweringError LowerError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "evm" }

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

/-- Bit width for the compile-time Solidity ABI word subset supported by E1.1.
    Dynamic, signed, tuple, array, and short fixed-bytes types are rejected. -/
def solidityStaticArgBitWidth? : String -> Option Nat
  | "uint8" => some 8
  | "uint32" => some 32
  | "uint64" => some 64
  | "uint128" => some 128
  | "uint256" => some 256
  | "bool" => some 1
  | "address" => some 160
  | "bytes32" => some 256
  | _ => none

/-- Fail-closed validation for the transitional EVM custom-error static-word
    annotation on portable `ErrorRef`. Runtime expressions and dynamic ABI
    values require a future target-plan representation. -/
def validateSolidityErrorRef (context : String) (ref : ErrorRef) : Except LowerError Unit := do
  match ref.soliditySelector? with
  | none =>
      if !ref.solidityArgTypes.isEmpty || !ref.solidityArgWords.isEmpty then
        .error {
          message := s!"{context} has Solidity custom-error args without a selector"
        }
      else
        .ok ()
  | some selector =>
      if selector.length != 8 || !(selector.all isHexChar) then
        .error {
          message := s!"{context} Solidity custom-error selector must be exactly 8 hex digits"
        }
      if ref.solidityArgTypes.size != ref.solidityArgWords.size then
        .error {
          message :=
            s!"{context} Solidity custom-error arg type/value count mismatch: " ++
              s!"{ref.solidityArgTypes.size} type(s), {ref.solidityArgWords.size} value(s)"
        }
      for ((abiType, word), index) in
          (ref.solidityArgTypes.zip ref.solidityArgWords).zipIdx do
        let some width := solidityStaticArgBitWidth? abiType
          | .error {
              message :=
                s!"{context} Solidity custom-error arg {index} has unsupported static ABI type " ++
                  s!"`{abiType}`"
            }
        if word >= 2 ^ width then
          .error {
            message :=
              s!"{context} Solidity custom-error arg {index} value `{word}` exceeds `{abiType}` range"
          }
      .ok ()

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

/-- Event fields are output-only, so widening the portable U64 value domain to
the standard Solidity uint256 event word is lossless. Keep this separate from
entrypoint calldata override compatibility, where U64 <- uint256 is unsafe. -/
def eventAbiWordOverrideCompatible (type : ValueType) (abiWord : String) : Bool :=
  ProofForge.Backend.Evm.AbiType.abiWordOverrideCompatible type abiWord ||
    (type == .u64 && abiWord == "uint256")

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

mutual
  partial def eventStructSignatureTuple
      (module : Module)
      (eventName fieldName typeName : String) : Except LowerError String := do
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

  partial def eventSignatureFieldType (module : Module) (eventName fieldName : String) (type : ValueType) : Except LowerError String :=
    let overrides := module.eventAbiWords.filter fun override =>
      override.eventName == eventName && override.fieldName == fieldName
    if overrides.size > 1 then
      .error {
        message := s!"event `{eventName}` field `{fieldName}` has duplicate ABI overrides"
      }
    else
      match overrides[0]? with
      | some override =>
          if eventAbiWordOverrideCompatible type override.abiWord then
            .ok override.abiWord
          else
            .error {
              message :=
                s!"event `{eventName}` field `{fieldName}` has incompatible EVM ABI override " ++
                  s!"`{override.abiWord}` for IR carrier `{type.name}`"
            }
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
            | .structType typeName => do
                let tuple ← eventStructSignatureTuple module eventName fieldName typeName
                .ok (tuple ++ s!"[{length}]")
            | _ => do
                let elementName ← eventSignatureFieldType module eventName fieldName elementType
                .ok (elementName ++ s!"[{length}]")
        | .array _ =>
            .error { message := s!"event `{eventName}` field `{fieldName}` has unsupported EVM IR v0 type `Array`; dynamic arrays are not supported in EVM event signatures" }
        | .unit =>
            .error { message := s!"event `{eventName}` field `{fieldName}` has unsupported EVM IR v0 type `Unit`; event fields must be U32, U64, Bool, Hash, Address, Bytes, String, flat structs, or fixed arrays" }
        | .structType typeName =>
            eventStructSignatureTuple module eventName fieldName typeName
end

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
  s!"__pf_event_indexed_topic{index}"

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
  ProofForge.Backend.Evm.Names.arrayLocalElementName name index

def arrayStructLocalFieldName (name : String) (index : Nat) (fieldName : String) : String :=
  ProofForge.Backend.Evm.Names.arrayStructLocalFieldName name index fieldName

def natPathSuffix (path : Array Nat) : String :=
  ProofForge.Backend.Evm.Names.natPathSuffix path

def arrayLocalPathName (name : String) (path : Array Nat) : String :=
  ProofForge.Backend.Evm.Names.arrayLocalPathName name path

def arrayStructLocalPathFieldName (name : String) (path : Array Nat) (fieldName : String) : String :=
  ProofForge.Backend.Evm.Names.arrayStructLocalPathFieldName name path fieldName

def structLocalFieldName (name fieldName : String) : String :=
  ProofForge.Backend.Evm.Names.structLocalFieldName name fieldName

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

def validateUserIdentifier (context name : String) : Except LowerError Unit :=
  if name.startsWith "__pf_" then
    .error {
      message :=
        s!"{context} `{name}` starts with `__pf_`, which is reserved for generated EVM temporaries"
    }
  else if name.startsWith "__proof_forge_" then
    .error {
      message :=
        s!"{context} `{name}` starts with `__proof_forge_`, which is reserved for generated EVM temporaries"
    }
  else
    .ok ()

def addLocal (env : TypeEnv) (name : String) (type : ValueType) (isMutable : Bool) : Except LowerError TypeEnv := do
  validateUserIdentifier "local" name
  if (findLocal? env name).isSome then
    .error { message := s!"duplicate local `{name}`" }
  else
    .ok (env.push { name, type, isMutable })

def ensureType (context : String) (expected actual : ValueType) : Except LowerError Unit :=
  match ProofForge.Backend.SharedValidate.ensureType context expected actual with
  | .ok _ => .ok ()
  | .error diag => .error { message := diag.message }

/-- Portable contract / method handles: `U64` words or portable identity `Address`. -/
def ensureCrosscallHandleType (context : String) (actual : ValueType) : Except LowerError Unit :=
  match actual with
  | .u64 | .address => .ok ()
  | _ =>
      .error {
        message :=
          s!"{context} expected `U64` or `Address` (portable handle), got `{actual.name}`"
      }

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

end ProofForge.Backend.Evm.Validate
