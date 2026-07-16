import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.GenericEntrypointProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def answer : Entrypoint := {
  name := "answer"
  returns := .u64
  body := #[
    .letBind "base" .u64 (.literal (.u64 40)),
    .return (.add (.local "base") (.literal (.u64 2)))
  ]
}

def module : Module := {
  name := "GenericEntrypointProbe"
  state := #[stateMarker]
  entrypoints := #[answer]
}

end ProofForge.IR.Examples.GenericEntrypointProbe
