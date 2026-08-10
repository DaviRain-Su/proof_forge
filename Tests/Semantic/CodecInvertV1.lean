/-
  Tests.Semantic.CodecInvertV1 — mig-a1 foundation + fields + callable + root:
  MidOffsetInvert, Visibility, InvariantDecl, empty tables/Requirements,
  Type.Bool, QN singleton, CallableKind, ValueDef, LoopBound, Op.Constant/
  StateLoad/Commit/Literal, Term.Return, empty callables, array one/two lift,
  DecodeEncodeRoundtripGoal composition discharge.

  Does not claim full RootFieldInvert for arbitrary programs.
-/
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1
import ProofForgeV2.Semantic.Wire.CodecInvertCallableV1
import ProofForgeV2.Semantic.Wire.CodecInvertRootV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.CodecInvertV1

open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Positive theorem: public Visibility mid-offset invert at nesting 0. -/
theorem visibility_public_mid_nest0 :
    decodeVisibilityV1
        ⟨taggedHeaderBytesV1 "Visibility.Public" 0, 0, 0⟩ =
      .ok (.public_,
        ⟨taggedHeaderBytesV1 "Visibility.Public" 0,
          (taggedHeaderBytesV1 "Visibility.Public" 0).size, 0⟩) := by
  simpa [ByteArray.append_empty] using
    decodeVisibility_public_midV1 ByteArray.empty ByteArray.empty 0 (by decide)

/-- Positive theorem: encode success ⇒ mid-offset decode for all Visibility. -/
theorem visibility_of_encode_all (vis : VisibilityV1) :
    ∃ b, encodeVisibilityV1 vis = .ok b ∧
      decodeVisibilityV1 ⟨b, 0, 0⟩ = .ok (vis, ⟨b, b.size, 0⟩) := by
  match vis with
  | .public_ =>
      refine ⟨taggedHeaderBytesV1 "Visibility.Public" 0, encodeVisibility_public_eq, ?_⟩
      simpa [ByteArray.append_empty] using
        decodeVisibility_of_encode_midV1 .public_
          (taggedHeaderBytesV1 "Visibility.Public" 0) ByteArray.empty ByteArray.empty 0
          (by decide) encodeVisibility_public_eq
  | .private_ =>
      refine ⟨taggedHeaderBytesV1 "Visibility.Private" 0, encodeVisibility_private_eq, ?_⟩
      simpa [ByteArray.append_empty] using
        decodeVisibility_of_encode_midV1 .private_
          (taggedHeaderBytesV1 "Visibility.Private" 0) ByteArray.empty ByteArray.empty 0
          (by decide) encodeVisibility_private_eq
  | .commitment =>
      refine ⟨taggedHeaderBytesV1 "Visibility.Commitment" 0,
        encodeVisibility_commitment_eq, ?_⟩
      simpa [ByteArray.append_empty] using
        decodeVisibility_of_encode_midV1 .commitment
          (taggedHeaderBytesV1 "Visibility.Commitment" 0) ByteArray.empty ByteArray.empty 0
          (by decide) encodeVisibility_commitment_eq

/-- Positive theorem: MidOffsetInvert package for Visibility. -/
theorem visibility_midOffsetInvert :
    MidOffsetInvertV1 encodeVisibilityV1 decodeVisibilityV1 :=
  midOffsetInvert_encodeVisibility_decodeVisibility

