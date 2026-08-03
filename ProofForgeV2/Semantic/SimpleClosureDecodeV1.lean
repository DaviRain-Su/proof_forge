import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1

/-!
  ProofForgeV2.Semantic.SimpleClosureDecodeV1 — B-SC-DEC slice for the
  name-parameterized SimpleClosure materialize family.

  Goal (family form):
    decodeSemanticProgramDataV1 (simpleClosureWireBytesV1 p) =
      .ok (materializeSimpleClosureDataV1 p)

  under well-formed / ASCII-name hypotheses. Bytes are built by transparent
  name-parameterized spines (no Tests FQN, no fixture hardcode).

  Current shipped foundation (honest):
    * reusable CodecRoundtripV1 mid-offset u8/u16/u32/array-count/option/
      field-count lemmas (imported)
    * fixed micro-spines for magic, root header, Bool+UInt64 types, empty
      tables, literal-true block body, value.bool requirements (name-free)
    * name-parameterized QN / view / inv string hole constructors
    * empty-table decode at parametric offsets
    * finish @ exact total length
    * framing composition interface ready for field successes

  Remaining to close B-SC-DEC product-positively:
    * name-hole string/QN/callable/invariant field decoders at dynamic offsets
    * full nine-field tagged root composition for arbitrary well-formed p
    * dual encode-spine identity (B-SC-ENC) so encode(materialize p) equals
      the transparent wire bytes (then decode premise discharges WireTrace)

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
  Does not hardcode Tests FQN or 1.2k-line per-program scripts.
-/

namespace ProofForgeV2.Semantic.SimpleClosureDecodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Fixed (name-free) transparent spines -/

/-- Production magic `pf.semantic.v1\0`. -/
def simpleClosureMagicSpineV1 : TransparentByteSpineV1 :=
  [112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118, 49, 0]

/-- Root tagged header: `SemanticProgram.Data` / 9 fields. -/
def simpleClosureRootHeaderSpineV1 : TransparentByteSpineV1 :=
  [20, 0, 0, 0, 83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103,
    114, 97, 109, 46, 68, 97, 116, 97, 9, 0]

