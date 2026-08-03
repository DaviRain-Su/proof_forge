/-
  Tests.Semantic.SimpleClosureEncodeV1 — B-SC-ENC focused suite.

  Covers:
    * name-parameterized field-path builder (no root encode wrapper)
    * runtime equality: encode(materialize p) = ok (simpleClosureWireBytesV1 p)
      for arbitrary Demo / alt-name params and elaborator Proofed params
    * wire bytes match elaborator subjectBytesV1
    * light kernel lemmas (wf / empty tables / string ASCII encode)

  Does **not** re-prove full Proofed structure/encode certificates.
  No axiom / sorry / native_decide / ofReduceBool.
-/
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1
import Tests.Language.InlineProofAuthoringV1

namespace Tests.Semantic.SimpleClosureEncodeV1

open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open Tests.Language.InlineProofAuthoringV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Parametric demo params (no Tests FQN hardcoding in production path) -/

def demoParams : SimpleClosureParamsV1 :=
  {
    qnHead := "Demo"
    qnTail := #["Module", "Prog"]
    viewName := "alive"
    invName := "safe"
  }

theorem demo_wellFormed : SimpleClosureParamsWellFormedV1 demoParams :=
  ⟨by decide, by decide, by decide, by decide⟩

theorem demo_qnShape :
    validateProgramQualifiedNameShapeV1
      (materializeSimpleClosureDataV1 demoParams).qualifiedName = .ok () :=
  validateProgramQualifiedNameShape_materialize_of_wf demoParams demo_wellFormed

theorem demo_table_sizes_ok :
    checkTableSize (materializeSimpleClosureDataV1 demoParams).types.size = .ok () ∧
    checkTableSize (materializeSimpleClosureDataV1 demoParams).callables.size = .ok () ∧
    checkTableSize (materializeSimpleClosureDataV1 demoParams).invariants.size = .ok () :=
  ⟨checkTableSize_materialize_types demoParams,
    checkTableSize_materialize_callables demoParams,
    checkTableSize_materialize_invariants demoParams⟩

theorem demo_empty_tables :
    encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 demoParams).constants =
      .ok simpleClosureEmptyTableBytesV1 :=
  encodeEmptyConstants_materialize demoParams

/-- ASCII string spine lemma for the demo view name (production encodeString). -/
theorem encodeString_alive :
    encodeString "alive" =
      .ok ((encodeU32le (UInt32.ofNat "alive".toUTF8.size)).append "alive".toUTF8) :=
  encodeString_eq_ok_of_ascii "alive" (by decide) (by decide)

theorem encodeString_safe :
    encodeString "safe" =
      .ok ((encodeU32le (UInt32.ofNat "safe".toUTF8.size)).append "safe".toUTF8) :=
  encodeString_eq_ok_of_ascii "safe" (by decide) (by decide)

theorem proofed_params_wellFormed :
    SimpleClosureParamsWellFormedV1 Proofed.Proof.simpleClosureParamsV1 :=
  ⟨by decide, by decide, by decide, by decide⟩

/-- Kernel packaging of B-SC-ENC under free structure + free field-ok hyps
    (discharged at runtime for concrete params; structure is B-SC-STRUCT). -/
theorem encode_eq_wireBytes_of_structure_and_fields
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hstructure :
      validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ())
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok (simpleClosureWireBytesV1 p)) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) :=
  encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1
    p hwf hstructure hfields

/-! ### Runtime checks (parametric + elaborator) -/

private def testEncodeEqualsWireBytes (p : SimpleClosureParamsV1) (label : String) :
    IO Unit := do
  let data := materializeSimpleClosureDataV1 p
  match encodeSemanticProgramDataV1 data with
  | .error e =>
      throw <| IO.userError s!"{label}: encode failed: {repr e}"
  | .ok bytes =>
      match encodeSimpleClosureDataFieldsV1 p with
      | .error e =>
          throw <| IO.userError s!"{label}: field path failed: {repr e}"
      | .ok fieldBytes =>
          expect (bytes == fieldBytes)
            s!"{label}: root encode == field path"
          expect (bytes == simpleClosureWireBytesV1 p)
            s!"{label}: root encode == simpleClosureWireBytesV1"
          expect (simpleClosureWireBytesV1? p == some bytes)
            s!"{label}: wireBytes? == some root bytes"

private def testDemoAndProofed : IO Unit := do
  testEncodeEqualsWireBytes demoParams "demo"
  -- Distinct module path + names still parameterize the spine (no fixture lock-in).
  let alt : SimpleClosureParamsV1 :=
    {
      qnHead := "Acme"
      qnTail := #["Ledger", "Safe"]
      viewName := "okView"
      invName := "okInv"
    }
  testEncodeEqualsWireBytes alt "alt-names"
  -- Elaborator Proofed params.
  testEncodeEqualsWireBytes Proofed.Proof.simpleClosureParamsV1 "proofed"
  match encodeSemanticProgramDataV1
      (materializeSimpleClosureDataV1 Proofed.Proof.simpleClosureParamsV1) with
  | .error e => throw <| IO.userError s!"proofed encode: {repr e}"
  | .ok bytes =>
      expect (bytes == Proofed.Proof.subjectBytesV1)
        "proofed wire bytes == elaborator subjectBytesV1"
      expect (simpleClosureWireBytesV1 Proofed.Proof.simpleClosureParamsV1 ==
          Proofed.Proof.subjectBytesV1)
        "builder == subjectBytesV1"
  -- Field-path success rewrites wireBytes definitionally for packaging.
  match encodeSimpleClosureDataFieldsV1 Proofed.Proof.simpleClosureParamsV1 with
  | .error e => throw <| IO.userError s!"proofed fields: {repr e}"
  | .ok b =>
      expect (simpleClosureWireBytesV1 Proofed.Proof.simpleClosureParamsV1 == b)
        "wireBytes == fields ok payload"

def run : IO Unit := do
  testDemoAndProofed
  IO.println "Tests.Semantic.SimpleClosureEncodeV1: ok"

end Tests.Semantic.SimpleClosureEncodeV1
