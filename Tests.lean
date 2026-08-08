import Tests.Core.Common
import Tests.Core.CommonRemaining
import Tests.Core.CommonScalars
import Tests.Core.Unicode
import Tests.Core.DiagnosticV1
import Tests.Core.DiagnosticBundleV1
import Tests.Frontend.ProtocolV1
import Tests.Frontend.WorkerV1
import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Compiler.CheckV1ProductGate
import Tests.Compiler.DiagnosticPipelineV1
import Tests.Compiler.ProofSubjectFilesV1
import Tests.Compiler.InlineProofAuditV1
import Tests.Compiler.ProofWorkerV1
import Tests.Compiler.ProofWorkerSupervisorV1
import Tests.Compiler.InlineProofProtocolV1
import Tests.Compiler.InlineProofElaborationV1
import Tests.Compiler.InlineProofCertifierV1
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
import Tests.Semantic.ClosedSubjectPinV1
import Tests.Semantic.InvariantTheoremV1
import Tests.Semantic.ProofBridgeV1
import Tests.Semantic.ProofedCertV1
import Tests.Semantic.ProofedEncodeCertV1
import Tests.Semantic.ProofedDecodeCertV1
import Tests.Semantic.SimpleClosureCertV1
import Tests.Semantic.AuthorWireCertV1
import Tests.Semantic.ProofedClosedCertV1
import Tests.Semantic.ReferenceV1
import Tests.Semantic.MiniAmmVectorsV1
import Tests.Semantic.ProofBundleV1
import Tests.Semantic.ProofSubjectV1
import Tests.Semantic.ProofReferenceJoinV1
import Tests.Language.ProgramExports
import Tests.Language.ProgramExportAcceptance
import Tests.Language.ProgramExportAcceptanceEmpty
import Tests.Language.ProgramCommandAcceptance
import Tests.Language.InlineProofAuthoringV1
import Tests.Language.TheoremInventoryV1
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
import Tests.Materialization.BuildSelectionV1
import Tests.Materialization.TargetRegistryV1
import Tests.Materialization.RequirementResolverV1
import Tests.Materialization.IdentityChainV1
import Tests.Materialization.EvmPlanSchemaV1
import Tests.Materialization.AleoPlanSchemaV1
import Tests.Materialization.OutputSetV1
import Tests.Materialization.OutputEnvelopeV1
import Tests.Materialization.TargetIrFixtures
import Tests.Materialization.Targets
import Tests.Materialization.Aleo
import Tests.Materialization.AleoAcceptance
import Tests.Materialization.AleoCompiledFinalizationV1
import Tests.Materialization.QuintSourceV1
import Tests.Materialization.QuintAcceptance
import Tests.Materialization.EvmSmoke
import Tests.Materialization.EvmSolcAcceptance
import Tests.Materialization.NearWasmAcceptance
import Tests.Materialization.NearHostModel

