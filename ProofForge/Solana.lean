import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Contract.Builder
import ProofForge.IR.Allocator

namespace ProofForge.Solana

open ProofForge.Target

inductive AccountAccess where
  | readOnly
  | writable
  deriving BEq, DecidableEq, Repr

def AccountAccess.id : AccountAccess -> String
  | .readOnly => "readonly"
  | .writable => "writable"

inductive SignerPolicy where
  | none
  | signer
  | pdaSigner
  deriving BEq, DecidableEq, Repr

def SignerPolicy.id : SignerPolicy -> String
  | .none => "none"
  | .signer => "signer"
  | .pdaSigner => "pda-signer"

structure AccountMeta where
  name : String
  access : AccountAccess := .readOnly
  signer : SignerPolicy := .none
  deriving Repr

structure AccountConstraint where
  name : String
  access : AccountAccess := .readOnly
  signer : SignerPolicy := .none
  owner : String := "any"
  deriving Repr

structure PdaBinding where
  name : String
  seeds : Array String := #[]
  bump? : Option String := none
  account? : Option String := none
  isSigner : Bool := false
  deriving Repr

structure CpiCall where
  name : String
  program : String
  instruction : String
  accounts : Array AccountMeta := #[]
  signerSeeds : Array String := #[]
  dataLayout? : Option String := none
  extraMetadata : Array TargetMetadata := #[]
  deriving Repr

inductive AllocatorKind where
  | bump
  | noAllocator
  deriving BEq, DecidableEq, Repr

def AllocatorKind.id : AllocatorKind -> String
  | .bump => "bump"
  | .noAllocator => "none"

structure AllocatorConfig where
  name : String := "runtime"
  kind : AllocatorKind := .bump
  heapStart : String := "0x300000000"
  heapBytes : Nat := 32768
  deriving Repr, Inhabited

def AllocatorConfig.toIRConfig (config : AllocatorConfig) : ProofForge.IR.AllocatorConfig :=
  let baseOpt :=
    if config.heapStart.startsWith "0x" then
      (config.heapStart.drop 2).toString.toNat?
    else
      config.heapStart.toNat?
  let base := baseOpt.getD 0x300000000
  let release :=
    match config.kind with
    | .bump => ProofForge.IR.AllocatorRelease.noop
    | .noAllocator => ProofForge.IR.AllocatorRelease.none
  let strategy :=
    match config.kind with
    | .bump => ProofForge.IR.AllocatorStrategy.bump
    | .noAllocator => ProofForge.IR.AllocatorStrategy.bump
  {
    model := {
      strategy := strategy
      region := { base := base, size? := some config.heapBytes, growable := false }
      release := release
    }
  }

inductive MemoryOp where
  | memcpy
  | memmove
  | memcmp
  | memset
  deriving BEq, DecidableEq, Repr

def MemoryOp.id : MemoryOp -> String
  | .memcpy => "memcpy"
  | .memmove => "memmove"
  | .memcmp => "memcmp"
  | .memset => "memset"

inductive CryptoHashOp where
  | sha256
  | keccak256
  | blake3
  deriving BEq, DecidableEq, Repr

def CryptoHashOp.id : CryptoHashOp -> String
  | .sha256 => "sha256"
  | .keccak256 => "keccak256"
  | .blake3 => "blake3"

def CryptoHashOp.featureGated : CryptoHashOp -> Bool
  | .blake3 => true
  | _ => false

inductive SysvarKind where
  | rent
  | epochSchedule
  | epochRewards
  | lastRestartSlot
  deriving BEq, DecidableEq, Repr

def SysvarKind.id : SysvarKind -> String
  | .rent => "rent"
  | .epochSchedule => "epoch_schedule"
  | .epochRewards => "epoch_rewards"
  | .lastRestartSlot => "last_restart_slot"

def SysvarKind.featureGated : SysvarKind -> Bool
  | .lastRestartSlot => true
  | _ => false

inductive SysvarField where
  | rentLamportsPerByteYear
  | epochScheduleSlotsPerEpoch
  | epochScheduleLeaderScheduleSlotOffset
  | epochScheduleWarmup
  | epochScheduleFirstNormalEpoch
  | epochScheduleFirstNormalSlot
  | epochRewardsDistributionStartingBlockHeight
  | epochRewardsNumPartitions
  | epochRewardsParentBlockhashWord0
  | epochRewardsParentBlockhashWord1
  | epochRewardsParentBlockhashWord2
  | epochRewardsParentBlockhashWord3
  | epochRewardsTotalPointsLow
  | epochRewardsTotalPointsHigh
  | epochRewardsTotalRewards
  | epochRewardsDistributedRewards
  | epochRewardsActive
  | lastRestartSlot
  deriving BEq, DecidableEq, Repr

