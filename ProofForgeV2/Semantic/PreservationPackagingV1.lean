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

/-- Lift a typed returned-state business theorem to the exact raw callable-row
    obligation. State/result witnesses come only from production conformance;
    the resulting typed relation contains the same Reference step equality and
    preserves the full invocation/context/responses/vault/value/effects
    surface. -/
theorem preservationReturnedCallableV1_of_typedV1
    {State Result : Type}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (callableId : CallableIdV1)
    (callable : CallableV1)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted)
    (decodeStateComplete : ∀ logical,
      StateConformsV1 program logical →
        ∃ state, encodeState state = .ok logical)
    (decodeResultComplete : ∀ referenceValue,
      ReferenceResultConformsV1 admitted.data callable.result referenceValue →
        ∃ value, encodeResult value = referenceValue)
    (hpreserve : TypedReturnedPreservationV1 encodeState encodeResult ordinal
      ⟨admitted, hadmit⟩ callableId) :
    PreservationReturnedCallableV1 program ordinal admitted callableId
      callable := by
  intro pre invocation responses vault overlay context isInitializer postState
    referenceValue effects hcallableId hconforms heval hgate hstep
  obtain ⟨typedPre, hencodePre⟩ := decodeStateComplete pre hconforms
  obtain ⟨_hprogram, hvalidate⟩ :=
    admitReferenceProgramSliceV1_ok_implies_validate program admitted hadmit
  have hinitialized : pre.initialized = true :=
    (stateConformsV1_elim_of_validate_eq_ok program admitted.data pre hvalidate
      hconforms).1
  have hpostConforms : StateConformsV1 program postState :=
    stepReferenceSliceV1_returned_stateConformsV1_of_initialized
      program admitted pre postState invocation responses vault referenceValue
        effects hadmit hinitialized hstep
  obtain ⟨typedPost, hencodePost⟩ :=
    decodeStateComplete postState hpostConforms
  have hresultConforms :
      ReferenceResultConformsV1 admitted.data callable.result referenceValue :=
    stepReferenceSliceV1_returned_resultConformsV1 admitted pre postState
      invocation responses vault callable overlay context isInitializer
        referenceValue effects hgate hstep
  obtain ⟨typedValue, hencodeValue⟩ :=
    decodeResultComplete referenceValue hresultConforms
  have hpreInvariant : TypedInvariantV1 encodeState program ordinal typedPre :=
    ⟨pre, hencodePre, heval⟩
  have hrelation :
      TypedCallableRelationV1 encodeState encodeResult ⟨admitted, hadmit⟩
        typedPre invocation responses vault
          (.returned typedPost typedValue effects) := by
    refine ⟨pre, hencodePre, postState, hencodePost, ?_⟩
    rw [hencodeValue]
    exact hstep
  have hpostInvariant :=
    hpreserve typedPre typedPost typedValue effects invocation responses vault
      hcallableId hpreInvariant hrelation
  exact
    (typedInvariantV1_iff_eval_of_encode encodeState program ordinal typedPost
      postState hencodePost).mp hpostInvariant

/-- Lift a finite exact-row proof into exhaustive admitted-table coverage.
    `hadmittedData` must identify the row source with the same positive
    admission witness used by the production step. -/
theorem preservationReturnedCallablesV1_of_rowsV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (data : SemanticProgramDataV1)
    (hadmittedData : admitted.data = data)
    (hrows : PreservationReturnedRowsV1 program ordinal admitted data) :
    PreservationReturnedCallablesV1 program ordinal admitted := by
  intro callableId callable hlookup
  rw [hadmittedData] at hlookup
  rcases Array.getElem?_eq_some_iff.mp hlookup with ⟨hbound, heq⟩
  let index : Fin data.callables.size := ⟨callableId.toNat, hbound⟩
  have hrow := hrows index
  have hcallable : data.callables[index] = callable := by
    simpa [index] using heq
  have hcallableId : UInt32.ofNat index.val = callableId := by
    simp [index, UInt32.ofNat_toNat]
  rw [hcallableId, hcallable] at hrow
  exact hrow

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

/-- Build the initializer lifecycle base from only its successful returned
    obligation. Revert and trap are closed by the sole Reference machine's
    exact unchanged-state theorem, with invocation, responses, and vault still
    universally quantified. -/
theorem preservationBaseWithInitializerV1_of_returnedV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (initial : LogicalStateV1)
    (hinitial : initialLogicalStateV1 program = .ok initial)
    (hreturned :
      ∀ (invocation : InvocationV1)
        (responses : ExternalResponsesV1)
        (vault : ReferenceVaultSeedV1)
        (postState : LogicalStateV1)
        (value : Option ReferenceValueV1)
        (effects : Array OrderedEffectV1),
        IsInitializerInvocationV1 program invocation →
        stepReferenceSliceV1 admitted initial invocation responses vault =
          .returned postState value effects →
        evalInvariantV1 program ordinal postState = .returnedTrue) :
    PreservationBaseWithInitializerV1 program ordinal admitted := by
  refine ⟨initial, hinitial, ?_⟩
  intro invocation responses vault hinitializer
  have hfailure :=
    preservationStepFailureArmsV1 admitted initial invocation responses vault
  generalize hstep :
    stepReferenceSliceV1 admitted initial invocation responses vault = outcome
  cases outcome with
  | returned postState value effects =>
      exact hreturned invocation responses vault postState value effects
        hinitializer hstep
  | reverted reason unchangedState =>
      rw [hstep] at hfailure
      simpa [OutcomeFailureStateUnchangedV1, OutcomeRevertedUnchangedV1] using
        hfailure
  | trapped fault unchangedState =>
      rw [hstep] at hfailure
      simpa [OutcomeFailureStateUnchangedV1, OutcomeTrappedUnchangedV1] using
        hfailure

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

/-- If one production state encoder expression yields both the actual returned
    post-state and a known invariant-satisfying state, the two logical carriers
    are identical and the invariant transfers. -/
theorem preservationStepReturnedOfSameEncodingV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (encoded : Except SemanticWireErrorV1 LogicalStateV1)
    (post expected : LogicalStateV1)
    (hpost : encoded = .ok post)
    (hexpected : encoded = .ok expected)
    (heval : evalInvariantV1 program ordinal expected = .returnedTrue) :
    evalInvariantV1 program ordinal post = .returnedTrue := by
  have hpostExpected : post = expected :=
    Except.ok.inj (hpost.symm.trans hexpected)
  rw [hpostExpected]
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