import Tests.Materialization.NoirRelationModel
import Tests.Materialization.SolanaPlanV1
import Tests.Materialization.SolanaCpiPlanV1
import Tests.Materialization.SolanaCpiDeriveV1
import Tests.Materialization.SolanaCpiPreflightV1
import Tests.Materialization.SolanaCpiUnsignedV1
import Tests.Materialization.SolanaCpiPdaV1
import Tests.Materialization.SolanaCpiSystemV1
import Tests.Materialization.SolanaCpiTokenV1
import Tests.Materialization.SolanaCpiAtaV1
import Tests.Materialization.SolanaCpiEscrowV1
import Tests.Materialization.SolanaCpiPfAssetsV1
import Tests.Materialization.SolanaCpiActivationV1
import Tests.Materialization.SolanaProductSynthesizeV1
import Tests.Targets.SolanaAsmV1
import Tests.Targets.SolanaAcc1LayoutV1
import Tests.Targets.SolanaProductFrameV1
import Tests.Targets.SolanaProductCpiRecipesV1
import Tests.Targets.SolanaElfV1
import Tests.Targets.EvmCancunV1
import Tests.Materialization.EvmCorpusBlockedV1
import Tests.Product.CounterV1Evm
import Tests.Product.PrivateSum4PrivacyV1
import Tests.Product.PerfCheckHarnessV1
import Tests.Product.TokenV1
import Tests.Product.TipJarQuintV1
import Tests.Product.TipJarEvmV1
import Tests.Materialization.EvmPfAssetsV1
import Tests.Product.TokenJarEvmV1
import Tests.Product.TipJarSolanaV1
import Tests.Product.TokenJarSolanaV1
import Tests.Product.MiniAmmSolanaV1
import Tests.Product.BodyCpiMapTipSolanaV1
import Tests.Product.BodyCpiSysPaySolanaV1
import Tests.Product.BodyCpiTokenPaySolanaV1
import Tests.Product.MiniAmmAssetsSolanaV1
import Tests.Product.MiniAmmAssetsEvmV1
import Tests.Product.MiniAmmProofSurfaceV1
import Tests.Product.TipJarNearV1
import Tests.Materialization.NearPfAssetsV1
import Tests.Product.TipJarCosmWasmV1
import Tests.Materialization.CosmWasmPfAssetsV1
import Tests.Materialization.PsyPfAssetsV1
import Tests.Materialization.AleoPfAssetsV1
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy
import Tests.Materialization.EngineeringFinalizationV1
import Tests.Materialization.EngineeringDiskClosureV1
import Tests.CLI.DiagnosticsV1
import Tests.CLI.ResourceFlagsV1
import Tests.CLI.InlineProofProductV1

private unsafe def runSemanticTests : IO Unit := do
  Tests.Semantic.WireV1.run
  Tests.Semantic.InvariantABI.run
  Tests.Semantic.PreservationABI.run
  Tests.Semantic.ClosedSubjectPinV1.run
  Tests.Semantic.ProofBridgeV1.run
  Tests.Semantic.ReferenceV1.run
  Tests.Semantic.MiniAmmVectorsV1.run
  Tests.Semantic.ProofBundleV1.run
  Tests.Semantic.ProofSubjectV1.run
  Tests.Semantic.ProofReferenceJoinV1.run