def SysvarField.id : SysvarField -> String
  | .rentLamportsPerByteYear => "lamports_per_byte_year"
  | .epochScheduleSlotsPerEpoch => "slots_per_epoch"
  | .epochScheduleLeaderScheduleSlotOffset => "leader_schedule_slot_offset"
  | .epochScheduleWarmup => "warmup"
  | .epochScheduleFirstNormalEpoch => "first_normal_epoch"
  | .epochScheduleFirstNormalSlot => "first_normal_slot"
  | .epochRewardsDistributionStartingBlockHeight => "distribution_starting_block_height"
  | .epochRewardsNumPartitions => "num_partitions"
  | .epochRewardsParentBlockhashWord0 => "parent_blockhash_word0"
  | .epochRewardsParentBlockhashWord1 => "parent_blockhash_word1"
  | .epochRewardsParentBlockhashWord2 => "parent_blockhash_word2"
  | .epochRewardsParentBlockhashWord3 => "parent_blockhash_word3"
  | .epochRewardsTotalPointsLow => "total_points_low"
  | .epochRewardsTotalPointsHigh => "total_points_high"
  | .epochRewardsTotalRewards => "total_rewards"
  | .epochRewardsDistributedRewards => "distributed_rewards"
  | .epochRewardsActive => "active"
  | .lastRestartSlot => "last_restart_slot"

def SysvarField.kind : SysvarField -> SysvarKind
  | .rentLamportsPerByteYear => .rent
  | .epochScheduleSlotsPerEpoch => .epochSchedule
  | .epochScheduleLeaderScheduleSlotOffset => .epochSchedule
  | .epochScheduleWarmup => .epochSchedule
  | .epochScheduleFirstNormalEpoch => .epochSchedule
  | .epochScheduleFirstNormalSlot => .epochSchedule
  | .epochRewardsDistributionStartingBlockHeight => .epochRewards
  | .epochRewardsNumPartitions => .epochRewards
  | .epochRewardsParentBlockhashWord0 => .epochRewards
  | .epochRewardsParentBlockhashWord1 => .epochRewards
  | .epochRewardsParentBlockhashWord2 => .epochRewards
  | .epochRewardsParentBlockhashWord3 => .epochRewards
  | .epochRewardsTotalPointsLow => .epochRewards
  | .epochRewardsTotalPointsHigh => .epochRewards
  | .epochRewardsTotalRewards => .epochRewards
  | .epochRewardsDistributedRewards => .epochRewards
  | .epochRewardsActive => .epochRewards
  | .lastRestartSlot => .lastRestartSlot

structure MemoryAction where
  name : String
  op : MemoryOp
  dstState? : Option String := none
  srcState? : Option String := none
  lhsState? : Option String := none
  rhsState? : Option String := none
  resultState? : Option String := none
  bytes : Nat
  value? : Option Nat := none
  deriving Repr

structure CryptoHashAction where
  name : String
  op : CryptoHashOp := .sha256
  inputState : String
  bytes : Nat
  outputStates : Array String
  featureGated : Bool := false
  deriving Repr

structure SysvarReadAction where
  name : String
  kind : SysvarKind := .rent
  field : SysvarField := .rentLamportsPerByteYear
  outputState : String
  deriving Repr

structure ReturnDataAction where
  name : String
  sourceState : String
  bytes : Nat
  deriving Repr

structure ReturnDataReadAction where
  name : String
  destinationState : String
  maxBytes : Nat
  lengthState? : Option String := none
  programIdStates : Array String := #[]
  deriving Repr

structure ComputeUnitsAction where
  name : String
  outputState : String
  featureGated : Bool := true
  deriving Repr

structure ComputeUnitsLogAction where
  name : String
  deriving Repr

structure ComputeBudgetAdvice where
  name : String
  unitLimit? : Option Nat := none
  unitPriceMicroLamports? : Option Nat := none
  deriving Repr

structure PubkeyLogAction where
  name : String
  account : String
  deriving Repr

structure DataLogAction where
  name : String
  sourceState : String
  bytes : Nat
  deriving Repr

structure AccountReallocAction where
  name : String
  account : String
  newSize : Nat
  deriving Repr

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

def accountConstraint (name : String) (access : AccountAccess := .readOnly)
    (signerPolicy : SignerPolicy := .none) (owner : String := "any") :
    ProofForge.Contract.Builder.ModuleM Unit := do
  let account : AccountConstraint := { name, access, signer := signerPolicy, owner }
  ProofForge.Contract.Builder.capability .accountExplicit "solana.account.declare"
    (source? := some name)
    (metadata := account.metadata)

def readonlyAccountConstraint (name : String) (owner : String := "any") :
    ProofForge.Contract.Builder.ModuleM Unit :=
  accountConstraint name .readOnly .none owner

