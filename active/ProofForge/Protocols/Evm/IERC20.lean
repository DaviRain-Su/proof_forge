/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — EVM IERC20 external client

Call an **already-deployed** ERC-20 at a peer address via portable
`crosscall.invoke` (materializes as EVM CALL).

This is **not** `Contract.Stdlib.ERC20` (Layer C: *you* are the token).
Selectors match the ERC-20 ABI (OpenZeppelin / Ethereum wiki). EVM Yul packs
the method id as the 4-byte selector (`shl(224, selector)`).

Peer identity is logical (`declareToken "usdc.peer"`); bind with `--peer` at
deploy time where the host uses a string pool. On EVM the peer handle is a
numeric target index into the crosscall pool / plan.
-/
import ProofForge.Contract.Source.Internal

namespace ProofForge.Protocols.Evm.IERC20

open ProofForge.Contract.Source.Internal

/-- Catalog id for docs / diagnostics. -/
def catalogId : String := "protocols.evm.ierc20"

/-- `transfer(address,uint256)` -/
def selectorTransfer : Nat := 0xa9059cbb
/-- `approve(address,uint256)` -/
def selectorApprove : Nat := 0x095ea7b3
/-- `transferFrom(address,address,uint256)` -/
def selectorTransferFrom : Nat := 0x23b872dd
/-- `balanceOf(address)` -/
def selectorBalanceOf : Nat := 0x70a08231
/-- `allowance(address,address)` -/
def selectorAllowance : Nat := 0xdd62ed3e
/-- `totalSupply()` -/
def selectorTotalSupply : Nat := 0x18160ddd

/-- External token peer (target only; methods use fixed selectors). -/
structure Token where
  target : ProofForge.IR.Expr
  deriving Repr

/-- Register a logical token peer once at module scope. -/
def declareToken (peerId : String) : ModuleM Token := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  pure { target := peerHandle tIdx }

/-- `transfer(to, amount)` — returns bool word on success path. -/
def transfer (token : Token) (to amount : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorTransfer) #[to, amount]

/-- `approve(spender, amount)`. -/
def approve (token : Token) (spender amount : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorApprove) #[spender, amount]

/-- `transferFrom(from, to, amount)`. -/
def transferFrom (token : Token) (fromAddr to amount : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorTransferFrom) #[fromAddr, to, amount]

/-- `balanceOf(account)`. -/
def balanceOf (token : Token) (account : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorBalanceOf) #[account]

/-- `allowance(owner, spender)`. -/
def allowance (token : Token) (owner spender : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorAllowance) #[owner, spender]

/-- `totalSupply()`. -/
def totalSupply (token : Token) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorTotalSupply) #[]

end ProofForge.Protocols.Evm.IERC20