private unsafe def runMaterializationAndProductTests : IO Unit := do
  Tests.Materialization.BuildSelectionV1.run
  Tests.Materialization.TargetRegistryV1.run
  Tests.Materialization.RequirementResolverV1.run
  Tests.Materialization.IdentityChainV1.run
  Tests.Materialization.EvmPlanSchemaV1.run
  Tests.Materialization.AleoPlanSchemaV1.run
  Tests.Materialization.OutputSetV1.run
  Tests.Materialization.OutputEnvelopeV1.run
  Tests.Materialization.EngineeringFinalizationV1.run
  Tests.Materialization.EngineeringDiskClosureV1.run
  Tests.Materialization.run
  Tests.Materialization.Aleo.run
  Tests.Materialization.AleoAcceptance.run
  Tests.Materialization.AleoCompiledFinalizationV1.run
  Tests.Materialization.QuintSourceV1.run
  Tests.Materialization.QuintAcceptance.run
  Tests.Materialization.EvmSmoke.run
  Tests.Materialization.EvmSolcAcceptance.run
  Tests.Materialization.NearWasmAcceptance.run
  Tests.Materialization.NearHostModel.run
  Tests.Materialization.NoirRelationModel.run
  Tests.Materialization.SolanaPlanV1.run
  Tests.Materialization.SolanaCpiPlanV1.run
  Tests.Materialization.SolanaCpiDeriveV1.run
  Tests.Materialization.SolanaCpiPreflightV1.run
  Tests.Materialization.SolanaCpiUnsignedV1.run
  Tests.Materialization.SolanaCpiPdaV1.run
  Tests.Materialization.SolanaCpiSystemV1.run
  Tests.Materialization.SolanaCpiTokenV1.run
  Tests.Materialization.SolanaCpiAtaV1.run
  Tests.Materialization.SolanaCpiEscrowV1.run
  Tests.Materialization.SolanaCpiPfAssetsV1.run
  Tests.Materialization.SolanaCpiActivationV1.run
  Tests.Materialization.SolanaProductSynthesizeV1.run
  Tests.Targets.SolanaAsmV1.run
  Tests.Targets.SolanaAcc1LayoutV1.run
  Tests.Targets.SolanaProductFrameV1.run
  Tests.Targets.SolanaProductCpiRecipesV1.run
  Tests.Targets.SolanaElfV1.run
  Tests.Targets.EvmCancunV1.run
  Tests.Materialization.EvmCorpusBlockedV1.run
  Tests.Product.CounterV1Evm.run
  Tests.Product.PrivateSum4PrivacyV1.run
  Tests.Product.PerfCheckHarnessV1.run
  Tests.Product.TokenV1.run
  Tests.Product.TipJarQuintV1.run
  Tests.Product.TipJarEvmV1.run
  Tests.Materialization.EvmPfAssetsV1.run
  Tests.Product.TokenJarEvmV1.run
  Tests.Product.TipJarSolanaV1.run
  Tests.Product.TokenJarSolanaV1.run
  Tests.Product.MiniAmmSolanaV1.run
  Tests.Product.BodyCpiMapTipSolanaV1.run
  Tests.Product.BodyCpiSysPaySolanaV1.run
  Tests.Product.BodyCpiTokenPaySolanaV1.run
  Tests.Product.MiniAmmAssetsSolanaV1.run
  Tests.Product.MiniAmmAssetsEvmV1.run
  Tests.Product.MiniAmmProofSurfaceV1.run
  Tests.Product.TipJarNearV1.run
  Tests.Materialization.NearPfAssetsV1.run
  Tests.Product.TipJarCosmWasmV1.run
  Tests.Materialization.CosmWasmPfAssetsV1.run
  Tests.Materialization.PsyPfAssetsV1.run
  Tests.Materialization.AleoPfAssetsV1.run
  Tests.CLI.Emit.run
  Tests.CLI.ToolchainPolicy.run
  Tests.CLI.DiagnosticsV1.run
  Tests.CLI.ResourceFlagsV1.run
  Tests.CLI.InlineProofProductV1.run

unsafe def main : IO Unit := do
  Tests.Core.Common.run
  Tests.Core.CommonRemaining.run
  Tests.Core.CommonScalars.run
  Tests.Core.Unicode.run
  Tests.Core.DiagnosticV1.run
  Tests.Core.DiagnosticBundleV1.run
  Tests.Frontend.ProtocolV1.run
  Tests.Frontend.WorkerV1.run
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Compiler.CheckV1ProductGate.run
  Tests.Compiler.DiagnosticPipelineV1.run
  Tests.Compiler.ProofSubjectFilesV1.run
  Tests.Compiler.InlineProofAuditV1.run
  Tests.Compiler.ProofWorkerV1.run
  Tests.Compiler.ProofWorkerSupervisorV1.run
  Tests.Compiler.InlineProofProtocolV1.run
  Tests.Compiler.InlineProofElaborationV1.run
  Tests.Compiler.InlineProofCertifierV1.run
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
  runSemanticTests
  Tests.Language.ProgramExports.run
  Tests.Language.ProgramExportAcceptance.run
  Tests.Language.ProgramExportAcceptanceEmpty.run
  Tests.Language.ProgramCommandAcceptance.run
  Tests.Language.InlineProofAuthoringV1.run
  Tests.Language.TheoremInventoryV1.run
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
  runMaterializationAndProductTests
  IO.println "proof-forge-next-tests: ok"
