import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmStorageStructProbe

open ProofForge.IR

def pointStruct : StructDecl := {
  name := "Point"
  fields := #[
    { id := "x", type := .u64 },
    { id := "y", type := .u64 }
  ]
}

def metaStruct : StructDecl := {
  name := "Meta"
  fields := #[
    { id := "flag", type := .bool },
    { id := "count", type := .u32 },
    { id := "root", type := .hash }
  ]
}

def stateBefore : StateDecl := {
  id := "before"
  kind := .scalar
  type := .u64
}

def stateCurrent : StateDecl := {
  id := "current"
  kind := .scalar
  type := .structType "Point"
}

def stateAfter : StateDecl := {
  id := "after"
  kind := .scalar
  type := .u64
}

def statePoints : StateDecl := {
  id := "points"
  kind := .array 2
  type := .structType "Point"
}

def stateMeta : StateDecl := {
  id := "meta"
  kind := .scalar
  type := .structType "Meta"
}

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def bool (value : Bool) : Expr :=
  .literal (.bool value)

def hash (a b c d : Nat) : Expr :=
  .literal (.hash4 a b c d)

def point (x y : Nat) : Expr :=
  .structLit "Point" #[
    ("x", u64 x),
    ("y", u64 y)
  ]

def storagePoint (index : Nat) : Expr :=
  .structLit "Point" #[
    ("x", .effect (.storageArrayStructFieldRead "points" (u64 index) "x")),
    ("y", .effect (.storageArrayStructFieldRead "points" (u64 index) "y"))
  ]

def pathIndex (value : Nat) : StoragePathSegment :=
  .index (u64 value)

def pathField (fieldName : String) : StoragePathSegment :=
  .field fieldName

def structLifecycle : Entrypoint := {
  name := "struct_lifecycle"
  selector? := some "93ddf147"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "before" (u64 111)),
    .effect (.storageScalarWrite "after" (u64 222)),
    .effect (.storageStructFieldWrite "current" "x" (u64 7)),
    .effect (.storageStructFieldWrite "current" "y" (u64 11)),
    .return (.add
      (.effect (.storageStructFieldRead "current" "x"))
      (.effect (.storageStructFieldRead "current" "y")))
  ]
}

