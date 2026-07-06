import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.WhileProbe

open ProofForge.IR

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def countToThree : Entrypoint := {
  name := "count_to_three"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "count" (.literal (.u64 0))),
    .whileLoop
      (.lt (.effect (.storageScalarRead "count")) (.literal (.u64 3)))
      #[
        .letBind "n" .u64 (.effect (.storageScalarRead "count")),
        .effect (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1))))
      ],
    .return (.effect (.storageScalarRead "count"))
  ]
}

def module : Module := {
  name := "WhileProbe"
  state := #[stateCount]
  entrypoints := #[countToThree]
}

end ProofForge.IR.Examples.WhileProbe