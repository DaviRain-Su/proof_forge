/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable ERC-20 token authored with `contract_source`.
-/
import ProofForge.Contract.Source

namespace ERC20

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

contract_source ERC20 do
  state totalSupply : .u64
  mapping balances from .u64 to .u64
  mapping allowances from .u64 to .u64

  query totalSupply returns(.u64) do
    return totalSupply;

  query balanceOf (who : .u64) returns(.u64) do
    return mapRead balances who;

  entry transfer (recipient : .u64, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient) "zero recipient";
    let sender : .u64 := caller;
    let srcBal : .u64 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal) (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (dstBal +! amount);

  query allowance (ownerAddr : .u64, spender : .u64) returns(.u64) do
    return pathReadAllowance allowances (ProofForge.Contract.Surface.ref ownerAddr) (ProofForge.Contract.Surface.ref spender);

  entry approve (spender : .u64, amount : .u64) do
    let ownerAddr : .u64 := caller;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref spender) "zero spender";
    do pathWriteAllowance allowances (ProofForge.Contract.Surface.ref ownerAddr) (ProofForge.Contract.Surface.ref spender) amount;

  entry transferFrom (src : .u64, dst : .u64, amount : .u64) do
    let spender : .u64 := caller;
    let current : .u64 := pathReadAllowance allowances (ProofForge.Contract.Surface.ref src) (ProofForge.Contract.Surface.ref spender);
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref current) (ProofForge.Contract.Surface.ref amount) "insufficient allowance";
    do pathWriteAllowance allowances (ProofForge.Contract.Surface.ref src) (ProofForge.Contract.Surface.ref spender) (current -! amount);
    let srcBal : .u64 := mapRead balances src;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal) (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances src (srcBal -! amount);
    let dstBal : .u64 := mapRead balances dst;
    do mapWrite balances dst (dstBal +! amount);

  entry mint (who : .u64, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref who) "zero account";
    let ts : .u64 := totalSupply;
    totalSupply := ts +! amount;
    let bal : .u64 := mapRead balances who;
    do mapWrite balances who (bal +! amount);

  entry burn (who : .u64, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref who) "zero account";
    let bal : .u64 := mapRead balances who;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal) (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances who (bal -! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! amount;

end ERC20
