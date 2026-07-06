import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Manifest
import ProofForge.Contract.Spec.Json
import ProofForge.IR.Contract
import ProofForge.Target.Plan
import ProofForge.Util.Json

namespace ProofForge.Backend.Solana.Idl

open ProofForge.IR
open ProofForge.Target
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.Manifest
open ProofForge.Util.Json

def schema : String := "proof-forge.solana.idl.v0"
def targetId : String := "solana-sbpf-asm"
def irVersion : String := "portable-ir-v0"
def idlPath : String := "proof-forge-idl.json"

def jsonNatOption : Option Nat → String
  | some value => toString value
  | none => "null"

def pushUnique (values : Array String) (value : String) : Array String :=
  if values.any (fun existing => existing == value) then values else values.push value

def dedupStrings (values : Array String) : Array String :=
  values.foldl pushUnique #[]

def stateKindName : StateKind → String
  | .scalar => "scalar"
  | .map _ _ => "map"
  | .array _ => "array"
  | .dynamicArray => "dynamicArray"

def stateKindJson : StateKind → String
  | .scalar =>
      jsonObject #[
        ("kind", jsonString "scalar")
      ]
  | .map keyType capacity =>
      jsonObject #[
        ("kind", jsonString "map"),
        ("keyType", jsonString keyType.name),
        ("capacity", toString capacity)
      ]
  | .array length =>
      jsonObject #[
        ("kind", jsonString "array"),
        ("length", toString length)
      ]
  | .dynamicArray =>
      jsonObject #[
        ("kind", jsonString "dynamicArray")
      ]

def structFieldJson (field : StructField) : String :=
  jsonObject #[
    ("name", jsonString field.id),
    ("type", jsonString field.type.name),
    ("public", jsonBool field.isPublic),
    ("ref", jsonBool field.isRef)
  ]

def structJson (decl : StructDecl) : String :=
  jsonObject #[
    ("name", jsonString decl.name),
    ("fields", jsonArray (decl.fields.map structFieldJson)),
    ("deriveStorage", jsonBool decl.deriveStorage),
    ("public", jsonBool decl.isPublic)
  ]

def stateJson (state : StateDecl) : String :=
  jsonObject #[
    ("name", jsonString state.id),
    ("type", jsonString state.type.name),
    ("kind", jsonString (stateKindName state.kind)),
    ("layout", stateKindJson state.kind)
  ]

def accountJson (account : AccountEntry) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("index", toString account.index),
    ("signer", jsonBool account.signer),
    ("writable", jsonBool account.writable),
    ("owner", jsonString account.owner)
  ]

def paramJson (param : InstructionParamEntry) : String :=
  jsonObject #[
    ("name", jsonString param.name),
    ("type", jsonString param.typeName),
    ("offset", toString param.offset),
    ("byteSize", toString param.byteSize),
    ("encoding", jsonString param.encoding)
  ]

def entrypointReturnJson (module : Module) (name : String) : String :=
  match module.entrypoints.find? (fun ep => ep.name == name) with
  | some ep => jsonString ep.returns.name
  | none => jsonString "Unit"

def computeBudgetJson (action : ComputeBudgetAdvice) : String :=
  jsonObject #[
    ("name", jsonString action.name),
    ("unitLimit", jsonNatOption action.unitLimit?),
    ("unitPriceMicroLamports", jsonNatOption action.unitPriceMicroLamports?)
  ]

def computeBudgetForEntrypoint (extensions : ProgramExtensions) (entrypoint : String) :
    Array ComputeBudgetAdvice :=
  extensions.computeBudgetActions.filter (fun action => action.entrypoint == entrypoint)

def instructionJson (module : Module) (extensions : ProgramExtensions)
    (instruction : InstructionEntry) : String :=
  jsonObject #[
    ("name", jsonString instruction.name),
    ("tag", toString instruction.tag),
    ("handler", jsonString instruction.handler),
    ("minDataLen", toString instruction.minDataLen),
    ("accounts", jsonArray (instruction.accounts.map accountJson)),
    ("params", jsonArray (instruction.params.map paramJson)),
    ("computeBudget", jsonArray ((computeBudgetForEntrypoint extensions instruction.name).map computeBudgetJson)),
    ("returns", entrypointReturnJson module instruction.name)
  ]

