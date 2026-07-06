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

/-- Chains `promise_create` with `promise_then` onto a local callback entrypoint. -/
def callRemoteWithCallback : Entrypoint := {
  name := "call_remote_with_callback"
  returns := .u64
  params := #[]
  body := #[
    .return (.nearPromiseThen
      (.crosscallInvoke (.literal (.address 0)) (.literal (.address 1)) #[.literal (.u64 42)])
      (.literal (.address 2))
      #[] (.literal (.u64 0)))
  ]
}

/-- Promise callback entrypoint: decodes the first result payload as U64. -/
def handleRemote : Entrypoint := {
  name := "handle_remote"
  returns := .u64
  params := #[]
  body := #[
    .letBind "result_count" .u64 .nearPromiseResultsCount,
    .return (.nearPromiseResultU64 (.literal (.u64 0)))
  ]
}

def module : Module := {
  name := "NearCrosscallProbe"
  state := #[stateMarker]
  entrypoints := #[callRemote, callRemoteWithAmount, callRemoteWithCallback, handleRemote]
  nearCrosscallStrings := #["callee.testnet", "remote_call", "handle_remote"]
}

end ProofForge.IR.Examples.NearCrosscallProbe