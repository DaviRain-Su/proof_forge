import ProofForge.Frontend.Surface

/-! # Canonical Counter (Surface v2)

Surface-authored Counter contract using the independent `Frontend.Surface`
AST. This is the public EVM materialization source; the older sibling source is
retained only for targets whose ordered migration has not run yet.
-/

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.Counter

def contract : SurfaceContract := {
  name := "Counter"
  structs := #[]
  state := #[{ name := "count", kind := .scalar .u64 }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c",
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count" (.literal (.u64Lit 0))
      ]
    },
    { name := "increment", kind := .function, mutability := .call,
      selector? := some "d09de08a",
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count"
          (.arith .add true
            (.stateRead "count")
            (.literal (.u64Lit 1)))
      ]
    },
    { name := "get", kind := .function, mutability := .view,
      selector? := some "6d4ce63c",
      params := #[], retType := .u64,
      body := #[
        .returnExpr (.stateRead "count")
      ]
    }
  ]
  constructorParams := #[]
  constructorBindings := #[]
  intents := #[
    { kind := .module, label := "Counter" },
    { kind := .state, label := "count" },
    { kind := .entrypoint, label := "initialize" },
    { kind := .entrypoint, label := "increment" },
    { kind := .entrypoint, label := "get" },
    { kind := .capability, label := "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, label := "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, label := "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, label := "storage.scalar", capability? := some .storageScalar }
  ]
}

end Examples.Product.Canonical.Counter
