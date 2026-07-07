/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical high-level non-transferable token intent.

This file describes a product-level soulbound token once. It does not name the
Solana Token-2022 program in the authored contract; the Solana target selects
Token-2022 because the shared intent asks for non-transferability.

Compile by changing only `--target`:

  lake env proof-forge build --target solana-sbpf-asm --token --root . \
    -o build/shared-soulbound-token/SoulboundToken.solana-token-2022-plan.json \
    Examples/Shared/SoulboundToken.lean

EVM token lowering currently emits ERC-20-compatible artifacts for the common
fungible-token subset. Non-transferable semantics are target-gated below this
shared intent layer and are currently validated through the Solana Token-2022
plan.
-/
import ProofForge.Contract.Token

namespace Examples.Shared.SoulboundToken

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

end Examples.Shared.SoulboundToken
