import ProofForgeV2.Semantic.PreservationPackagingV1
import ProofForgeV2.Semantic.ReferenceV1

/-
  ProofForgeV2.Semantic.PreservationShapeV1 — shape-family packaging for L1
  preservation proofs on the sole product Reference step.

  Wave-3′ mig-a2-shape + mig-b1 parity family: program-agnostic constructors +
  ready-step theorems so same-file author proofs can be `apply` + `decide`/`rfl`
  shape facts instead of replaying per-contract micro-paths. Families:

    * store-constant clear (single public UInt64 slot ← fixed literal zero)
    * view-load identity (single-slot load → re-encode; post = pre)
    * store-constant clear triple (3× public UInt64 ← zero; reuses
      triple-UInt64 machine packaging `4b7219a2b`)
    * view-load triple slot-2 (load slot 2; re-encode full overlay)
    * increment-add-two (single public UInt64 load/+2/store/reload)
    * UInt64 parity invariant (`(slot % 2) == 0` micro-path)

  Engineering only (track 1). No second State/Effect/step. No contract-specific
  constants. Pin / residual golden modules remain optional accelerators until
  wave-3′ C deletes them.
-/

namespace ProofForgeV2.Semantic.PreservationShapeV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.PreservationPackagingV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Shape constructors (rfl / decide discharge)

    Closed callables that match the production ready micro-path theorems.
    Instance proofs discharge `callable = storeConstantClearCallableV1 …` by
    `rfl` after unfolding their local defs.
-/

/-- Nullary entry: `literal constant → stateStore → stateLoad → return`.
    Store-constant clear family (ZeroCounter `clear`, MiniAmm-style single slot). -/
def storeConstantClearCallableV1
    (callableId : CallableIdV1)
    (entryName : Option String)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (constantBytes : ByteArray) : CallableV1 := {
  id := callableId
  kind := .entry
  name := entryName
  params := #[]
  result := { typeId := uint64TypeId, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[
      { result := some { valueId := 0, typeId := uint64TypeId },
        op := .literal uint64TypeId constantBytes },
      { result := none, op := .stateStore stateId 0 },
      { result := some { valueId := 1, typeId := uint64TypeId },
        op := .stateLoad stateId }
    ]
    terminator := .return_ (some 1)
  }]
  loopBounds := #[]
  invariantSteps := none
}

/-- Nullary view: `stateLoad → return`. Get/view identity family. -/
def viewLoadCallableV1
    (callableId : CallableIdV1)
    (viewName : Option String)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1) : CallableV1 := {
  id := callableId
  kind := .view
  name := viewName
  params := #[]
  result := { typeId := uint64TypeId, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[{
      result := some { valueId := 0, typeId := uint64TypeId }
      op := .stateLoad stateId
    }]
    terminator := .return_ (some 0)
  }]
  loopBounds := #[]
  invariantSteps := none
}

/-- Nullary entry: store the same constant into slots 0/1/2, return load of 2.
    Reuses triple-UInt64 ready packaging. -/
def storeConstantClearTripleCallableV1
    (callableId : CallableIdV1)
    (entryName : Option String)
    (uint64TypeId : TypeIdV1)
    (constantBytes : ByteArray) : CallableV1 := {
  id := callableId
  kind := .entry
  name := entryName
  params := #[]
  result := { typeId := uint64TypeId, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[
      { result := some { valueId := 0, typeId := uint64TypeId },
        op := .literal uint64TypeId constantBytes },
      { result := none, op := .stateStore 0 0 },
      { result := some { valueId := 1, typeId := uint64TypeId },
        op := .literal uint64TypeId constantBytes },
      { result := none, op := .stateStore 1 1 },
      { result := some { valueId := 2, typeId := uint64TypeId },
        op := .literal uint64TypeId constantBytes },
      { result := none, op := .stateStore 2 2 },
      { result := some { valueId := 3, typeId := uint64TypeId },
        op := .stateLoad 2 }
    ]
    terminator := .return_ (some 3)
  }]
  loopBounds := #[]
  invariantSteps := none
}

