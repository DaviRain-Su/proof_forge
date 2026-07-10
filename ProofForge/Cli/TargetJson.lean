import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Manifest
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.JsonUtil
import ProofForge.IR
import ProofForge.Target

open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

def targetMetadataJson (metadata : ProofForge.Target.TargetMetadata) : String :=
  jsonObject #[
    ("key", jsonString metadata.key),
    ("value", jsonString metadata.value)
  ]

def capabilityCallJson (call : ProofForge.Target.CapabilityCall) : String :=
  let sourceValue :=
    match call.source? with
    | some source => jsonString source
    | none => "null"
  jsonObject #[
    ("capability", jsonString call.capability.id),
    ("operation", jsonString call.operation),
    ("source", sourceValue),
    ("metadata", jsonArray (call.metadata.map targetMetadataJson))
  ]

def capabilityPlanJson (plan : ProofForge.Target.CapabilityPlan) : String :=
  jsonObject #[
    ("targetId", jsonString plan.targetId),
    ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
    ("calls", jsonArray (plan.calls.map capabilityCallJson)),
    ("metadata", jsonArray (plan.metadata.map targetMetadataJson))
  ]

def solanaExtensionAccountJson (account : ProofForge.Backend.Solana.Extension.AccountMeta) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("access", jsonString account.access),
    ("signer", jsonString account.signer)
  ]

def solanaDeclaredAccountJson
    (account : ProofForge.Backend.Solana.Extension.DeclaredAccount) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("access", jsonString account.access),
    ("signer", jsonString account.signer),
    ("owner", jsonString account.owner)
  ]

def solanaPdaSeedJson (seed : ProofForge.Backend.Solana.Extension.PdaSeed) : String :=
  jsonObject #[
    ("kind", jsonString seed.kind.id),
    ("value", jsonString seed.value)
  ]

def solanaPdaJson (pda : ProofForge.Backend.Solana.Extension.PdaDerive) : String :=
  jsonObject #[
    ("name", jsonString pda.name),
    ("seeds", jsonStringArray pda.seedValues),
    ("typedSeeds", jsonArray (pda.effectiveSeeds.map solanaPdaSeedJson)),
    ("bump", match pda.bump? with | some bump => jsonString bump | none => "null"),
    ("account", match pda.account? with | some account => jsonString account | none => "null"),
    ("signer", jsonBool pda.signer)
  ]

def solanaCpiJson (cpi : ProofForge.Backend.Solana.Extension.CpiInvoke) : String :=
  jsonObject #[
    ("name", jsonString cpi.name),
    ("program", jsonString cpi.program),
    ("instruction", jsonString cpi.instruction),
    ("accounts", jsonArray (cpi.accounts.map solanaExtensionAccountJson)),
    ("signerSeeds", jsonStringArray cpi.signerSeeds),
    ("protocol", match cpi.protocol? with | some protocol => jsonString protocol | none => "null"),
    ("dataLayout", match cpi.dataLayout? with | some layout => jsonString layout | none => "null"),
    ("lamportsSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.lamports_source" with
      | some value => jsonString value
      | none => "null"),
    ("spaceSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.space_source" with
      | some value => jsonString value
      | none => "null"),
    ("ownerSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.owner" with
      | some value => jsonString value
      | none => "null"),
    ("amountSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.amount_source" with
      | some value => jsonString value
      | none => "null"),
    ("feeSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.fee_source" with
      | some value => jsonString value
      | none => "null"),
    ("decimals",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.decimals" with
      | some value => jsonString value
      | none => "null"),
    ("authorityType",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.authority_type" with
      | some value => jsonString value
      | none => "null"),
    ("newAuthority",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.new_authority" with
      | some value => jsonString value
      | none => "null"),
    ("transferFeeConfigAuthority",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.transfer_fee_config_authority" with
      | some value => jsonString value
      | none => "null"),
    ("withdrawWithheldAuthority",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.withdraw_withheld_authority" with
      | some value => jsonString value
      | none => "null"),
    ("transferFeeBasisPoints",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.transfer_fee_basis_points" with
      | some value => jsonString value
      | none => "null"),
    ("maximumFee",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.maximum_fee" with
      | some value => jsonString value
      | none => "null"),
    ("numTokenAccounts",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.num_token_accounts" with
      | some value => jsonString value
      | none => "null"),
    ("signed", jsonBool cpi.signed)
  ]

