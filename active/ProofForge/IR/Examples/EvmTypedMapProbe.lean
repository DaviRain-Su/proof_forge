import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmTypedMapProbe

open ProofForge.IR

def stateScores : StateDecl := {
  id := "scores"
  kind := .map .u32 16
  type := .u32
}

def stateFlags : StateDecl := {
  id := "flags"
  kind := .map .bool 2
  type := .bool
}

def stateRoots : StateDecl := {
  id := "roots"
  kind := .map .hash 8
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

def mapPath (key : Expr) : Array StoragePathSegment :=
  #[.mapKey key]

def nestedMapPath (outer inner : Expr) : Array StoragePathSegment :=
  #[.mapKey outer, .mapKey inner]

def rootA : Expr :=
  hashLit 1 2 3 4

def rootB : Expr :=
  hashLit 5 6 7 8

def typedMapLifecycle : Entrypoint := {
  name := "typed_map_lifecycle"
  selector? := some "e4e7feaf"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "after" (u64 777)),
    .letBind "old0" .u32 (.effect (.storageMapInsert "scores" (u32 7) (u32 11))),
    .assertEq (.local "old0") (u32 0) "first u32 map insert returns default zero",
    .letBind "old1" .u32 (.effect (.storageMapSet "scores" (u32 7) (u32 13))),
    .assertEq (.local "old1") (u32 11) "u32 map set returns old value",
    .effect (.storagePathWrite "scores" (mapPath (u32 8)) (u32 17)),
    .letBind "flagOld" .bool (.effect (.storageMapSet "flags" (boolLit true) (boolLit true))),
    .assertEq (.local "flagOld") (boolLit false) "first bool map set returns false",
    .effect (.storagePathWrite "flags" (mapPath (boolLit false)) (boolLit false)),
    .letBind "rootOld" .hash (.effect (.storageMapSet "roots" rootA rootB)),
    .assertEq (.local "rootOld") (hashLit 0 0 0 0) "first hash map set returns zero hash",
    .assertEq (.effect (.storageMapGet "flags" (boolLit true))) (boolLit true) "bool map reads true",
    .assertEq (.effect (.storagePathRead "flags" (mapPath (boolLit false)))) (boolLit false) "bool map path reads false",
    .assertEq (.effect (.storageMapGet "roots" rootA)) rootB "hash map reads bytes32 root",
    .letBind "sum" .u32 (.add
      (.effect (.storageMapGet "scores" (u32 7)))
      (.effect (.storagePathRead "scores" (mapPath (u32 8))))),
    .return (.add
      (.cast (.local "sum") .u64)
      (.cast (.effect (.storageMapGet "flags" (boolLit true))) .u64))
  ]
}

def readScore : Entrypoint := {
  name := "read_score"
  selector? := some "04395342"
  params := #[("key", .u32)]
  returns := .u32
  body := #[
    .return (.effect (.storageMapGet "scores" (.local "key")))
  ]
}

def writeScore : Entrypoint := {
  name := "write_score"
  selector? := some "9dfe7834"
  params := #[
    ("key", .u32),
    ("value", .u32)
  ]
  returns := .unit
  body := #[
    .effect (.storageMapSet "scores" (.local "key") (.local "value"))
  ]
}

def containsScore : Entrypoint := {
  name := "contains_score"
  selector? := some "79b9741a"
  params := #[("key", .u32)]
  returns := .bool
  body := #[
    .return (.effect (.storageMapContains "scores" (.local "key")))
  ]
}

def readFlag : Entrypoint := {
  name := "read_flag"
  selector? := some "7c7d06af"
  params := #[("key", .bool)]
  returns := .bool
  body := #[
    .return (.effect (.storageMapGet "flags" (.local "key")))
  ]
}

def setFlag : Entrypoint := {
  name := "set_flag"
  selector? := some "481794a0"
  params := #[
    ("key", .bool),
    ("value", .bool)
  ]
  returns := .bool
  body := #[
    .return (.effect (.storageMapSet "flags" (.local "key") (.local "value")))
  ]
}

def containsFlag : Entrypoint := {
  name := "contains_flag"
  selector? := some "430d2c8d"
  params := #[("key", .bool)]
  returns := .bool
  body := #[
    .return (.effect (.storageMapContains "flags" (.local "key")))
  ]
}

def readRoot : Entrypoint := {
  name := "read_root"
  selector? := some "ca27ec99"
  params := #[("key", .hash)]
  returns := .hash
  body := #[
    .return (.effect (.storageMapGet "roots" (.local "key")))
  ]
}

def setRoot : Entrypoint := {
  name := "set_root"
  selector? := some "86370059"
  params := #[
    ("key", .hash),
    ("value", .hash)
  ]
  returns := .hash
  body := #[
    .return (.effect (.storageMapSet "roots" (.local "key") (.local "value")))
  ]
}

def containsRoot : Entrypoint := {
  name := "contains_root"
  selector? := some "1f24b6db"
  params := #[("key", .hash)]
  returns := .bool
  body := #[
    .return (.effect (.storageMapContains "roots" (.local "key")))
  ]
}

def pathAssignScore : Entrypoint := {
  name := "path_assign_score"
  selector? := some "a82c9bea"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "scores" (mapPath (u32 9)) (u32 10)),
    .effect (.storagePathAssignOp "scores" (mapPath (u32 9)) .add (u32 5)),
    .effect (.storagePathAssignOp "scores" (mapPath (u32 9)) .mul (u32 2)),
    .return (.cast (.effect (.storagePathRead "scores" (mapPath (u32 9)))) .u64)
  ]
}

def nestedPathScore : Entrypoint := {
  name := "nested_path_score"
  selector? := some "cb239774"
  params := #[
    ("outer", .u32),
    ("inner", .u32),
    ("value", .u32)
  ]
  returns := .u32
  body := #[
    .effect (.storagePathWrite "scores" (nestedMapPath (.local "outer") (.local "inner")) (.local "value")),
    .effect (.storagePathAssignOp "scores" (nestedMapPath (.local "outer") (.local "inner")) .add (u32 5)),
    .return (.effect (.storagePathRead "scores" (nestedMapPath (.local "outer") (.local "inner"))))
  ]
}

def module : Module := {
  name := "EvmTypedMapProbe"
  state := #[stateScores, stateFlags, stateRoots, stateAfter]
  entrypoints := #[
    typedMapLifecycle,
    readScore,
    writeScore,
    containsScore,
    readFlag,
    setFlag,
    containsFlag,
    readRoot,
    setRoot,
    containsRoot,
    pathAssignScore,
    nestedPathScore
  ]
}

end ProofForge.IR.Examples.EvmTypedMapProbe
