import Lake
open Lake DSL

package «proof-forge-next» where
  version := v!"0.1.0"

@[default_target]
lean_lib ProofForgeV2 where
  roots := #[`ProofForgeV2, `Examples]

lean_lib ProofForgeV2Tests where
  roots := #[
    `Tests.Fixtures.SourcePrograms,
    `Tests.Core.Common,
    `Tests.Core.CommonRemaining,
    `Tests.Core.CommonScalars,
    `Tests.Core.Unicode,
    `Tests.Core.Semantics,
    `Tests.Compiler.Pipeline,
    `Tests.Compiler.TypedNameIndex,
    `Tests.Compiler.ValidatedSourceV1Pipeline,
    `Tests.Language.ParserSession,
    `Tests.Language.ProgramExportFixtures.A,
    `Tests.Language.ProgramExportFixtures.B,
    `Tests.Language.ProgramExportFixtures.OrderAB,
    `Tests.Language.ProgramExportFixtures.OrderBA,
    `Tests.Language.ProgramExportFixtures.Shared,
    `Tests.Language.ProgramExportSnapshot,
    `Tests.Language.ProgramExports,
    `Tests.Language.ProgramExportAcceptanceEmpty,
    `Tests.Language.ProgramExportAcceptance,
    `Tests.Language.ProgramCommandAcceptance,
    `Tests.Language.ProgramSyntax,
    `Tests.Language.ProgramV1Declarations,
    `Tests.Language.ProgramV1DeclarationNegatives,
    `Tests.Language.ProgramV1ExternalStatements,
    `Tests.Language.ProgramV1ControlFlow,
    `Tests.Language.ProgramV1ExpressionForms,
    `Tests.Language.ProgramV1UnaryExpressions,
    `Tests.Language.ProgramV1ArithmeticExpressions,
    `Tests.Language.ProgramV1ShiftExpressions,
    `Tests.Language.ProgramV1EqualityExpressions,
    `Tests.Language.ProgramV1OrderingComparisons,
    `Tests.Language.ProgramV1BitwiseExpressions,
    `Tests.Language.ProgramV1LogicalExpressions,
    `Tests.Language.ProgramV1CoreStatements,
    `Tests.Language.ProgramV1MatchStatements,
    `Tests.Language.ProgramV1MatchExpressions,
    `Tests.Language.ProgramV1ConstructorPatterns,
    `Tests.Language.ProgramV1FieldPlaces,
    `Tests.Language.ProgramV1IndexedPlaces,
    `Tests.Language.ProgramV1PlaceSuffixes,
    `Tests.Language.ProgramV1RevertEmitStatements,
    `Tests.Language.ProgramV1StringLiterals,
    `Tests.Language.ProgramV1TypeSurface,
    `Tests.Language.ProgramV1SpanJoin,
    `Tests.Language.ProgramV1Diagnostics,
    `Tests.Language.AggregateDeclarations,
    `Tests.Language.StateVisibility,
    `Tests.Language.SourceIdentity,
    `Tests.Language.SourceNodeAssignmentCollisionV1,
    `Tests.Language.SourceNodeTraversalV1,
    `Tests.Language.SourceProgramWireBoundaryGoldenV1,
    `Tests.Language.SourceProgramWireFieldCountGoldenV1,
    `Tests.Language.SourceProgramWireGoldenV1,
    `Tests.Language.SourceProgramWireMarkerGoldenV1,
    `Tests.Language.SourceProgramWireUnknownTagGoldenV1,
    `Tests.Language.SourceSpan,
    `Tests.Language.SourceWireAcceptance,
    `Tests.Language.SourceWireCodecV1,
    `Tests.Language.SourceWireDecodeV1,
    `Tests.Language.SourceNameComponentV1,
    `Tests.Language.SourceQualifiedNameV1,
    `Tests.Language.SourceAstLeafV1,
    `Tests.Language.SourceAstSupportV1,
    `Tests.Language.SourceAstPatternV1,
    `Tests.Language.SourceAstDeclV1,
    `Tests.Language.SourceAstSpineV1,
    `Tests.Language.SourceAstSpineCodecV1,
    `Tests.Language.SourceAstSpineDeclV1,
    `Tests.Language.SourceAstProgramItemV1,
    `Tests.Language.SourceAstProgramV1,
    `Tests.Language.SourceAstCanonicalRootV1,
    `Tests.Language.SourceAstProgramValidateV1,
    `Tests.Language.SourceAstWideEncoderV1,
    `Tests.Language.SourceAstScalarDecodeV1,
    `Tests.Language.SourceAstTypeDecodeV1,
    `Tests.Language.SourceAstPatternDecodeV1,
    `Tests.Language.SourceAstSupportDecodeV1,
    `Tests.Language.SourceAstDeclDecodeV1,
    `Tests.Language.SourceAstSpinePlaceExprDecodeV1,
    `Tests.Language.SourceAstSpineStmtDecodeV1,
    `Tests.Language.SourceAstSpineDeclDecodeV1,
    `Tests.Language.SourceAstProgramItemDecodeV1,
    `Tests.Language.SourceAstProgramDecodeV1,
    `Tests.Language.SourceAstCanonicalRootDecodeV1,
    `Tests.Language.FrontendParity,
    `Tests.Language.Loader,
    `Tests.Materialization.Targets,
    `Tests.Materialization.EvmSmoke,
    `Tests.Materialization.NearHostModel,
    `Tests.Materialization.NoirRelationModel,
    `Tests.Product.CounterV1Evm,
    `Tests.CLI.Emit,
    `Tests.CLI.ToolchainPolicy,
    `Tests.Core.DiagnosticV1
  ]

lean_exe proof_forge_next where
  exeName := "proof-forge-next"
  root := `ProofForgeV2.CLI.Main
  -- Parser / module loading pulls Init interpreter symbols (e.g. IO.getRandomBytes).
  supportInterpreter := true

lean_exe proof_forge_next_tests where
  exeName := "proof-forge-next-tests"
  root := `Tests
  supportInterpreter := true

lean_exe proof_forge_next_fast_tests where
  exeName := "proof-forge-next-fast-tests"
  root := `Tests.Fast
  supportInterpreter := true
