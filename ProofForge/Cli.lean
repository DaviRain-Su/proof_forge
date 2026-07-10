import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.ConstructorInit
import ProofForge.Backend.Psy.IR
import ProofForge.Contract.Client
import ProofForge.Contract.Spec.Json
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
import ProofForge.Cli.SourcegenCommands
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.SolanaCommands
import ProofForge.Cli.FileUtil
import ProofForge.Cli.PsyArtifacts
import ProofForge.Cli.EmitWatArtifacts
import ProofForge.Cli.WasmNearCommands
import ProofForge.Cli.IrJson
import ProofForge.Cli.EvmFixtures
import ProofForge.Cli.LearnArtifacts
import ProofForge.Cli.TargetJson
import ProofForge.Cli.Usage
import ProofForge.Cli.Options
import ProofForge.Cli.TargetDriver
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
   encodeConstructorValues constructorSchemaHasDynamic validateCanonicalAddressWords
   validateConstructorSchemaAndArgs)
export ProofForge.Cli.EmitMode (EmitMode)

def emitWatFixtureModule? (fixtureId : String) : Option ProofForge.IR.Module :=
  ProofForge.Cli.Check.emitWatFixtureModule? fixtureId

def cliVersion : String :=
  "0.1.0-beta.1"

def readFileTrim (path : String) : IO String := do
  let s ← IO.FS.readFile (FilePath.mk path)
  return s.trimAscii.toString

def gitShortSha? : IO (Option String) := do
  try
    let out ← IO.Process.output { cmd := "git", args := #["rev-parse", "--short", "HEAD"] }
    if out.exitCode == 0 then
      return some out.stdout.trimAscii.toString
    else
      return none
  catch _ =>
    return none

def printVersion : IO UInt32 := do
  let toolchain ← try readFileTrim "lean-toolchain" catch _ => pure "unknown"
  let sha ← gitShortSha?
  IO.println s!"proof-forge {cliVersion}"
  IO.println s!"Lean toolchain: {toolchain}"
  match sha with
  | some s => IO.println s!"git sha: {s}"
  | none => IO.println "git sha: unknown"
  return 0

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
  | .contractSourceSolanaElf => compileContractSourceSolanaElf opts
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
  | .counterIrDpnJson => compileCounterIrDpnJson opts
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
  | .solanaMemoCpiSbpf => compileSolanaMemoCpiSbpf opts
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
  | .solanaMemoCpiElf => compileSolanaMemoCpiElf opts
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
  | .counterIrAleo => compileCounterIrAleo opts
  | .pureMathIrLeo => compilePureMathIrLeo opts
  | .counterIrCosmWasm => compileCounterIrCosmWasm opts
  | .counterIrAptos => compileCounterIrAptos opts
  | .counterIrSui => compileCounterIrSui opts
  | .counterIrQuint => compileCounterIrQuint opts
  | .valueVaultIrQuint => compileValueVaultIrQuint opts
  | .irQuint => compileIrQuint opts
  | .irQuintScenario => compileIrQuintScenario opts

end ProofForge.Cli

def wantsHelp (args : List String) : Bool :=
  args.any (fun a => a == "--help" || a == "-h")

unsafe def dispatch (args : List String) : IO UInt32 := do
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
        | "--list-targets" :: rest =>
            let wantsJson := rest.any (fun a => a == "--json")
            Except.ok {
              cmd := ProofForge.Cli.Command.listTargets
              reportFormat? := if wantsJson then some "json" else none }
        | "--list-fixtures" :: _ => Except.ok { cmd := ProofForge.Cli.Command.listFixtures }
        | "build" :: rest =>
            match ProofForge.Cli.parseNewOptions rest {} with
            | Except.ok state =>
                match ProofForge.Cli.newCommandArgsToLegacy state "build" with
                | Except.ok legacyArgs =>
                    match ProofForge.Cli.parseArgs legacyArgs {} with
                    | Except.ok opts => Except.ok { opts with
                        cmd := ProofForge.Cli.Command.build,
                        format? := state.format?,
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
                        format? := state.format?,
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
              if opts.reportFormat? == some "json" then
                IO.println ProofForge.Cli.listTargetsJson
              else
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

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | ["--version"] | "--version" :: _ =>
      ProofForge.Cli.printVersion
  | ["--help"] | "--help" :: _ | ["-h"] | "-h" :: _ =>
      IO.println ProofForge.Cli.usage
      return 0
  | [] =>
      IO.println ProofForge.Cli.usage
      return 0
  | "build" :: rest =>
      if wantsHelp rest then
        IO.println ProofForge.Cli.buildUsage
        return 0
      else
        dispatch args
  | "emit" :: rest =>
      if wantsHelp rest then
        IO.println ProofForge.Cli.emitUsage
        return 0
      else
        dispatch args
  | "check" :: rest =>
      if wantsHelp rest then
        IO.println ProofForge.Cli.checkUsage
        return 0
      else
        dispatch args
  | _ =>
      dispatch args
