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
import Tests.Language.ProgramV1Declarations
import Tests.Language.ProgramV1DeclarationNegatives
import Tests.Language.ProgramV1ExternalStatements
import Tests.Language.ProgramV1ControlFlow
import Tests.Language.ProgramV1ExpressionForms
import Tests.Language.ProgramV1UnaryExpressions
import Tests.Language.ProgramV1ArithmeticExpressions
import Tests.Language.ProgramV1ShiftExpressions
import Tests.Language.ProgramV1EqualityExpressions
import Tests.Language.ProgramV1OrderingComparisons
import Tests.Language.ProgramV1BitwiseExpressions
import Tests.Language.ProgramV1LogicalExpressions
import Tests.Language.ProgramV1CoreStatements
import Tests.Language.ProgramV1MatchStatements
import Tests.Language.ProgramV1MatchExpressions
import Tests.Language.ProgramV1ConstructorPatterns
import Tests.Language.ProgramV1FieldPlaces
import Tests.Language.ProgramV1IndexedPlaces
import Tests.Language.ProgramV1PlaceSuffixes
import Tests.Language.ProgramV1RevertEmitStatements
import Tests.Language.ProgramV1StringLiterals
import Tests.Language.ProgramV1TypeSurface
import Tests.Language.ProgramV1SpanJoin
import Tests.Language.ProgramV1OriginJoin
import Tests.Language.ProgramV1DiagnosticLocate
import Tests.Language.ProgramV1Diagnostics
import Tests.Language.ProgramV1Bounds
import Tests.Language.ProgramV1SourceFullTagGolden
import Tests.Core.DiagnosticV1
import Tests.Core.DiagnosticBundleV1
import Tests.Frontend.ProtocolV1
import Tests.Frontend.WorkerV1
import Tests.Product.CounterV1Evm
import Tests.Materialization.EvmSmoke
import Tests.Materialization.EvmSolcAcceptance
import Tests.Materialization.SolanaPlanV1

import Tests.Materialization.Targets
import Tests.Materialization.NearHostModel
import Tests.Materialization.NoirRelationModel
import Tests.Materialization.TargetRegistryV1
import Tests.Materialization.RequirementResolverV1
import Tests.Materialization.IdentityChainV1
import Tests.Materialization.EvmPlanSchemaV1
import Tests.Materialization.OutputSetV1
import Tests.Materialization.OutputEnvelopeV1
import Tests.Materialization.EngineeringFinalizationV1
import Tests.Materialization.EngineeringDiskClosureV1
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy
import Tests.CLI.DiagnosticsV1
-- S1 NormalizeV1 suite is defined in Tests/Typed/CheckV1.lean under namespace
-- Tests.Semantic.NormalizeV1 and invoked from Tests.Typed.CheckV1.run (ordinary
-- CI + fast path both hit that root).

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
  Tests.Language.ProgramV1Declarations.run
  Tests.Language.ProgramV1DeclarationNegatives.run
  Tests.Language.ProgramV1ExternalStatements.run
  Tests.Language.ProgramV1ControlFlow.run
  Tests.Language.ProgramV1ExpressionForms.run
  Tests.Language.ProgramV1UnaryExpressions.run
  Tests.Language.ProgramV1ArithmeticExpressions.run
  Tests.Language.ProgramV1ShiftExpressions.run
  Tests.Language.ProgramV1EqualityExpressions.run
  Tests.Language.ProgramV1OrderingComparisons.run
  Tests.Language.ProgramV1BitwiseExpressions.run
  Tests.Language.ProgramV1LogicalExpressions.run
  Tests.Language.ProgramV1CoreStatements.run
  Tests.Language.ProgramV1MatchStatements.run
  Tests.Language.ProgramV1MatchExpressions.run
  Tests.Language.ProgramV1ConstructorPatterns.run
  Tests.Language.ProgramV1FieldPlaces.run
  Tests.Language.ProgramV1IndexedPlaces.run
  Tests.Language.ProgramV1PlaceSuffixes.run
  Tests.Language.ProgramV1RevertEmitStatements.run
  Tests.Language.ProgramV1StringLiterals.run
  Tests.Language.ProgramV1TypeSurface.run
  Tests.Language.ProgramV1SpanJoin.run
  Tests.Language.ProgramV1OriginJoin.run
  Tests.Language.ProgramV1DiagnosticLocate.run
  Tests.Language.ProgramV1Diagnostics.run
  Tests.Language.ProgramV1Bounds.run
  Tests.Language.ProgramV1SourceFullTagGolden.run
  Tests.Core.DiagnosticV1.run
  Tests.Core.DiagnosticBundleV1.run
  Tests.Frontend.ProtocolV1.run
  Tests.Frontend.WorkerV1.run
  Tests.Product.CounterV1Evm.run
  Tests.Materialization.EvmSmoke.run
  Tests.Materialization.EvmSolcAcceptance.run
  Tests.Materialization.SolanaPlanV1.run

  Tests.Materialization.TargetRegistryV1.run
  Tests.Materialization.RequirementResolverV1.run
  Tests.Materialization.IdentityChainV1.run
  Tests.Materialization.EvmPlanSchemaV1.run
  Tests.Materialization.OutputSetV1.run
  Tests.Materialization.OutputEnvelopeV1.run
  Tests.Materialization.EngineeringFinalizationV1.run
  Tests.Materialization.EngineeringDiskClosureV1.run
  Tests.CLI.Emit.run
  Tests.CLI.ToolchainPolicy.run
  Tests.CLI.DiagnosticsV1.run
  -- Keep target-leaf regressions after child-process wall-budget suites so
  -- their retained Plan fixtures cannot perturb host scheduling. The two
  -- lightweight model entries prove checked-sub success/underflow execution;
  -- full lifecycle models remain in the ordinary aggregate.
  Tests.Materialization.runSemanticPlanLeafFast
  Tests.Materialization.NearHostModel.runCheckedSubFast
  Tests.Materialization.NoirRelationModel.runCheckedSubFast
  IO.println "proof-forge-next-fast-tests: ok"
