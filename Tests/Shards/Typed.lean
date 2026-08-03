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
import Tests.Semantic.InvariantTheoremV1
import Tests.Semantic.ProofBridgeV1
import Tests.Semantic.ProofedCertV1
import Tests.Semantic.SimpleClosureCertV1
import Tests.Semantic.AuthorWireCertV1
import Tests.Semantic.ProofedEncodeCertV1
import Tests.Semantic.ProofedDecodeCertV1
import Tests.Semantic.ProofedClosedCertV1
import Tests.Semantic.ReferenceV1
import Tests.Semantic.NormalizeConst
import Tests.Semantic.ProofBundleV1
import Tests.Semantic.ProofSubjectV1
import Tests.Semantic.ProofReferenceJoinV1
unsafe def main : IO Unit := do
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Compiler.CheckV1ProductGate.run
  Tests.Compiler.DiagnosticPipelineV1.run
  Tests.Compiler.ProofBundleFilesV1.run
  Tests.Compiler.InlineProofAuditV1.run
  Tests.Compiler.InlineProofProtocolV1.run
  Tests.Compiler.InlineProofElaborationV1.run
  Tests.Compiler.InlineProofCertifierV1.run
  Tests.Language.InlineProofAuthoringV1.run
  Tests.Language.TheoremInventoryV1.run
  Tests.Typed.NameResolutionV1.run
  Tests.Typed.DiagnosticLocationsV1.run
  Tests.Typed.TypeCheckExpressionsV1.run
  Tests.Typed.TypeCheckCallsV1.run
  Tests.Typed.TypeCheckStatementsV1.run
  Tests.Typed.TypeCheckMatchV1.run
  Tests.Typed.CallGraphV1.run
  Tests.Typed.EffectCheckV1.run
  Tests.Typed.BoundCheckV1.run
  Tests.Typed.DisclosureCheckV1.run
  Tests.Typed.AuthorityCustodyCheckV1.run
  Tests.Typed.ContextExtensionCheckV1.run
  Tests.Typed.RequirementsInferV1.run
  Tests.Typed.CheckV1.run
  Tests.Semantic.WireV1.run
  Tests.Semantic.InvariantABI.run
  Tests.Semantic.ProofBridgeV1.run
  Tests.Semantic.ReferenceV1.run
  Tests.Semantic.NormalizeConst.run
  Tests.Semantic.ProofBundleV1.run
  Tests.Semantic.ProofSubjectV1.run
  Tests.Semantic.ProofReferenceJoinV1.run
  IO.println "shard-typed: ok"