/-- Nullary view over a three-slot overlay: load slot 2 and return. -/
def viewLoadTripleSlot2CallableV1
    (callableId : CallableIdV1)
    (viewName : Option String)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1) : CallableV1 := {
  id := callableId
  kind := .view
  name := viewName
  params := #[]
  result := { typeId := uint64TypeId, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[{
      result := some { valueId := 0, typeId := uint64TypeId }
      op := .stateLoad stateId
    }]
    terminator := .return_ (some 0)
  }]
  loopBounds := #[]
  invariantSteps := none
}

/-- Nullary entry: `stateLoad → literal 2 → add → stateStore → stateLoad → return`.
    Single-slot UInt64 increment-by-two family (EvenCounter `increment`). -/
def incrementAddTwoCallableV1
    (callableId : CallableIdV1)
    (entryName : Option String)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1) : CallableV1 := {
  id := callableId
  kind := .entry
  name := entryName
  params := #[]
  result := { typeId := uint64TypeId, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[
      { result := some { valueId := 0, typeId := uint64TypeId },
        op := .stateLoad stateId },
      { result := some { valueId := 1, typeId := uint64TypeId },
        op := .literal uint64TypeId two8BytesV1 },
      { result := some { valueId := 2, typeId := uint64TypeId },
        op := .binary .add 0 1 },
      { result := none, op := .stateStore stateId 2 },
      { result := some { valueId := 3, typeId := uint64TypeId },
        op := .stateLoad stateId }
    ]
    terminator := .return_ (some 3)
  }]
  loopBounds := #[]
  invariantSteps := none
}

/-- Nullary invariant: `stateLoad → literal 2 → mod → literal 0 → eq → return`.
    Single-slot UInt64 parity predicate `(count % 2) == 0` (EvenCounter `even`).
    `invariantSteps` is the closed production value for this five-instruction body. -/
def uint64ParityInvariantCallableV1
    (callableId : CallableIdV1)
    (invName : Option String)
    (uint64TypeId boolTypeId : TypeIdV1)
    (stateId : StateIdV1)
    (visibility : VisibilityV1)
    (invariantSteps : Option UInt64) : CallableV1 := {
  id := callableId
  kind := .invariant
  name := invName
  params := #[]
  result := { typeId := boolTypeId, visibility }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[
      { result := some { valueId := 0, typeId := uint64TypeId },
        op := .stateLoad stateId },
      { result := some { valueId := 1, typeId := uint64TypeId },
        op := .literal uint64TypeId two8BytesV1 },
      { result := some { valueId := 2, typeId := uint64TypeId },
        op := .binary .mod 0 1 },
      { result := some { valueId := 3, typeId := uint64TypeId },
        op := .literal uint64TypeId zero8BytesV1 },
      { result := some { valueId := 4, typeId := boolTypeId },
        op := .binary .eq 2 3 }
    ]
    terminator := .return_ (some 4)
  }]
  loopBounds := #[]
  invariantSteps
}

/-! ### Ready-step shape theorems (sole `stepReferenceSliceV1`)

    Thin wrappers: gate carries the constructor spelling so author proofs only
    need shape equality + type/state/can hyps.
-/

/-- Store-constant clear (zero) with empty responses returns the encode of zero. -/
theorem stepReturned_of_readyStoreConstantClearZeroV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[zero8BytesV1] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (storeConstantClearCallableV1 callableId entryName uint64TypeId
            stateId zero8BytesV1)
          #[countBytes] context false) :
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v0) #[] := by
  simpa [storeConstantClearCallableV1] using
    stepReferenceSliceV1_ready_clear_returned admitted pre invocation data
      countBytes uint64TypeId stateId stateName callableId entryName post
      responses vault context hadmitted_data htypeU hstate hstateId hcanZero
      hinit hencode hrespEmpty hgate

/-- Nonempty responses after store-constant clear trap with exact pre. -/
theorem stepTrapped_of_readyStoreConstantClearZero_nonemptyResponsesV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hrespNonempty : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (storeConstantClearCallableV1 callableId entryName uint64TypeId
            stateId zero8BytesV1)
          #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  simpa [storeConstantClearCallableV1] using
    stepReferenceSliceV1_ready_clear_nonempty_responses_traps admitted pre
      invocation data countBytes uint64TypeId stateId stateName callableId
      entryName responses vault context hadmitted_data htypeU hstate hstateId
      hcanZero hrespNonempty hgate

