import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.ConstructorInit
import ProofForge.Backend.Psy.IR
import ProofForge.Contract.Client
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec.Json
import ProofForge.Backend.WasmNear
import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Backend.Aleo.IR
import ProofForge.Backend.CosmWasm.EmitWat
import ProofForge.Backend.Move.Aptos
import ProofForge.Backend.Move.Sui
import ProofForge.Backend.Quint.Scenario
import ProofForge.Backend.Quint.Lower
import ProofForge.Cli.Fixture
import ProofForge.Cli.Scaffold
import ProofForge.Cli.Deploy
import ProofForge.Cli.Check
import ProofForge.Cli.ContractSourceArtifacts
import ProofForge.Cli.Metadata
import ProofForge.Cli.Quint
import ProofForge.Compiler.TS.AST
import ProofForge.Compiler.TS.Printer
import ProofForge.Compiler.TS.Emit
import ProofForge.IR.Examples.AbiAggregateProbe
import ProofForge.IR.Examples.AbiScalarProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.ArithmeticProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.AssignmentProbe
import ProofForge.IR.Examples.BitwiseProbe
import ProofForge.IR.Examples.BoolStorageArrayProbe
import ProofForge.IR.Examples.BoolStorageScalarProbe
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.ElseIfProbe
import ProofForge.IR.Examples.ControlFlowAssertProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Examples.ErrorRefProbe
import ProofForge.IR.Examples.PureMath
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.EvmAbiAggregateProbe
import ProofForge.IR.Examples.EvmArrayAbiProbe
import ProofForge.IR.Examples.EvmDynamicAbiProbe
import ProofForge.IR.Examples.EvmDynamicArrayProbe
import ProofForge.IR.Examples.EvmMemoryArrayProbe
import ProofForge.IR.Examples.EvmPackedStorageProbe
import ProofForge.IR.Examples.EvmErrorsProbe
import ProofForge.IR.Examples.EvmFallbackProbe
import ProofForge.IR.Examples.EvmArrayValueProbe
import ProofForge.IR.Examples.EvmAssignOpProbe
import ProofForge.IR.Examples.EvmCrosscallProbe
import ProofForge.IR.Examples.EvmContextProbe
import ProofForge.IR.Examples.EvmExpressionProbe
import ProofForge.IR.Examples.EvmHashProbe
import ProofForge.IR.Examples.EvmLoopProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.IR.Examples.EvmStructArrayValueProbe
import ProofForge.IR.Examples.EvmStructValueProbe
import ProofForge.IR.Examples.EvmTypedMapProbe
import ProofForge.IR.Examples.EvmTypedStorageProbe
import ProofForge.IR.Examples.ExpressionPredicateProbe
import ProofForge.IR.Examples.GenericEntrypointProbe
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.HashStorageProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.NestedAggregateProbe
import ProofForge.IR.Examples.StorageNestedAggregateProbe
import ProofForge.IR.Examples.StructArrayProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.U32ArithmeticProbe
import ProofForge.IR.Examples.U32HashPackingProbe
import ProofForge.IR.Examples.U32StorageArrayProbe
import ProofForge.IR.Examples.U32StorageScalarProbe
import ProofForge.Target
import ProofForge.Target.Check
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.HexUtil
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.EmitMode
import ProofForge.Cli.Process
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.Artifact
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.SolanaCommands
import ProofForge.Cli.FileUtil
import ProofForge.Cli.PsyArtifacts
import ProofForge.Cli.EmitWatArtifacts
import ProofForge.Cli.IrJson
import ProofForge.Cli.EvmFixtures
import ProofForge.Cli.LearnArtifacts
import ProofForge.Cli.TargetJson
import ProofForge.Cli.Usage
import ProofForge.Cli.Options
import ProofForge.Cli.TargetFirst
import ProofForge.Cli.LegacyArgs

open Lean
open System
open ProofForge.Cli.JsonUtil
open ProofForge.Cli.HexUtil
open ProofForge.Cli.ConstructorAbi

namespace ProofForge.Cli

