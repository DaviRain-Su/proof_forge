/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM constructor ABI encoding for the CLI. Parses `--evm-constructor-param
name:type` and `--evm-constructor-arg name=value` flags, validates them against
the constructor ABI schema, and emits the ABI-encoded constructor arguments
appended to EVM initcode.

This was previously inlined in `Cli.lean`; it is self-contained (depends only
on `Cli/HexUtil.lean` for hex/string primitives) so it lives in its own module.
The `ConstructorParamSpec` and `ConstructorValueSpec` structures are re-exported
from `Cli.lean` via `export` so existing `ProofForge.Cli.ConstructorParamSpec`
references keep resolving.
-/

import ProofForge.Cli.HexUtil

namespace ProofForge.Cli.ConstructorAbi

open ProofForge.Cli.HexUtil

structure ConstructorParamSpec where
  name : String
  abiType : String
  deriving Repr, BEq

structure ConstructorValueSpec where
  name : String
  value : String
  deriving Repr

def supportedConstructorAbiTypes : Array String :=
  #["uint256", "uint64", "uint32", "bool", "bytes32", "address", "string", "bytes", "uint256[]"]

def constructorParamIsDynamic (abiType : String) : Bool :=
  abiType == "string" || abiType == "bytes" || abiType == "uint256[]"

def constructorParamEncoding (abiType : String) : String :=
  match abiType with
  | "string" | "bytes" => "abi-dynamic-bytes"
  | "uint256[]" => "abi-dynamic-array"
  | _ => "abi-static-word"

def constructorAbiTypeSupported (abiType : String) : Bool :=
  supportedConstructorAbiTypes.contains abiType

def supportedConstructorAbiTypesMessage : String :=
  String.intercalate ", " supportedConstructorAbiTypes.toList

def parseConstructorParamSpec (s : String) : Except String ConstructorParamSpec := do
  match s.splitOn ":" with
  | [name, abiType] =>
      let name := trimAsciiString name
      let abiType := trimAsciiString abiType
      if name.isEmpty then
        .error s!"invalid constructor parameter spec '{s}': name is empty"
      else if abiType.isEmpty then
        .error s!"invalid constructor parameter spec '{s}': type is empty"
      else if !constructorAbiTypeSupported abiType then
        .error s!"unsupported constructor ABI type '{abiType}'; supported types: {supportedConstructorAbiTypesMessage}"
      else
        .ok { name := name, abiType := abiType }
  | _ =>
      .error s!"invalid constructor parameter spec '{s}', expected name:type"

def parseConstructorValueSpec (s : String) : Except String ConstructorValueSpec := do
  match s.splitOn "=" with
  | [name, value] =>
      let name := trimAsciiString name
      let value := trimAsciiString value
      if name.isEmpty then
        .error s!"invalid constructor argument spec '{s}': name is empty"
      else if value.isEmpty then
        .error s!"invalid constructor argument spec '{s}': value is empty"
      else
        .ok { name := name, value := value }
  | _ =>
      .error s!"invalid constructor argument spec '{s}', expected name=value"

def encodeUintConstructorArg (name value : String) (bytes : Nat) : Except String String := do
  let n ← parseUnsignedNat value s!"constructor argument `{name}`"
  if n < byteLimit bytes then
    .ok (fixedHexBytes 32 n)
  else
    .error s!"constructor argument `{name}` does not fit in uint{bytes * 8}"

def encodeBoolConstructorArg (name value : String) : Except String String :=
  match trimAsciiString value with
  | "true" | "True" | "TRUE" | "1" => .ok (fixedHexBytes 32 1)
  | "false" | "False" | "FALSE" | "0" => .ok (fixedHexBytes 32 0)
  | _ => .error s!"constructor argument `{name}` must be true, false, 1, or 0"

def encodeDynamicBytesTail (dataHex : String) (byteLen : Nat) : String :=
  fixedHexBytes 32 byteLen ++ padHexTo32ByteBoundary dataHex

def parseCommaSeparatedNatList (value name : String) : Except String (Array Nat) := do
  let trimmed := trimAsciiString value
  if trimmed.isEmpty then
    .error s!"constructor argument `{name}` must not be empty"
  let mut nums : Array Nat := #[]
  for part in trimmed.splitOn "," do
    let part := trimAsciiString part
    if part.isEmpty then
      .error s!"constructor argument `{name}` must not contain empty elements"
    else
      let n ← parseUnsignedNat part s!"constructor argument `{name}` element"
      nums := nums.push n
  .ok nums

def encodeStringConstructorTail (name value : String) : Except String String := do
  let trimmed := trimAsciiString value
  if trimmed.isEmpty then
    .error s!"constructor argument `{name}` must not be empty"
  let bytes := trimmed.toUTF8
  let dataHex := byteArrayToHex bytes
  .ok (encodeDynamicBytesTail dataHex bytes.size)

def encodeBytesConstructorTail (name value : String) : Except String String := do
  let hex ← normalizeConstructorArgsHex value
  if hex.isEmpty then
    .error s!"constructor argument `{name}` must not be empty"
  .ok (encodeDynamicBytesTail hex (hex.length / 2))

