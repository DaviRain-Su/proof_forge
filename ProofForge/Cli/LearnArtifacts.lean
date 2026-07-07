import Lean.Util.Path
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Cli.Artifact
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.EvmArtifacts
import ProofForge.Cli.FileUtil
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.TargetJson
import ProofForge.Cli.TokenLoader
import ProofForge.Contract.Learn
import ProofForge.Contract.Spec
import ProofForge.Contract.Token
import ProofForge.Contract.Token.EvmSpec
import ProofForge.Contract.Token.EvmWrap
import ProofForge.Contract.Token.Learn
import ProofForge.IR
import ProofForge.Target

open System
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

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

private def fileEndsWith (input : FilePath) (suffix : String) : Bool :=
  input.toString.endsWith suffix

private def tokenValidationKey (sourceKind : String) : String :=
  if sourceKind == "lean-token-source" then
    "leanTokenLoading"
  else
    "learnTokenParsing"

unsafe def parseTokenInput (opts : CliOptions) (modeName : String) :
    IO (FilePath × ProofForge.Contract.Token.Learn.TokenDecl × String) := do
  let input ← learnInput opts modeName
  if fileEndsWith input ".lean" then
    let (id?, spec) ← ProofForge.Cli.TokenLoader.loadToken input opts.root? opts.moduleName?
    let id := id?.getD (leanBaseName input)
    pure (input, { id := id, spec := spec }, "lean-token-source")
  else
    match (← ProofForge.Contract.Token.Learn.parseFile input) with
    | .ok decl => pure (input, decl, "learn-token-source")
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
    (sourceKind : String)
    (profile : ProofForge.Target.TargetProfile)
    (plan : ProofForge.Contract.Token.TokenPlan)
    (sourceArtifact : String)
    (solanaDeployment? : Option ProofForge.Contract.Token.SolanaTokenDeploymentPlan := none) : String :=
  jsonObject #[
    ("format", jsonString "proof-forge-token-plan-v0"),
    ("sourceKind", jsonString sourceKind),
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
      (tokenValidationKey sourceKind, jsonString "passed"),
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
    (sourceKind : String)
    (profile : ProofForge.Target.TargetProfile)
    (plan : ProofForge.Contract.Token.TokenPlan)
    (sourceArtifact yulArtifact bytecodeArtifact entrypointsJson eventsJson : String) : String :=
  jsonObject #[
    ("format", jsonString "proof-forge-token-artifact-v0"),
    ("sourceKind", jsonString sourceKind),
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
      (tokenValidationKey sourceKind, jsonString "passed"),
      ("targetRouting", jsonString "passed"),
      ("erc20IrLowering", jsonString "passed"),
      ("solcStrictAssembly", jsonString "passed")
    ])
  ]

def renderLearnEvmYul (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) :
    IO (String × ProofForge.IR.Module) :=
  renderContractSpecEvmYul opts spec

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
    (sourceKind : String)
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
    (tokenEvmArtifactJson decl sourceKind profile plan sourceArtifact yulArtifact bytecodeArtifact entrypointsJson
      eventsJson ++ "\n")
  IO.println s!"wrote {yulOutput}"
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  IO.println s!"wrote {metadataOutput}"
  return 0

def compileLearnTokenPlan (opts : CliOptions)
    (profile : ProofForge.Target.TargetProfile)
    (input : FilePath)
    (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (sourceKind : String)
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
  writeTextFile output (tokenPlanJson decl sourceKind profile plan sourceArtifact solanaDeployment? ++ "\n")
  IO.println s!"wrote {output}"
  return 0

unsafe def compileLearnTokenTarget (opts : CliOptions) : IO UInt32 := do
  let profile ← learnTokenTargetProfile opts
  let (input, decl, sourceKind) ← parseTokenInput opts "--learn-token"
  let plan ←
    match ProofForge.Contract.Token.planForTarget profile decl.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  if profile.id == ProofForge.Target.evm.id then
    compileLearnTokenEvm opts profile input decl sourceKind plan
  else
    compileLearnTokenPlan opts profile input decl sourceKind plan

end ProofForge.Cli
