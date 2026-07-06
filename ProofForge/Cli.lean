import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.ConstructorInit
import ProofForge.Backend.Psy.IR
import ProofForge.Backend.Psy.Metadata
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Client
import ProofForge.Contract.Client
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Learn
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec.Json
import ProofForge.Contract.Token.Evm
import ProofForge.Contract.Token.EvmSpec
import ProofForge.Contract.Token.EvmWrap
import ProofForge.Contract.Token.Learn
import ProofForge.Backend.WasmNear
import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Backend.Aleo.IR
import ProofForge.Backend.CosmWasm.EmitWat
import ProofForge.Backend.Move.Aptos
import ProofForge.Backend.Move.Sui
import ProofForge.Backend.Quint.Scenario
import ProofForge.Backend.Quint.Lower
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.Fixture
import ProofForge.Cli.Scaffold
import ProofForge.Cli.Deploy
import ProofForge.Cli.Check
import ProofForge.Cli.Metadata
import ProofForge.Cli.Quint
import ProofForge.Cli.Evm
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
import ProofForge.Solana.Examples.Vault
import ProofForge.Solana.Examples.SystemCpi
import ProofForge.Solana.Examples.SystemCreateAccountCpi
import ProofForge.Solana.Examples.SplTokenTransferCheckedCpi
import ProofForge.Solana.Examples.SplTokenOpsCpi
import ProofForge.Solana.Examples.SplTokenCloseAccountCpi
import ProofForge.Solana.Examples.SplTokenAuthorityCpi
import ProofForge.Solana.Examples.AssociatedTokenCpi
import ProofForge.Solana.Examples.SplToken2022Cpi
import ProofForge.Solana.Examples.SplToken2022PausableCpi
import ProofForge.Solana.Examples.SplToken2022TransferHook
import ProofForge.Solana.Examples.LogEvent
import ProofForge.Solana.Examples.Clock
import ProofForge.Solana.Examples.Rent
import ProofForge.Solana.Examples.EpochSchedule
import ProofForge.Solana.Examples.EpochRewards
import ProofForge.Solana.Examples.LastRestartSlot
import ProofForge.Solana.Examples.Memory
import ProofForge.Solana.Examples.Crypto
import ProofForge.Solana.Examples.ReturnDataCompute
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.HexUtil
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.EmitMode
import ProofForge.Cli.Process
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.Artifact
import ProofForge.Cli.FileUtil
import ProofForge.Cli.EmitWatArtifacts
import ProofForge.Cli.IrJson
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.EvmArtifacts
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

/-! ### Metadata command (plan-driven artifact metadata JSON) -/

/-- Map a fixture id to its portable IR module for plan-driven metadata
    export. Covers all Psy-compatible fixtures. -/
def metadataFixtureModule? (fixtureId : String) : Option ProofForge.IR.Module :=
  match fixtureId with
  | "counter" => some ProofForge.IR.Examples.Counter.module
  | "map" => some ProofForge.IR.Examples.MapProbe.module
  | "event" => some ProofForge.IR.Examples.EventProbe.module
  | "context" => some ProofForge.IR.Examples.ContextProbe.module
  | "crosscall" => some ProofForge.IR.Examples.CrosscallProbe.psyModule
  | "struct" => some ProofForge.IR.Examples.StructProbe.module
  | "struct-array" => some ProofForge.IR.Examples.StructArrayProbe.module
  | "array" => some ProofForge.IR.Examples.ArrayProbe.module
  | "assert" => some ProofForge.IR.Examples.AssertProbe.module
  | "hash" => some ProofForge.IR.Examples.HashProbe.module
  | "hash-storage" => some ProofForge.IR.Examples.HashStorageProbe.module
  | "loop" => some ProofForge.IR.Examples.LoopProbe.module
  | "arithmetic" => some ProofForge.IR.Examples.ArithmeticProbe.module
  | "bitwise" => some ProofForge.IR.Examples.BitwiseProbe.module
  | "conditional" => some ProofForge.IR.Examples.ConditionalProbe.module
  | "else-if" => some ProofForge.IR.Examples.ElseIfProbe.module
  | "expression-predicate" => some ProofForge.IR.Examples.ExpressionPredicateProbe.module
  | "generic-entrypoint" => some ProofForge.IR.Examples.GenericEntrypointProbe.module
  | "abi-aggregate" => some ProofForge.IR.Examples.AbiAggregateProbe.module
  | "nested-aggregate" => some ProofForge.IR.Examples.NestedAggregateProbe.module
  | "storage-nested-aggregate" => some ProofForge.IR.Examples.StorageNestedAggregateProbe.module
  | "u32-arithmetic" => some ProofForge.IR.Examples.U32ArithmeticProbe.module
  | "u32-hash-packing" => some ProofForge.IR.Examples.U32HashPackingProbe.module
  | "u32-storage-array" => some ProofForge.IR.Examples.U32StorageArrayProbe.module
  | "u32-storage-scalar" => some ProofForge.IR.Examples.U32StorageScalarProbe.module
  | "bool-storage-array" => some ProofForge.IR.Examples.BoolStorageArrayProbe.module
  | "bool-storage-scalar" => some ProofForge.IR.Examples.BoolStorageScalarProbe.module
  | _ => none

def metadataQuoteString (s : String) : String :=
  "\"" ++ (s.toList.map (fun c => match c with
    | '\\' => "\\\\"
    | '"' => "\\\""
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | c => c.toString)).foldl (· ++ ·) "" ++ "\""

def metadataJsonArray (items : List String) : String :=
  "[" ++ ", ".intercalate items ++ "]"

def metadataJsonObject (fields : List (String × String)) : String :=
  "{" ++ ", ".intercalate (fields.map (fun (k, v) => metadataQuoteString k ++ ": " ++ v)) ++ "}"

def metadataRenderAbiParam (p : ProofForge.Backend.Psy.Metadata.AbiParamDescriptor) : String :=
  metadataJsonObject [("name", metadataQuoteString p.name), ("type", metadataQuoteString p.type)]

def metadataRenderAbiEntrypoint (e : ProofForge.Backend.Psy.Metadata.AbiEntrypointDescriptor) : String :=
  metadataJsonObject [
    ("name", metadataQuoteString e.name),
    ("params", metadataJsonArray (e.params.toList.map metadataRenderAbiParam)),
    ("returnType", metadataQuoteString e.returnType)
  ]

def metadataRenderAbiEventField (f : ProofForge.Backend.Psy.Metadata.AbiEventFieldDescriptor) : String :=
  metadataJsonObject [("name", metadataQuoteString f.name), ("type", metadataQuoteString f.type)]

def metadataRenderAbiEvent (e : ProofForge.Backend.Psy.Metadata.AbiEventDescriptor) : String :=
  metadataJsonObject [
    ("name", metadataQuoteString e.name),
    ("fields", metadataJsonArray (e.fields.toList.map metadataRenderAbiEventField))
  ]

