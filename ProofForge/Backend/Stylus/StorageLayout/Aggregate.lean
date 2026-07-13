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

end ProofForge.Backend.Stylus.StorageLayout.Aggregate