/-- Positive theorem: empty array mid-offset invert. -/
theorem array_zero_mid :
    decodeArray 10 (decodeVisibilityV1)
        ⟨encodeU32le 0, 0, 0⟩ =
      .ok (#[], ⟨encodeU32le 0, 4, 0⟩) := by
  simpa [ByteArray.append_empty] using
    decodeArray_of_encodeArray_zero_midV1 encodeVisibilityV1 decodeVisibilityV1 10
      ByteArray.empty ByteArray.empty 0

/-- Positive theorem: InvariantDecl MidOffsetInvert package. -/
theorem invariantDecl_midOffsetInvert :
    MidOffsetInvertV1 encodeInvariantDeclV1 decodeInvariantDeclV1 :=
  midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl

/-- The public production-array induction packages arbitrary-length invariant
    tables from per-element production codec facts; it is not limited to a
    closed singleton or contract-specific byte layout. -/
theorem invariantTable_exact_of_forall_encoded
    (values : Array InvariantDeclV1)
    (hsize : values.size ≤ maxTableElements)
    (hsizeU32 : values.size ≤ UInt32.size - 1)
    (hencoded :
      ∀ value ∈ values.toList, ∃ bytes, encodeInvariantDeclV1 value = .ok bytes) :
    ExactMidOffsetInvertV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1) values := by
  exact
    exactMidOffsetInvert_array_of_forall_encoded_exact
      encodeInvariantDeclV1 decodeInvariantDeclV1 maxTableElements values
      hsize (by decide) hsizeU32 hencoded (by
        intro value _hvalue
        exact
          ExactMidOffsetInvertV1.ofGlobal
            midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl value)

/-- Positive theorem: CallableKind MidOffsetInvert package. -/
theorem callableKind_midOffsetInvert :
    MidOffsetInvertV1 encodeCallableKindV1 decodeCallableKindV1 :=
  midOffsetInvert_encodeCallableKind_decodeCallableKind

/-- Positive theorem: ValueDef MidOffsetInvert package. -/
theorem valueDef_midOffsetInvert :
    MidOffsetInvertV1 encodeValueDefV1 decodeValueDefV1 :=
  midOffsetInvert_encodeValueDef_decodeValueDef

/-- Positive theorem: LoopBound MidOffsetInvert package. -/
theorem loopBound_midOffsetInvert :
    MidOffsetInvertV1 encodeLoopBoundV1 decodeLoopBoundV1 :=
  midOffsetInvert_encodeLoopBound_decodeLoopBound

/-- Positive theorem: DecodeEncodeRoundtripGoal composition is discharged. -/
theorem decodeEncodeRoundtripGoal_discharged_all
    (data : SemanticProgramDataV1) (bytes : ByteArray) :
    DecodeEncodeRoundtripGoalV1 data bytes :=
  decodeEncodeRoundtripGoal_discharged data bytes

/-- Positive theorem: encode + RootFieldInvert ⇒ transport decode. -/
theorem decode_of_encode_of_rootFieldInvert
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hinvert : RootFieldInvertV1 data) :
    decodeSemanticProgramDataV1 bytes = .ok data :=
  decodeSemanticProgramDataV1_of_encode_ok data bytes hencode hinvert

