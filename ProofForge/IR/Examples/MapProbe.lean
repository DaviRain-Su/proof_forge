import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.MapProbe

open ProofForge.IR

def stateBefore : StateDecl := {
  id := "before"
  kind := .scalar
  type := .u64
}

def stateBalances : StateDecl := {
  id := "balances"
  kind := .map .hash 128
  type := .hash
}

def stateAfter : StateDecl := {
  id := "after"
  kind := .scalar
  type := .u64
}

def seedKey : Expr :=
  .literal (.hash4 1001 0 0 0)

def initialValue : Expr :=
  .literal (.hash4 11 22 33 44)

def updatedValue : Expr :=
  .literal (.hash4 55 66 77 88)

def pathKey : Expr :=
  .literal (.hash4 2002 0 0 0)

def pathValue : Expr :=
  .literal (.hash4 77 88 99 111)

def nestedOuterKey : Expr :=
  .literal (.hash4 4004 0 0 0)

def nestedInnerKey : Expr :=
  .literal (.hash4 5005 0 0 0)

def nestedPathValue : Expr :=
  .literal (.hash4 88 99 111 112)

def pathAssignKey : Expr :=
  .literal (.u64 3003)

def zeroHash : Expr :=
  .literal (.hash4 0 0 0 0)

def setReturnKey : Expr :=
  .literal (.hash4 3003 0 0 0)

def setReturnInitialValue : Expr :=
  .literal (.hash4 31 32 33 34)

def setReturnUpdatedValue : Expr :=
  .literal (.hash4 41 42 43 44)

def insertReturnKey : Expr :=
  .literal (.hash4 4004 0 0 0)

def insertReturnFirstValue : Expr :=
  .literal (.hash4 1 2 3 4)

def insertReturnSecondValue : Expr :=
  .literal (.hash4 5 6 7 8)

def insertReturnThirdValue : Expr :=
  .literal (.hash4 9 10 11 12)

def mapLifecycle : Entrypoint := {
  name := "map_lifecycle"
  returns := .hash
  body := #[
    .letBind "key" .hash seedKey,
    .letBind "value0" .hash initialValue,
    .letBind "value1" .hash updatedValue,
    .effect (.storageScalarWrite "before" (.literal (.u64 111))),
    .effect (.storageScalarWrite "after" (.literal (.u64 222))),
    .letBind "present0" .bool (.effect (.storageMapContains "balances" (.local "key"))),
    .letBind "old0" .hash (.effect (.storageMapInsert "balances" (.local "key") (.local "value0"))),
    .letBind "present1" .bool (.effect (.storageMapContains "balances" (.local "key"))),
    .effect (.storageMapSet "balances" (.local "key") (.local "value1")),
    .return (.effect (.storageMapGet "balances" (.local "key")))
  ]
}

