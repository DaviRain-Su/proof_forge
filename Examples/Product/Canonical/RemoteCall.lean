import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.RemoteCall

private def peer : SurfaceExpr :=
  .literal (.addressLit "0x000000000000000000000000000000000000dEaD")

private def method : SurfaceExpr := .literal (.stringLit "remote_call")

def contract : SurfaceContract := {
  name := "RemoteCall"
  structs := #[]
  state := #[{ name := "marker", kind := .scalar .u64 }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c", params := #[], retType := .unit,
      body := #[.stateWrite "marker" (.literal (.u64Lit 0))] },
    { name := "call_remote", kind := .function, mutability := .call,
      selector? := some "1f44d2ce", params := #[], retType := .u64,
      body := #[.returnExpr (.crosscall .invoke peer method #[] .u64)] },
    { name := "call_with_args", kind := .function, mutability := .call,
      selector? := some "f1ae0699", params := #[], retType := .u64,
      body := #[.returnExpr (.crosscall .invoke peer method
        #[.literal (.u64Lit 42), .literal (.u64Lit 7)] .u64)] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.RemoteCall
