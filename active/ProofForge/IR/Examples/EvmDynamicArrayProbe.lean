import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmDynamicArrayProbe

open ProofForge.IR

def stateValues : StateDecl := {
  id := "values"
  kind := .dynamicArray
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
    .effect (.storagePathWrite "values" #[pathIndex 0] (u64 7)),
    .effect (.storagePathWrite "values" #[pathIndex 1] (u64 11)),
    .effect (.storagePathWrite "values" #[pathIndex 2] (u64 13)),
    .return (.add
      (.add
        (.effect (.storagePathRead "values" #[pathIndex 0]))
        (.effect (.storagePathRead "values" #[pathIndex 1])))
      (.effect (.storagePathRead "values" #[pathIndex 2])))
  ]
}

def readValue : Entrypoint := {
  name := "read_value"
  selector? := some "ac35feee"
  params := #[("index", .u64)]
  returns := .u64
  body := #[
    .return (.effect (.storagePathRead "values" #[.index (.local "index")]))
  ]
}

def writeValue : Entrypoint := {
  name := "write_value"
  selector? := some "5a6fd3b0"
  params := #[("index", .u64), ("value", .u64)]
  returns := .unit
  body := #[
    .effect (.storagePathWrite "values" #[.index (.local "index")] (.local "value"))
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

def pushValue : Entrypoint := {
  name := "push_value"
  selector? := some "b408dd47"
  params := #[("value", .u64)]
  returns := .unit
  body := #[
    .effect (.storageDynamicArrayPush "values" (.local "value"))
  ]
}

def popValue : Entrypoint := {
  name := "pop_value"
  selector? := some "12c62f71"
  returns := .unit
  body := #[
    .effect (.storageDynamicArrayPop "values")
  ]
}

def module : Module := {
  name := "EvmDynamicArrayProbe"
  state := #[stateValues]
  entrypoints := #[storageLifecycle, readValue, writeValue, pathAssignLifecycle, pushValue, popValue]
}

end ProofForge.IR.Examples.EvmDynamicArrayProbe