export ProofForge.Cli.ConstructorAbi (ConstructorParamSpec ConstructorValueSpec)
export ProofForge.Cli.ConstructorAbi
  (supportedConstructorAbiTypes constructorParamIsDynamic constructorParamEncoding
   constructorAbiTypeSupported supportedConstructorAbiTypesMessage
   parseConstructorParamSpec parseConstructorValueSpec
   encodeUintConstructorArg encodeBoolConstructorArg encodeDynamicBytesTail
   parseCommaSeparatedNatList encodeStringConstructorTail encodeBytesConstructorTail
   encodeUint256ArrayConstructorTail encodeDynamicConstructorTail encodeStaticConstructorValue
   constructorParamExists constructorValueCount findConstructorValue?
   validateConstructorValues validateConstructorValuesAgainstParams
   encodeConstructorValues constructorSchemaHasDynamic validateConstructorSchemaAndArgs)
export ProofForge.Cli.EmitMode (EmitMode)

def emitWatFixtureModule? (fixtureId : String) : Option ProofForge.IR.Module :=
  ProofForge.Cli.Check.emitWatFixtureModule? fixtureId

unsafe def checkCommand (opts : CliOptions) : IO UInt32 := do
  let targetId ← match opts.targetId? with
    | some id => pure id
    | none => throw <| IO.userError "check requires --target <id>"
  ProofForge.Cli.Check.checkCommand
    targetId
    opts.fixture?
    (opts.input?.map (·.toString))
    opts.format?
    opts.reportFormat?
    opts.root?
    opts.moduleName?

def compileCounterIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near Counter package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileContextIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.ContextProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near ContextProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.HashProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near HashProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileMapIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.MapProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near MapProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileCounterIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/Counter.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compilePureMathIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/PureMath.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.PureMath.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileCounterIrCosmWasm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/cosmwasm/Counter.wat")
  match ProofForge.Backend.CosmWasm.EmitWat.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

def writePackageFiles (outputDir : FilePath) (pkg : Array ProofForge.Backend.Move.Aptos.PackageFile) : IO Unit := do
  for file in pkg do
    let path := outputDir / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    writeTextFile path file.content

def writeSuiPackageFiles (outputDir : FilePath) (pkg : Array ProofForge.Backend.Move.Sui.PackageFile) : IO Unit := do
  for file in pkg do
    let path := outputDir / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    writeTextFile path file.content

def compileCounterIrAptos (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aptos/counter")
  match ProofForge.Backend.Move.Aptos.renderPackage ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      writePackageFiles output pkg
      IO.println s!"wrote Aptos package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

def loadQuintScenarioConfig (opts : CliOptions) : IO ProofForge.Backend.Quint.Scenario.Config := do
  match opts.scenario? with
  | none => return {}
  | some path =>
      let contents ← IO.FS.readFile path
      match ProofForge.Backend.Quint.Scenario.parse contents with
      | .ok cfg => return cfg
      | .error msg => throw <| IO.userError s!"failed to parse scenario {path}: {msg}"

def compileCounterIrSui (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/sui/counter")
  let module := ProofForge.IR.Examples.Counter.module
  match ProofForge.Backend.Move.Sui.renderPackage module with
  | .ok pkg =>
      writeSuiPackageFiles output pkg
      let moveToml := output / "Move.toml"
      let sourceOutput := output / "sources" / "counter.move"
      let testsOutput := output / "tests" / "counter_tests.move"
      let clientOutput := output / "proof-forge-client.ts"
      IO.println s!"wrote Sui package to {output}"
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (output / "proof-forge-artifact.json")
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString "move-sui"),
        ("targetFamily", jsonString "move"),
        ("artifactKind", jsonString "move-package"),
        ("fixture", jsonString "counter"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Contract.SdkSchema.irVersion),
        ("sourceModule", jsonString "Counter"),
        ("sdkSchema", jsonString "proof-forge-sdk.json"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "assertions.check"]),
        ("artifacts", jsonObject #[
          ("moveToml", ← artifactEntryJson moveToml),
          ("source", ← artifactEntryJson sourceOutput),
          ("tests", ← artifactEntryJson testsOutput)
        ]),
        ("validation", jsonObject #[
          ("sourceGeneration", jsonString "passed"),
          ("suiMoveBuild", jsonString "pending")
        ])
      ]
      writeTextFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      if opts.fromNewSurface then
        let spec := ProofForge.Contract.ContractSpec.fromIR module
        discard <| writeSdkSchemaFile "move-sui" spec output #[
          ("artifactMetadata", metadataOutput),
          ("manifest", moveToml),
          ("primary", sourceOutput),
          ("tests", testsOutput)
        ] #[("typescript", clientOutput)]
      return 0
  | .error err =>
      throw <| IO.userError err.message