def writableAccountConstraint (name : String) (owner : String := "any") :
    ProofForge.Contract.Builder.ModuleM Unit :=
  accountConstraint name .writable .none owner

def signerAccountConstraint (name : String) (access : AccountAccess := .readOnly)
    (owner : String := "any") : ProofForge.Contract.Builder.ModuleM Unit :=
  accountConstraint name access .signer owner

def writableSignerAccountConstraint (name : String) (owner : String := "any") :
    ProofForge.Contract.Builder.ModuleM Unit :=
  accountConstraint name .writable .signer owner

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

def systemProgram : String :=
  "system_program"

def splTokenProgram : String :=
  "spl_token"

def splToken2022Program : String :=
  "spl_token_2022"

def associatedTokenProgram : String :=
  "associated_token"

def memoProgram : String :=
  "memo"

def memoMetadata : Array TargetMetadata :=
  #[
    kv "solana.cpi.protocol" "memo"
  ]

def tokenProtocolForProgram (tokenProgram : String) : String :=
  if tokenProgram == splToken2022Program then
    "token-2022"
  else
    "spl-token"

def signerForSeeds (name : String) (access : AccountAccess) (signerSeeds : Array String) : AccountMeta :=
  if signerSeeds.isEmpty then
    signerAccount name access
  else
    pdaSignerAccount name access

def systemMetadata : Array TargetMetadata :=
  #[
    kv "solana.cpi.protocol" "system"
  ]

def tokenMetadata (tokenProgram : String) : Array TargetMetadata :=
  #[
    kv "solana.cpi.protocol" (tokenProtocolForProgram tokenProgram)
  ]

def token2022Metadata : Array TargetMetadata :=
  tokenMetadata splToken2022Program

def systemTransferCall (name fromAccount to lamportsSource : String)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := systemProgram
  instruction := "transfer"
  accounts := #[
    signerForSeeds fromAccount .writable signerSeeds,
    writableAccount to
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "system.transfer"
  extraMetadata := systemMetadata ++ #[
    kv "solana.cpi.lamports_source" lamportsSource
  ]
}

/-- Memo program CPI: logs a UTF-8 memo string on-chain. No accounts, no signer
    seeds — the memo is purely instruction data. -/
def memoCall (name memoSource : String) : CpiCall := {
  name := name
  program := memoProgram
  instruction := "memo"
  accounts := #[]
  signerSeeds := #[]
  dataLayout? := some "memo.memo"
  extraMetadata := memoMetadata ++ #[
    kv "solana.cpi.memo_source" memoSource
  ]
}

def systemCreateAccountCall (name payer newAccount lamportsSource spaceSource owner : String)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := systemProgram
  instruction := "create_account"
  accounts := #[
    writableSignerAccount payer,
    signerForSeeds newAccount .writable signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "system.create_account"
  extraMetadata := systemMetadata ++ #[
    kv "solana.cpi.lamports_source" lamportsSource,
    kv "solana.cpi.space_source" spaceSource,
    kv "solana.cpi.owner" owner
  ]
}

def splTokenTransferCheckedCall (name source mint destination authority amountSource : String)
    (decimals : Nat) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "transfer_checked"
  accounts := #[
    writableAccount source,
    readonlyAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.transfer_checked"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource,
    kv "solana.cpi.decimals" (toString decimals)
  ]
}

def splToken2022InitializeTransferFeeConfigCall
    (name mint transferFeeConfigAuthority withdrawWithheldAuthority basisPointsSource
      maximumFeeSource : String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_transfer_fee_config"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_transfer_fee_config"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.transfer_fee_config_authority" transferFeeConfigAuthority,
    kv "solana.cpi.withdraw_withheld_authority" withdrawWithheldAuthority,
    kv "solana.cpi.transfer_fee_basis_points" basisPointsSource,
    kv "solana.cpi.maximum_fee" maximumFeeSource
  ]
}

def splToken2022TransferCheckedWithFeeCall
    (name source mint destination authority amountSource feeSource : String)
    (decimals : Nat) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "transfer_checked_with_fee"
  accounts := #[
    writableAccount source,
    readonlyAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.transfer_checked_with_fee"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.amount_source" amountSource,
    kv "solana.cpi.decimals" (toString decimals),
    kv "solana.cpi.fee_source" feeSource
  ]
}

def splToken2022WithdrawWithheldTokensFromMintCall
    (name mint destination authority : String) (signerSeeds : Array String := #[]) :
    CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "withdraw_withheld_tokens_from_mint"
  accounts := #[
    writableAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.withdraw_withheld_tokens_from_mint"
  extraMetadata := token2022Metadata
}

