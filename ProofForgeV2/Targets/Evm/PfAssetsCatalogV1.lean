/-
  ADR-0029 Phase B2 — EVM-owned `pf.assets` native binding catalog skeleton.
  ADR-0030 E1a — EVM-owned `pf.assets.token.transfer` ERC-20 binding.

  L1 portable QNs (`pf.assets.native.deposit` / `pf.assets.native.transfer`) bind
  to EVM native value transfer. This module freezes the target-owned binding
  surface and the third `artifactBinding` form (`interface-standard`) used by
  the ERC-20 token lane (E1a: `pf.assets.token.transfer`).

  **Not** a formal catalog digest / BuildIdentity / NetworkProfile asset registry.
  `pf.assets.token.transferAsync` and `pf.assets.native.transferAsync` stay
  fail closed on EVM (sync is strictly stronger; no weak-async variant offered).
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

/-- Skeleton ERC-20 interface-standard binding (admitted for materialization
    in E1a). Predicate list is documentary; the `loweringContract` carries the
    product-pinned lowering decisions. -/
def erc20InterfaceStandardSkeletonV1 : ArtifactBindingKind :=
  .interfaceStandard "erc-20"
    #["return-value-bool-or-absent", "no-fee-on-transfer", "decimals-join-via-network-profile"]

/-- Frozen lowering contract for EVM ERC-20 `transfer(address,uint256)`
    (ADR-0030 E1a). Decisions are product-pinned; changes require a
    catalog/version bump. This is the **controlled dynamic callee** surface:
    only the catalog token family admits a parameterized token-contract
    address; generic dynamic callees remain fail closed. -/
structure Erc20TokenLoweringContractV1 where
  /-- Function selector for `transfer(address,uint256)` = `0xa9059cbb`. -/
  transferSelector : String := "0xa9059cbb"
  /-- Calldata layout: 4B selector + 32B address + 32B amount = 68 bytes. -/
  transferCalldataSize : String := "68"
  /-- Calldata layout description. -/
  transferCalldataLayout : String :=
    "4B-selector + 32B-address + 32B-amount"
  /-- Gas policy: forward all remaining gas (`gas()`). -/
  transferGasPolicy : String := "forward-all-gas"
  /-- Call value: zero (ERC-20 transfer carries no native ETH). -/
  transferCallValue : String := "zero"
  /-- `mint` Principal parameter carries the token contract address as
      exact wire shape `u32le(20)||addr20` (ADR-0025 discipline; same as B2
      native transfer dst). High limbs must be zero; runtime assembles a
      20-byte network-order address for the CALL target. -/
  mintPrincipalEncoding : String := "u32le(20)||addr20-network-order"
  /-- `dst` Principal parameter carries the ERC-20 recipient address with the
      same exact wire shape and high-limb-zero gate as `mint`. -/
  dstPrincipalEncoding : String := "u32le(20)||addr20-network-order"
  /-- Return-value handling (catalog predicate):
      * `returndatasize == 0` → success (USDT-style no-return contracts)
      * `returndatasize >= 32` → first return word must be != 0 (bool false →
        revert); `> 32` is admitted only as the leading 32 bytes (extra bytes
        ignored by this predicate — standard ERC-20 return is exactly 32B)
      * CALL `success == false` → revert (failure propagate) -/
  transferReturnValuePolicy : String :=
    "returndatasize==0→ok; >=32→first-word-must-be-nonzero; call-fail→revert"
  /-- CALL failure reverts the caller (Reference failure propagate). -/
  transferFailure : String := "propagate-revert"
  /-- Vault semantics: the EVM contract's own ERC-20 balance is the vault;
      no additional state is needed. -/
  vaultSemantics : String :=
    "contract-own-erc20-balance-is-vault; no-extra-state"
  /-- Controlled-dynamic-callee discipline: only catalog token family admits
      a parameterized address; generic dynamic callee stays fail closed. -/
  dynamicCalleeDiscipline : String :=
    "catalog-token-family-only; generic-dynamic-callee-fail-closed"
  deriving BEq, Repr, Inhabited

def erc20TokenLoweringContractV1 : Erc20TokenLoweringContractV1 := {}

/-- One admitted L1 QN binding for the EVM ERC-20 token package. -/
structure TokenBindingV1 where
  qn : String
  packageId : String
  artifactBinding : ArtifactBindingKind
  loweringContract : Erc20TokenLoweringContractV1
  admittedForMaterialization : Bool
  deriving BEq, Repr, Inhabited

/-- Package id for the EVM ERC-20 interface-standard package (no bytecode;
    binds the standard + predicates). -/
def erc20TokenPackageIdV1 : String := "evm-erc20-standard-v1"

/-- Phase E1a admitted token binding: `pf.assets.token.transfer` only. -/
def tokenBindingsV1 : Array TokenBindingV1 :=
  #[
    { qn := "pf.assets.token.transfer"
      packageId := erc20TokenPackageIdV1
      artifactBinding := erc20InterfaceStandardSkeletonV1
      loweringContract := erc20TokenLoweringContractV1
      admittedForMaterialization := true }
  ]

/-- Closed QN membership for the EVM native Phase B2 admit set. -/
def isEvmAdmittedPfAssetsQnV1 (qn : String) : Bool :=
  qn == "pf.assets.native.deposit" || qn == "pf.assets.native.transfer"
    || qn == "pf.assets.token.transfer"

/-- Full catalog membership (five QNs); non-admitted members fail closed at Plan. -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

end ProofForgeV2.Targets.Evm.PfAssetsCatalogV1