def metadataRenderContextOp (o : ProofForge.Backend.Psy.Metadata.ContextOpDescriptor) : String :=
  metadataJsonObject [("name", metadataQuoteString o.name)]

def metadataRenderCrosscall (c : ProofForge.Backend.Psy.Metadata.CrosscallDescriptor) : String :=
  metadataJsonObject [("targetContractId", metadataQuoteString c.targetContractId)]

def metadataRenderArtifactMetadata (m : ProofForge.Backend.Psy.Metadata.ArtifactMetadata) : String :=
  metadataJsonObject [
    ("targetId", metadataQuoteString m.targetId),
    ("moduleName", metadataQuoteString m.moduleName),
    ("entrypoints", metadataJsonArray (m.entrypoints.toList.map metadataRenderAbiEntrypoint)),
    ("events", metadataJsonArray (m.events.toList.map metadataRenderAbiEvent)),
    ("contextOps", metadataJsonArray (m.contextOps.toList.map metadataRenderContextOp)),
    ("crosscalls", metadataJsonArray (m.crosscalls.toList.map metadataRenderCrosscall)),
    ("capabilities", metadataJsonArray (m.capabilities.toList.map metadataQuoteString))
  ]

/-- Run the `proof-forge metadata` command: build plan-driven artifact
    metadata from a fixture and print it as JSON to stdout or --output. -/
def metadataCommand (opts : CliOptions) : IO UInt32 := do
  let fixtureId ← match opts.fixture? with
    | some f => pure f
    | none => throw <| IO.userError "metadata requires --fixture <id>"
  let module ← match metadataFixtureModule? fixtureId with
    | some m => pure m
    | none => throw <| IO.userError s!"metadata: unknown fixture '{fixtureId}'"
  let artifactMeta ← match ProofForge.Backend.Psy.Metadata.buildPlanArtifactMetadata module with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"metadata: failed to build plan: {e.message}"
  let json := metadataRenderArtifactMetadata artifactMeta
  match opts.output? with
  | some path =>
      if let some parent := path.parent then
        IO.FS.createDirAll parent
      IO.FS.writeFile path (json ++ "\n")
      IO.eprintln s!"metadata: wrote {path}"
  | none =>
      IO.println json
  pure 0

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

def compileCounterIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/Counter.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.Counter.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileErrorRefIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ErrorRefProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderCounterIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.Counter.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileCounterIrTs (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ts/Counter.ts")
  match ProofForge.Compiler.TS.Emit.emitModule ProofForge.IR.Examples.Counter.module with
  | .ok tsModule =>
    let source := ProofForge.Compiler.TS.Printer.render tsModule
    writeTextFile output source
    IO.println s!"wrote {output}"
    return 0
  | .error msg =>
    IO.eprintln s!"compileCounterIrTs: {msg}"
    return 1

def compileCounterIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/Counter.yul")
  let yul ← renderCounterIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/Counter.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "Counter" "ProofForge.IR.Examples.Counter" ProofForge.IR.Examples.Counter.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def renderErrorRefIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileErrorRefIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ErrorRefProbe.yul")
  let yul ← renderErrorRefIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ErrorRefProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module
  let (_, _, specArtifact, clientArtifact) ←
    writeEvmContractSdkClientArtifacts spec output "ErrorRefProbe"
  writeEvmIrArtifactMetadata opts "ErrorRefProbe" "ProofForge.IR.Examples.ErrorRefProbe"
    ProofForge.IR.Examples.ErrorRefProbe.module yulOutput output #[
    ("contractSpec", specArtifact),
    ("client", clientArtifact)
  ]
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileValueVaultIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ValueVault.yul")
  let module ← hydrateEvmSelectors opts.cast ProofForge.Contract.Examples.ValueVault.module
  match ProofForge.Cli.Evm.renderYul module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderValueVaultIrYul (opts : CliOptions) : IO (String × ProofForge.IR.Module) := do
  let module ← hydrateEvmSelectors opts.cast ProofForge.Contract.Examples.ValueVault.module
  match ProofForge.Cli.Evm.renderYul module with
  | .ok yul => return (yul, module)
  | .error err => throw <| IO.userError err.render

def compileValueVaultIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ValueVault.yul")
  let (yul, module) ← renderValueVaultIrYul opts
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ValueVault.bin")
  writeTextFile output (bytecode ++ "\n")
  let spec := ProofForge.Contract.ContractSpec.fromIR module
  writeEvmContractSdkArtifactMetadata opts "ValueVault" "ProofForge.Contract.Examples.ValueVault"
    spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def learnInput (opts : CliOptions) (modeName : String) : IO FilePath := do
  match opts.input? with
  | some input => pure input
  | none => throw <| IO.userError s!"{modeName} requires an input .learn file"

def parseLearnInput (opts : CliOptions) (modeName : String) :
    IO (FilePath × ProofForge.Contract.ContractSpec) := do
  let input ← learnInput opts modeName
  match (← ProofForge.Contract.Learn.parseAndLowerFile input) with
  | .ok spec => pure (input, spec)
  | .error err => throw <| IO.userError s!"{input}: {err}"

def parseLearnTokenInput (opts : CliOptions) (modeName : String) :
    IO (FilePath × ProofForge.Contract.Token.Learn.TokenDecl) := do
  let input ← learnInput opts modeName
  match (← ProofForge.Contract.Token.Learn.parseFile input) with
  | .ok decl => pure (input, decl)
  | .error err => throw <| IO.userError s!"{input}: {err}"

def learnFixtureName (input : FilePath) : String :=
  input.fileName.getD input.toString

def learnSourceModuleName (input : FilePath) (spec : ProofForge.Contract.ContractSpec) : String :=
  s!"{spec.name} ({input})"

def defaultLearnOutput (subdir extension : String) (spec : ProofForge.Contract.ContractSpec) :
    FilePath :=
  FilePath.mk s!"build/{subdir}/{spec.name}.{extension}"

