import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.HashProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def poseidonHash : Entrypoint := {
  name := "poseidon_hash"
  returns := .hash
  body := #[
    .letBind "data" .hash (.literal (.hash4 1 2 3 4)),
    .return (.hash (.local "data"))
  ]
}

def poseidonPairHash : Entrypoint := {
  name := "poseidon_pair_hash"
  returns := .hash
  body := #[
    .letBind "left" .hash (.literal (.hash4 1 2 3 4)),
    .letBind "right" .hash (.literal (.hash4 5 6 7 8)),
    .return (.hashTwoToOne (.local "left") (.local "right"))
  ]
}

def module : Module := {
  name := "HashProbe"
  state := #[stateMarker]
  entrypoints := #[poseidonHash, poseidonPairHash]
}

end ProofForge.IR.Examples.HashProbe
