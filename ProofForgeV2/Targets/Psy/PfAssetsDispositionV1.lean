/-
  ADR-0029 Phase D — Psy `pf.assets` disposition: **zero binding**.

  Research (product honesty bar matching Quint A5 async rejection):

  (a) Native vault / balance semantics?
      No. Psy CFC surface has user-partitioned CSTATE / Felt computation, not
      a contract-held native denomination. Felt = Goldilocks is the arithmetic
      domain, not an asset unit. There is no Tool Lock / psy-vm / prover gate
      that could validate a vault debit/credit effect. Emitting
      `__invoke_sync#<Felt>(hash,hash,args)` for a catalog QN would be pure
      source sugar with no honest value movement — **fake modeling**.

  (b) Deposit (caller funds → self vault)?
      No analogue of EVM `msg.value`, Solana outer-signer System CPI, CW
      `info.funds`, or NEAR `attached_deposit`. Cross-user value ingress is
      not a frozen Psy intrinsic on the current research surface.

  (c) Sync `transfer` / async `transferAsync`?
      Sync: `__invoke_sync` is source-only; no runtime proof of atomic vault
      debit + dst credit + failure propagation. Async: schedule already
      declines (no deferred crosscall form); must not alias sync.

  Disposition: **bind zero QNs**. Resolver does not advertise
  `extension.pf-assets`. Plan/lowering rejects every catalog QN with an
  explicit **unbound** diagnostic (distinct from non-catalog L0 call, which
  still lowers to hashed `__invoke_sync` as today).

  **Not** a formal catalog / BuildIdentity / NetworkProfile asset registry.
-/
import ProofForgeV2.Core.RequirementIdsV1

namespace ProofForgeV2.Targets.Psy.PfAssetsDispositionV1

open ProofForgeV2.Core.RequirementIdsV1

/-- Phase D admitted set is empty — every catalog QN is unbound on Psy. -/
def admittedBindingsV1 : Array String := #[]

/-- Closed QN membership for the portable catalog (five names). -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

/-- Admitted membership is always false on Psy Phase D. -/
def isPsyAdmittedPfAssetsQnV1 (_qn : String) : Bool := false

/-- Stable Plan diagnostic fragment for an unbound catalog QN. -/
def unboundCatalogDiagV1 (qn : String) : String :=
  s!"pf.assets catalog QN '{qn}' is unbound on Psy \
(ADR-0029 Phase D zero-binding: no honest native vault/deposit/balance surface; \
must not alias __invoke_sync as value transfer)"

end ProofForgeV2.Targets.Psy.PfAssetsDispositionV1
