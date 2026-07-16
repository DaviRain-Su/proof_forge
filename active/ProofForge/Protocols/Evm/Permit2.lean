/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — Uniswap Permit2 external client

Thin CALL wrappers for a deployed Permit2. Signature/witness structs are
**not** fully ABI-packed here — selectors + portable scalar args only
(honest bound; same pattern as Multicall).

Canonical Permit2 selectors (Uniswap):
- `allowance(address,address,address)` → `0x927da105`
- `approve(address,address,uint160,uint48)` → `0x87517c45`
- `transferFrom(address,address,uint160,address)` → `0x36c78516`
- `permitTransferFrom(...)` → `0x30f28b7a` (struct-heavy; scalar smoke only)
-/
import ProofForge.Contract.Source.Internal

namespace ProofForge.Protocols.Evm.Permit2

open ProofForge.Contract.Source.Internal

def catalogId : String := "protocols.evm.permit2"

def selectorAllowance : Nat := 0x927da105
def selectorApprove : Nat := 0x87517c45
def selectorTransferFrom : Nat := 0x36c78516
def selectorPermitTransferFrom : Nat := 0x30f28b7a

structure Permit2 where
  target : ProofForge.IR.Expr
  deriving Repr

def declarePermit2 (peerId : String) : ModuleM Permit2 := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  pure { target := peerHandle tIdx }

def allowance (p : Permit2) (owner spender token : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall p.target (u64 selectorAllowance) #[owner, spender, token]

def approve (p : Permit2) (token spender amount expiration : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall p.target (u64 selectorApprove) #[token, spender, amount, expiration]

def transferFrom (p : Permit2) (fromAddr to amount token : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall p.target (u64 selectorTransferFrom) #[fromAddr, to, amount, token]

/-- permitTransferFrom — selector only with scalar args; full PermitTransferFrom
struct packing is **out of scope** (honest bound). -/
def permitTransferFrom (p : Permit2) (args : Array ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall p.target (u64 selectorPermitTransferFrom) args

end ProofForge.Protocols.Evm.Permit2
