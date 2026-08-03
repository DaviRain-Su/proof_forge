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

private def proofSubjectNativeCompiler : IO (System.FilePath × Array String) := do
  if System.Platform.isOSX then
    let cc := System.FilePath.mk (← xcrunValue #["--find", "clang"])
    let sdk ← xcrunValue #["--sdk", "macosx", "--show-sdk-path"]
    pure (cc, #["-isysroot", sdk])
  else if System.Platform.isWindows then
    throw <| IO.userError "proof-subject native stable-read is unsupported on Windows"
  else
    let cc := System.FilePath.mk "/usr/bin/cc"
    unless ← cc.pathExists do
      throw <| IO.userError "proof-subject native stable-read requires /usr/bin/cc"
    pure (cc, #[])

package «proof-forge-next» where
  version := v!"0.1.0"

extern_lib proof_forge_proof_subject_files_v1 pkg := do
  let source ← inputFile
    (pkg.dir / "ProofForgeV2/Compiler/Native/proof_forge_proof_subject_files_v1.c") false
  let leanInclude ← getLeanIncludeDir
  let (cc, platformArgs) ← liftM proofSubjectNativeCompiler
  let object ← buildO
    (pkg.buildDir / "native/compiler/proof_forge_proof_subject_files_v1.o") source #[]
    (#["-std=c11", "-fPIC", "-Wall", "-Wextra", "-Werror", "-I",
        leanInclude.toString] ++ platformArgs)
    cc
  buildStaticLib
    (pkg.buildDir / "lib" / nameToStaticLib "proof_forge_proof_subject_files_v1") #[object]

extern_lib proof_forge_proof_bundle_files_v1 pkg := do
  let source ← inputFile
    (pkg.dir / "ProofForgeV2/Compiler/Native/proof_forge_proof_bundle_files_v1.c") false
  let leanInclude ← getLeanIncludeDir
  let (cc, platformArgs) ← liftM proofSubjectNativeCompiler
  let object ← buildO
    (pkg.buildDir / "native/compiler/proof_forge_proof_bundle_files_v1.o") source #[]
    (#["-std=c11", "-fPIC", "-Wall", "-Wextra", "-Werror", "-I",
        leanInclude.toString] ++ platformArgs) cc
  buildStaticLib
    (pkg.buildDir / "lib" / nameToStaticLib "proof_forge_proof_bundle_files_v1") #[object]

extern_lib proof_forge_proof_worker_supervisor_v1 pkg := do
  let source ← inputFile
    (pkg.dir / "ProofForgeV2/Compiler/Native/proof_forge_proof_worker_supervisor_v1.c") false
  let leanInclude ← getLeanIncludeDir
  let (cc, platformArgs) ← liftM proofSubjectNativeCompiler
  let object ← buildO
    (pkg.buildDir / "native/compiler/proof_forge_proof_worker_supervisor_v1.o") source #[]
    (#["-std=c11", "-fPIC", "-Wall", "-Wextra", "-Werror", "-I",
        leanInclude.toString] ++ platformArgs) cc
  buildStaticLib
    (pkg.buildDir / "lib" / nameToStaticLib "proof_forge_proof_worker_supervisor_v1") #[object]

@[default_target]
lean_lib ProofForgeV2 where
  roots := #[`ProofForgeV2, `Examples]

