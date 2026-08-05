/-
  ADR-0029 Phase C2 + ADR-0030 E1-NEAR — NEAR-owned `pf.assets` binding catalog.

  L1 portable QNs admitted for materialization on NEAR:
    * `pf.assets.native.deposit(amount)` — exact `attached_deposit == amount`
      (yoctoNEAR base unit; amount is UInt64 so high u128 word must be 0).
    * `pf.assets.native.transferAsync(dst, amount)` — fire-and-forget
      `promise_batch_create` + `promise_batch_action_transfer` (no response
      observation; async failure never propagates — matches Reference
      schedule/no-response-cursor discipline).
    * `pf.assets.token.transferAsync(mint, dst, amount)` — ADR-0030 E1-NEAR:
      fire-and-forget NEP-141 `ft_transfer` cross-contract Promise.
      `promise_batch_create(mint)` +
      `promise_batch_action_function_call("ft_transfer", json_args, gas,
      attached_deposit=1 yoctoNEAR)`. NEP-141 requires exactly 1 yoctoNEAR
      deposit; JSON args are `{"receiver_id":"<dst>","amount":"<amount>"}`
      where `<amount>` is the decimal ASCII of the UInt64 base-unit value.
      Fire-and-forget: no result callback, no response cursor (same acceptance
      discipline as C2 native transferAsync).

  Permanently fail closed on NEAR:
    * `pf.assets.native.transfer` — Promise is async; must not be wrapped as sync.
    * `pf.assets.token.transfer` (sync) — NEP-141 cross-contract call is async;
      must not be wrapped as sync (honesty boundary, not debt).

  Principal encoding for mint / dst (wire identity ≠ NEAR account-id):
    `u32le(len) || utf8-account-id-bytes` (Pilot Principal leaves:
    len leaf + 8×UInt64 body words). Runtime validates NEAR account-id grammar
    (2..64 bytes; lowercase a-z, digits, `_`, `-`, `.`; no leading/trailing `.`)
    and fail-closes on any other Principal body. The `mint` Principal decodes
    to the NEP-141 token contract account id (controlled dynamic callee —
    catalog token family only, not arbitrary dynamic callee).

  **Not** a formal catalog digest / BuildIdentity / NetworkProfile asset registry.
-/
import ProofForgeV2.Core.RequirementIdsV1

namespace ProofForgeV2.Targets.Near.PfAssetsCatalogV1

open ProofForgeV2.Core.RequirementIdsV1

/-- Frozen lowering contract for NEAR native deposit + transferAsync (Phase C2).
    Decisions are product-pinned; changes require a catalog/version bump. -/
structure NativeValueLoweringContractV1 where
  /-- Deposit: exact `attached_deposit` u128 == amount (lo) || 0 (hi). Not `>=`. -/
  depositAttachedRelation : String := "eq-u128-amount-lo-hi0"
  /-- Entries without any deposit statement keep historical zero-deposit
      discipline (`attached_deposit == 0` before KV work). -/
  nonDepositEntryAttached : String := "must-be-zero"
  /-- yoctoNEAR is the sole base unit (no gas/storage economics claim). -/
  depositBaseUnit : String := "yoctoNEAR"
  /-- transferAsync: `Promise::new(dst).transfer(amount)` as
      `promise_batch_create` + `promise_batch_action_transfer`. -/
  transferAsyncHost : String :=
    "promise_batch_create+promise_batch_action_transfer"
  /-- Fire-and-forget: no response cursor; async failure never propagates. -/
  transferAsyncFailure : String := "async-failure-not-propagated"
  /-- Destination Principal → account-id wire identity. -/
  dstPrincipalEncoding : String := "u32le(len)||utf8-account-id-bytes"
  /-- Account-id grammar (pilot; matches schedule receivers). -/
  accountIdGrammar : String :=
    "len-2..64;lowercase-a-z|0-9|_|-|. ;no-leading-or-trailing-dot"
  /-- Sync transfer permanently refuse (Promise is async). -/
  syncTransferPolicy : String := "permanently-fail-closed"
  deriving BEq, Repr, Inhabited

/-- Frozen lowering contract for NEAR NEP-141 token transferAsync (ADR-0030 E1).
    Decisions are product-pinned; changes require a catalog/version bump. -/
