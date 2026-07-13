import ProofForge.Backend.Stylus.AbiLayout

namespace ProofForge.Backend.Stylus.StorageLayout.Aggregate

open ProofForge.Backend.Stylus

/-- Word-aligned storage footprint for the first aggregate slice. Packing and
dynamic short/long storage are deliberately separate later layout decisions. -/
partial def staticStorageSlots (limit : Nat) : StylusAbiType -> Except AbiLayoutError Nat
  | .bool | .uint _ | .address | .fixedBytes _ => pure 1
  | .fixedArray element size => do
      if size == 0 then
        .error { message := "static storage fixed array length must be positive" }
      checkedMul "static storage fixed array" limit size (← staticStorageSlots limit element)
  | .tuple fields => do
      if fields.isEmpty then
        .error { message := "static storage tuple must contain at least one field" }
      fields.foldlM (fun slots field => do
        checkedAdd "static storage tuple" limit slots (← staticStorageSlots limit field)) 0
  | .bytes | .string | .dynamicArray _ =>
      .error { message := "dynamic storage type requires short/long storage planning" }

structure DynamicBytesWritePlan where
  /-- Solidity-compatible root slot. Short values are inline; long values store
  `length * 2 + 1`. -/
  rootWord : Array UInt8
  /-- Padded payload words written below `keccak256(rootSlot)`. -/
  dataWords : Array (Array UInt8)
  /-- Zero-based payload word indices left behind by the previous long value. -/
  clearDataWordIndices : Array Nat
  deriving Repr, BEq

structure DynamicArrayStoragePlan where
  lengthWord : Array UInt8
  elementSlots : Nat
  deriving Repr, BEq

private def fail (message : String) : Except AbiLayoutError α :=
  .error { message }

private def wordOfNat (value : Nat) : Array UInt8 :=
  (List.range 32).toArray.map fun index =>
    UInt8.ofNat ((value / (2 ^ (8 * (31 - index)))) % 256)

private def payloadWords (bytes : Array UInt8) : Array (Array UInt8) := Id.run do
  let mut words := #[]
  for offset in [0:(bytes.size + 31) / 32] do
    let chunk := bytes.extract (offset * 32) (min bytes.size ((offset + 1) * 32))
    words := words.push (chunk ++ Array.replicate (32 - chunk.size) 0)
  return words

/-- Plan the Solidity/Stylus short/long bytes transition without committing to a
renderer. `oldLength` is used only to identify stale long payload words. -/
def planDynamicBytesWrite (limit maximumLength oldLength : Nat) (value : Array UInt8) :
    Except AbiLayoutError DynamicBytesWritePlan := do
  if maximumLength == 0 then fail "dynamic storage maximum must be positive"
  if maximumLength > limit then
    fail s!"dynamic storage maximum {maximumLength} exceeds layout limit {limit}"
  if oldLength > maximumLength then
    fail s!"previous dynamic storage length {oldLength} exceeds maximum {maximumLength}"
  if value.size > maximumLength then
    fail s!"dynamic storage length {value.size} exceeds maximum {maximumLength}"
  let oldWords := if oldLength < 32 then 0 else (oldLength + 31) / 32
  if value.size < 32 then
    let root := value ++ Array.replicate (31 - value.size) 0 ++ #[UInt8.ofNat (value.size * 2)]
    pure {
      rootWord := root
      dataWords := #[]
      clearDataWordIndices := (List.range oldWords).toArray
    }
  else
    let words := payloadWords value
    let clearCount := oldWords - min oldWords words.size
    pure {
      rootWord := wordOfNat (value.size * 2 + 1)
      dataWords := words
      clearDataWordIndices := (List.range clearCount).toArray.map (words.size + ·)
    }

/-- Size the payload below `keccak256(rootSlot)` for a bounded dynamic array
whose element layout is static. -/
def planDynamicArrayStorage (limit maximumLength length : Nat) (element : StylusAbiType) :
    Except AbiLayoutError DynamicArrayStoragePlan := do
  if maximumLength == 0 then fail "dynamic-array storage maximum must be positive"
  if maximumLength > limit then
    fail s!"dynamic-array storage maximum {maximumLength} exceeds layout limit {limit}"
  if length > maximumLength then
    fail s!"dynamic-array storage length {length} exceeds maximum {maximumLength}"
  let elementWidth <- staticStorageSlots limit element
  let slots <- checkedMul "dynamic-array storage payload" limit length elementWidth
  pure { lengthWord := wordOfNat length, elementSlots := slots }

end ProofForge.Backend.Stylus.StorageLayout.Aggregate
