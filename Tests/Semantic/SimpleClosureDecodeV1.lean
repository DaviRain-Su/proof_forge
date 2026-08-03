/-
  Tests.Semantic.SimpleClosureDecodeV1 — focused suite for B-SC-DEC foundation.

  Covers reusable CodecRoundtrip mid-offset lemmas and SimpleClosureDecode
  name-parameterized spine / magic / empty-array / framing packaging.
  Does not claim product-positive DecodeSimpleClosureGoalV1 for all p.
-/
import ProofForgeV2.Semantic.SimpleClosureDecodeV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Unicode

namespace Tests.Semantic.SimpleClosureDecodeV1

open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureDecodeV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-- Mid-offset u32le zero read is parametric in left/right. -/
theorem roundtrip_u32_zero (left right : List UInt8) :
    readSpineU32leV1 (left ++ u32leSpine0V1 ++ right) left.length =
      .ok (0, left.length + 4) :=
  readSpineU32leV1_zero_mid left right

/-- Mid-offset u32le one read. -/
theorem roundtrip_u32_one (left right : List UInt8) :
    readSpineU32leV1 (left ++ u32leSpine1V1 ++ right) left.length =
      .ok (1, left.length + 4) :=
  readSpineU32leV1_one_mid left right

/-- Mid-offset empty array decode never invokes the element decoder. -/
theorem roundtrip_empty_array (left right : List UInt8) :
    decodeArray maxTableElements decodeConstantV1
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray, left.length, 1⟩ =
      .ok (#[],
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray,
          left.length + 4, 1⟩) :=
  decodeArray_zero_midV1 maxTableElements decodeConstantV1 left right 1

/-- Field-count 9 at mid offset (SemanticProgram.Data). -/
theorem roundtrip_field_count_nine (left right : List UInt8) :
    decodeFieldCount 9
        ⟨ByteArray.mk (left ++ u16leSpine9V1 ++ right).toArray, left.length, 1⟩ =
      .ok ((),
        ⟨ByteArray.mk (left ++ u16leSpine9V1 ++ right).toArray,
          left.length + 2, 1⟩) :=
  decodeFieldCount_nine_mid left right 1

/-- Option.none marker at mid offset. -/
theorem roundtrip_option_none (left right : List UInt8) :
    decodeOption decodeU32le
        ⟨ByteArray.mk (left ++ (0 : UInt8) :: right).toArray, left.length, 1⟩ =
      .ok (none,
        ⟨ByteArray.mk (left ++ (0 : UInt8) :: right).toArray,
          left.length + 1, 1⟩) :=
  decodeOption_none_midV1 decodeU32le left right 1

/-- Magic consume on parametric rest (name-independent). -/
theorem magic_on_rest (rest : TransparentByteSpineV1) :
    consumeMagic semanticProgramMagicV1
        (start (ByteArray.mk (simpleClosureMagicSpineV1 ++ rest).toArray)) =
      .ok ((),
        ⟨ByteArray.mk (simpleClosureMagicSpineV1 ++ rest).toArray, 15, 0⟩) :=
  consumeMagic_simpleClosureSpine rest

/-- Demo params are certificate-well-formed and ASCII. -/
theorem demo_wf : SimpleClosureParamsWellFormedV1 demoParamsV1 :=
  demoParams_wf

theorem demo_ascii : SimpleClosureAsciiNamesV1 demoParamsV1 :=
  demoParams_ascii

/-- Materialize of demo has the fixed micro-shape (2 types, 2 callables, 1 inv). -/
theorem demo_materialize_shape :
    (materializeSimpleClosureDataV1 demoParamsV1).types.size = 2 ∧
    (materializeSimpleClosureDataV1 demoParamsV1).callables.size = 2 ∧
    (materializeSimpleClosureDataV1 demoParamsV1).invariants.size = 1 := by
  refine ⟨?_, ?_, ?_⟩
  · rfl
  · rfl
  · rfl

/-- Wire spine is name-parameterized at the definition level (view name hole). -/
theorem viewCallableSpine_mentions_name (name : String) :
    (stringSpineV1 name).length ≤ (viewCallableSpineV1 name).length := by
  simp [viewCallableSpineV1, stringSpineV1, someStringSpineV1, List.length_append]
  omega

/-- Finish at exact spine end. -/
theorem finish_demo_magic :
    finish ⟨ByteArray.mk simpleClosureMagicSpineV1.toArray, 15, 0⟩ = .ok () :=
  finish_at_spine_end simpleClosureMagicSpineV1 0

/-- Empty constants table on pure zero header. -/
theorem empty_constants :
    decodeArray maxTableElements decodeConstantV1
        ⟨ByteArray.mk u32leSpine0V1.toArray, 0, 1⟩ =
      .ok (#[], ⟨ByteArray.mk u32leSpine0V1.toArray, 4, 1⟩) :=
  decodeConstants_empty_demo

/-- Framing packager typechecks: DecodeSimpleClosureGoalV1 is the named goal. -/
theorem framing_interface_type
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
    DecodeSimpleClosureGoalV1 p :=
  decodeSimpleClosure_of_framing p afterMagic afterData hsize hmagic hdata hfinish

def run : IO Unit := do
  -- Kernel theorems above are the suite; IO only acknowledges the foundation.
  IO.println "Tests.Semantic.SimpleClosureDecodeV1: ok"
  IO.println "  CodecRoundtrip mid-offset u32/u16/array/option/field-count closed"
  IO.println "  SimpleClosure magic/empty-array/framing packaging closed"
  IO.println "  DecodeSimpleClosureGoalV1 residual: name-hole field composition"

end Tests.Semantic.SimpleClosureDecodeV1
