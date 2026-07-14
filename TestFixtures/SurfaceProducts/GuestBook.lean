import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace TestFixtures.SurfaceProducts.GuestBook

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)

def contract : SurfaceContract := {
  name := "GuestBook"
  structs := #[]
  state := #[
    { name := "messageCount", kind := .scalar .u64 },
    { name := "messages", kind := .map .u64 .u64 (some 256) },
    { name := "authors", kind := .map .u64 .u64 (some 256) }
  ]
  events := #[{
    name := "MessagePosted"
    fields := #[
      { name := "index", type := .u64, indexed := true },
      { name := "author", type := .u64, indexed := true },
      { name := "code", type := .u64, indexed := false }
    ]
  }]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[.stateWrite "messageCount" (u64 0)] },
    { name := "add_message", kind := .function, mutability := .call,
      selector? := some "42133260", params := #[{ name := "code", type := .u64 }],
      retType := .unit,
      body := #[
        .bind "index" .u64 (.stateRead "messageCount"),
        .bind "author" .u64 (.cast .u64 (.contextRead .sender)),
        .mapWrite "messages" (.local "index") (.local "code"),
        .mapWrite "authors" (.local "index") (.local "author"),
        .stateWrite "messageCount" (.arith .add true (.local "index") (u64 1)),
        .emit "MessagePosted" #[.local "index", .local "author", .local "code"]] },
    { name := "get_message", kind := .function, mutability := .view,
      selector? := some "db55a57b", params := #[{ name := "index", type := .u64 }],
      retType := .u64, body := #[.returnExpr (.mapRead "messages" (.local "index"))] },
    { name := "get_author", kind := .function, mutability := .view,
      selector? := some "79ca3ff9", params := #[{ name := "index", type := .u64 }],
      retType := .u64, body := #[.returnExpr (.mapRead "authors" (.local "index"))] },
    { name := "total_messages", kind := .function, mutability := .view,
      selector? := some "3b1297ab", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "messageCount")] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end TestFixtures.SurfaceProducts.GuestBook
