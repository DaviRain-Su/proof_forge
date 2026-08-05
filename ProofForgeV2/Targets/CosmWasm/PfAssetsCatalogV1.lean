/-
  ADR-0029 Phase C1 — CosmWasm-owned `pf.assets` native binding catalog.
  ADR-0030 E1-CW — CosmWasm-owned `pf.assets.token.transfer` CW20 binding.

  L1 portable QNs (`pf.assets.native.deposit` / `pf.assets.native.transfer`) bind
  to CosmWasm bank module funds / BankMsg::Send. This module freezes the
  target-owned binding surface (denom, reply mode, dst encoding).

  **E1-CW scope**: `pf.assets.token.transfer` binds to a CW20 `Transfer`
  execute emitted as a `WasmMsg::Execute` SubMsg with `reply_on=never`
  (error-propagating, same sync discipline as C1 native `BankMsg::Send`).
  `mint` Principal carries the CW20 contract address (controlled dynamic
  callee — catalog token family only; generic dynamic callee stays fail
  closed). `token.transferAsync` and non-catalog QNs stay fail closed.

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
      trailing-zero limbs + lowercase bech32 charset `[a-z0-9]` body
      (which is what makes raw JSON embedding of the address
      injection-safe). -/
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

/-- CW20 interface-standard binding. E1-CW admits `token.transfer` for
    materialization; `token.transferAsync` stays fail closed. Predicate list
    is documentary; the `loweringContract` carries product-pinned decisions. -/
def cw20InterfaceStandardV1 : ArtifactBindingKind :=
  .interfaceStandard "cw20"
    #["transfer-msg", "no-fee-on-transfer", "decimals-join-via-network-profile"]

/-- Frozen lowering contract for CosmWasm CW20 `Transfer` execute
    (ADR-0030 E1-CW). Decisions are product-pinned; changes require a
    catalog/version bump. This is the **controlled dynamic callee** surface:
    only the catalog token family admits a parameterized CW20 contract
    address; generic dynamic callees remain fail closed. -/
structure Cw20TokenLoweringContractV1 where
  /-- CosmosMsg kind: `WasmMsg::Execute` targeting the CW20 contract. -/
  transferMsgKind : String := "wasm-execute"
  /-- CW20 execute message object: `{"transfer":{"recipient":"<dst>","amount":"<amount>"}}`
      packed as cosmwasm-std **Binary** (base64 of UTF-8 JSON) into
      `WasmMsg::Execute.msg`. -/
  transferExecuteMsg : String :=
    "{\"transfer\":{\"recipient\":\"<dst>\",\"amount\":\"<amount>\"}}"
  /-- SubMsg reply mode: `reply_on=never` — error-propagating atomic transfer.
      Same reply mode and semantic contract as C1 native `BankMsg::Send`:
      failure of the CW20 call fails the whole transaction (sync-atomic L1
      contract). See `NativeBankLoweringContractV1.transferReplyOn` docstring
      for the wasmd `DispatchSubmessages` verification. -/
  transferReplyOn : String := "never"
  /-- `mint` Principal parameter carries the CW20 contract address as
      exact runtime wire shape `u32le(len)||utf8-bech32-bytes` (same bech32
      grammar validation C1 uses for `dst`). Controlled dynamic callee —
      catalog token family only; this is NOT a generic dynamic callee opening. -/
  mintPrincipalEncoding : String := "u32le(len)||utf8-bech32-bytes"
  /-- `dst` Principal parameter carries the CW20 recipient address with the
      same exact wire shape and bech32 grammar validation as C1 native
      transfer `dst`. -/
  dstPrincipalEncoding : String := "u32le(len)||utf8-bech32-bytes"
  /-- `WasmMsg::Execute.funds` is empty: CW20 transfer carries no native coins.
      Entry stays non-payable for `token.transfer`; C1's funds-exactness
      discipline for native deposit is preserved (no `info.funds` movement). -/
  transferFunds : String := "empty"
  /-- CALL failure reverts the caller (Reference failure propagate). -/
  transferFailure : String := "propagate-revert"
  /-- Vault semantics: the contract's own CW20 balance is the vault;
      no funds move through `info.funds` for this API. -/
  vaultSemantics : String :=
    "contract-own-cw20-balance-is-vault; no-info-funds-movement"
  /-- Controlled-dynamic-callee discipline: only catalog token family admits
      a parameterized CW20 contract address; generic dynamic callee stays
      fail closed. -/
  dynamicCalleeDiscipline : String :=
    "catalog-token-family-only; generic-dynamic-callee-fail-closed"
  deriving BEq, Repr, Inhabited

def cw20TokenLoweringContractV1 : Cw20TokenLoweringContractV1 := {}

/-- One admitted L1 QN binding for the CosmWasm CW20 token package. -/
structure TokenBindingV1 where
  qn : String
  packageId : String
  artifactBinding : ArtifactBindingKind
  loweringContract : Cw20TokenLoweringContractV1
  admittedForMaterialization : Bool
  deriving BEq, Repr, Inhabited

/-- Package id for the CosmWasm CW20 interface-standard package (no bytecode;
    binds the standard + predicates). -/
def cw20TokenPackageIdV1 : String := "cosmwasm-cw20-standard-v1"

/-- E1-CW admitted token binding: `pf.assets.token.transfer` only. -/
def tokenBindingsV1 : Array TokenBindingV1 :=
  #[
    { qn := "pf.assets.token.transfer"
      packageId := cw20TokenPackageIdV1
      artifactBinding := cw20InterfaceStandardV1
      loweringContract := cw20TokenLoweringContractV1
      admittedForMaterialization := true }
  ]

/-- Closed QN membership for the CosmWasm admitted pf.assets set (C1 native
    + E1-CW token.transfer). `token.transferAsync` and `native.transferAsync`
    stay fail closed at Plan lowering. -/
def isCosmWasmAdmittedPfAssetsQnV1 (qn : String) : Bool :=
  qn == "pf.assets.native.deposit" || qn == "pf.assets.native.transfer"
    || qn == "pf.assets.token.transfer"

/-- Full catalog membership (five QNs); non-admitted members fail closed at Plan. -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

end ProofForgeV2.Targets.CosmWasm.PfAssetsCatalogV1
