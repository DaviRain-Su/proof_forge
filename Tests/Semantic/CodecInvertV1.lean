/-
  Tests.Semantic.CodecInvertV1 — mig-a1 foundation + fields + callable + root:
  MidOffsetInvert, Visibility, InvariantDecl, empty tables/Requirements,
  Type.Bool, QN singleton, CallableKind, ValueDef, LoopBound, Op.Constant/
  StateLoad/Commit/Literal, Term.Return, empty callables, array one/two lift,
  DecodeEncodeRoundtripGoal composition discharge.

  Nine root fields invert for arbitrary data via `CodecInvertRootFieldsV1`.
  `decodeSemanticProgramDataV1_of_encode_ok` has no remaining callables or
  requirements invert hypotheses. Transport invert only; not TASK-D2-06 /
  TST-SEM-001.
-/
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1
import ProofForgeV2.Semantic.Wire.CodecInvertCallableV1
import ProofForgeV2.Semantic.Wire.CodecInvertRootV1
import ProofForgeV2.Semantic.Wire.CodecInvertRootFieldsV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.CodecInvertV1

open ProofForgeV2.Semantic.PreservationShapeV1
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

/-- Empty invariants table inverts at root-field depth via RootFields assembly. -/
theorem empty_invariants_table_rootField_exactAt :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1)
      (#[] : Array InvariantDeclV1) 1 :=
  exactMidOffsetInvertAt_invariantsTableV1 #[] (by decide)

/-- A named public callable parameter uses the actual production codec and is
    exactly invertible under arbitrary framing at callable-array depth. -/
theorem parameter_public_exactAt :
    ExactMidOffsetInvertAtV1 encodeParameterV1 decodeParameterV1
      ({
        valueId := 0
        name := "amount"
        typeId := 0
        visibility := .public_
      } : ParameterV1) 2 :=
  exactAt_parameter_publicV1 0 0 "amount" (by rfl) 2 (by decide)

/-- The complete state-changing entry plus equality-invariant table is
    packaged from production callable codecs, not from pinned bytes. -/
theorem stateful_equality_callable_table_exactAt :
    ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1)
      #[storeParameterTwoReturnCallableV1 0 (some "sync") "amount"
          0 0 1 .public_,
        twoStateCompareInvariantCallableV1 1 (some "solvent")
          0 1 0 1 .eq .public_ (some 5)] 1 :=
  exactAt_storeParameterEqualityCallableTableV1 0 1 "sync" "amount"
    "solvent" 0 1 0 1 (by rfl) (by rfl) (by rfl)

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

/-- The same production-array induction is consumable at the root's fixed
    nesting depth, which is required by element codecs with deeper children. -/
theorem invariantTable_exactAt_of_forall_encoded
    (values : Array InvariantDeclV1)
    (hsize : values.size ≤ maxTableElements)
    (hsizeU32 : values.size ≤ UInt32.size - 1)
    (hencoded :
      ∀ value ∈ values.toList, ∃ bytes, encodeInvariantDeclV1 value = .ok bytes) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1) values 1 := by
  exact
    exactMidOffsetInvertAt_array_of_forall_encoded_exactAt
      encodeInvariantDeclV1 decodeInvariantDeclV1 maxTableElements values 1
      hsize (by decide) hsizeU32 hencoded (by
        intro value _hvalue
        exact
          ExactMidOffsetInvertAtV1.ofGlobal
            midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl value
            (by decide))

/-- Anonymous TypeDecl leaves expose root-depth exact certificates without a
    contract byte pin. -/
theorem typeDecl_uint64_exactAt_root (id : UInt32) :
    ExactMidOffsetInvertAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      ({ id := id, name := none, shape := .uint 64 } : TypeDeclV1) 1 :=
  exactAt_typeDecl_uint_noneV1 id 64 1 (by decide)

theorem typeDecl_bool_exactAt_root (id : UInt32) :
    ExactMidOffsetInvertAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      ({ id := id, name := none, shape := .bool } : TypeDeclV1) 1 :=
  exactAt_typeDecl_bool_noneV1 id 1 (by decide)

/-- Public StateDecl leaves retain arbitrary declaration/type ids at the
    root-table element depth. -/
theorem stateDecl_public_exactAt_root
    (id typeId : UInt32) (stateName : String)
    (hname : validateIdentifierComponent stateName = .ok ()) :
    ExactMidOffsetInvertAtV1 encodeStateDeclV1 decodeStateDeclV1
      ({ id, name := stateName, typeId, visibility := .public_ } : StateDeclV1) 1 :=
  exactAt_stateDecl_publicV1 id typeId stateName hname 1 (by decide)

/-- Binary inequality uses the same production tagged-op inversion path as
    equality; the operands remain arbitrary. -/
theorem binaryNe_exactAt_instructionOp (lhs rhs : UInt32) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      (.binary .ne lhs rhs) 4 :=
  exactAt_semanticOp_binaryNeV1 lhs rhs 4 (by decide) (by decide)

/-- Literal-true and field-comparison structural budgets share one
    production option-codec theorem rather than closed `3`/`5` byte proofs. -/
