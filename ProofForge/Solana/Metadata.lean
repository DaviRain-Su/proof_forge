import ProofForge.Solana.Types

namespace ProofForge.Solana

open ProofForge.Target

def kv (key value : String) : TargetMetadata := {
  key := key
  value := value
}

def joinWith (separator : String) (values : Array String) : String :=
  values.foldl
    (fun acc value =>
      if acc == "" then
        value
      else
        acc ++ separator ++ value)
    ""

def maybeKv (key : String) : Option String -> Array TargetMetadata
  | some value => #[kv key value]
  | none => #[]

def boolValue (value : Bool) : String :=
  if value then "true" else "false"

def seedPrefixValue? (marker seed : String) : Option String :=
  if seed.startsWith marker then
    some (seed.drop marker.length |>.toString)
  else
    none

def seedDescriptorValue (seed : String) : String :=
  match seedPrefixValue? "literal:" seed with
  | some value => value
  | none =>
      match seedPrefixValue? "utf8:" seed with
      | some value => value
      | none =>
          match seedPrefixValue? "account:" seed with
          | some value => value
          | none =>
              match seedPrefixValue? "bump:" seed with
              | some value => value
              | none =>
                  match seedPrefixValue? "param:" seed with
                  | some value => value
                  | none =>
                      match seedPrefixValue? "instruction:" seed with
                      | some value => value
                      | none => seed

def literalSeed (value : String) : String :=
  "literal:" ++ value

def utf8Seed (value : String) : String :=
  "utf8:" ++ value

def accountSeed (account : String) : String :=
  "account:" ++ account

def bumpSeed (source : String) : String :=
  "bump:" ++ source

def instructionSeed (param : String) : String :=
  "param:" ++ param

def paramSeed (param : String) : String :=
  instructionSeed param

def AccountMeta.encode (account : AccountMeta) : String :=
  account.name ++ ":" ++ account.access.id ++ ":" ++ account.signer.id

def AccountConstraint.metadata (account : AccountConstraint) : Array TargetMetadata :=
  #[
    kv "solana.extension" "account",
    kv "solana.account.name" account.name,
    kv "solana.account.access" account.access.id,
    kv "solana.account.signer" account.signer.id,
    kv "solana.account.owner" account.owner
  ]

def account (name : String) (access : AccountAccess := .readOnly)
    (signerPolicy : SignerPolicy := .none) : AccountMeta := {
  name := name
  access := access
  signer := signerPolicy
}

def readonlyAccount (name : String) : AccountMeta :=
  account name .readOnly .none

def writableAccount (name : String) : AccountMeta :=
  account name .writable .none

def signerAccount (name : String) (access : AccountAccess := .readOnly) : AccountMeta :=
  account name access .signer

def writableSignerAccount (name : String) : AccountMeta :=
  account name .writable .signer

def pdaSignerAccount (name : String) (access : AccountAccess := .readOnly) : AccountMeta :=
  account name access .pdaSigner

def PdaBinding.metadata (binding : PdaBinding) : Array TargetMetadata :=
  #[
    kv "solana.extension" "pda",
    kv "solana.pda.name" binding.name,
    kv "solana.pda.seeds" (joinWith "," (binding.seeds.map seedDescriptorValue)),
    kv "solana.pda.seed_descriptors" (joinWith "," binding.seeds),
    kv "solana.pda.signer" (boolValue binding.isSigner)
  ] ++
  maybeKv "solana.pda.bump" binding.bump? ++
  maybeKv "solana.pda.account" binding.account?

def CpiCall.metadata (call : CpiCall) : Array TargetMetadata :=
  #[
    kv "solana.extension" "cpi",
    kv "solana.cpi.name" call.name,
    kv "solana.cpi.program" call.program,
    kv "solana.cpi.instruction" call.instruction,
    kv "solana.cpi.accounts" (joinWith "," (call.accounts.map AccountMeta.encode)),
    kv "solana.cpi.signer_seeds" (joinWith "," call.signerSeeds)
  ] ++
  maybeKv "solana.cpi.data_layout" call.dataLayout? ++
  call.extraMetadata

def AllocatorConfig.metadata (config : AllocatorConfig) : Array TargetMetadata :=
  #[
    kv "solana.extension" "allocator",
    kv "solana.allocator.name" config.name,
    kv "solana.allocator.kind" config.kind.id,
    kv "solana.allocator.heap_start" config.heapStart,
    kv "solana.allocator.heap_bytes" (toString config.heapBytes),
    kv "solana.allocator.model" (
      match config.kind with
      | .bump => "downward-bump"
      | .noAllocator => "deny-dynamic"
    )
  ]

