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

end ProofForge.Backend.Stylus
