import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.ConstructorInit
import ProofForge.Backend.Psy.IR
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
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.FileUtil
import ProofForge.Cli.PsyArtifacts
import ProofForge.Cli.EmitWatArtifacts
import ProofForge.Cli.IrJson
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.EvmArtifacts
import ProofForge.Cli.EvmFixtures
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