def pathLifecycle : Entrypoint := {
  name := "path_lifecycle"
  selector? := some "84c21205"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "current" #[pathField "x"] (u64 21)),
    .effect (.storagePathWrite "current" #[pathField "y"] (u64 22)),
    .effect (.storagePathAssignOp "current" #[pathField "x"] .add (u64 5)),
    .return (.add
      (.effect (.storagePathRead "current" #[pathField "x"]))
      (.effect (.storagePathRead "current" #[pathField "y"])))
  ]
}

def arrayStructLifecycle : Entrypoint := {
  name := "array_struct_lifecycle"
  selector? := some "2d84bb06"
  returns := .u64
  body := #[
    .effect (.storageArrayStructFieldWrite "points" (u64 0) "x" (u64 3)),
    .effect (.storageArrayStructFieldWrite "points" (u64 0) "y" (u64 5)),
    .effect (.storageArrayStructFieldWrite "points" (u64 1) "x" (u64 7)),
    .effect (.storageArrayStructFieldWrite "points" (u64 1) "y" (u64 11)),
    .return (.add
      (.effect (.storageArrayStructFieldRead "points" (u64 1) "x"))
      (.effect (.storageArrayStructFieldRead "points" (u64 0) "y")))
  ]
}

def returnPoints : Entrypoint := {
  name := "return_points"
  selector? := some "d16ccd19"
  returns := .fixedArray (.structType "Point") 2
  body := #[
    .effect (.storageArrayStructFieldWrite "points" (u64 0) "x" (u64 29)),
    .effect (.storageArrayStructFieldWrite "points" (u64 0) "y" (u64 31)),
    .effect (.storageArrayStructFieldWrite "points" (u64 1) "x" (u64 37)),
    .effect (.storageArrayStructFieldWrite "points" (u64 1) "y" (u64 41)),
    .return (.arrayLit (.structType "Point") #[
      storagePoint 0,
      storagePoint 1
    ])
  ]
}

def arrayPathLifecycle : Entrypoint := {
  name := "array_path_lifecycle"
  selector? := some "2991a157"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "points" #[pathIndex 1, pathField "x"] (u64 13)),
    .effect (.storagePathAssignOp "points" #[pathIndex 1, pathField "x"] .add (u64 2)),
    .effect (.storagePathWrite "points" #[pathIndex 0, pathField "y"] (u64 8)),
    .return (.add
      (.effect (.storagePathRead "points" #[pathIndex 1, pathField "x"]))
      (.effect (.storagePathRead "points" #[pathIndex 0, pathField "y"])))
  ]
}

def typedSum : Entrypoint := {
  name := "typed_sum"
  selector? := some "2ec467be"
  returns := .u64
  body := #[
    .effect (.storageStructFieldWrite "meta" "flag" (bool true)),
    .effect (.storageStructFieldWrite "meta" "count" (u32 33)),
    .return (.add
      (.cast (.effect (.storageStructFieldRead "meta" "flag")) .u64)
      (.cast (.effect (.storageStructFieldRead "meta" "count")) .u64))
  ]
}

def rootValue : Entrypoint := {
  name := "root_value"
  selector? := some "c42f8c06"
  returns := .hash
  body := #[
    .effect (.storageStructFieldWrite "meta" "root" (hash 1 2 3 4)),
    .return (.effect (.storageStructFieldRead "meta" "root"))
  ]
}

def wholeStructWriteSum : Entrypoint := {
  name := "whole_struct_write_sum"
  selector? := some "c1e31e63"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "current" (point 30 40)),
    .letBind "snapshot" (.structType "Point") (.effect (.storageScalarRead "current")),
    .return (.add
      (.field (.local "snapshot") "x")
      (.field (.local "snapshot") "y"))
  ]
}

def wholeStructReturn : Entrypoint := {
  name := "whole_struct_return"
  selector? := some "cd13529b"
  returns := .structType "Point"
  body := #[
    .effect (.storageScalarWrite "current" (point 8 13)),
    .return (.effect (.storageScalarRead "current"))
  ]
}

def selfStructStorageWrite : Entrypoint := {
  name := "self_struct_storage_write"
  selector? := some "696ddaa7"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "current" (point 5 7)),
    .effect (.storageScalarWrite "current" (.structLit "Point" #[
      ("x", .field (.effect (.storageScalarRead "current")) "y"),
      ("y", .field (.effect (.storageScalarRead "current")) "x")
    ])),
    .return (.add
      (.mul (.effect (.storageStructFieldRead "current" "x")) (u64 100))
      (.effect (.storageStructFieldRead "current" "y")))
  ]
}

def readPointX : Entrypoint := {
  name := "read_point_x"
  selector? := some "db006782"
  params := #[("index", .u64)]
  returns := .u64
  body := #[
    .return (.effect (.storageArrayStructFieldRead "points" (.local "index") "x"))
  ]
}

def dynamicArrayPathLifecycle : Entrypoint := {
  name := "dynamic_array_path_lifecycle"
  selector? := some "a1b2c3d4"
  params := #[("index", .u64)]
  returns := .u64
  body := #[
    .ifElse (.le (.local "index") (u64 1))
      #[
        .effect (.storagePathWrite "points" #[.index (.local "index"), pathField "x"] (u64 42)),
        .effect (.storagePathAssignOp "points" #[.index (.local "index"), pathField "x"] .add (u64 3)),
        .return (.effect (.storagePathRead "points" #[.index (.local "index"), pathField "x"]))
      ]
      #[.return (u64 0)]
  ]
}

def module : Module := {
  name := "EvmStorageStructProbe"
  structs := #[pointStruct, metaStruct]
  state := #[stateBefore, stateCurrent, stateAfter, statePoints, stateMeta]
  entrypoints := #[
    structLifecycle,
    pathLifecycle,
    arrayStructLifecycle,
    returnPoints,
    arrayPathLifecycle,
    typedSum,
    rootValue,
    wholeStructWriteSum,
    wholeStructReturn,
    selfStructStorageWrite,
    readPointX
  ]
}

/-- Quint/MBT subset: struct field and array-of-struct `storagePath*` paths. -/
def emitQuintPathModule : Module := {
  name := "EvmStorageStructProbe"
  structs := #[pointStruct]
  state := #[stateCurrent, statePoints]
  entrypoints := #[pathLifecycle, arrayPathLifecycle]
}

/-- Quint/MBT subset: dynamic-index `storagePath*` on array-of-struct storage. -/
def emitQuintDynamicStructPathModule : Module := {
  name := "EvmStorageStructProbe"
  structs := #[pointStruct]
  state := #[statePoints]
  entrypoints := #[dynamicArrayPathLifecycle]
}

end ProofForge.IR.Examples.EvmStorageStructProbe
