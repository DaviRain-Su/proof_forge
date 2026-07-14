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

open ProofForge.Contract.Source.Legacy

def noncesMap : MapRef :=
  { id := "nonces", keyType := .u64, valueType := .u64 }

def domainSeparatorSlot : ScalarRef :=
  ProofForge.Contract.Source.Legacy.slot "domainSeparator" .hash

def totalSupply : ScalarRef :=
  ProofForge.Contract.Source.Legacy.slot "totalSupply" .u64

def balances : MapRef :=
  { id := "balances", keyType := .u64, valueType := .u64 }

def allowances : MapRef :=
  { id := "allowances", keyType := .u64, valueType := .u64 }

contract_mixin ERC20PermitMixin do
  use ProofForge.Contract.Source.Legacy.scalar totalSupply
  use ProofForge.Contract.Source.Legacy.scalar domainSeparatorSlot
  use ProofForge.Contract.Source.Legacy.mapState balances
  use ProofForge.Contract.Source.Legacy.mapState allowances
  use ProofForge.Contract.Source.Legacy.mapState noncesMap

  event Approval

  query nonces (who : .address) returns(.u64) do
    return mapRead noncesMap who;

  query DOMAIN_SEPARATOR returns(.hash) do
    return domainSeparatorSlot;

  entry initDomain (sep : .hash) do
    do ProofForge.Contract.Source.Legacy.requireEq
      (ProofForge.Contract.Source.Legacy.read domainSeparatorSlot)
      (ProofForge.Contract.Source.Legacy.hash4 0 0 0 0) "domain already initialized";
    do ProofForge.Contract.Source.Legacy.requireNe
      (ProofForge.Contract.Source.Legacy.ref sep)
      (ProofForge.Contract.Source.Legacy.hash4 0 0 0 0) "zero domain";
    domainSeparatorSlot := sep;

  entry permit (holder : .address, spender : .address, value : .u64, deadline : .u64, v : .u8, r : .bytes32, s : .bytes32) do
    do ProofForge.Contract.Source.Legacy.requireNonZero (ProofForge.Contract.Source.Legacy.ref holder)
      "zero owner";
    do ProofForge.Contract.Source.Legacy.requireNonZero (ProofForge.Contract.Source.Legacy.ref spender)
      "zero spender";
    do ProofForge.Contract.Source.Legacy.requireGe (ProofForge.Contract.Source.Legacy.ref deadline) timestamp
      "permit expired";
    let n : .u64 := mapRead noncesMap holder;
    let digest : .hash :=
      ProofForge.Contract.Source.Evm.eip712PermitDigest
        (ProofForge.Contract.Source.Legacy.ref holder)
        (ProofForge.Contract.Source.Legacy.ref spender)
        (ProofForge.Contract.Source.Legacy.ref value)
        (ProofForge.Contract.Source.Legacy.ref n)
        (ProofForge.Contract.Source.Legacy.ref deadline)
        (ProofForge.Contract.Source.Legacy.read domainSeparatorSlot);
    let recovered : .u64 :=
      ProofForge.Contract.Source.Evm.ecrecover
        (ProofForge.Contract.Source.Legacy.ref digest)
        (ProofForge.Contract.Source.Legacy.cast (ProofForge.Contract.Source.Legacy.ref v) .u64)
        (ProofForge.Contract.Source.Legacy.ref r)
        (ProofForge.Contract.Source.Legacy.ref s);
    do ProofForge.Contract.Source.Legacy.requireEq
      (ProofForge.Contract.Source.Legacy.ref recovered)
      (ProofForge.Contract.Source.Legacy.ref holder)
      "invalid permit signature";
    do mapWrite noncesMap holder (n +! u64 1);
    do pathWriteAllowance allowances (ProofForge.Contract.Source.Legacy.ref holder)
      (ProofForge.Contract.Source.Legacy.ref spender) value;
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
