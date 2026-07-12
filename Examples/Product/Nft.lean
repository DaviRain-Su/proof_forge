/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical portable NFT intent shared across primary targets.

Authors write a single `NFTSpec` with business features only. They never
pick a chain NFT standard. `--target` materializes the standard:

  - `evm` → ERC-721
  - `solana-sbpf-asm` → Metaplex
  - `wasm-near` → NEP-171

Compile the same NFT intent by changing only `--target`:

  lake env proof-forge build --target evm --nft --root . \
    -o build/shared-nft/Nft.erc721.bin \
    Examples/Product/Nft.lean

  lake env proof-forge build --target solana-sbpf-asm --nft --root . \
    -o build/shared-nft/Nft.s \
    Examples/Product/Nft.lean

  lake env proof-forge build --target wasm-near --nft --root . \
    -o build/shared-nft/near \
    Examples/Product/Nft.lean
-/
import ProofForge.Contract.Nft

namespace Examples.Product.Nft

open ProofForge.Contract

def id : String :=
  "Nft"

def spec : NFTSpec := {
  name := "Proof NFT"
  symbol := "PNFT"
  features := #[.mintable, .transferable]
}

end Examples.Product.Nft
