/-
  ADR-0029 Phase D — Aleo `pf.assets` disposition: **zero binding**.

  ## Research (product honesty bar)

  (a) Native vault / account-balance semantics?
      **No honest account-balance vault.** Aleo assets are primarily
      **records** (owner-bound UTXO-like objects consumed and re-minted) plus
      optional public **mappings**. That is not EVM `address(this).balance`,
      NEAR contract balance, or Solana program-owned PDA lamports. A "self
      vault" as "program-held fungible balance the program can debit/credit
      atomically in the same execution context" does not map without inventing
      a custody model the portable L1 API does not currently name.

  (b) Deposit (caller funds → self vault)?
      No portable analogue of `msg.value` / attached_deposit / message funds.
      A caller "depositing" credits would mean: caller supplies a `credits`
      record (or public balance decrement) and the program gains a record or
      mapping credit. That requires record mint/consume + ownership transfer
      rules, nonce/double-spend discipline, and proof-vs-finalize split —
      far beyond Phase D account-balance vault packaging.

  (c) Sync `transfer` vs `transferAsync`?
      * `credits.aleo/transfer_public` mutates **public** credits balances and
        runs through Aleo's private-proof + **public finalization** pipeline.
        From a nested-call perspective this is **not** the same atomic
        same-context failure-propagation contract as EVM value `CALL` or
        Solana program-direct lamports move. Treating it as portable sync
        transfer would over-claim.
      * `transfer_private` consumes/produces **records** (async-shaped
        Future / finalize paths in Leo 4). That is closer to fire-and-forget
        / multi-phase custody than to ADR-0029 sync-atomic vault debit.
      * Resolver already declines both `effect.synchronous-call` and
        `effect.asynchronous-workflow` (and event). No honest call surface
        exists on the current Aleo leaf.

  ## Record-model custody vs account-balance vault (custody v2 seed)

  Portable `pf.assets` v1 models **account-balance vault**:
    self vault balance B; deposit: caller −a, vault +a; transfer: vault −a,
    dst +a; atomic within one execution; failure rolls back both sides.

  Aleo record custody is different along at least these axes:
    1. **Identity of the asset object**: records are first-class owned objects
       with nonces; balances are often derived from record amounts, not a
       single vault scalar.
    2. **Who can spend**: record owner (private key / proof of ownership), not
       "program as address(this)" by default. Program-owned records require an
       explicit program-as-owner design (and still differ from PDA seeds).
    3. **Atomicity surface**: proof execution vs `final {}` / finalize ops can
       split private mint/consume from public mapping updates; nested
       `credits.aleo` calls do not automatically give L1-style sync failure
       propagation into the caller's vault math.
    4. **Visibility**: private records vs public mappings vs public credits
       balances have distinct disclosure/visibility requirements; portable
       transfer currently does not encode privacy class.
    5. **Official credits program**: `credits.aleo` is a **shared public
       program**, not "this program's self vault". Binding transfer to
       `credits.aleo/transfer_public` would move **caller or named account**
       public balances, not a program-local vault identity unless a separate
       program-owned public mapping / record pool is designed.

  Therefore **Aleo custody for portable assets is a v2 design** (likely a
  distinct extension or versioned vault model: program-owned records,
  public mapping vault, or explicit credits.aleo custody roles) — not a
  Phase D zero-cost alias of the accepted `pf.assets` payload (now @1.1.0).

  Disposition: **bind zero QNs**. Resolver does not advertise
  `extension.pf-assets`. Plan/lowering rejects catalog QNs with an explicit
  **unbound** diagnostic (distinct from generic "no external calls").

  **Not** a formal catalog / BuildIdentity / NetworkProfile asset registry.
-/
import ProofForgeV2.Core.RequirementIdsV1

namespace ProofForgeV2.Targets.Aleo.PfAssetsDispositionV1

open ProofForgeV2.Core.RequirementIdsV1

/-- Phase D admitted set is empty — every catalog QN is unbound on Aleo. -/
def admittedBindingsV1 : Array String := #[]

/-- Closed QN membership for the portable catalog (five names). -/
def isPfAssetsCatalogQnV1 (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

/-- Admitted membership is always false on Aleo Phase D. -/
def isAleoAdmittedPfAssetsQnV1 (_qn : String) : Bool := false

/-- Stable Plan diagnostic fragment for an unbound catalog QN. -/
def unboundCatalogDiagV1 (qn : String) : String :=
  s!"pf.assets catalog QN '{qn}' is unbound on Aleo \
(ADR-0029 Phase D zero-binding: record custody ≠ account-balance vault; \
credits.aleo is not self-vault; custody v2 required)"

end ProofForgeV2.Targets.Aleo.PfAssetsDispositionV1
