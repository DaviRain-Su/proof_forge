/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

ERC-1155 core mixin for `contract_source` composition on EVM.
Covers balances, operator approvals, mint, burn, single `safeTransferFrom`
with IERC1155Receiver callback (PF-P2-02), and size-2 `safeBatchTransferFrom2`
(fixed two ids; dynamic-array batch ABI is a later slice).
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.ERC1155

open ProofForge.Contract.Source

namespace Spec

theorem transfer_preserves_token_supply {srcBal dstBal amount : Nat}
    (h_src : amount ≤ srcBal)
    : (srcBal - amount) + (dstBal + amount) = srcBal + dstBal := by
  omega

theorem burn_decreases_balance {balance amount : Nat}
    (h : amount ≤ balance)
    : balance - amount ≤ balance := by omega

end Spec

def balances : MapRef :=
  { id := "erc1155Balances", keyType := .u64, valueType := .u64 }

def operatorApprovals : MapRef :=
  { id := "erc1155OperatorApprovals", keyType := .u64, valueType := .u64 }

contract_mixin ERC1155Mixin do
  use ProofForge.Contract.Surface.mapState balances
  use ProofForge.Contract.Surface.mapState operatorApprovals

  event TransferSingle
  event ApprovalForAll

  query balanceOf (holder : .address, id : .u64) returns(.u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref holder) "zero account";
    return pathRead2 balances holder id;

  query isApprovedForAll (holder : .address, operator : .address) returns(.bool) do
    let approved : .u64 := pathRead2 operatorApprovals holder operator;
    return ProofForge.Contract.Surface.ne (ProofForge.Contract.Surface.ref approved) (u64 0);

  entry setApprovalForAll (operator : .address, approved : .bool) do
    let holder : .address := caller;
    do ProofForge.Contract.Surface.requireNe (ProofForge.Contract.Surface.ref holder)
      (ProofForge.Contract.Surface.ref operator) "self approval";
    do pathWrite2 operatorApprovals holder operator
      (ProofForge.IR.Expr.cast (ProofForge.Contract.Surface.ref approved) .u64);
    emit ApprovalForAll indexed #[
      fieldAsName "account" holder,
      fieldAsName "operator" operator
    ] data #[
      fieldAsName "approved" approved
    ];

  entry safeTransferFrom (src : .address, dst : .address, id : .u64, amount : .u64) do
    let operator : .address := caller;
    let approved : .u64 := pathRead2 operatorApprovals src operator;
    do ProofForge.Contract.Surface.assertCondition
      (ProofForge.Contract.Surface.boolOr
        (ProofForge.Contract.Surface.eq (ProofForge.Contract.Surface.ref operator)
          (ProofForge.Contract.Surface.ref src))
        (ProofForge.Contract.Surface.ne (ProofForge.Contract.Surface.ref approved) (u64 0)))
      "not approved";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref dst) "zero recipient";
    let fromBal : .u64 := pathRead2 balances src id;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref fromBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do pathWrite2 balances src id (fromBal -! amount);
    let toBal : .u64 := pathRead2 balances dst id;
    do pathWrite2 balances dst id (toBal +! amount);
    emit TransferSingle indexed #[
      fieldAsName "operator" operator,
      fieldAsName "from" src,
      fieldAsName "to" dst
    ] data #[
      fieldAsName "id" id,
      fieldAsName "value" amount
    ];
    do ProofForge.Contract.Surface.checkErc1155Received
      (ProofForge.Contract.Surface.ref operator)
      (ProofForge.Contract.Surface.ref src)
      (ProofForge.Contract.Surface.ref dst)
      (ProofForge.Contract.Surface.ref id)
      (ProofForge.Contract.Surface.ref amount);

  -- Size-2 batch transfer (PF-P2-02 MVP). Full dynamic-array batch ABI is
  -- a later slice; this entry exercises multi-id accounting + dual receiver
  -- checks on EVM.
  entry safeBatchTransferFrom2 (src : .address, dst : .address, id0 : .u64, amount0 : .u64, id1 : .u64, amount1 : .u64) do
    let operator : .address := caller;
    let approved : .u64 := pathRead2 operatorApprovals src operator;
    do ProofForge.Contract.Surface.assertCondition
      (ProofForge.Contract.Surface.boolOr
        (ProofForge.Contract.Surface.eq (ProofForge.Contract.Surface.ref operator)
          (ProofForge.Contract.Surface.ref src))
        (ProofForge.Contract.Surface.ne (ProofForge.Contract.Surface.ref approved) (u64 0)))
      "not approved";
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref dst) "zero recipient";
    let fromBal0 : .u64 := pathRead2 balances src id0;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref fromBal0)
      (ProofForge.Contract.Surface.ref amount0) "insufficient balance";
    do pathWrite2 balances src id0 (fromBal0 -! amount0);
    let toBal0 : .u64 := pathRead2 balances dst id0;
    do pathWrite2 balances dst id0 (toBal0 +! amount0);
    emit TransferSingle indexed #[
      fieldAsName "operator" operator,
      fieldAsName "from" src,
      fieldAsName "to" dst
    ] data #[
      fieldAsName "id" id0,
      fieldAsName "value" amount0
    ];
    do ProofForge.Contract.Surface.checkErc1155Received
      (ProofForge.Contract.Surface.ref operator)
      (ProofForge.Contract.Surface.ref src)
      (ProofForge.Contract.Surface.ref dst)
      (ProofForge.Contract.Surface.ref id0)
      (ProofForge.Contract.Surface.ref amount0);
    let fromBal1 : .u64 := pathRead2 balances src id1;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref fromBal1)
      (ProofForge.Contract.Surface.ref amount1) "insufficient balance";
    do pathWrite2 balances src id1 (fromBal1 -! amount1);
    let toBal1 : .u64 := pathRead2 balances dst id1;
    do pathWrite2 balances dst id1 (toBal1 +! amount1);
    emit TransferSingle indexed #[
      fieldAsName "operator" operator,
      fieldAsName "from" src,
      fieldAsName "to" dst
    ] data #[
      fieldAsName "id" id1,
      fieldAsName "value" amount1
    ];
    do ProofForge.Contract.Surface.checkErc1155Received
      (ProofForge.Contract.Surface.ref operator)
      (ProofForge.Contract.Surface.ref src)
      (ProofForge.Contract.Surface.ref dst)
      (ProofForge.Contract.Surface.ref id1)
      (ProofForge.Contract.Surface.ref amount1);

  entry mint (recipient : .address, id : .u64, amount : .u64) do
    let operator : .address := caller;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref recipient) "zero recipient";
    let toBal : .u64 := pathRead2 balances recipient id;
    do pathWrite2 balances recipient id (toBal +! amount);
    emit TransferSingle indexed #[
      fieldAsName "operator" operator,
      fieldAsName "from" (u64 0),
      fieldAsName "to" recipient
    ] data #[
      fieldAsName "id" id,
      fieldAsName "value" amount
    ];

  entry burn (id : .u64, amount : .u64) do
    let operator : .address := caller;
    let bal : .u64 := pathRead2 balances operator id;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do pathWrite2 balances operator id (bal -! amount);
    emit TransferSingle indexed #[
      fieldAsName "operator" operator,
      fieldAsName "from" operator,
      fieldAsName "to" (u64 0)
    ] data #[
      fieldAsName "id" id,
      fieldAsName "value" amount
    ];

contract_source ERC1155 do
  use mixin

end ProofForge.Contract.Stdlib.ERC1155
