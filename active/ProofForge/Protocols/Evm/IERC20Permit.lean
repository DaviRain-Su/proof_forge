/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — EVM EIP-2612 `permit` external client

Call `permit` on an **already-deployed** ERC-20 that implements EIP-2612
(OpenZeppelin ERC20Permit, etc.).

This is **not** TokenSpec `permit` feature materialization (Layer C body still
honestly rejects `permit` on EVM until a dedicated nonces/DOMAIN_SEPARATOR
stdlib ships). Product authors who need to *invoke* an external permit use
this client or portable protocol method id `permit`.

Scalar-bounded: `v` is a u64 word (0/1/27/28); `r`/`s` are hash-width words.
-/
import ProofForge.Contract.Source.Internal

namespace ProofForge.Protocols.Evm.IERC20Permit

open ProofForge.Contract.Source.Internal

def catalogId : String := "protocols.evm.ierc20_permit"

/-- `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)` -/
def selectorPermit : Nat := 0xd505accf
/-- `nonces(address)` -/
def selectorNonces : Nat := 0x7ecebe00
/-- `DOMAIN_SEPARATOR()` -/
def selectorDomainSeparator : Nat := 0x3644e515

structure Token where
  target : ProofForge.IR.Expr
  deriving Repr

def declareToken (peerId : String) : ModuleM Token := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  pure { target := peerHandle tIdx }

/-- EIP-2612 `permit(owner, spender, value, deadline, v, r, s)`. -/
def permit (token : Token)
    (owner spender value deadline v r s : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorPermit)
    #[owner, spender, value, deadline, v, r, s]

def nonces (token : Token) (owner : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorNonces) #[owner]

def domainSeparator (token : Token) : ProofForge.IR.Expr :=
  remoteCall token.target (u64 selectorDomainSeparator) #[]

end ProofForge.Protocols.Evm.IERC20Permit