structure TokenTransferLoweringContractV1 where
  /-- NEP-141 method name on the token contract. -/
  methodName : String := "ft_transfer"
  /-- JSON args shape: `{"receiver_id":"<dst>","amount":"<decimal>"}`. -/
  argsShape : String := "json-receiver-id-and-amount-decimal"
  /-- NEP-141 requires exactly 1 yoctoNEAR attached deposit. -/
  attachedDeposit : String := "1-yoctoNEAR"
  /-- Fire-and-forget: no response cursor; async failure never propagates. -/
  transferAsyncFailure : String := "async-failure-not-propagated"
  /-- Frozen gas allocation for the function-call action (prepaid gas). -/
  gasAllocation : String := "30000000000000"
  /-- mint Principal → token contract account id wire identity. -/
  mintPrincipalEncoding : String := "u32le(len)||utf8-account-id-bytes"
  /-- dst Principal → receiver account id wire identity (same as native dst). -/
  dstPrincipalEncoding : String := "u32le(len)||utf8-account-id-bytes"
  /-- Account-id grammar (pilot; matches schedule receivers + native dst). -/
  accountIdGrammar : String :=
    "len-2..64;lowercase-a-z|0-9|_|-|. ;no-leading-or-trailing-dot"
  /-- Sync token transfer permanently refuse (NEP-141 is async). -/
  syncTokenTransferPolicy : String := "permanently-fail-closed"
  /-- Host functions used. -/
  transferAsyncHost : String :=
    "promise_batch_create+promise_batch_action_function_call"
  deriving BEq, Repr, Inhabited

def nativeValueLoweringContractV1 : NativeValueLoweringContractV1 := {}

/-- Package id for NEAR native yoctoNEAR value (no contract bytecode). -/
def nativeValuePackageIdV1 : String := "near-native-value-v1"

def tokenTransferLoweringContractV1 : TokenTransferLoweringContractV1 := {}

/-- Package id for NEAR NEP-141 token standard (interface-standard; no bytecode). -/
def tokenInterfacePackageIdV1 : String := "near-nep141-token-v1"

/-- Frozen gas (in gas units) for the NEP-141 ft_transfer function-call action.
    Consistent with the C2 schedule promise gas placeholder (30 Tgas). -/
def tokenTransferGasV1 : Nat := 30000000000000

/-- One admitted L1 QN binding for the NEAR native half-binding package. -/
structure NativeBindingV1 where
  qn : String
  packageId : String
  loweringContract : NativeValueLoweringContractV1
  admittedForMaterialization : Bool
  deriving BEq, Repr, Inhabited

/-- One admitted L1 QN binding for the NEAR NEP-141 token package. -/
structure TokenBindingV1 where
  qn : String
  packageId : String
  loweringContract : TokenTransferLoweringContractV1
  admittedForMaterialization : Bool
  deriving BEq, Repr, Inhabited

/-- Phase C2 admitted bindings: native deposit + transferAsync only. -/
def nativeBindingsV1 : Array NativeBindingV1 :=
  #[
    { qn := "pf.assets.native.deposit"
      packageId := nativeValuePackageIdV1
      loweringContract := nativeValueLoweringContractV1
      admittedForMaterialization := true },
    { qn := "pf.assets.native.transferAsync"
      packageId := nativeValuePackageIdV1
      loweringContract := nativeValueLoweringContractV1
      admittedForMaterialization := true }
  ]

/-- ADR-0030 E1-NEAR admitted binding: token transferAsync only. -/
def tokenBindingsV1 : Array TokenBindingV1 :=
  #[
    { qn := "pf.assets.token.transferAsync"
      packageId := tokenInterfacePackageIdV1
      loweringContract := tokenTransferLoweringContractV1
      admittedForMaterialization := true }
  ]

/-- Closed QN membership for the NEAR admitted pf.assets set (native + token
    transferAsync). Sync transfer / token.transfer stay fail closed. -/
def isNearAdmittedPfAssetsQnV1 (qn : String) : Bool :=
  qn == "pf.assets.native.deposit" ||
    qn == "pf.assets.native.transferAsync" ||
    qn == "pf.assets.token.transferAsync"

/-- Full catalog membership (five QNs); non-admitted members fail closed at Plan. -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

end ProofForgeV2.Targets.Near.PfAssetsCatalogV1
