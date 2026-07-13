import ProofForge.Backend.Stylus.DirectWasm.Storage

namespace ProofForge.Backend.Stylus

structure AbiLayoutError where
  message : String
  deriving Repr, BEq

structure DynamicAbiSlice where
  offset : Nat
  dataOffset : Nat
  length : Nat
  paddedEnd : Nat
  deriving Repr, BEq

structure DynamicArrayAbiSlice where
  offset : Nat
  dataOffset : Nat
  length : Nat
  elementWords : Nat
  endOffset : Nat
  deriving Repr, BEq

private def fail (message : String) : Except AbiLayoutError α :=
  .error { message }

def checkedAdd (context : String) (limit lhs rhs : Nat) : Except AbiLayoutError Nat := do
  if lhs > limit || rhs > limit || rhs > limit - lhs then
    fail s!"{context} exceeds layout limit {limit}: {lhs} + {rhs}"
  pure (lhs + rhs)

def checkedMul (context : String) (limit lhs rhs : Nat) : Except AbiLayoutError Nat := do
  if lhs > limit || rhs > limit || (lhs != 0 && rhs > limit / lhs) then
    fail s!"{context} exceeds layout limit {limit}: {lhs} * {rhs}"
  pure (lhs * rhs)

partial def staticAbiWords (limit : Nat) : StylusAbiType -> Except AbiLayoutError Nat
  | .bool | .uint _ | .address | .fixedBytes _ => pure 1
  | .fixedArray element size => do
      if size == 0 then fail "static ABI fixed array length must be positive"
      checkedMul "static ABI fixed array" limit size (← staticAbiWords limit element)
  | .tuple fields => do
      if fields.isEmpty then fail "static ABI tuple must contain at least one field"
      fields.foldlM (fun words field => do
        checkedAdd "static ABI tuple" limit words (← staticAbiWords limit field)) 0
  | .bytes | .string | .dynamicArray _ =>
      fail "dynamic ABI type has no fixed static-word layout"

def abiHeadWords (limit : Nat) (params : Array StylusAbiParamPlan) : Except AbiLayoutError Nat :=
  params.foldlM (fun words param => do
    let width ← if param.type.isDynamic then pure 1 else staticAbiWords limit param.type
    checkedAdd s!"ABI head for `{param.name}`" limit words width) 0

def roundUpWord (length : Nat) : Nat :=
  ((length + 31) / 32) * 32

private def wordAt (bytes : Array UInt8) (offset : Nat) : Except AbiLayoutError (Array UInt8) :=
  if offset + 32 <= bytes.size then pure (bytes.extract offset (offset + 32))
  else fail s!"ABI word at {offset} exceeds calldata length {bytes.size}"

private def allZero (bytes : Array UInt8) : Bool := bytes.all (· == 0)

private partial def validateStaticAt (bytes : Array UInt8) (offset : Nat) : StylusAbiType ->
    Except AbiLayoutError Nat
  | .bool => do
      let word ← wordAt bytes offset
      unless allZero (word.extract 0 31) && (word[31]? == some 0 || word[31]? == some 1) do
        fail s!"non-canonical bool at ABI offset {offset}"
      pure (offset + 32)
  | .uint bits => do
      if bits == 0 || bits > 256 || bits % 8 != 0 then fail s!"unsupported uint{bits} ABI width"
      let word ← wordAt bytes offset
      unless allZero (word.extract 0 (32 - bits / 8)) do
        fail s!"non-canonical uint{bits} at ABI offset {offset}"
      pure (offset + 32)
  | .address => do
      let word ← wordAt bytes offset
      unless allZero (word.extract 0 12) do fail s!"non-canonical address at ABI offset {offset}"
      pure (offset + 32)
  | .fixedBytes size => do
      if size == 0 || size > 32 then fail s!"unsupported bytes{size} ABI width"
      let word ← wordAt bytes offset
      unless allZero (word.extract size 32) do fail s!"non-canonical bytes{size} at ABI offset {offset}"
      pure (offset + 32)
  | .fixedArray element size => do
      if size == 0 then fail "dynamic-array element contains a zero-length fixed array"
      let mut next := offset
      for _ in [0:size] do next ← validateStaticAt bytes next element
      pure next
  | .tuple fields => do
      if fields.isEmpty then fail "dynamic-array element contains an empty tuple"
      let mut next := offset
      for field in fields do next ← validateStaticAt bytes next field
      pure next
  | .bytes | .string | .dynamicArray _ =>
      fail "nested dynamic-array elements require recursive tail planning"

def decodeDynamicArgument (arguments : Array UInt8) (headWords index maximumLength : Nat) :
    Except AbiLayoutError DynamicAbiSlice := do
  if index >= headWords then fail s!"dynamic ABI argument index {index} exceeds head arity {headWords}"
  let headBytes := headWords * 32
  if headBytes > arguments.size then fail "dynamic ABI head is truncated"
  let offset := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments (index * 32))
  if offset % 32 != 0 then fail s!"dynamic ABI offset {offset} is not word aligned"
  if offset < headBytes then fail s!"dynamic ABI offset {offset} points inside the static head"
  let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments offset)
  if length > maximumLength then fail s!"dynamic ABI length {length} exceeds maximum {maximumLength}"
  let dataOffset := offset + 32
  let paddedEnd := dataOffset + roundUpWord length
  if paddedEnd > arguments.size then
    fail s!"dynamic ABI tail end {paddedEnd} exceeds calldata length {arguments.size}"
  pure { offset, dataOffset, length, paddedEnd }

/-- Decode a Solidity `T[]` argument when `T` has a fully static ABI layout.
Every element is canonical-validated before the slice is returned. -/
def decodeDynamicArrayArgument (arguments : Array UInt8) (headWords index maximumElements : Nat)
    (element : StylusAbiType) : Except AbiLayoutError DynamicArrayAbiSlice := do
  if index >= headWords then fail s!"dynamic-array ABI index {index} exceeds head words {headWords}"
  let headBytes ← checkedMul "dynamic-array ABI head" arguments.size headWords 32
  if headBytes > arguments.size then fail "dynamic-array ABI head is truncated"
  let offset := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments (index * 32))
  if offset % 32 != 0 then fail s!"dynamic-array ABI offset {offset} is not word aligned"
  if offset < headBytes then fail s!"dynamic-array ABI offset {offset} points inside the static head"
  let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments offset)
  if length > maximumElements then
    fail s!"dynamic-array length {length} exceeds maximum {maximumElements}"
  let elementWords ← staticAbiWords (arguments.size / 32 + 1) element
  let dataOffset ← checkedAdd "dynamic-array data offset" arguments.size offset 32
  let payloadWords ← checkedMul "dynamic-array payload words" (arguments.size / 32 + 1) length elementWords
  let payloadBytes ← checkedMul "dynamic-array payload bytes" arguments.size payloadWords 32
  let endOffset ← checkedAdd "dynamic-array tail end" arguments.size dataOffset payloadBytes
  if endOffset > arguments.size then
    fail s!"dynamic-array tail end {endOffset} exceeds calldata length {arguments.size}"
  let mut cursor := dataOffset
  for _ in [0:length] do cursor ← validateStaticAt arguments cursor element
  pure { offset, dataOffset, length, elementWords, endOffset }

end ProofForge.Backend.Stylus