def defaultLearnTokenPlanOutput (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (profile : ProofForge.Target.TargetProfile) : FilePath :=
  FilePath.mk s!"build/learn/token/{decl.id}.{profile.id}.token-plan.json"

def defaultLearnTokenEvmYulOutput (decl : ProofForge.Contract.Token.Learn.TokenDecl) :
    FilePath :=
  FilePath.mk s!"build/learn/token/{decl.id}.erc20.yul"

def defaultLearnTokenEvmBytecodeOutput (decl : ProofForge.Contract.Token.Learn.TokenDecl) :
    FilePath :=
  FilePath.mk s!"build/learn/token/{decl.id}.erc20.bin"

def defaultLearnTokenArtifactOutput (bytecodeOutput : FilePath) : FilePath :=
  let fileName := FilePath.mk "proof-forge-token-artifact.json"
  match bytecodeOutput.parent with
  | some parent => parent / fileName
  | none => fileName

def targetProfileForMode (opts : CliOptions) (modeName : String) :
    IO ProofForge.Target.TargetProfile := do
  let some targetId := opts.targetId?
    | throw <| IO.userError s!"{modeName} requires --target <target-id>"
  match ProofForge.Target.find? targetId with
  | some profile => pure profile
  | none =>
      let known := String.intercalate ", " ProofForge.Target.knownIds.toList
      throw <| IO.userError s!"unknown {modeName} target `{targetId}`; known targets: {known}"

def learnTargetProfile (opts : CliOptions) : IO ProofForge.Target.TargetProfile :=
  targetProfileForMode opts "--learn"

def learnTokenTargetProfile (opts : CliOptions) : IO ProofForge.Target.TargetProfile :=
  targetProfileForMode opts "--learn-token"

def tokenFeatureIdsJson (spec : ProofForge.Contract.Token.TokenSpec) : String :=
  jsonStringArray (spec.features.map fun feature => feature.id)

def tokenSpecJson (decl : ProofForge.Contract.Token.Learn.TokenDecl) : String :=
  jsonObject #[
    ("id", jsonString decl.id),
    ("name", jsonString decl.spec.name),
    ("symbol", jsonString decl.spec.symbol),
    ("decimals", toString decl.spec.decimals),
    ("initialSupply", jsonNatOption decl.spec.initialSupply?),
    ("features", tokenFeatureIdsJson decl.spec)
  ]

def tokenSolanaAccountJson
    (account : ProofForge.Contract.Token.SolanaTokenAccountPlan) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("role", jsonString account.role),
    ("ownerProgram", jsonStringOption account.ownerProgram?),
    ("signer", jsonBool account.signer),
    ("writable", jsonBool account.writable),
    ("derivation", jsonStringOption account.derivation?)
  ]

def tokenSolanaInstructionParamJson
    (param : ProofForge.Contract.Token.SolanaTokenInstructionParam) : String :=
  jsonObject #[
    ("name", jsonString param.name),
    ("type", jsonString param.type),
    ("source", jsonString param.source)
  ]

def tokenSolanaInstructionJson
    (instruction : ProofForge.Contract.Token.SolanaTokenInstructionPlan) : String :=
  jsonObject #[
    ("order", toString instruction.order),
    ("name", jsonString instruction.name),
    ("operation", jsonString instruction.operation),
    ("programId", jsonString instruction.programId),
    ("accounts", jsonStringArray instruction.accounts),
    ("params", jsonArray (instruction.params.map tokenSolanaInstructionParamJson)),
    ("feature", jsonStringOption instruction.feature?),
    ("token2022Only", jsonBool instruction.token2022Only)
  ]

def tokenSolanaExtensionJson
    (extension : ProofForge.Contract.Token.SolanaTokenExtensionPlan) : String :=
  jsonObject #[
    ("feature", jsonString extension.feature),
    ("extension", jsonString extension.extension),
    ("scope", jsonString extension.scope),
    ("initInstruction", jsonString extension.initInstruction),
    ("requiresConfig", jsonBool extension.requiresConfig),
    ("notes", jsonStringArray extension.notes)
  ]

def tokenSolanaAuthorityChangeJson
    (change : ProofForge.Contract.Token.SolanaTokenAuthorityChangePlan) : String :=
  jsonObject #[
    ("name", jsonString change.name),
    ("authorityType", jsonString change.authorityType),
    ("currentAuthority", jsonString change.currentAuthority),
    ("newAuthority", jsonString change.newAuthority),
    ("operation", jsonString change.operation),
    ("reason", jsonString change.reason)
  ]

def tokenSolanaReferenceJson
    (reference : ProofForge.Contract.Token.SolanaTokenReference) : String :=
  jsonObject #[
    ("label", jsonString reference.label),
    ("url", jsonString reference.url)
  ]

def tokenSolanaDeploymentPlanJson
    (deployment : ProofForge.Contract.Token.SolanaTokenDeploymentPlan) : String :=
  jsonObject #[
    ("standard", jsonString deployment.standard.id),
    ("programs", jsonObject #[
      ("token", jsonString deployment.tokenProgramId),
      ("associatedToken", jsonString deployment.associatedTokenProgramId),
      ("system", jsonString deployment.systemProgramId),
      ("rentSysvar", jsonString deployment.rentSysvarId)
    ]),
    ("accounts", jsonArray (deployment.accounts.map tokenSolanaAccountJson)),
    ("instructions", jsonArray (deployment.instructions.map tokenSolanaInstructionJson)),
    ("extensions", jsonArray (deployment.extensions.map tokenSolanaExtensionJson)),
    ("authorityChanges", jsonArray (deployment.authorityChanges.map tokenSolanaAuthorityChangeJson)),
    ("references", jsonArray (deployment.references.map tokenSolanaReferenceJson))
  ]

def tokenPlanJson (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (profile : ProofForge.Target.TargetProfile)
    (plan : ProofForge.Contract.Token.TokenPlan)
    (sourceArtifact : String)
    (solanaDeployment? : Option ProofForge.Contract.Token.SolanaTokenDeploymentPlan := none) : String :=
  jsonObject #[
    ("format", jsonString "proof-forge-token-plan-v0"),
    ("sourceKind", jsonString "learn-token-source"),
    ("token", tokenSpecJson decl),
    ("target", jsonString profile.id),
    ("targetFamily", jsonString profile.family.id),
    ("standard", jsonString plan.standard.id),
    ("artifactKind", jsonString plan.artifactKind.id),
    ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
    ("operations", jsonStringArray plan.operations),
    ("notes", jsonStringArray plan.notes),
    ("solana", match solanaDeployment? with
      | some deployment => tokenSolanaDeploymentPlanJson deployment
      | none => "null"),
    ("artifacts", jsonObject #[
      ("source", sourceArtifact)
    ]),
    ("validation", jsonObject #[
      ("learnTokenParsing", jsonString "passed"),
      ("targetRouting", jsonString "passed"),
      ("planGeneration", jsonString "passed")
    ])
  ]

def tokenEntrypointReturnsAbi
    (module : ProofForge.IR.Module)
    (entrypoint : ProofForge.IR.Entrypoint) : Except String String :=
  match entrypoint.returns with
  | .unit => .ok "void"
  | _ =>
      entrypointAbiType module s!"entrypoint `{entrypoint.name}` return" entrypoint.returns

def tokenEvmEntrypointsJson (module : ProofForge.IR.Module) : Except String String := do
  let mut entries := #[]
  for entrypoint in module.entrypoints do
    let signature ← entrypointSoliditySignature module entrypoint
    let selector :=
      match entrypoint.selector? with
      | some value => value
      | none => ""
    let returnsAbi ← tokenEntrypointReturnsAbi module entrypoint
    entries := entries.push <| jsonObject #[
      ("name", jsonString entrypoint.name),
      ("selector", jsonString selector),
      ("signature", jsonString signature),
      ("returns", jsonString returnsAbi)
    ]
  pure (jsonArray entries)

