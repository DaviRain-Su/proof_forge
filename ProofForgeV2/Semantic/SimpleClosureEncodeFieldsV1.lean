import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1

/-
  B-SC-ENC: field encode success + size under legal; legal-only main theorem.
  Sole `encodeSemanticProgramDataBodyV1`; no second builder / Tests FQN /
  sorry / native_decide / ofReduceBool.
-/

set_option maxHeartbeats 1500000
set_option maxRecDepth 200000

namespace ProofForgeV2.Semantic.SimpleClosureEncodeFieldsV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### String / QN sizes -/

theorem encodeString_size_le_244_of_ident
    (s : String) (h : validateIdentifierComponent s = .ok ())
    {b : ByteArray} (hb : encodeString s = .ok b) :
    b.size ≤ 244 := by
  have heq := encodeString_eq_ok_of_validateIdentifierComponent s h
  have : b = (encodeU32le (UInt32.ofNat s.toUTF8.size)).append s.toUTF8 :=
    Except.ok.inj (hb.symm.trans heq)
  subst this
  have hutf : s.toUTF8.size = s.utf8ByteSize := by
    simp [String.toUTF8_eq_toByteArray, String.size_toByteArray]
  have h240 := utf8ByteSize_le_240_of_ident s h
  rw [ByteArray_size_append, encodeU32le_size, hutf]
  omega

theorem encodeArrayChunks_string_size_le
    (xs : List String) (acc : ByteArray)
    (h : ∀ s ∈ xs, validateIdentifierComponent s = .ok ())
    {payload : ByteArray}
    (hp : encodeArrayChunksV1 encodeString xs acc = .ok payload) :
    payload.size ≤ acc.size + xs.length * 244 := by
  induction xs generalizing acc with
  | nil =>
      simp only [encodeArrayChunksV1] at hp
      cases hp; omega
  | cons x xs ih =>
      have hxid := h x (List.Mem.head xs)
      have hstr := encodeString_eq_ok_of_validateIdentifierComponent x hxid
      simp only [encodeArrayChunksV1, hstr, Bind.bind, Except.bind] at hp
      have hrest : ∀ s ∈ xs, validateIdentifierComponent s = .ok () :=
        fun s hs => h s (List.Mem.tail x hs)
      have hchunk :
          ((encodeU32le (UInt32.ofNat x.toUTF8.size)).append x.toUTF8).size ≤ 244 :=
        encodeString_size_le_244_of_ident x hxid hstr
      have ih' :=
        ih (acc.append ((encodeU32le (UInt32.ofNat x.toUTF8.size)).append x.toUTF8))
          hrest hp
      have happ :=
        ByteArray_size_append acc
          ((encodeU32le (UInt32.ofNat x.toUTF8.size)).append x.toUTF8)
      -- goal uses (x::xs).length = xs.length + 1
      simp only [List.length_cons] at ih' ⊢
      omega

theorem encodeArray_string_ok_size
    (values : Array String)
    (hsize : values.size ≤ maxArrayElements)
    (hsizeU32 : values.size ≤ UInt32.size - 1)
    (h : ∀ s ∈ values.toList, validateIdentifierComponent s = .ok ()) :
    ∃ b, encodeArray encodeString values = .ok b ∧ b.size ≤ 4 + values.size * 244 := by
  obtain ⟨chunks, hchunks⟩ :=
    encodeArrayChunksV1_ok_of_forall encodeString values.toList ByteArray.empty
      (fun s hs => ⟨_, encodeString_eq_ok_of_validateIdentifierComponent s (h s hs)⟩)
  have henc :=
    encodeArray_eq_of_chunksV1 encodeString values chunks hsize hsizeU32 hchunks
  have hchunks' :=
    encodeArrayChunks_string_size_le values.toList ByteArray.empty h hchunks
  have hnil : (ByteArray.empty : ByteArray).size = 0 := rfl
  have hlen : values.toList.length = values.size := by simp
  refine ⟨(encodeU32le (UInt32.ofNat values.size)).append chunks, henc, ?_⟩
  have : chunks.size ≤ values.size * 244 := by
    simpa [hnil, hlen] using hchunks'
  rw [ByteArray_size_append, encodeU32le_size]
  omega

