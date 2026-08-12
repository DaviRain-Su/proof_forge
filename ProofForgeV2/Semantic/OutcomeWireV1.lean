import ProofForgeV2.Semantic.ReferenceV1

/-
  ProofForgeV2.Semantic.OutcomeWireV1 — versioned tagged retained Outcome
  artifact (engineering).

  Closes the SPEC-SEM-001 / TST-SEM-002/003 packaging gap named in
  semantic-core.md and MIGRATION_MATRIX: in-memory OutcomeV1 carriers become
  an exact tagged byte envelope with re-encode identity and SHA-256 digest.

  Engineering only:
    * not formal TASK-D2-07 / TST-SEM-002/003 completion
    * not EV retained-artifact binding / formal evidence
    * not a target adapter (EVM/Solana/… → OutcomeV1)
    * not a substitute for proof-forge.evidence.v1 observations

  Wire framing reuses WireV1 tagged/magic helpers. Program-relative valueBytes
  validation remains the caller's responsibility (Reference step /
  StateConforms); transport encodes LogicalState / ReferenceValue bytes as-is.
-/

namespace ProofForgeV2.Semantic.OutcomeWireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.ReferenceV1

/-- Local alias so field projection elaborates against the foundation structure
    even while `ReferenceV1` is open for Outcome carriers. -/
abbrev LogicalStateCarrierV1 :=
  ProofForgeV2.Semantic.InvariantABI.LogicalStateV1

/-- Schema id (evidence / catalog join key; not embedded in the magic spine). -/
def referenceOutcomeSchemaIdV1 : String :=
  "proof-forge.reference-outcome.v1"

/-- Root magic consumed by the envelope decoder. -/
def referenceOutcomeMagicV1 : String := "pf.reference-outcome.v1"

/-- Private-ctor retained artifact: exact canonical envelope bytes. -/
structure ReferenceOutcomeArtifactV1 where
  private mk ::
  canonicalBytes : ByteArray

private def err (e : SemanticWireErrorV1) : Except SemanticWireErrorV1 α :=
  .error e

/-! ### Leaf encode/decode -/

private def encodeOccurrenceV1 (occ : EffectOccurrenceV1) :
    Except SemanticWireErrorV1 ByteArray :=
  encodeTagged "occurrence" #[
    encodeU32le occ.effectId,
    encodeU32le occ.occurrence
  ]

private def decodeOccurrenceV1 : Decoder EffectOccurrenceV1 :=
  withTaggedNesting fun c => do
    let ((), c) ← expectTag "occurrence" 2 c
    let (effectId, c) ← decodeU32le c
    let (occurrence, c) ← decodeU32le c
    pure ({ effectId, occurrence }, c)

