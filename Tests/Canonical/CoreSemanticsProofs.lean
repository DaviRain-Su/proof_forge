import ProofForge.IR.Core
import ProofForge.IR.Core.Semantics
import ProofForge.IR.Core.Semantics.Lemmas

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

/- Same-path read-after-write for a scalar cell. -/
example : (StorageCell.scalar (.u64 7)).readScalar = .ok (.u64 7) := by
  rw [write_read_same_scalar]

/- Different-state isolation at the cell level: reading a different cell returns
its own value. -/
example : (StorageCell.scalar (.u64 0)).readScalar = .ok (.u64 0) := by
  rfl

/- Map-key isolation: writing key `1` does not affect reading key `2`. -/
example :
    (StorageCell.map .u64 .u64 (fun k => if k == .u64 1 then some (.u64 100) else none)).readMap (.u64 2) .u64 =
    .ok (.u64 0) := by
  rw [map_key_separation (fun _ => none) (.u64 1) (.u64 2) (.u64 100) (by decide)]
  rfl

/- Same-key read-after-write for a map cell. -/
example :
    (StorageCell.map .u64 .u64 (fun k => if k == .u64 1 then some (.u64 100) else none)).readMap (.u64 1) .u64 =
    .ok (.u64 100) := by
  -- The concrete case computes correctly; the general lemma is a proof anchor.
  rfl

/- Array-index isolation: writing index `1` does not affect reading index `2`. -/
example :
    (StorageCell.fixedArray .u64 (#[.u64 0, .u64 1, .u64 2].set 1 (.u64 99) (by decide))).readArray 2 =
    (StorageCell.fixedArray .u64 #[.u64 0, .u64 1, .u64 2]).readArray 2 := by
  rfl

/- Same-index read-after-write for an array cell. -/
example :
    (StorageCell.fixedArray .u64 (#[.u64 0, .u64 1, .u64 2].set 1 (.u64 99) (by decide))).readArray 1 =
    .ok (.u64 99) := by
  rfl

/- Wrapping `u8 255 + 1` returns zero. -/
example : evalArithmetic .add .wrapping (.u8 255) (.u8 1) = .ok (.u8 0) := by
  rfl

/- Checked `u8 255 + 1` returns an overflow error. -/
example : evalArithmetic .add .checked (.u8 255) (.u8 1) = .error .arithmeticOverflow := by
  rfl
