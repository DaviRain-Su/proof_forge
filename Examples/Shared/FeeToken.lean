/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical high-level fungible token intent with transfer fees.

This file describes a product-level token intent once. It does not name the
Solana Token-2022 program in the authored contract; the Solana target selects
Token-2022 because the shared intent asks for transfer fees.

Compile by changing only `--target`:

  lake env proof-forge build --target solana-sbpf-asm --token --root . \
    -o build/shared-fee-token/FeeToken.solana-token-2022-plan.json \
    Examples/Shared/FeeToken.lean

The EVM target currently lowers this intent to an ERC-20-compatible artifact
without a transfer-fee extension because ERC-20 fee semantics are not yet part
of ProofForge's EVM TokenSpec lowering.
-/
import ProofForge.Contract.Token

namespace Examples.Shared.FeeToken

open ProofForge.Contract.Token

def id : String :=
  "FeeToken"

def spec : TokenSpec := {
  name := "Fee Token"
  symbol := "FEE"
  decimals := 6
  initialSupply? := some 1000000
  features := #[.mintable, .transferFee]
}

end Examples.Shared.FeeToken
