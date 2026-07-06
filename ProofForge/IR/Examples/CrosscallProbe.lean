import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.CrosscallProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def callRemote : Entrypoint := {
  name := "call_remote"
  returns := .u64
  params := #[("target", .u64), ("method", .u64)]
  body := #[
    .return (.crosscallInvoke (.local "target") (.local "method") #[])
  ]
}

def callWithArgs : Entrypoint := {
  name := "call_with_args"
  returns := .u64
  params := #[("target", .u64), ("method", .u64), ("amount", .u64), ("fee", .u64)]
  body := #[
    .return (.crosscallInvoke (.local "target") (.local "method")
      #[.local "amount", .local "fee"])
  ]
}

def callRemoteBool : Entrypoint := {
  name := "call_remote_bool"
  returns := .bool
  params := #[("target", .u64), ("method", .u64), ("flag", .bool)]
  body := #[
    .return (.crosscallInvokeTyped (.local "target") (.local "method") #[.local "flag"] .bool)
  ]
}

def callRemoteU32 : Entrypoint := {
  name := "call_remote_u32"
  returns := .u32
  params := #[("target", .u64), ("method", .u64), ("x", .u32)]
  body := #[
    .return (.crosscallInvokeTyped (.local "target") (.local "method") #[.local "x"] .u32)
  ]
}

def callRemoteHash : Entrypoint := {
  name := "call_remote_hash"
  returns := .hash
  params := #[("target", .u64), ("method", .u64), ("value", .hash)]
  body := #[
    .return (.crosscallInvokeTyped (.local "target") (.local "method") #[.local "value"] .hash)
  ]
}

def module : Module := {
  name := "CrosscallProbe"
  state := #[stateMarker]
  entrypoints := #[callRemote, callWithArgs, callRemoteBool, callRemoteU32, callRemoteHash]
}

end ProofForge.IR.Examples.CrosscallProbe
