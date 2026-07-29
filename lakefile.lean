import Lake
open Lake DSL

private def xcrunValue (args : Array String) : IO String := do
  let output ← IO.Process.output {
    cmd := "/usr/bin/xcrun"
    args
    stdin := .null
    stdout := .piped
    stderr := .piped
    inheritEnv := true
  }
  unless output.exitCode == 0 do
    throw <| IO.userError "xcrun failed while resolving the macOS native toolchain"
  let value := output.stdout.trimAscii.copy
  if value.isEmpty then
    throw <| IO.userError "xcrun returned an empty macOS native toolchain path"
  pure value

package «proof-forge-next» where
  version := v!"0.1.0"

extern_lib proof_forge_frontend_native_v1 pkg := do
  let source ← inputFile
    (pkg.dir / "ProofForgeV2/Frontend/Native/proof_forge_frontend_native_v1.c") false
  let leanInclude ← getLeanIncludeDir
  let (cc, platformArgs) ←
    if System.Platform.isOSX then do
      let cc := System.FilePath.mk (← liftM <| xcrunValue #["--find", "clang"])
      let sdk ← liftM <| xcrunValue #["--sdk", "macosx", "--show-sdk-path"]
      pure (cc, #["-isysroot", sdk])
    else do
      let cc ← getLeanCc
      pure (cc, #[])
  let object ← buildO
    (pkg.buildDir / "native/frontend/proof_forge_frontend_native_v1.o") source #[]
    (#["-std=c11", "-fPIC", "-Wall", "-Wextra", "-Werror", "-I",
        leanInclude.toString] ++ platformArgs)
    cc
  buildStaticLib
    (pkg.buildDir / "lib" / nameToStaticLib "proof_forge_frontend_native_v1") #[object]

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
    `Tests.Compiler.CheckV1ProductGate,
    `Tests.Compiler.DiagnosticPipelineV1,
    `Tests.Typed.NameResolutionV1,
    `Tests.Typed.DiagnosticLocationsV1,
    `Tests.Typed.TypeCheckExpressionsV1,
    `Tests.Typed.TypeCheckCallsV1,
    `Tests.Typed.TypeCheckStatementsV1,
    `Tests.Typed.TypeCheckMatchV1,
    `Tests.Typed.CallGraphV1,
    `Tests.Typed.EffectCheckV1,
    `Tests.Typed.BoundCheckV1,
    `Tests.Typed.DisclosureCheckV1,
    `Tests.Typed.RequirementsInferV1,
    `Tests.Typed.CheckV1,
    `Tests.Semantic.WireV1,
    `Tests.Semantic.InvariantABI,
    `Tests.Semantic.ReferenceV1,
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
    `Tests.Language.ProgramV1OriginJoin,
    `Tests.Language.ProgramV1DiagnosticLocate,
    `Tests.Language.ProgramV1Diagnostics,
    `Tests.Language.ProgramV1Bounds,
    `Tests.Language.ProgramV1SourceFullTagGolden.Source,
    `Tests.Language.ProgramV1SourceFullTagGolden,
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
    `Tests.Materialization.BuildSelectionV1,
    `Tests.Materialization.TargetRegistryV1,
    `Tests.Materialization.RequirementResolverV1,
    `Tests.Materialization.OutputEnvelopeV1,
    `Tests.Materialization.EngineeringFinalizationV1,
    `Tests.Materialization.EngineeringDiskClosureV1,
    `Tests.Materialization.TargetIrFixtures,
    `Tests.Materialization.Targets,
    `Tests.Materialization.EvmSmoke,
    `Tests.Materialization.NearHostModel,
    `Tests.Materialization.NoirRelationModel,
    `Tests.Product.CounterV1Evm,
    `Tests.CLI.Emit,
    `Tests.CLI.ToolchainPolicy,
    `Tests.CLI.DiagnosticsV1,
    `Tests.Core.DiagnosticV1,
    `Tests.Core.DiagnosticBundleV1,
    `Tests.Frontend.ProtocolV1,
    `Tests.Frontend.WorkerV1,
    `Tests.Frontend.SafeOpenV1,
    `Tests.Frontend.DarwinSupervisorReceiptV1,
    `Tests.Frontend.DarwinWorkerSupervisorV1
  ]

lean_exe proof_forge_next where
  exeName := "proof-forge-next"
  -- Thin root: top-level `main` only. Product CLI API is `ProofForgeV2.CLI.run`
  -- in `ProofForgeV2.CLI.Main` (importable by tests without main collision).
  root := `ProofForgeV2.CLI.Exe
  -- Parser / module loading pulls Init interpreter symbols (e.g. IO.getRandomBytes).
  supportInterpreter := true

lean_exe proof_forge_frontend_worker_v1 where
  exeName := "proof-forge-frontend-worker-v1"
  root := `ProofForgeV2.Frontend.WorkerMainV1
  supportInterpreter := true

lean_exe proof_forge_next_tests where
  exeName := "proof-forge-next-tests"
  root := `Tests
  supportInterpreter := true

lean_exe proof_forge_next_fast_tests where
  exeName := "proof-forge-next-fast-tests"
  root := `Tests.Fast
  supportInterpreter := true
