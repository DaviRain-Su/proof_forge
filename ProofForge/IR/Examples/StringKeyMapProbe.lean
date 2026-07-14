import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.StringKeyMapProbe

open ProofForge.IR

/-! A string-keyed map with a U128 value — the shape of NEP-141 `balances` keyed
    by raw AccountId string (Phase 3 NEAR interop). Used to prove the
    variable-length string-keyed map read/write path on the real NEAR VM:
    storage key = prefix ++ account-id bytes, with a RUNTIME key length
    (`pl + kl`). This mirrors the hash-keyed `U128MapProbe` but exercises the
    `__pf_map_buildkey_string` / `__pf_map_read_string_u128` /
    `__pf_map_write_string_u128` helpers instead of the fixed-32-byte hash path. -/

def stateBalances : StateDecl := {
  id := "balances"
  kind := .map .string 8
  type := .u128
}

def u128 (v : Nat) : Expr :=
  .literal (.u128 v)

/-! `map_roundtrip(key : String) -> U128`: write u128(100) at the AccountId
    string key, read it back, return. The key is a Borsh string parameter
    (4-byte LE length prefix + UTF-8 payload), decoded by `Params` into a
    `(ptr, len)` pair. A correct lowering returns
    `64000000000000000000000000000000` (= u128 100) via `__pf_return_u128`. -/

def mapRoundTrip : Entrypoint := {
  name := "map_roundtrip"
  params := #[("key", .string)]
  returns := .u128
  body := #[
    .effect (.storageMapSet "balances" (.local "key") (u128 100)),
    .return (.effect (.storageMapGet "balances" (.local "key")))
  ]
}

def module : Module := {
  name := "StringKeyMapProbe"
  state := #[stateBalances]
  entrypoints := #[mapRoundTrip]
}

end ProofForge.IR.Examples.StringKeyMapProbe