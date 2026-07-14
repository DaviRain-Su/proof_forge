/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer C — EIP-2612 ERC20Permit mixin (EVM)

`nonces`, `DOMAIN_SEPARATOR`, and atomic `permit`.

**Host gate:** `crypto.ecrecover` (EVM-only). Solana/NEAR reject at preflight.

`permit(owner,spender,value,deadline,v,r,s)` is the canonical atomic EIP-2612
surface. DOMAIN_SEPARATOR is initialized once via `initDomain(sep)`.
-/
import ProofForge.Contract.Source.Evm

namespace ProofForge.Contract.Stdlib.ERC20Permit

open ProofForge.Contract.Source

def noncesMap : MapRef :=
  { id := "nonces", keyType := .u64, valueType := .u64 }

def domainSeparatorSlot : ScalarRef :=
  ProofForge.Contract.Source.slot "domainSeparator" .hash

def totalSupply : ScalarRef :=
  ProofForge.Contract.Source.slot "totalSupply" .u64

def balances : MapRef :=
  { id := "balances", keyType := .u64, valueType := .u64 }

def allowances : MapRef :=
  { id := "allowances", keyType := .u64, valueType := .u64 }

contract_mixin ERC20PermitMixin do
  use ProofForge.Contract.Source.scalar totalSupply
  use ProofForge.Contract.Source.scalar domainSeparatorSlot
  use ProofForge.Contract.Source.mapState balances
  use ProofForge.Contract.Source.mapState allowances
  use ProofForge.Contract.Source.mapState noncesMap

  event Approval

  query nonces (who : .address) returns(.u64) do
    return mapRead noncesMap who;

  query DOMAIN_SEPARATOR returns(.hash) do
    return domainSeparatorSlot;

  entry initDomain (sep : .hash) do
    do ProofForge.Contract.Source.requireEq
      (ProofForge.Contract.Source.read domainSeparatorSlot)
      (ProofForge.Contract.Source.hash4 0 0 0 0) "domain already initialized";
    do ProofForge.Contract.Source.requireNe
      (ProofForge.Contract.Source.ref sep)
      (ProofForge.Contract.Source.hash4 0 0 0 0) "zero domain";
    domainSeparatorSlot := sep;

  entry permit (holder : .address, spender : .address, value : .u64, deadline : .u64, v : .u8, r : .bytes32, s : .bytes32) do
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref holder)
      "zero owner";
    do ProofForge.Contract.Source.requireNonZero (ProofForge.Contract.Source.ref spender)
      "zero spender";
    do ProofForge.Contract.Source.requireGe (ProofForge.Contract.Source.ref deadline) timestamp
      "permit expired";
    let n : .u64 := mapRead noncesMap holder;
    let digest : .hash :=
      ProofForge.Contract.Source.Evm.eip712PermitDigest
        (ProofForge.Contract.Source.ref holder)
        (ProofForge.Contract.Source.ref spender)
        (ProofForge.Contract.Source.ref value)
        (ProofForge.Contract.Source.ref n)
        (ProofForge.Contract.Source.ref deadline)
        (ProofForge.Contract.Source.read domainSeparatorSlot);
    let recovered : .u64 :=
      ProofForge.Contract.Source.Evm.ecrecover
        (ProofForge.Contract.Source.ref digest)
        (ProofForge.Contract.Source.cast (ProofForge.Contract.Source.ref v) .u64)
        (ProofForge.Contract.Source.ref r)
        (ProofForge.Contract.Source.ref s);
    do ProofForge.Contract.Source.requireEq
      (ProofForge.Contract.Source.ref recovered)
      (ProofForge.Contract.Source.ref holder)
      "invalid permit signature";
    do mapWrite noncesMap holder (n +! u64 1);
    do pathWriteAllowance allowances (ProofForge.Contract.Source.ref holder)
      (ProofForge.Contract.Source.ref spender) value;
    emit Approval indexed #[
      fieldAsName "owner" holder,
      fieldAsName "spender" spender
    ] data #[
      fieldAsName "value" value
    ];

contract_source ERC20Permit do
  use mixin
  entry init do
    totalSupply := u64 0;

end ProofForge.Contract.Stdlib.ERC20Permit
