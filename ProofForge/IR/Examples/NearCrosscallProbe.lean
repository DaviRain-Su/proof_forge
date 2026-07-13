import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.NearCrosscallProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

/-- Portable product path: `crosscall.invoke` only. Account/method names are
compile-time strings referenced by address-literal indices into
`nearCrosscallStrings`. Backend materializes as `promise_create` — authors do
not write Promise constructors. -/
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

/-- NEAR host-extension only (D-050 Slice 3): chains `promise_then` onto a
local callback. Not portable product authoring — fixture / advanced NEAR path. -/
def callRemoteWithCallback : Entrypoint := {
  name := "call_remote_with_callback"
  returns := .u64
  params := #[]
  body := #[
    .return (.nearPromiseThen
      (.crosscallInvoke (.literal (.address 0)) (.literal (.address 1)) #[.literal (.u64 42)])
      (.literal (.address 2))
      #[] (.literal (.u64 0)) #[])
  ]
}

/-- NEAR host-extension only: callback entrypoint that decodes promise results. -/
def handleRemote : Entrypoint := {
  name := "handle_remote"
  returns := .u64
  params := #[]
  body := #[
    .letBind "result_count" .u64 .nearPromiseResultsCount,
    .return (.nearPromiseResultU64 (.literal (.u64 0)))
  ]
}

/-- Full fixture including Promise-chain constructors (host-extension surface). -/
def module : Module := {
  name := "NearCrosscallProbe"
  state := #[stateMarker]
  entrypoints := #[callRemote, callRemoteWithAmount, callRemoteWithCallback, handleRemote]
  nearCrosscallStrings := #["callee.testnet", "remote_call", "handle_remote"]
}

/-- Portable NEAR crosscall subset: only `crosscall.invoke` + string pool.
No `nearPromiseThen` / result constructors — those stay host-extension fixtures. -/
def portableModule : Module := {
  name := "NearCrosscallPortable"
  state := #[stateMarker]
  entrypoints := #[callRemote, callRemoteWithAmount]
  nearCrosscallStrings := #["callee.testnet", "remote_call"]
}

/-- Host-extension Promise chaining only (then + callback result decode). -/
def promiseExtensionModule : Module := {
  name := "NearPromiseExtension"
  state := #[stateMarker]
  entrypoints := #[callRemoteWithCallback, handleRemote]
  nearCrosscallStrings := #["callee.testnet", "remote_call", "handle_remote"]
}

end ProofForge.IR.Examples.NearCrosscallProbe