/-- View-load with empty responses returns the encode of the overlay. -/
theorem stepReturned_of_readyViewLoadV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (viewLoadCallableV1 callableId viewName uint64TypeId stateId)
          #[countBytes] context false) :
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := countBytes }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v0) #[] := by
  simpa [viewLoadCallableV1] using
    stepReferenceSliceV1_ready_get_returned admitted pre invocation data
      countBytes uint64TypeId stateId stateName callableId viewName post
      responses vault context hadmitted_data htypeU hstate hstateId hcan hinit
      hencode hrespEmpty hgate

/-- Nonempty responses after view-load trap with exact pre. -/
theorem stepTrapped_of_readyViewLoad_nonemptyResponsesV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hrespNonempty : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (viewLoadCallableV1 callableId viewName uint64TypeId stateId)
          #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  simpa [viewLoadCallableV1] using
    stepReferenceSliceV1_ready_get_nonempty_responses_traps admitted pre
      invocation data countBytes uint64TypeId stateId stateName callableId
      viewName responses vault context hadmitted_data htypeU hstate hstateId
      hcan hrespNonempty hgate

/-- Triple store-constant clear (all zero) with empty responses. -/
theorem stepReturned_of_readyStoreConstantClearTripleZeroV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (name0 name1 name2 : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hst0 : data.logicalState[0]? = some {
      id := 0, name := name0, typeId := uint64TypeId, visibility := .public_ })
    (hst1 : data.logicalState[1]? = some {
      id := 1, name := name1, typeId := uint64TypeId, visibility := .public_ })
    (hst2 : data.logicalState[2]? = some {
      id := 2, name := name2, typeId := uint64TypeId, visibility := .public_ })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[zero8BytesV1, zero8BytesV1, zero8BytesV1] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (storeConstantClearTripleCallableV1 callableId entryName uint64TypeId
            zero8BytesV1)
          #[b0, b1, b2] context false) :
    let vZ : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some vZ) #[] := by
  simpa [storeConstantClearTripleCallableV1] using
    stepReferenceSliceV1_ready_clear_triple_returned admitted pre invocation
      data b0 b1 b2 uint64TypeId name0 name1 name2 callableId entryName post
      responses vault context hadmitted_data htypeU hst0 hst1 hst2 hcanZero
      hinit hencode hrespEmpty hgate

/-- Nonempty responses after triple clear trap with exact pre. -/
theorem stepTrapped_of_readyStoreConstantClearTripleZero_nonemptyResponsesV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (name0 name1 name2 : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hst0 : data.logicalState[0]? = some {
      id := 0, name := name0, typeId := uint64TypeId, visibility := .public_ })
    (hst1 : data.logicalState[1]? = some {
      id := 1, name := name1, typeId := uint64TypeId, visibility := .public_ })
    (hst2 : data.logicalState[2]? = some {
      id := 2, name := name2, typeId := uint64TypeId, visibility := .public_ })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hrespNonempty : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (storeConstantClearTripleCallableV1 callableId entryName uint64TypeId
            zero8BytesV1)
          #[b0, b1, b2] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  simpa [storeConstantClearTripleCallableV1] using
    stepReferenceSliceV1_ready_clear_triple_nonempty_responses_traps admitted
      pre invocation data b0 b1 b2 uint64TypeId name0 name1 name2 callableId
      entryName responses vault context hadmitted_data htypeU hst0 hst1 hst2
      hcanZero hrespNonempty hgate

/-- Triple view-load of slot 2 with empty responses re-encodes the overlay. -/
theorem stepReturned_of_readyViewLoadTripleSlot2V1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 2)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId b2 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[b0, b1, b2] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (viewLoadTripleSlot2CallableV1 callableId viewName uint64TypeId
            stateId)
          #[b0, b1, b2] context false) :
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := b2 }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v0) #[] := by
  simpa [viewLoadTripleSlot2CallableV1] using
    stepReferenceSliceV1_ready_get_triple_slot2_returned admitted pre
      invocation data b0 b1 b2 uint64TypeId stateId stateName callableId
      viewName post responses vault context hadmitted_data htypeU hstate
      hstateId hcan hinit hencode hrespEmpty hgate