def tokenEvmEventsJson (events : Array EventAbi) : String :=
  jsonArray (events.map fun event => jsonObject #[
    ("name", jsonString event.name),
    ("topic0", jsonString event.topic0),
    ("signature", jsonString event.signature)
  ])

def tokenEvmArtifactJson (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (profile : ProofForge.Target.TargetProfile)
    (plan : ProofForge.Contract.Token.TokenPlan)
    (sourceArtifact yulArtifact bytecodeArtifact entrypointsJson eventsJson : String) : String :=
  jsonObject #[
    ("format", jsonString "proof-forge-token-artifact-v0"),
    ("sourceKind", jsonString "learn-token-source"),
    ("token", tokenSpecJson decl),
    ("target", jsonString profile.id),
    ("targetFamily", jsonString profile.family.id),
    ("standard", jsonString plan.standard.id),
    ("artifactKind", jsonString plan.artifactKind.id),
    ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
    ("operations", jsonStringArray plan.operations),
    ("notes", jsonStringArray plan.notes),
    ("abi", jsonObject #[
      ("entrypoints", entrypointsJson),
      ("events", eventsJson)
    ]),
    ("artifacts", jsonObject #[
      ("source", sourceArtifact),
      ("yul", yulArtifact),
      ("bytecode", bytecodeArtifact)
    ]),
    ("validation", jsonObject #[
      ("learnTokenParsing", jsonString "passed"),
      ("targetRouting", jsonString "passed"),
      ("erc20IrLowering", jsonString "passed"),
      ("solcStrictAssembly", jsonString "passed")
    ])
  ]

def renderLearnEvmYul (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) :
    IO (String × ProofForge.IR.Module) := do
  let module ← hydrateEvmSelectors opts.cast spec.module
  match ProofForge.Cli.Evm.renderYul module with
  | .ok yul => return (yul, module)
  | .error err => throw <| IO.userError err.render

def renderContractSourceEvmYul (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) :
    IO (String × ProofForge.IR.Module) :=
  renderLearnEvmYul opts spec

