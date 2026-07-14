import ProofForge.Frontend.Surface

/-! # Counter internal normalization fixture

Surface-authored Counter contract using the independent `Frontend.Surface`
AST. This is a temporary migration fixture, not an authored contract.
-/

open ProofForge.Frontend.Surface

namespace TestFixtures.SurfaceProducts.Counter

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
    { kind := .module, operation := .builtin "Counter" },
    { kind := .state, operation := .builtin "count" },
    { kind := .entrypoint, operation := .builtin "initialize" },
    { kind := .entrypoint, operation := .builtin "increment" },
    { kind := .entrypoint, operation := .builtin "get" },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar }
  ]
}

end TestFixtures.SurfaceProducts.Counter
