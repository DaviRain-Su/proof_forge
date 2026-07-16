/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — EVM IERC721 external client

Call an **already-deployed** ERC-721 at a peer address via portable
`crosscall.invoke` (materializes as EVM CALL).

This is **not** `Contract.Stdlib.ERC721` (Layer C: *you* are the NFT).
Selectors match the ERC-721 ABI. Receiver callbacks (`onERC721Received`) are
not synthesized here — same honesty as the stdlib `safeTransferFrom` note.
-/
import ProofForge.Contract.Source.Internal

namespace ProofForge.Protocols.Evm.IERC721

open ProofForge.Contract.Source.Internal

/-- Catalog id for docs / diagnostics. -/
def catalogId : String := "protocols.evm.ierc721"

/-- `balanceOf(address)` -/
def selectorBalanceOf : Nat := 0x70a08231
/-- `ownerOf(uint256)` -/
def selectorOwnerOf : Nat := 0x6352211e
/-- `transferFrom(address,address,uint256)` -/
def selectorTransferFrom : Nat := 0x23b872dd
/-- `safeTransferFrom(address,address,uint256)` (no data) -/
def selectorSafeTransferFrom : Nat := 0x42842e0e
/-- `approve(address,uint256)` -/
def selectorApprove : Nat := 0x095ea7b3
/-- `setApprovalForAll(address,bool)` -/
def selectorSetApprovalForAll : Nat := 0xa22cb465
/-- `getApproved(uint256)` -/
def selectorGetApproved : Nat := 0x081812fc
/-- `isApprovedForAll(address,address)` -/
def selectorIsApprovedForAll : Nat := 0xe985e9c5

/-- External NFT peer (target only; methods use fixed selectors). -/
structure Nft where
  target : ProofForge.IR.Expr
  deriving Repr

/-- Register a logical NFT peer once at module scope. -/
def declareNft (peerId : String) : ModuleM Nft := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  pure { target := peerHandle tIdx }

/-- `balanceOf(owner)`. -/
def balanceOf (nft : Nft) (owner : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorBalanceOf) #[owner]

/-- `ownerOf(tokenId)`. -/
def ownerOf (nft : Nft) (tokenId : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorOwnerOf) #[tokenId]

/-- `transferFrom(from, to, tokenId)`. -/
def transferFrom (nft : Nft) (fromAddr to tokenId : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorTransferFrom) #[fromAddr, to, tokenId]

/-- `safeTransferFrom(from, to, tokenId)` — CALL only; no onERC721Received. -/
def safeTransferFrom (nft : Nft) (fromAddr to tokenId : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorSafeTransferFrom) #[fromAddr, to, tokenId]

/-- `approve(to, tokenId)`. -/
def approve (nft : Nft) (to tokenId : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorApprove) #[to, tokenId]

/-- `setApprovalForAll(operator, approved)` — approved as 0/1 word. -/
def setApprovalForAll (nft : Nft) (operator approved : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorSetApprovalForAll) #[operator, approved]

/-- `getApproved(tokenId)`. -/
def getApproved (nft : Nft) (tokenId : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorGetApproved) #[tokenId]

/-- `isApprovedForAll(owner, operator)`. -/
def isApprovedForAll (nft : Nft) (owner operator : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall nft.target (u64 selectorIsApprovedForAll) #[owner, operator]

end ProofForge.Protocols.Evm.IERC721
