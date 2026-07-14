/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Target-neutral high-level non-transferable (soulbound) token intent.

Authors write `feature non_transferable` only. Chain standards are resolved by
`--target`:

  - `solana-sbpf-asm` → Token-2022 plan (non_transferable extension)
  - `evm` → **rejected** until soulbound ERC-20 materialization exists

Compile:

  lake env proof-forge build --target solana-sbpf-asm --token --root . \
    -o build/shared-soulbound-token/SoulboundToken.token-plan.json \
    Examples/Product/SoulboundToken.lean
-/
import ProofForge.Contract.Token

namespace Examples.Product.SoulboundToken

open ProofForge.Contract.Token

def id : String :=
  "SoulboundToken"

def spec : TokenSpec := {
  name := "Soulbound Token"
  symbol := "SBT"
  decimals := 0
  initialSupply? := some 1
  features := #[.mintable, .burnable, .nonTransferable]
}

end Examples.Product.SoulboundToken
