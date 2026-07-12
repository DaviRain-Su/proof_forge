/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Token auth models as feature flags (gap-analysis route step 4)

There is **no** common auth denominator across chains:

| Model | Home | Ops |
|-------|------|-----|
| allowance | ERC-20 | approve / allowance / transferFrom |
| authority | SPL | mint/freeze/delegate authority + ATA |
| storageDeposit | NEP-141 | storage_deposit before receive |
| transferCall | NEP-141 | ft_transfer_call + callback |

Portable **core** is transfer / balanceOf / mint / burn (capability-gated).
Auth models are optional features: materialize on home host, honest-reject
elsewhere. Do not fake ERC-20 allowance on NEP-141.

Does **not** import `Contract.Token` (avoids cycle); callers pass mintable/burnable
flags from TokenSpec features.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Contract.Compliance

namespace ProofForge.Contract.TokenAuth

open ProofForge.Contract.Compliance

/-- Divergent token authorization / permission models. -/
inductive TokenAuthFeature where
  | allowance
  | authority
  | storageDeposit
  | transferCall
  deriving BEq, DecidableEq, Repr

def TokenAuthFeature.id : TokenAuthFeature → String
  | .allowance => "token.auth.allowance"
  | .authority => "token.auth.authority"
  | .storageDeposit => "token.auth.storage_deposit"
  | .transferCall => "token.auth.transfer_call"

def allAuthFeatures : Array TokenAuthFeature :=
  #[.allowance, .authority, .storageDeposit, .transferCall]

/-- Portable token core operations (common product surface). -/
inductive TokenCoreOp where
  | transfer
  | balanceOf
  | mint
  | burn
  deriving BEq, DecidableEq, Repr

def TokenCoreOp.id : TokenCoreOp → String
  | .transfer => "token.core.transfer"
  | .balanceOf => "token.core.balanceOf"
  | .mint => "token.core.mint"
  | .burn => "token.core.burn"

def allCoreOps : Array TokenCoreOp := #[.transfer, .balanceOf, .mint, .burn]

inductive AuthSupport where
  | full
  | experimental
  | reject
  | noLane
  deriving BEq, DecidableEq, Repr

def AuthSupport.id : AuthSupport → String
  | .full => "full"
  | .experimental => "experimental"
  | .reject => "reject"
  | .noLane => "no-lane"

/-- Support matrix for auth features on primary TokenSpec targets. -/
def authSupportOnTarget (targetId : String) (feature : TokenAuthFeature) : AuthSupport :=
  match targetId, feature with
  | "evm", .allowance => .experimental
  | "evm", .authority => .reject
  | "evm", .storageDeposit => .reject
  | "evm", .transferCall => .reject
  | "solana-sbpf-asm", .allowance => .reject
  | "solana-sbpf-asm", .authority => .experimental
  | "solana-sbpf-asm", .storageDeposit => .reject
  | "solana-sbpf-asm", .transferCall => .reject
  | "wasm-near", .allowance => .reject
  | "wasm-near", .authority => .reject
  | "wasm-near", .storageDeposit => .experimental
  | "wasm-near", .transferCall => .experimental
  | _, _ => .noLane

def authEvidenceRequirement? (targetId : String) (feature : TokenAuthFeature) :
    Option (StandardManifest × AdapterRef) :=
  match targetId, feature with
  | "evm", .allowance =>
      some (erc20Manifest, { id := "proof-forge.evm.erc20", version := "1" })
  | "solana-sbpf-asm", .authority =>
      some (splTokenManifest, { id := "proof-forge.solana.spl-token", version := "1" })
  | "wasm-near", .storageDeposit =>
      some (nep145Manifest, { id := "proof-forge.near.nep145", version := "1" })
  | "wasm-near", .transferCall =>
      some (nep141Manifest, { id := "proof-forge.near.nep141", version := "1" })
  | _, _ => none

def authSupportOnTargetWithEvidence (targetId : String) (feature : TokenAuthFeature)
    (claims : Array EvidenceClaim) : AuthSupport :=
  let support := authSupportOnTarget targetId feature
  match support, authEvidenceRequirement? targetId feature with
  | .experimental, some (manifest, adapter) =>
      if claims.any (fun claim => claim.isExactFor manifest adapter) then .full
      else .experimental
  | _, _ => support

/-- Core ops on a primary target, **capability-gated** by mintable/burnable flags.

