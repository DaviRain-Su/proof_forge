import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmTypedStorageProbe

open ProofForge.IR

def stateFlag : StateDecl := {
  id := "flag"
  kind := .scalar
  type := .bool
}

def stateLimbs : StateDecl := {
  id := "limbs"
  kind := .array 3
  type := .u32
}

def stateFlags : StateDecl := {
  id := "flags"
  kind := .array 2
  type := .bool
}

def stateRoots : StateDecl := {
  id := "roots"
  kind := .array 2
  type := .hash
}

def stateAfter : StateDecl := {
  id := "after"
  kind := .scalar
  type := .u64
}

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def boolLit (value : Bool) : Expr :=
  .literal (.bool value)

def hashLit (a b c d : Nat) : Expr :=
  .literal (.hash4 a b c d)

def pathIndex (value : Nat) : Array StoragePathSegment :=
  #[.index (u64 value)]

def rootA : Expr :=
  hashLit 1 2 3 4

def rootB : Expr :=
  hashLit 5 6 7 8

def boolScalarLifecycle : Entrypoint := {
  name := "bool_scalar_lifecycle"
  selector? := some "06422075"
  returns := .bool
  body := #[
    .effect (.storageScalarWrite "flag" (boolLit true)),
    .assertEq (.effect (.storageScalarRead "flag")) (boolLit true) "bool scalar storage reads true",
    .return (.effect (.storageScalarRead "flag"))
  ]
}

def typedArrayLifecycle : Entrypoint := {
  name := "typed_array_lifecycle"
  selector? := some "9f3c504b"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "after" (u64 999)),
    .effect (.storageArrayWrite "limbs" (u64 0) (u32 7)),
    .effect (.storageArrayWrite "limbs" (u64 1) (u32 11)),
    .effect (.storagePathWrite "limbs" (pathIndex 2) (u32 13)),
    .effect (.storageArrayWrite "flags" (u64 0) (boolLit true)),
    .effect (.storagePathWrite "flags" (pathIndex 1) (boolLit false)),
    .effect (.storageArrayWrite "roots" (u64 0) rootA),
    .effect (.storagePathWrite "roots" (pathIndex 1) rootB),
    .assertEq (.effect (.storageArrayRead "flags" (u64 0))) (boolLit true) "bool array reads true",
    .assertEq (.effect (.storagePathRead "flags" (pathIndex 1))) (boolLit false) "bool array path reads false",
    .assertEq (.effect (.storageArrayRead "roots" (u64 0))) rootA "hash array reads first root",
    .assertEq (.effect (.storagePathRead "roots" (pathIndex 1))) rootB "hash array path reads second root",
    .letBind "sum" .u32 (.add
      (.add
        (.effect (.storageArrayRead "limbs" (u64 0)))
        (.effect (.storageArrayRead "limbs" (u64 1))))
      (.effect (.storagePathRead "limbs" (pathIndex 2)))),
    .return (.add
      (.cast (.local "sum") .u64)
      (.cast (.effect (.storageArrayRead "flags" (u64 0))) .u64))
  ]
}

def pathAssignU32 : Entrypoint := {
  name := "path_assign_u32"
  selector? := some "5ab2cb77"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "limbs" (pathIndex 0) (u32 10)),
    .effect (.storagePathAssignOp "limbs" (pathIndex 0) .add (u32 5)),
    .effect (.storagePathAssignOp "limbs" (pathIndex 0) .mul (u32 2)),
    .return (.cast (.effect (.storagePathRead "limbs" (pathIndex 0))) .u64)
  ]
}

def readFlag : Entrypoint := {
  name := "read_flag"
  selector? := some "afbe1175"
  params := #[("index", .u64)]
  returns := .bool
  body := #[
    .return (.effect (.storageArrayRead "flags" (.local "index")))
  ]
}

def writeLimb : Entrypoint := {
  name := "write_limb"
  selector? := some "6a088e19"
  params := #[("index", .u64), ("value", .u32)]
  returns := .unit
  body := #[
    .effect (.storageArrayWrite "limbs" (.local "index") (.local "value"))
  ]
}

def readRoot : Entrypoint := {
  name := "read_root"
  selector? := some "4994f441"
  params := #[("index", .u64)]
  returns := .hash
  body := #[
    .return (.effect (.storageArrayRead "roots" (.local "index")))
  ]
}

def module : Module := {
  name := "EvmTypedStorageProbe"
  state := #[stateFlag, stateLimbs, stateFlags, stateRoots, stateAfter]
  entrypoints := #[
    boolScalarLifecycle,
    typedArrayLifecycle,
    pathAssignU32,
    readFlag,
    writeLimb,
    readRoot
  ]
}

end ProofForge.IR.Examples.EvmTypedStorageProbe