def pathLifecycle : Entrypoint := {
  name := "path_lifecycle"
  returns := .hash
  body := #[
    .letBind "key" .hash pathKey,
    .letBind "value" .hash pathValue,
    .effect (.storagePathWrite "balances" #[.mapKey (.local "key")] (.local "value")),
    .return (.effect (.storagePathRead "balances" #[.mapKey (.local "key")]))
  ]
}

def nestedPathLifecycle : Entrypoint := {
  name := "nested_path_lifecycle"
  returns := .hash
  body := #[
    .effect (.storagePathWrite "balances"
      #[.mapKey nestedOuterKey, .mapKey nestedInnerKey] nestedPathValue),
    .return (.effect (.storagePathRead "balances"
      #[.mapKey nestedOuterKey, .mapKey nestedInnerKey]))
  ]
}

def tripleOuterKey : Expr :=
  .literal (.hash4 7007 0 0 0)

def tripleMiddleKey : Expr :=
  .literal (.hash4 8008 0 0 0)

def tripleInnerKey : Expr :=
  .literal (.hash4 9009 0 0 0)

def triplePathValue : Expr :=
  .literal (.hash4 10 20 30 40)

def triplePathLifecycle : Entrypoint := {
  name := "triple_path_lifecycle"
  returns := .hash
  body := #[
    .effect (.storagePathWrite "balances"
      #[.mapKey tripleOuterKey, .mapKey tripleMiddleKey, .mapKey tripleInnerKey] triplePathValue),
    .return (.effect (.storagePathRead "balances"
      #[.mapKey tripleOuterKey, .mapKey tripleMiddleKey, .mapKey tripleInnerKey]))
  ]
}

def nestedDynamicPathLifecycle : Entrypoint := {
  name := "nested_dynamic_path_lifecycle"
  returns := .hash
  params := #[("inner", .hash)]
  body := #[
    .effect (.storagePathWrite "balances"
      #[.mapKey nestedOuterKey, .mapKey (.local "inner")] pathValue),
    .return (.effect (.storagePathRead "balances"
      #[.mapKey nestedOuterKey, .mapKey (.local "inner")]))
  ]
}

def nestedU64OuterKey : Expr :=
  .literal (.u64 4004)

def nestedU64InnerKey : Expr :=
  .literal (.u64 5005)

def nestedPathAssignLifecycle : Entrypoint := {
  name := "nested_path_assign_lifecycle"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "scores"
      #[.mapKey nestedU64OuterKey, .mapKey nestedU64InnerKey] (.literal (.u64 88))),
    .effect (.storagePathAssignOp "scores"
      #[.mapKey nestedU64OuterKey, .mapKey nestedU64InnerKey] .add (.literal (.u64 7))),
    .return (.effect (.storagePathRead "scores"
      #[.mapKey nestedU64OuterKey, .mapKey nestedU64InnerKey]))
  ]
}

def stateScores : StateDecl := {
  id := "scores"
  kind := .map .u64 8
  type := .u64
}

def pathAssignLifecycle : Entrypoint := {
  name := "path_assign_lifecycle"
  returns := .u64
  body := #[
    .effect (.storagePathWrite "scores" #[.mapKey pathAssignKey] (.literal (.u64 10))),
    .effect (.storagePathAssignOp "scores" #[.mapKey pathAssignKey] .add (.literal (.u64 5))),
    .return (.effect (.storagePathRead "scores" #[.mapKey pathAssignKey]))
  ]
}

def hashPathAssignUpdatedValue : Expr :=
  .literal (.hash4 99 88 77 66)

def hashPathAssignLifecycle : Entrypoint := {
  name := "hash_path_assign_lifecycle"
  returns := .hash
  body := #[
    .effect (.storagePathWrite "balances" #[.mapKey pathKey] pathValue),
    .effect (.storagePathAssignOp "balances" #[.mapKey pathKey] .add hashPathAssignUpdatedValue),
    .return (.effect (.storagePathRead "balances" #[.mapKey pathKey]))
  ]
}

def setReturnLifecycle : Entrypoint := {
  name := "set_return_lifecycle"
  returns := .hash
  body := #[
    .letBind "key" .hash setReturnKey,
    .letBind "value0" .hash setReturnInitialValue,
    .letBind "value1" .hash setReturnUpdatedValue,
    .letBind "old0" .hash (.effect (.storageMapSet "balances" (.local "key") (.local "value0"))),
    .assertEq (.local "old0") zeroHash "set on absent map key returns zero hash",
    .assertEq (.effect (.storageMapGet "balances" (.local "key"))) (.local "value0") "set on absent map key writes value",
    .letBind "old1" .hash (.effect (.storageMapSet "balances" (.local "key") (.local "value1"))),
    .assertEq (.local "old1") (.local "value0") "set on existing map key returns previous value",
    .assertEq (.effect (.storageMapGet "balances" (.local "key"))) (.local "value1") "set on existing map key writes new value",
    .return (.local "old1")
  ]
}

def insertReturnLifecycle : Entrypoint := {
  name := "insert_return_lifecycle"
  returns := .hash
  body := #[
    .letBind "key" .hash insertReturnKey,
    .letBind "value0" .hash insertReturnFirstValue,
    .letBind "value1" .hash insertReturnSecondValue,
    .letBind "value2" .hash insertReturnThirdValue,
    .letBind "old0" .hash (.effect (.storageMapInsert "balances" (.local "key") (.local "value0"))),
    .assertEq (.local "old0") zeroHash "first insert returns zero hash",
    .letBind "old1" .hash (.effect (.storageMapInsert "balances" (.local "key") (.local "value1"))),
    .assertEq (.local "old1") (.local "value0") "second insert returns first value",
    .letBind "old2" .hash (.effect (.storageMapInsert "balances" (.local "key") (.local "value2"))),
    .assertEq (.local "old2") (.local "value1") "third insert returns second value",
    .assertEq (.effect (.storageMapGet "balances" (.local "key"))) (.local "value2") "latest insert wins",
    .return (.local "old2")
  ]
}

def getSeedBalance : Entrypoint := {
  name := "get_seed_balance"
  returns := .hash
  body := #[
    .letBind "key" .hash seedKey,
    .return (.effect (.storageMapGet "balances" (.local "key")))
  ]
}

def hasSeedBalance : Entrypoint := {
  name := "has_seed_balance"
  returns := .bool
  body := #[
    .letBind "key" .hash seedKey,
    .return (.effect (.storageMapContains "balances" (.local "key")))
  ]
}

def upsertBalance : Entrypoint := {
  name := "upsert_balance"
  params := #[
    ("key", .hash),
    ("value", .hash)
  ]
  returns := .hash
  body := #[
    .return (.effect (.storageMapInsert "balances" (.local "key") (.local "value")))
  ]
}

def setBalance : Entrypoint := {
  name := "set_balance"
  params := #[
    ("key", .hash),
    ("value", .hash)
  ]
  returns := .unit
  body := #[
    .effect (.storageMapSet "balances" (.local "key") (.local "value"))
  ]
}

def module : Module := {
  name := "MapProbe"
  state := #[stateBefore, stateBalances, stateAfter]
  entrypoints := #[
    mapLifecycle,
    getSeedBalance,
    hasSeedBalance,
    upsertBalance,
    setBalance,
    pathLifecycle,
    setReturnLifecycle,
    insertReturnLifecycle
  ]
}

/-! EmitWat-compatible subset: hash-key Map<Hash, Hash> using only storageMapGet /
    storageMapContains / storageMapSet (as a statement). The full `module` uses
    `storageMapInsert` (return-old-value semantics) and `pathLifecycle` (struct/path
    storage), which EmitWat does not lower — those belong to the Rust-v0 borrow-heavy
    surface and are out of scope for the minimal EmitWat backend. -/

def ewGetBalance : Entrypoint := {
  name := "getBalance", params := #[("key", .hash)], returns := .hash,
  body := #[.return (.effect (.storageMapGet "balances" (.local "key")))] }

def ewHasBalance : Entrypoint := {
  name := "hasBalance", params := #[("key", .hash)], returns := .bool,
  body := #[.return (.effect (.storageMapContains "balances" (.local "key")))] }

def ewSetBalance : Entrypoint := {
  name := "setBalanceReturn", params := #[("key", .hash), ("value", .hash)], returns := .hash,
  body := #[
    .effect (.storageMapSet "balances" (.local "key") (.local "value")),
    .return (.effect (.storageMapGet "balances" (.local "key")))
  ] }

def emitWatModule : Module := {
  name := "MapProbe",
  state := #[stateBefore, stateBalances, stateAfter],
  entrypoints := #[ewGetBalance, ewHasBalance, ewSetBalance]
}

/-- Quint/MBT subset: map get/has/set with a presence guard on `getBalance` so
    absent keys fail the action, matching IR `storageMapGet` error semantics. -/
def emitQuintStorageModule : Module := {
  name := "MapProbe",
  state := #[stateBalances],
  entrypoints := #[ewGetBalance, ewHasBalance, ewSetBalance]
}

/-- Quint/MBT subset: `path_lifecycle` via single-segment `storagePath*` on map state. -/
def emitQuintPathModule : Module := {
  name := "MapProbe",
  state := #[stateBalances],
  entrypoints := #[pathLifecycle]
}

/-- Quint/MBT subset: nested consecutive `mapKey` `storagePath*` on hash map state. -/
def emitQuintNestedPathModule : Module := {
  name := "MapProbe",
  state := #[stateBalances],
  entrypoints := #[nestedPathLifecycle]
}

/-- Quint/MBT subset: three consecutive `mapKey` `storagePath*` on hash map state. -/
def emitQuintTriplePathModule : Module := {
  name := "MapProbe",
  state := #[stateBalances],
  entrypoints := #[triplePathLifecycle]
}

/-- Quint/MBT subset: literal + dynamic nested `mapKey` `storagePath*` on hash map state. -/
def emitQuintNestedDynamicPathModule : Module := {
  name := "MapProbe",
  state := #[stateBalances],
  entrypoints := #[nestedDynamicPathLifecycle]
}

/-- Quint/MBT subset: `storagePathAssignOp` on single- and nested-mapKey U64 paths. -/
def emitQuintPathAssignModule : Module := {
  name := "MapProbe",
  state := #[stateScores],
  entrypoints := #[pathAssignLifecycle, nestedPathAssignLifecycle]
}

/-- Quint/MBT subset: `storagePathAssignOp` on hash-valued map paths (replace stub). -/
def emitQuintHashPathAssignModule : Module := {
  name := "MapProbe",
  state := #[stateBalances],
  entrypoints := #[hashPathAssignLifecycle]
}

/-! EmitWat "full" subset: every MapProbe entrypoint EXCEPT `pathLifecycle` (which
    needs `storagePath*`, task #16). Exercises `storageMapInsert` + `storageMapSet`
    return-old-value semantics (setReturnLifecycle / insertReturnLifecycle / mapLifecycle). -/
def emitWatFullModule : Module := {
  name := "MapProbe",
  state := #[stateBefore, stateBalances, stateAfter],
  entrypoints := #[mapLifecycle, getSeedBalance, hasSeedBalance, upsertBalance,
                   setBalance, setReturnLifecycle, insertReturnLifecycle]
}

/-- EmitWat subset for 16d: only `pathLifecycle` (storagePathRead/Write with a single
    mapKey segment). -/
def emitWatPathModule : Module := {
  name := "MapProbe",
  state := #[stateBalances],
  entrypoints := #[pathLifecycle]
}


end ProofForge.IR.Examples.MapProbe
