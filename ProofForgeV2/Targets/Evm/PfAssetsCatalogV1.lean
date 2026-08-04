/-
  ADR-0029 Phase B2 — EVM-owned `pf.assets` native binding catalog skeleton.

  L1 portable QNs (`pf.assets.native.deposit` / `pf.assets.native.transfer`) bind
  to EVM native value transfer. This module freezes the target-owned binding
  surface and the third `artifactBinding` form (`interface-standard`) as a
  minimal engineering skeleton for the later ERC-20 token lane.

  **Not** a formal catalog digest / BuildIdentity / NetworkProfile asset registry.
  Token (`pf.assets.token.*`) and async variants stay fail closed at Plan lowering.
-/
import ProofForgeV2.Core.RequirementIdsV1

namespace ProofForgeV2.Targets.Evm.PfAssetsCatalogV1

open ProofForgeV2.Core.RequirementIdsV1

/-- Three-form artifact binding (ADR-0029 promotion of ADR-0028's two forms).
    `interfaceStandard` carries a named standard id + free-form predicate list;
    it does **not** bind exact bytecode. Native ETH value has no ERC contract
    instance — Phase B2 uses `runtimeNative` for the native-value package and
    reserves `interfaceStandard` for the future ERC-20 binding. -/
inductive ArtifactBindingKind where
  | runtimeNative
  | packageOwnedBytes
  | interfaceStandard (standardId : String) (predicates : Array String)
  deriving BEq, Repr, Inhabited

/-- Frozen lowering contract for EVM native deposit/transfer (Phase B2).
    Decisions are product-pinned; changes require a catalog/version bump. -/
structure NativeValueLoweringContractV1 where
  /-- Deposit: Yul `eq(callvalue(), amount)` (exact, not `>=`). -/
  depositCallvalueRelation : String := "eq"
  /-- Entries with no deposit statement keep non-payable discipline
      (`callvalue() == 0`). -/
  nonDepositEntryCallvalue : String := "must-be-zero"
  /-- Transfer gas: forward all remaining gas (`gas()`). -/
  transferGasPolicy : String := "forward-all-gas"
  /-- Transfer calldata: empty (`argsOffset=0, argsSize=0`). -/
  transferCalldata : String := "empty"
  /-- CALL success=false reverts the caller (Reference failure propagate). -/
  transferFailure : String := "propagate-revert"
  /-- Destination Principal must be exact wire shape `u32le(20)||addr20`
      (ADR-0025 caller encoding discipline). Wire identity ≠ 20B address pin
      (B-3) is preserved: only this exact 20-byte body is admitted for value
      CALL; other Principal bodies fail closed at runtime. -/
  dstPrincipalEncoding : String := "u32le(20)||addr20-network-order"
  /-- Opaque-effect honesty: value CALL may execute recipient code (including
      re-entrancy into the caller). Reference has no re-entrancy model; EVM
      binding is an opaque external effect. Programs must not rely on mid-entry
      state after a transfer. Source order is not reordered. -/
  reentrancyNote : String :=
    "value-CALL-may-execute-recipient-code-including-reentrancy; \
Reference-has-no-reentrancy-model; opaque-external-effect; \
programs-must-not-depend-on-mid-entry-state-after-transfer; \
source-order-preserved"
  deriving BEq, Repr, Inhabited

def nativeValueLoweringContractV1 : NativeValueLoweringContractV1 := {}

/-- One admitted L1 QN binding for the EVM native-value package. -/
structure NativeBindingV1 where
  qn : String
  packageId : String
  artifactBinding : ArtifactBindingKind
  loweringContract : NativeValueLoweringContractV1
  admittedForMaterialization : Bool
  deriving BEq, Repr, Inhabited

/-- Package id for EVM native ETH value (no contract bytecode). -/
def nativeValuePackageIdV1 : String := "evm-native-value-v1"

/-- Phase B2 admitted bindings: native deposit + transfer only. -/
def nativeBindingsV1 : Array NativeBindingV1 :=
  #[
    { qn := "pf.assets.native.deposit"
      packageId := nativeValuePackageIdV1
      artifactBinding := .runtimeNative
      loweringContract := nativeValueLoweringContractV1
      admittedForMaterialization := true },
    { qn := "pf.assets.native.transfer"
      packageId := nativeValuePackageIdV1
      artifactBinding := .runtimeNative
      loweringContract := nativeValueLoweringContractV1
      admittedForMaterialization := true }
  ]

/-- Skeleton ERC-20 interface-standard binding (not admitted for materialization
    in Phase B2). Predicate list is documentary; token lowering is a later slice. -/
def erc20InterfaceStandardSkeletonV1 : ArtifactBindingKind :=
  .interfaceStandard "erc-20"
    #["return-value-bool-or-absent", "no-fee-on-transfer", "decimals-join-via-network-profile"]

/-- Closed QN membership for the EVM native Phase B2 admit set. -/
def isEvmAdmittedPfAssetsQnV1 (qn : String) : Bool :=
  qn == "pf.assets.native.deposit" || qn == "pf.assets.native.transfer"

/-- Full catalog membership (five QNs); non-admitted members fail closed at Plan. -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

end ProofForgeV2.Targets.Evm.PfAssetsCatalogV1