def solanaAllocatorJson (allocator : ProofForge.Backend.Solana.Extension.RuntimeAllocator) : String :=
  let region := allocator.config.model.region
  jsonObject #[
    ("name", jsonString allocator.name),
    ("kind", jsonString allocator.kind),
    ("model", jsonString allocator.model),
    ("heapStart", jsonString allocator.heapStart),
    ("heapBytes", jsonString allocator.heapBytes),
    ("strategy", jsonString allocator.config.model.strategy.id),
    ("release", jsonString allocator.config.model.release.id),
    ("region", jsonObject #[
      ("base", jsonString (toString region.base)),
      ("size", jsonString allocator.heapBytes),
      ("growable", jsonString (toString region.growable))
    ])
  ]

def solanaPdaActionJson (action : ProofForge.Backend.Solana.Extension.PdaAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("pda", jsonString action.name)
  ]

def solanaCpiActionJson (action : ProofForge.Backend.Solana.Extension.CpiAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("cpi", jsonString action.name)
  ]

def solanaMemoryActionJson (action : ProofForge.Backend.Solana.Extension.MemoryAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("memory", jsonString action.name),
    ("op", jsonString action.op.id),
    ("bytes", toString action.bytes),
    ("dstState", match action.dstState? with | some state => jsonString state | none => "null"),
    ("srcState", match action.srcState? with | some state => jsonString state | none => "null"),
    ("lhsState", match action.lhsState? with | some state => jsonString state | none => "null"),
    ("rhsState", match action.rhsState? with | some state => jsonString state | none => "null"),
    ("resultState", match action.resultState? with | some state => jsonString state | none => "null"),
    ("value", match action.value? with | some value => toString value | none => "null")
  ]

def solanaCryptoHashActionJson
    (action : ProofForge.Backend.Solana.Extension.CryptoHashAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("crypto", jsonString action.name),
    ("op", jsonString action.op.id),
    ("inputState", jsonString action.inputState),
    ("bytes", toString action.bytes),
    ("outputStates", jsonArray (action.outputStates.map jsonString)),
    ("featureGated", jsonBool action.featureGated)
  ]

def solanaSysvarActionJson
    (action : ProofForge.Backend.Solana.Extension.SysvarReadAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("sysvar", jsonString action.name),
    ("kind", jsonString action.kind.id),
    ("field", jsonString action.field.id),
    ("outputState", jsonString action.outputState),
    ("featureGated", jsonBool (ProofForge.Backend.Solana.Extension.SysvarKind.featureGated action.kind))
  ]

def solanaReturnDataActionJson
    (action : ProofForge.Backend.Solana.Extension.ReturnDataAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("returnData", jsonString action.name),
    ("op", jsonString "set"),
    ("sourceState", jsonString action.sourceState),
    ("bytes", toString action.bytes)
  ]

def solanaReturnDataReadActionJson
    (action : ProofForge.Backend.Solana.Extension.ReturnDataReadAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("returnData", jsonString action.name),
    ("op", jsonString "get"),
    ("destinationState", jsonString action.destinationState),
    ("maxBytes", toString action.maxBytes),
    ("lengthState", match action.lengthState? with | some state => jsonString state | none => "null"),
    ("programIdStates", jsonArray (action.programIdStates.map jsonString))
  ]

def solanaComputeUnitsActionJson
    (action : ProofForge.Backend.Solana.Extension.ComputeUnitsAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("computeUnits", jsonString action.name),
    ("op", jsonString "remaining"),
    ("outputState", jsonString action.outputState),
    ("featureGated", jsonBool action.featureGated)
  ]

def solanaComputeUnitsLogActionJson
    (action : ProofForge.Backend.Solana.Extension.ComputeUnitsLogAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("computeUnits", jsonString action.name),
    ("op", jsonString "log_remaining")
  ]

def solanaPubkeyLogActionJson
    (action : ProofForge.Backend.Solana.Extension.PubkeyLogAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("log", jsonString action.name),
    ("op", jsonString "pubkey"),
    ("account", jsonString action.account)
  ]

def solanaDataLogActionJson
    (action : ProofForge.Backend.Solana.Extension.DataLogAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("log", jsonString action.name),
    ("op", jsonString "data"),
    ("sourceState", jsonString action.sourceState),
    ("bytes", toString action.bytes)
  ]

def solanaInstructionAccountJson (account : ProofForge.Backend.Solana.Manifest.AccountEntry) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("index", toString account.index),
    ("signer", jsonBool account.signer),
    ("writable", jsonBool account.writable),
    ("owner", jsonString account.owner)
  ]

