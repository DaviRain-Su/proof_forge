import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.ConditionalProbe

open ProofForge.IR

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def readCount : Expr :=
  .effect (.storageScalarRead "count")

def conditionalLifecycle : Entrypoint := {
  name := "conditional_lifecycle"
  selector? := some "f3380744"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "count" (felt 0)),
    .ifElse (.eq (felt 1) (felt 1)) #[
      .letBind "seed" .u64 (felt 4),
      .effect (.storageScalarWrite "count" (.local "seed"))
    ] #[
      .effect (.storageScalarWrite "count" (felt 99))
    ],
    .ifElse (.lt readCount (felt 2)) #[
      .effect (.storageScalarWrite "count" (felt 100))
    ] #[
      .letBind "next" .u64 (.add readCount (felt 6)),
      .effect (.storageScalarWrite "count" (.local "next"))
    ],
    .assertEq readCount (felt 10) "conditional branches update storage",
    .return readCount
  ]
}

def module : Module := {
  name := "ConditionalProbe"
  state := #[stateCount]
  entrypoints := #[conditionalLifecycle]
}

end ProofForge.IR.Examples.ConditionalProbe
