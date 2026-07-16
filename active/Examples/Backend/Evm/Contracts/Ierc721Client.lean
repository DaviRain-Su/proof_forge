/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — EVM IERC721 external client (fixture)

Calls an **already-deployed** ERC-721 via CALL + standard selectors.
Not Layer C (`Stdlib.ERC721` / ERC721Probe — those *are* the NFT).

Product index: `docs/protocols-layer.md` · `ProofForge.Protocols.Evm.IERC721`.
-/
import ProofForge.Contract.Builder
import ProofForge.Protocols.Evm.IERC721

namespace Examples.Backend.Evm.Contracts.Ierc721Client

open ProofForge.Contract.Builder
open ProofForge.Protocols.Evm.IERC721

def spec : ProofForge.Contract.ContractSpec :=
  build "Ierc721Client" do
    scalarState "last_token" .u64
    let nft ← declareNft "nft.peer"

    entrySelectorWithParams "moveToken" "0d1dfd76"
        #[("from", .u64), ("to", .u64), ("tokenId", .u64)] .unit do
      letBind "_ok" .u64 (transferFrom nft (localVar "from") (localVar "to") (localVar "tokenId"))
      effect (storageScalarWrite "last_token" (localVar "tokenId"))

    entrySelectorWithParams "safeMoveToken" "60218c1e"
        #[("from", .u64), ("to", .u64), ("tokenId", .u64)] .unit do
      letBind "_ok" .u64 (safeTransferFrom nft (localVar "from") (localVar "to") (localVar "tokenId"))
      effect (storageScalarWrite "last_token" (localVar "tokenId"))

    entrySelectorWithParams "readOwner" "ed953f2b"
        #[("tokenId", .u64)] .u64 do
      ret (ownerOf nft (localVar "tokenId"))

    entrySelectorWithParams "readBalance" "9f700267"
        #[("account", .u64)] .u64 do
      ret (balanceOf nft (localVar "account"))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Evm.Contracts.Ierc721Client