def declaredAccountJson (account : DeclaredAccount) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("access", jsonString account.access),
    ("signer", jsonString account.signer),
    ("owner", jsonString account.owner),
    ("entrypoint", jsonStringOption account.entrypoint?)
  ]

def pdaSeedJson (seed : PdaSeed) : String :=
  jsonObject #[
    ("kind", jsonString seed.kind.id),
    ("value", jsonString seed.value),
    ("raw", jsonString seed.raw)
  ]

def pdaJson (pda : PdaDerive) : String :=
  jsonObject #[
    ("name", jsonString pda.name),
    ("seeds", jsonStringArray pda.seedValues),
    ("typedSeeds", jsonArray (pda.effectiveSeeds.map pdaSeedJson)),
    ("bump", jsonStringOption pda.bump?),
    ("account", jsonStringOption pda.account?),
    ("signer", jsonBool pda.signer),
    ("entrypoint", jsonStringOption pda.entrypoint?)
  ]

def cpiAccountJson (account : AccountMeta) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("access", jsonString account.access),
    ("signer", jsonString account.signer)
  ]

def cpiMetadataJson (cpi : CpiInvoke) (metadataKey fieldName : String) : String × String :=
  match metadataValue? cpi.metadata metadataKey with
  | some value => (fieldName, jsonString value)
  | none => (fieldName, "null")

def cpiJson (cpi : CpiInvoke) : String :=
  jsonObject #[
    ("name", jsonString cpi.name),
    ("program", jsonString cpi.program),
    ("instruction", jsonString cpi.instruction),
    ("accounts", jsonArray (cpi.accounts.map cpiAccountJson)),
    ("signerSeeds", jsonStringArray cpi.signerSeeds),
    ("protocol", jsonStringOption cpi.protocol?),
    ("dataLayout", jsonStringOption cpi.dataLayout?),
    cpiMetadataJson cpi "solana.cpi.lamports_source" "lamportsSource",
    cpiMetadataJson cpi "solana.cpi.space_source" "spaceSource",
    cpiMetadataJson cpi "solana.cpi.owner" "ownerSource",
    cpiMetadataJson cpi "solana.cpi.amount_source" "amountSource",
    cpiMetadataJson cpi "solana.cpi.fee_source" "feeSource",
    cpiMetadataJson cpi "solana.cpi.decimals" "decimals",
    cpiMetadataJson cpi "solana.cpi.authority_type" "authorityType",
    cpiMetadataJson cpi "solana.cpi.new_authority" "newAuthority",
    cpiMetadataJson cpi "solana.cpi.token_program" "tokenProgram",
    cpiMetadataJson cpi "solana.cpi.transfer_fee_config_authority" "transferFeeConfigAuthority",
    cpiMetadataJson cpi "solana.cpi.withdraw_withheld_authority" "withdrawWithheldAuthority",
    cpiMetadataJson cpi "solana.cpi.transfer_fee_basis_points" "transferFeeBasisPoints",
    cpiMetadataJson cpi "solana.cpi.maximum_fee" "maximumFee",
    cpiMetadataJson cpi "solana.cpi.num_token_accounts" "numTokenAccounts",
    cpiMetadataJson cpi "solana.cpi.memo_source" "memoSource",
    cpiMetadataJson cpi "solana.cpi.metadata_pointer_authority" "metadataPointerAuthority",
    cpiMetadataJson cpi "solana.cpi.metadata_address" "metadataAddress",
    cpiMetadataJson cpi "solana.cpi.default_account_state" "defaultAccountState",
    cpiMetadataJson cpi "solana.cpi.permanent_delegate" "permanentDelegate",
    cpiMetadataJson cpi "solana.cpi.interest_rate_authority" "interestRateAuthority",
    cpiMetadataJson cpi "solana.cpi.interest_rate" "interestRate",
    cpiMetadataJson cpi "solana.cpi.memo_transfer_required" "memoTransferRequired",
    cpiMetadataJson cpi "solana.cpi.transfer_hook_authority" "transferHookAuthority",
    cpiMetadataJson cpi "solana.cpi.transfer_hook_program" "transferHookProgram",
    cpiMetadataJson cpi "solana.cpi.pausable_authority" "pausableAuthority",
    ("signed", jsonBool cpi.signed),
    ("entrypoint", jsonStringOption cpi.entrypoint?)
  ]

