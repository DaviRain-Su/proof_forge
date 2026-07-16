/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical high-level fungible token intent with transfer fees.

Authors write business features only (`transfer_fee`). They never pick a chain
token standard. `planForTarget` / `--target` materialize the standard:

  - `solana-sbpf-asm` → Token-2022 plan (transfer_fee extension)
  - `evm` → **rejected** until ERC-20 fee materialization exists (honest diagnostic)

Compile:

  lake env proof-forge build --target solana-sbpf-asm --token --root . \
    -o build/shared-fee-token/FeeToken.token-plan.json \
    Examples/Product/FeeToken.lean
-/
import ProofForge.Contract.Token

namespace Examples.Product.FeeToken

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

end Examples.Product.FeeToken
