import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.U128MapProbe

open ProofForge.IR

/-! A hash-keyed map with a U128 value — the shape of NEP-141 `balances`
    (Map<AccountId-hash, U128>). Used to prove the two-word U128 map read/write
    path on the real NEAR VM. -/

def stateBalances : StateDecl := {
  id := "balances"
  kind := .map .hash 8
  type := .u128
}

def u128 (v : Nat) : Expr :=
  .literal (.u128 v)

def key : Expr :=
  .literal (.hash4 1001 0 0 0)

/-! Write u128(100) at a hash key (bare — U128 map write is void), read it back,
    return. A correct lowering returns `64000000000000000000000000000000`
    (= u128 100) via `__pf_return_u128`. -/
def mapRoundTrip : Entrypoint := {
  name := "map_roundtrip"
  returns := .u128
  body := #[
    .effect (.storageMapSet "balances" key (u128 100)),
    .return (.effect (.storageMapGet "balances" key))
  ]
}

def module : Module := {
  name := "U128MapProbe"
  state := #[stateBalances]
  entrypoints := #[mapRoundTrip]
}

end ProofForge.IR.Examples.U128MapProbe
