import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.StructProbe

open ProofForge.IR

def pointStruct : StructDecl := {
  name := "Point"
  deriveStorage := true
  fields := #[
    { id := "x", type := .u64 },
    { id := "y", type := .u64 }
  ]
}

def stateCurrent : StateDecl := {
  id := "current"
  kind := .scalar
  type := .structType "Point"
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def point (x y : Nat) : Expr :=
  .structLit "Point" #[
    ("x", felt x),
    ("y", felt y)
  ]

def localSum : Entrypoint := {
  name := "local_sum"
  returns := .u64
  body := #[
    .letBind "p" (.structType "Point") (point 10 20),
    .return (.add
      (.field (.local "p") "x")
      (.field (.local "p") "y"))
  ]
}

def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "current" (point 7 11)),
    .effect (.storageStructFieldWrite "current" "y" (felt 19)),
    .return (.add
      (.effect (.storageStructFieldRead "current" "x"))
      (.effect (.storageStructFieldRead "current" "y")))
  ]
}

def module : Module := {
  name := "StructProbe"
  structs := #[pointStruct]
  state := #[stateCurrent]
  entrypoints := #[localSum, storageLifecycle]
}

/-- EmitWat-compatible subset for 16c-1: only `localSum` (structLit + field),
    no storage. -/
def emitWatLocalSumModule : Module := {
  name := "StructProbe"
  structs := #[pointStruct]
  state := #[]
  entrypoints := #[localSum]
}

/-- Quint/MBT subset: storage struct field read/write lifecycle. -/
def emitWatStorageModule : Module := {
  name := "StructProbe"
  structs := #[pointStruct]
  state := #[stateCurrent]
  entrypoints := #[storageLifecycle]
}


end ProofForge.IR.Examples.StructProbe