def natKv (key : String) (value : Nat) : TargetMetadata :=
  kv key (toString value)

def maybeNatKv (key : String) : Option Nat -> Array TargetMetadata
  | some value => #[natKv key value]
  | none => #[]

def MemoryAction.metadata (action : MemoryAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "memory",
    kv "solana.memory.name" action.name,
    kv "solana.memory.op" action.op.id,
    natKv "solana.memory.bytes" action.bytes
  ] ++
  maybeKv "solana.memory.dst_state" action.dstState? ++
  maybeKv "solana.memory.src_state" action.srcState? ++
  maybeKv "solana.memory.lhs_state" action.lhsState? ++
  maybeKv "solana.memory.rhs_state" action.rhsState? ++
  maybeKv "solana.memory.result_state" action.resultState? ++
  maybeNatKv "solana.memory.value" action.value?

def CryptoHashAction.metadata (action : CryptoHashAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "crypto",
    kv "solana.crypto.name" action.name,
    kv "solana.crypto.op" action.op.id,
    kv "solana.crypto.input_state" action.inputState,
    natKv "solana.crypto.bytes" action.bytes,
    kv "solana.crypto.output_states" (joinWith "," action.outputStates),
    kv "solana.crypto.feature_gated" (boolValue action.featureGated)
  ]

def SysvarReadAction.metadata (action : SysvarReadAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "sysvar",
    kv "solana.sysvar.name" action.name,
    kv "solana.sysvar.kind" action.kind.id,
    kv "solana.sysvar.field" action.field.id,
    kv "solana.sysvar.output_state" action.outputState,
    kv "solana.sysvar.feature_gated" (boolValue (SysvarKind.featureGated action.kind))
  ]

def ReturnDataAction.metadata (action : ReturnDataAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "return_data",
    kv "solana.return_data.name" action.name,
    kv "solana.return_data.op" "set",
    kv "solana.return_data.source_state" action.sourceState,
    natKv "solana.return_data.bytes" action.bytes
  ]

def ReturnDataReadAction.metadata (action : ReturnDataReadAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "return_data",
    kv "solana.return_data.name" action.name,
    kv "solana.return_data.op" "get",
    kv "solana.return_data.destination_state" action.destinationState,
    natKv "solana.return_data.max_bytes" action.maxBytes,
    kv "solana.return_data.program_id_states" (joinWith "," action.programIdStates)
  ] ++
  maybeKv "solana.return_data.length_state" action.lengthState?

def ComputeUnitsAction.metadata (action : ComputeUnitsAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "compute_units",
    kv "solana.compute_units.name" action.name,
    kv "solana.compute_units.op" "remaining",
    kv "solana.compute_units.output_state" action.outputState,
    kv "solana.compute_units.feature_gated" (boolValue action.featureGated)
  ]

def ComputeUnitsLogAction.metadata (action : ComputeUnitsLogAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "compute_units",
    kv "solana.compute_units.name" action.name,
    kv "solana.compute_units.op" "log_remaining"
  ]

def ComputeBudgetAdvice.metadata (advice : ComputeBudgetAdvice) : Array TargetMetadata :=
  #[
    kv "solana.extension" "compute_budget",
    kv "solana.compute_budget.name" advice.name,
    kv "solana.compute_budget.op" "instruction"
  ] ++
  maybeNatKv "solana.compute_budget.unit_limit" advice.unitLimit? ++
  maybeNatKv "solana.compute_budget.unit_price_micro_lamports" advice.unitPriceMicroLamports?

def PubkeyLogAction.metadata (action : PubkeyLogAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "log",
    kv "solana.log.name" action.name,
    kv "solana.log.op" "pubkey",
    kv "solana.log.account" action.account
  ]

def DataLogAction.metadata (action : DataLogAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "log",
    kv "solana.log.name" action.name,
    kv "solana.log.op" "data",
    kv "solana.log.source_state" action.sourceState,
    natKv "solana.log.bytes" action.bytes
  ]

def AccountReallocAction.metadata (action : AccountReallocAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "account_realloc",
    kv "solana.account_realloc.name" action.name,
    kv "solana.account_realloc.account" action.account,
    natKv "solana.account_realloc.new_size" action.newSize
  ]

def TransferHookExtraAccountMetaListAction.metadata
    (action : TransferHookExtraAccountMetaListAction) : Array TargetMetadata :=
  #[
    kv "solana.extension" "transfer_hook_extra_account_meta_list",
    kv "solana.transfer_hook_extra_meta.name" action.name,
    kv "solana.transfer_hook_extra_meta.account" action.account,
    kv "solana.transfer_hook_extra_meta.extra_accounts" (joinWith "," action.extraAccounts)
  ]

end ProofForge.Solana
