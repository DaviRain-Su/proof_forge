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
