import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.ArrayProbe

open ProofForge.IR

def stateValues : StateDecl := {
  id := "values"
  kind := .array 3
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def ix (value : Nat) : Expr :=
  .literal (.u64 value)

def sumLiteral : Entrypoint := {
  name := "sum_literal"
  returns := .u64
  body := #[
    .letBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[felt 10, felt 20, felt 30]),
    .return (.add
      (.add
        (.arrayGet (.local "xs") (ix 0))
        (.arrayGet (.local "xs") (ix 1)))
      (.arrayGet (.local "xs") (ix 2)))
  ]
}

def releaseThenSum : Entrypoint := {
  name := "release_then_sum"
  returns := .u64
  body := #[
    .letBind "tmp" (.fixedArray .u64 3) (.arrayLit .u64 #[felt 1, felt 2, felt 3]),
    .release "tmp",
    .letBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[felt 10, felt 20, felt 30]),
    .return (.add
      (.add
        (.arrayGet (.local "xs") (ix 0))
        (.arrayGet (.local "xs") (ix 1)))
      (.arrayGet (.local "xs") (ix 2)))
  ]
}

def storageLifecycle : Entrypoint := {
  name := "storage_lifecycle"
  returns := .u64
  body := #[
    .effect (.storageArrayWrite "values" (ix 0) (felt 7)),
    .effect (.storageArrayWrite "values" (ix 1) (felt 11)),
    .effect (.storageArrayWrite "values" (ix 2) (felt 13)),
    .return (.add
      (.add
        (.effect (.storageArrayRead "values" (ix 0)))
        (.effect (.storageArrayRead "values" (ix 1))))
      (.effect (.storageArrayRead "values" (ix 2))))
  ]
}

def arrayPredicates : Entrypoint := {
  name := "array_predicates"
  returns := .u64
  body := #[
    .letBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[felt 1, felt 2, felt 3]),
    .letBind "ys" (.fixedArray .u64 3) (.arrayLit .u64 #[felt 1, felt 2, felt 3]),
    .letBind "zs" (.fixedArray .u64 3) (.arrayLit .u64 #[felt 1, felt 2, felt 4]),
    .assertEq (.local "xs") (.local "ys") "fixed array assert_eq compares elements",
    .assert (.eq (.local "xs") (.local "ys")) "fixed array equality compares elements",
    .assert (.ne (.local "xs") (.local "zs")) "fixed array inequality compares elements",
    .return (felt 1)
  ]
}

def emitWatStorageModule : Module := {
  name := "ArrayProbe",
  state := #[stateValues],
  entrypoints := #[storageLifecycle]
}

/-- EmitWat-compatible subset for 16b-1: only `sumLiteral` (arrayLit + arrayGet),
    no storage or array-equality. -/
def emitWatSumModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[sumLiteral]
}
/-- Allocator-strategy variants of the sumLiteral subset. -/
def emitWatSumResetModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[sumLiteral],
  allocator := ProofForge.IR.AllocatorConfig.bumpReset
}
def emitWatSumExternalModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[sumLiteral],
  allocator := ProofForge.IR.AllocatorConfig.hostBump
}
/-- Direct-WAT wasm-internal allocator: allocator code is emitted into the WAT
    module and returns wasm linear-memory offsets. -/
def emitWatSumMinimalMallocModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[sumLiteral],
  allocator := ProofForge.IR.AllocatorConfig.minimalMalloc
}
/-- NEAR deployment allocator profile: conceptually matches near-sdk's wasm
    allocator placement model and lowers to the direct-WAT internal allocator. -/
def emitWatSumNearAllocatorModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[sumLiteral],
  allocator := ProofForge.IR.AllocatorConfig.nearWeeModel
}
def emitWatReleaseMinimalMallocModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[releaseThenSum],
  allocator := ProofForge.IR.AllocatorConfig.minimalMalloc
}
/-- A reuse-capable strategy: same lowering surface as `external` (`pf_alloc` /
    `pf_dealloc` imports). The imported allocator must return offsets in wasm
    linear memory. The offline host currently simulates this with bump allocation;
    a true jemalloc path requires jemalloc compiled/linkable as wasm. Not
    chain-deployable on NEAR, which exports neither import. -/
def emitWatSumJemallocModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[sumLiteral],
  allocator := ProofForge.IR.AllocatorConfig.hostJemallocShape
}
def emitWatReleaseExternalModule : Module := {
  name := "ArrayProbe",
  state := #[],
  entrypoints := #[releaseThenSum],
  allocator := ProofForge.IR.AllocatorConfig.hostJemallocShape
}


def module : Module := {
  name := "ArrayProbe"
  state := #[stateValues]
  entrypoints := #[sumLiteral, storageLifecycle, arrayPredicates]
}

end ProofForge.IR.Examples.ArrayProbe
