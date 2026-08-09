import ProofForgeV2.Semantic.ReferenceV1

/-!
  ProofForgeV2.Semantic.StateModelV1 — generic typed-state projection seams.

  This module does not define transition semantics. Generated contract models
  use these scalar projections only after the production logical-state decoder
  has validated canonical value bytes; execution remains exclusively owned by
  `ReferenceMachineV1`.
-/

namespace ProofForgeV2.Semantic.StateModelV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Decode a business-state carrier only after the lifecycle is initialized.
    The per-slot framing and canonical-value checks are delegated unchanged to
    the production logical-state decoder. -/
def decodeInitializedStateValuesV1
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1) : Except SemanticWireErrorV1 (Array ByteArray) := do
  unless state.initialized do
    return ← err .nonCanonical
  decodeLogicalStateValuesV1 data state

/-- A successful initialized business-state encode decodes through the same
    production logical-state codec to the exact source-order value array. -/
theorem decodeInitializedStateValuesV1_of_encodeLogicalStateValuesV1
    (data : SemanticProgramDataV1)
    (values : Array ByteArray)
    (state : LogicalStateV1)
    (hencode : encodeLogicalStateValuesV1 data true values = .ok state) :
    decodeInitializedStateValuesV1 data state = .ok values := by
  have hdecode :=
    decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
      data true values state hencode
  have hinitialized : state.initialized = true :=
    state.initialized_of_encodeLogicalStateValuesV1 data true values hencode
  simp [decodeInitializedStateValuesV1, hinitialized, hdecode,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- A successful initialized encode is a conforming state for the exact
    validated carrier. This is only a bridge into the production
    `StateConformsV1` predicate; it does not introduce a model-side checker. -/
theorem stateConformsV1_of_encodeLogicalStateValuesV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (values : Array ByteArray)
    (state : LogicalStateV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hencode : encodeLogicalStateValuesV1 data true values = .ok state) :
    StateConformsV1 program state := by
  apply stateConformsV1_intro_of_validate_eq_ok program data state values hvalidate
  · exact state.initialized_of_encodeLogicalStateValuesV1 data true values hencode
  · exact decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
      data true values state hencode

/-- Bool projection for bytes already accepted by `validateValueBytesV1` at a
    Bool slot. The comparison is against the production Wire encoding. -/
def boolOfCanonicalValueBytesV1 (bytes : ByteArray) : Bool :=
  bytes == encodeBool true

/-- UInt64 projection used by the Reference machine itself, narrowed back to
    UInt64 after production canonical validation has established width 8. -/
def uint64OfCanonicalValueBytesV1 (bytes : ByteArray) : UInt64 :=
  UInt64.ofNat (leBytesToNatV1 bytes)

theorem boolOfCanonicalValueBytesV1_encodeBool (value : Bool) :
    boolOfCanonicalValueBytesV1 (encodeBool value) = value := by
  cases value <;> rfl

theorem uint64OfCanonicalValueBytesV1_encodeU64le (value : UInt64) :
    uint64OfCanonicalValueBytesV1 (encodeU64le value) = value := by
  unfold uint64OfCanonicalValueBytesV1
  rw [leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat]

end ProofForgeV2.Semantic.StateModelV1