lean_lib ProofForgeV2Tests where
  roots := #[
    `Tests.Core.Common,
    `Tests.Core.CommonRemaining,
    `Tests.Core.CommonScalars,
    `Tests.Core.Unicode,
    `Tests.Core.ToolLockV4,
    `Tests.Compiler.ValidatedSourceV1Pipeline,
    `Tests.Compiler.CheckV1ProductGate,
    `Tests.Compiler.DiagnosticPipelineV1,
    `Tests.Compiler.ProofBundleFilesV1,
    `Tests.Compiler.ProofSubjectFilesV1,
    `Tests.Compiler.InlineProofAuditV1,
    `Tests.Compiler.ProofWorkerV1,
    `Tests.Compiler.ProofWorkerSupervisorV1,
    `Tests.Compiler.InlineProofProtocolV1,
    `Tests.Compiler.InlineProofElaborationV1,
    `Tests.Compiler.InlineProofCertifierV1,
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
    `Tests.Typed.AuthorityCustodyCheckV1,
    `Tests.Typed.ContextExtensionCheckV1,
    `Tests.Typed.RequirementsInferV1,
    `Tests.Typed.CheckV1,
    `Tests.Semantic.WireV1,
    `Tests.Semantic.InvariantABI,
    `Tests.Semantic.InvariantTheoremV1,
    `Tests.Semantic.ProofBridgeV1,
    `Tests.Semantic.ProofedCertV1,
    `Tests.Semantic.ProofedEncodeCertV1,
    `Tests.Semantic.ProofedDecodeCertV1,
    `Tests.Semantic.SimpleClosureCertV1,
    `Tests.Semantic.AuthorWireCertV1,
    `Tests.Semantic.SimpleClosureTraceV1,
    `Tests.Semantic.SimpleClosureStructureCertV1,
    `Tests.Semantic.SimpleClosureEncodeV1,
    `Tests.Semantic.ProofedClosedCertV1,
    `Tests.Semantic.ReferenceV1,
    `Tests.Semantic.NormalizeConst,
    `Tests.Semantic.ProofBundleV1,
    `Tests.Semantic.ProofSubjectGeneratedFixtureV1,
    `Tests.Semantic.ProofSubjectV1,
    `Tests.Semantic.ProofReferenceJoinV1,
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
    `Tests.Language.InlineProofAuthoringV1,
    `Tests.Language.TheoremInventoryV1,
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
    `Tests.Materialization.RegistryRootV1,
    `Tests.Materialization.RequirementResolverV1,
    `Tests.Materialization.IdentityChainV1,
    `Tests.Materialization.EvmPlanSchemaV1,
    `Tests.Materialization.OutputSetV1,
    `Tests.Materialization.OutputEnvelopeV1,
    `Tests.Materialization.EngineeringFinalizationV1,
    `Tests.Materialization.ArtifactContentV1,
    `Tests.Materialization.EngineeringDiskClosureV1,
    `Tests.Materialization.TargetIrFixtures,
    `Tests.Materialization.Targets,
    `Tests.Materialization.Aleo,
    `Tests.Materialization.AleoAcceptance,
    `Tests.Materialization.PsySourceV1,
    `Tests.Materialization.PsyAcceptance,
    `Tests.Materialization.EvmSmoke,
    `Tests.Materialization.EvmSolcAcceptance,
    `Tests.Materialization.NearWasmAcceptance,
    `Tests.Materialization.NearSandboxAcceptance,
    `Tests.Materialization.CosmWasmCheckAcceptance,
    `Tests.Materialization.CosmWasmPlanV1,
    `Tests.Materialization.TonPlanV1,
    `Tests.Materialization.NearHostModel,
    `Tests.Materialization.NoirRelationModel,
    `Tests.Materialization.NoirCompileAcceptance,
    `Tests.Materialization.SolanaPlanV1,
    `Tests.Targets.SolanaAsmV1,
    `Tests.Targets.SolanaElfV1,
    `Tests.Targets.EvmCancunV1,
    `Tests.Materialization.EvmCorpusBlockedV1,
    `Tests.Product.CounterV1Evm,
    `Tests.Product.PrivateSum4PrivacyV1,
    `Tests.Product.PerfCheckHarnessV1,
    `Tests.Product.TokenV1,
    `Tests.CLI.Emit,
    `Tests.CLI.ToolchainPolicy,
    `Tests.CLI.DiagnosticsV1,
    `Tests.CLI.ResourceFlagsV1,
    `Tests.CLI.InlineProofProductV1,
    `Tests.Core.DiagnosticV1,
    `Tests.Core.DiagnosticBundleV1,
    `Tests.Frontend.ProtocolV1,
    `Tests.Frontend.WorkerV1
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