/-- Positive theorem: empty constants table mid-offset invert. -/
theorem empty_constants_table_mid :
    decodeArray maxTableElements decodeConstantV1 ⟨encodeU32le 0, 0, 0⟩ =
      .ok (#[], ⟨encodeU32le 0, 4, 0⟩) := by
  have henc : encodeArray encodeConstantV1 (#[] : Array ConstantV1) = .ok (encodeU32le 0) :=
    encodeArray_zeroV1 encodeConstantV1
  simpa [ByteArray.append_empty, encodeU32le_sizeV1] using
    midOffsetInvert_empty_constants_table (encodeU32le 0) ByteArray.empty ByteArray.empty 0
      henc

/-- Positive theorem: empty ProgramRequirements mid-offset invert. -/
theorem empty_requirements_mid :
    ∃ b, encodeProgramRequirementsV1 { items := #[] } = .ok b ∧
      decodeProgramRequirementsV1 ⟨b, 0, 0⟩ =
        .ok ({ items := #[] }, ⟨b, b.size, 0⟩) := by
  -- Encode empty requirements via production path.
  have henc :
      encodeProgramRequirementsV1 { items := #[] } =
        .ok (taggedBytesV1 "ProgramRequirements" #[encodeU32le 0]) := by
    have hempty := encodeArray_zeroV1 encodeRequirementRequestV1
    have htag :=
      encodeTagged_eq_okV1 "ProgramRequirements" #[encodeU32le 0]
        (by decide) (by decide) (by decide) (by decide) (by decide)
    simp only [encodeProgramRequirementsV1, hempty, htag, Bind.bind, Pure.pure,
      Except.bind, Except.pure]
  refine ⟨taggedBytesV1 "ProgramRequirements" #[encodeU32le 0], henc, ?_⟩
  simpa [ByteArray.append_empty] using
    decodeProgramRequirements_empty_of_encode_midV1
      (taggedBytesV1 "ProgramRequirements" #[encodeU32le 0])
      ByteArray.empty ByteArray.empty 0 (by decide) henc

/-- Runtime smoke: Visibility + InvariantDecl + empty tables. -/
def run : IO Unit := do
  let cases : Array VisibilityV1 := #[.public_, .private_, .commitment]
  for vis in cases do
    match encodeVisibilityV1 vis with
    | .error e => throw <| IO.userError s!"encode failed: {repr e}"
    | .ok b =>
        match decodeVisibilityV1 ⟨b, 0, 0⟩ with
        | .error e => throw <| IO.userError s!"decode failed: {repr e}"
        | .ok (vis', c) =>
            expect (vis' == vis) s!"visibility mismatch"
            expect (c.offset == b.size) s!"cursor not at end"
  -- empty array
  match decodeArray 10 decodeVisibilityV1 ⟨encodeU32le 0, 0, 0⟩ with
  | .error e => throw <| IO.userError s!"empty array decode failed: {repr e}"
  | .ok (arr, c) =>
      expect (arr.size == 0) "expected empty array"
      expect (c.offset == 4) "expected post-header cursor"
  -- empty constants table
  match encodeArray encodeConstantV1 (#[] : Array ConstantV1) with
  | .error e => throw <| IO.userError s!"empty constants encode failed: {repr e}"
  | .ok b =>
      match decodeArray maxTableElements decodeConstantV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"empty constants decode failed: {repr e}"
      | .ok (arr, c) =>
          expect (arr.size == 0) "expected empty constants"
          expect (c.offset == b.size) "constants cursor not at end"
  -- empty ProgramRequirements
  match encodeProgramRequirementsV1 { items := #[] } with
  | .error e => throw <| IO.userError s!"empty requirements encode failed: {repr e}"
  | .ok b =>
      match decodeProgramRequirementsV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"empty requirements decode failed: {repr e}"
      | .ok (r, c) =>
          expect (r.items.size == 0) "expected empty requirements items"
          expect (c.offset == b.size) "requirements cursor not at end"
  -- InvariantDecl round-trip
  let inv : InvariantDeclV1 := { id := 0, name := "even", callableId := 1 }
  match encodeInvariantDeclV1 inv with
  | .error e => throw <| IO.userError s!"invariant encode failed: {repr e}"
  | .ok b =>
      match decodeInvariantDeclV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"invariant decode failed: {repr e}"
      | .ok (inv', c) =>
          expect (inv'.name == inv.name) "invariant name mismatch"
          expect (inv'.id == inv.id) "invariant id mismatch"
          expect (inv'.callableId == inv.callableId) "invariant callable mismatch"
          expect (c.offset == b.size) "invariant cursor not at end"
  -- CallableKind round-trip (all five)
  let kinds : Array CallableKindV1 :=
    #[.initializer, .entry, .view, .pureFn, .invariant]
  for kind in kinds do
    match encodeCallableKindV1 kind with
    | .error e => throw <| IO.userError s!"callable kind encode failed: {repr e}"
    | .ok b =>
        match decodeCallableKindV1 ⟨b, 0, 0⟩ with
        | .error e => throw <| IO.userError s!"callable kind decode failed: {repr e}"
        | .ok (kind', c) =>
            expect (kind' == kind) "callable kind mismatch"
            expect (c.offset == b.size) "callable kind cursor not at end"
  -- ValueDef round-trip
  let vd : ValueDefV1 := { valueId := 0, typeId := 1 }
  match encodeValueDefV1 vd with
  | .error e => throw <| IO.userError s!"valueDef encode failed: {repr e}"
  | .ok b =>
      match decodeValueDefV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"valueDef decode failed: {repr e}"
      | .ok (vd', c) =>
          expect (vd'.valueId == vd.valueId) "valueDef valueId mismatch"
          expect (vd'.typeId == vd.typeId) "valueDef typeId mismatch"
          expect (c.offset == b.size) "valueDef cursor not at end"
  -- LoopBound round-trip
  let lb : LoopBoundV1 := { header := 0, backEdgeFrom := 1, maxIterations := 16 }
  match encodeLoopBoundV1 lb with
  | .error e => throw <| IO.userError s!"loopBound encode failed: {repr e}"
  | .ok b =>
      match decodeLoopBoundV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"loopBound decode failed: {repr e}"
      | .ok (lb', c) =>
          expect (lb'.header == lb.header) "loopBound header mismatch"
          expect (lb'.backEdgeFrom == lb.backEdgeFrom) "loopBound backEdge mismatch"
          expect (lb'.maxIterations == lb.maxIterations) "loopBound maxIterations mismatch"
          expect (c.offset == b.size) "loopBound cursor not at end"
  -- Op.Constant + Op.Literal + Term.Return
  match encodeSemanticOpV1 (.constant 7) with
  | .error e => throw <| IO.userError s!"op.constant encode failed: {repr e}"
  | .ok b =>
      match decodeSemanticOpV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"op.constant decode failed: {repr e}"
      | .ok (op, c) =>
          expect (op == .constant 7) "op.constant mismatch"
          expect (c.offset == b.size) "op.constant cursor not at end"
  match encodeSemanticOpV1 (.literal 0 (ByteArray.mk #[1])) with
  | .error e => throw <| IO.userError s!"op.literal encode failed: {repr e}"
  | .ok b =>
      match decodeSemanticOpV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"op.literal decode failed: {repr e}"
      | .ok (op, c) =>
          match op with
          | .literal tid vb =>
              expect (tid == 0) "op.literal typeId mismatch"
              expect (vb == ByteArray.mk #[1]) "op.literal bytes mismatch"
          | _ => throw <| IO.userError "op.literal wrong constructor"
          expect (c.offset == b.size) "op.literal cursor not at end"
  match encodeTerminatorV1 (.return_ none) with
  | .error e => throw <| IO.userError s!"term.return none encode failed: {repr e}"
  | .ok b =>
      match decodeTerminatorV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"term.return none decode failed: {repr e}"
      | .ok (t, c) =>
          expect (t == .return_ none) "term.return none mismatch"
          expect (c.offset == b.size) "term.return none cursor not at end"
  match encodeTerminatorV1 (.return_ (some 3)) with
  | .error e => throw <| IO.userError s!"term.return some encode failed: {repr e}"
  | .ok b =>
      match decodeTerminatorV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"term.return some decode failed: {repr e}"
      | .ok (t, c) =>
          expect (t == .return_ (some 3)) "term.return some mismatch"
          expect (c.offset == b.size) "term.return some cursor not at end"
  -- empty callables table
  match encodeArray encodeCallableV1 (#[] : Array CallableV1) with
  | .error e => throw <| IO.userError s!"empty callables encode failed: {repr e}"
  | .ok b =>
      match decodeArray maxTableElements decodeCallableV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"empty callables decode failed: {repr e}"
      | .ok (arr, c) =>
          expect (arr.size == 0) "expected empty callables"
          expect (c.offset == b.size) "callables cursor not at end"
  IO.println "Tests.Semantic.CodecInvertV1: OK"

end Tests.Semantic.CodecInvertV1
