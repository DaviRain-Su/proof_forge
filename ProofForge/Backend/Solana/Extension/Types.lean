import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Syscalls
import ProofForge.Target.Plan

namespace ProofForge.Backend.Solana.Extension

open ProofForge.Backend.Solana.StateLayout
open ProofForge.Target

structure AccountMeta where
  name : String
  access : String
  signer : String
  deriving Repr, Inhabited

structure DeclaredAccount where
  name : String
  access : String
  signer : String
  owner : String
  entrypoint? : Option String := none
  deriving Repr, Inhabited

structure PdaDerive where
  name : String
  seeds : Array String := #[]
  bump? : Option String := none
  account? : Option String := none
  signer : Bool := false
  entrypoint? : Option String := none
  deriving Repr, Inhabited

inductive PdaSeedKind where
  | literal
  | account
  | bump
  | instructionParam
  deriving BEq, DecidableEq, Repr, Inhabited

def PdaSeedKind.id : PdaSeedKind -> String
  | .literal => "literal"
  | .account => "account"
  | .bump => "bump"
  | .instructionParam => "instruction-param"

structure PdaSeed where
  kind : PdaSeedKind
  value : String
  raw : String
  deriving Repr, Inhabited

structure CpiInvoke where
  name : String
  program : String
  instruction : String
  accounts : Array AccountMeta := #[]
  signerSeeds : Array String := #[]
  protocol? : Option String := none
  dataLayout? : Option String := none
  metadata : Array TargetMetadata := #[]
  signed : Bool := false
  entrypoint? : Option String := none
  deriving Repr, Inhabited

inductive MemoryOp where
  | memcpy
  | memmove
  | memcmp
  | memset
  deriving BEq, DecidableEq, Repr, Inhabited

def MemoryOp.id : MemoryOp -> String
  | .memcpy => "memcpy"
  | .memmove => "memmove"
  | .memcmp => "memcmp"
  | .memset => "memset"

inductive CryptoHashOp where
  | sha256
  | keccak256
  | blake3
  deriving BEq, DecidableEq, Repr, Inhabited

def CryptoHashOp.id : CryptoHashOp -> String
  | .sha256 => "sha256"
  | .keccak256 => "keccak256"
  | .blake3 => "blake3"

def CryptoHashOp.syscall : CryptoHashOp -> String
  | .sha256 => ProofForge.Backend.Solana.Syscalls.sol_sha256
  | .keccak256 => ProofForge.Backend.Solana.Syscalls.sol_keccak256
  | .blake3 => ProofForge.Backend.Solana.Syscalls.sol_blake3

def CryptoHashOp.featureGated : CryptoHashOp -> Bool
  | .blake3 => true
  | _ => false

inductive SysvarKind where
  | rent
  | epochSchedule
  | epochRewards
  | lastRestartSlot
  deriving BEq, DecidableEq, Repr, Inhabited

def SysvarKind.id : SysvarKind -> String
  | .rent => "rent"
  | .epochSchedule => "epoch_schedule"
  | .epochRewards => "epoch_rewards"
  | .lastRestartSlot => "last_restart_slot"

def SysvarKind.syscall : SysvarKind -> String
  | .rent => ProofForge.Backend.Solana.Syscalls.sol_get_rent_sysvar
  | .epochSchedule => ProofForge.Backend.Solana.Syscalls.sol_get_epoch_schedule_sysvar
  | .epochRewards => ProofForge.Backend.Solana.Syscalls.sol_get_epoch_rewards_sysvar
  | .lastRestartSlot => ProofForge.Backend.Solana.Syscalls.sol_get_sysvar

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
  deriving BEq, DecidableEq, Repr, Inhabited

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
  entrypoint : String
  deriving Repr, Inhabited

structure CryptoHashAction where
  name : String
  op : CryptoHashOp
  inputState : String
  bytes : Nat
  outputStates : Array String := #[]
  featureGated : Bool := false
  entrypoint : String
  deriving Repr, Inhabited

structure SysvarReadAction where
  name : String
  kind : SysvarKind
  field : SysvarField
  outputState : String
  entrypoint : String
  deriving Repr, Inhabited

structure ReturnDataAction where
  name : String
  sourceState : String
  bytes : Nat
  entrypoint : String
  deriving Repr, Inhabited

structure ReturnDataReadAction where
  name : String
  destinationState : String
  maxBytes : Nat
  lengthState? : Option String := none
  programIdStates : Array String := #[]
  entrypoint : String
  deriving Repr, Inhabited

structure ComputeUnitsAction where
  name : String
  outputState : String
  featureGated : Bool := true
  entrypoint : String
  deriving Repr, Inhabited

structure ComputeUnitsLogAction where
  name : String
  entrypoint : String
  deriving Repr, Inhabited

