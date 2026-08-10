/-
  Tests.Semantic.SubjectDataBridgeV1 — mig-a3-elab generic subject-data bridge.

  Runtime packaging only: encodeSubjectBytesV1 equals production encode and
  programOfEncode packaging theorems typecheck by mention. No pin table growth.
-/
import ProofForgeV2.Semantic.SubjectDataBridgeV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.SubjectDataBridgeV1

open ProofForgeV2.Semantic.SubjectDataBridgeV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

/-- Minimal legal simple-closure params (ASCII components). -/
private def params : SimpleClosureParamsV1 := {
  qnHead := "Root"
  qnTail := #["BridgeProbe"]
  viewName := "alive"
  invName := "safe"
}

private def data : SemanticProgramDataV1 :=
  materializeSimpleClosureDataV1 params

/-- The production body codec accepts this transport shape, but the sole root
    encoder must reject its one-component program identity. -/
private def invalidRootData : SemanticProgramDataV1 :=
  { data with qualifiedName := { components := ⟨"Root", #[]⟩ } }

/-- Closed encode of the probe data (runtime-checked below). -/
private def probeBytes? : Option ByteArray :=
  match encodeSemanticProgramDataV1 data with
  | .ok b => some b
  | .error _ => none

/-- Definitional packaging under the production encode equality for this probe. -/
private theorem probe_encode_ok
    (bytes : ByteArray)
    (h : encodeSemanticProgramDataV1 data = .ok bytes) :
    (programOfEncodeV1 data bytes h).canonicalBytes = bytes :=
  programOfEncodeV1_canonicalBytes data bytes h

private theorem probe_witness_data
    (bytes : ByteArray)
    (h : encodeSemanticProgramDataV1 data = .ok bytes) :
    (toEncodeWitnessV1 data bytes h).data = data :=
  toEncodeWitnessV1_data data bytes h

def run : IO Unit := do
  match encodeSubjectBytesV1 data, encodeSemanticProgramDataV1 data with
  | .ok bytes, .ok expected =>
      expect (bytes == expected)
        "encodeSubjectBytesV1 must equal production encode"
      expect (bytes.size > 0) "probe encode non-empty"
      -- Force packaging theorem types into the elaborator (no step execution).
      let _ := @programOfEncodeV1_canonicalBytes
      let _ := @toEncodeWitnessV1_data
      let _ := @encode_of_subjectData_body_gates
      let _ := @validate_of_subjectData_body_gates_invert
      let _ := @validate_of_subjectData_decode
      let _ := @structure_of_subjectData_encode
      let _ := @probe_encode_ok
      let _ := @probe_witness_data
      let _ := probeBytes?
      expect true "SubjectDataBridgeV1 packaging theorems elaborate"
  | .error e, _ =>
      throw <| IO.userError s!"encodeSubjectBytesV1 failed: {repr e}"
  | _, .error e =>
      throw <| IO.userError s!"production encode failed: {repr e}"
  match encodeSemanticProgramDataBodyV1 invalidRootData with
  | .error error =>
      throw <| IO.userError
        s!"invalid-root body encode unexpectedly failed: {repr error}"
  | .ok bytes =>
      match encodeSemanticProgramDataV1 invalidRootData with
      | .error .badScalar => pure ()
      | .error error =>
          throw <| IO.userError
            s!"invalid-root encoder returned wrong error: {repr error}"
      | .ok _ =>
          throw <| IO.userError
            "body equality must not bypass the production root-name gate"
      match validateSemanticProgramV1 ⟨bytes⟩ with
      | .error .badScalar => pure ()
      | .error error =>
          throw <| IO.userError
            s!"invalid-root validator returned wrong error: {repr error}"
      | .ok _ =>
          throw <| IO.userError
            "body-only carrier must not validate without production root gates"
  IO.println "Tests.Semantic.SubjectDataBridgeV1: ok"

end Tests.Semantic.SubjectDataBridgeV1