lean_exe proof_forge_compiler_proof_worker_v1 where
  exeName := "proof-forge-compiler-proof-worker-v1"
  root := `ProofForgeV2.Compiler.ProofWorkerMainV1
  supportInterpreter := true

lean_exe proof_forge_compiler_proof_worker_v2 where
  exeName := "proof-forge-compiler-proof-worker-v2"
  root := `ProofForgeV2.Compiler.ProofWorkerMainV2
  supportInterpreter := true

lean_exe proof_forge_next_tests where
  exeName := "proof-forge-next-tests"
  root := `Tests
  -- Parser-backed suites transitively require Init interpreter externs such as
  -- IO.getRandomBytes on Linux, even though this aggregate is non-product.
  supportInterpreter := true

lean_exe proof_forge_next_fast_tests where
  exeName := "proof-forge-next-fast-tests"
  root := `Tests.Fast
  supportInterpreter := true

-- Memory-bounded shards: the single-process aggregate keeps a high-water RSS
-- above the 7 GB hosted runner limit because Lean does not return heap to the
-- OS between suites. Each shard runs an independent process so the OS reclaims
-- memory when it exits. `test` runs the shards instead of the aggregate.
--
-- Memory-bounded shards: the single-process aggregate keeps a high-water RSS
-- above the 7 GB hosted runner limit because Lean does not return heap to the
-- OS between suites. Each shard runs an independent process so the OS reclaims
-- memory when it exits. `test` runs the shards instead of the aggregate.
--
-- BUILD-3 (revised): test suite exes keep `supportInterpreter := true`. The
-- earlier `false` probe saved ~7–15 MiB per shard but broke linux runners:
-- Lean 4.31 linux builds do not export `IO.getRandomBytes` (and a few other
-- `Init/Std` externs) without the interpreter, so any shard whose transitive
-- imports touch those symbols fails with "Could not find native
-- implementation". The ~170 MiB/shard cost is well within the 7 GB runner
-- budget (9 shards × ~170 MiB ≈ 1.5 GB peak, and shards run with limited
-- parallelism). Product CLI already keeps the interpreter on for the
-- parser/elaborator.
lean_exe proof_forge_next_tests_shard_core where
  exeName := "proof-forge-next-tests-shard-core"
  root := `Tests.Shards.Core
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_worker where
  exeName := "proof-forge-next-tests-shard-worker"
  root := `Tests.Shards.Worker
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_typed where
  exeName := "proof-forge-next-tests-shard-typed"
  root := `Tests.Shards.Typed
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_language where
  exeName := "proof-forge-next-tests-shard-language"
  root := `Tests.Shards.Language
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_language_b where
  exeName := "proof-forge-next-tests-shard-language-b"
  root := `Tests.Shards.LanguageB
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_language_c where
  exeName := "proof-forge-next-tests-shard-language-c"
  root := `Tests.Shards.LanguageC
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_aggregate where
  exeName := "proof-forge-next-tests-shard-aggregate"
  root := `Tests.Shards.Aggregate
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_language_heavy where
  exeName := "proof-forge-next-tests-shard-language-heavy"
  root := `Tests.Shards.LanguageHeavy
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_source where
  exeName := "proof-forge-next-tests-shard-source"
  root := `Tests.Shards.Source
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_source_b where
  exeName := "proof-forge-next-tests-shard-source-b"
  root := `Tests.Shards.SourceB
  supportInterpreter := true

lean_exe proof_forge_next_tests_shard_targets where
  exeName := "proof-forge-next-tests-shard-targets"
  root := `Tests.Shards.Targets
  supportInterpreter := true
