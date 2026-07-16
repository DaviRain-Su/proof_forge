import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.ArithmeticProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def arithmeticMix : Entrypoint := {
  name := "arithmetic_mix"
  returns := .u64
  body := #[
    .letBind "a" .u64 (felt 9),
    .letBind "b" .u64 (felt 4),
    .letBind "factor" .u64 (felt 3),
    .letBind "delta" .u64 (.sub (.local "a") (.local "b")),
    .letBind "product" .u64 (.mul (.local "delta") (.local "factor")),
    .letBind "nested" .u64 (.mul
      (.add (.local "delta") (felt 1))
      (.sub (.local "product") (felt 5))),
    .assertEq (.local "delta") (felt 5) "subtraction lowers to Psy",
    .assertEq (.local "product") (felt 15) "multiplication lowers to Psy",
    .assertEq (.local "nested") (felt 60) "nested arithmetic preserves precedence",
    .return (.local "nested")
  ]
}

def module : Module := {
  name := "ArithmeticProbe"
  state := #[stateMarker]
  entrypoints := #[arithmeticMix]
}

end ProofForge.IR.Examples.ArithmeticProbe
