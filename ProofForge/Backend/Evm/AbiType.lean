import ProofForge.IR.Contract

namespace ProofForge.Backend.Evm.AbiType

open ProofForge.IR

/-- `paramAbiWords` changes the host-visible ABI shape without changing the IR
carrier. Keep the two representations compatible so selector generation,
calldata validation, and local lowering cannot disagree about one word. -/
def abiWordOverrideCompatible (type : ValueType) (abiWord : String) : Bool :=
  match type, abiWord with
  | .u8, "uint8" => true
  | .u32, "uint32" => true
  | .u64, "uint64" => true
  | .u128, "uint128" => true
  | .bool, "bool" => true
  | .hash, "uint256" | .hash, "bytes32" => true
  | .address, "address" => true
  -- Contract.Source represents these EVM surface words with a portable U64
  -- carrier. Their canonical calldata guards are applied by ToYul.Abi.
  | .u64, "address" | .u64, "bytes4" => true
  | _, _ => false

def validateAbiWordOverride
    (context : String) (type : ValueType) (abiWord? : Option String) : Except String Unit :=
  match abiWord? with
  | none => .ok ()
  | some abiWord =>
      if abiWordOverrideCompatible type abiWord then
        .ok ()
      else
        .error s!"{context} has incompatible EVM ABI override `{abiWord}` for IR carrier `{type.name}`"

def scalarTypeName
    (context : String) (type : ValueType) (abiWord? : Option String := none) :
    Except String String := do
  validateAbiWordOverride context type abiWord?
  match abiWord? with
  | some word => .ok word
  | none =>
      match type with
      | .u8 => .ok "uint8"
      | .u32 => .ok "uint32"
      | .u64 => .ok "uint256"
      | .u128 => .ok "uint128"
      | .bool => .ok "bool"
      | .hash => .ok "bytes32"
      | .address => .ok "address"
      | .bytes => .ok "bytes"
      | .string => .ok "string"
      | .unit | .fixedArray _ _ | .structType _ | .array _ =>
          .error s!"{context} has unsupported EVM ABI word type `{type.name}`; entrypoint ABI words support U8, U32, U64, U128, Bool, Hash, Address, Bytes, or String"

partial def typeName
    (module : Module) (context : String) (type : ValueType)
    (abiWord? : Option String := none) : Except String String := do
  validateAbiWordOverride context type abiWord?
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string =>
      scalarTypeName context type abiWord?
  | .unit =>
      .error s!"{context} uses Unit; EVM entrypoint parameters and non-Unit returns must use supported ABI values"
  | .array elementType => do
      let elementAbiType ← typeName module s!"{context} dynamic-array element" elementType
      .ok s!"{elementAbiType}[]"
  | .fixedArray elementType length => do
      if length == 0 then
        .error s!"{context} uses Array<{elementType.name},0>; EVM entrypoint ABI fixed arrays must have non-zero length"
      let elementAbiType ← typeName module s!"{context} fixed-array element" elementType
      .ok s!"{elementAbiType}[{length}]"
  | .structType typeName => do
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error s!"{context} uses unknown struct `{typeName}`"
      if decl.fields.isEmpty then
        .error s!"{context} uses empty struct `{typeName}`; EVM entrypoint ABI structs must have at least one field"
      let mut parts := #[]
      for field in decl.fields do
        parts := parts.push (← scalarTypeName
          s!"{context} struct `{typeName}` field `{field.id}`" field.type)
      .ok ("(" ++ String.intercalate "," parts.toList ++ ")")

mutual
  /-- JSON ABI descriptors are intentionally separate from selector canonical
  type strings. Solidity selectors use `(uint256,uint256)` while JSON ABI uses
  `type: "tuple"` plus named `components`. -/
  inductive Descriptor where
    | scalar (typeName : String)
    | tuple (components : Array Component)
    | array (element : Descriptor) (length? : Option Nat)
    deriving Repr

  structure Component where
    name : String
    descriptor : Descriptor
    deriving Repr
