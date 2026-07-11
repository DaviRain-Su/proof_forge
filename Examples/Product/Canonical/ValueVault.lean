import ProofForge.Frontend.Surface

/-! # Canonical ValueVault (Surface v2)

Surface-authored ValueVault contract — same business behavior as the
Legacy `Examples/Product/ValueVault.lean` but using the independent
`Frontend.Surface` AST. Test input only; the Legacy product baseline
remains the public source until cutover.
-/

open ProofForge.Frontend.Surface

def contract : SurfaceContract := {
  name := "ValueVault"
  structs := #[]
  state := #[
    { name := "totalDeposits", kind := .scalar .u64 },
    { name := "releasedAmount", kind := .scalar .u64 }
  ]
  events := #[
    { name := "Deposited", fields := #[
      { name := "amount", type := .u64, indexed := false }
    ] },
    { name := "Released", fields := #[
      { name := "amount", type := .u64, indexed := false }
    ] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "totalDeposits" (.literal (.u64Lit 0)),
        .stateWrite "releasedAmount" (.literal (.u64Lit 0))
      ]
    },
    { name := "deposit", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "totalDeposits"
          (.arith .add true
            (.stateRead "totalDeposits")
            (.contextRead .value)),
        .emit "Deposited" #[.contextRead .value]
      ]
    },
    { name := "release", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "releasedAmount"
          (.arith .add true
            (.stateRead "releasedAmount")
            (.literal (.u64Lit 1))),
        .emit "Released" #[.literal (.u64Lit 1)]
      ]
    },
    { name := "getTotalDeposits", kind := .function, mutability := .view,
      params := #[], retType := .u64,
      body := #[
        .returnExpr (.stateRead "totalDeposits")
      ]
    }
  ]
  constructorParams := #[]
  constructorBindings := #[]
  intents := #[]
}