def encodeUint256ArrayConstructorTail (name value : String) : Except String String := do
  let nums ← parseCommaSeparatedNatList value name
  if !nums.all (fun n => n < byteLimit 32) then
    .error s!"constructor argument `{name}` element does not fit in uint256"
  else
    let countWord := fixedHexBytes 32 nums.size
    let elemWords := String.intercalate "" (nums.toList.map (fixedHexBytes 32))
    .ok (countWord ++ elemWords)

def encodeDynamicConstructorTail (param : ConstructorParamSpec) (value : String) : Except String String :=
  match param.abiType with
  | "string" => encodeStringConstructorTail param.name value
  | "bytes" => encodeBytesConstructorTail param.name value
  | "uint256[]" => encodeUint256ArrayConstructorTail param.name value
  | abiType => .error s!"unsupported dynamic constructor ABI type '{abiType}'"

def encodeStaticConstructorValue (param : ConstructorParamSpec) (value : String) : Except String String := do
  match param.abiType with
  | "uint256" => encodeUintConstructorArg param.name value 32
  | "uint64" => encodeUintConstructorArg param.name value 8
  | "uint32" => encodeUintConstructorArg param.name value 4
  | "bool" => encodeBoolConstructorArg param.name value
  | "bytes32" => normalizeExactHexBytes value s!"constructor argument `{param.name}`" 32
  | "address" =>
      let address ← normalizeExactHexBytes value s!"constructor argument `{param.name}`" 20
      .ok (repeatString 24 "0" ++ address)
  | abiType => .error s!"unsupported static constructor ABI type '{abiType}'"

def constructorParamExists (params : Array ConstructorParamSpec) (name : String) : Bool :=
  params.any (fun param => param.name == name)

def constructorValueCount (values : Array ConstructorValueSpec) (name : String) : Nat :=
  values.foldl (fun count value => if value.name == name then count + 1 else count) 0

def findConstructorValue? (values : Array ConstructorValueSpec) (name : String) : Option String :=
  values.foldl
    (fun found value =>
      match found with
      | some _ => found
      | none => if value.name == name then some value.value else none)
    none

def validateConstructorValues (_params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Except String Unit := do
  for value in values do
    if constructorValueCount values value.name > 1 then
      .error s!"duplicate --evm-constructor-arg for `{value.name}`"
    else
      pure ()

def validateConstructorValuesAgainstParams
    (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Except String Unit := do
  validateConstructorValues params values
  for value in values do
    if !constructorParamExists params value.name then
      .error s!"--evm-constructor-arg `{value.name}` has no matching --evm-constructor-param"
    else
      pure ()

def encodeConstructorValues (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Except String String := do
  if params.isEmpty then
    .error "--evm-constructor-arg requires at least one --evm-constructor-param"
  validateConstructorValuesAgainstParams params values
  let headWordCount := params.size
  let mut headWords : Array String := #[]
  let mut tailHex := ""
  let mut tailOffset := headWordCount * 32
  for param in params do
    match findConstructorValue? values param.name with
    | some value =>
        if constructorParamIsDynamic param.abiType then
          let tail ← encodeDynamicConstructorTail param value
          headWords := headWords.push (fixedHexBytes 32 tailOffset)
          tailHex := tailHex ++ tail
          tailOffset := tailOffset + tail.length / 2
        else
          let word ← encodeStaticConstructorValue param value
          headWords := headWords.push word
    | none =>
        .error s!"missing --evm-constructor-arg for constructor parameter `{param.name}`"
  .ok (String.intercalate "" headWords.toList ++ tailHex)

def constructorSchemaHasDynamic (params : Array ConstructorParamSpec) : Bool :=
  params.any (fun param => constructorParamIsDynamic param.abiType)

def validateCanonicalAddressWords
    (params : Array ConstructorParamSpec) (argsHex : String) : Except String Unit := do
  for pair in params.zipIdx do
    let param := pair.1
    let idx := pair.2
    if param.abiType == "address" then
      let word := ((argsHex.drop (idx * 64)).take 64).toString
      let high96 := (word.take 24).toString
      if high96 != repeatString 24 "0" then
        .error s!"constructor ABI address parameter `{param.name}` has non-zero high 96 bits"

def validateConstructorSchemaAndArgs (params : Array ConstructorParamSpec) (constructorArgsHex : String) : Except String Unit := do
  let argsHex ← normalizeConstructorArgsHex constructorArgsHex
  if params.isEmpty then
    .ok ()
  else if argsHex.isEmpty then
    .ok ()
  else
    let actualBytes := argsHex.length / 2
    if constructorSchemaHasDynamic params then
      let minBytes := params.size * 32
      if actualBytes < minBytes then
        .error s!"constructor ABI schema expects at least {minBytes} bytes ({params.size} ABI head word(s)), but constructor args have {actualBytes} byte(s)"
    else
      let expectedBytes := params.size * 32
      if actualBytes != expectedBytes then
        .error s!"constructor ABI schema expects {expectedBytes} bytes ({params.size} static-word parameter(s)), but constructor args have {actualBytes} byte(s)"
    validateCanonicalAddressWords params argsHex

end ProofForge.Cli.ConstructorAbi
