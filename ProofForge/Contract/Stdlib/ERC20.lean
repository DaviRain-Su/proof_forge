/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical ERC-20 token mixin for `contract_source` composition on EVM.
Uses standard selectors, Transfer/Approval events, and bool returns.
To combine with Ownable in one contract, use the official `compose` API and import
`ProofForge.Contract.Stdlib.Compose.Specs` rather than chaining both mixins directly.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.ERC20

open ProofForge.Contract.Source

namespace Spec

theorem transfer_conserves_supply {srcBal dstBal amount : Nat}
    (h_src : amount ≤ srcBal)
    : (srcBal - amount) + (dstBal + amount) = srcBal + dstBal := by
  omega

theorem spend_allowance_bounded {current allowance : Nat}
    (h : current ≤ allowance)
    : allowance - current ≤ allowance := by omega

theorem mint_increases_supply {supply : Nat} {amount : Nat}
    : supply + amount ≥ supply := by omega

theorem burn_decreases_supply {supply amount : Nat}
    (h : amount ≤ supply)
    : supply - amount ≤ supply := by omega

end Spec

def totalSupply : ScalarRef :=
  ProofForge.Contract.Surface.slot "totalSupply" .u64

def tokenDecimals : ScalarRef :=
  ProofForge.Contract.Surface.slot "decimals" .u64

def balances : MapRef :=
  { id := "balances", keyType := .u64, valueType := .u64 }

def allowances : MapRef :=
  { id := "allowances", keyType := .u64, valueType := .u64 }

contract_mixin ERC20Mixin do
  use ProofForge.Contract.Surface.scalar totalSupply
  use ProofForge.Contract.Surface.scalar tokenDecimals
  use ProofForge.Contract.Surface.mapState balances
  use ProofForge.Contract.Surface.mapState allowances

  event Transfer abi #[
    ("from", "address"), ("to", "address"), ("value", "uint256")
  ]
  event Approval abi #[
    ("owner", "address"), ("spender", "address"), ("value", "uint256")
  ]

  query totalSupply returns(.u64) do
    return totalSupply;

  query «decimals» returns(.u64) do
    return tokenDecimals;

  query balanceOf (who : .address) returns(.u64) do
    return mapRead balances who;

  query allowance (holder : .address, spender : .address) returns(.u64) do
    return pathReadAllowance allowances (ProofForge.Contract.Surface.ref holder)
      (ProofForge.Contract.Surface.ref spender);

  entry transfer (recipient : .address, amount : .u64) returns(.bool) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient) "zero recipient";
    let sender : .address := caller;
    let srcBal : .u64 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (dstBal +! amount);
    emit Transfer indexed #[
      fieldAsName "from" sender,
      fieldAsName "to" recipient
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

  entry approve (spender : .address, amount : .u64) returns(.bool) do
    let holder : .address := caller;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref spender) "zero spender";
    do pathWriteAllowance allowances (ProofForge.Contract.Surface.ref holder)
      (ProofForge.Contract.Surface.ref spender) amount;
    emit Approval indexed #[
      fieldAsName "owner" holder,
      fieldAsName "spender" spender
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

  entry transferFrom (src : .address, dst : .address, amount : .u64) returns(.bool) do
    let spender : .address := caller;
    let current : .u64 := pathReadAllowance allowances (ProofForge.Contract.Surface.ref src)
      (ProofForge.Contract.Surface.ref spender);
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref current)
      (ProofForge.Contract.Surface.ref amount) "insufficient allowance";
    do pathWriteAllowance allowances (ProofForge.Contract.Surface.ref src)
      (ProofForge.Contract.Surface.ref spender) (current -! amount);
    let srcBal : .u64 := mapRead balances src;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances src (srcBal -! amount);
    let dstBal : .u64 := mapRead balances dst;
    do mapWrite balances dst (dstBal +! amount);
    emit Transfer indexed #[
      fieldAsName "from" src,
      fieldAsName "to" dst
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

  entry mint (recipient : .address, amount : .u64) returns(.bool) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient) "zero account";
    let ts : .u64 := totalSupply;
    totalSupply := ts +! amount;
    let bal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (bal +! amount);
    emit Transfer indexed #[
      fieldAsName "from" (u64 0),
      fieldAsName "to" recipient
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

  entry burn (amount : .u64) returns(.bool) do
    let who : .address := caller;
    let bal : .u64 := mapRead balances who;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances who (bal -! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! amount;
    emit Transfer indexed #[
      fieldAsName "from" who,
      fieldAsName "to" (u64 0)
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

contract_source ERC20 do
  use mixin
  entry init do
    tokenDecimals := u64 18;

end ProofForge.Contract.Stdlib.ERC20
