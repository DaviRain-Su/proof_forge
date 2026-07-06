import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.CrosscallProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def remotePairStruct : StructDecl := {
  name := "RemotePair"
  fields := #[
    { id := "flag", type := .bool },
    { id := "small", type := .u32 }
  ]
}

def pair (flag small : Expr) : Expr :=
  .structLit "RemotePair" #[
    ("flag", flag),
    ("small", small)
  ]

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

def callRemoteValue : Entrypoint := {
  name := "call_remote_value"
  returns := .u64
  params := #[("target", .u64), ("method", .u64)]
  body := #[
    .return (.crosscallInvokeValueTyped (.local "target") (.local "method") .nativeValue #[] .u64)
  ]
}

def callRemoteStatic : Entrypoint := {
  name := "call_remote_static"
  returns := .u64
  params := #[("target", .u64), ("method", .u64)]
  body := #[
    .return (.crosscallInvokeStaticTyped (.local "target") (.local "method") #[] .u64)
  ]
}

def callRemoteDelegate : Entrypoint := {
  name := "call_remote_delegate"
  returns := .u64
  params := #[("target", .u64), ("method", .u64)]
  body := #[
    .return (.crosscallInvokeDelegateTyped (.local "target") (.local "method") #[] .u64)
  ]
}

/-- Minimal init-code hex for portable create/create2 stubs (ignored by Quint semantics). -/
def returnFortyTwoInitCodeHex : String :=
  "69602a60005260206000f3600052600a6016f3"

def deployCreate : Entrypoint := {
  name := "deploy_create"
  returns := .u64
  params := #[("value", .u64)]
  body := #[
    .return (.crosscallCreate (.local "value") returnFortyTwoInitCodeHex)
  ]
}

def deployCreate2 : Entrypoint := {
  name := "deploy_create2"
  returns := .u64
  params := #[("value", .u64), ("salt", .hash)]
  body := #[
    .return (.crosscallCreate2 (.local "value") (.local "salt") returnFortyTwoInitCodeHex)
  ]
}

def callRemotePair : Entrypoint := {
  name := "call_remote_pair"
  returns := .structType "RemotePair"
  params := #[("target", .u64), ("method", .u64)]
  body := #[
    .return (.crosscallInvokeTyped (.local "target") (.local "method") #[] (.structType "RemotePair"))
  ]
}

def callRemotePairArg : Entrypoint := {
  name := "call_remote_pair_arg"
  returns := .bool
  params := #[("target", .u64), ("method", .u64), ("flag", .bool), ("small", .u32)]
  body := #[
    .letBind "pair" (.structType "RemotePair") (pair (.local "flag") (.local "small")),
    .return (.crosscallInvokeTyped (.local "target") (.local "method") #[.local "pair"] .bool)
  ]
}

def callRemoteArray : Entrypoint := {
  name := "call_remote_array"
  returns := .fixedArray .u64 2
  params := #[("target", .u64), ("method", .u64)]
  body := #[
    .return (.crosscallInvokeTyped (.local "target") (.local "method") #[] (.fixedArray .u64 2))
  ]
}

def callRemoteArrayArg : Entrypoint := {
  name := "call_remote_array_arg"
  returns := .u64
  params := #[("target", .u64), ("method", .u64), ("x", .u64), ("y", .u64)]
  body := #[
    .letBind "values" (.fixedArray .u64 2) (.arrayLit .u64 #[.local "x", .local "y"]),
    .return (.crosscallInvokeTyped (.local "target") (.local "method") #[.local "values"] .u64)
  ]
}

def module : Module := {
  name := "CrosscallProbe"
  structs := #[remotePairStruct]
  state := #[stateMarker]
  entrypoints := #[
    callRemote, callWithArgs, callRemoteBool, callRemoteU32, callRemoteHash,
    callRemoteValue, callRemoteStatic, callRemoteDelegate,
    deployCreate, deployCreate2,
    callRemotePair, callRemotePairArg, callRemoteArray, callRemoteArrayArg
  ]
}

def psyModule : Module := {
  name := "CrosscallProbe"
  state := #[stateMarker]
  entrypoints := #[callRemote]
}

end ProofForge.IR.Examples.CrosscallProbe
