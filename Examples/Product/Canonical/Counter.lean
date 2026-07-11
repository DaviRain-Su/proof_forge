import ProofForge.Frontend.Surface

/-! # Canonical Counter (Surface v2)

Surface-authored Counter contract — same business behavior as the
Legacy `Examples/Product/Counter.lean` but using the independent
`Frontend.Surface` AST. Test input only; the Legacy product baseline
remains the public source until cutover.
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
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count" (.literal (.u64Lit 0))
      ]
    },
    { name := "increment", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count"
          (.arith .add true
            (.stateRead "count")
            (.literal (.u64Lit 1)))
      ]
    },
    { name := "get", kind := .function, mutability := .view,
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