unsafe def compileContractSourceEvmBytecode (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let opts ← match finalizeConstructorOptionsForSpec opts spec with
    | .ok opts => pure opts
    | .error msg => throw <| IO.userError msg
  let output := opts.output?.getD (input.withExtension "bin")
  let yulOutput := opts.yulOutput?.getD (defaultBytecodeYulOutput output)
  let (yul, module) ← renderContractSourceEvmYul opts spec
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  writeTextFile output (bytecode ++ "\n")
  writeEvmContractSdkArtifactMetadata opts (leanBaseName input) spec.name spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

unsafe def compileContractSourceYul (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let output := opts.output?.getD (defaultYulOutput input)
  let (yul, _module) ← renderContractSourceEvmYul opts spec
  writeTextFile output yul
  IO.println s!"wrote {output}"
  return 0

def compileLearnYul (opts : CliOptions) : IO UInt32 := do
  let (_input, spec) ← parseLearnInput opts "--learn-yul"
  let output := opts.output?.getD (defaultLearnOutput "learn/evm" "yul" spec)
  let (yul, _module) ← renderLearnEvmYul opts spec
  writeTextFile output yul
  IO.println s!"wrote {output}"
  return 0

def compileLearnBytecode (opts : CliOptions) : IO UInt32 := do
  let (input, spec) ← parseLearnInput opts "--learn-bytecode"
  let yulOutput := opts.yulOutput?.getD (defaultLearnOutput "learn/evm" "yul" spec)
  let (yul, module) ← renderLearnEvmYul opts spec
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (defaultLearnOutput "learn/evm" "bin" spec)
  writeTextFile output (bytecode ++ "\n")
  writeEvmLearnArtifactMetadata opts (learnFixtureName input)
    (learnSourceModuleName input spec) input module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAbiScalarIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AbiScalarProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AbiScalarProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAbiScalarIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AbiScalarProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAbiScalarIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AbiScalarProbe.yul")
  let yul ← renderAbiScalarIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AbiScalarProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AbiScalarProbe" "ProofForge.IR.Examples.AbiScalarProbe" ProofForge.IR.Examples.AbiScalarProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAssertIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AssertProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssertProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAssertIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssertProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAssertIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AssertProbe.yul")
  let yul ← renderAssertIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AssertProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AssertProbe" "ProofForge.IR.Examples.AssertProbe" ProofForge.IR.Examples.AssertProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAssignmentIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AssignmentProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssignmentProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAssignmentIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.AssignmentProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAssignmentIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AssignmentProbe.yul")
  let yul ← renderAssignmentIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AssignmentProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AssignmentProbe" "ProofForge.IR.Examples.AssignmentProbe" ProofForge.IR.Examples.AssignmentProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmAssignOpIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAssignOpProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmAssignOpIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAssignOpProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmAssignOpIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.yul")
  let yul ← renderEvmAssignOpIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmAssignOpProbe" "ProofForge.IR.Examples.EvmAssignOpProbe" ProofForge.IR.Examples.EvmAssignOpProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileConditionalIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ConditionalProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderConditionalIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileConditionalIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ConditionalProbe.yul")
  let yul ← renderConditionalIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ConditionalProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "ConditionalProbe" "ProofForge.IR.Examples.ConditionalProbe" ProofForge.IR.Examples.ConditionalProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileContextIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ContextProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmContextProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderContextIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmContextProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileContextIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ContextProbe.yul")
  let yul ← renderContextIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ContextProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "ContextProbe" "ProofForge.IR.Examples.EvmContextProbe" ProofForge.IR.Examples.EvmContextProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmEventIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EventProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EventProbe.evmModule with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmEventIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EventProbe.evmModule with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmEventIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EventProbe.yul")
  let yul ← renderEvmEventIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EventProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EventProbe" "ProofForge.IR.Examples.EventProbe.evmModule" ProofForge.IR.Examples.EventProbe.evmModule yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmCrosscallIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmCrosscallProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmCrosscallIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmCrosscallProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmCrosscallIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.yul")
  let yul ← renderEvmCrosscallIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmCrosscallProbe" "ProofForge.IR.Examples.EvmCrosscallProbe" ProofForge.IR.Examples.EvmCrosscallProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmExpressionIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmExpressionProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmExpressionProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmExpressionIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmExpressionProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmExpressionIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmExpressionProbe.yul")
  let yul ← renderEvmExpressionIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmExpressionProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmExpressionProbe" "ProofForge.IR.Examples.EvmExpressionProbe" ProofForge.IR.Examples.EvmExpressionProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmHashIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmHashProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmHashProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmHashIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmHashProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmHashIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmHashProbe.yul")
  let yul ← renderEvmHashIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmHashProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmHashProbe" "ProofForge.IR.Examples.EvmHashProbe" ProofForge.IR.Examples.EvmHashProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmLoopIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmLoopProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmLoopProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmLoopIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmLoopProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmLoopIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmLoopProbe.yul")
  let yul ← renderEvmLoopIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmLoopProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmLoopProbe" "ProofForge.IR.Examples.EvmLoopProbe" ProofForge.IR.Examples.EvmLoopProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmMapIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMapProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMapProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmMapIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMapProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmMapIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmMapProbe.yul")
  let yul ← renderEvmMapIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMapProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmMapProbe" "ProofForge.IR.Examples.EvmMapProbe" ProofForge.IR.Examples.EvmMapProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStorageArrayIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageArrayProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStorageArrayIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageArrayProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStorageArrayIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.yul")
  let yul ← renderEvmStorageArrayIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStorageArrayProbe" "ProofForge.IR.Examples.EvmStorageArrayProbe" ProofForge.IR.Examples.EvmStorageArrayProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStorageStructIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageStructProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStorageStructIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStorageStructProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStorageStructIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.yul")
  let yul ← renderEvmStorageStructIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStorageStructProbe" "ProofForge.IR.Examples.EvmStorageStructProbe" ProofForge.IR.Examples.EvmStorageStructProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmTypedMapIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedMapProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmTypedMapIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedMapProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmTypedMapIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.yul")
  let yul ← renderEvmTypedMapIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmTypedMapProbe" "ProofForge.IR.Examples.EvmTypedMapProbe" ProofForge.IR.Examples.EvmTypedMapProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmTypedStorageIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedStorageProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmTypedStorageIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmTypedStorageProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmTypedStorageIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.yul")
  let yul ← renderEvmTypedStorageIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmTypedStorageProbe" "ProofForge.IR.Examples.EvmTypedStorageProbe" ProofForge.IR.Examples.EvmTypedStorageProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmArrayValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmArrayValueIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmArrayValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.yul")
  let yul ← renderEvmArrayValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmArrayValueProbe" "ProofForge.IR.Examples.EvmArrayValueProbe" ProofForge.IR.Examples.EvmArrayValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStructArrayValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructArrayValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStructArrayValueIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructArrayValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStructArrayValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.yul")
  let yul ← renderEvmStructArrayValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStructArrayValueProbe" "ProofForge.IR.Examples.EvmStructArrayValueProbe" ProofForge.IR.Examples.EvmStructArrayValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStructValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructValueProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStructValueIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmStructValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStructValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStructValueProbe.yul")
  let yul ← renderEvmStructValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStructValueProbe" "ProofForge.IR.Examples.EvmStructValueProbe" ProofForge.IR.Examples.EvmStructValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmAbiAggregateIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAbiAggregateProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmAbiAggregateIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmAbiAggregateProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmAbiAggregateIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.yul")
  let yul ← renderEvmAbiAggregateIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmAbiAggregateProbe" "ProofForge.IR.Examples.EvmAbiAggregateProbe" ProofForge.IR.Examples.EvmAbiAggregateProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmDynamicAbiIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicAbiProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicAbiProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmDynamicAbiIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicAbiProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmDynamicAbiIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmDynamicAbiProbe.yul")
  let yul ← renderEvmDynamicAbiIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicAbiProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmDynamicAbiProbe" "ProofForge.IR.Examples.EvmDynamicAbiProbe" ProofForge.IR.Examples.EvmDynamicAbiProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmArrayAbiIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayAbiProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayAbiProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmArrayAbiIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmArrayAbiProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmArrayAbiIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmArrayAbiProbe.yul")
  let yul ← renderEvmArrayAbiIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayAbiProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmArrayAbiProbe" "ProofForge.IR.Examples.EvmArrayAbiProbe" ProofForge.IR.Examples.EvmArrayAbiProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmDynamicArrayIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicArrayProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicArrayProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmDynamicArrayIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmDynamicArrayProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmDynamicArrayIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmDynamicArrayProbe.yul")
  let yul ← renderEvmDynamicArrayIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmDynamicArrayProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmDynamicArrayProbe" "ProofForge.IR.Examples.EvmDynamicArrayProbe" ProofForge.IR.Examples.EvmDynamicArrayProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmMemoryArrayIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMemoryArrayProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMemoryArrayProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmMemoryArrayIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmMemoryArrayProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmMemoryArrayIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmMemoryArrayProbe.yul")
  let yul ← renderEvmMemoryArrayIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMemoryArrayProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmMemoryArrayProbe" "ProofForge.IR.Examples.EvmMemoryArrayProbe" ProofForge.IR.Examples.EvmMemoryArrayProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmPackedStorageIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmPackedStorageProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmPackedStorageProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmPackedStorageIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmPackedStorageProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmPackedStorageIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmPackedStorageProbe.yul")
  let yul ← renderEvmPackedStorageIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmPackedStorageProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmPackedStorageProbe" "ProofForge.IR.Examples.EvmPackedStorageProbe" ProofForge.IR.Examples.EvmPackedStorageProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmErrorsIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmErrorsProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmErrorsProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmErrorsIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmErrorsProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmErrorsIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmErrorsProbe.yul")
  let yul ← renderEvmErrorsIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmErrorsProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmErrorsProbe" "ProofForge.IR.Examples.EvmErrorsProbe" ProofForge.IR.Examples.EvmErrorsProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmFallbackIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmFallbackProbe.yul")
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmFallbackProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmFallbackIrYul : IO String := do
  match ProofForge.Cli.Evm.renderYul ProofForge.IR.Examples.EvmFallbackProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmFallbackIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmFallbackProbe.yul")
  let yul ← renderEvmFallbackIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmFallbackProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmFallbackProbe" "ProofForge.IR.Examples.EvmFallbackProbe" ProofForge.IR.Examples.EvmFallbackProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileCounterIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/Counter.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileEventIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/EventProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.EventProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileCrosscallIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/CrosscallProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.CrosscallProbe.psyModule with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileExpressionPredicateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ExpressionPredicateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ExpressionPredicateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileGenericEntrypointIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/GenericEntrypointProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.GenericEntrypointProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileArithmeticIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ArithmeticProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ArithmeticProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBitwiseIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BitwiseProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BitwiseProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBoolStorageArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BoolStorageArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BoolStorageArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBoolStorageScalarIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BoolStorageScalarProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BoolStorageScalarProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileConditionalIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ConditionalProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileElseIfIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ElseIfProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ElseIfProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileContextIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ContextProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ContextProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/HashProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.HashProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashStorageIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/HashStorageProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.HashStorageProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileMapIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/MapProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.MapProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileAssertIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/AssertProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.AssertProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileLoopIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/LoopProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.LoopProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStructIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StructProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StructProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStructArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StructArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StructArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileAbiAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/AbiAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.AbiAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileNestedAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/NestedAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.NestedAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStorageNestedAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StorageNestedAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StorageNestedAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32ArithmeticIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32ArithmeticProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32ArithmeticProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32HashPackingIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32HashPackingProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32HashPackingProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32StorageScalarIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32StorageScalarProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32StorageScalarProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32StorageArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32StorageArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32StorageArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render
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

