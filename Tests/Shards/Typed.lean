import Tests.Shards.Runner
import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Compiler.CheckV1ProductGate
import Tests.Compiler.DiagnosticPipelineV1
import Tests.Compiler.ProofBundleFilesV1
import Tests.Compiler.InlineProofAuditV1
import Tests.Compiler.InlineProofProtocolV1
import Tests.Compiler.InlineProofElaborationV1
import Tests.Compiler.InlineProofCertifierV1
import Tests.Language.InlineProofAuthoringV1
import Tests.Language.TheoremInventoryV1
import Tests.Typed.NameResolutionV1
import Tests.Typed.DiagnosticLocationsV1
import Tests.Typed.TypeCheckExpressionsV1
import Tests.Typed.TypeCheckCallsV1
import Tests.Typed.TypeCheckStatementsV1
import Tests.Typed.TypeCheckMatchV1
import Tests.Typed.CallGraphV1
import Tests.Typed.EffectCheckV1
import Tests.Typed.BoundCheckV1
import Tests.Typed.DisclosureCheckV1
import Tests.Typed.AuthorityCustodyCheckV1
import Tests.Typed.ContextExtensionCheckV1
import Tests.Typed.RequirementsInferV1
import Tests.Typed.CheckV1
import Tests.Semantic.WireV1
import Tests.Semantic.InvariantABI
import Tests.Semantic.PreservationABI
import Tests.Semantic.UInt64ParitySubjectV1
import Tests.Semantic.InvariantTheoremV1
import Tests.Semantic.ProofBridgeV1
import Tests.Semantic.CodecInvertV1
import Tests.Semantic.ProofedCertV1
import Tests.Semantic.SimpleClosureCertV1
import Tests.Semantic.AuthorWireCertV1
import Tests.Semantic.SimpleClosureTraceV1
import Tests.Semantic.SimpleClosureStructureCertV1
import Tests.Semantic.SimpleClosureEncodeV1
import Tests.Semantic.SimpleClosureDecodeV1
import Tests.Semantic.SimpleClosureDecodeRootQnV1
import Tests.Semantic.SimpleClosureDecodeFixedFieldsV1
import Tests.Semantic.SimpleClosureDecodeCallableV1
import Tests.Semantic.SimpleClosureDecodeComposeV1
import Tests.Semantic.ProofedEncodeCertV1
import Tests.Semantic.ProofedDecodeCertV1
import Tests.Semantic.ProofedClosedCertV1
import Tests.Semantic.ReferenceV1
import Tests.Semantic.OutcomeWireV1
import Tests.Semantic.StepFacadeV1
import Tests.Semantic.Sem001ShapeV1
import Tests.Semantic.Sem002ShapeV1
import Tests.Semantic.Sem003ShapeV1
import Tests.Semantic.AttachedValueContextV1
import Tests.Semantic.MiniAmmVectorsV1
import Tests.Semantic.NormalizeConst
import Tests.Semantic.NormalizeSha256BytesV1
import Tests.Semantic.NormalizeMerkleVerifyV1
import Tests.Semantic.ProofBundleV1
import Tests.Semantic.ProofSubjectV1
import Tests.Semantic.ProofReferenceJoinV1

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Compiler.ValidatedSourceV1Pipeline"
    Tests.Compiler.ValidatedSourceV1Pipeline.run
  runSuite "Tests.Compiler.CheckV1ProductGate" Tests.Compiler.CheckV1ProductGate.run
  runSuite "Tests.Compiler.DiagnosticPipelineV1" Tests.Compiler.DiagnosticPipelineV1.run
  runSuite "Tests.Compiler.ProofBundleFilesV1" Tests.Compiler.ProofBundleFilesV1.run
  runSuite "Tests.Compiler.InlineProofAuditV1" Tests.Compiler.InlineProofAuditV1.run
  runSuite "Tests.Compiler.InlineProofProtocolV1" Tests.Compiler.InlineProofProtocolV1.run
  runSuite "Tests.Compiler.InlineProofElaborationV1"
    Tests.Compiler.InlineProofElaborationV1.run
  runSuite "Tests.Compiler.InlineProofCertifierV1"
    Tests.Compiler.InlineProofCertifierV1.run
  runSuite "Tests.Language.InlineProofAuthoringV1" Tests.Language.InlineProofAuthoringV1.run
  runSuite "Tests.Language.TheoremInventoryV1" Tests.Language.TheoremInventoryV1.run
  runSuite "Tests.Typed.NameResolutionV1" Tests.Typed.NameResolutionV1.run
  runSuite "Tests.Typed.DiagnosticLocationsV1" Tests.Typed.DiagnosticLocationsV1.run
  runSuite "Tests.Typed.TypeCheckExpressionsV1" Tests.Typed.TypeCheckExpressionsV1.run
  runSuite "Tests.Typed.TypeCheckCallsV1" Tests.Typed.TypeCheckCallsV1.run
  runSuite "Tests.Typed.TypeCheckStatementsV1" Tests.Typed.TypeCheckStatementsV1.run
  runSuite "Tests.Typed.TypeCheckMatchV1" Tests.Typed.TypeCheckMatchV1.run
  runSuite "Tests.Typed.CallGraphV1" Tests.Typed.CallGraphV1.run
  runSuite "Tests.Typed.EffectCheckV1" Tests.Typed.EffectCheckV1.run
  runSuite "Tests.Typed.BoundCheckV1" Tests.Typed.BoundCheckV1.run
  runSuite "Tests.Typed.DisclosureCheckV1" Tests.Typed.DisclosureCheckV1.run
  runSuite "Tests.Typed.AuthorityCustodyCheckV1" Tests.Typed.AuthorityCustodyCheckV1.run
  runSuite "Tests.Typed.ContextExtensionCheckV1" Tests.Typed.ContextExtensionCheckV1.run
  runSuite "Tests.Typed.RequirementsInferV1" Tests.Typed.RequirementsInferV1.run
  runSuite "Tests.Typed.CheckV1" Tests.Typed.CheckV1.run
  runSuite "Tests.Semantic.WireV1" Tests.Semantic.WireV1.run
  runSuite "Tests.Semantic.InvariantABI" Tests.Semantic.InvariantABI.run
  runSuite "Tests.Semantic.PreservationABI" Tests.Semantic.PreservationABI.run
  runSuite "Tests.Semantic.UInt64ParitySubjectV1"
    Tests.Semantic.UInt64ParitySubjectV1.run
  runSuite "Tests.Semantic.ProofBridgeV1" Tests.Semantic.ProofBridgeV1.run
  runSuite "Tests.Semantic.CodecInvertV1" Tests.Semantic.CodecInvertV1.run
  runSuite "Tests.Semantic.SimpleClosureTraceV1" Tests.Semantic.SimpleClosureTraceV1.run
  runSuite "Tests.Semantic.SimpleClosureStructureCertV1"
    Tests.Semantic.SimpleClosureStructureCertV1.run
  runSuite "Tests.Semantic.SimpleClosureEncodeV1" Tests.Semantic.SimpleClosureEncodeV1.run
  runSuite "Tests.Semantic.SimpleClosureDecodeV1" Tests.Semantic.SimpleClosureDecodeV1.run
  runSuite "Tests.Semantic.SimpleClosureDecodeRootQnV1"
    Tests.Semantic.SimpleClosureDecodeRootQnV1.run
  runSuite "Tests.Semantic.SimpleClosureDecodeFixedFieldsV1"
    Tests.Semantic.SimpleClosureDecodeFixedFieldsV1.run
  runSuite "Tests.Semantic.SimpleClosureDecodeCallableV1"
    Tests.Semantic.SimpleClosureDecodeCallableV1.run
  runSuite "Tests.Semantic.SimpleClosureDecodeComposeV1"
    Tests.Semantic.SimpleClosureDecodeComposeV1.run
  runSuite "Tests.Semantic.ReferenceV1" Tests.Semantic.ReferenceV1.run
  runSuite "Tests.Semantic.OutcomeWireV1" Tests.Semantic.OutcomeWireV1.run
  runSuite "Tests.Semantic.StepFacadeV1" Tests.Semantic.StepFacadeV1.run
  runSuite "Tests.Semantic.Sem001ShapeV1" Tests.Semantic.Sem001ShapeV1.run
  runSuite "Tests.Semantic.Sem002ShapeV1" Tests.Semantic.Sem002ShapeV1.run
  runSuite "Tests.Semantic.Sem003ShapeV1" Tests.Semantic.Sem003ShapeV1.run
  runSuite "Tests.Semantic.AttachedValueContextV1"
    Tests.Semantic.AttachedValueContextV1.run
  runSuite "Tests.Semantic.MiniAmmVectorsV1" Tests.Semantic.MiniAmmVectorsV1.run
  runSuite "Tests.Semantic.NormalizeConst" Tests.Semantic.NormalizeConst.run
  runSuite "Tests.Semantic.NormalizeSha256BytesV1" Tests.Semantic.NormalizeSha256BytesV1.run
  runSuite "Tests.Semantic.NormalizeMerkleVerifyV1"
    Tests.Semantic.NormalizeMerkleVerifyV1.run
  runSuite "Tests.Semantic.ProofBundleV1" Tests.Semantic.ProofBundleV1.run
  runSuite "Tests.Semantic.ProofSubjectV1" Tests.Semantic.ProofSubjectV1.run
  runSuite "Tests.Semantic.ProofReferenceJoinV1" Tests.Semantic.ProofReferenceJoinV1.run
  IO.println "shard-typed: ok"
