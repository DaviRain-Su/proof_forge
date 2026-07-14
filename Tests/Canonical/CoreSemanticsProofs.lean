import ProofForge.IR.Core
import ProofForge.IR.Core.Semantics
import ProofForge.IR.Core.Semantics.Lemmas

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

local instance {ε α : Type} [BEq ε] [BEq α] : BEq (Except ε α) where
  beq
    | .ok lhs, .ok rhs => lhs == rhs
    | .error lhs, .error rhs => lhs == rhs
    | .ok _, .error _ | .error _, .ok _ => false

/- Cell-level helpers remain covered independently of the logical-path laws. -/
example :
    match (StorageCell.scalar (.u64 0)).writeScalar (.u64 7) with
    | .ok updated => updated.readScalar = .ok (.u64 7)
    | .error _ => False := by
  exact write_read_same_scalar (.u64 0) (.u64 7) (by native_decide)

example :
    (((StorageCell.map .u64 .u64 none #[]).writeMap (.u64 1) (.u64 100)).bind
      (fun updated => updated.readMap (.u64 2) .u64) ==
      (StorageCell.map .u64 .u64 none #[]).readMap (.u64 2) .u64) = true := by
  exact map_key_separation_cell

example :
    ((StorageCell.map .u64 .u64 none #[(.u64 1, .u64 100)]).readMap (.u64 1) .u64 ==
      .ok (.u64 100)) = true := by
  native_decide

example :
    match (StorageCell.fixedArray .u64 #[.u64 0, .u64 1, .u64 2]).writeArray
      1 (.u64 99) with
    | .ok updated => updated.readArray 2 =
        (StorageCell.fixedArray .u64 #[.u64 0, .u64 1, .u64 2]).readArray 2
    | .error _ => False := by
  exact array_index_separation_cell (elem := .u64)
    #[.u64 0, .u64 1, .u64 2] 1 2 (.u64 99)
    (by native_decide) (by decide) (by decide)

/- Required public anchors exercise the real LogicalState path API. -/
example :
    ((writePath scalarPathModule {} default (scalarPath ⟨0⟩) (.u64 7)).bind
      (fun updated => readPath scalarPathModule {} updated (scalarPath ⟨0⟩)) ==
    .ok (.u64 7)) = true := by
  exact write_read_same_concrete

example :
    ((writePath scalarPathModule {} default (scalarPath ⟨0⟩) (.u64 7)).bind
      (fun updated => readPath scalarPathModule {} updated (scalarPath ⟨1⟩)) ==
    readPath scalarPathModule {} default (scalarPath ⟨1⟩)) = true := by
  exact write_read_other_concrete

example :
    ((writePath mapPathModule mapPathEnv default (mapPath ⟨20⟩) (.u64 100)).bind
      (fun updated => readPath mapPathModule mapPathEnv updated (mapPath ⟨21⟩)) ==
    readPath mapPathModule mapPathEnv default (mapPath ⟨21⟩)) = true := by
  exact map_key_separation_concrete

example :
    ((writePath arrayPathModule arrayPathEnv default (arrayPath ⟨30⟩) (.u64 99)).bind
      (fun updated => readPath arrayPathModule arrayPathEnv updated (arrayPath ⟨31⟩)) ==
    readPath arrayPathModule arrayPathEnv default (arrayPath ⟨31⟩)) = true := by
  exact array_index_separation_concrete

/- The required public names remain parameterized laws; the concrete aliases
above are only executable witnesses. -/
#check write_read_same
#check write_read_other
#check map_key_separation
#check array_index_separation

example : evalArithmetic .add .wrapping (.u8 255) (.u8 1) = .ok (.u8 0) := by
  rfl

example : evalArithmetic .add .checked (.u8 255) (.u8 1) = .error .arithmeticOverflow := by
  rfl