/-- Anonymous Bool + anonymous UInt64 type table (Normalize envelope). -/
def simpleClosureTypesSpineV1 : TransparentByteSpineV1 :=
  [2, 0, 0, 0,
    -- TypeDecl id=0 name=none shape=Bool
    8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0,
    0, 0, 0, 0, 0,
    9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0,
    -- TypeDecl id=1 name=none shape=UInt 64
    8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0,
    1, 0, 0, 0, 0,
    9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

/-- Empty table array header (count = 0). -/
def simpleClosureEmptyTableSpineV1 : TransparentByteSpineV1 :=
  u32leSpine0V1

/-- Four empty tables: constants / logicalState / events / errors. -/
def simpleClosureEmptyTablesSpineV1 : TransparentByteSpineV1 :=
  simpleClosureEmptyTableSpineV1 ++ simpleClosureEmptyTableSpineV1 ++
    simpleClosureEmptyTableSpineV1 ++ simpleClosureEmptyTableSpineV1

/-- Callables array count = 2. -/
def simpleClosureCallablesHeaderSpineV1 : TransparentByteSpineV1 :=
  u32leSpine2V1

/-- Shared literal-true single-block body (after callable name/result headers).
    Instruction: Option.some ValueDef(0,Bool) + Op.Literal Bool true;
    Term.Return (some 0); empty loopBounds. -/
def simpleClosureLitTrueBlockBodySpineV1 : TransparentByteSpineV1 :=
  [ -- entryBlock = 0
    0, 0, 0, 0,
    -- blocks count = 1
    1, 0, 0, 0,
    -- Block tag + 4 fields
    5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0,
    -- block id = 0
    0, 0, 0, 0,
    -- params empty
    0, 0, 0, 0,
    -- instructions count = 1
    1, 0, 0, 0,
    -- Instruction tag + 2 fields
    11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0,
    -- Option.some ValueDef
    1,
    8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0,
    0, 0, 0, 0,  -- valueId
    0, 0, 0, 0,  -- typeId
    -- Op.Literal typeId=0 valueBytes=[1]
    10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0,
    0, 0, 0, 0,
    1, 0, 0, 0, 1,
    -- Term.Return some 0
    11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0,
    1, 0, 0, 0, 0,
    -- loopBounds empty
    0, 0, 0, 0
  ]

/-- View kind nullary tag `Callable.View`. -/
def simpleClosureViewKindSpineV1 : TransparentByteSpineV1 :=
  [13, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119, 0, 0]

/-- Invariant kind nullary tag `Callable.Invariant`. -/
def simpleClosureInvKindSpineV1 : TransparentByteSpineV1 :=
  [18, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114,
    105, 97, 110, 116, 0, 0]

/-- Public Bool CallableResult. -/
def simpleClosurePublicBoolResultSpineV1 : TransparentByteSpineV1 :=
  [14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116,
    2, 0,
    0, 0, 0, 0,  -- typeId Bool
    17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98,
    108, 105, 99, 0, 0]

/-- Closed S2 `value.bool` ProgramRequirements row (transparent digest). -/
def simpleClosureRequirementsSpineV1 : TransparentByteSpineV1 :=
  [19, 0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101,
    109, 101, 110, 116, 115, 1, 0,
    1, 0, 0, 0,  -- items count
    18, 0, 0, 0, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101,
    113, 117, 101, 115, 116, 4, 0,
    10, 0, 0, 0, 118, 97, 108, 117, 101, 46, 98, 111, 111, 108,
    5, 0, 0, 0, 49, 46, 48, 46, 48] ++
    s2ValueBoolDigestBytesV1.data.toList ++
    [0, 0, 0, 0]  -- empty predicates

/-! ### Name-parameterized holes (ASCII UTF-8 spines) -/

/-- LE u32 of a Nat (caller ensures fit in u32). -/
def natU32leSpineV1 (n : Nat) : TransparentByteSpineV1 :=
  [UInt8.ofNat (n % 256), UInt8.ofNat ((n / 256) % 256),
   UInt8.ofNat ((n / 65536) % 256), UInt8.ofNat ((n / 16777216) % 256)]

/-- Length-prefixed UTF-8 string spine from a Lean String. -/
def stringSpineV1 (s : String) : TransparentByteSpineV1 :=
  natU32leSpineV1 s.toUTF8.size ++ s.toUTF8.data.toList

/-- Option.some string spine. -/
def someStringSpineV1 (s : String) : TransparentByteSpineV1 :=
  (1 : UInt8) :: stringSpineV1 s

/-- Option.none spine. -/
def noneSpineV1 : TransparentByteSpineV1 :=
  [0]

/-- QualifiedName component array spine: count + each string. -/
def qualifiedNameSpineV1 (p : SimpleClosureParamsV1) : TransparentByteSpineV1 :=
  natU32leSpineV1 p.qnSize ++
    stringSpineV1 p.qnHead ++
    p.qnTail.foldl (fun acc s => acc ++ stringSpineV1 s) []

/-- Callable header tag `Callable` / 9 fields. -/
def callableHeaderSpineV1 : TransparentByteSpineV1 :=
  [8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0]

/-- View callable spine: id=0, View kind, some viewName, empty params, public Bool
    result, lit-true block, steps=none. -/
def viewCallableSpineV1 (viewName : String) : TransparentByteSpineV1 :=
  callableHeaderSpineV1 ++
    u32leSpine0V1 ++  -- id
    simpleClosureViewKindSpineV1 ++
    someStringSpineV1 viewName ++
    u32leSpine0V1 ++  -- empty params
    simpleClosurePublicBoolResultSpineV1 ++
    simpleClosureLitTrueBlockBodySpineV1 ++
    noneSpineV1  -- invariantSteps

/-- Option.some invariantSteps = 3. -/
def invStepsSome3SpineV1 : TransparentByteSpineV1 :=
  (1 : UInt8) :: u32leSpine3V1

/-- Invariant callable spine: id=1, Invariant kind, some invName, empty params,
    public Bool result, lit-true block, steps=some 3. -/
def invCallableSpineV1 (invName : String) : TransparentByteSpineV1 :=
  callableHeaderSpineV1 ++
    u32leSpine1V1 ++
    simpleClosureInvKindSpineV1 ++
    someStringSpineV1 invName ++
    u32leSpine0V1 ++
    simpleClosurePublicBoolResultSpineV1 ++
    simpleClosureLitTrueBlockBodySpineV1 ++
    invStepsSome3SpineV1

/-- InvariantDecl array: count=1, decl id=0 name=invName callableId=1. -/
def invariantDeclSpineV1 (invName : String) : TransparentByteSpineV1 :=
  u32leSpine1V1 ++
    [13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108, 3, 0] ++
    u32leSpine0V1 ++
    stringSpineV1 invName ++
    u32leSpine1V1

/-- Full name-parameterized SimpleClosure wire spine (transport bytes). -/
def simpleClosureWireSpineV1 (p : SimpleClosureParamsV1) : TransparentByteSpineV1 :=
  simpleClosureMagicSpineV1 ++
    simpleClosureRootHeaderSpineV1 ++
    qualifiedNameSpineV1 p ++
    simpleClosureTypesSpineV1 ++
    simpleClosureEmptyTablesSpineV1 ++
    simpleClosureCallablesHeaderSpineV1 ++
    viewCallableSpineV1 p.viewName ++
    invCallableSpineV1 p.invName ++
    invariantDeclSpineV1 p.invName ++
    simpleClosureRequirementsSpineV1

/-- Production ByteArray of the parametric wire spine. -/
def simpleClosureWireBytesV1 (p : SimpleClosureParamsV1) : ByteArray :=
  ByteArray.mk (simpleClosureWireSpineV1 p).toArray

/-! ### ASCII / well-formed certificate hypotheses for name holes -/

/-- Engineering ASCII gate for parametric string holes (NFC free via isAscii).
    Tail components are required pairwise via `List` so kernel proofs avoid
    opaque `Array.all` reduction (no native_decide). -/
structure SimpleClosureAsciiNamesV1 (p : SimpleClosureParamsV1) : Prop where
  hhead : isAscii p.qnHead = true
  hview : isAscii p.viewName = true
  hinv : isAscii p.invName = true
  htail : ∀ s ∈ p.qnTail.toList, isAscii s = true

/-! ### Fixed-spine length lemmas -/

theorem magicSpine_length : simpleClosureMagicSpineV1.length = 15 := by
  rfl

theorem rootHeaderSpine_length : simpleClosureRootHeaderSpineV1.length = 26 := by
  rfl

theorem typesSpine_length : simpleClosureTypesSpineV1.length = 74 := by
  rfl

theorem emptyTablesSpine_length : simpleClosureEmptyTablesSpineV1.length = 16 := by
  rfl

theorem callablesHeader_length : simpleClosureCallablesHeaderSpineV1.length = 4 := by
  rfl

/-! ### Empty-table decode at parametric offsets -/

/-- Decode one empty array (constants-shaped) at a mid offset whose next 4 bytes
    are the zero u32le header. -/
theorem decodeEmptyArray_midV1 (maxCount : Nat) (decode : Decoder α)
    (left right : List UInt8) (nesting : Nat) :
    decodeArray maxCount decode
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray, left.length, nesting⟩ =
      .ok (#[],
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray,
          left.length + 4, nesting⟩) :=
  decodeArray_zero_midV1 maxCount decode left right nesting

/-! ### Magic + root header composition (name-independent) -/

theorem consumeMagicSpine_simpleClosure
    (rest : TransparentByteSpineV1) :
    consumeMagicSpineBytesV1 (simpleClosureMagicSpineV1 ++ rest) 0
        simpleClosureMagicSpineV1 = .ok 15 := by
  unfold consumeMagicSpineBytesV1 takeSpineBytesV1 spineRemainingV1
  have hlen :
      simpleClosureMagicSpineV1.length ≤
        (simpleClosureMagicSpineV1 ++ rest).length - 0 := by
    simp [List.length_append]
  simp only [if_pos hlen]
  have htake :
      ((simpleClosureMagicSpineV1 ++ rest).drop 0).take
          simpleClosureMagicSpineV1.length = simpleClosureMagicSpineV1 := by
    simp [List.drop_zero]
  rw [htake]
  -- length unfolds to 15; beq of equal lists is true
  simp [magicSpine_length]

theorem consumeMagic_simpleClosureSpine
    (rest : TransparentByteSpineV1) :
    consumeMagic semanticProgramMagicV1
        (start (ByteArray.mk (simpleClosureMagicSpineV1 ++ rest).toArray)) =
      .ok ((),
        ⟨ByteArray.mk (simpleClosureMagicSpineV1 ++ rest).toArray, 15, 0⟩) := by
  apply consumeMagic_eq_of_bytesV1
  change consumeMagicBytesAtV1
      (ByteArray.mk (simpleClosureMagicSpineV1 ++ rest).toArray) 0
      (ByteArray.mk simpleClosureMagicSpineV1.toArray) = .ok 15
  have href :=
    consumeMagicBytesAtV1_refinesSpine
      (simpleClosureMagicSpineV1 ++ rest) simpleClosureMagicSpineV1 0
  rw [href, consumeMagicSpine_simpleClosure]

/-! ### Finish at total length -/

theorem finish_at_spine_end (spine : TransparentByteSpineV1) (nesting : Nat) :
    finish ⟨ByteArray.mk spine.toArray, spine.length, nesting⟩ = .ok () := by
  apply finish_eq_ok_of_offset_sizeV1
  change spine.length = (ByteArray.mk spine.toArray).size
  rfl

/-! ### Wire-trace discharge interface (B-SC-DEC target shape) -/

/-- Target B-SC-DEC statement for the materialize family: transport decode of
    the name-parameterized wire bytes recovers materialize(p).

    Closed once field-level name-hole decoders are composed through
    `decodeSemanticProgramDataV1_eq_of_framing`. This module supplies the
    spine, magic, empty-table, and finish foundations; remaining field
    successes are the open residual listed in the module header. -/
def DecodeSimpleClosureGoalV1 (p : SimpleClosureParamsV1) : Prop :=
  decodeSemanticProgramDataV1 (simpleClosureWireBytesV1 p) =
    .ok (materializeSimpleClosureDataV1 p)

/-- Package a complete field-success chain into the family decode goal. -/
theorem decodeSimpleClosure_of_framing
    (p : SimpleClosureParamsV1)
    (afterMagic afterData : Cursor)
    (hsize : (simpleClosureWireBytesV1 p).size ≤ maxCanonicalProgramBytes)
    (hmagic :
      consumeMagic semanticProgramMagicV1 (start (simpleClosureWireBytesV1 p)) =
        .ok ((), afterMagic))
    (hdata :
      decodeSemanticProgramDataTaggedV1 afterMagic =
        .ok (materializeSimpleClosureDataV1 p, afterData))
    (hfinish : finish afterData = .ok ()) :
    DecodeSimpleClosureGoalV1 p := by
  unfold DecodeSimpleClosureGoalV1
  exact decodeSemanticProgramDataV1_eq_of_framing
    (simpleClosureWireBytesV1 p) afterMagic afterData
    (materializeSimpleClosureDataV1 p) hsize hmagic hdata hfinish

/-- Once the family decode goal holds and encode produces the same bytes,
    `SimpleClosureWireTraceV1` is assembled (joins B-SC-ENC + B-SC-DEC). -/
theorem simpleClosureWireTrace_of_encode_decode
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hencode :
      encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
        .ok (simpleClosureWireBytesV1 p))
    (hdecode : DecodeSimpleClosureGoalV1 p) :
    SimpleClosureWireTraceV1 p (simpleClosureWireBytesV1 p) :=
  SimpleClosureWireTraceV1.ofParts p (simpleClosureWireBytesV1 p) hwf hencode hdecode

