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

/-- Eliminate production conformance into a successful initialized decode.
    Generated typed models use the returned production value array directly;
    no model-side conformance predicate or slot parser is introduced. -/
theorem decodeInitializedStateValuesV1_exists_of_stateConformsV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hconforms : StateConformsV1 program state) :
    ∃ values : Array ByteArray,
      decodeInitializedStateValuesV1 data state = .ok values := by
  obtain ⟨hinitialized, values, hdecode⟩ :=
    stateConformsV1_elim_of_validate_eq_ok program data state hvalidate hconforms
  refine ⟨values, ?_⟩
  simp [decodeInitializedStateValuesV1, hinitialized, hdecode,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Successful initialized decoding re-encodes the exact original carrier
    through the sole production logical-state codec. -/
theorem encodeLogicalStateValuesV1_of_decodeInitializedStateValuesV1
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (values : Array ByteArray)
    (hdecode : decodeInitializedStateValuesV1 data state = .ok values) :
    encodeLogicalStateValuesV1 data true values = .ok state := by
  cases hinitialized : state.initialized with
  | false =>
      simp [decodeInitializedStateValuesV1, hinitialized, err] at hdecode
  | true =>
      have hproduction :
          decodeLogicalStateValuesV1 data state = .ok values := by
        simpa [decodeInitializedStateValuesV1, hinitialized, Pure.pure,
          Except.pure, Bind.bind, Except.bind] using hdecode
      simpa [hinitialized] using
        encodeLogicalStateValuesV1_of_decodeLogicalStateValuesV1
          data state values hproduction

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

/-- Re-encoding a production-validated UInt64 payload after typed projection
    recovers the same bytes. The validator supplies the exact width; endian
    interpretation is the Reference/Wire alignment theorem. -/
theorem encodeU64le_uint64OfCanonicalValueBytesV1
    (types : Array TypeDeclV1)
    (typeId : TypeIdV1)
    (decl : TypeDeclV1)
    (bytes : ByteArray)
    (hlookup : types[typeId.toNat]? = some decl)
    (hshape : decl.shape = .uint 64)
    (hcanonical : validateValueBytesV1 types typeId bytes = .ok ()) :
    encodeU64le (uint64OfCanonicalValueBytesV1 bytes) = bytes := by
  apply encodeU64le_uint64OfLeBytesToNatV1_of_size
  exact validateValueBytesV1_uint64_size
    types typeId decl bytes hlookup hshape hcanonical

/-- A UInt64 slot returned at a known source-order index by the production
    decoder survives typed projection and Wire re-encoding byte-for-byte. -/
theorem encodeU64le_uint64OfDecodedStateValueV1
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (values : Array ByteArray)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok values)
    (index : Nat)
    (hindex : index < values.size)
    (stateDecl : StateDeclV1)
    (typeDecl : TypeDeclV1)
    (hstateDecl : data.logicalState[index]? = some stateDecl)
    (htypeDecl : data.types[stateDecl.typeId.toNat]? = some typeDecl)
    (hshape : typeDecl.shape = .uint 64) :
    encodeU64le (uint64OfCanonicalValueBytesV1 values[index]!) =
      values[index]! := by
  have hvalue : values[index]? = some values[index]! := by
    simp [hindex]
  have hcanonical :=
    validateValueBytesV1_of_decodeLogicalStateValuesV1_getElem
      data state values hdecode index stateDecl values[index]!
      hstateDecl hvalue
  exact encodeU64le_uint64OfCanonicalValueBytesV1
    data.types stateDecl.typeId typeDecl values[index]!
    htypeDecl hshape hcanonical

end ProofForgeV2.Semantic.StateModelV1
