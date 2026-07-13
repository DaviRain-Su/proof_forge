import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.CallerAccountIdMapProbe

open ProofForge.IR

/-! A string-keyed map keyed by the RAW predecessor account id (Phase 3 NEP-141
    interop). Proves the `__pf_ctx_account_id` host path (identity from
    `predecessor_account_id`, NOT a Borsh param and NOT sha256) plus the
    variable-length string-keyed map read/write path on the real NEAR VM. -/

def callerAccountId : Expr :=
  .effect (.contextRead .accountId)

def stateBalances : StateDecl := {
  id := "balances",
  kind := .map .string 8,
  type := .u128
}

def u128 (v : Nat) : Expr :=
  .literal (.u128 v)

/-! `map_roundtrip() -> U128`: write u128(100) at the caller's AccountId string
    key, read it back, return. -/

def mapRoundTrip : Entrypoint := {
  name := "map_roundtrip",
  returns := .u128,
  body := #[
    .effect (.storageMapSet "balances" callerAccountId (u128 100)),
    .return (.effect (.storageMapGet "balances" callerAccountId))
  ]
}

def module : Module := {
  name := "CallerAccountIdMapProbe",
  state := #[stateBalances],
  entrypoints := #[mapRoundTrip]
}

end ProofForge.IR.Examples.CallerAccountIdMapProbe