/-- Nonempty responses after triple view-load trap with exact pre. -/
theorem stepTrapped_of_readyViewLoadTripleSlot2_nonemptyResponsesV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 2)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId b2 = .ok ())
    (hrespNonempty : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (viewLoadTripleSlot2CallableV1 callableId viewName uint64TypeId
            stateId)
          #[b0, b1, b2] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  simpa [viewLoadTripleSlot2CallableV1] using
    stepReferenceSliceV1_ready_get_triple_slot2_nonempty_responses_traps
      admitted pre invocation data b0 b1 b2 uint64TypeId stateId stateName
      callableId viewName responses vault context hadmitted_data htypeU hstate
      hstateId hcan hrespNonempty hgate

/-- Increment-add-two with empty responses returns the encode of sum (+2). -/
theorem stepReturned_of_readyIncrementAddTwoV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (incrementAddTwoCallableV1 callableId entryName uint64TypeId stateId)
          #[countBytes] context false) :
    let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    let v2 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := sumBytes }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v2) #[] := by
  simpa [incrementAddTwoCallableV1] using
    stepReferenceSliceV1_ready_increment_returned admitted pre invocation data
      countBytes uint64TypeId stateId stateName callableId entryName post
      responses vault context hadmitted_data htypeU hstate hstateId hcan hcanTwo
      hnoOverflow hinit hencode hrespEmpty hgate

/-- Nonempty responses after increment-add-two trap with exact pre. -/
theorem stepTrapped_of_readyIncrementAddTwo_nonemptyResponsesV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hrespNonempty : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (incrementAddTwoCallableV1 callableId entryName uint64TypeId stateId)
          #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  simpa [incrementAddTwoCallableV1] using
    stepReferenceSliceV1_ready_increment_nonempty_responses_traps admitted pre
      invocation data countBytes uint64TypeId stateId stateName callableId
      entryName responses vault context hadmitted_data htypeU hstate hstateId
      hcan hcanTwo hnoOverflow hrespNonempty hgate

