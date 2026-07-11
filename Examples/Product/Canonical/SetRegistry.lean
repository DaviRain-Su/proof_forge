import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.SetRegistry

def registry : SurfaceSetDecl := { id := 0, elementType := .u64, capacity := 100 }

def contract : SurfaceContract := {
  name := "SetRegistry", structs := #[], state := registry.expand, events := #[], errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call, params := #[], retType := .unit,
      body := #[.stateWrite registry.cardinalityName (.literal (.u64Lit 0))] },
    { name := "insert", kind := .function, mutability := .call,
      params := #[{ name := "key", type := .u64 }], retType := .unit,
      body := registry.insertStmts (.local "key") },
    { name := "remove", kind := .function, mutability := .call,
      params := #[{ name := "key", type := .u64 }], retType := .unit,
      body := registry.removeStmts (.local "key") },
    { name := "contains", kind := .function, mutability := .view,
      params := #[{ name := "key", type := .u64 }], retType := .bool,
      body := #[.returnExpr (registry.containsExpr (.local "key"))] }
  ], constructorParams := #[], constructorBindings := #[]
}

end Examples.Product.Canonical.SetRegistry
