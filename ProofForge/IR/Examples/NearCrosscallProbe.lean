import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.NearCrosscallProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

/-- Account id and method name are compile-time strings referenced by address-literal
    indices into `nearCrosscallStrings`. -/
def callRemote : Entrypoint := {
  name := "call_remote"
  returns := .u64
  params := #[]
  body := #[
    .return (.crosscallInvoke (.literal (.address 0)) (.literal (.address 1)) #[])
  ]
}

def callRemoteWithAmount : Entrypoint := {
  name := "call_remote_with_amount"
  returns := .u64
  params := #[]
  body := #[
    .return (.crosscallInvoke (.literal (.address 0)) (.literal (.address 1)) #[.literal (.u64 42)])
  ]
}

def module : Module := {
  name := "NearCrosscallProbe"
  state := #[stateMarker]
  entrypoints := #[callRemote, callRemoteWithAmount]
  nearCrosscallStrings := #["callee.testnet", "remote_call"]
}

end ProofForge.IR.Examples.NearCrosscallProbe