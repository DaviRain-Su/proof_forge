import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmStorageArrayProbe

open ProofForge.IR

def stateBefore : StateDecl := {
  id := "before"
  kind := .scalar
  type := .u64
}

def stateValues : StateDecl := {
  id := "values"
  kind := .array 3
  type := .u64
}

def stateAfter : StateDecl := {
  id := "after"
  kind := .scalar
  type := .u64
}

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def pathIndex (value : Nat) : StoragePathSegment :=
  .index (u64 value)

def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  selector? := some "e4684b67"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "before" (u64 111)),
    .effect (.storageScalarWrite "after" (u64 222)),
    .effect (.storageArrayWrite "values" (u64 0) (u64 7)),
    .effect (.storageArrayWrite "values" (u64 1) (u64 11)),
    .effect (.storageArrayWrite "values" (u64 2) (u64 13)),
    .return (.add
      (.add
        (.effect (.storageArrayRead "values" (u64 0)))
        (.effect (.storageArrayRead "values" (u64 1))))
      (.effect (.storageArrayRead "values" (u64 2))))
  ]
}

def readValue : Entrypoint := {
  name := "read_value"
  selector? := some "ac35feee"
  params := #[("index", .u64)]
  returns := .u64
  body := #[
    .return (.effect (.storageArrayRead "values" (.local "index")))
  ]
}

def writeValue : Entrypoint := {
  name := "write_value"
  selector? := some "5a6fd3b0"
  params := #[("index", .u64), ("value", .u64)]
  returns := .unit
  body := #[
    .effect (.storageArrayWrite "values" (.local "index") (.local "value"))
  ]
}

def returnValues : Entrypoint := {
  name := "return_values"
  selector? := some "08b37751"
  returns := .fixedArray .u64 3
  body := #[
    .effect (.storageArrayWrite "values" (u64 0) (u64 17)),
    .effect (.storageArrayWrite "values" (u64 1) (u64 19)),
    .effect (.storageArrayWrite "values" (u64 2) (u64 23)),
    .return (.arrayLit .u64 #[
      .effect (.storageArrayRead "values" (u64 0)),
      .effect (.storageArrayRead "values" (u64 1)),
      .effect (.storageArrayRead "values" (u64 2))
    ])
  ]
}

def pathLifecycle : Entrypoint := {
  name := "path_lifecycle"
  selector? := some "84c21205"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "values" #[pathIndex 0] (u64 21)),
    .effect (.storagePathWrite "values" #[pathIndex 1] (u64 22)),
    .return (.add
      (.effect (.storagePathRead "values" #[pathIndex 0]))
      (.effect (.storagePathRead "values" #[pathIndex 1])))
  ]
}

def pathAssignLifecycle : Entrypoint := {
  name := "path_assign_lifecycle"
  selector? := some "bce9e77b"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "values" #[pathIndex 2] (u64 10)),
    .effect (.storagePathAssignOp "values" #[pathIndex 2] .add (u64 5)),
    .return (.effect (.storagePathRead "values" #[pathIndex 2]))
  ]
}

def module : Module := {
  name := "EvmStorageArrayProbe"
  state := #[stateBefore, stateValues, stateAfter]
  entrypoints := #[storageLifecycle, readValue, writeValue, returnValues, pathLifecycle, pathAssignLifecycle]
}

/-- Quint/MBT subset: multi-segment `storagePath*` on fixed-size scalar arrays. -/
def emitQuintPathModule : Module := {
  name := "EvmStorageArrayProbe"
  state := #[stateValues]
  entrypoints := #[pathLifecycle, pathAssignLifecycle]
}

end ProofForge.IR.Examples.EvmStorageArrayProbe
