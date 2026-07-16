/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — EVM IERC4626 external vault client

Call an **already-deployed** ERC-4626 vault via portable `crosscall.invoke`.
This is **not** a deployable vault mixin (Layer C) — product TokenSpec still
does not emit ERC-4626 bodies; this client is ecosystem integration only.

Selectors match the EIP-4626 interface (OpenZeppelin IERC4626).
-/
import ProofForge.Contract.Source.Internal

namespace ProofForge.Protocols.Evm.IERC4626

open ProofForge.Contract.Source.Internal

def catalogId : String := "protocols.evm.ierc4626"

/-- `asset()` -/
def selectorAsset : Nat := 0x38d52e0f
/-- `totalAssets()` -/
def selectorTotalAssets : Nat := 0x01e1d114
/-- `convertToShares(uint256)` -/
def selectorConvertToShares : Nat := 0xc6e6f592
/-- `convertToAssets(uint256)` -/
def selectorConvertToAssets : Nat := 0x07a2d13a
/-- `maxDeposit(address)` -/
def selectorMaxDeposit : Nat := 0x402d267d
/-- `maxMint(address)` -/
def selectorMaxMint : Nat := 0xc63d75b6
/-- `maxWithdraw(address)` -/
def selectorMaxWithdraw : Nat := 0xce96cb77
/-- `maxRedeem(address)` -/
def selectorMaxRedeem : Nat := 0xd905777e
/-- `previewDeposit(uint256)` -/
def selectorPreviewDeposit : Nat := 0xef8b30f7
/-- `previewMint(uint256)` -/
def selectorPreviewMint : Nat := 0xb3d7f6b9
/-- `previewWithdraw(uint256)` -/
def selectorPreviewWithdraw : Nat := 0x0a28a477
/-- `previewRedeem(uint256)` -/
def selectorPreviewRedeem : Nat := 0x4cdad506
/-- `deposit(uint256,address)` -/
def selectorDeposit : Nat := 0x6e553f65
/-- `mint(uint256,address)` -/
def selectorMint : Nat := 0x94bf804d
/-- `withdraw(uint256,address,address)` -/
def selectorWithdraw : Nat := 0xb460af94
/-- `redeem(uint256,address,address)` -/
def selectorRedeem : Nat := 0xba087652

structure Vault where
  target : ProofForge.IR.Expr
  deriving Repr

def declareVault (peerId : String) : ModuleM Vault := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  pure { target := peerHandle tIdx }

def asset (v : Vault) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorAsset) #[]

def totalAssets (v : Vault) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorTotalAssets) #[]

def convertToShares (v : Vault) (assets : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorConvertToShares) #[assets]

def convertToAssets (v : Vault) (shares : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorConvertToAssets) #[shares]

def maxDeposit (v : Vault) (receiver : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorMaxDeposit) #[receiver]

def maxMint (v : Vault) (receiver : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorMaxMint) #[receiver]

def maxWithdraw (v : Vault) (owner : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorMaxWithdraw) #[owner]

def maxRedeem (v : Vault) (owner : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorMaxRedeem) #[owner]

def previewDeposit (v : Vault) (assets : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorPreviewDeposit) #[assets]

def previewMint (v : Vault) (shares : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorPreviewMint) #[shares]

def previewWithdraw (v : Vault) (assets : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorPreviewWithdraw) #[assets]

def previewRedeem (v : Vault) (shares : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorPreviewRedeem) #[shares]

def deposit (v : Vault) (assets receiver : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorDeposit) #[assets, receiver]

def mint (v : Vault) (shares receiver : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorMint) #[shares, receiver]

def withdraw (v : Vault) (assets receiver owner : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorWithdraw) #[assets, receiver, owner]

def redeem (v : Vault) (shares receiver owner : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall v.target (u64 selectorRedeem) #[shares, receiver, owner]

end ProofForge.Protocols.Evm.IERC4626
