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

def module : Module := {
  name := "CrosscallProbe"
  state := #[stateMarker]
  entrypoints := #[callRemote, callWithArgs]
}

end ProofForge.IR.Examples.CrosscallProbe