def splToken2022WithdrawWithheldTokensFromAccountsCall
    (name mint destination authority : String) (sources : Array String)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "withdraw_withheld_tokens_from_accounts"
  accounts :=
    #[
      readonlyAccount mint,
      writableAccount destination,
      signerForSeeds authority .readOnly signerSeeds
    ] ++ sources.map writableAccount
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.withdraw_withheld_tokens_from_accounts"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.num_token_accounts" (toString sources.size)
  ]
}

def splToken2022HarvestWithheldTokensToMintCall
    (name mint : String) (sources : Array String) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "harvest_withheld_tokens_to_mint"
  accounts := #[writableAccount mint] ++ sources.map writableAccount
  dataLayout? := some "token-2022.harvest_withheld_tokens_to_mint"
  extraMetadata := token2022Metadata
}

def splToken2022SetTransferFeeCall
    (name mint authority basisPointsSource maximumFeeSource : String)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "set_transfer_fee"
  accounts := #[
    writableAccount mint,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "token-2022.set_transfer_fee"
  extraMetadata := token2022Metadata ++ #[
    kv "solana.cpi.transfer_fee_basis_points" basisPointsSource,
    kv "solana.cpi.maximum_fee" maximumFeeSource
  ]
}

def splToken2022InitializeNonTransferableMintCall (name mint : String) :
    CpiCall := {
  name := name
  program := splToken2022Program
  instruction := "initialize_non_transferable_mint"
  accounts := #[
    writableAccount mint
  ]
  dataLayout? := some "token-2022.initialize_non_transferable_mint"
  extraMetadata := token2022Metadata
}

def splTokenMintToCall (name mint destination authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "mint_to"
  accounts := #[
    writableAccount mint,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.mint_to"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource
  ]
}

def splTokenBurnCall (name source mint authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "burn"
  accounts := #[
    writableAccount source,
    writableAccount mint,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.burn"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource
  ]
}

def splTokenApproveCall (name source delegate owner amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "approve"
  accounts := #[
    writableAccount source,
    readonlyAccount delegate,
    signerForSeeds owner .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.approve"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.amount_source" amountSource
  ]
}

def splTokenRevokeCall (name source owner : String) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "revoke"
  accounts := #[
    writableAccount source,
    signerForSeeds owner .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.revoke"
  extraMetadata := tokenMetadata tokenProgram
}

def splTokenCloseAccountCall (name account destination authority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "close_account"
  accounts := #[
    writableAccount account,
    writableAccount destination,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.close_account"
  extraMetadata := tokenMetadata tokenProgram
}

def splTokenSetAuthorityCall (name account authority authorityType newAuthority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) : CpiCall := {
  name := name
  program := tokenProgram
  instruction := "set_authority"
  accounts := #[
    writableAccount account,
    signerForSeeds authority .readOnly signerSeeds
  ]
  signerSeeds := signerSeeds
  dataLayout? := some "spl-token.set_authority"
  extraMetadata := tokenMetadata tokenProgram ++ #[
    kv "solana.cpi.authority_type" authorityType,
    kv "solana.cpi.new_authority" newAuthority
  ]
}

def pda (binding : PdaBinding) : ProofForge.Contract.Builder.ModuleM Unit := do
  ProofForge.Contract.Builder.capability .accountExplicit "solana.account.pda" (source? := some binding.name)
    (metadata := binding.metadata)
  ProofForge.Contract.Builder.capability .storagePda "solana.pda.derive" (source? := some binding.name)
    (metadata := binding.metadata)

def pdaEntry (binding : PdaBinding) : ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .accountExplicit "solana.account.pda" (source? := some binding.name)
    (metadata := binding.metadata)
  ProofForge.Contract.Builder.entryCapability .storagePda "solana.pda.derive" (source? := some binding.name)
    (metadata := binding.metadata)

def pdaAccount (name : String) (seeds : Array String) (bump? : Option String := none)
    (account? : Option String := none) (isSigner : Bool := false) : ProofForge.Contract.Builder.ModuleM Unit :=
  pda {
    name := name
    seeds := seeds
    bump? := bump?
    account? := account?
    isSigner := isSigner
  }

def derivePda (name : String) (seeds : Array String) (bump? : Option String := none)
    (account? : Option String := none) (isSigner : Bool := false) : ProofForge.Contract.Builder.EntryM Unit :=
  pdaEntry {
    name := name
    seeds := seeds
    bump? := bump?
    account? := account?
    isSigner := isSigner
  }

def allocator (config : AllocatorConfig) : ProofForge.Contract.Builder.ModuleM Unit := do
  ProofForge.Contract.Builder.capability .runtimeAllocator "solana.runtime.allocator"
    (source? := some config.name)
    (metadata := config.metadata)

