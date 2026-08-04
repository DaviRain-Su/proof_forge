import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.SimpleClosureCertV1

/-
  ProofForgeV2.Semantic.AuthorWireCertV1 — production wire certificate bridge
  for raw same-file author theorems on literal-true simple-closure invariants.

  Purpose: package the only product-safe path from wire encode/decode witnesses
  plus an explicit `LiteralTrueInvariantWitnessV1` into a kernel-checked
  `InvariantTheoremV1` on exact product bytes (the elaborator subject spine).

  Composition (each step is a production equality, no second model):

    encodeSemanticProgramDataV1 data = .ok bytes
    decodeSemanticProgramDataV1 bytes = .ok data
    LiteralTrueInvariantWitnessV1 data ordinal …
      ──► ValidatedSemanticProgramV1.ofEncodeDecode
      ──► SimpleClosureCertV1.invariantTheoremV1_of_literalTrueWitness
      ──► InvariantTheoremV1 ⟨bytes⟩ ordinal

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO
    * no private validation mint; sole wire validation is `ofEncodeDecode`
    * theorem bodies never enter ProgramV1 / sourceHash / semanticHash
    * does not relax InlineProofCertifier audit (Environment FQN still required)
    * does not forge transport decode — authors (or a sibling decode lane) must
      supply `hdecode` as an exact production premise

  Decode blocker (document, do not forge): parametric or fixture
  `decodeSemanticProgramDataV1 bytes = .ok data` remains the sole free premise
  once structure+encode are closed for a carrier. A parallel decode lane may
  discharge it later; this module stays decode-hypothesis honest.
-/

namespace ProofForgeV2.Semantic.AuthorWireCertV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.SimpleClosureCertV1
open ProofForgeV2.Semantic.WireV1

/-- Phased wire certificate for a nullary literal-`true` invariant author theorem.

    Fields are production equalities only. There is no structure field here:
    structure is implied by a successful `hencode` (and re-checked by
    `validate` via encode+decode). Shape/table premises live in `hwitness`. -/
structure LiteralTrueAuthorWireCertV1
    (data : SemanticProgramDataV1)
    (bytes : ByteArray)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String) : Prop where
  /-- Sole product encoder success for these exact bytes. -/
  hencode : encodeSemanticProgramDataV1 data = .ok bytes
  /-- Transport decode recovers the same data (free until a decode cert exists). -/
  hdecode : decodeSemanticProgramDataV1 bytes = .ok data
  /-- Explicit literal-true micro-shape witness (table lookups + Bool-true). -/
  hwitness :
    LiteralTrueInvariantWitnessV1 data invariantOrdinal invariant
      boolTypeId rootName visibility typeName

/-- Assemble a certificate from the three production premises. -/
def LiteralTrueAuthorWireCertV1.ofParts
    (data : SemanticProgramDataV1)
    (bytes : ByteArray)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data)
    (hwitness :
      LiteralTrueInvariantWitnessV1 data invariantOrdinal invariant
        boolTypeId rootName visibility typeName) :
    LiteralTrueAuthorWireCertV1 data bytes invariantOrdinal invariant
      boolTypeId rootName visibility typeName :=
  ⟨hencode, hdecode, hwitness⟩

/-- Mint the private-ctor validated carrier from a completed wire certificate. -/
def LiteralTrueAuthorWireCertV1.toValidated
    (data : SemanticProgramDataV1)
    (bytes : ByteArray)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (c : LiteralTrueAuthorWireCertV1 data bytes invariantOrdinal invariant
      boolTypeId rootName visibility typeName) :
    ValidatedSemanticProgramV1 :=
  ValidatedSemanticProgramV1.ofEncodeDecode data bytes c.hencode c.hdecode

/-- Definitional: certificate bytes are the carrier program bytes. -/
theorem LiteralTrueAuthorWireCertV1.toValidated_program
    (data : SemanticProgramDataV1)
    (bytes : ByteArray)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (c : LiteralTrueAuthorWireCertV1 data bytes invariantOrdinal invariant
      boolTypeId rootName visibility typeName) :
    (LiteralTrueAuthorWireCertV1.toValidated data bytes invariantOrdinal
      invariant boolTypeId rootName visibility typeName c).program =
      { canonicalBytes := bytes } :=
  ValidatedSemanticProgramV1.ofEncodeDecode_program data bytes c.hencode c.hdecode

/-- Definitional: certificate data is the carrier data. -/
theorem LiteralTrueAuthorWireCertV1.toValidated_data
    (data : SemanticProgramDataV1)
    (bytes : ByteArray)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (c : LiteralTrueAuthorWireCertV1 data bytes invariantOrdinal invariant
      boolTypeId rootName visibility typeName) :
    (LiteralTrueAuthorWireCertV1.toValidated data bytes invariantOrdinal
      invariant boolTypeId rootName visibility typeName c).data = data :=
  ValidatedSemanticProgramV1.ofEncodeDecode_data data bytes c.hencode c.hdecode

/-- Kernel-checked author bridge: wire certificate ⇒ `InvariantTheoremV1` on
    exact product bytes. Uses only production encode/decode validation and the
    parametric simple-closure evaluator theorem. -/
theorem invariantTheoremV1_of_literalTrueAuthorWireCert
    (data : SemanticProgramDataV1)
    (bytes : ByteArray)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (c : LiteralTrueAuthorWireCertV1 data bytes invariantOrdinal invariant
      boolTypeId rootName visibility typeName) :
    InvariantTheoremV1 { canonicalBytes := bytes } invariantOrdinal := by
  let carrier :=
    LiteralTrueAuthorWireCertV1.toValidated data bytes invariantOrdinal
      invariant boolTypeId rootName visibility typeName c
  have hdata : carrier.data = data :=
    LiteralTrueAuthorWireCertV1.toValidated_data data bytes invariantOrdinal
      invariant boolTypeId rootName visibility typeName c
  have hwitness' :
      LiteralTrueInvariantWitnessV1 carrier.data invariantOrdinal invariant
        boolTypeId rootName visibility typeName := by
    simpa [hdata] using c.hwitness
  have hclosed :
      InvariantTheoremV1 carrier.program invariantOrdinal :=
    invariantTheoremV1_of_literalTrueWitness carrier invariantOrdinal invariant
      boolTypeId rootName visibility typeName hwitness'
  have hprogram : carrier.program = { canonicalBytes := bytes } :=
    LiteralTrueAuthorWireCertV1.toValidated_program data bytes invariantOrdinal
      invariant boolTypeId rootName visibility typeName c
  simpa [hprogram] using hclosed

/-- Same conclusion from a Normalize encode witness plus decode + shape
    witness (authors who already hold `encodeCarrierV1` success). -/
theorem invariantTheoremV1_of_normalizeEncode_literalTrue
    (w : NormalizeEncodeWitnessV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (hdecode : decodeSemanticProgramDataV1 w.bytes = .ok w.data)
    (hwitness :
      LiteralTrueInvariantWitnessV1 w.data invariantOrdinal invariant
        boolTypeId rootName visibility typeName) :
    InvariantTheoremV1 w.program invariantOrdinal := by
  have c :=
    LiteralTrueAuthorWireCertV1.ofParts w.data w.bytes invariantOrdinal
      invariant boolTypeId rootName visibility typeName w.hencode hdecode hwitness
  have hclosed :=
    invariantTheoremV1_of_literalTrueAuthorWireCert w.data w.bytes
      invariantOrdinal invariant boolTypeId rootName visibility typeName c
  simpa [NormalizeEncodeWitnessV1.program] using hclosed

end ProofForgeV2.Semantic.AuthorWireCertV1
