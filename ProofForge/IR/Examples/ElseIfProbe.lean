import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.ElseIfProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def classify : Entrypoint := {
  name := "classify"
  returns := .u64
  body := #[
    .ifElse (.lt (felt 5) (felt 3)) #[
      .return (felt 0)
    ] #[
      .ifElse (.eq (felt 5) (felt 5)) #[
        .return (felt 1)
      ] #[
        .ifElse (.lt (felt 5) (felt 10)) #[
          .return (felt 2)
        ] #[
          .return (felt 3)
        ]
      ]
    ]
  ]
}

def module : Module := {
  name := "ElseIfProbe"
  state := #[stateMarker]
  entrypoints := #[classify]
}

end ProofForge.IR.Examples.ElseIfProbe