def bumpAllocator (name : String := "runtime") (heapStart : String := "0x300000000")
    (heapBytes : Nat := 32768) : ProofForge.Contract.Builder.ModuleM Unit :=
  allocator {
    name := name
    kind := .bump
    heapStart := heapStart
    heapBytes := heapBytes
  }

def noAllocator (name : String := "runtime") : ProofForge.Contract.Builder.ModuleM Unit :=
  allocator {
    name := name
    kind := .noAllocator
    heapBytes := 0
  }

def memoryEntry (action : MemoryAction) : ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .runtimeMemory
    ("solana.memory." ++ action.op.id)
    (source? := some action.name)
    (metadata := action.metadata)

def memcpyState (name dstState srcState : String) (bytes : Nat) :
    ProofForge.Contract.Builder.EntryM Unit :=
  memoryEntry {
    name := name
    op := .memcpy
    dstState? := some dstState
    srcState? := some srcState
    bytes := bytes
  }

def memmoveState (name dstState srcState : String) (bytes : Nat) :
    ProofForge.Contract.Builder.EntryM Unit :=
  memoryEntry {
    name := name
    op := .memmove
    dstState? := some dstState
    srcState? := some srcState
    bytes := bytes
  }

def memcmpState (name lhsState rhsState resultState : String) (bytes : Nat) :
    ProofForge.Contract.Builder.EntryM Unit :=
  memoryEntry {
    name := name
    op := .memcmp
    lhsState? := some lhsState
    rhsState? := some rhsState
    resultState? := some resultState
    bytes := bytes
  }

def memsetState (name dstState : String) (value bytes : Nat) :
    ProofForge.Contract.Builder.EntryM Unit :=
  memoryEntry {
    name := name
    op := .memset
    dstState? := some dstState
    bytes := bytes
    value? := some value
  }

def cryptoHashEntry (action : CryptoHashAction) : ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .cryptoHash
    ("solana.crypto." ++ action.op.id)
    (source? := some action.name)
    (metadata := action.metadata)

def sha256StateToStates (name inputState : String) (bytes : Nat)
    (outputStates : Array String) : ProofForge.Contract.Builder.EntryM Unit :=
  cryptoHashEntry {
    name := name
    op := .sha256
    inputState := inputState
    bytes := bytes
    outputStates := outputStates
    featureGated := CryptoHashOp.featureGated .sha256
  }

def keccak256StateToStates (name inputState : String) (bytes : Nat)
    (outputStates : Array String) : ProofForge.Contract.Builder.EntryM Unit :=
  cryptoHashEntry {
    name := name
    op := .keccak256
    inputState := inputState
    bytes := bytes
    outputStates := outputStates
    featureGated := CryptoHashOp.featureGated .keccak256
  }

def blake3StateToStates (name inputState : String) (bytes : Nat)
    (outputStates : Array String) : ProofForge.Contract.Builder.EntryM Unit :=
  cryptoHashEntry {
    name := name
    op := .blake3
    inputState := inputState
    bytes := bytes
    outputStates := outputStates
    featureGated := CryptoHashOp.featureGated .blake3
  }

def sysvarEntry (action : SysvarReadAction) : ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .storageScalar
    "solana.sysvar.output_state"
    (source? := some action.outputState)
    (metadata := action.metadata)
  ProofForge.Contract.Builder.entryCapability .envBlock
    ("solana.sysvar." ++ action.kind.id ++ "." ++ action.field.id)
    (source? := some action.name)
    (metadata := action.metadata)

def rentLamportsPerByteYearToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .rent
    field := .rentLamportsPerByteYear
    outputState := outputState
  }

def epochScheduleSlotsPerEpochToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochSchedule
    field := .epochScheduleSlotsPerEpoch
    outputState := outputState
  }

def epochScheduleLeaderScheduleSlotOffsetToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochSchedule
    field := .epochScheduleLeaderScheduleSlotOffset
    outputState := outputState
  }

def epochScheduleWarmupToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochSchedule
    field := .epochScheduleWarmup
    outputState := outputState
  }

def epochScheduleFirstNormalEpochToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochSchedule
    field := .epochScheduleFirstNormalEpoch
    outputState := outputState
  }

def epochScheduleFirstNormalSlotToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochSchedule
    field := .epochScheduleFirstNormalSlot
    outputState := outputState
  }

def epochRewardsDistributionStartingBlockHeightToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsDistributionStartingBlockHeight
    outputState := outputState
  }

def epochRewardsNumPartitionsToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsNumPartitions
    outputState := outputState
  }

def epochRewardsParentBlockhashWord0ToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsParentBlockhashWord0
    outputState := outputState
  }

def epochRewardsParentBlockhashWord1ToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsParentBlockhashWord1
    outputState := outputState
  }

