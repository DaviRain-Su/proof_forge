import Tests.Core.Common
import Tests.Core.CommonRemaining
import Tests.Core.CommonScalars
import Tests.Core.Unicode
import Tests.Core.Semantics
import Tests.Core.DiagnosticV1
import Tests.Core.DiagnosticBundleV1
import Tests.Frontend.ProtocolV1
import Tests.Frontend.WorkerV1
import Tests.Compiler.Pipeline
import Tests.Compiler.TypedNameIndex
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
import Tests.Language.ProgramExports
import Tests.Language.ProgramExportAcceptance
import Tests.Language.ProgramExportAcceptanceEmpty
import Tests.Language.ProgramCommandAcceptance
import Tests.Language.ProgramSyntax
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
import Tests.Language.AggregateDeclarations
import Tests.Language.StateVisibility
import Tests.Language.SourceIdentity
import Tests.Language.SourceNodeAssignmentCollisionV1
import Tests.Language.SourceNodeTraversalV1
import Tests.Language.SourceProgramWireBoundaryGoldenV1
import Tests.Language.SourceProgramWireFieldCountGoldenV1
import Tests.Language.SourceProgramWireGoldenV1
import Tests.Language.SourceProgramWireMarkerGoldenV1
import Tests.Language.SourceProgramWireUnknownTagGoldenV1
import Tests.Language.SourceSpan
import Tests.Language.SourceWireAcceptance
import Tests.Language.SourceWireCodecV1
import Tests.Language.SourceWireDecodeV1
import Tests.Language.SourceNameComponentV1
import Tests.Language.SourceQualifiedNameV1
import Tests.Language.SourceAstLeafV1
import Tests.Language.SourceAstSupportV1
import Tests.Language.SourceAstPatternV1
import Tests.Language.SourceAstDeclV1
import Tests.Language.SourceAstSpineV1
import Tests.Language.SourceAstSpineCodecV1
import Tests.Language.SourceAstSpineDeclV1
import Tests.Language.SourceAstProgramItemV1
import Tests.Language.SourceAstProgramV1
import Tests.Language.SourceAstCanonicalRootV1
import Tests.Language.SourceAstProgramValidateV1
import Tests.Language.SourceAstWideEncoderV1
import Tests.Language.SourceAstScalarDecodeV1
import Tests.Language.SourceAstTypeDecodeV1
import Tests.Language.SourceAstPatternDecodeV1
import Tests.Language.SourceAstSupportDecodeV1
import Tests.Language.SourceAstDeclDecodeV1
import Tests.Language.SourceAstSpinePlaceExprDecodeV1
import Tests.Language.SourceAstSpineStmtDecodeV1
import Tests.Language.SourceAstSpineDeclDecodeV1
import Tests.Language.SourceAstProgramItemDecodeV1
import Tests.Language.SourceAstProgramDecodeV1
import Tests.Language.SourceAstCanonicalRootDecodeV1
import Tests.Language.FrontendParity
import Tests.Language.Loader
import Tests.Materialization.Targets
import Tests.Materialization.EvmSmoke
import Tests.Materialization.NearHostModel
import Tests.Materialization.NoirRelationModel
import Tests.Product.CounterV1Evm
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy
import Tests.CLI.DiagnosticsV1


unsafe def main : IO Unit := do
  Tests.Core.Common.run
  Tests.Core.CommonRemaining.run
  Tests.Core.CommonScalars.run
  Tests.Core.Unicode.run
  Tests.Core.run
  Tests.Core.DiagnosticV1.run
  Tests.Core.DiagnosticBundleV1.run
  Tests.Frontend.ProtocolV1.run
  Tests.Frontend.WorkerV1.run
  Tests.Compiler.run
  Tests.Compiler.TypedNameIndex.run
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
  Tests.Language.ProgramExports.run
  Tests.Language.ProgramExportAcceptance.run
  Tests.Language.ProgramExportAcceptanceEmpty.run
  Tests.Language.ProgramCommandAcceptance.run
  Tests.Language.ProgramSyntax.run
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
  Tests.Language.AggregateDeclarations.run
  Tests.Language.StateVisibility.run
  Tests.Language.FrontendParity.run
  Tests.Language.Loader.run
  Tests.Language.SourceWireAcceptance.run
  Tests.Language.SourceWireCodecV1.run
  Tests.Language.SourceWireDecodeV1.run
  Tests.Language.SourceNameComponentV1.run
  Tests.Language.SourceQualifiedNameV1.run
  Tests.Language.SourceAstLeafV1.run
  Tests.Language.SourceAstSupportV1.run
  Tests.Language.SourceAstPatternV1.run
  Tests.Language.SourceAstDeclV1.run
  Tests.Language.SourceAstSpineV1.run
  Tests.Language.SourceAstSpineCodecV1.run
  Tests.Language.SourceAstSpineDeclV1.run
  Tests.Language.SourceAstProgramItemV1.run
  Tests.Language.SourceAstProgramV1.run
  Tests.Language.SourceAstCanonicalRootV1.run
  Tests.Language.SourceAstProgramValidateV1.run
  Tests.Language.SourceAstWideEncoderV1.run
  Tests.Language.SourceAstScalarDecodeV1.run
  Tests.Language.SourceAstTypeDecodeV1.run
  Tests.Language.SourceAstPatternDecodeV1.run
  Tests.Language.SourceAstSupportDecodeV1.run
  Tests.Language.SourceAstDeclDecodeV1.run
  Tests.Language.SourceAstSpinePlaceExprDecodeV1.run
  Tests.Language.SourceAstSpineStmtDecodeV1.run
  Tests.Language.SourceAstSpineDeclDecodeV1.run
  Tests.Language.SourceAstProgramItemDecodeV1.run
  Tests.Language.SourceAstProgramDecodeV1.run
  Tests.Language.SourceAstCanonicalRootDecodeV1.run
  Tests.Language.SourceIdentity.run
  Tests.Language.SourceNodeAssignmentCollisionV1.run
  Tests.Language.SourceNodeTraversalV1.run
  Tests.Language.SourceProgramWireBoundaryGoldenV1.run
  Tests.Language.SourceProgramWireFieldCountGoldenV1.run
  Tests.Language.SourceProgramWireGoldenV1.run
  Tests.Language.SourceProgramWireMarkerGoldenV1.run
  Tests.Language.SourceProgramWireUnknownTagGoldenV1.run
  Tests.Language.SourceSpan.run
  Tests.Materialization.run
  Tests.Materialization.EvmSmoke.run
  Tests.Materialization.NearHostModel.run
  Tests.Materialization.NoirRelationModel.run
  Tests.Product.CounterV1Evm.run
  Tests.CLI.Emit.run
  Tests.CLI.ToolchainPolicy.run
  Tests.CLI.DiagnosticsV1.run
  IO.println "proof-forge-next-tests: ok"
