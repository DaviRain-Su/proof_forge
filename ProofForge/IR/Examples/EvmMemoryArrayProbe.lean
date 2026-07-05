import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmMemoryArrayProbe

open ProofForge.IR

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def memoryLifecycle : Entrypoint := {
  name := "memory_lifecycle"
  selector? := some "351b36c7"
  returns := .u64
  body := #[
    .letBind "arr" (.array .u64) (.memoryArrayNew .u64 (u64 3)),
    .effect (.memoryArraySet (.local "arr") (u64 0) (u64 7)),
    .effect (.memoryArraySet (.local "arr") (u64 1) (u64 11)),
    .effect (.memoryArraySet (.local "arr") (u64 2) (u64 13)),
    .return (.add
      (.add
        (.memoryArrayGet (.local "arr") (u64 0))
        (.memoryArrayGet (.local "arr") (u64 1)))
      (.memoryArrayGet (.local "arr") (u64 2)))
  ]
}

def memoryLength : Entrypoint := {
  name := "memory_length"
  selector? := some "f748ed48"
  returns := .u64
  body := #[
    .letBind "arr" (.array .u64) (.memoryArrayNew .u64 (u64 5)),
    .return (.memoryArrayLength (.local "arr"))
  ]
}

def getAndSum : Entrypoint := {
  name := "get_and_sum"
  selector? := some "c46232c0"
  params := #[("a", .u64), ("b", .u64), ("c", .u64)]
  returns := .u64
  body := #[
    .letBind "arr" (.array .u64) (.memoryArrayNew .u64 (u64 3)),
    .effect (.memoryArraySet (.local "arr") (u64 0) (.local "a")),
    .effect (.memoryArraySet (.local "arr") (u64 1) (.local "b")),
    .effect (.memoryArraySet (.local "arr") (u64 2) (.local "c")),
    .return (.add
      (.add
        (.memoryArrayGet (.local "arr") (u64 0))
        (.memoryArrayGet (.local "arr") (u64 1)))
      (.memoryArrayGet (.local "arr") (u64 2)))
  ]
}

def module : Module := {
  name := "EvmMemoryArrayProbe"
  state := #[]
  entrypoints := #[memoryLifecycle, memoryLength, getAndSum]
}

end ProofForge.IR.Examples.EvmMemoryArrayProbe