theorem invariantSteps_exactAt_root (steps : UInt8) :
    ExactMidOffsetInvertAtV1
      (encodeOption (fun value : UInt64 => pure (encodeU64le value)))
      (decodeOption decodeU64le) (some steps.toUInt64) 2 :=
  exactAt_optionU64_someUInt8V1 steps 2

/-- Single-literal callable composition remains independent of concrete IDs,
    names, payloads, kind, and optional structural budget. -/
theorem literalReturnCallable_exactAt_root
    (callableId typeId : UInt32) (kind : CallableKindV1)
    (name : String) (valueBytes : ByteArray) (visibility : VisibilityV1)
    (steps : Option UInt64)
    (hname : validateIdentifierComponent name = .ok ())
    (hsteps : ExactMidOffsetInvertAtV1
      (encodeOption (fun value : UInt64 => pure (encodeU64le value)))
      (decodeOption decodeU64le) steps 2) :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
      (literalReturnCallableV1 callableId kind (some name) typeId valueBytes
        visibility steps) 1 :=
  exactAt_literalReturnCallableV1 callableId kind name typeId valueBytes
    visibility steps hname hsteps

/-- Equality and inequality callables share the same parameterized production
    CFG package; only their binary-op leaf certificate differs. -/
theorem twoStateCompareCallables_exactAt_root
    (eqId neId valueTypeId boolTypeId leftStateId rightStateId : UInt32)
    (eqName neName : String)
    (heqName : validateIdentifierComponent eqName = .ok ())
    (hneName : validateIdentifierComponent neName = .ok ()) :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        (twoStateCompareInvariantCallableV1 eqId (some eqName)
          valueTypeId boolTypeId leftStateId rightStateId .eq .public_ (some 5)) 1 ∧
      ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        (twoStateCompareInvariantCallableV1 neId (some neName)
          valueTypeId boolTypeId leftStateId rightStateId .ne .public_ (some 5)) 1 := by
  constructor
  · simpa using
      exactAt_twoStateCompareInvariantCallableV1 eqId eqName valueTypeId
        boolTypeId leftStateId rightStateId .eq .public_ 5 heqName
        (exactAt_semanticOp_binaryEqV1 0 1 4 (by decide) (by decide))
  · simpa using
      exactAt_twoStateCompareInvariantCallableV1 neId neName valueTypeId
        boolTypeId leftStateId rightStateId .ne .public_ 5 hneName
        (exactAt_semanticOp_binaryNeV1 0 1 4 (by decide) (by decide))

/-- The four-row authoring-family package composes without contract-specific
    names, IDs, state slots, type IDs, literal bytes, or encoded table bytes. -/
theorem literalFieldComparisonCallableTable_exactAt_root
    (viewId literalInvariantId eqId neId valueTypeId boolTypeId
      leftStateId rightStateId : UInt32)
    (viewName literalInvariantName eqName neName : String)
    (viewValueBytes invariantValueBytes : ByteArray)
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqName : validateIdentifierComponent eqName = .ok ())
    (hneName : validateIdentifierComponent neName = .ok ()) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1)
      #[literalReturnCallableV1 viewId .view (some viewName) boolTypeId
          viewValueBytes .public_ none,
        literalReturnCallableV1 literalInvariantId .invariant
          (some literalInvariantName) boolTypeId invariantValueBytes .public_
          (some 3),
        twoStateCompareInvariantCallableV1 eqId (some eqName)
          valueTypeId boolTypeId leftStateId rightStateId .eq .public_ (some 5),
        twoStateCompareInvariantCallableV1 neId (some neName)
          valueTypeId boolTypeId leftStateId rightStateId .ne .public_ (some 5)] 1 :=
  exactAt_literalFieldComparisonCallableTableV1 viewId literalInvariantId
    eqId neId viewName literalInvariantName eqName neName valueTypeId boolTypeId
    leftStateId rightStateId viewValueBytes invariantValueBytes hviewName
    hliteralInvariantName heqName hneName

/-- Two production requirement rows compose through the generic array and
    tagged ProgramRequirements wrappers without caller-supplied row bytes. -/
theorem twoRequirements_exactAt_root
    (row0 row1 : RequirementRequestV1)
    (h0 : ExactMidOffsetInvertAtV1 encodeRequirementRequestV1
      decodeRequirementRequestV1 row0 2)
    (h1 : ExactMidOffsetInvertAtV1 encodeRequirementRequestV1
      decodeRequirementRequestV1 row1 2) :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 ({ items := #[row0, row1] } :
        ProgramRequirementsV1) 1 :=
  exactAt_programRequirements_of_itemsV1
    ({ items := #[row0, row1] } : ProgramRequirementsV1) 1 (by decide)
    (exactAt_array_two_of_exactAtV1 encodeRequirementRequestV1
      decodeRequirementRequestV1 maxArrayElements (by decide) (by decide)
      row0 row1 2 h0 h1)

/-- A production field codec consumes the generic four-element fixed-depth
    array seam without supplying element bytes. -/
theorem invariantTable_four_exactAt_root
    (v0 v1 v2 v3 : InvariantDeclV1) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1) #[v0, v1, v2, v3] 1 :=
  exactAt_array_four_of_exactAtV1 encodeInvariantDeclV1 decodeInvariantDeclV1
    maxTableElements (by decide) (by decide) v0 v1 v2 v3 1
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl v0 (by decide))
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl v1 (by decide))
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl v2 (by decide))
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl v3 (by decide))

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
  decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert data bytes hencode
    hinvert