end

partial def descriptor
    (module : Module) (context : String) (type : ValueType)
    (abiWord? : Option String := none) : Except String Descriptor := do
  validateAbiWordOverride context type abiWord?
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string =>
      .ok (.scalar (← scalarTypeName context type abiWord?))
  | .unit =>
      .error s!"{context} uses Unit; EVM entrypoint parameters and non-Unit returns must use supported ABI values"
  | .array elementType =>
      .ok (.array (← descriptor module s!"{context} dynamic-array element" elementType) none)
  | .fixedArray elementType length => do
      if length == 0 then
        .error s!"{context} uses Array<{elementType.name},0>; EVM entrypoint ABI fixed arrays must have non-zero length"
      .ok (.array (← descriptor module s!"{context} fixed-array element" elementType) (some length))
  | .structType structName => do
      let some decl := module.structs.find? fun decl => decl.name == structName
        | .error s!"{context} uses unknown struct `{structName}`"
      if decl.fields.isEmpty then
        .error s!"{context} uses empty struct `{structName}`; EVM entrypoint ABI structs must have at least one field"
      let mut components := #[]
      for field in decl.fields do
        components := components.push {
          name := field.id
          descriptor := ← descriptor module
            s!"{context} struct `{structName}` field `{field.id}`" field.type
        }
      .ok (.tuple components)

def jsonEscape (value : String) : String :=
  value.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"

mutual
  partial def Descriptor.jsonType : Descriptor → String
    | .scalar typeName => typeName
    | .tuple _ => "tuple"
    | .array element none => s!"{element.jsonType}[]"
    | .array element (some length) => s!"{element.jsonType}[{length}]"

  partial def Descriptor.baseComponents? : Descriptor → Option (Array Component)
    | .scalar _ => none
    | .tuple components => some components
    | .array element _ => element.baseComponents?

  partial def Descriptor.jsonFields (descriptor : Descriptor) : String :=
    let typeField := s!"\"type\":\"{jsonEscape descriptor.jsonType}\""
    match descriptor.baseComponents? with
    | none => typeField
    | some components =>
        let rendered := String.intercalate "," (components.map Component.toJson).toList
        typeField ++ s!",\"components\":[{rendered}]"

  partial def Component.toJson (component : Component) : String :=
    s!"\{\"name\":\"{jsonEscape component.name}\",{component.descriptor.jsonFields}}"
end

def Descriptor.toJson (descriptor : Descriptor) (name? : Option String := none) : String :=
  let nameField := match name? with
    | none => ""
    | some name => s!"\"name\":\"{jsonEscape name}\","
  s!"\{{nameField}{descriptor.jsonFields}}"

partial def wordTypes
    (module : Module) (context : String) (type : ValueType) :
    Except String (Array String) := do
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string =>
      .ok #[← scalarTypeName context type]
  | .unit =>
      .error s!"{context} uses Unit; EVM ABI values must use supported ABI values"
  | .array elementType => do
      let elementAbiType ← typeName module s!"{context} dynamic-array element" elementType
      .ok #[s!"{elementAbiType}[]"]
  | .fixedArray elementType length => do
      if length == 0 then
        .error s!"{context} uses Array<{elementType.name},0>; EVM entrypoint ABI fixed arrays must have non-zero length"
      let elementWords ← wordTypes module s!"{context} fixed-array element" elementType
      let mut words := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName => do
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error s!"{context} uses unknown struct `{typeName}`"
      if decl.fields.isEmpty then
        .error s!"{context} uses empty struct `{typeName}`; EVM entrypoint ABI structs must have at least one field"
      let mut words := #[]
      for field in decl.fields do
        words := words.push (← scalarTypeName
          s!"{context} struct `{typeName}` field `{field.id}`" field.type)
      .ok words

end ProofForge.Backend.Evm.AbiType