private def encodeReferenceValueV1 (v : ReferenceValueV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let payload ← encodeByteArray v.valueBytes
  encodeTagged "value" #[encodeU32le v.typeId, payload]

private def decodeReferenceValueV1 : Decoder ReferenceValueV1 :=
  withTaggedNesting fun c => do
    let ((), c) ← expectTag "value" 2 c
    let (typeId, c) ← decodeU32le c
    let (valueBytes, c) ← decodeByteArray maxCanonicalValueBytes c
    pure ({ typeId, valueBytes }, c)

private def encodeLogicalStateV1 (state : LogicalStateCarrierV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let values ← encodeByteArray state.canonicalValues
  encodeTagged "logicalState" #[encodeBool state.initialized, values]

private def decodeLogicalStateV1 : Decoder LogicalStateCarrierV1 :=
  withTaggedNesting fun c => do
    let ((), c) ← expectTag "logicalState" 2 c
    let (initialized, c) ← decodeBool c
    let (canonicalValues, c) ← decodeByteArray maxCanonicalProgramBytes c
    pure (⟨initialized, canonicalValues⟩, c)

private def encodeStandardRevertCodeV1 (code : StandardRevertCodeV1) :
    Except SemanticWireErrorV1 ByteArray :=
  let tag : UInt8 :=
    match code with
    | .arithmeticOverflow => 0
    | .arithmeticUnderflow => 1
    | .divisionByZero => 2
    | .invalidShift => 3
    | .castOutOfRange => 4
    | .indexOutOfBounds => 5
    | .boundExceeded => 6
    | .assertionFailed => 7
    | .uninitialized => 8
    | .alreadyInitialized => 9
  encodeTagged "standard" #[encodeU8 tag]

private def decodeStandardRevertCodeV1 : Decoder StandardRevertCodeV1 :=
  withTaggedNesting fun c => do
    let ((), c) ← expectTag "standard" 1 c
    let (tag, c) ← decodeU8 c
    match tag.toNat with
    | 0 => pure (.arithmeticOverflow, c)
    | 1 => pure (.arithmeticUnderflow, c)
    | 2 => pure (.divisionByZero, c)
    | 3 => pure (.invalidShift, c)
    | 4 => pure (.castOutOfRange, c)
    | 5 => pure (.indexOutOfBounds, c)
    | 6 => pure (.boundExceeded, c)
    | 7 => pure (.assertionFailed, c)
    | 8 => pure (.uninitialized, c)
    | 9 => pure (.alreadyInitialized, c)
    | _ => err .badScalar

private def encodeSemanticFaultV1 (fault : SemanticFaultV1) :
    Except SemanticWireErrorV1 ByteArray :=
  let tag : UInt8 :=
    match fault with
    | .invalidInvocation => 0
    | .invalidExternalResponse => 1
    | .invalidCore => 2
    | .resourceExhausted => 3
    | .unreachable => 4
    | .internalInvariant => 5
  encodeTagged "fault" #[encodeU8 tag]

private def decodeSemanticFaultV1 : Decoder SemanticFaultV1 :=
  withTaggedNesting fun c => do
    let ((), c) ← expectTag "fault" 1 c
    let (tag, c) ← decodeU8 c
    match tag.toNat with
    | 0 => pure (.invalidInvocation, c)
    | 1 => pure (.invalidExternalResponse, c)
    | 2 => pure (.invalidCore, c)
    | 3 => pure (.resourceExhausted, c)
    | 4 => pure (.unreachable, c)
    | 5 => pure (.internalInvariant, c)
    | _ => err .badScalar

private def encodeSemanticRevertV1 (reason : SemanticRevertV1) :
    Except SemanticWireErrorV1 ByteArray :=
  match reason with
  | .declared errorId args => do
      let argsBytes ← encodeArray encodeReferenceValueV1 args
      encodeTagged "declared" #[encodeU32le errorId, argsBytes]
  | .standard code =>
      encodeStandardRevertCodeV1 code
  | .externalCallReverted occurrence => do
      let occ ← encodeOccurrenceV1 occurrence
      encodeTagged "externalCallReverted" #[occ]

private def decodeSemanticRevertV1 : Decoder SemanticRevertV1 :=
  withTaggedNesting fun c => do
    let (tag, c) ← decodeTag c
    match tag with
    | "declared" =>
        let ((), c) ← decodeFieldCount 2 c
        let (errorId, c) ← decodeU32le c
        let (args, c) ← decodeArray maxArrayElements decodeReferenceValueV1 c
        pure (.declared errorId args, c)
    | "standard" =>
        let ((), c) ← decodeFieldCount 1 c
        let (codeTag, c) ← decodeU8 c
        let code ← match codeTag.toNat with
          | 0 => pure StandardRevertCodeV1.arithmeticOverflow
          | 1 => pure .arithmeticUnderflow
          | 2 => pure .divisionByZero
          | 3 => pure .invalidShift
          | 4 => pure .castOutOfRange
          | 5 => pure .indexOutOfBounds
          | 6 => pure .boundExceeded
          | 7 => pure .assertionFailed
          | 8 => pure .uninitialized
          | 9 => pure .alreadyInitialized
          | _ => err .badScalar
        pure (.standard code, c)
    | "externalCallReverted" =>
        let ((), c) ← decodeFieldCount 1 c
        let (occ, c) ← decodeOccurrenceV1 c
        pure (.externalCallReverted occ, c)
    | _ => err .badTag

private def encodeOrderedEffectPayloadV1 (payload : OrderedEffectPayloadV1) :
    Except SemanticWireErrorV1 ByteArray :=
  match payload with
  | .event eventId args => do
      let argsBytes ← encodeArray encodeReferenceValueV1 args
      encodeTagged "event" #[encodeU32le eventId, argsBytes]
  | .externalCall callee args => do
      let qn ← encodeQualifiedName callee
      let argsBytes ← encodeArray encodeReferenceValueV1 args
      encodeTagged "externalCall" #[qn, argsBytes]
  | .schedule callee args => do
      let qn ← encodeQualifiedName callee
      let argsBytes ← encodeArray encodeReferenceValueV1 args
      encodeTagged "schedule" #[qn, argsBytes]

private def decodeOrderedEffectPayloadV1 : Decoder OrderedEffectPayloadV1 :=
  withTaggedNesting fun c => do
    let (tag, c) ← decodeTag c
    match tag with
    | "event" =>
        let ((), c) ← decodeFieldCount 2 c
        let (eventId, c) ← decodeU32le c
        let (args, c) ← decodeArray maxArrayElements decodeReferenceValueV1 c
        pure (.event eventId args, c)
    | "externalCall" =>
        let ((), c) ← decodeFieldCount 2 c
        let (callee, c) ← decodeQualifiedName c
        let (args, c) ← decodeArray maxArrayElements decodeReferenceValueV1 c
        pure (.externalCall callee args, c)
    | "schedule" =>
        let ((), c) ← decodeFieldCount 2 c
        let (callee, c) ← decodeQualifiedName c
        let (args, c) ← decodeArray maxArrayElements decodeReferenceValueV1 c
        pure (.schedule callee args, c)
    | _ => err .badTag

private def encodeOrderedEffectV1 (effect : OrderedEffectV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let occ ← encodeOccurrenceV1 effect.occurrence
  let payload ← encodeOrderedEffectPayloadV1 effect.payload
  encodeTagged "effect" #[occ, payload]

private def decodeOrderedEffectV1 : Decoder OrderedEffectV1 :=
  withTaggedNesting fun c => do
    let ((), c) ← expectTag "effect" 2 c
    let (occurrence, c) ← decodeOccurrenceV1 c
    let (payload, c) ← decodeOrderedEffectPayloadV1 c
    pure ({ occurrence, payload }, c)

/-- Encode the in-memory OutcomeV1 body (no root magic). -/
def encodeOutcomeDataV1 (outcome : OutcomeV1) :
    Except SemanticWireErrorV1 ByteArray :=
  match outcome with
  | .returned postState value effects => do
      let state ← encodeLogicalStateV1 postState
      let valueBytes ← encodeOption encodeReferenceValueV1 value
      let effectsBytes ← encodeArray encodeOrderedEffectV1 effects
      encodeTagged "returned" #[state, valueBytes, effectsBytes]
  | .reverted reason unchangedState => do
      let reasonBytes ← encodeSemanticRevertV1 reason
      let state ← encodeLogicalStateV1 unchangedState
      encodeTagged "reverted" #[reasonBytes, state]
  | .trapped fault unchangedState => do
      let faultBytes ← encodeSemanticFaultV1 fault
      let state ← encodeLogicalStateV1 unchangedState
      encodeTagged "trapped" #[faultBytes, state]

private def decodeOutcomeDataBodyV1 : Decoder OutcomeV1 := fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "returned" =>
      let ((), c) ← decodeFieldCount 3 c
      let (postState, c) ← decodeLogicalStateV1 c
      let (value, c) ← decodeOption decodeReferenceValueV1 c
      let (effects, c) ← decodeArray maxArrayElements decodeOrderedEffectV1 c
      pure (.returned postState value effects, c)
  | "reverted" =>
      let ((), c) ← decodeFieldCount 2 c
      let (reason, c) ← decodeSemanticRevertV1 c
      let (unchangedState, c) ← decodeLogicalStateV1 c
      pure (.reverted reason unchangedState, c)
  | "trapped" =>
      let ((), c) ← decodeFieldCount 2 c
      let (fault, c) ← decodeSemanticFaultV1 c
      let (unchangedState, c) ← decodeLogicalStateV1 c
      pure (.trapped fault unchangedState, c)
  | _ => err .badTag

/-- Transport decoder for the Outcome body (no root magic). -/
def decodeOutcomeDataV1 : Decoder OutcomeV1 :=
  withTaggedNesting decodeOutcomeDataBodyV1

/-- Root envelope: magic-prefix || tagged Outcome body. -/
def encodeOutcomeEnvelopeV1 (outcome : OutcomeV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let body ← encodeOutcomeDataV1 outcome
  let framed := (encodeMagicPrefix referenceOutcomeMagicV1).append body
  unless framed.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  pure framed

/-- Mint the private retained artifact (structure = successful encode). -/
def mintReferenceOutcomeArtifactV1 (outcome : OutcomeV1) :
    Except SemanticWireErrorV1 ReferenceOutcomeArtifactV1 := do
  let bytes ← encodeOutcomeEnvelopeV1 outcome
  pure ⟨bytes⟩

/-- SHA-256 of exact canonical envelope bytes. -/
def referenceOutcomeDigestV1 (artifact : ReferenceOutcomeArtifactV1) : Digest :=
  sha256Bytes artifact.canonicalBytes

/-- Transport decode of the root envelope; full-consume. -/
def decodeOutcomeEnvelopeDataV1 (bytes : ByteArray) :
    Except SemanticWireErrorV1 OutcomeV1 := do
  unless bytes.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  let c := start bytes
  let ((), c) ← consumeMagic referenceOutcomeMagicV1 c
  let (outcome, c) ← decodeOutcomeDataV1 c
  finish c
  pure outcome

/-- Carrier decode: transport → re-encode → exact byte identity. -/
def decodeReferenceOutcomeArtifactV1 (bytes : ByteArray) :
    Except SemanticWireErrorV1 ReferenceOutcomeArtifactV1 := do
  let outcome ← decodeOutcomeEnvelopeDataV1 bytes
  let reencoded ← encodeOutcomeEnvelopeV1 outcome
  unless reencoded == bytes do
    return ← err .nonCanonical
  pure ⟨bytes⟩

/-- Decode artifact to the structural OutcomeV1 (after carrier identity). -/
def outcomeOfArtifactV1 (artifact : ReferenceOutcomeArtifactV1) :
    Except SemanticWireErrorV1 OutcomeV1 :=
  decodeOutcomeEnvelopeDataV1 artifact.canonicalBytes

end ProofForgeV2.Semantic.OutcomeWireV1