/-- Soundness surface: wire trace from encode+decode premises yields ordinal-0
    invariant theorem (reuses SimpleClosureTrace soundness; no second model). -/
theorem invariantTheorem_of_simpleClosure_encode_decode
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hencode :
      encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
        .ok (simpleClosureWireBytesV1 p))
    (hdecode : DecodeSimpleClosureGoalV1 p) :
    InvariantTheoremV1 { canonicalBytes := simpleClosureWireBytesV1 p } 0 :=
  invariantTheoremV1_of_simpleClosureWireTrace p (simpleClosureWireBytesV1 p)
    (simpleClosureWireTrace_of_encode_decode p hwf hencode hdecode)

/-! ### Demo params (not Tests FQN — production-shaped Module.Prog) -/

def demoParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "Module"
    qnTail := #["Prog"]
    viewName := "alive"
    invName := "safe" }

theorem demoParams_qnSize : demoParamsV1.qnSize = 2 := by
  rfl

theorem demoParams_wf : SimpleClosureParamsWellFormedV1 demoParamsV1 := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · decide
  · decide
  · decide
  · decide

theorem demoParams_ascii : SimpleClosureAsciiNamesV1 demoParamsV1 := by
  refine ⟨rfl, rfl, rfl, ?_⟩
  intro s hs
  -- qnTail.toList = ["Prog"]
  simp [demoParamsV1] at hs
  subst hs
  rfl

