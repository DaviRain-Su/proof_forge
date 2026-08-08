import ProofForgeV2.Semantic.PreservationABI
import ProofForgeV2.Semantic.ReferenceV1

/-
  ProofForgeV2.Semantic.PreservationPackagingV1 — program-agnostic packaging
  lemmas for L1 PreservationTheoremV1 proofs.

  Extracted from the EvenCounter first instance so later programs can reuse
  failure-arm, returned-gate, post=pre, and UInt64 size packaging without
  mentioning EvenCounter constants. Instance modules (e.g. EvenCounter) must
  call these lemmas directly — no defeq-safe local aliases.

  Engineering only (track 1 business formalization packaging). Does not add a
  second State/Effect/step machine. Sole L1 step authority remains
  admitReferenceProgramSliceV1 + stepReferenceSliceV1. Pin is not required.
-/

namespace ProofForgeV2.Semantic.PreservationPackagingV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Failure-arm / Outcome packaging

    Revert and trap always reattach the exact pre-state on the production step.
    The returned branch is left as `True` so callers can share this lemma with a
    full `PreservationStepV1` case split.
-/

/-- Production step failure arms package into the Preservation ABI outcome
    helpers. Program-agnostic: no program constants or ordinals. -/
theorem preservationStepFailureArmsV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1) :
    match stepReferenceSliceV1 admitted pre invocation responses vault with
    | .returned _ _ _ => True
    | .reverted reason unchangedState =>
        OutcomeRevertedUnchangedV1 pre reason unchangedState
    | .trapped fault unchangedState =>
        OutcomeTrappedUnchangedV1 pre fault unchangedState := by
  have hfail :=
    stepReferenceSliceV1_failureStateUnchangedV1 admitted pre invocation
      responses vault
  generalize hstep :
    stepReferenceSliceV1 admitted pre invocation responses vault = outcome
  cases outcome with
  | returned post value effects =>
      trivial
  | reverted reason unchanged =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeRevertedUnchangedV1] using
        hfail
  | trapped fault unchanged =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeTrappedUnchangedV1] using
        hfail

/-! ### Returned ⇒ gate ready

    Lifecycle / invalid gates never produce a successful return. A returned
    outcome forces the ready arm of `gateInvocation`.
-/

/-- If the sole production step returns, the invocation gate is ready. -/
theorem stepReturnedImpliesGateReadyV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (post : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        .returned post value effects) :
    match gateInvocation admitted pre invocation with
    | .ready _ _ _ _ => True
    | .invalidInvocation => False
    | .lifecycle _ => False := by
  cases hgate : gateInvocation admitted pre invocation with
  | invalidInvocation =>
      have h :=
        stepReferenceSliceV1_invalidInvocation_eq admitted pre invocation
          responses vault hgate
      rw [h] at hstep
      cases hstep
  | lifecycle cand =>
      have h :=
        stepReferenceSliceV1_lifecycle_eq admitted pre invocation responses
          vault cand hgate
      rw [h] at hstep
      exact
        absurd hstep
          (finalizeLifecycle_ne_returned_publicV1 pre responses cand post value
            effects)
  | ready c o ctx ini =>
      trivial

/-! ### Returned arm when post = pre

    Carrier-identity finalization (e.g. get that re-encodes the same overlay)
    reuses the pre-state invariant evaluation.
-/

/-- Returned arm when finalize is carrier identity (`post = pre`). -/
theorem preservationStepReturnedPostEqPreV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (pre post : LogicalStateV1)
    (heval : evalInvariantV1 program ordinal pre = .returnedTrue)
    (hpost : post = pre) :
    evalInvariantV1 program ordinal post = .returnedTrue := by
  rw [hpost]
  exact heval

/-! ### UInt64 size-from-validate packaging

    Thin packaging over the sole wire-size theorem so preservation proofs can
    name size obligations without reaching into ValueBytes internals.
-/

/-- Accepted UInt64 valueBytes always have exact width 8. -/
theorem uint64BytesSizeOfValidateV1
    (types : Array TypeDeclV1)
    (typeId : TypeIdV1)
    (decl : TypeDeclV1)
    (bytes : ByteArray)
    (hlookup : types[typeId.toNat]? = some decl)
    (hshape : decl.shape = .uint 64)
    (hcan : validateValueBytesV1 types typeId bytes = .ok ()) :
    bytes.size = 8 :=
  validateValueBytesV1_uint64_size types typeId decl bytes hlookup hshape hcan

end ProofForgeV2.Semantic.PreservationPackagingV1