def allocatorJson (allocator : RuntimeAllocator) : String :=
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
    ]),
    ("entrypoint", jsonStringOption allocator.entrypoint?)
  ]

def pdaActionJson (action : PdaAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("pda", jsonString action.name)
  ]

def cpiActionJson (action : CpiAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("cpi", jsonString action.name)
  ]

def computeBudgetActionJson (action : ComputeBudgetAdvice) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("computeBudget", jsonString action.name),
    ("unitLimit", jsonNatOption action.unitLimit?),
    ("unitPriceMicroLamports", jsonNatOption action.unitPriceMicroLamports?)
  ]

def accountReallocActionJson (action : AccountReallocAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("realloc", jsonString action.name),
    ("account", jsonString action.account),
    ("newSize", toString action.newSize),
    ("maxPermittedDataIncrease",
      toString ProofForge.Backend.Solana.StateLayout.MAX_PERMITTED_DATA_INCREASE)
  ]

def transferHookExtraAccountMetaListActionJson
    (action : TransferHookExtraAccountMetaListAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("transferHookExtraMeta", jsonString action.name),
    ("account", jsonString action.account),
    ("extraAccounts", jsonStringArray action.extraAccounts),
    ("executeDiscriminator", jsonString "692565c54bfb661a"),
    ("extraAccountCount", toString action.extraAccounts.size)
  ]

def actionsJson (extensions : ProgramExtensions) : String :=
  jsonObject #[
    ("pdas", jsonArray (extensions.pdaActions.map pdaActionJson)),
    ("cpis", jsonArray (extensions.cpiActions.map cpiActionJson)),
    ("computeBudget", jsonArray (extensions.computeBudgetActions.map computeBudgetActionJson)),
    ("accountReallocs", jsonArray (extensions.accountReallocActions.map accountReallocActionJson)),
    ("transferHookExtraMetas", jsonArray
      (extensions.transferHookExtraAccountMetaListActions.map
        transferHookExtraAccountMetaListActionJson))
  ]

def capabilitiesJson (plan : CapabilityPlan) : String :=
  jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))

def renderWithInstructions (module : Module) (instructions : Array InstructionEntry)
    (extensions : ProgramExtensions) (capabilities : Array String := #[]) : String :=
  jsonObject #[
    ("schema", jsonString schema),
    ("name", jsonString module.name),
    ("target", jsonString targetId),
    ("irVersion", jsonString irVersion),
    ("capabilities", jsonStringArray (dedupStrings capabilities)),
    ("structs", jsonArray (module.structs.map structJson)),
    ("state", jsonArray (module.state.map stateJson)),
    ("instructions", jsonArray (instructions.map (instructionJson module extensions))),
    ("accounts", jsonArray (buildModuleAccounts module extensions |>.map accountJson)),
    ("declaredAccounts", jsonArray (extensions.accounts.map declaredAccountJson)),
    ("allocators", jsonArray (extensions.allocators.map allocatorJson)),
    ("pdas", jsonArray (extensions.pdas.map pdaJson)),
    ("cpis", jsonArray (extensions.cpis.map cpiJson)),
    ("errors", jsonArray (ProofForge.Contract.Spec.Json.errorCatalog module |>.map
      ProofForge.Contract.Spec.Json.errorCatalogEntryJson)),
    ("entrypointActions", actionsJson extensions)
  ]

def renderWithPlan (module : Module) (plan : CapabilityPlan) : String :=
  let extensions := ProgramExtensions.fromPlan plan
  renderWithInstructions
    module
    (buildInstructionsWithExtensions module extensions)
    extensions
    (plan.capabilities.map fun capability => capability.id)

def render (module : Module) : String :=
  let extensions : ProgramExtensions := {}
  renderWithInstructions
    module
    (buildInstructions module)
    extensions
    (module.capabilities.map fun capability => capability.id)

end ProofForge.Backend.Solana.Idl
