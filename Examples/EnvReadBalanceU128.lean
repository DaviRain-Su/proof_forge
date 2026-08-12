import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E2 follow-on: full-width native balance (UInt128).
-- Requires pf.assets@1.2.0. NEAR materializes host account_balance u128 with
-- no hi64 trap. Other targets fail closed at Plan (UInt64 balanceOfSelf remains).
-- Not imported by Examples.lean (NEAR runtime fixture).
program EnvReadBalanceU128 where
  requires extension pf.assets version "1.2.0"
    digest "sha256:48a7b7b49a5dae57c503dbdb72257882801420a74239ec4874c15f566ae85945"

  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  view nativeBalanceU128() : UInt128 do
    return pf.assets.native.balanceOfSelfU128()

  view get() : UInt64 do
    return pad

end Examples