def epochRewardsParentBlockhashWord2ToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsParentBlockhashWord2
    outputState := outputState
  }

def epochRewardsParentBlockhashWord3ToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsParentBlockhashWord3
    outputState := outputState
  }

def epochRewardsTotalPointsLowToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsTotalPointsLow
    outputState := outputState
  }

def epochRewardsTotalPointsHighToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsTotalPointsHigh
    outputState := outputState
  }

def epochRewardsTotalRewardsToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsTotalRewards
    outputState := outputState
  }

def epochRewardsDistributedRewardsToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsDistributedRewards
    outputState := outputState
  }

def epochRewardsActiveToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .epochRewards
    field := .epochRewardsActive
    outputState := outputState
  }

def lastRestartSlotToState (name outputState : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  sysvarEntry {
    name := name
    kind := .lastRestartSlot
    field := .lastRestartSlot
    outputState := outputState
  }

def returnDataEntry (action : ReturnDataAction) : ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .storageScalar
    "solana.return_data.source_state"
    (source? := some action.sourceState)
    (metadata := action.metadata)
  ProofForge.Contract.Builder.entryCapability .runtimeReturnData
    "solana.return_data.set"
    (source? := some action.name)
    (metadata := action.metadata)

def setReturnDataFromState (name sourceState : String) (bytes : Nat) :
    ProofForge.Contract.Builder.EntryM Unit :=
  returnDataEntry {
    name := name
    sourceState := sourceState
    bytes := bytes
  }

def returnDataReadEntry (action : ReturnDataReadAction) :
    ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .storageScalar
    "solana.return_data.destination_state"
    (source? := some action.destinationState)
    (metadata := action.metadata)
  match action.lengthState? with
  | some state =>
      ProofForge.Contract.Builder.entryCapability .storageScalar
        "solana.return_data.length_state"
        (source? := some state)
        (metadata := action.metadata)
  | none => pure ()
  for state in action.programIdStates do
    ProofForge.Contract.Builder.entryCapability .storageScalar
      "solana.return_data.program_id_state"
      (source? := some state)
      (metadata := action.metadata)
  ProofForge.Contract.Builder.entryCapability .runtimeReturnData
    "solana.return_data.get"
    (source? := some action.name)
    (metadata := action.metadata)

def getReturnDataToState (name destinationState : String) (maxBytes : Nat)
    (lengthState? : Option String := none) (programIdStates : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  returnDataReadEntry {
    name := name
    destinationState := destinationState
    maxBytes := maxBytes
    lengthState? := lengthState?
    programIdStates := programIdStates
  }

def computeUnitsEntry (action : ComputeUnitsAction) : ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .storageScalar
    "solana.compute_units.output_state"
    (source? := some action.outputState)
    (metadata := action.metadata)
  ProofForge.Contract.Builder.entryCapability .runtimeComputeUnits
    "solana.compute_units.remaining"
    (source? := some action.name)
    (metadata := action.metadata)

def remainingComputeUnitsToState (name outputState : String) (featureGated : Bool := true) :
    ProofForge.Contract.Builder.EntryM Unit :=
  computeUnitsEntry {
    name := name
    outputState := outputState
    featureGated := featureGated
  }

def computeUnitsLogEntry (action : ComputeUnitsLogAction) :
    ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .runtimeComputeUnits
    "solana.compute_units.log_remaining"
    (source? := some action.name)
    (metadata := action.metadata)

def logRemainingComputeUnits (name : String := "log_remaining_compute_units") :
    ProofForge.Contract.Builder.EntryM Unit :=
  computeUnitsLogEntry {
    name := name
  }

def computeBudgetEntry (advice : ComputeBudgetAdvice) :
    ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .runtimeComputeUnits
    "solana.compute_budget.instruction"
    (source? := some advice.name)
    (metadata := advice.metadata)

def requestComputeBudget (name : String := "compute_budget")
    (unitLimit? : Option Nat := none) (unitPriceMicroLamports? : Option Nat := none) :
    ProofForge.Contract.Builder.EntryM Unit :=
  computeBudgetEntry {
    name := name
    unitLimit? := unitLimit?
    unitPriceMicroLamports? := unitPriceMicroLamports?
  }

def pubkeyLogEntry (action : PubkeyLogAction) :
    ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .accountExplicit
    "solana.log.pubkey.account"
    (source? := some action.account)
    (metadata := action.metadata)
  ProofForge.Contract.Builder.entryCapability .eventsEmit
    "solana.log.pubkey"
    (source? := some action.name)
    (metadata := action.metadata)

def logAccountPubkey (name account : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  pubkeyLogEntry {
    name := name
    account := account
  }

def dataLogEntry (action : DataLogAction) :
    ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .storageScalar
    "solana.log.data.source_state"
    (source? := some action.sourceState)
    (metadata := action.metadata)
  ProofForge.Contract.Builder.entryCapability .eventsEmit
    "solana.log.data"
    (source? := some action.name)
    (metadata := action.metadata)

def logStateData (name sourceState : String) (bytes : Nat) :
    ProofForge.Contract.Builder.EntryM Unit :=
  dataLogEntry {
    name := name
    sourceState := sourceState
    bytes := bytes
  }

def accountReallocEntry (action : AccountReallocAction) :
    ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .accountExplicit
    "solana.account.realloc"
    (source? := some action.name)
    (metadata := action.metadata)

def reallocAccount (name account : String) (newSize : Nat) :
    ProofForge.Contract.Builder.EntryM Unit :=
  accountReallocEntry {
    name := name
    account := account
    newSize := newSize
  }

def cpi (call : CpiCall) : ProofForge.Contract.Builder.ModuleM Unit := do
  if call.accounts.size > 0 then
    ProofForge.Contract.Builder.capability .accountExplicit "solana.cpi.accounts" (source? := some call.name)
      (metadata := call.metadata)
  let operation :=
    if call.signerSeeds.size == 0 then
      "solana.cpi.invoke"
    else
      "solana.cpi.invoke_signed"
  ProofForge.Contract.Builder.capability .crosscallCpi operation (source? := some call.name)
    (metadata := call.metadata)

def cpiEntry (call : CpiCall) : ProofForge.Contract.Builder.EntryM Unit := do
  if call.accounts.size > 0 then
    ProofForge.Contract.Builder.entryCapability .accountExplicit "solana.cpi.accounts" (source? := some call.name)
      (metadata := call.metadata)
  let operation :=
    if call.signerSeeds.size == 0 then
      "solana.cpi.invoke"
    else
      "solana.cpi.invoke_signed"
  ProofForge.Contract.Builder.entryCapability .crosscallCpi operation (source? := some call.name)
    (metadata := call.metadata)

def cpiInvoke (name program instruction : String) (accounts : Array AccountMeta := #[])
    (dataLayout? : Option String := none) (extraMetadata : Array TargetMetadata := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi {
    name := name
    program := program
    instruction := instruction
    accounts := accounts
    dataLayout? := dataLayout?
    extraMetadata := extraMetadata
  }

def cpiInvokeSigned (name program instruction : String) (accounts : Array AccountMeta)
    (signerSeeds : Array String) (dataLayout? : Option String := none)
    (extraMetadata : Array TargetMetadata := #[]) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi {
    name := name
    program := program
    instruction := instruction
    accounts := accounts
    signerSeeds := signerSeeds
    dataLayout? := dataLayout?
    extraMetadata := extraMetadata
  }

def invokeCpi (name program instruction : String) (accounts : Array AccountMeta := #[])
    (dataLayout? : Option String := none) (extraMetadata : Array TargetMetadata := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry {
    name := name
    program := program
    instruction := instruction
    accounts := accounts
    dataLayout? := dataLayout?
    extraMetadata := extraMetadata
  }

def invokeSignedCpi (name program instruction : String) (accounts : Array AccountMeta)
    (signerSeeds : Array String) (dataLayout? : Option String := none)
    (extraMetadata : Array TargetMetadata := #[]) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry {
    name := name
    program := program
    instruction := instruction
    accounts := accounts
    signerSeeds := signerSeeds
    dataLayout? := dataLayout?
    extraMetadata := extraMetadata
  }

def systemTransfer (name fromAccount to lamportsSource : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (systemTransferCall name fromAccount to lamportsSource (signerSeeds := signerSeeds))

def invokeSystemTransfer (name fromAccount to lamportsSource : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (systemTransferCall name fromAccount to lamportsSource (signerSeeds := signerSeeds))

def systemCreateAccount (name payer newAccount lamportsSource spaceSource owner : String)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (systemCreateAccountCall name payer newAccount lamportsSource spaceSource owner
    (signerSeeds := signerSeeds))

def invokeSystemCreateAccount (name payer newAccount lamportsSource spaceSource owner : String)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (systemCreateAccountCall name payer newAccount lamportsSource spaceSource owner
    (signerSeeds := signerSeeds))

def memo (name memoSource : String) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (memoCall name memoSource)

def invokeMemo (name memoSource : String) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (memoCall name memoSource)

def splTokenTransferChecked (name source mint destination authority amountSource : String)
    (decimals : Nat) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splTokenTransferCheckedCall name source mint destination authority amountSource decimals
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def invokeSplTokenTransferChecked (name source mint destination authority amountSource : String)
    (decimals : Nat) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splTokenTransferCheckedCall name source mint destination authority amountSource decimals
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def splToken2022InitializeTransferFeeConfig
    (name mint transferFeeConfigAuthority withdrawWithheldAuthority basisPointsSource
      maximumFeeSource : String) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializeTransferFeeConfigCall name mint transferFeeConfigAuthority
    withdrawWithheldAuthority basisPointsSource maximumFeeSource)

def invokeSplToken2022InitializeTransferFeeConfig
    (name mint transferFeeConfigAuthority withdrawWithheldAuthority basisPointsSource
      maximumFeeSource : String) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializeTransferFeeConfigCall name mint transferFeeConfigAuthority
    withdrawWithheldAuthority basisPointsSource maximumFeeSource)

def splToken2022TransferCheckedWithFee
    (name source mint destination authority amountSource feeSource : String)
    (decimals : Nat) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022TransferCheckedWithFeeCall name source mint destination authority
    amountSource feeSource decimals (signerSeeds := signerSeeds))

def invokeSplToken2022TransferCheckedWithFee
    (name source mint destination authority amountSource feeSource : String)
    (decimals : Nat) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022TransferCheckedWithFeeCall name source mint destination authority
    amountSource feeSource decimals (signerSeeds := signerSeeds))

def splToken2022WithdrawWithheldTokensFromMint
    (name mint destination authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022WithdrawWithheldTokensFromMintCall name mint destination authority
    (signerSeeds := signerSeeds))

def invokeSplToken2022WithdrawWithheldTokensFromMint
    (name mint destination authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022WithdrawWithheldTokensFromMintCall name mint destination authority
    (signerSeeds := signerSeeds))

def splToken2022WithdrawWithheldTokensFromAccounts
    (name mint destination authority : String) (sources : Array String)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022WithdrawWithheldTokensFromAccountsCall name mint destination authority sources
    (signerSeeds := signerSeeds))

def invokeSplToken2022WithdrawWithheldTokensFromAccounts
    (name mint destination authority : String) (sources : Array String)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022WithdrawWithheldTokensFromAccountsCall name mint destination authority sources
    (signerSeeds := signerSeeds))

def splToken2022HarvestWithheldTokensToMint
    (name mint : String) (sources : Array String) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022HarvestWithheldTokensToMintCall name mint sources)

def invokeSplToken2022HarvestWithheldTokensToMint
    (name mint : String) (sources : Array String) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022HarvestWithheldTokensToMintCall name mint sources)

def splToken2022SetTransferFee
    (name mint authority basisPointsSource maximumFeeSource : String)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022SetTransferFeeCall name mint authority basisPointsSource maximumFeeSource
    (signerSeeds := signerSeeds))

