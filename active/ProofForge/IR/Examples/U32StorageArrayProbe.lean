import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.U32StorageArrayProbe

open ProofForge.IR

def stateLimbs : StateDecl := {
  id := "limbs"
  kind := .array 4
  type := .u32
}

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def ix (value : Nat) : Expr :=
  .literal (.u64 value)

def limbPath (index : Nat) : Array StoragePathSegment :=
  #[.index (ix index)]

def readLimb (index : Nat) : Expr :=
  .effect (.storageArrayRead "limbs" (ix index))

def readLimbPath (index : Nat) : Expr :=
  .effect (.storagePathRead "limbs" (limbPath index))

def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u64
  body := #[
    .effect (.storageArrayWrite "limbs" (ix 0) (u32 7)),
    .effect (.storageArrayWrite "limbs" (ix 1) (u32 11)),
    .effect (.storageArrayWrite "limbs" (ix 2) (.add (u32 6) (u32 7))),
    .effect (.storagePathWrite "limbs" (limbPath 3) (u32 17)),
    .effect (.storagePathAssignOp "limbs" (limbPath 0) .add (u32 5)),
    .effect (.storagePathAssignOp "limbs" (limbPath 0) .mul (u32 2)),
    .effect (.storagePathAssignOp "limbs" (limbPath 0) .div (u32 3)),
    .effect (.storagePathAssignOp "limbs" (limbPath 0) .mod (u32 5)),
    .effect (.storagePathAssignOp "limbs" (limbPath 1) .sub (u32 3)),
    .effect (.storagePathAssignOp "limbs" (limbPath 1) .bitOr (u32 16)),
    .effect (.storagePathAssignOp "limbs" (limbPath 1) .bitAnd (u32 28)),
    .effect (.storagePathAssignOp "limbs" (limbPath 1) .bitXor (u32 10)),
    .effect (.storagePathAssignOp "limbs" (limbPath 2) .shiftLeft (u32 1)),
    .effect (.storagePathAssignOp "limbs" (limbPath 2) .shiftRight (u32 2)),
    .effect (.storagePathAssignOp "limbs" (limbPath 3) .div (u32 17)),
    .letBind "sum" .u32 (.add
      (.add
        (readLimb 0)
        (readLimb 1))
      (.add
        (readLimb 2)
        (readLimbPath 3))),
    .assertEq (.local "sum") (u32 28) "u32 storage array read/write preserves u32 values",
    .return (.cast (.local "sum") .u64)
  ]
}

def module : Module := {
  name := "U32StorageArrayProbe"
  state := #[stateLimbs]
  entrypoints := #[storageLifecycle]
}

end ProofForge.IR.Examples.U32StorageArrayProbe