* `transfer` / `balanceOf` — always available on TokenSpec lanes.
* `mint` — requires `hasMintable`; else honest reject.
* `burn` — requires `hasBurnable`; else honest reject.
-/
def coreOpSupportOnTarget (targetId : String) (op : TokenCoreOp)
    (hasMintable : Bool := false) (hasBurnable : Bool := false) : AuthSupport :=
  match targetId with
  | "evm" | "solana-sbpf-asm" | "wasm-near" =>
      match op with
      | .transfer | .balanceOf => .experimental
      | .mint => if hasMintable then .experimental else .reject
      | .burn => if hasBurnable then .experimental else .reject
  | _ => .noLane

structure AuthMaterialization where
  targetId : String
  feature : TokenAuthFeature
  nativeOps : Array String
  note : String
  deriving Repr, BEq

structure CoreOpMaterialization where
  targetId : String
  op : TokenCoreOp
  nativeOps : Array String
  note : String
  deriving Repr, BEq

def authReject (targetId : String) (feature : TokenAuthFeature) (reason : String) : String :=
  s!"TokenAuth: target `{targetId}` cannot materialize `{feature.id}`: {reason}"

def coreOpReject (targetId : String) (op : TokenCoreOp) (reason : String) : String :=
  s!"TokenAuth: target `{targetId}` cannot materialize `{op.id}`: {reason}"

/-- Materialize a core op under mintable/burnable gates (or honest-reject). -/
def materializeCoreOp (targetId : String) (op : TokenCoreOp)
    (hasMintable : Bool := false) (hasBurnable : Bool := false) :
    Except String CoreOpMaterialization :=
  match coreOpSupportOnTarget targetId op hasMintable hasBurnable, targetId, op with
  | .experimental, tid, .transfer =>
      .ok {
        targetId := tid, op := op
        nativeOps := #["transfer"]
        note := "portable transfer (ERC-20 / SPL / NEP-141)"
      }
  | .experimental, tid, .balanceOf =>
      .ok {
        targetId := tid, op := op
        nativeOps := #["balanceOf", "balance_of", "ft_balance_of"]
        note := "portable balance query"
      }
  | .experimental, tid, .mint =>
      .ok {
        targetId := tid, op := op
        nativeOps := #["mint"]
        note := "requires TokenFeature.mintable"
      }
  | .experimental, tid, .burn =>
      .ok {
        targetId := tid, op := op
        nativeOps := #["burn"]
        note := "requires TokenFeature.burnable"
      }
  | .reject, tid, .mint =>
      .error (coreOpReject tid op
        "mint is capability-gated: enable TokenFeature.mintable on TokenSpec")
  | .reject, tid, .burn =>
      .error (coreOpReject tid op
        "burn is capability-gated: enable TokenFeature.burnable on TokenSpec")
  | .reject, tid, op' =>
      .error (coreOpReject tid op' "core op rejected on this target")
  | .noLane, tid, op' =>
      .error (coreOpReject tid op' "no TokenSpec lane for target")
  | .full, tid, op' =>
      .error (coreOpReject tid op' "internal: full support requires bound compliance evidence")

/-- Materialize an auth feature or honest-reject. -/
def materializeAuth (targetId : String) (feature : TokenAuthFeature) :
    Except String AuthMaterialization :=
  match authSupportOnTarget targetId feature, targetId, feature with
  | .experimental, "evm", .allowance =>
      .ok {
        targetId := targetId, feature := feature
        nativeOps := #["approve", "allowance", "transferFrom"]
        note := "ERC-20 allowance model"
      }
  | .experimental, "solana-sbpf-asm", .authority =>
      .ok {
        targetId := targetId, feature := feature
        nativeOps := #["mint_authority", "freeze_authority", "approve_delegate", "revoke"]
        note := "SPL authority + delegate; not ERC-20 allowance"
      }
  | .experimental, "wasm-near", .storageDeposit =>
      .ok {
        targetId := targetId, feature := feature
        nativeOps := #["storage_deposit", "storage_balance_of"]
        note := "NEP-145 storage deposit/balance subset; unregister is not materialized"
      }
  | .experimental, "wasm-near", .transferCall =>
      .ok {
        targetId := targetId, feature := feature
        nativeOps := #["ft_transfer_call"]
        note := "NEP-141 transfer-call with receiver callback (async)"
      }
  | .reject, _, _ =>
      .error (authReject targetId feature
        s!"auth model not available on this host (support={AuthSupport.id .reject}); \
use home-host feature or drop it — no silent polyfill")
  | .noLane, _, _ =>
      .error (authReject targetId feature "no TokenSpec lane for target")
  | .full, _, _ =>
      .error (authReject targetId feature "internal: full support without materialize row")
  | .experimental, _, _ =>
      .error (authReject targetId feature "internal: experimental support without materialize row")

def primaryTokenTargetIds : Array String :=
  #["evm", "solana-sbpf-asm", "wasm-near"]

end ProofForge.Contract.TokenAuth
