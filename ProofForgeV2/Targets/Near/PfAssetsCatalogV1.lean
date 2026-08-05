/-
  ADR-0029 Phase C2 — NEAR-owned `pf.assets` half-binding catalog.

  L1 portable QNs admitted for materialization on NEAR:
    * `pf.assets.native.deposit(amount)` — exact `attached_deposit == amount`
      (yoctoNEAR base unit; amount is UInt64 so high u128 word must be 0).
    * `pf.assets.native.transferAsync(dst, amount)` — fire-and-forget
      `promise_batch_create` + `promise_batch_action_transfer` (no response
      observation; async failure never propagates — matches Reference
      schedule/no-response-cursor discipline).

  Permanently fail closed on NEAR:
    * `pf.assets.native.transfer` — Promise is async; must not be wrapped as sync.
    * `pf.assets.token.*` — NEP-141 is async; Phase C scope is native half only.

  Destination Principal encoding (wire identity ≠ NEAR account-id):
    `u32le(len) || utf8-account-id-bytes` (Pilot Principal leaves:
    len leaf + 8×UInt64 body words). Runtime validates NEAR account-id grammar
    (2..64 bytes; lowercase a-z, digits, `_`, `-`, `.`; no leading/trailing `.`)
    and fail-closes on any other Principal body.

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

def nativeValueLoweringContractV1 : NativeValueLoweringContractV1 := {}

/-- Package id for NEAR native yoctoNEAR value (no contract bytecode). -/
def nativeValuePackageIdV1 : String := "near-native-value-v1"

/-- One admitted L1 QN binding for the NEAR native half-binding package. -/
structure NativeBindingV1 where
  qn : String
  packageId : String
  loweringContract : NativeValueLoweringContractV1
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

/-- Closed QN membership for the NEAR native Phase C2 admit set. -/
def isNearAdmittedPfAssetsQnV1 (qn : String) : Bool :=
  qn == "pf.assets.native.deposit" || qn == "pf.assets.native.transferAsync"

/-- Full catalog membership (five QNs); non-admitted members fail closed at Plan. -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

end ProofForgeV2.Targets.Near.PfAssetsCatalogV1