def compileIrQuintModule (opts : CliOptions) (module : ProofForge.IR.Module) (defaultOutput : String)
    (contractInvariants : Array (String × String) := #[])
    (contractLiveness : Array (String × String) := #[]) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk defaultOutput)
  let scenario ← loadQuintScenarioConfig opts
  let scenario := {
    scenario with
      contractInvariants := contractInvariants
      contractLiveness := contractLiveness
  }
  match ProofForge.Backend.Quint.Lower.renderModule module scenario with
  | .ok source =>
      match output.parent with
      | some parent => IO.FS.createDirAll parent
      | none => pure ()
      IO.FS.writeFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

def compileCounterIrQuint (opts : CliOptions) : IO UInt32 :=
  compileIrQuintModule opts ProofForge.IR.Examples.Counter.module "build/quint/Counter.qnt"
    ProofForge.Contract.Examples.Counter.spec.quintInvariants
    ProofForge.Contract.Examples.Counter.spec.quintLiveness

def compileValueVaultIrQuint (opts : CliOptions) : IO UInt32 :=
  compileIrQuintModule opts ProofForge.IR.Examples.ValueVault.module "build/quint/ValueVault.qnt"
    ProofForge.Contract.Examples.ValueVault.spec.quintInvariants
    ProofForge.Contract.Examples.ValueVault.spec.quintLiveness

def compileIrQuint (opts : CliOptions) : IO UInt32 := do
  let fixture ← match opts.fixture? with
    | some f => pure f
    | none => throw <| IO.userError "missing --fixture for --emit-ir-quint"
  let module ← match ProofForge.Cli.Quint.fixtureModule? fixture with
    | some m => pure m
    | none => throw <| IO.userError s!"unknown or unsupported Quint fixture `{fixture}`"
  compileIrQuintModule opts module (ProofForge.Cli.Quint.defaultOutputPath fixture)

def compileIrQuintScenario (opts : CliOptions) : IO UInt32 := do
  let fixture ← match opts.fixture? with
    | some f => pure f
    | none => throw <| IO.userError "missing --fixture for --emit-ir-quint-scenario"
  if !ProofForge.Cli.Quint.supportsFixture fixture then
    throw <| IO.userError s!"unknown or unsupported Quint fixture `{fixture}`"
  let output := opts.output?.getD (FilePath.mk (ProofForge.Cli.Quint.defaultScenarioOutputPath fixture))
  let cfg := ProofForge.Cli.Quint.scenarioConfigForEmit fixture
  let source := ProofForge.Backend.Quint.Scenario.renderToml fixture cfg
  match output.parent with
  | some parent => IO.FS.createDirAll parent
  | none => pure ()
  IO.FS.writeFile output source
  IO.println s!"wrote {output}"
  return 0

unsafe def compileEvmBytecode (opts : CliOptions) : IO UInt32 :=
  compileContractSourceEvmBytecode opts

unsafe def compileFile (opts : CliOptions) : IO UInt32 := do
  match opts.mode with
  | .yul => compileContractSourceYul opts
  | .evmBytecode => compileEvmBytecode opts
  | .counterIrYul => compileCounterIrYul opts
  | .counterIrTs => compileCounterIrTs opts
  | .counterIrBytecode => compileCounterIrBytecode opts
  | .valueVaultIrYul => compileValueVaultIrYul opts
  | .valueVaultIrBytecode => compileValueVaultIrBytecode opts
  | .errorRefIrYul => compileErrorRefIrYul opts
  | .errorRefIrBytecode => compileErrorRefIrBytecode opts
  | .errorRefIrSbpf => compileErrorRefIrSbpf opts
  | .errorRefEmitWat => compileErrorRefEmitWat opts
  | .learnYul => compileLearnYul opts
  | .learnBytecode => compileLearnBytecode opts
  | .learnSbpf => compileLearnSbpf opts
  | .contractSourceSbpf => compileContractSourceSbpf opts
  | .contractSourceEmitWat => compileContractSourceEmitWat opts
  | .learnTarget => compileLearnTarget opts
  | .learnTokenTarget => compileLearnTokenTarget opts
  | .abiScalarIrYul => compileAbiScalarIrYul opts
  | .abiScalarIrBytecode => compileAbiScalarIrBytecode opts
  | .assertIrYul => compileAssertIrYul opts
  | .assertIrBytecode => compileAssertIrBytecode opts
  | .assignmentIrYul => compileAssignmentIrYul opts
  | .assignmentIrBytecode => compileAssignmentIrBytecode opts
  | .evmAssignOpIrYul => compileEvmAssignOpIrYul opts
  | .evmAssignOpIrBytecode => compileEvmAssignOpIrBytecode opts
  | .conditionalIrYul => compileConditionalIrYul opts
  | .conditionalIrBytecode => compileConditionalIrBytecode opts
  | .contextIrYul => compileContextIrYul opts
  | .contextIrBytecode => compileContextIrBytecode opts
  | .evmEventIrYul => compileEvmEventIrYul opts
  | .evmEventIrBytecode => compileEvmEventIrBytecode opts
  | .evmCrosscallIrYul => compileEvmCrosscallIrYul opts
  | .evmCrosscallIrBytecode => compileEvmCrosscallIrBytecode opts
  | .evmExpressionIrYul => compileEvmExpressionIrYul opts
  | .evmExpressionIrBytecode => compileEvmExpressionIrBytecode opts
  | .evmHashIrYul => compileEvmHashIrYul opts
  | .evmHashIrBytecode => compileEvmHashIrBytecode opts
  | .evmLoopIrYul => compileEvmLoopIrYul opts
  | .evmLoopIrBytecode => compileEvmLoopIrBytecode opts
  | .evmMapIrYul => compileEvmMapIrYul opts
  | .evmMapIrBytecode => compileEvmMapIrBytecode opts
  | .evmStorageArrayIrYul => compileEvmStorageArrayIrYul opts
  | .evmStorageArrayIrBytecode => compileEvmStorageArrayIrBytecode opts
  | .evmStorageStructIrYul => compileEvmStorageStructIrYul opts
  | .evmStorageStructIrBytecode => compileEvmStorageStructIrBytecode opts
  | .evmTypedMapIrYul => compileEvmTypedMapIrYul opts
  | .evmTypedMapIrBytecode => compileEvmTypedMapIrBytecode opts
  | .evmTypedStorageIrYul => compileEvmTypedStorageIrYul opts
  | .evmTypedStorageIrBytecode => compileEvmTypedStorageIrBytecode opts
  | .evmArrayValueIrYul => compileEvmArrayValueIrYul opts
  | .evmArrayValueIrBytecode => compileEvmArrayValueIrBytecode opts
  | .evmStructArrayValueIrYul => compileEvmStructArrayValueIrYul opts
  | .evmStructArrayValueIrBytecode => compileEvmStructArrayValueIrBytecode opts
  | .evmStructValueIrYul => compileEvmStructValueIrYul opts
  | .evmStructValueIrBytecode => compileEvmStructValueIrBytecode opts
  | .evmAbiAggregateIrYul => compileEvmAbiAggregateIrYul opts
  | .evmAbiAggregateIrBytecode => compileEvmAbiAggregateIrBytecode opts
  | .evmArrayAbiIrYul => compileEvmArrayAbiIrYul opts
  | .evmArrayAbiIrBytecode => compileEvmArrayAbiIrBytecode opts
  | .evmDynamicAbiIrYul => compileEvmDynamicAbiIrYul opts
  | .evmDynamicAbiIrBytecode => compileEvmDynamicAbiIrBytecode opts
  | .evmDynamicArrayIrYul => compileEvmDynamicArrayIrYul opts
  | .evmDynamicArrayIrBytecode => compileEvmDynamicArrayIrBytecode opts
  | .evmMemoryArrayIrYul => compileEvmMemoryArrayIrYul opts
  | .evmMemoryArrayIrBytecode => compileEvmMemoryArrayIrBytecode opts
  | .evmPackedStorageIrYul => compileEvmPackedStorageIrYul opts
  | .evmPackedStorageIrBytecode => compileEvmPackedStorageIrBytecode opts
  | .evmErrorsIrYul => compileEvmErrorsIrYul opts
  | .evmErrorsIrBytecode => compileEvmErrorsIrBytecode opts
  | .evmFallbackIrYul => compileEvmFallbackIrYul opts
  | .evmFallbackIrBytecode => compileEvmFallbackIrBytecode opts
  | .counterIrPsy => compileCounterIrPsy opts
  | .eventIrPsy => compileEventIrPsy opts
  | .crosscallIrPsy => compileCrosscallIrPsy opts
  | .expressionPredicateIrPsy => compileExpressionPredicateIrPsy opts
  | .genericEntrypointIrPsy => compileGenericEntrypointIrPsy opts
  | .arithmeticIrPsy => compileArithmeticIrPsy opts
  | .bitwiseIrPsy => compileBitwiseIrPsy opts
  | .boolStorageArrayIrPsy => compileBoolStorageArrayIrPsy opts
  | .boolStorageScalarIrPsy => compileBoolStorageScalarIrPsy opts
  | .conditionalIrPsy => compileConditionalIrPsy opts
  | .elseIfIrPsy => compileElseIfIrPsy opts
  | .contextIrPsy => compileContextIrPsy opts
  | .hashIrPsy => compileHashIrPsy opts
  | .hashStorageIrPsy => compileHashStorageIrPsy opts
  | .mapIrPsy => compileMapIrPsy opts
  | .assertIrPsy => compileAssertIrPsy opts
  | .loopIrPsy => compileLoopIrPsy opts
  | .arrayIrPsy => compileArrayIrPsy opts
  | .structIrPsy => compileStructIrPsy opts
  | .structArrayIrPsy => compileStructArrayIrPsy opts
  | .abiAggregateIrPsy => compileAbiAggregateIrPsy opts
  | .nestedAggregateIrPsy => compileNestedAggregateIrPsy opts
  | .storageNestedAggregateIrPsy => compileStorageNestedAggregateIrPsy opts
  | .u32ArithmeticIrPsy => compileU32ArithmeticIrPsy opts
  | .u32HashPackingIrPsy => compileU32HashPackingIrPsy opts
  | .u32StorageScalarIrPsy => compileU32StorageScalarIrPsy opts
  | .u32StorageArrayIrPsy => compileU32StorageArrayIrPsy opts
  | .counterIrSbpf => compileCounterIrSbpf opts
  | .valueVaultIrSbpf => compileValueVaultIrSbpf opts
  | .controlIrSbpf => compileControlIrSbpf opts
  | .solanaSdkSbpf => compileSolanaSdkSbpf opts
  | .solanaSystemCpiSbpf => compileSolanaSystemCpiSbpf opts
  | .solanaSystemCreateAccountCpiSbpf => compileSolanaSystemCreateAccountCpiSbpf opts
  | .solanaSplTokenTransferCpiSbpf => compileSolanaSplTokenTransferCpiSbpf opts
  | .solanaSplTokenOpsCpiSbpf => compileSolanaSplTokenOpsCpiSbpf opts
  | .solanaSplTokenCloseAccountCpiSbpf => compileSolanaSplTokenCloseAccountCpiSbpf opts
  | .solanaSplTokenAuthorityCpiSbpf => compileSolanaSplTokenAuthorityCpiSbpf opts
  | .solanaAssociatedTokenCpiSbpf => compileSolanaAssociatedTokenCpiSbpf opts
  | .solanaSplToken2022CpiSbpf => compileSolanaSplToken2022CpiSbpf opts
  | .solanaSplToken2022PausableCpiSbpf => compileSolanaSplToken2022PausableCpiSbpf opts
  | .solanaSplToken2022TransferHookSbpf => compileSolanaSplToken2022TransferHookSbpf opts
  | .solanaElf => compileSolanaElf opts
  | .valueVaultSolanaElf => compileValueVaultSolanaElf opts
  | .solanaSystemCpiElf => compileSolanaSystemCpiElf opts
  | .solanaSystemCreateAccountCpiElf => compileSolanaSystemCreateAccountCpiElf opts
  | .solanaSplTokenTransferCpiElf => compileSolanaSplTokenTransferCpiElf opts
  | .solanaSplTokenOpsCpiElf => compileSolanaSplTokenOpsCpiElf opts
  | .solanaSplTokenCloseAccountCpiElf => compileSolanaSplTokenCloseAccountCpiElf opts
  | .solanaSplTokenAuthorityCpiElf => compileSolanaSplTokenAuthorityCpiElf opts
  | .solanaAssociatedTokenCpiElf => compileSolanaAssociatedTokenCpiElf opts
  | .solanaSplToken2022CpiElf => compileSolanaSplToken2022CpiElf opts
  | .solanaSplToken2022PausableCpiElf => compileSolanaSplToken2022PausableCpiElf opts
  | .solanaSplToken2022TransferHookElf => compileSolanaSplToken2022TransferHookElf opts
  | .solanaLogEventElf => compileSolanaLogEventElf opts
  | .solanaClockSysvarElf => compileSolanaClockSysvarElf opts
  | .solanaRentSysvarElf => compileSolanaRentSysvarElf opts
  | .solanaEpochScheduleSysvarElf => compileSolanaEpochScheduleSysvarElf opts
  | .solanaEpochRewardsSysvarElf => compileSolanaEpochRewardsSysvarElf opts
  | .solanaLastRestartSlotSysvarElf => compileSolanaLastRestartSlotSysvarElf opts
  | .solanaMemoryElf => compileSolanaMemoryElf opts
  | .solanaCryptoHashElf => compileSolanaCryptoHashElf opts
  | .solanaReturnDataComputeElf => compileSolanaReturnDataComputeElf opts
  | .sbpfAsm => compileSbpfAsm opts
  | .counterIrWasmNear => compileCounterIrWasmNear opts
  | .contextIrWasmNear => compileContextIrWasmNear opts
  | .hashIrWasmNear => compileHashIrWasmNear opts
  | .mapIrWasmNear => compileMapIrWasmNear opts
  | .counterEmitWat => compileCounterEmitWat opts
  | .contextEmitWat => compileContextEmitWat opts
  | .hashEmitWat => compileHashEmitWat opts
  | .mapEmitWat => compileMapEmitWat opts
  | .counterIrLeo => compileCounterIrLeo opts
  | .pureMathIrLeo => compilePureMathIrLeo opts
  | .counterIrCosmWasm => compileCounterIrCosmWasm opts
  | .counterIrAptos => compileCounterIrAptos opts
  | .counterIrSui => compileCounterIrSui opts
  | .counterIrQuint => compileCounterIrQuint opts
  | .valueVaultIrQuint => compileValueVaultIrQuint opts
  | .irQuint => compileIrQuint opts
  | .irQuintScenario => compileIrQuintScenario opts

end ProofForge.Cli

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | "init" :: rest =>
    match ProofForge.Cli.Scaffold.parseInitOptions rest with
    | Except.ok opts => ProofForge.Cli.Scaffold.initCommand opts
    | Except.error msg =>
        IO.eprintln msg
        return 1
  | "deploy" :: rest =>
    match ProofForge.Cli.Deploy.parseDeployOptions rest with
    | Except.ok opts => ProofForge.Cli.Deploy.deployCommand opts
    | Except.error msg =>
        IO.eprintln msg
        return 1
  | "metadata" :: rest =>
    match ProofForge.Cli.Metadata.parseMetadataOptions rest with
    | Except.ok opts => ProofForge.Cli.Metadata.metadataCommand opts
    | Except.error msg =>
        IO.eprintln msg
        return 1
  | _ =>
    let parseResult : Except String ProofForge.Cli.CliOptions :=
      match args with
      | "--list-targets" :: _ => Except.ok { cmd := ProofForge.Cli.Command.listTargets }
      | "--list-fixtures" :: _ => Except.ok { cmd := ProofForge.Cli.Command.listFixtures }
      | "build" :: rest =>
        match ProofForge.Cli.parseNewOptions rest {} with
        | Except.ok state =>
          match ProofForge.Cli.newCommandArgsToLegacy state "build" with
          | Except.ok legacyArgs =>
            match ProofForge.Cli.parseArgs legacyArgs {} with
            | Except.ok opts => Except.ok { opts with
                cmd := ProofForge.Cli.Command.build,
                scenario? := state.scenario?.map FilePath.mk,
                fromNewSurface := true }
            | Except.error msg => Except.error msg
          | Except.error msg => Except.error msg
        | Except.error msg => Except.error msg
      | "emit" :: rest =>
        match ProofForge.Cli.parseNewOptions rest {} with
        | Except.ok state =>
          match ProofForge.Cli.newCommandArgsToLegacy state "emit" with
          | Except.ok legacyArgs =>
            match ProofForge.Cli.parseArgs legacyArgs {} with
            | Except.ok opts => Except.ok { opts with
                cmd := ProofForge.Cli.Command.emit,
                fixture? := state.fixture?,
                scenario? := state.scenario?.map FilePath.mk,
                fromNewSurface := true }
            | Except.error msg => Except.error msg
          | Except.error msg => Except.error msg
        | Except.error msg => Except.error msg
      | "check" :: rest =>
        match ProofForge.Cli.parseNewOptions rest {} with
        | Except.ok state =>
          Except.ok {
            cmd := ProofForge.Cli.Command.check,
            targetId? := state.target?,
            fixture? := state.fixture?,
            format? := state.format?,
            reportFormat? := state.reportFormat?,
            input? := state.input?.map FilePath.mk,
            root? := state.root?.map FilePath.mk,
            moduleName? := state.module?.map ProofForge.Cli.parseModuleName,
            fromNewSurface := true
            : ProofForge.Cli.CliOptions }
        | Except.error msg => Except.error msg
      | "metadata" :: rest =>
        match ProofForge.Cli.parseNewOptions rest {} with
        | Except.ok state =>
          Except.ok {
            cmd := ProofForge.Cli.Command.metadata,
            fixture? := state.fixture?,
            output? := state.out?.map FilePath.mk,
            root? := state.root?.map FilePath.mk,
            fromNewSurface := true
            : ProofForge.Cli.CliOptions }
        | Except.error msg => Except.error msg
      | _ => ProofForge.Cli.parseArgs args {}
    match parseResult with
    | Except.ok opts => do
        match opts.cmd with
        | ProofForge.Cli.Command.listTargets =>
          IO.println (String.intercalate "\n" ProofForge.Target.knownIds.toList)
          return 0
        | ProofForge.Cli.Command.listFixtures =>
          IO.println (String.intercalate "\n" ProofForge.Cli.Fixture.ids.toList)
          return 0
        | ProofForge.Cli.Command.check =>
          ProofForge.Cli.checkCommand opts
        | ProofForge.Cli.Command.metadata =>
          ProofForge.Cli.Metadata.metadataCommandFromCliOptions opts
        | _ =>
          if !opts.fromNewSurface then
            if let some note := opts.mode.deprecationNote then
              IO.eprintln note
          if opts.evmChainProfile?.isSome then
            discard <| ProofForge.Cli.resolveEvmChainProfile? opts.evmChainProfile?
          ProofForge.Cli.compileFile opts
    | Except.error msg =>
        IO.eprintln msg
        return 1
