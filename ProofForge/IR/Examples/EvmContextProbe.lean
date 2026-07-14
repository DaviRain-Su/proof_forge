import ProofForge.IR.Examples.ContextProbe

namespace ProofForge.IR.Examples.EvmContextProbe

open ProofForge.IR

def nativeValue : Entrypoint := {
  name := "native_value"
  selector? := some "f0eba40f"
  returns := .u64
  body := #[
    .return .nativeValue
  ]
}

def contextExtras : Entrypoint := {
  name := "context_extras"
  selector? := some "d9b80589"
  returns := .fixedArray .u64 3
  body := #[
    .return <| .arrayLit .u64 #[
      .effect (.contextRead .timestamp),
      .effect (.contextRead .chainId),
      .effect (.contextRead .gasLeft)
    ]
  ]
}

def contextHashes : Entrypoint := {
  name := "context_hashes"
  selector? := some "b59b9225"
  returns := .fixedArray .hash 1
  body := #[
    .return <| .arrayLit .hash #[
      .effect (.contextRead .signer)
    ]
  ]
}

def module : Module := {
  name := "ContextProbe"
  state := #[ProofForge.IR.Examples.ContextProbe.stateMarker]
  entrypoints := #[
    ProofForge.IR.Examples.ContextProbe.sumContext,
    nativeValue,
    contextExtras,
    contextHashes
  ]
}

end ProofForge.IR.Examples.EvmContextProbe
