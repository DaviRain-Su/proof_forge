/-
  ADR-0029 Phase C1 — CosmWasm-owned `pf.assets` native binding catalog.

  L1 portable QNs (`pf.assets.native.deposit` / `pf.assets.native.transfer`) bind
  to CosmWasm bank module funds / BankMsg::Send. This module freezes the
  target-owned binding surface (denom, reply mode, dst encoding).

  **Phase C scope**: sync native deposit + transfer only.
  Token (`pf.assets.token.*`) and async variants stay fail closed at Plan lowering.

  **Not** a formal catalog digest / BuildIdentity / NetworkProfile asset registry.
  Multi-denom and per-chain asset instance identity are NetworkProfile follow-ups.
-/
import ProofForgeV2.Core.RequirementIdsV1

namespace ProofForgeV2.Targets.CosmWasm.PfAssetsCatalogV1

open ProofForgeV2.Core.RequirementIdsV1

/-- Three-form artifact binding (ADR-0029 promotion of ADR-0028's two forms).
    Native bank denom has no CW20 contract instance — Phase C uses
    `runtimeNative` for the bank package and reserves `interfaceStandard`
    for a later CW20 token binding. -/
inductive ArtifactBindingKind where
  | runtimeNative
  | packageOwnedBytes
  | interfaceStandard (standardId : String) (predicates : Array String)
  deriving BEq, Repr, Inhabited

/-- Frozen lowering contract for CosmWasm native deposit/transfer (Phase C1).
    Decisions are product-pinned; changes require a catalog/version bump. -/
structure NativeBankLoweringContractV1 where
  /-- Single frozen native denom for Phase C. Chosen as `stake` to match
      wasmd local-chain / cosmwasm-vm mock convention (rung-1). Multi-denom
      and asset-instance identity belong to a later NetworkProfile asset
      registry — not this catalog. -/
  nativeDenom : String := "stake"
  /-- Deposit: `info.funds` must be exactly one coin `{denom, amount}`
      with denom == frozen native and amount == deposit arg (exact, not ≥). -/
  depositFundsRelation : String := "exact-one-coin-eq-amount"
  /-- Entries with no deposit statement require `info.funds == []`. -/
  nonDepositEntryFunds : String := "must-be-empty"
  /-- Transfer CosmosMsg: `BankMsg::Send { to_address, amount: [coin] }`. -/
  transferMsgKind : String := "bank-send"
  /-- SubMsg reply mode for pf.assets sync transfer.

      ## Versioned contract (coexists with CW-4 async schedule)

      * **CW-4 async `schedule`**: `WasmMsg::Execute` SubMsg with
        `reply_on=never` — fire-and-forget / no response channel (Reference
        schedule). Same-tx savepoint; submsg failure still aborts parent tx
        under wasmd `DispatchSubmessages` (verified).
      * **pf.assets sync `transfer`**: `BankMsg::Send` SubMsg with
        `reply_on=never` — **error-propagating atomic transfer**. Same
        reply mode (no reply entrypoint required), different CosmosMsg kind
        and semantic contract: failure of the bank send fails the whole
        transaction (sync-atomic L1 contract).

      Why not `ReplyOn::Error`? Error requires a `reply` entrypoint and lets
      the parent continue when reply handles the error — weaker than the
      L1 sync failure-propagation contract. wasmd documents that
      `ReplyOn::Never` returns `err` to the parent on submsg failure
      (dossier SRC-CW-002 / wasmd `msg_dispatcher.go`). Never is therefore
      the honest error-propagating mode without inventing a reply handler. -/
  transferReplyOn : String := "never"
  /-- Destination Principal runtime wire shape: `u32le(len)||utf8-bech32-bytes`
      packed into the T12 pilot leaves (`len` + 8×UInt64 body words, max 64
      body bytes). Wire identity ≠ bech32 AccAddress pin: only this exact
      framing is admitted for BankMsg `to_address`; other Principal bodies
      fail closed at runtime. Full bech32 checksum verification is left to
      the host bank module (wasmd); emitter validates length framing +
      trailing-zero limbs + printable ASCII body. -/
  dstPrincipalEncoding : String := "u32le(len)||utf8-bech32-bytes"
  /-- Opaque-effect honesty: BankMsg::Send does not execute recipient code
      (unlike EVM value CALL). Reference has no re-entrancy model; CW binding
      is still an opaque external effect on the receiver's bank balance. -/
  recipientCodeNote : String :=
    "BankMsg::Send-does-not-execute-recipient-code; \
opaque-external-effect-on-bank-balance; source-order-preserved"
  deriving BEq, Repr, Inhabited

def nativeBankLoweringContractV1 : NativeBankLoweringContractV1 := {}

/-- Frozen Phase C native denom (wasmd / mock convention). -/
def frozenNativeDenomV1 : String := nativeBankLoweringContractV1.nativeDenom

/-- One admitted L1 QN binding for the CosmWasm bank package. -/
structure NativeBindingV1 where
  qn : String
  packageId : String
  artifactBinding : ArtifactBindingKind
  loweringContract : NativeBankLoweringContractV1
  admittedForMaterialization : Bool
  deriving BEq, Repr, Inhabited

/-- Package id for CosmWasm native bank module (no contract bytecode). -/
def nativeBankPackageIdV1 : String := "cosmwasm-bank-native-v1"

/-- Phase C1 admitted bindings: native deposit + transfer only. -/
def nativeBindingsV1 : Array NativeBindingV1 :=
  #[
    { qn := "pf.assets.native.deposit"
      packageId := nativeBankPackageIdV1
      artifactBinding := .runtimeNative
      loweringContract := nativeBankLoweringContractV1
      admittedForMaterialization := true },
    { qn := "pf.assets.native.transfer"
      packageId := nativeBankPackageIdV1
      artifactBinding := .runtimeNative
      loweringContract := nativeBankLoweringContractV1
      admittedForMaterialization := true }
  ]

/-- Skeleton CW20 interface-standard binding (not admitted for materialization
    in Phase C1). Predicate list is documentary; token lowering is a later slice. -/
def cw20InterfaceStandardSkeletonV1 : ArtifactBindingKind :=
  .interfaceStandard "cw20"
    #["transfer-msg", "no-fee-on-transfer", "decimals-join-via-network-profile"]

/-- Closed QN membership for the CosmWasm native Phase C admit set. -/
def isCosmWasmAdmittedPfAssetsQnV1 (qn : String) : Bool :=
  qn == "pf.assets.native.deposit" || qn == "pf.assets.native.transfer"

/-- Full catalog membership (five QNs); non-admitted members fail closed at Plan. -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

end ProofForgeV2.Targets.CosmWasm.PfAssetsCatalogV1
