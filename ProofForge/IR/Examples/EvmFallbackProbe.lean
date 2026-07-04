import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmFallbackProbe

open ProofForge.IR

/-- Fallback/receive probe: tests EntrypointKind.fallback and EntrypointKind.receive.
    Entry points:
    - increment: normal function (has selector)
    - getValue: normal query (has selector)
    - fallback: fallback entrypoint (called on unknown selector)
    - receive: receive entrypoint (called on empty calldata + ETH) -/

def stateCounter : StateDecl := {
  id := "counter"
  kind := .scalar
  type := .u64
}

def stateReceived : StateDecl := {
  id := "received"
  kind := .scalar
  type := .u64
}

def entryIncrement : Entrypoint := {
  name := "increment"
  selector? := some "d09de08a"
  params := #[]
  returns := .unit
  body := #[
    .effect (.storageScalarAssignOp "counter" .add (Expr.literal (.u64 1)))
  ]
}

def entryGetValue : Entrypoint := {
  name := "getValue"
  selector? := some "20965255"
  params := #[]
  returns := .u64
  body := #[
    .return (Expr.effect (.storageScalarRead "counter"))
  ]
}

def entryFallback : Entrypoint := {
  name := "fallback"
  kind := .fallback
  params := #[]
  returns := .unit
  body := #[
    .revert "fallback: unknown function"
  ]
}

def entryReceive : Entrypoint := {
  name := "receive"
  kind := .receive
  params := #[]
  returns := .unit
  body := #[
    .effect (.storageScalarAssignOp "received" .add (Expr.literal (.u64 1)))
  ]
}

def module : Module := {
  name := "EvmFallbackProbe"
  state := #[stateCounter, stateReceived]
  entrypoints := #[
    entryIncrement,
    entryGetValue,
    entryFallback,
    entryReceive
  ]
}

end ProofForge.IR.Examples.EvmFallbackProbe