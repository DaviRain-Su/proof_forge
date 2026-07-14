/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Product protocol intent — external fungible token peer

Authors call an **already-deployed** ecosystem token without importing
`ProofForge.Protocols.*` (Layer B is materialize implementation, not the
authoring menu).

```lean
import ProofForge.Contract.Source

contract_source PayWithUsdc do
  external_token usdc "usdc.peer";

  entry pay (to : .u64) (amount : .u64) returns(.u64) do
    return externalTokenTransfer usdc to amount;
```

`--target` selects packing:
- **evm** → IERC20 selectors (pool method → selector via ProtocolMaterialize)
- **wasm-near** → NEP-141 `ft_*` + JsonEncode objects
- **solana-sbpf-asm** → portable CPI smoke (not live Tokenkeg layout; see
  ProtocolMaterialize honesty)

Bind the peer at deploy: `--peer usdc.peer=…`.
-/
import ProofForge.Contract.Source.Internal
import ProofForge.Target.ProtocolMaterialize

namespace ProofForge.Contract.Protocol

open ProofForge.Contract.Source.Internal
open ProofForge.Target.ProtocolMaterialize

/-- Logical external FT peer + method handles (string pool). -/
structure ExternalToken where
  peer : ProofForge.IR.Expr
  transferMethod : ProofForge.IR.Expr
  approveMethod : ProofForge.IR.Expr
  transferFromMethod : ProofForge.IR.Expr
  balanceOfMethod : ProofForge.IR.Expr
  totalSupplyMethod : ProofForge.IR.Expr
  deriving Repr

/-- Register a portable external token peer and standard FT method ids.
No chain-specific selectors, layouts, or account metas. -/
def declareExternalToken (peerId : String) : ModuleM ExternalToken := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  let mTransfer ← ProofForge.Contract.Builder.ensureCrosscallString methodFtTransfer
  let mApprove ← ProofForge.Contract.Builder.ensureCrosscallString methodApprove
  let mTransferFrom ← ProofForge.Contract.Builder.ensureCrosscallString methodTransferFrom
  let mBalance ← ProofForge.Contract.Builder.ensureCrosscallString methodFtBalanceOf
  let mSupply ← ProofForge.Contract.Builder.ensureCrosscallString methodFtTotalSupply
  pure {
    peer := peerHandle tIdx
    transferMethod := peerHandle mTransfer
    approveMethod := peerHandle mApprove
    transferFromMethod := peerHandle mTransferFrom
    balanceOfMethod := peerHandle mBalance
    totalSupplyMethod := peerHandle mSupply
  }

/-- `transfer(to, amount)` — EVM IERC20 / NEAR ft_transfer / Solana portable CPI. -/
def externalTokenTransfer (token : ExternalToken) (to amount : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall token.peer token.transferMethod #[to, amount]

/-- `approve(spender, amount)`. -/
def externalTokenApprove (token : ExternalToken) (spender amount : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall token.peer token.approveMethod #[spender, amount]

/-- `transferFrom(from, to, amount)`. -/
def externalTokenTransferFrom (token : ExternalToken) (fromAddr to amount : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall token.peer token.transferFromMethod #[fromAddr, to, amount]

/-- `balanceOf(account)` / `ft_balance_of`. -/
def externalTokenBalanceOf (token : ExternalToken) (account : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall token.peer token.balanceOfMethod #[account]

/-- `totalSupply` / `ft_total_supply`. -/
def externalTokenTotalSupply (token : ExternalToken) : ProofForge.IR.Expr :=
  remoteCall token.peer token.totalSupplyMethod #[]

/-- Register a NEAR-style account id string for use as receiver/account pool idx
(args to transfer / balanceOf on NEAR). On EVM the same handle is a u64 word. -/
def registerAccountId (accountId : String) : ModuleM ProofForge.IR.Expr := do
  let idx ← ProofForge.Contract.Builder.ensureCrosscallString accountId
  pure (peerHandle idx)

/-- EIP-2612 `permit` on an external token peer (method id `permit` in pool).
Does **not** implement token-side nonces (TokenSpec `permit` still rejects for
*being* the ERC-20). Scalar-bounded: v/r/s as portable words. -/
def externalTokenPermit (token : ExternalToken)
    (owner spender value deadline v r s : ProofForge.IR.Expr) : ModuleM ProofForge.IR.Expr := do
  let mIdx ← ProofForge.Contract.Builder.ensureCrosscallString methodPermit
  pure (remoteCall token.peer (peerHandle mIdx) #[owner, spender, value, deadline, v, r, s])

/-! ## External ERC-4626 vault peer -/

structure ExternalVault where
  peer : ProofForge.IR.Expr
  depositMethod : ProofForge.IR.Expr
  withdrawMethod : ProofForge.IR.Expr
  convertToSharesMethod : ProofForge.IR.Expr
  convertToAssetsMethod : ProofForge.IR.Expr
  totalAssetsMethod : ProofForge.IR.Expr
  assetMethod : ProofForge.IR.Expr
  deriving Repr

def declareExternalVault (peerId : String) : ModuleM ExternalVault := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  let mDep ← ProofForge.Contract.Builder.ensureCrosscallString methodVaultDeposit
  let mWd ← ProofForge.Contract.Builder.ensureCrosscallString methodVaultWithdraw
  let mCts ← ProofForge.Contract.Builder.ensureCrosscallString methodVaultConvertToShares
  let mCta ← ProofForge.Contract.Builder.ensureCrosscallString methodVaultConvertToAssets
  let mTa ← ProofForge.Contract.Builder.ensureCrosscallString methodVaultTotalAssets
  let mAsset ← ProofForge.Contract.Builder.ensureCrosscallString methodVaultAsset
  pure {
    peer := peerHandle tIdx
    depositMethod := peerHandle mDep
    withdrawMethod := peerHandle mWd
    convertToSharesMethod := peerHandle mCts
    convertToAssetsMethod := peerHandle mCta
    totalAssetsMethod := peerHandle mTa
    assetMethod := peerHandle mAsset
  }

def externalVaultDeposit (v : ExternalVault) (assets receiver : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall v.peer v.depositMethod #[assets, receiver]

def externalVaultWithdraw (v : ExternalVault) (assets receiver owner : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall v.peer v.withdrawMethod #[assets, receiver, owner]

def externalVaultConvertToShares (v : ExternalVault) (assets : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall v.peer v.convertToSharesMethod #[assets]

def externalVaultConvertToAssets (v : ExternalVault) (shares : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall v.peer v.convertToAssetsMethod #[shares]

def externalVaultTotalAssets (v : ExternalVault) : ProofForge.IR.Expr :=
  remoteCall v.peer v.totalAssetsMethod #[]

def externalVaultAsset (v : ExternalVault) : ProofForge.IR.Expr :=
  remoteCall v.peer v.assetMethod #[]

end ProofForge.Contract.Protocol