theorem encodeQualifiedName_materialize_ok_size_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    ∃ b, encodeQualifiedName (materializeSimpleClosureDataV1 p).qualifiedName =
        .ok b ∧ b.size ≤ 4 + p.qnSize * 244 := by
  have hcomp := renderQualifiedNameComponents_materialize_of_legal p legal
  have hmap :
      mapCommon
          (renderQualifiedNameComponents
            (materializeSimpleClosureDataV1 p).qualifiedName) =
        .ok (#[p.qnHead] ++ p.qnTail) := by
    simp only [mapCommon, hcomp]
  have hsize : (#[p.qnHead] ++ p.qnTail).size ≤ maxArrayElements := by
    simpa [Array.size_append, SimpleClosureParamsV1.qnSize, Nat.add_comm]
      using Nat.le_trans legal.hqnCap (by decide : 256 ≤ maxArrayElements)
  have hsizeU32 : (#[p.qnHead] ++ p.qnTail).size ≤ UInt32.size - 1 := by
    simpa [Array.size_append, SimpleClosureParamsV1.qnSize, Nat.add_comm]
      using Nat.le_trans legal.hqnCap (by decide : 256 ≤ UInt32.size - 1)
  have hidents :
      ∀ s ∈ (#[p.qnHead] ++ p.qnTail).toList,
        validateIdentifierComponent s = .ok () := by
    intro s hs
    have : (#[p.qnHead] ++ p.qnTail).toList = p.qnHead :: p.qnTail.toList := by
      simp [Array.toList_append]
    rw [this] at hs
    exact qn_idents_list_of_legal p legal s hs
  obtain ⟨payload, hpayload, hsz⟩ :=
    encodeArray_string_ok_size (#[p.qnHead] ++ p.qnTail) hsize hsizeU32 hidents
  have henc :
      encodeQualifiedName (materializeSimpleClosureDataV1 p).qualifiedName =
        .ok payload := by
    simp only [encodeQualifiedName, hmap, hpayload, Bind.bind, Except.bind]
  have hcsize : (#[p.qnHead] ++ p.qnTail).size = p.qnSize := by
    simp [Array.size_append, SimpleClosureParamsV1.qnSize]; omega
  refine ⟨payload, henc, ?_⟩
  simpa [hcsize] using hsz

/-! ### Fixed types -/

private def boolShapeB : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private def uint64ShapeB : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

private theorem boolShapeB_size : boolShapeB.size = 15 := by
  simp [boolShapeB, ByteArray.size, Array.size]

private theorem uint64ShapeB_size : uint64ShapeB.size = 17 := by
  simp [uint64ShapeB, ByteArray.size, Array.size]

private theorem encodeTypeShape_bool :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolShapeB := by
  change encodeNullary "Type.Bool" = .ok boolShapeB
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem encodeTypeShape_uint64 :
    encodeTypeShapeV1 (.uint 64) = .ok uint64ShapeB := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] = .ok uint64ShapeB
  rw [encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)]
  rfl

private theorem encodeOption_none_string :
    encodeOption encodeString (none : Option String) = .ok (encodeU8 0) := rfl

private theorem encodeTypeDecl_bool_eq :
    encodeTypeDeclV1 simpleClosureBoolTypeV1 =
      .ok (taggedBytesV1 "TypeDecl" #[encodeU32le 0, encodeU8 0, boolShapeB]) := by
  have hshape := encodeTypeShape_bool
  have hname := encodeOption_none_string
  have htag :=
    encodeTagged_eq_okV1 "TypeDecl" #[encodeU32le 0, encodeU8 0, boolShapeB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  simp only [encodeTypeDeclV1, simpleClosureBoolTypeV1, hname, hshape, htag,
    Bind.bind, Except.bind]

private theorem encodeTypeDecl_uint64_eq :
    encodeTypeDeclV1 simpleClosureUInt64TypeV1 =
      .ok (taggedBytesV1 "TypeDecl" #[encodeU32le 1, encodeU8 0, uint64ShapeB]) := by
  have hshape := encodeTypeShape_uint64
  have hname := encodeOption_none_string
  have htag :=
    encodeTagged_eq_okV1 "TypeDecl" #[encodeU32le 1, encodeU8 0, uint64ShapeB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  simp only [encodeTypeDeclV1, simpleClosureUInt64TypeV1, hname, hshape, htag,
    Bind.bind, Except.bind]

private theorem typeDecl_bool_size_le :
    (taggedBytesV1 "TypeDecl" #[encodeU32le 0, encodeU8 0, boolShapeB]).size ≤ 64 := by
  simp only [taggedBytesV1_size]
  have ht : "TypeDecl".toUTF8.size = 8 := rfl
  have hfold :
      (#[encodeU32le 0, encodeU8 0, boolShapeB] : Array ByteArray).foldl
          (fun n f => n + f.size) 0 =
        4 + 1 + 15 := by
    simp [List.foldl, encodeU32le_size, encodeU8_size, boolShapeB_size]
  rw [ht, hfold]
  omega

private theorem typeDecl_uint64_size_le :
    (taggedBytesV1 "TypeDecl" #[encodeU32le 1, encodeU8 0, uint64ShapeB]).size ≤ 64 := by
  simp only [taggedBytesV1_size]
  have ht : "TypeDecl".toUTF8.size = 8 := rfl
  have hfold :
      (#[encodeU32le 1, encodeU8 0, uint64ShapeB] : Array ByteArray).foldl
          (fun n f => n + f.size) 0 =
        4 + 1 + 17 := by
    simp [List.foldl, encodeU32le_size, encodeU8_size, uint64ShapeB_size]
  rw [ht, hfold]
  omega

theorem encodeTypes_materialize_ok_size (p : SimpleClosureParamsV1) :
    ∃ b, encodeArray encodeTypeDeclV1 (materializeSimpleClosureDataV1 p).types =
        .ok b ∧ b.size ≤ 200 := by
  let b0 := taggedBytesV1 "TypeDecl" #[encodeU32le 0, encodeU8 0, boolShapeB]
  let b1 := taggedBytesV1 "TypeDecl" #[encodeU32le 1, encodeU8 0, uint64ShapeB]
  have htwo :=
    encodeArray_twoV1 encodeTypeDeclV1 simpleClosureBoolTypeV1 simpleClosureUInt64TypeV1
      b0 b1 encodeTypeDecl_bool_eq encodeTypeDecl_uint64_eq
  refine ⟨(encodeU32le 2).append (b0.append b1), ?_, ?_⟩
  · simpa [materializeSimpleClosureDataV1] using htwo
  · have s0 : b0.size ≤ 64 := typeDecl_bool_size_le
    have s1 : b1.size ≤ 64 := typeDecl_uint64_size_le
    rw [ByteArray_size_append, encodeU32le_size, ByteArray_size_append]
    omega



/-! ### Fixed lit-true block -/

private theorem encodeValueDef_00 :
    encodeValueDefV1 { valueId := 0, typeId := 0 } =
      .ok (taggedBytesV1 "ValueDef" #[encodeU32le 0, encodeU32le 0]) := by
  simp only [encodeValueDefV1]
  exact encodeTagged_eq_okV1 "ValueDef" #[encodeU32le 0, encodeU32le 0]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private theorem encodeByteArray_u8_1 :
    encodeByteArray (encodeU8 1) =
      .ok ((encodeU32le 1).append (encodeU8 1)) := by
  have hsize : (encodeU8 1).size ≤ maxCanonicalProgramBytes := by
    simp only [encodeU8_size]; decide
  have hu32 : (encodeU8 1).size ≤ UInt32.size - 1 := by
    simp only [encodeU8_size]; decide
  exact encodeByteArray_eq_okV1 (encodeU8 1) hsize hu32

private theorem encodeLiteral_true_eq :
    encodeSemanticOpV1 (.literal 0 (encodeU8 1)) =
      .ok (taggedBytesV1 "Op.Literal"
        #[encodeU32le 0, (encodeU32le 1).append (encodeU8 1)]) := by
  have hb := encodeByteArray_u8_1
  simp only [encodeSemanticOpV1, hb, Bind.bind, Pure.pure, Except.bind, Except.pure]
  exact encodeTagged_eq_okV1 "Op.Literal"
    #[encodeU32le 0, (encodeU32le 1).append (encodeU8 1)]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private def litInstrB : ByteArray :=
  taggedBytesV1 "Instruction"
    #[(encodeU8 1).append (taggedBytesV1 "ValueDef" #[encodeU32le 0, encodeU32le 0]),
      taggedBytesV1 "Op.Literal"
        #[encodeU32le 0, (encodeU32le 1).append (encodeU8 1)]]

private theorem encodeInstruction_litTrue_eq :
    encodeInstructionV1 simpleClosureLitTrueV1 = .ok litInstrB := by
  have hres :
      encodeOption encodeValueDefV1 (some { valueId := 0, typeId := 0 }) =
        .ok ((encodeU8 1).append
          (taggedBytesV1 "ValueDef" #[encodeU32le 0, encodeU32le 0])) := by
    simp only [encodeOption, encodeValueDef_00, Bind.bind, Pure.pure, Except.bind,
      Except.pure]
  have hop := encodeLiteral_true_eq
  have htag :=
    encodeTagged_eq_okV1 "Instruction"
      #[(encodeU8 1).append (taggedBytesV1 "ValueDef" #[encodeU32le 0, encodeU32le 0]),
        taggedBytesV1 "Op.Literal"
          #[encodeU32le 0, (encodeU32le 1).append (encodeU8 1)]]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  simp only [encodeInstructionV1, simpleClosureLitTrueV1, litInstrB, hres, hop, htag,
    Bind.bind, Except.bind]

private theorem encodeTerminator_return0_eq :
    encodeTerminatorV1 (.return_ (some 0)) =
      .ok (taggedBytesV1 "Term.Return"
        #[(encodeU8 1).append (encodeU32le 0)]) := by
  simp only [encodeTerminatorV1, encodeOption, pure, Except.pure, Bind.bind,
    Except.bind]
  exact encodeTagged_eq_okV1 "Term.Return"
    #[(encodeU8 1).append (encodeU32le 0)]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private def blockB : ByteArray :=
  taggedBytesV1 "Block"
    #[encodeU32le 0, encodeU32le 0, (encodeU32le 1).append litInstrB,
      taggedBytesV1 "Term.Return" #[(encodeU8 1).append (encodeU32le 0)]]

private theorem encodeBlock_simpleClosure_eq :
    encodeBlockV1 simpleClosureBlockV1 = .ok blockB := by
  have hparams := encodeArray_zeroV1 encodeBlockParameterV1
  have hinstrs :=
    encodeArray_oneV1 encodeInstructionV1 simpleClosureLitTrueV1 litInstrB
      encodeInstruction_litTrue_eq
  have hterm := encodeTerminator_return0_eq
  have htag :=
    encodeTagged_eq_okV1 "Block"
      #[encodeU32le 0, encodeU32le 0, (encodeU32le 1).append litInstrB,
        taggedBytesV1 "Term.Return" #[(encodeU8 1).append (encodeU32le 0)]]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  simp only [encodeBlockV1, simpleClosureBlockV1, blockB, hparams, hinstrs, hterm,
    htag, Bind.bind, Except.bind]

private theorem litInstrB_size_le : litInstrB.size ≤ 256 := by
  have h : litInstrB.size = 65 := by decide
  omega

private theorem blockB_size_le : blockB.size ≤ 512 := by
  have h : blockB.size = 110 := by decide
  omega


/-! ### Callables / invariants / requirements / main -/

private theorem encodeVisibility_public_eq :
    encodeVisibilityV1 .public_ =
      .ok (taggedBytesV1 "Visibility.Public" #[]) := by
  simp only [encodeVisibilityV1, encodeNullary]
  exact encodeTagged_eq_okV1 "Visibility.Public" #[]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private theorem encodeCallableResult_publicBool_eq :
    encodeCallableResultV1 { typeId := 0, visibility := .public_ } =
      .ok (taggedBytesV1 "CallableResult"
        #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]) := by
  have hvis := encodeVisibility_public_eq
  simp only [encodeCallableResultV1, hvis, Bind.bind, Except.bind]
  exact encodeTagged_eq_okV1 "CallableResult"
    #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private theorem encodeCallableKind_view_eq :
    encodeCallableKindV1 .view = .ok (taggedBytesV1 "Callable.View" #[]) := by
  simp only [encodeCallableKindV1, encodeNullary]
  exact encodeTagged_eq_okV1 "Callable.View" #[]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private theorem encodeCallableKind_invariant_eq :
    encodeCallableKindV1 .invariant =
      .ok (taggedBytesV1 "Callable.Invariant" #[]) := by
  simp only [encodeCallableKindV1, encodeNullary]
  exact encodeTagged_eq_okV1 "Callable.Invariant" #[]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private theorem optionString_size_le_245
    (name : String) (h : validateIdentifierComponent name = .ok ()) :
    ((encodeU8 1).append
        ((encodeU32le (UInt32.ofNat name.toUTF8.size)).append name.toUTF8)).size ≤
      245 := by
  have hstr := encodeString_eq_ok_of_validateIdentifierComponent name h
  have hs := encodeString_size_le_244_of_ident name h hstr
  rw [ByteArray_size_append, encodeU8_size]; omega

private theorem callableResult_size_le :
    (taggedBytesV1 "CallableResult"
      #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]).size ≤ 64 := by
  have : (taggedBytesV1 "CallableResult"
      #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]).size = 47 := by decide
  omega

private theorem callableView_kind_size_le :
    (taggedBytesV1 "Callable.View" #[]).size ≤ 32 := by
  have : (taggedBytesV1 "Callable.View" #[]).size = 19 := by decide
  omega

private theorem callableInv_kind_size_le :
    (taggedBytesV1 "Callable.Invariant" #[]).size ≤ 40 := by
  have : (taggedBytesV1 "Callable.Invariant" #[]).size = 24 := by decide
  omega


theorem encodeViewCallable_ok
    (viewName : String) (hname : validateIdentifierComponent viewName = .ok ()) :
    ∃ b, encodeCallableV1 (simpleClosureViewCallableV1 viewName) = .ok b := by
  have hstr := encodeString_eq_ok_of_validateIdentifierComponent viewName hname
  have hopt := encodeOptionString_some_eq_ok viewName _ hstr
  let nameB := (encodeU8 1).append
    ((encodeU32le (UInt32.ofNat viewName.toUTF8.size)).append viewName.toUTF8)
  have hnameB : encodeOption encodeString (some viewName) = .ok nameB := hopt
  have hkind := encodeCallableKind_view_eq
  have hparams := encodeArray_zeroV1 encodeParameterV1
  have hresult := encodeCallableResult_publicBool_eq
  have hblocks :=
    encodeArray_oneV1 encodeBlockV1 simpleClosureBlockV1 blockB
      encodeBlock_simpleClosure_eq
  have hloop := encodeArray_zeroV1 encodeLoopBoundV1
  have hsteps :
      encodeOption (fun v => pure (encodeU64le v)) (none : Option UInt64) =
        .ok (encodeU8 0) := rfl
  let kindB := taggedBytesV1 "Callable.View" #[]
  let paramsB := encodeU32le 0
  let resultB := taggedBytesV1 "CallableResult"
    #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]
  let blocksB := (encodeU32le 1).append blockB
  let loopB := encodeU32le 0
  let stepsB := encodeU8 0
  let out := taggedBytesV1 "Callable"
    #[encodeU32le 0, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
      stepsB]
  have htag :
      encodeTagged "Callable"
          #[encodeU32le 0, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB,
            loopB, stepsB] =
        .ok out := by
    simp only [out]
    exact encodeTagged_eq_okV1 "Callable"
      #[encodeU32le 0, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
        stepsB]
      (by decide) (by decide) (by decide) (by decide)
      (by decide : (9 : Nat) ≤ UInt16.size - 1)
  have henc :=
    encodeCallableV1_eq_of_fields
      (simpleClosureViewCallableV1 viewName)
      kindB nameB paramsB resultB blocksB loopB stepsB out hkind hnameB hparams
      hresult hblocks hloop hsteps htag
  exact ⟨out, henc⟩

theorem encodeViewCallable_ok_size
    (viewName : String) (hname : validateIdentifierComponent viewName = .ok ()) :
    ∃ b, encodeCallableV1 (simpleClosureViewCallableV1 viewName) = .ok b ∧
      b.size ≤ 2048 := by
  have hstr := encodeString_eq_ok_of_validateIdentifierComponent viewName hname
  have hopt := encodeOptionString_some_eq_ok viewName _ hstr
  let nameB := (encodeU8 1).append
    ((encodeU32le (UInt32.ofNat viewName.toUTF8.size)).append viewName.toUTF8)
  have hnameB : encodeOption encodeString (some viewName) = .ok nameB := hopt
  have hkind := encodeCallableKind_view_eq
  have hparams := encodeArray_zeroV1 encodeParameterV1
  have hresult := encodeCallableResult_publicBool_eq
  have hblocks :=
    encodeArray_oneV1 encodeBlockV1 simpleClosureBlockV1 blockB
      encodeBlock_simpleClosure_eq
  have hloop := encodeArray_zeroV1 encodeLoopBoundV1
  have hsteps :
      encodeOption (fun v => pure (encodeU64le v)) (none : Option UInt64) =
        .ok (encodeU8 0) := rfl
  let kindB := taggedBytesV1 "Callable.View" #[]
  let paramsB := encodeU32le 0
  let resultB := taggedBytesV1 "CallableResult"
    #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]
  let blocksB := (encodeU32le 1).append blockB
  let loopB := encodeU32le 0
  let stepsB := encodeU8 0
  let out := taggedBytesV1 "Callable"
    #[encodeU32le 0, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
      stepsB]
  have htag :
      encodeTagged "Callable"
          #[encodeU32le 0, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB,
            loopB, stepsB] =
        .ok out := by
    simp only [out]
    exact encodeTagged_eq_okV1 "Callable"
      #[encodeU32le 0, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
        stepsB]
      (by decide) (by decide) (by decide) (by decide)
      (by decide : (9 : Nat) ≤ UInt16.size - 1)
  have henc :=
    encodeCallableV1_eq_of_fields
      (simpleClosureViewCallableV1 viewName)
      kindB nameB paramsB resultB blocksB loopB stepsB out hkind hnameB hparams
      hresult hblocks hloop hsteps htag
  refine ⟨out, henc, ?_⟩
  have hn : nameB.size ≤ 245 := by
    simpa [nameB] using optionString_size_le_245 viewName hname
  have hb' := blockB_size_le
  have hk : kindB.size ≤ 32 := by simpa [kindB] using callableView_kind_size_le
  have hr : resultB.size ≤ 64 := by simpa [resultB] using callableResult_size_le
  have hblk : blocksB.size = 4 + blockB.size := by
    simp only [blocksB]; rw [ByteArray_size_append, encodeU32le_size]
  have hfold :=
    foldl_size_nine (encodeU32le 0) kindB nameB paramsB resultB (encodeU32le 0)
      blocksB loopB stepsB
  have ht : ("Callable".toUTF8.size : Nat) = 8 := by decide
  have hsz : out.size =
      6 + 8 + (4 + kindB.size + nameB.size + 4 + resultB.size + 4 +
        blocksB.size + 4 + 1) := by
    simp only [out, taggedBytesV1_size]
    rw [ht, hfold]
    simp only [paramsB, loopB, stepsB, encodeU32le_size, encodeU8_size]
  have hgoal :
      out.size ≤ 6 + 8 + (4 + 32 + 245 + 4 + 64 + 4 + (4 + 512) + 4 + 1) := by
    rw [hsz]
    have : blocksB.size ≤ 4 + 512 := by omega
    omega
  exact Nat.le_trans hgoal (by decide)

/-! ### Invariant callable -/

private theorem encodeOption_some_u64 (v : UInt64) :
    encodeOption (fun x => pure (encodeU64le x)) (some v) =
      .ok ((encodeU8 1).append (encodeU64le v)) := by
  simp only [encodeOption, pure, Except.pure, Bind.bind, Except.bind]

theorem encodeInvCallable_ok
    (invName : String) (hname : validateIdentifierComponent invName = .ok ()) :
    ∃ b, encodeCallableV1 (simpleClosureInvCallableV1 invName) = .ok b := by
  have hstr := encodeString_eq_ok_of_validateIdentifierComponent invName hname
  have hopt := encodeOptionString_some_eq_ok invName _ hstr
  let nameB := (encodeU8 1).append
    ((encodeU32le (UInt32.ofNat invName.toUTF8.size)).append invName.toUTF8)
  have hnameB : encodeOption encodeString (some invName) = .ok nameB := hopt
  have hkind := encodeCallableKind_invariant_eq
  have hparams := encodeArray_zeroV1 encodeParameterV1
  have hresult := encodeCallableResult_publicBool_eq
  have hblocks :=
    encodeArray_oneV1 encodeBlockV1 simpleClosureBlockV1 blockB
      encodeBlock_simpleClosure_eq
  have hloop := encodeArray_zeroV1 encodeLoopBoundV1
  have hsteps := encodeOption_some_u64 3
  let kindB := taggedBytesV1 "Callable.Invariant" #[]
  let paramsB := encodeU32le 0
  let resultB := taggedBytesV1 "CallableResult"
    #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]
  let blocksB := (encodeU32le 1).append blockB
  let loopB := encodeU32le 0
  let stepsB := (encodeU8 1).append (encodeU64le 3)
  let out := taggedBytesV1 "Callable"
    #[encodeU32le 1, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
      stepsB]
  have htag :
      encodeTagged "Callable"
          #[encodeU32le 1, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB,
            loopB, stepsB] =
        .ok out := by
    simp only [out]
    exact encodeTagged_eq_okV1 "Callable"
      #[encodeU32le 1, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
        stepsB]
      (by decide) (by decide) (by decide) (by decide)
      (by decide : (9 : Nat) ≤ UInt16.size - 1)
  have henc :=
    encodeCallableV1_eq_of_fields
      (simpleClosureInvCallableV1 invName)
      kindB nameB paramsB resultB blocksB loopB stepsB out hkind hnameB hparams
      hresult hblocks hloop hsteps htag
  exact ⟨out, henc⟩

theorem encodeInvCallable_ok_size
    (invName : String) (hname : validateIdentifierComponent invName = .ok ()) :
    ∃ b, encodeCallableV1 (simpleClosureInvCallableV1 invName) = .ok b ∧
      b.size ≤ 2048 := by
  have hstr := encodeString_eq_ok_of_validateIdentifierComponent invName hname
  have hopt := encodeOptionString_some_eq_ok invName _ hstr
  let nameB := (encodeU8 1).append
    ((encodeU32le (UInt32.ofNat invName.toUTF8.size)).append invName.toUTF8)
  have hnameB : encodeOption encodeString (some invName) = .ok nameB := hopt
  have hkind := encodeCallableKind_invariant_eq
  have hparams := encodeArray_zeroV1 encodeParameterV1
  have hresult := encodeCallableResult_publicBool_eq
  have hblocks :=
    encodeArray_oneV1 encodeBlockV1 simpleClosureBlockV1 blockB
      encodeBlock_simpleClosure_eq
  have hloop := encodeArray_zeroV1 encodeLoopBoundV1
  have hsteps := encodeOption_some_u64 3
  let kindB := taggedBytesV1 "Callable.Invariant" #[]
  let paramsB := encodeU32le 0
  let resultB := taggedBytesV1 "CallableResult"
    #[encodeU32le 0, taggedBytesV1 "Visibility.Public" #[]]
  let blocksB := (encodeU32le 1).append blockB
  let loopB := encodeU32le 0
  let stepsB := (encodeU8 1).append (encodeU64le 3)
  let out := taggedBytesV1 "Callable"
    #[encodeU32le 1, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
      stepsB]
  have htag :
      encodeTagged "Callable"
          #[encodeU32le 1, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB,
            loopB, stepsB] =
        .ok out := by
    simp only [out]
    exact encodeTagged_eq_okV1 "Callable"
      #[encodeU32le 1, kindB, nameB, paramsB, resultB, encodeU32le 0, blocksB, loopB,
        stepsB]
      (by decide) (by decide) (by decide) (by decide)
      (by decide : (9 : Nat) ≤ UInt16.size - 1)
  have henc :=
    encodeCallableV1_eq_of_fields
      (simpleClosureInvCallableV1 invName)
      kindB nameB paramsB resultB blocksB loopB stepsB out hkind hnameB hparams
      hresult hblocks hloop hsteps htag
  refine ⟨out, henc, ?_⟩
  have hn : nameB.size ≤ 245 := by
    simpa [nameB] using optionString_size_le_245 invName hname
  have hb' := blockB_size_le
  have hk : kindB.size ≤ 40 := by simpa [kindB] using callableInv_kind_size_le
  have hr : resultB.size ≤ 64 := by simpa [resultB] using callableResult_size_le
  have hblk : blocksB.size = 4 + blockB.size := by
    simp only [blocksB]; rw [ByteArray_size_append, encodeU32le_size]
  have hfold :=
    foldl_size_nine (encodeU32le 1) kindB nameB paramsB resultB (encodeU32le 0)
      blocksB loopB stepsB
  have ht : ("Callable".toUTF8.size : Nat) = 8 := by decide
  have hsz : out.size =
      6 + 8 + (4 + kindB.size + nameB.size + 4 + resultB.size + 4 +
        blocksB.size + 4 + 9) := by
    simp only [out, taggedBytesV1_size]
    rw [ht, hfold]
    simp only [paramsB, loopB, stepsB, encodeU32le_size, encodeU8_size,
      encodeU64le_size, ByteArray_size_append]
  have hgoal :
      out.size ≤ 6 + 8 + (4 + 40 + 245 + 4 + 64 + 4 + (4 + 512) + 4 + 9) := by
    rw [hsz]
    have : blocksB.size ≤ 4 + 512 := by omega
    omega
  exact Nat.le_trans hgoal (by decide)

theorem encodeCallables_materialize_ok_size
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    ∃ b, encodeArray encodeCallableV1 (materializeSimpleClosureDataV1 p).callables =
        .ok b ∧ b.size ≤ 4200 := by
  obtain ⟨viewB, hview, hviewSz⟩ :=
    encodeViewCallable_ok_size p.viewName legal.hview
  obtain ⟨invB, hinv, hinvSz⟩ :=
    encodeInvCallable_ok_size p.invName legal.hinv
  have htwo :=
    encodeArray_twoV1 encodeCallableV1
      (simpleClosureViewCallableV1 p.viewName)
      (simpleClosureInvCallableV1 p.invName)
      viewB invB hview hinv
  refine ⟨(encodeU32le 2).append (viewB.append invB), ?_, ?_⟩
  · simpa [materializeSimpleClosureDataV1] using htwo
  · rw [ByteArray_size_append, encodeU32le_size, ByteArray_size_append]
    omega

/-! ### InvariantDecl -/

theorem encodeInvariantDecl_ok_size
    (invName : String) (hname : validateIdentifierComponent invName = .ok ()) :
    ∃ b, encodeInvariantDeclV1 (simpleClosureInvariantDeclV1 invName) = .ok b ∧
      b.size ≤ 512 := by
  have hstr := encodeString_eq_ok_of_validateIdentifierComponent invName hname
  let nameB :=
    (encodeU32le (UInt32.ofNat invName.toUTF8.size)).append invName.toUTF8
  have hnameB : encodeString invName = .ok nameB := hstr
  let out := taggedBytesV1 "InvariantDecl"
    #[encodeU32le 0, nameB, encodeU32le 1]
  have htag :
      encodeTagged "InvariantDecl" #[encodeU32le 0, nameB, encodeU32le 1] =
        .ok out := by
    simp only [out]
    have hfs :
        (#[encodeU32le 0, nameB, encodeU32le 1] : Array ByteArray).size ≤
          UInt16.size - 1 := by
      change (3 : Nat) ≤ UInt16.size - 1
      decide
    exact encodeTagged_eq_okV1 "InvariantDecl" #[encodeU32le 0, nameB, encodeU32le 1]
      (by decide) (by decide) (by decide) (by decide) hfs
  have henc : encodeInvariantDeclV1 (simpleClosureInvariantDeclV1 invName) = .ok out := by
    simp only [encodeInvariantDeclV1, simpleClosureInvariantDeclV1, hnameB, htag,
      Bind.bind, Except.bind]
  refine ⟨out, henc, ?_⟩
  have hn : nameB.size ≤ 244 :=
    encodeString_size_le_244_of_ident invName hname hstr
  have hfold := foldl_size_three (encodeU32le 0) nameB (encodeU32le 1)
  have ht : ("InvariantDecl".toUTF8.size : Nat) = 13 := by decide
  have hsz : out.size = 6 + 13 + (4 + nameB.size + 4) := by
    simp only [out, taggedBytesV1_size]
    rw [ht, hfold, encodeU32le_size, encodeU32le_size]
  have hgoal : out.size ≤ 6 + 13 + (4 + 244 + 4) := by
    rw [hsz]; omega
  exact Nat.le_trans hgoal (by decide)

theorem encodeInvariants_materialize_ok_size
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    ∃ b, encodeArray encodeInvariantDeclV1
        (materializeSimpleClosureDataV1 p).invariants = .ok b ∧ b.size ≤ 600 := by
  obtain ⟨invB, hinv, hinvSz⟩ :=
    encodeInvariantDecl_ok_size p.invName legal.hinv
  have hone :=
    encodeArray_oneV1 encodeInvariantDeclV1
      (simpleClosureInvariantDeclV1 p.invName) invB hinv
  refine ⟨(encodeU32le 1).append invB, ?_, ?_⟩
  · simpa [materializeSimpleClosureDataV1] using hone
  · rw [ByteArray_size_append, encodeU32le_size]
    omega

/-! ### Fixed value.bool requirements -/

private theorem encodeString_value_bool :
    encodeString "value.bool" =
      .ok ((encodeU32le (UInt32.ofNat "value.bool".toUTF8.size)).append
        "value.bool".toUTF8) :=
  encodeString_eq_ok_of_ascii "value.bool" (by decide) (by decide)

private theorem encodeString_1_0_0 :
    encodeString "1.0.0" =
      .ok ((encodeU32le (UInt32.ofNat "1.0.0".toUTF8.size)).append "1.0.0".toUTF8) :=
  encodeString_eq_ok_of_ascii "1.0.0" (by decide) (by decide)

private theorem renderSemVer_s2 :
    renderSemVer s2RequirementVersionV1 = .ok "1.0.0" := by
  -- Empty prerelease/build: validateSemVer is a no-op for-loop; render is "1.0.0".
  simp only [s2RequirementVersionV1, renderSemVer, validateSemVer]
  rfl

private theorem encodeSemVer_s2 :
    encodeSemVer s2RequirementVersionV1 =
      .ok ((encodeU32le (UInt32.ofNat "1.0.0".toUTF8.size)).append "1.0.0".toUTF8) := by
  simp only [encodeSemVer, mapCommon, renderSemVer_s2, encodeString_1_0_0,
    Bind.bind, Except.bind]

private theorem s2ValueBoolDigestBytesV1_size :
    s2ValueBoolDigestBytesV1.size = 32 := by
  decide

private theorem validateDigest_value_bool :
    validateDigest
        { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 } = .ok () := by
  simp only [validateDigest, s2ValueBoolDigestBytesV1_size, ↓reduceIte, Pure.pure,
    Except.pure]

private theorem encodeDigest_value_bool :
    encodeDigest { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 } =
      .ok s2ValueBoolDigestBytesV1 := by
  simp only [encodeDigest, mapCommon, validateDigest_value_bool, Bind.bind,
    Pure.pure, Except.bind, Except.pure]

private theorem encodeRequirementRequest_value_bool_ok :
    ∃ b, encodeRequirementRequestV1 simpleClosureBoolRequirementV1 = .ok b ∧
      b.size ≤ 256 := by
  let idB :=
    (encodeU32le (UInt32.ofNat "value.bool".toUTF8.size)).append "value.bool".toUTF8
  let verB :=
    (encodeU32le (UInt32.ofNat "1.0.0".toUTF8.size)).append "1.0.0".toUTF8
  let digB := s2ValueBoolDigestBytesV1
  have hid : encodeString "value.bool" = .ok idB := encodeString_value_bool
  have hver : encodeSemVer s2RequirementVersionV1 = .ok verB := encodeSemVer_s2
  have hdig :
      encodeDigest { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 } =
        .ok digB := encodeDigest_value_bool
  have hpred := encodeArray_zeroV1 encodeRequirementPredicateV1
  let out := taggedBytesV1 "RequirementRequest"
    #[idB, verB, digB, encodeU32le 0]
  have hfs :
      (#[idB, verB, digB, encodeU32le 0] : Array ByteArray).size ≤
        UInt16.size - 1 := by
    change (4 : Nat) ≤ UInt16.size - 1
    decide
  have htag :
      encodeTagged "RequirementRequest" #[idB, verB, digB, encodeU32le 0] =
        .ok out := by
    simp only [out]
    exact encodeTagged_eq_okV1 "RequirementRequest"
      #[idB, verB, digB, encodeU32le 0]
      (by decide) (by decide) (by decide) (by decide) hfs
  have henc :
      encodeRequirementRequestV1 simpleClosureBoolRequirementV1 = .ok out := by
    simp only [encodeRequirementRequestV1, simpleClosureBoolRequirementV1, hid,
      hver, hdig, hpred, htag, Bind.bind, Except.bind]
  refine ⟨out, henc, ?_⟩
  have hidSz : idB.size = 14 := by
    simp only [idB]; rw [ByteArray_size_append, encodeU32le_size]
    decide
  have hverSz : verB.size = 9 := by
    simp only [verB]; rw [ByteArray_size_append, encodeU32le_size]
    decide
  have hdigSz : digB.size = 32 := by
    simpa [digB] using s2ValueBoolDigestBytesV1_size
  have hpredSz : (encodeU32le 0).size = 4 := encodeU32le_size 0
  have hfold := foldl_size_four idB verB digB (encodeU32le 0)
  have ht : ("RequirementRequest".toUTF8.size : Nat) = 18 := by decide
  have hsz : out.size = 6 + 18 + (14 + 9 + 32 + 4) := by
    simp only [out, taggedBytesV1_size]
    rw [ht, hfold, hidSz, hverSz, hdigSz, hpredSz]
  have : out.size = 83 := by rw [hsz]
  omega

theorem encodeRequirements_materialize_ok_size (p : SimpleClosureParamsV1) :
    ∃ b, encodeProgramRequirementsV1
        (materializeSimpleClosureDataV1 p).requirements = .ok b ∧
      b.size ≤ 400 := by
  obtain ⟨reqItemB, hitem, hitemSz⟩ := encodeRequirementRequest_value_bool_ok
  have hone :=
    encodeArray_oneV1 encodeRequirementRequestV1 simpleClosureBoolRequirementV1
      reqItemB hitem
  let itemsB := (encodeU32le 1).append reqItemB
  have hitems :
      encodeArray encodeRequirementRequestV1
          (#[simpleClosureBoolRequirementV1] : Array RequirementRequestV1) =
        .ok itemsB := hone
  let out := taggedBytesV1 "ProgramRequirements" #[itemsB]
  have hfs :
      (#[itemsB] : Array ByteArray).size ≤ UInt16.size - 1 := by
    change (1 : Nat) ≤ UInt16.size - 1
    decide
  have htag :
      encodeTagged "ProgramRequirements" #[itemsB] = .ok out := by
    simp only [out]
    exact encodeTagged_eq_okV1 "ProgramRequirements" #[itemsB]
      (by decide) (by decide) (by decide) (by decide) hfs
  have henc :
      encodeProgramRequirementsV1
          (materializeSimpleClosureDataV1 p).requirements = .ok out := by
    simp only [encodeProgramRequirementsV1, materializeSimpleClosureDataV1,
      hitems, htag, Bind.bind, Except.bind]
  refine ⟨out, henc, ?_⟩
  have hitemsSz : itemsB.size = 4 + reqItemB.size := by
    simp only [itemsB]; rw [ByteArray_size_append, encodeU32le_size]
  have ht : ("ProgramRequirements".toUTF8.size : Nat) = 19 := by decide
  have hfold1 : (#[itemsB] : Array ByteArray).foldl (fun n f => n + f.size) 0 =
      itemsB.size := by
    simp [List.foldl]
  have hsz : out.size = 6 + 19 + itemsB.size := by
    simp only [out, taggedBytesV1_size]
    rw [ht, hfold1]
  have : out.size ≤ 6 + 19 + (4 + 256) := by
    rw [hsz, hitemsSz]; omega
  exact Nat.le_trans this (by decide)

/-! ### Body encode from legal alone -/

theorem encodeSimpleClosureDataFields_ok_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    ∃ b, encodeSimpleClosureDataFieldsV1 p = .ok b := by
  obtain ⟨qnB, hqn, hqnSz⟩ :=
    encodeQualifiedName_materialize_ok_size_of_legal p legal
  obtain ⟨typesB, htypes, htypesSz⟩ := encodeTypes_materialize_ok_size p
  have hconst := encodeEmptyConstants_materialize p
  have hstate := encodeEmptyLogicalState_materialize p
  have hevents := encodeEmptyEvents_materialize p
  have herrors := encodeEmptyErrors_materialize p
  obtain ⟨callablesB, hcallables, hcallablesSz⟩ :=
    encodeCallables_materialize_ok_size p legal
  obtain ⟨invariantsB, hinvariants, hinvariantsSz⟩ :=
    encodeInvariants_materialize_ok_size p legal
  obtain ⟨reqB, hreq, hreqSz⟩ := encodeRequirements_materialize_ok_size p
  let emptyB := simpleClosureEmptyTableBytesV1
  have hemptySz : emptyB.size = 4 := by
    simp only [emptyB, simpleClosureEmptyTableBytesV1, encodeU32le_size]
  let body := taggedBytesV1 "SemanticProgram.Data"
    #[qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB, invariantsB, reqB]
  have htag :
      encodeTagged "SemanticProgram.Data"
          #[qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB, invariantsB,
            reqB] =
        .ok body := by
    simp only [body]
    have hfs :
        (#[qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB, invariantsB,
            reqB] : Array ByteArray).size ≤ UInt16.size - 1 := by
      change (9 : Nat) ≤ UInt16.size - 1
      decide
    exact encodeTagged_eq_okV1 "SemanticProgram.Data"
      #[qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB, invariantsB, reqB]
      (by decide) (by decide) (by decide) (by decide) hfs
  -- Size: qn ≤ 4+256*244=62468; types≤200; empty×4=16; callables≤4200;
  -- invariants≤600; req≤400; tag≤64 → body ≤ 6+64+9*62468 ≪ 64MiB, tighter:
  have hqnCap : p.qnSize ≤ 256 := legal.hqnCap
  have hqnLoose : qnB.size ≤ 70000 := by
    have : 4 + p.qnSize * 244 ≤ 4 + 256 * 244 := by
      have : p.qnSize * 244 ≤ 256 * 244 := Nat.mul_le_mul_right _ hqnCap
      omega
    omega
  have hfieldBound : ∀ f ∈
      ([qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB, invariantsB, reqB] :
        List ByteArray),
      f.size ≤ 70000 := by
    intro f hf
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hf
    rcases hf with
      rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact hqnLoose
    · exact Nat.le_trans htypesSz (by decide)
    · omega
    · omega
    · omega
    · omega
    · exact Nat.le_trans hcallablesSz (by decide)
    · exact Nat.le_trans hinvariantsSz (by decide)
    · exact Nat.le_trans hreqSz (by decide)
  have hbodySz : body.size ≤ 6 + 64 + 9 * 70000 := by
    simpa [body] using
      taggedBytesV1_size_le "SemanticProgram.Data"
        #[qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB, invariantsB, reqB]
        70000 (by decide) (by
          intro f hf
          have : (#[qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB,
              invariantsB, reqB] : Array ByteArray).toList =
              [qnB, typesB, emptyB, emptyB, emptyB, emptyB, callablesB, invariantsB,
                reqB] := by
            simp
          rw [this] at hf
          exact hfieldBound f hf)
  have hmagicSz :
      ((encodeMagicPrefix semanticProgramMagicV1).append body).size ≤
        maxCanonicalProgramBytes := by
    have hmagic : (encodeMagicPrefix semanticProgramMagicV1).size = 15 := by
      simp only [encodeMagicPrefix_size]
      decide
    rw [ByteArray_size_append, hmagic]
    -- 15 + 6 + 64 + 630000 = 630085 ≤ 64*1024*1024
    exact Nat.le_trans (Nat.add_le_add_left hbodySz 15) (by decide)
  -- constants/state/events/errors all encode to emptyB
  have hconst' :
      encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 p).constants =
        .ok emptyB := by
    simpa [emptyB, simpleClosureEmptyTableBytesV1] using hconst
  have hstate' :
      encodeArray encodeStateDeclV1 (materializeSimpleClosureDataV1 p).logicalState =
        .ok emptyB := by
    simpa [emptyB, simpleClosureEmptyTableBytesV1] using hstate
  have hevents' :
      encodeArray encodeEventDeclV1 (materializeSimpleClosureDataV1 p).events =
        .ok emptyB := by
    simpa [emptyB, simpleClosureEmptyTableBytesV1] using hevents
  have herrors' :
      encodeArray encodeErrorDeclV1 (materializeSimpleClosureDataV1 p).errors =
        .ok emptyB := by
    simpa [emptyB, simpleClosureEmptyTableBytesV1] using herrors
  have hbody :=
    encodeSemanticProgramDataBodyV1_eq_of_fields
      (materializeSimpleClosureDataV1 p)
      qnB typesB emptyB emptyB emptyB emptyB callablesB invariantsB reqB body
      hqn htypes hconst' hstate' hevents' herrors' hcallables hinvariants hreq
      htag hmagicSz
  refine ⟨(encodeMagicPrefix semanticProgramMagicV1).append body, ?_⟩
  simpa [encodeSimpleClosureDataFieldsV1] using hbody

/-- B-SC-ENC legal-only main theorem. -/
theorem encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) :=
  encodeSimpleClosureGoal_of_body_exists p legal
    (encodeSimpleClosureDataFields_ok_of_legal p legal)

/-- Public alias for the closed encode goal. -/
theorem encodeSimpleClosure_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    EncodeSimpleClosureGoalV1 p :=
  encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1_of_legal p legal

/-! ### Concrete kernel instances (Demo; Unicode via parametric legal) -/

-- Concrete Demo identifiers (ASCII NFC free).
private theorem demo_ident_Demo :
    validateIdentifierComponent "Demo" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Demo" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_Module :
    validateIdentifierComponent "Module" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Module" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_Prog :
    validateIdentifierComponent "Prog" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Prog" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_alive :
    validateIdentifierComponent "alive" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "alive" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_safe :
    validateIdentifierComponent "safe" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "safe" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

def demoParamsV1 : SimpleClosureParamsV1 :=
  {
    qnHead := "Demo"
    qnTail := #["Module", "Prog"]
    viewName := "alive"
    invName := "safe"
  }

theorem demoParamsV1_legal : SimpleClosureParamsLegalV1 demoParamsV1 := by
  refine {
    hqnSize := by decide
    hqnCap := by decide
    hdistinct := by decide
    hqnHead := demo_ident_Demo
    hqnTail := ?_
    hview := demo_ident_alive
    hinv := demo_ident_safe
  }
  intro i hi
  have hlt : i < 2 := by simpa [demoParamsV1] using hi
  match i with
  | 0 => exact demo_ident_Module
  | 1 => exact demo_ident_Prog
  | n + 2 => omega

/-- Demo kernel theorem: legal alone ⇒ encode = wireBytes (no body-ok premise). -/
theorem encodeSimpleClosure_demo :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 demoParamsV1) =
      .ok (simpleClosureWireBytesV1 demoParamsV1) :=
  encodeSimpleClosure_of_legal demoParamsV1 demoParamsV1_legal

/-- Parametric Unicode/NFC coverage: any `SimpleClosureParamsLegalV1` name
    payload (including non-ASCII UTF-8 identifiers ≤240 bytes) closes encode.
    Concrete non-ASCII NFC discharge is a Unicode-table concern; the encode
    path itself imposes no ASCII restriction. -/
theorem encodeSimpleClosure_of_legal_unicodeCapable
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) :=
  encodeSimpleClosure_of_legal p legal

end ProofForgeV2.Semantic.SimpleClosureEncodeFieldsV1
