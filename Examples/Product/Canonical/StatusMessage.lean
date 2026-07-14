import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.StatusMessage

def contract : SurfaceContract := {
  name := "StatusMessage"
  structs := #[]
  state := #[
    { name := "version", kind := .scalar .u64 },
    { name := "records", kind := .map .u64 .u64 (some 256) }
  ]
  events := #[{
    name := "StatusSet"
    fields := #[
      { name := "account", type := .u64, indexed := true },
      { name := "status", type := .u64, indexed := false }
    ]
  }]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[.stateWrite "version" (.literal (.u64Lit 1))] },
    { name := "set_status", kind := .function, mutability := .call,
      selector? := some "086562c9", params := #[{ name := "status", type := .u64 }],
      retType := .unit,
      body := #[
        .bind "account" .u64 (.cast .u64 (.contextRead .sender)),
        .mapWrite "records" (.local "account") (.local "status"),
        .emit "StatusSet" #[.local "account", .local "status"]] },
    { name := "get_status", kind := .function, mutability := .view,
      selector? := some "d415a772", params := #[{ name := "who", type := .u64 }],
      retType := .u64, body := #[.returnExpr (.mapRead "records" (.local "who"))] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.StatusMessage
