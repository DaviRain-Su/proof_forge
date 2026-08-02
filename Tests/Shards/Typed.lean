import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Compiler.CheckV1ProductGate
import Tests.Compiler.DiagnosticPipelineV1
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
import Tests.Typed.RequirementsInferV1
import Tests.Typed.CheckV1
import Tests.Semantic.WireV1
import Tests.Semantic.InvariantABI
import Tests.Semantic.ReferenceV1
import Tests.Semantic.NormalizeConst
import Tests.Semantic.ProofBundleV1
import Tests.Semantic.ProofReferenceJoinV1
unsafe def main : IO Unit := do
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Compiler.CheckV1ProductGate.run
  Tests.Compiler.DiagnosticPipelineV1.run
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
  Tests.Typed.RequirementsInferV1.run
  Tests.Typed.CheckV1.run
  Tests.Semantic.WireV1.run
  Tests.Semantic.InvariantABI.run
  Tests.Semantic.ReferenceV1.run
  Tests.Semantic.NormalizeConst.run
  Tests.Semantic.ProofBundleV1.run
  Tests.Semantic.ProofReferenceJoinV1.run
  IO.println "shard-typed: ok"
