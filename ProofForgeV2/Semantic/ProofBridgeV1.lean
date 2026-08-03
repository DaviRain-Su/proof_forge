import ProofForgeV2.Semantic.WireV1

/-
  ProofForgeV2.Semantic.ProofBridgeV1 — exact product-byte proof bridge.

  Purpose: let proof authors close `validateSemanticProgramV1` (and therefore
  the wire half of `InvariantTheoremV1`) from sole production encode/decode
  witnesses, without hand-writing hundreds of structure phases and without
  trusting a private constructor to invent validation.

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool
    * no second semantic model or residual encoder
    * private constructor is not a public mint; sole mint requires
      `encodeSemanticProgramDataV1 data = .ok bytes` and
      `decodeSemanticProgramDataV1 bytes = .ok data`
    * product kernel remains `SemanticProgramV1.canonicalBytes`

  Remaining gap (documented, not forged):
    parametric `decodeSemanticProgramDataV1 (encode data) = .ok data` for
    arbitrary admitted data. Normalize already produces the encode witness;
    full codec round-trip refinement is still open beyond fixture-level proofs.
-/

namespace ProofForgeV2.Semantic.ProofBridgeV1

open ProofForgeV2.Semantic.WireV1

/-- Proof-carrying validated carrier. Fields are private so validation cannot
    be asserted by construction; the only public mint is
    `ofEncodeDecode` below. -/
structure ValidatedSemanticProgramV1 where
  private mkPrivate ::
  private program_ : SemanticProgramV1
  private data_ : SemanticProgramDataV1
  private hvalidate_ : validateSemanticProgramV1 program_ = .ok data_

/-- Exact product carrier bytes (sole semantic identity). -/
def ValidatedSemanticProgramV1.program (v : ValidatedSemanticProgramV1) :
    SemanticProgramV1 :=
  v.program_

/-- Structure-gated program data recovered by production validation. -/
def ValidatedSemanticProgramV1.data (v : ValidatedSemanticProgramV1) :
    SemanticProgramDataV1 :=
  v.data_

/-- Exact production validation equality for this carrier. -/
def ValidatedSemanticProgramV1.hvalidate (v : ValidatedSemanticProgramV1) :
    validateSemanticProgramV1 v.program = .ok v.data :=
  v.hvalidate_

/-- Sole public mint: exact encode of `data` to `bytes` plus transport decode
    recovering the same `data`. Uses the parametric Wire bridge; does not
    bypass validation. -/
def ValidatedSemanticProgramV1.ofEncodeDecode
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data) :
    ValidatedSemanticProgramV1 :=
  {
    program_ := ⟨bytes⟩
    data_ := data
    hvalidate_ :=
      validateSemanticProgramV1_eq_ok_of_encode_decode data bytes hencode hdecode
  }

/-- Definitional: minted carrier program bytes are exactly the encode output. -/
theorem ValidatedSemanticProgramV1.ofEncodeDecode_program
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data) :
    (ValidatedSemanticProgramV1.ofEncodeDecode data bytes hencode hdecode).program =
      ⟨bytes⟩ :=
  rfl

/-- Definitional: minted carrier data is the encode input. -/
theorem ValidatedSemanticProgramV1.ofEncodeDecode_data
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data) :
    (ValidatedSemanticProgramV1.ofEncodeDecode data bytes hencode hdecode).data =
      data :=
  rfl

/-- Encode-success witness extracted from Normalize's sole carrier encoder. -/
structure NormalizeEncodeWitnessV1 where
  data : SemanticProgramDataV1
  bytes : ByteArray
  hencode : encodeSemanticProgramDataV1 data = .ok bytes

/-- Package a successful `encodeSemanticProgramDataV1` as a Normalize encode
    witness. `encodeCarrierV1` success is definitionally this shape. -/
def NormalizeEncodeWitnessV1.ofEncode
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    NormalizeEncodeWitnessV1 :=
  ⟨data, bytes, hencode⟩

/-- Carrier constructed from an encode witness (product `SemanticProgramV1`). -/
def NormalizeEncodeWitnessV1.program (w : NormalizeEncodeWitnessV1) :
    SemanticProgramV1 :=
  ⟨w.bytes⟩

/-- Lift an encode witness to a validated carrier once transport decode is
    refined. This is the Normalize-preservation half of the bridge. -/
def NormalizeEncodeWitnessV1.toValidated
    (w : NormalizeEncodeWitnessV1)
    (hdecode : decodeSemanticProgramDataV1 w.bytes = .ok w.data) :
    ValidatedSemanticProgramV1 :=
  ValidatedSemanticProgramV1.ofEncodeDecode w.data w.bytes w.hencode hdecode

/-- Encode success implies structure (re-export for proof authors). -/
theorem structure_of_encode_witness (w : NormalizeEncodeWitnessV1) :
    validateSemanticProgramStructureV1 w.data = .ok () :=
  encodeSemanticProgramDataV1_ok_implies_structure w.data w.bytes w.hencode

/-- Validate from encode witness + decode refinement (re-export). -/
theorem validate_of_encode_witness
    (w : NormalizeEncodeWitnessV1)
    (hdecode : decodeSemanticProgramDataV1 w.bytes = .ok w.data) :
    validateSemanticProgramV1 w.program = .ok w.data :=
  validateSemanticProgramV1_eq_ok_of_encode_decode w.data w.bytes w.hencode hdecode

end ProofForgeV2.Semantic.ProofBridgeV1