def solanaInstructionParamJson
    (param : ProofForge.Backend.Solana.Manifest.InstructionParamEntry) : String :=
  jsonObject #[
    ("name", jsonString param.name),
    ("type", jsonString param.typeName),
    ("offset", toString param.offset),
    ("byteSize", toString param.byteSize),
    ("encoding", jsonString param.encoding)
  ]

def solanaInstructionJson (instruction : ProofForge.Backend.Solana.Manifest.InstructionEntry) : String :=
  jsonObject #[
    ("name", jsonString instruction.name),
    ("tag", toString instruction.tag),
    ("handler", jsonString instruction.handler),
    ("minDataLen", toString instruction.minDataLen),
    ("accounts", jsonArray (instruction.accounts.map solanaInstructionAccountJson)),
    ("params", jsonArray (instruction.params.map solanaInstructionParamJson))
  ]

def solanaInstructionsJson (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : String :=
  jsonArray ((ProofForge.Backend.Solana.Manifest.buildInstructionsWithPlan module plan).map solanaInstructionJson)

def solanaExtensionsJson (plan : ProofForge.Target.CapabilityPlan) : String :=
  let extensions := ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan
  jsonObject #[
    ("accounts", jsonArray (extensions.accounts.map solanaDeclaredAccountJson)),
    ("allocators", jsonArray (extensions.allocators.map solanaAllocatorJson)),
    ("pdas", jsonArray (extensions.pdas.map solanaPdaJson)),
    ("cpis", jsonArray (extensions.cpis.map solanaCpiJson)),
    ("pdaActions", jsonArray (extensions.pdaActions.map solanaPdaActionJson)),
    ("cpiActions", jsonArray (extensions.cpiActions.map solanaCpiActionJson)),
    ("memoryActions", jsonArray (extensions.memoryActions.map solanaMemoryActionJson)),
    ("cryptoHashActions", jsonArray (extensions.cryptoHashActions.map solanaCryptoHashActionJson)),
    ("sysvarActions", jsonArray (extensions.sysvarActions.map solanaSysvarActionJson)),
    ("returnDataActions", jsonArray (extensions.returnDataActions.map solanaReturnDataActionJson)),
    ("returnDataReadActions", jsonArray (extensions.returnDataReadActions.map solanaReturnDataReadActionJson)),
    ("computeUnitsActions", jsonArray (extensions.computeUnitsActions.map solanaComputeUnitsActionJson)),
    ("computeUnitsLogActions", jsonArray (extensions.computeUnitsLogActions.map solanaComputeUnitsLogActionJson)),
    ("pubkeyLogActions", jsonArray (extensions.pubkeyLogActions.map solanaPubkeyLogActionJson)),
    ("dataLogActions", jsonArray (extensions.dataLogActions.map solanaDataLogActionJson))
  ]

/-! ## PF-P1-02: machine-readable target support matrix (`--list-targets --json`) -/

def toolStageRequirementJson (req : ProofForge.Target.ToolStageRequirement) : String :=
  jsonObject #[
    ("tool", jsonString req.tool),
    ("stage", jsonString req.stage)
  ]

def targetSupportJson (support : ProofForge.Target.TargetSupport) : String :=
  jsonObject #[
    ("maturity", jsonString support.maturity.id),
    ("inputModes", jsonStringArray (support.inputModes.map fun m => m.id)),
    ("commands", jsonStringArray (support.commands.map fun c => c.id)),
    ("outputStages", jsonStringArray (support.outputStages.map fun s => s.id)),
    ("validationLevel", jsonString support.validationLevel.id),
    ("supportedFragment", jsonString support.supportedFragment),
    ("toolStages", jsonArray (support.toolStages.map toolStageRequirementJson))
  ]

def targetProfileSupportJson (profile : ProofForge.Target.TargetProfile) : String :=
  jsonObject #[
    ("id", jsonString profile.id),
    ("family", jsonString profile.family.id),
    ("artifactKind", jsonString profile.artifactKind.id),
    ("requiredTools", jsonStringArray profile.requiredTools),
    ("support", targetSupportJson profile.support)
  ]

/-- Authoritative support matrix for every active registry target. -/
def listTargetsJson : String :=
  jsonObject #[
    ("schemaVersion", jsonString "1"),
    ("kind", jsonString "proof-forge-target-support-matrix"),
    ("targets", jsonArray (ProofForge.Target.all.map targetProfileSupportJson))
  ]

end ProofForge.Cli
