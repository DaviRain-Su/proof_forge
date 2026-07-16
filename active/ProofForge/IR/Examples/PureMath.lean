import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.PureMath

open ProofForge.IR

def plus : Entrypoint := {
  name := "plus"
  params := #[("a", .u64), ("b", .u64)]
  returns := .u64
  body := #[ .return (.add (.local "a") (.local "b")) ]
}

def max : Entrypoint := {
  name := "max"
  params := #[("a", .u64), ("b", .u64)]
  returns := .u64
  body := #[
    .ifElse (.gt (.local "a") (.local "b"))
      #[ .return (.local "a") ]
      #[ .return (.local "b") ]
  ]
}

def sumFirst10 : Entrypoint := {
  name := "sumFirst10"
  params := #[]
  returns := .u64
  body := #[
    .letBind "total" .u64 (.literal (.u64 0)),
    .boundedFor "i" 0 10 #[
      .assign (.local "total") (.add (.local "total") (.local "i"))
    ],
    .return (.local "total")
  ]
}

def isEven : Entrypoint := {
  name := "isEven"
  params := #[("n", .u64)]
  returns := .bool
  body := #[ .return (.eq (.mod (.local "n") (.literal (.u64 2))) (.literal (.u64 0))) ]
}

def module : Module := {
  name := "PureMath"
  state := #[]
  entrypoints := #[plus, max, sumFirst10, isEven]
}

end ProofForge.IR.Examples.PureMath