/-- Write the Solana instruction manifest.toml alongside the emitted .s file.
Returns the path that was written. -/
def writeSbpfManifest (output : FilePath) (module : ProofForge.IR.Module) : IO FilePath := do
  let manifestOutput := match output.parent with
    | some parent => parent / "manifest.toml"
    | none => FilePath.mk "manifest.toml"
  let manifest := ProofForge.Backend.Solana.Manifest.renderManifest module
  IO.FS.writeFile manifestOutput (manifest ++ "\n")
  return manifestOutput

def writeSbpfManifestWithPlan (output : FilePath) (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO FilePath := do
  let manifestOutput := match output.parent with
    | some parent => parent / "manifest.toml"
    | none => FilePath.mk "manifest.toml"
  let manifest := ProofForge.Backend.Solana.Manifest.renderManifestWithPlan module plan
  IO.FS.writeFile manifestOutput (manifest ++ "\n")
  return manifestOutput

def writeSbpfIdlWithPlan (output : FilePath) (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO FilePath := do
  let idlOutput := match output.parent with
    | some parent => parent / ProofForge.Backend.Solana.Idl.idlPath
    | none => FilePath.mk ProofForge.Backend.Solana.Idl.idlPath
  let idl := ProofForge.Backend.Solana.Idl.renderWithPlan module plan
  IO.FS.writeFile idlOutput (idl ++ "\n")
  return idlOutput

def writeSbpfClientWithPlan (output : FilePath) (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO FilePath := do
  let clientOutput := match output.parent with
    | some parent => parent / ProofForge.Backend.Solana.Client.clientPath
    | none => FilePath.mk ProofForge.Backend.Solana.Client.clientPath
  let client := ProofForge.Backend.Solana.Client.renderWithPlan module plan
  IO.FS.writeFile clientOutput (client ++ "\n")
  return clientOutput

def packagePath (root : FilePath) (rel : String) : FilePath :=
  rel.splitOn "/" |>.foldl (init := root) fun acc part =>
    if part.isEmpty then acc else acc / part

def compileCounterIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/Counter.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifest output ProofForge.IR.Examples.Counter.module
      IO.println s!"wrote {manifestOutput}"
      let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
      let plan ←
        match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
        | .ok plan => pure plan
        | .error err => throw <| IO.userError err.render
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "counter-ir-sbpf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "Counter"),
        ("sdkSchema", jsonString "proof-forge-sdk.json"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "control.conditional"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      if opts.fromNewSurface then
        let schemaDir := output.parent.getD (FilePath.mk ".")
        discard <| writeSdkSchemaFile
          ProofForge.Backend.Solana.SbpfAsm.targetId
          spec
          schemaDir
          #[
            ("artifactMetadata", metadataOutput),
            ("primary", output),
            ("manifest", manifestOutput),
            ("interface", idlOutput)
          ]
          #[("typescript", clientOutput)]
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileErrorRefIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/ErrorRefProbe.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderModule ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifest output ProofForge.IR.Examples.ErrorRefProbe.module
      IO.println s!"wrote {manifestOutput}"
      let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module
      let specOutput := match output.parent with
        | some parent => parent / "ErrorRefProbe.contract-spec.json"
        | none => FilePath.mk "ErrorRefProbe.contract-spec.json"
      writeTextFile specOutput (ProofForge.Contract.Spec.Json.render spec ++ "\n")
      IO.println s!"wrote {specOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "error-ref-ir-sbpf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "ErrorRefProbe"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "assertions.check"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileControlIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/ControlFlowAssertProbe.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderModule ProofForge.IR.Examples.ControlFlowAssertProbe.module with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifest output ProofForge.IR.Examples.ControlFlowAssertProbe.module
      IO.println s!"wrote {manifestOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "control-ir-sbpf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "ControlFlowAssertProbe"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "control.conditional", "assertions.check"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed"),
          ("molluskRuntime", jsonObject #[
            ("lifecycle", jsonString "pending"),
            ("guardedIncrementSuccess", jsonString "pending"),
            ("guardedIncrementRevert", jsonString "pending"),
            ("equalityGuardSuccess", jsonString "pending"),
            ("equalityGuardRevert", jsonString "pending")
          ])
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSdkSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/SolanaVault.s")
  let spec := ProofForge.Solana.Examples.Vault.spec
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "solana-sdk-vault-sbpf"),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending"),
          ("cpiLowering", jsonString "helper-emitted"),
          ("pdaLowering", jsonString "helper-emitted")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileValueVaultIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/ValueVault.s")
  let spec := ProofForge.Contract.Examples.ValueVault.spec
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "value-vault-ir-sbpf"),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileLearnSbpf (opts : CliOptions) : IO UInt32 := do
  let (input, spec) ← parseLearnInput opts "--learn-sbpf"
  let output := opts.output?.getD (defaultLearnOutput "learn/solana" "s" spec)
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let asmArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let learnArtifact ← artifactEntryJson input
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString (learnFixtureName input)),
        ("sourceKind", jsonString "learn-source"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString (learnSourceModuleName input spec)),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("source", learnArtifact),
          ("sbpfAsm", asmArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("learnLowering", jsonString "passed"),
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

unsafe def compileContractSourceSbpf (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let output := opts.output?.getD (siblingPath input s!".{leanBaseName input}.s")
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let sourceArtifactEntry ← artifactEntryJson input
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString (leanBaseName input)),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("sdkSchema", jsonString "proof-forge-sdk.json"),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("source", sourceArtifactEntry),
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("contractSourceLowering", jsonString "passed"),
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      if opts.fromNewSurface then
        let schemaDir := output.parent.getD (FilePath.mk ".")
        discard <| writeSdkSchemaFile
          ProofForge.Backend.Solana.SbpfAsm.targetId
          spec
          schemaDir
          #[
            ("artifactMetadata", metadataOutput),
            ("primary", output),
            ("manifest", manifestOutput),
            ("interface", idlOutput)
          ]
          #[("typescript", clientOutput)]
      return 0
  | .error err =>
      throw <| IO.userError err.render

