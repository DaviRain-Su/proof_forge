import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Allocator
import ProofForge.Target

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

structure TransferHookExtraAccountMetaListAction where
  name : String
  account : String
  extraAccounts : Array String := #[]
  deriving Repr

end ProofForge.Solana
