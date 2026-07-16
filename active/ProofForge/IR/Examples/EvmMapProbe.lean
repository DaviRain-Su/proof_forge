import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmMapProbe

open ProofForge.IR

def stateBefore : StateDecl := {
  id := "before"
  kind := .scalar
  type := .u64
}

def stateBalances : StateDecl := {
  id := "balances"
  kind := .map .u64 128
  type := .u64
}

def stateAfter : StateDecl := {
  id := "after"
  kind := .scalar
  type := .u64
}

def seedKey : Expr :=
  .literal (.u64 1001)

def pathKey : Expr :=
  .literal (.u64 2002)

def pathAssignKey : Expr :=
  .literal (.u64 3003)

def nestedOuterKey : Expr :=
  .literal (.u64 4004)

def nestedInnerKey : Expr :=
  .literal (.u64 5005)

def mapLifecycle : Entrypoint := {
  name := "map_lifecycle"
  selector? := some "3bb39394"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "before" (.literal (.u64 111))),
    .effect (.storageScalarWrite "after" (.literal (.u64 222))),
    .letBind "old0" .u64 (.effect (.storageMapInsert "balances" seedKey (.literal (.u64 11)))),
    .assertEq (.local "old0") (.literal (.u64 0)) "first insert returns default zero",
    .assertEq (.effect (.storageMapGet "balances" seedKey)) (.literal (.u64 11)) "insert writes the value",
    .letBind "old1" .u64 (.effect (.storageMapSet "balances" seedKey (.literal (.u64 55)))),
    .assertEq (.local "old1") (.literal (.u64 11)) "set returns the previous value",
    .return (.effect (.storageMapGet "balances" seedKey))
  ]
}

def getSeedBalance : Entrypoint := {
  name := "get_seed_balance"
  selector? := some "541be503"
  returns := .u64
  body := #[
    .return (.effect (.storageMapGet "balances" seedKey))
  ]
}

def readBalance : Entrypoint := {
  name := "read_balance"
  selector? := some "68eb1eef"
  params := #[("key", .u64)]
  returns := .u64
  body := #[
    .return (.effect (.storageMapGet "balances" (.local "key")))
  ]
}

def upsertBalance : Entrypoint := {
  name := "upsert_balance"
  selector? := some "e1de6ac8"
  params := #[
    ("key", .u64),
    ("value", .u64)
  ]
  returns := .u64
  body := #[
    .return (.effect (.storageMapInsert "balances" (.local "key") (.local "value")))
  ]
}

def setBalance : Entrypoint := {
  name := "set_balance"
  selector? := some "b41d1f5c"
  params := #[
    ("key", .u64),
    ("value", .u64)
  ]
  returns := .unit
  body := #[
    .effect (.storageMapSet "balances" (.local "key") (.local "value"))
  ]
}

def containsLifecycle : Entrypoint := {
  name := "contains_lifecycle"
  selector? := some "a0c7a60a"
  returns := .u64
  body := #[
    .assertEq (.effect (.storageMapContains "balances" seedKey)) (.literal (.bool false)) "fresh key is absent",
    .letBind "old0" .u64 (.effect (.storageMapInsert "balances" seedKey (.literal (.u64 0)))),
    .assertEq (.local "old0") (.literal (.u64 0)) "first zero insert returns default zero",
    .assertEq (.effect (.storageMapGet "balances" seedKey)) (.literal (.u64 0)) "zero insert writes zero value",
    .assertEq (.effect (.storageMapContains "balances" seedKey)) (.literal (.bool true)) "zero-valued inserted key is present",
    .effect (.storageMapSet "balances" seedKey (.literal (.u64 99))),
    .assertEq (.effect (.storageMapContains "balances" seedKey)) (.literal (.bool true)) "set key remains present",
    .return (.effect (.storageMapGet "balances" seedKey))
  ]
}

def containsBalance : Entrypoint := {
  name := "contains_balance"
  selector? := some "4c136189"
  params := #[("key", .u64)]
  returns := .bool
  body := #[
    .return (.effect (.storageMapContains "balances" (.local "key")))
  ]
}

def pathLifecycle : Entrypoint := {
  name := "path_lifecycle"
  selector? := some "84c21205"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "balances" #[.mapKey pathKey] (.literal (.u64 77))),
    .return (.effect (.storagePathRead "balances" #[.mapKey pathKey]))
  ]
}

def pathAssignLifecycle : Entrypoint := {
  name := "path_assign_lifecycle"
  selector? := some "bce9e77b"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "balances" #[.mapKey pathAssignKey] (.literal (.u64 11))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .add (.literal (.u64 5))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .sub (.literal (.u64 1))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .mul (.literal (.u64 2))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .div (.literal (.u64 3))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .mod (.literal (.u64 13))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .bitOr (.literal (.u64 16))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .bitAnd (.literal (.u64 31))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .bitXor (.literal (.u64 7))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .shiftLeft (.literal (.u64 2))),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathAssignKey] .shiftRight (.literal (.u64 1))),
    .return (.effect (.storagePathRead "balances" #[.mapKey pathAssignKey]))
  ]
}

def nestedPathLifecycle : Entrypoint := {
  name := "nested_path_lifecycle"
  selector? := some "13a524e0"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "balances" #[.mapKey nestedOuterKey, .mapKey nestedInnerKey] (.literal (.u64 88))),
    .assertEq
      (.effect (.storagePathRead "balances" #[.mapKey nestedOuterKey, .mapKey nestedInnerKey]))
      (.literal (.u64 88))
      "nested map path write can be read back",
    .effect (.storagePathAssignOp "balances" #[.mapKey nestedOuterKey, .mapKey nestedInnerKey] .add (.literal (.u64 7))),
    .return (.effect (.storagePathRead "balances" #[.mapKey nestedOuterKey, .mapKey nestedInnerKey]))
  ]
}

def nestedPathDynamic : Entrypoint := {
  name := "nested_path_dynamic"
  selector? := some "ce6fd7c0"
  params := #[
    ("outer", .u64),
    ("inner", .u64),
    ("value", .u64)
  ]
  returns := .u64
  body := #[
    .effect (.storagePathWrite "balances" #[.mapKey (.local "outer"), .mapKey (.local "inner")] (.local "value")),
    .return (.effect (.storagePathRead "balances" #[.mapKey (.local "outer"), .mapKey (.local "inner")]))
  ]
}

def module : Module := {
  name := "EvmMapProbe"
  state := #[stateBefore, stateBalances, stateAfter]
  entrypoints := #[
    mapLifecycle,
    getSeedBalance,
    readBalance,
    upsertBalance,
    setBalance,
    containsLifecycle,
    containsBalance,
    pathLifecycle,
    pathAssignLifecycle,
    nestedPathLifecycle,
    nestedPathDynamic
  ]
}

end ProofForge.IR.Examples.EvmMapProbe
