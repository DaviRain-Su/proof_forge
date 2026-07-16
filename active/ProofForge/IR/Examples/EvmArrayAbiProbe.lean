import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmArrayAbiProbe

open ProofForge.IR

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def echoArray : Entrypoint := {
  name := "echo_array"
  selector? := some "c3b0874d"
  params := #[("xs", .array .u64)]
  returns := .array .u64
  body := #[
    .return (.local "xs")
  ]
}

def sumArray : Entrypoint := {
  name := "sum_array"
  selector? := some "bc2d8fd1"
  params := #[("xs", .array .u64)]
  returns := .u64
  body := #[
    .assertEq (.memoryArrayLength (.local "xs")) (u64 3) "expected length 3",
    .return (.add
      (.add
        (.memoryArrayGet (.local "xs") (u64 0))
        (.memoryArrayGet (.local "xs") (u64 1)))
      (.memoryArrayGet (.local "xs") (u64 2)))
  ]
}

def module : Module := {
  name := "EvmArrayAbiProbe"
  state := #[]
  entrypoints := #[echoArray, sumArray]
}

end ProofForge.IR.Examples.EvmArrayAbiProbe