structure ComputeBudgetAdvice where
  name : String
  unitLimit? : Option Nat := none
  unitPriceMicroLamports? : Option Nat := none
  entrypoint : String
  deriving Repr, Inhabited

structure PubkeyLogAction where
  name : String
  account : String
  entrypoint : String
  deriving Repr, Inhabited

structure DataLogAction where
  name : String
  sourceState : String
  bytes : Nat
  entrypoint : String
  deriving Repr, Inhabited

structure AccountReallocAction where
  name : String
  account : String
  newSize : Nat
  entrypoint : String
  deriving Repr, Inhabited

structure RuntimeAllocator where
  name : String
  config : ProofForge.IR.AllocatorConfig
  entrypoint? : Option String := none
  deriving Repr, Inhabited

def hexDigitValue (c : Char) : Option Nat :=
  if c.isDigit then some (c.toNat - '0'.toNat)
  else if c ≥ 'a' && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if c ≥ 'A' && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

def parseHex? (s : String) : Option Nat :=
  let chars := if s.startsWith "0x" then (s.drop 2).toString.toList else s.toList
  chars.foldl (fun acc c => do
    let n ← acc
    let d ← hexDigitValue c
    some (n * 16 + d)) (some 0)

def toHex (n : Nat) : String :=
  "0x" ++ String.ofList (Nat.toDigits 16 n)

def RuntimeAllocator.kind (allocator : RuntimeAllocator) : String :=
  match allocator.config.model.release, allocator.config.model.region.size? with
  | .none, some 0 => "none"
  | .none, _ => "none"
  | .noop, _ =>
      match allocator.config.model.strategy with
      | .bump | .bumpReset => "bump"
      | .freeList => "free_list"
      | .hostImport => "host_import"
  | .reuse, _ =>
      match allocator.config.model.strategy with
      | .freeList => "free_list"
      | .hostImport => "host_import"
      | _ => "bump"

def RuntimeAllocator.model (allocator : RuntimeAllocator) : String :=
  match allocator.config.model.release, allocator.config.model.region.size? with
  | .none, some 0 => "deny-dynamic"
  | .none, _ => "deny-dynamic"
  | .noop, _ =>
      match allocator.config.model.strategy with
      | .bumpReset => "bump-reset"
      | _ => "downward-bump"
  | .reuse, _ =>
      match allocator.config.model.strategy with
      | .freeList => "wee-alloc"
      | .hostImport => "cosmwasm-region"
      | _ => "downward-bump"

def RuntimeAllocator.heapStart (allocator : RuntimeAllocator) : String :=
  toHex allocator.config.model.region.base

def RuntimeAllocator.heapBytes (allocator : RuntimeAllocator) : String :=
  match allocator.config.model.region.size? with
  | some n => toString n
  | none => "32768"

structure PdaAction where
  name : String
  entrypoint : String
  deriving Repr, Inhabited

structure CpiAction where
  name : String
  entrypoint : String
  deriving Repr, Inhabited

structure TransferHookExtraAccountMetaListAction where
  name : String
  account : String
  extraAccounts : Array String := #[]
  entrypoint : String
  deriving Repr, Inhabited

structure ProgramExtensions where
  accountOrder : Array String := #[]
  accounts : Array DeclaredAccount := #[]
  allocators : Array RuntimeAllocator := #[]
  pdas : Array PdaDerive := #[]
  cpis : Array CpiInvoke := #[]
  pdaActions : Array PdaAction := #[]
  cpiActions : Array CpiAction := #[]
  memoryActions : Array MemoryAction := #[]
  cryptoHashActions : Array CryptoHashAction := #[]
  sysvarActions : Array SysvarReadAction := #[]
  returnDataActions : Array ReturnDataAction := #[]
  returnDataReadActions : Array ReturnDataReadAction := #[]
  computeUnitsActions : Array ComputeUnitsAction := #[]
  computeUnitsLogActions : Array ComputeUnitsLogAction := #[]
  computeBudgetActions : Array ComputeBudgetAdvice := #[]
  pubkeyLogActions : Array PubkeyLogAction := #[]
  dataLogActions : Array DataLogAction := #[]
  accountReallocActions : Array AccountReallocAction := #[]
  transferHookExtraAccountMetaListActions : Array TransferHookExtraAccountMetaListAction := #[]
  deriving Repr, Inhabited

structure CpiAccountBinding where
  name : String
  layout : AccountInputLayout
  deriving Repr, Inhabited

structure CpiValueBinding where
  name : String
  absOff : Nat
  byteSize : Nat := 8
  sourceKind : String := "state"
  relativeToInstructionData : Bool := false
  deriving Repr, Inhabited

end ProofForge.Backend.Solana.Extension
