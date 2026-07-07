/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical high-level fungible token intent shared across token targets.

This file intentionally does not mention ERC-20, SPL Token, Token-2022, or
NEP-141. It describes the product-level token intent once; target routing
chooses the concrete chain artifact.

Compile the same token intent by changing only `--target`:

  lake env proof-forge build --target evm --token --root . \
    -o build/shared-fungible-token/FungibleToken.erc20.bin \
    --yul-output build/shared-fungible-token/FungibleToken.erc20.yul \
    --artifact-output build/shared-fungible-token/FungibleToken.evm-artifact.json \
    Examples/Shared/FungibleToken.lean

  lake env proof-forge build --target solana-sbpf-asm --token --root . \
    -o build/shared-fungible-token/FungibleToken.solana-token-plan.json \
    Examples/Shared/FungibleToken.lean

The EVM target currently lowers this intent to an ERC-20-compatible contract.
The Solana target lowers it to an SPL Token mint/account plan, or Token-2022
when features require extensions.
-/
import ProofForge.Contract.Token

namespace Examples.Shared.FungibleToken

open ProofForge.Contract.Token

def id : String :=
  "FungibleToken"

def spec : TokenSpec := {
  name := "Proof Token"
  symbol := "PRF"
  decimals := 9
  initialSupply? := some 1000000
  features := #[.mintable, .burnable]
}

end Examples.Shared.FungibleToken