/-- Positive theorem: encode success ⇒ transport decode for arbitrary data.
    No remaining callables/requirements invert hypotheses. -/
theorem decode_of_encode_ok
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes) :
    decodeSemanticProgramDataV1 bytes = .ok data :=
  decodeSemanticProgramDataV1_of_encode_ok data bytes hencode

private def zeroDigestV1 : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }

private def nonemptyPredicatesRequestV1 : RequirementRequestV1 :=
  {
    id := "proof-forge.test.req.v1"
    version := { major := 1, minor := 0, patch := 0 }
    digest := zeroDigestV1
    predicates := #[.uintAtLeast "n" 1, .boolEquals "flag" true]
  }

/-- Nonempty predicates invert through the generic Requirements package. -/
theorem nonempty_predicates_requirements_exactAt :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1
      ({ items := #[nonemptyPredicatesRequestV1] } : ProgramRequirementsV1) 1 :=
  exactMidOffsetInvertAt_requirementsV1
    ({ items := #[nonemptyPredicatesRequestV1] } : ProgramRequirementsV1)

private def unaryJumpCallableV1 : CallableV1 :=
  {
    id := 0
    kind := .entry
    name := some "go"
    params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := 0 }
        op := .unary .not 0
      }]
      terminator := .jump { blockId := 0, args := #[] }
    }]
    loopBounds := #[]
    invariantSteps := none
  }

/-- A one-block callable carrying `Op.Unary` and `Term.Jump` inverts as a
    production callables table. -/
theorem unary_jump_callable_table_exactAt :
    ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1) #[unaryJumpCallableV1] 1 :=
  exactMidOffsetInvertAt_callablesTableV1 #[unaryJumpCallableV1] (by decide)

/-- Empty callables table + empty requirements invert at root-field depth. -/
theorem empty_callables_and_requirements_exactAt :
    ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1)
      (#[] : Array CallableV1) 1 ∧
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 ({ items := #[] } : ProgramRequirementsV1) 1 :=
  ⟨exactMidOffsetInvertAt_callablesTableV1 #[] (by decide),
    exactMidOffsetInvertAt_requirementsV1 { items := #[] }⟩

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
  -- nonempty predicates
  match encodeProgramRequirementsV1 { items := #[nonemptyPredicatesRequestV1] } with
  | .error e => throw <| IO.userError s!"nonempty requirements encode failed: {repr e}"
  | .ok b =>
      match decodeProgramRequirementsV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"nonempty requirements decode failed: {repr e}"
      | .ok (r, c) =>
          expect (r.items.size == 1) "expected one requirement row"
          match r.items[0]? with
          | none => throw <| IO.userError "missing requirement row"
          | some row =>
              expect (row.predicates.size == 2) "expected two predicates"
          expect (c.offset == b.size) "nonempty requirements cursor not at end"
  -- Op.Unary + Term.Jump
  match encodeSemanticOpV1 (.unary .not 0) with
  | .error e => throw <| IO.userError s!"op.unary encode failed: {repr e}"
  | .ok b =>
      match decodeSemanticOpV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"op.unary decode failed: {repr e}"
      | .ok (op, c) =>
          expect (op == .unary .not 0) "op.unary mismatch"
          expect (c.offset == b.size) "op.unary cursor not at end"
  match encodeTerminatorV1 (.jump { blockId := 0, args := #[] }) with
  | .error e => throw <| IO.userError s!"term.jump encode failed: {repr e}"
  | .ok b =>
      match decodeTerminatorV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"term.jump decode failed: {repr e}"
      | .ok (t, c) =>
          expect (t == .jump { blockId := 0, args := #[] }) "term.jump mismatch"
          expect (c.offset == b.size) "term.jump cursor not at end"
  -- nonempty single-block callable
  match encodeArray encodeCallableV1 #[unaryJumpCallableV1] with
  | .error e => throw <| IO.userError s!"unary-jump callable encode failed: {repr e}"
  | .ok b =>
      match decodeArray maxTableElements decodeCallableV1 ⟨b, 0, 0⟩ with
      | .error e => throw <| IO.userError s!"unary-jump callable decode failed: {repr e}"
      | .ok (arr, c) =>
          expect (arr.size == 1) "expected one callable"
          match arr[0]? with
          | none => throw <| IO.userError "missing unary-jump callable"
          | some c0 =>
              expect (c0 == unaryJumpCallableV1) "unary-jump callable mismatch"
          expect (c.offset == b.size) "unary-jump callable cursor not at end"
  IO.println "Tests.Semantic.CodecInvertV1: OK"

end Tests.Semantic.CodecInvertV1