def invokeSplToken2022SetTransferFee
    (name mint authority basisPointsSource maximumFeeSource : String)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022SetTransferFeeCall name mint authority basisPointsSource maximumFeeSource
    (signerSeeds := signerSeeds))

def splToken2022InitializeNonTransferableMint (name mint : String) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializeNonTransferableMintCall name mint)

def invokeSplToken2022InitializeNonTransferableMint (name mint : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializeNonTransferableMintCall name mint)

def splTokenMintTo (name mint destination authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splTokenMintToCall name mint destination authority amountSource
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def invokeSplTokenMintTo (name mint destination authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splTokenMintToCall name mint destination authority amountSource
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def splTokenBurn (name source mint authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splTokenBurnCall name source mint authority amountSource
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def invokeSplTokenBurn (name source mint authority amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splTokenBurnCall name source mint authority amountSource
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def splTokenApprove (name source delegate owner amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splTokenApproveCall name source delegate owner amountSource
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def invokeSplTokenApprove (name source delegate owner amountSource : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splTokenApproveCall name source delegate owner amountSource
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def splTokenRevoke (name source owner : String) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splTokenRevokeCall name source owner (tokenProgram := tokenProgram)
    (signerSeeds := signerSeeds))

def invokeSplTokenRevoke (name source owner : String) (tokenProgram : String := splTokenProgram)
    (signerSeeds : Array String := #[]) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splTokenRevokeCall name source owner (tokenProgram := tokenProgram)
    (signerSeeds := signerSeeds))

def splTokenCloseAccount (name account destination authority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splTokenCloseAccountCall name account destination authority
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def invokeSplTokenCloseAccount (name account destination authority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splTokenCloseAccountCall name account destination authority
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def splTokenSetAuthority (name account authority authorityType newAuthority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splTokenSetAuthorityCall name account authority authorityType newAuthority
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

def invokeSplTokenSetAuthority (name account authority authorityType newAuthority : String)
    (tokenProgram : String := splTokenProgram) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splTokenSetAuthorityCall name account authority authorityType newAuthority
    (tokenProgram := tokenProgram) (signerSeeds := signerSeeds))

end ProofForge.Solana