/-- Overflowing increment-add-two cannot produce a returned outcome. -/
theorem stepNotReturned_of_readyIncrementAddTwo_overflowV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (post : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hoverflow : ¬ leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (incrementAddTwoCallableV1 callableId entryName uint64TypeId stateId)
          #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault ≠
      .returned post value effects := by
  simpa [incrementAddTwoCallableV1] using
    stepReferenceSliceV1_ready_increment_overflow_not_returned admitted pre
      invocation data countBytes uint64TypeId stateId stateName callableId
      entryName responses vault context post value effects hadmitted_data
      htypeU hstate hstateId hcan hcanTwo hoverflow hgate

/-! ### Preservation-step outcome packaging

    Given a known ready shape and a known post-state evaluation, package the
    returned arm of `PreservationStepV1` without replaying the micro-path.
-/

/-- Returned arm after store-constant clear zero: post is the zero encode;
    eval-true on that post discharges the preservation returned arm. -/
theorem preservationReturned_of_readyStoreConstantClearZeroV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[zero8BytesV1] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (storeConstantClearCallableV1 callableId entryName uint64TypeId
            stateId zero8BytesV1)
          #[countBytes] context false)
    (heval_post : evalInvariantV1 program ordinal post = .returnedTrue)
    (post' : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        .returned post' value effects) :
    evalInvariantV1 program ordinal post' = .returnedTrue := by
  have hret :=
    stepReturned_of_readyStoreConstantClearZeroV1 admitted pre invocation data
      countBytes uint64TypeId stateId stateName callableId entryName post
      responses vault context hadmitted_data htypeU hstate hstateId hcanZero
      hinit hencode hrespEmpty hgate
  have h1 := hstep
  have h2 := hret
  rw [h2] at h1
  injection h1 with hpost _ _
  simpa [hpost.symm] using heval_post

/-- Returned arm after view-load when encode of overlay recovers pre. -/
theorem preservationReturned_of_readyViewLoad_postEqPreV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (viewLoadCallableV1 callableId viewName uint64TypeId stateId)
          #[countBytes] context false)
    (hpost_pre : post = pre)
    (heval_pre : evalInvariantV1 program ordinal pre = .returnedTrue)
    (post' : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        .returned post' value effects) :
    evalInvariantV1 program ordinal post' = .returnedTrue := by
  have hret :=
    stepReturned_of_readyViewLoadV1 admitted pre invocation data countBytes
      uint64TypeId stateId stateName callableId viewName post responses vault
      context hadmitted_data htypeU hstate hstateId hcan hinit hencode
      hrespEmpty hgate
  have h1 := hstep
  have h2 := hret
  rw [h2] at h1
  injection h1 with hpost _ _
  have hpost' : post' = pre := by
    have := hpost.symm
    exact this.trans hpost_pre
  exact preservationStepReturnedPostEqPreV1 program ordinal pre post' heval_pre
    hpost'

/-- Returned arm after triple store-constant clear zero. -/
theorem preservationReturned_of_readyStoreConstantClearTripleZeroV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (name0 name1 name2 : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hst0 : data.logicalState[0]? = some {
      id := 0, name := name0, typeId := uint64TypeId, visibility := .public_ })
    (hst1 : data.logicalState[1]? = some {
      id := 1, name := name1, typeId := uint64TypeId, visibility := .public_ })
    (hst2 : data.logicalState[2]? = some {
      id := 2, name := name2, typeId := uint64TypeId, visibility := .public_ })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[zero8BytesV1, zero8BytesV1, zero8BytesV1] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (storeConstantClearTripleCallableV1 callableId entryName uint64TypeId
            zero8BytesV1)
          #[b0, b1, b2] context false)
    (heval_post : evalInvariantV1 program ordinal post = .returnedTrue)
    (post' : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        .returned post' value effects) :
    evalInvariantV1 program ordinal post' = .returnedTrue := by
  have hret :=
    stepReturned_of_readyStoreConstantClearTripleZeroV1 admitted pre invocation
      data b0 b1 b2 uint64TypeId name0 name1 name2 callableId entryName post
      responses vault context hadmitted_data htypeU hst0 hst1 hst2 hcanZero
      hinit hencode hrespEmpty hgate
  have h1 := hstep
  have h2 := hret
  rw [h2] at h1
  injection h1 with hpost _ _
  simpa [hpost.symm] using heval_post

/-- Returned arm after triple view-load when encode of overlay recovers pre. -/
theorem preservationReturned_of_readyViewLoadTripleSlot2_postEqPreV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 2)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId b2 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[b0, b1, b2] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (viewLoadTripleSlot2CallableV1 callableId viewName uint64TypeId
            stateId)
          #[b0, b1, b2] context false)
    (hpost_pre : post = pre)
    (heval_pre : evalInvariantV1 program ordinal pre = .returnedTrue)
    (post' : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        .returned post' value effects) :
    evalInvariantV1 program ordinal post' = .returnedTrue := by
  have hret :=
    stepReturned_of_readyViewLoadTripleSlot2V1 admitted pre invocation data b0
      b1 b2 uint64TypeId stateId stateName callableId viewName post responses
      vault context hadmitted_data htypeU hstate hstateId hcan hinit hencode
      hrespEmpty hgate
  have h1 := hstep
  have h2 := hret
  rw [h2] at h1
  injection h1 with hpost _ _
  have hpost' : post' = pre := by
    have := hpost.symm
    exact this.trans hpost_pre
  exact preservationStepReturnedPostEqPreV1 program ordinal pre post' heval_pre
    hpost'

/-- Returned arm after increment-add-two when post keeps the invariant. -/
theorem preservationReturned_of_readyIncrementAddTwoV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready
          (incrementAddTwoCallableV1 callableId entryName uint64TypeId stateId)
          #[countBytes] context false)
    (heval_post : evalInvariantV1 program ordinal post = .returnedTrue)
    (post' : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        .returned post' value effects) :
    evalInvariantV1 program ordinal post' = .returnedTrue := by
  have hret :=
    stepReturned_of_readyIncrementAddTwoV1 admitted pre invocation data
      countBytes uint64TypeId stateId stateName callableId entryName post
      responses vault context hadmitted_data htypeU hstate hstateId hcan hcanTwo
      hnoOverflow hinit hencode hrespEmpty hgate
  have h1 := hstep
  have h2 := hret
  rw [h2] at h1
  injection h1 with hpost _ _
  simpa [hpost.symm] using heval_post

end ProofForgeV2.Semantic.PreservationShapeV1