/-- Empty constants table decodes on a pure zero-header input. -/
theorem decodeConstants_empty_demo :
    decodeArray maxTableElements decodeConstantV1
        ⟨ByteArray.mk u32leSpine0V1.toArray, 0, 1⟩ =
      .ok (#[], ⟨ByteArray.mk u32leSpine0V1.toArray, 4, 1⟩) := by
  simpa using
    (decodeEmptyArray_midV1 maxTableElements decodeConstantV1
      ([] : List UInt8) ([] : List UInt8) 1)

/-- Magic consumption on demo spine prefix (name-independent prefix of any p). -/
theorem consumeMagic_demo_prefix :
    consumeMagic semanticProgramMagicV1
        (start (ByteArray.mk (simpleClosureMagicSpineV1 ++
          simpleClosureRootHeaderSpineV1).toArray)) =
      .ok ((),
        ⟨ByteArray.mk (simpleClosureMagicSpineV1 ++
          simpleClosureRootHeaderSpineV1).toArray, 15, 0⟩) :=
  consumeMagic_simpleClosureSpine simpleClosureRootHeaderSpineV1

end ProofForgeV2.Semantic.SimpleClosureDecodeV1

/-!
  ## B-SC-DEC residual (do not forge)

  | Closed here | Residual |
  |---|---|
  | CodecRoundtrip mid-offset u8/u16/u32/array-count/option/field-count | Full inductive encode→decode for arbitrary SemanticProgramDataV1 |
  | Name-parameterized wire spine constructors (no Tests FQN) | Dynamic-offset string/QN/callable/invariant field decoders |
  | Magic consume on parametric rest suffix | expectTag root header at offset 15 for arbitrary rest |
  | Empty-array mid-offset decode | Types / callables / invariants / requirements full composition |
  | Framing interface `decodeSimpleClosure_of_framing` | Discharge of hdata for all well-formed p |
  | WireTrace + InvariantTheorem packaging | Unconditional product-positive `DecodeSimpleClosureGoalV1 p` |

  Next mechanical step: prove `expectTag "SemanticProgram.Data" 9` at offset 15
  for `magic ++ rootHeader ++ rest`, then types/empty tables via CodecRoundtrip,
  then name-hole string decode under `SimpleClosureAsciiNamesV1`.
-/
