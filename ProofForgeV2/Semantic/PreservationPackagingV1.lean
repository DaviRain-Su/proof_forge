import ProofForgeV2.Semantic.PreservationABI
import ProofForgeV2.Semantic.ReferenceV1

/-
  ProofForgeV2.Semantic.PreservationPackagingV1 — program-agnostic packaging
  lemmas for L1 PreservationTheoremV1 proofs.

  Reusable failure-arm, returned-gate, post=pre, and UInt64 size packaging.
  Business source files call these lemmas through generated subject declarations;
  the product package contains no per-contract proof module or byte alias.

  ## Author recipe (unpinned / arbitrary contracts)

  ```text
  theorem AuthorThm : P.ProofPreserving.inv := by
    -- Goal: PreservationTheoremV1 P.Proof.subjectProgramV1 ordinal
    -- Use packaging lemmas + program-specific step facts; no contract registry
    -- or package-owned subject golden is involved.
    ...
  ```

  Engineering only (track 1 business formalization packaging). Does not add a
  second State/Effect/step machine. Sole L1 step authority remains
  `admitReferenceProgramSliceV1` + `stepReferenceSliceV1`.
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

/-! ### Per-callable returned obligations → universal preservation

    Authors prove only successful returned-state preservation for every exact
    callable-table row. The composer obtains exhaustive row coverage from the
    production ready gate and closes revert/trap with the production unchanged
    theorem. No input surface is hidden or reinterpreted.
-/

/-- Existing universal step proofs can be projected into the per-callable
    returned obligation surface. This is a compatibility direction only; it
    does not execute or classify a callable. -/
theorem preservationReturnedCallablesV1_of_stepV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (hpreserve : PreservationStepV1 program ordinal admitted) :
    PreservationReturnedCallablesV1 program ordinal admitted := by
  intro callableId callable _hlookup
  intro pre invocation responses vault overlay context isInitializer
    postState value effects _hcallableId hconforms heval _hgate hstep
  have hresult := hpreserve pre invocation responses vault hconforms heval
  rw [hstep] at hresult
  exact hresult

/-- Compose exhaustive per-callable returned obligations with the generic
    production failure arms into the universal one-step preservation ABI. -/
theorem preservationStepV1_of_returnedCallablesV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (hreturned : PreservationReturnedCallablesV1 program ordinal admitted) :
    PreservationStepV1 program ordinal admitted := by
  intro pre invocation responses vault hconforms heval
  have hfail :=
    preservationStepFailureArmsV1 admitted pre invocation responses vault
  generalize hstep :
    stepReferenceSliceV1 admitted pre invocation responses vault = outcome
  cases outcome with
  | returned postState value effects =>
      have hready :=
        stepReturnedImpliesGateReadyV1 admitted pre invocation responses vault
          postState value effects hstep
      cases hgate : gateInvocation admitted pre invocation with
      | invalidInvocation =>
          rw [hgate] at hready
          exact False.elim hready
      | lifecycle candidate =>
          rw [hgate] at hready
          exact False.elim hready
      | ready callable overlay context isInitializer =>
          have hlookup :=
            (gateInvocation_ready_callable_lookup admitted pre invocation
              callable overlay context isInitializer hgate).1
          exact hreturned invocation.callableId callable hlookup pre invocation
            responses vault overlay context isInitializer postState value effects
            rfl hconforms heval hgate hstep
  | reverted reason unchangedState =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeRevertedUnchangedV1] using
        hfail
  | trapped fault unchangedState =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeTrappedUnchangedV1] using
        hfail

/-- Select the positive initializer lifecycle base without changing its exact
    production-step obligation. -/
theorem preservationBaseV1_of_initializerV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (hhasInitializer : HasInitializerV1 program)
    (hbase : PreservationBaseWithInitializerV1 program ordinal admitted) :
    PreservationBaseV1 program ordinal admitted :=
  Or.inl ⟨hhasInitializer, hbase⟩

/-- Select the positive product initial-state base for a program with no
    initializer. -/
theorem preservationBaseV1_of_noInitializerV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (hnoInitializer : ¬ HasInitializerV1 program)
    (hbase : PreservationBaseNoInitializerV1 program ordinal) :
    PreservationBaseV1 program ordinal admitted :=
  Or.inr ⟨hnoInitializer, hbase⟩

/-- Assemble the exact public preservation theorem from one positive admission,
    the selected lifecycle base, and exhaustive per-callable returned proofs.
    Revert/trap and invalid/lifecycle-only coverage are discharged by the
    production machine lemmas above. -/
theorem preservationTheoremV1_of_callableObligationsV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (hordinal : ordinal.toNat < program.invariants.size)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted)
    (hbase : PreservationBaseV1 program ordinal admitted)
    (hreturned : PreservationReturnedCallablesV1 program ordinal admitted) :
    PreservationTheoremV1 program ordinal := by
  exact ⟨hordinal, admitted, hadmit, hbase,
    preservationStepV1_of_returnedCallablesV1 program ordinal admitted
      hreturned⟩

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