unsafe def compileContractSourceEmitWat (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let fixtureSlug := spec.name.toLower
  let outputDir ← match opts.output? with
    | some out =>
        if out.extension == "wat" then
          pure <| match out.parent with | some parent => parent | none => FilePath.mk "."
        else
          pure out
    | none =>
        throw <| IO.userError "contract source EmitWat build requires -o output directory (or .wat path)"
  let opts' := { opts with
    output? := some outputDir
    targetId? := opts.targetId? <|> some ProofForge.Target.wasmNear.id
  }
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.wasmNear spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  compileEmitWatWithPlan opts' fixtureSlug spec.module plan

def compileLearnTarget (opts : CliOptions) : IO UInt32 := do
  let profile ← learnTargetProfile opts
  if profile.id == ProofForge.Target.evm.id then
    compileLearnBytecode opts
  else if profile.id == ProofForge.Target.solanaSbpfAsm.id then
    compileLearnSbpf opts
  else
    throw <| IO.userError
      s!"Learn target emission for `{profile.id}` is not implemented yet; currently implemented targets: evm, solana-sbpf-asm"

def compileLearnTokenEvm (opts : CliOptions)
    (profile : ProofForge.Target.TargetProfile)
    (input : FilePath)
    (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (plan : ProofForge.Contract.Token.TokenPlan) : IO UInt32 := do
  let spec := ProofForge.Contract.Token.EvmSpec.specFor decl.spec
  let module ← hydrateEvmSelectors opts.cast spec.module
  let runtimeObject ←
    match ProofForge.Backend.Evm.IR.lowerModule module with
    | .ok obj => pure obj
    | .error err => throw <| IO.userError err.render
  let runtimeName := decl.id ++ "Runtime"
  let yul := ProofForge.Contract.Token.EvmWrap.wrapRuntimeObject decl.id runtimeName runtimeObject decl.spec
  let yulOutput := opts.yulOutput?.getD (defaultLearnTokenEvmYulOutput decl)
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (defaultLearnTokenEvmBytecodeOutput decl)
  writeTextFile output (bytecode ++ "\n")
  let metadataOutput := opts.artifactOutput?.getD (defaultLearnTokenArtifactOutput output)
  let sourceArtifact ← artifactEntryJson input
  let yulArtifact ← artifactEntryJson yulOutput
  let bytecodeArtifact ← artifactEntryJson output
  let events ← eventAbisForModule opts.cast module
  let entrypointsJson ← liftExceptString (tokenEvmEntrypointsJson module)
  let eventsJson := tokenEvmEventsJson events
  writeTextFile metadataOutput
    (tokenEvmArtifactJson decl profile plan sourceArtifact yulArtifact bytecodeArtifact entrypointsJson
      eventsJson ++ "\n")
  IO.println s!"wrote {yulOutput}"
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  IO.println s!"wrote {metadataOutput}"
  return 0

def compileLearnTokenPlan (opts : CliOptions)
    (profile : ProofForge.Target.TargetProfile)
    (input : FilePath)
    (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (plan : ProofForge.Contract.Token.TokenPlan) : IO UInt32 := do
  let output := opts.output?.getD (defaultLearnTokenPlanOutput decl profile)
  let sourceArtifact ← artifactEntryJson input
  let solanaDeployment? ←
    if profile.family == ProofForge.Target.TargetFamily.solana then
      match ProofForge.Contract.Token.solanaTokenDeploymentPlan decl.spec with
      | .ok deployment => pure (some deployment)
      | .error err => throw <| IO.userError err
    else
      pure none
  writeTextFile output (tokenPlanJson decl profile plan sourceArtifact solanaDeployment? ++ "\n")
  IO.println s!"wrote {output}"
  return 0

def compileLearnTokenTarget (opts : CliOptions) : IO UInt32 := do
  let profile ← learnTokenTargetProfile opts
  let (input, decl) ← parseLearnTokenInput opts "--learn-token"
  let plan ←
    match ProofForge.Contract.Token.planForTarget profile decl.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  if profile.id == ProofForge.Target.evm.id then
    compileLearnTokenEvm opts profile input decl plan
  else
    compileLearnTokenPlan opts profile input decl plan

def compileSolanaElf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/Counter.so")
  let projectName := match output.fileName with
    | some n => (n.splitOn ".").headD "counter"
    | none => "counter"
  let projectDir := match output.parent with
    | some parent => parent / s!"{projectName}-sbpf-project"
    | none => FilePath.mk s!"{projectName}-sbpf-project"

  match ProofForge.Backend.Solana.Package.renderPackage projectName ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      for file in pkg.files do
        let path := packagePath projectDir file.path
        writeTextFile path file.contents
        IO.println s!"wrote {path}"

      let asmSrc := packagePath projectDir pkg.asmPath
      let manifestOutput := packagePath projectDir pkg.manifestPath

      -- Invoke the sbpf toolchain to assemble and link the ELF.
      let _ ← runProcess "sbpf" #["build", "--arch", opts.solanaSbpfArch] (cwd? := some projectDir)

      let builtElf := projectDir / "deploy" / s!"{projectName}.so"
      if ! (← builtElf.pathExists) then
        throw <| IO.userError s!"sbpf build did not produce {builtElf}"

      let elfBytes ← IO.FS.readBinFile builtElf
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      IO.FS.writeBinFile output elfBytes
      IO.println s!"wrote {output}"

      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson asmSrc
      let manifestArtifact ← artifactEntryJson manifestOutput
      let elfArtifact ← artifactEntryJson output
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "counter-elf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "Counter"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "control.conditional"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null"),
            ("arch", jsonString opts.solanaSbpfArch)
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaElf", elfArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "passed"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSpecElf (opts : CliOptions) (defaultOutput : FilePath)
    (fallbackProjectName fixture : String) (spec : ProofForge.Contract.ContractSpec) :
    IO UInt32 := do
  let output := opts.output?.getD defaultOutput
  let projectName := match output.fileName with
    | some n => (n.splitOn ".").headD fallbackProjectName
    | none => fallbackProjectName
  let projectDir := match output.parent with
    | some parent => parent / s!"{projectName}-sbpf-project"
    | none => FilePath.mk s!"{projectName}-sbpf-project"
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render

  match ProofForge.Backend.Solana.Package.renderPackageForSpec projectName spec with
  | .ok pkg =>
      for file in pkg.files do
        let path := packagePath projectDir file.path
        writeTextFile path file.contents
        IO.println s!"wrote {path}"

      let asmSrc := packagePath projectDir pkg.asmPath
      let manifestOutput := packagePath projectDir pkg.manifestPath
      let idlOutput := packagePath projectDir pkg.idlPath
      let clientOutput := packagePath projectDir pkg.clientPath
      let _ ← runProcess "sbpf" #["build", "--arch", opts.solanaSbpfArch] (cwd? := some projectDir)

      let builtElf := projectDir / "deploy" / s!"{projectName}.so"
      if ! (← builtElf.pathExists) then
        throw <| IO.userError s!"sbpf build did not produce {builtElf}"

      let elfBytes ← IO.FS.readBinFile builtElf
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      IO.FS.writeBinFile output elfBytes
      IO.println s!"wrote {output}"

      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson asmSrc
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let elfArtifact ← artifactEntryJson output
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString fixture),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null"),
            ("arch", jsonString opts.solanaSbpfArch)
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact),
          ("solanaElf", elfArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "passed"),
          ("liveCpi", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSpecSbpf (opts : CliOptions) (defaultOutput : FilePath)
    (fixture : String) (spec : ProofForge.Contract.ContractSpec) : IO UInt32 := do
  let output := opts.output?.getD defaultOutput
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString fixture),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending"),
          ("liveCpi", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSystemCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SystemCpi.s")
    "solana-system-cpi-sbpf"
    ProofForge.Solana.Examples.SystemCpi.spec

def compileSolanaSystemCreateAccountCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SystemCreateAccountCpi.s")
    "solana-system-create-account-cpi-sbpf"
    ProofForge.Solana.Examples.SystemCreateAccountCpi.spec

def compileSolanaSplTokenTransferCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenTransferCheckedCpi.s")
    "solana-spl-token-transfer-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenTransferCheckedCpi.spec

def compileSolanaSplTokenOpsCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenOpsCpi.s")
    "solana-spl-token-ops-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenOpsCpi.spec

def compileSolanaSplTokenCloseAccountCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenCloseAccountCpi.s")
    "solana-spl-token-close-account-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec

def compileSolanaSplTokenAuthorityCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenAuthorityCpi.s")
    "solana-spl-token-authority-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenAuthorityCpi.spec

def compileSolanaAssociatedTokenCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/AssociatedTokenCpi.s")
    "solana-associated-token-cpi-sbpf"
    ProofForge.Solana.Examples.AssociatedTokenCpi.spec

def compileSolanaSplToken2022CpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplToken2022Cpi.s")
    "solana-spl-token-2022-cpi-sbpf"
    ProofForge.Solana.Examples.SplToken2022Cpi.spec

def compileSolanaSplToken2022PausableCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplToken2022PausableCpi.s")
    "solana-spl-token-2022-pausable-cpi-sbpf"
    ProofForge.Solana.Examples.SplToken2022PausableCpi.spec

def compileSolanaSplToken2022TransferHookSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplToken2022TransferHook.s")
    "solana-spl-token-2022-transfer-hook-sbpf"
    ProofForge.Solana.Examples.SplToken2022TransferHook.spec

def compileValueVaultSolanaElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/ValueVault.so")
    "value-vault"
    "value-vault-solana-elf"
    ProofForge.Contract.Examples.ValueVault.spec

def compileSolanaSystemCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SystemCpi.so")
    "system-cpi"
    "solana-system-cpi-elf"
    ProofForge.Solana.Examples.SystemCpi.spec

def compileSolanaSystemCreateAccountCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SystemCreateAccountCpi.so")
    "system-create-account-cpi"
    "solana-system-create-account-cpi-elf"
    ProofForge.Solana.Examples.SystemCreateAccountCpi.spec

def compileSolanaSplTokenTransferCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenTransferCheckedCpi.so")
    "spl-token-transfer-cpi"
    "solana-spl-token-transfer-cpi-elf"
    ProofForge.Solana.Examples.SplTokenTransferCheckedCpi.spec

def compileSolanaSplTokenOpsCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenOpsCpi.so")
    "spl-token-ops-cpi"
    "solana-spl-token-ops-cpi-elf"
    ProofForge.Solana.Examples.SplTokenOpsCpi.spec

def compileSolanaSplTokenCloseAccountCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenCloseAccountCpi.so")
    "spl-token-close-account-cpi"
    "solana-spl-token-close-account-cpi-elf"
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec

def compileSolanaSplTokenAuthorityCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenAuthorityCpi.so")
    "spl-token-authority-cpi"
    "solana-spl-token-authority-cpi-elf"
    ProofForge.Solana.Examples.SplTokenAuthorityCpi.spec

def compileSolanaAssociatedTokenCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/AssociatedTokenCpi.so")
    "associated-token-cpi"
    "solana-associated-token-cpi-elf"
    ProofForge.Solana.Examples.AssociatedTokenCpi.spec

def compileSolanaSplToken2022CpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplToken2022Cpi.so")
    "spl-token-2022-cpi"
    "solana-spl-token-2022-cpi-elf"
    ProofForge.Solana.Examples.SplToken2022Cpi.spec

def compileSolanaSplToken2022PausableCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplToken2022PausableCpi.so")
    "spl-token-2022-pausable-cpi"
    "solana-spl-token-2022-pausable-cpi-elf"
    ProofForge.Solana.Examples.SplToken2022PausableCpi.spec

def compileSolanaSplToken2022TransferHookElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplToken2022TransferHook.so")
    "spl-token-2022-transfer-hook"
    "solana-spl-token-2022-transfer-hook-elf"
    ProofForge.Solana.Examples.SplToken2022TransferHook.spec

def compileSolanaLogEventElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/LogEvent.so")
    "log-event"
    "solana-log-event-elf"
    ProofForge.Solana.Examples.LogEvent.spec

def compileSolanaClockSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Clock.so")
    "clock-sysvar"
    "solana-clock-sysvar-elf"
    ProofForge.Solana.Examples.Clock.spec

def compileSolanaRentSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Rent.so")
    "rent-sysvar"
    "solana-rent-sysvar-elf"
    ProofForge.Solana.Examples.Rent.spec

def compileSolanaEpochScheduleSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/EpochSchedule.so")
    "epoch-schedule-sysvar"
    "solana-epoch-schedule-sysvar-elf"
    ProofForge.Solana.Examples.EpochSchedule.spec

def compileSolanaEpochRewardsSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/EpochRewards.so")
    "epoch-rewards-sysvar"
    "solana-epoch-rewards-sysvar-elf"
    ProofForge.Solana.Examples.EpochRewards.spec

def compileSolanaLastRestartSlotSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/LastRestartSlot.so")
    "last-restart-slot-sysvar"
    "solana-last-restart-slot-sysvar-elf"
    ProofForge.Solana.Examples.LastRestartSlot.spec

def compileSolanaMemoryElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Memory.so")
    "memory"
    "solana-memory-elf"
    ProofForge.Solana.Examples.Memory.spec

def compileSolanaCryptoHashElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/CryptoHash.so")
    "crypto-hash"
    "solana-crypto-hash-elf"
    ProofForge.Solana.Examples.Crypto.spec

def compileSolanaReturnDataComputeElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/ReturnDataCompute.so")
    "return-data-compute"
    "solana-return-data-compute-elf"
    ProofForge.Solana.Examples.ReturnDataCompute.spec

def compileSbpfAsm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/entrypoint.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderCannedEntrypoint with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "sbpf-asm-phase0-canned-entrypoint"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("capabilities", jsonStringArray #[]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
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
          ProofForge.Cli.metadataCommand opts
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
