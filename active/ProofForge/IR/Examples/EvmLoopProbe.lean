import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmLoopProbe

open ProofForge.IR

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def countToThree : Entrypoint := {
  name := "count_to_three"
  selector? := some "c4eff2de"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "count" (.literal (.u64 0))),
    .boundedFor "_i" 0 3 #[
      .letBind "n" .u64 (.effect (.storageScalarRead "count")),
      .effect (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1))))
    ],
    .return (.effect (.storageScalarRead "count"))
  ]
}

def chooseWithEarlyReturn : Entrypoint := {
  name := "choose_with_early_return"
  selector? := some "d9b42937"
  params := #[("flag", .bool)]
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "count" (.literal (.u64 0))),
    .ifElse (.local "flag") #[
      .return (.literal (.u64 11))
    ] #[
      .effect (.storageScalarWrite "count" (.literal (.u64 22)))
    ],
    .effect (.storageScalarWrite "count" (.literal (.u64 99))),
    .return (.effect (.storageScalarRead "count"))
  ]
}

def loopEarlyReturn : Entrypoint := {
  name := "loop_early_return"
  selector? := some "d11c9505"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "count" (.literal (.u64 100))),
    .boundedFor "_i" 0 3 #[
      .return (.cast (.local "_i") .u64)
    ]
  ]
}

def module : Module := {
  name := "EvmLoopProbe"
  state := #[stateCount]
  entrypoints := #[countToThree, chooseWithEarlyReturn, loopEarlyReturn]
}

end ProofForge.IR.Examples.EvmLoopProbe
