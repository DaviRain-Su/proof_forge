import ProofForge.Backend.Stylus.DirectWasm.Storage

namespace ProofForge.Backend.Stylus.DirectWasm

open ProofForge.Backend.Stylus

inductive AbiError where
  | truncatedCalldata
  | unknownSelector
  | nonCanonical (message : String)
  | unsupportedType (type : StylusAbiType)
  deriving Repr, BEq

def AbiError.bytes : AbiError -> Bytes
  | .truncatedCalldata => "stylus: truncated calldata".toUTF8.data
  | .unknownSelector => "stylus: unknown selector".toUTF8.data
  | .nonCanonical message => ("stylus: non-canonical " ++ message).toUTF8.data
  | .unsupportedType type => s!"stylus: unsupported ABI type {repr type}" |>.toUTF8.data

partial def isDynamicAbiType : StylusAbiType -> Bool
  | type => type.isDynamic

def validateAbiCompleteness (abi : StylusAbiPlan) : Except AbiError Unit := do
  for method in abi.methods do
    for param in method.params do
      if param.type.isDynamic && param.type != .bytes && param.type != .string then
        throw (.unsupportedType param.type)
    for result in method.returns do
      if result.isDynamic && result != .bytes && result != .string then
        throw (.unsupportedType result)

def selectorNat (selector : Bytes) : Nat :=
  selector.foldl (fun value byte => value * 256 + byte.toNat) 0

def calldataSelector (calldata : Bytes) : Except AbiError Bytes :=
  if calldata.size < 4 then .error .truncatedCalldata else .ok (calldata.extract 0 4)

def abiWordAt (calldata : Bytes) (index : Nat) : Except AbiError Bytes :=
  let start := 4 + index * 32
  if start + 32 > calldata.size then .error .truncatedCalldata
  else .ok (calldata.extract start (start + 32))

private def allZero (bytes : Bytes) : Bool := bytes.all (· == 0)

def decodeStaticWord (type : StylusAbiType) (word : Bytes) : Except AbiError Bytes := do
  let word <- normalizeWord word |>.mapError fun _ => .truncatedCalldata
  match type with
  | .bool =>
      if allZero (word.extract 0 31) && (word[31]? == some 0 || word[31]? == some 1) then pure word
      else throw (.nonCanonical "bool")
  | .uint bits =>
      let width := bits / 8
      if bits == 0 || bits > 256 || bits % 8 != 0 then throw (.unsupportedType type)
      if allZero (word.extract 0 (32 - width)) then pure word else throw (.nonCanonical s!"uint{bits}")
  | .address =>
      if allZero (word.extract 0 12) then pure word else throw (.nonCanonical "address")
  | .fixedBytes size =>
      if size <= 32 && allZero (word.extract size 32) then pure word
      else throw (.nonCanonical s!"bytes{size}")
  | _ => throw (.unsupportedType type)

def encodeStaticWord (type : StylusAbiType) (word : Bytes) : Except AbiError Bytes :=
  decodeStaticWord type word

end ProofForge.Backend.Stylus.DirectWasm
