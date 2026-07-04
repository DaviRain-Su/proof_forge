import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Syscalls
import ProofForge.Target.Plan

namespace ProofForge.Backend.Solana.Extension

open ProofForge.Backend.Solana.Asm
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

structure ProgramExtensions where
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

def metadataValue? (metadata : Array TargetMetadata) (key : String) : Option String :=
  metadata.foldl
    (fun found item =>
      match found with
      | some _ => found
      | none => if item.key == key then some item.value else none)
    none

def splitComma (value : String) : Array String :=
  value.splitOn "," |>.foldl
    (fun acc part => if part.isEmpty then acc else acc.push part)
    #[]

def parseSeedWithPrefix? (kind : PdaSeedKind) (marker raw : String) : Option PdaSeed :=
  if raw.startsWith marker then
    some { kind, value := raw.drop marker.length |>.toString, raw }
  else
    none

def parsePdaSeed (raw : String) : PdaSeed :=
  match parseSeedWithPrefix? .literal "literal:" raw with
  | some seed => seed
  | none =>
      match parseSeedWithPrefix? .literal "utf8:" raw with
      | some seed => seed
      | none =>
          match parseSeedWithPrefix? .account "account:" raw with
          | some seed => seed
          | none =>
              match parseSeedWithPrefix? .bump "bump:" raw with
              | some seed => seed
              | none =>
                  match parseSeedWithPrefix? .instructionParam "param:" raw with
                  | some seed => seed
                  | none =>
                      match parseSeedWithPrefix? .instructionParam "instruction:" raw with
                      | some seed => seed
                      | none => { kind := .literal, value := raw, raw }

def pdaMetadataSeeds (call : CapabilityCall) : Array String :=
  match metadataValue? call.metadata "solana.pda.seed_descriptors" with
  | some value => splitComma value
  | none => metadataValue? call.metadata "solana.pda.seeds" |>.map splitComma |>.getD #[]

def parseAccountMeta (encoded : String) : AccountMeta :=
  match encoded.splitOn ":" with
  | name :: access :: signer :: _ => { name, access, signer }
  | name :: access :: [] => { name, access, signer := "none" }
  | name :: [] => { name, access := "readonly", signer := "none" }
  | [] => { name := "", access := "readonly", signer := "none" }

def parseAccountMetas (encoded : String) : Array AccountMeta :=
  splitComma encoded |>.map parseAccountMeta

def boolFromString (value : String) : Bool :=
  value == "true"

def natFromMetadata? (metadata : Array TargetMetadata) (key : String) : Option Nat :=
  match metadataValue? metadata key with
  | some value => value.toNat?
  | none => none

def entrypoint? (call : CapabilityCall) : Option String :=
  metadataValue? call.metadata "proof_forge.entrypoint"

def memoryOpFromString? : String -> Option MemoryOp
  | "memcpy" => some .memcpy
  | "memmove" => some .memmove
  | "memcmp" => some .memcmp
  | "memset" => some .memset
  | _ => none

def cryptoHashOpFromString? : String -> Option CryptoHashOp
  | "sha256" => some .sha256
  | "keccak256" => some .keccak256
  | "blake3" => some .blake3
  | _ => none

def sysvarKindFromString? : String -> Option SysvarKind
  | "rent" => some .rent
  | "epoch_schedule" => some .epochSchedule
  | "epoch_rewards" => some .epochRewards
  | "last_restart_slot" => some .lastRestartSlot
  | _ => none

def sysvarFieldFromString? : String -> Option SysvarField
  | "lamports_per_byte_year" => some .rentLamportsPerByteYear
  | "slots_per_epoch" => some .epochScheduleSlotsPerEpoch
  | "leader_schedule_slot_offset" => some .epochScheduleLeaderScheduleSlotOffset
  | "warmup" => some .epochScheduleWarmup
  | "first_normal_epoch" => some .epochScheduleFirstNormalEpoch
  | "first_normal_slot" => some .epochScheduleFirstNormalSlot
  | "distribution_starting_block_height" => some .epochRewardsDistributionStartingBlockHeight
  | "num_partitions" => some .epochRewardsNumPartitions
  | "parent_blockhash_word0" => some .epochRewardsParentBlockhashWord0
  | "parent_blockhash_word1" => some .epochRewardsParentBlockhashWord1
  | "parent_blockhash_word2" => some .epochRewardsParentBlockhashWord2
  | "parent_blockhash_word3" => some .epochRewardsParentBlockhashWord3
  | "total_points_low" => some .epochRewardsTotalPointsLow
  | "total_points_high" => some .epochRewardsTotalPointsHigh
  | "total_rewards" => some .epochRewardsTotalRewards
  | "distributed_rewards" => some .epochRewardsDistributedRewards
  | "active" => some .epochRewardsActive
  | "last_restart_slot" => some .lastRestartSlot
  | _ => none

def PdaDerive.definition (pda : PdaDerive) : PdaDerive :=
  { pda with entrypoint? := none }

def CpiInvoke.definition (cpi : CpiInvoke) : CpiInvoke :=
  { cpi with
    entrypoint? := none
    metadata := cpi.metadata.filter (fun item => item.key != "proof_forge.entrypoint") }

def RuntimeAllocator.definition (allocator : RuntimeAllocator) : RuntimeAllocator :=
  { allocator with entrypoint? := none }

def DeclaredAccount.definition (account : DeclaredAccount) : DeclaredAccount :=
  { account with entrypoint? := none }

def mergeDeclaredAccess (existing incoming : String) : String :=
  if existing == "writable" || incoming == "writable" then
    "writable"
  else
    "readonly"

def mergeDeclaredSigner (existing incoming : String) : String :=
  if existing == "signer" || incoming == "signer" then
    "signer"
  else if existing == "pda-signer" || incoming == "pda-signer" then
    "pda-signer"
  else
    "none"

def mergeDeclaredOwner (existing incoming : String) : String :=
  if existing == incoming then
    existing
  else if existing == "any" then
    incoming
  else if incoming == "any" then
    existing
  else
    existing

def DeclaredAccount.merge (existing incoming : DeclaredAccount) : DeclaredAccount := {
  existing with
  access := mergeDeclaredAccess existing.access incoming.access
  signer := mergeDeclaredSigner existing.signer incoming.signer
  owner := mergeDeclaredOwner existing.owner incoming.owner
}

def ProgramExtensions.pushAccountDefinition (acc : ProgramExtensions)
    (account : DeclaredAccount) : ProgramExtensions :=
  let account := account.definition
  if acc.accounts.any (fun existing => existing.name == account.name) then
    { acc with
      accounts := acc.accounts.map fun existing =>
        if existing.name == account.name then
          existing.merge account
        else
          existing }
  else
    { acc with accounts := acc.accounts.push account }

def ProgramExtensions.pushAllocatorDefinition (acc : ProgramExtensions)
    (allocator : RuntimeAllocator) : ProgramExtensions :=
  if acc.allocators.any (fun existing => existing.name == allocator.name) then
    acc
  else
    { acc with allocators := acc.allocators.push allocator.definition }

def ProgramExtensions.pushPdaDefinition (acc : ProgramExtensions) (pda : PdaDerive) : ProgramExtensions :=
  if acc.pdas.any (fun existing => existing.name == pda.name) then
    acc
  else
    { acc with pdas := acc.pdas.push pda.definition }

def ProgramExtensions.pushCpiDefinition (acc : ProgramExtensions) (cpi : CpiInvoke) : ProgramExtensions :=
  if acc.cpis.any (fun existing => existing.name == cpi.name) then
    acc
  else
    { acc with cpis := acc.cpis.push cpi.definition }

def ProgramExtensions.pushPdaAction (acc : ProgramExtensions) (action : PdaAction) : ProgramExtensions :=
  if acc.pdaActions.any (fun existing => existing.name == action.name && existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with pdaActions := acc.pdaActions.push action }

def ProgramExtensions.pushCpiAction (acc : ProgramExtensions) (action : CpiAction) : ProgramExtensions :=
  if acc.cpiActions.any (fun existing => existing.name == action.name && existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with cpiActions := acc.cpiActions.push action }

def ProgramExtensions.pushMemoryAction (acc : ProgramExtensions)
    (action : MemoryAction) : ProgramExtensions :=
  if acc.memoryActions.any (fun existing =>
      existing.name == action.name &&
      existing.op == action.op &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with memoryActions := acc.memoryActions.push action }

def ProgramExtensions.pushCryptoHashAction (acc : ProgramExtensions)
    (action : CryptoHashAction) : ProgramExtensions :=
  if acc.cryptoHashActions.any (fun existing =>
      existing.name == action.name &&
      existing.op == action.op &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with cryptoHashActions := acc.cryptoHashActions.push action }

def ProgramExtensions.pushSysvarAction (acc : ProgramExtensions)
    (action : SysvarReadAction) : ProgramExtensions :=
  if acc.sysvarActions.any (fun existing =>
      existing.name == action.name &&
      existing.kind == action.kind &&
      existing.field == action.field &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with sysvarActions := acc.sysvarActions.push action }

def ProgramExtensions.pushReturnDataAction (acc : ProgramExtensions)
    (action : ReturnDataAction) : ProgramExtensions :=
  if acc.returnDataActions.any (fun existing =>
      existing.name == action.name &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with returnDataActions := acc.returnDataActions.push action }

def ProgramExtensions.pushReturnDataReadAction (acc : ProgramExtensions)
    (action : ReturnDataReadAction) : ProgramExtensions :=
  if acc.returnDataReadActions.any (fun existing =>
      existing.name == action.name &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with returnDataReadActions := acc.returnDataReadActions.push action }

def ProgramExtensions.pushComputeUnitsAction (acc : ProgramExtensions)
    (action : ComputeUnitsAction) : ProgramExtensions :=
  if acc.computeUnitsActions.any (fun existing =>
      existing.name == action.name &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with computeUnitsActions := acc.computeUnitsActions.push action }

def ProgramExtensions.pushComputeUnitsLogAction (acc : ProgramExtensions)
    (action : ComputeUnitsLogAction) : ProgramExtensions :=
  if acc.computeUnitsLogActions.any (fun existing =>
      existing.name == action.name &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with computeUnitsLogActions := acc.computeUnitsLogActions.push action }

def ProgramExtensions.pushComputeBudgetAdvice (acc : ProgramExtensions)
    (action : ComputeBudgetAdvice) : ProgramExtensions :=
  if acc.computeBudgetActions.any (fun existing =>
      existing.name == action.name &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with computeBudgetActions := acc.computeBudgetActions.push action }

def ProgramExtensions.pushPubkeyLogAction (acc : ProgramExtensions)
    (action : PubkeyLogAction) : ProgramExtensions :=
  if acc.pubkeyLogActions.any (fun existing =>
      existing.name == action.name &&
      existing.account == action.account &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with pubkeyLogActions := acc.pubkeyLogActions.push action }

def ProgramExtensions.pushDataLogAction (acc : ProgramExtensions)
    (action : DataLogAction) : ProgramExtensions :=
  if acc.dataLogActions.any (fun existing =>
      existing.name == action.name &&
      existing.sourceState == action.sourceState &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with dataLogActions := acc.dataLogActions.push action }

def ProgramExtensions.pushAccountReallocAction (acc : ProgramExtensions)
    (action : AccountReallocAction) : ProgramExtensions :=
  if acc.accountReallocActions.any (fun existing =>
      existing.name == action.name &&
      existing.account == action.account &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with accountReallocActions := acc.accountReallocActions.push action }

def ProgramExtensions.addPda (acc : ProgramExtensions) (pda : PdaDerive) : ProgramExtensions :=
  let acc := acc.pushPdaDefinition pda
  match pda.entrypoint? with
  | some entrypoint => acc.pushPdaAction { name := pda.name, entrypoint := entrypoint }
  | none => acc

def ProgramExtensions.addCpi (acc : ProgramExtensions) (cpi : CpiInvoke) : ProgramExtensions :=
  let acc := acc.pushCpiDefinition cpi
  match cpi.entrypoint? with
  | some entrypoint => acc.pushCpiAction { name := cpi.name, entrypoint := entrypoint }
  | none => acc

def ProgramExtensions.addAllocator (acc : ProgramExtensions)
    (allocator : RuntimeAllocator) : ProgramExtensions :=
  acc.pushAllocatorDefinition allocator

def ProgramExtensions.addMemory (acc : ProgramExtensions)
    (action : MemoryAction) : ProgramExtensions :=
  acc.pushMemoryAction action

def ProgramExtensions.addCryptoHash (acc : ProgramExtensions)
    (action : CryptoHashAction) : ProgramExtensions :=
  acc.pushCryptoHashAction action

def ProgramExtensions.addSysvar (acc : ProgramExtensions)
    (action : SysvarReadAction) : ProgramExtensions :=
  acc.pushSysvarAction action

def ProgramExtensions.addReturnData (acc : ProgramExtensions)
    (action : ReturnDataAction) : ProgramExtensions :=
  acc.pushReturnDataAction action

def ProgramExtensions.addReturnDataRead (acc : ProgramExtensions)
    (action : ReturnDataReadAction) : ProgramExtensions :=
  acc.pushReturnDataReadAction action

def ProgramExtensions.addComputeUnits (acc : ProgramExtensions)
    (action : ComputeUnitsAction) : ProgramExtensions :=
  acc.pushComputeUnitsAction action

def ProgramExtensions.addComputeUnitsLog (acc : ProgramExtensions)
    (action : ComputeUnitsLogAction) : ProgramExtensions :=
  acc.pushComputeUnitsLogAction action

def ProgramExtensions.addComputeBudget (acc : ProgramExtensions)
    (action : ComputeBudgetAdvice) : ProgramExtensions :=
  acc.pushComputeBudgetAdvice action

def ProgramExtensions.addPubkeyLog (acc : ProgramExtensions)
    (action : PubkeyLogAction) : ProgramExtensions :=
  acc.pushPubkeyLogAction action

def ProgramExtensions.addDataLog (acc : ProgramExtensions)
    (action : DataLogAction) : ProgramExtensions :=
  acc.pushDataLogAction action

def ProgramExtensions.addAccountRealloc (acc : ProgramExtensions)
    (action : AccountReallocAction) : ProgramExtensions :=
  acc.pushAccountReallocAction action

def ProgramExtensions.addDeclaredAccount (acc : ProgramExtensions)
    (account : DeclaredAccount) : ProgramExtensions :=
  acc.pushAccountDefinition account

def declaredAccountFromCall? (call : CapabilityCall) : Option DeclaredAccount :=
  if call.capability == .accountExplicit &&
      metadataValue? call.metadata "solana.extension" == some "account" then
    let name := metadataValue? call.metadata "solana.account.name" |>.getD call.operation
    some {
      name := name
      access := metadataValue? call.metadata "solana.account.access" |>.getD "readonly"
      signer := metadataValue? call.metadata "solana.account.signer" |>.getD "none"
      -- Default owner is the current program (`"program"`), not `"any"`.
      -- `"any"` skips the on-chain owner check entirely, which is unsafe as a
      -- default for user-declared accounts: a missing `solana.account.owner`
      -- metadata value used to silently disable owner verification.
      owner := metadataValue? call.metadata "solana.account.owner" |>.getD "program"
      entrypoint? := entrypoint? call
    }
  else
    none

def allocatorFromCall? (call : CapabilityCall) : Option RuntimeAllocator :=
  if call.capability == .runtimeAllocator then
    let name := metadataValue? call.metadata "solana.allocator.name" |>.getD "runtime"
    let kind := metadataValue? call.metadata "solana.allocator.kind" |>.getD "bump"
    let heapStartStr := metadataValue? call.metadata "solana.allocator.heap_start" |>.getD "0x300000000"
    let heapBytesStr := metadataValue? call.metadata "solana.allocator.heap_bytes" |>.getD "32768"
    let modelStr := metadataValue? call.metadata "solana.allocator.model" |>.getD "downward-bump"
    let base := parseHex? heapStartStr |>.getD 0x300000000
    let size := heapBytesStr.toNat? |>.getD 32768
    let (strategy, release) :=
      match kind, modelStr with
      | "none", "deny-dynamic" =>
          (ProofForge.IR.AllocatorStrategy.bump, ProofForge.IR.AllocatorRelease.none)
      | "bump", "bump-reset" =>
          (ProofForge.IR.AllocatorStrategy.bumpReset, ProofForge.IR.AllocatorRelease.noop)
      | "bump", _ =>
          (ProofForge.IR.AllocatorStrategy.bump, ProofForge.IR.AllocatorRelease.noop)
      | "free_list", _ =>
          (ProofForge.IR.AllocatorStrategy.freeList, ProofForge.IR.AllocatorRelease.reuse)
      | "host_import", _ =>
          (ProofForge.IR.AllocatorStrategy.hostImport, ProofForge.IR.AllocatorRelease.reuse)
      | _, _ =>
          (ProofForge.IR.AllocatorStrategy.bump, ProofForge.IR.AllocatorRelease.noop)
    some {
      name := name
      config := {
        model := {
          strategy := strategy
          region := { base := base, size? := some size, growable := false }
          release := release
        }
      }
      entrypoint? := entrypoint? call
    }
  else
    none

def pdaFromCall? (call : CapabilityCall) : Option PdaDerive :=
  if call.operation == "solana.pda.derive" then
    let name := metadataValue? call.metadata "solana.pda.name" |>.getD call.operation
    some {
      name := name
      seeds := pdaMetadataSeeds call
      bump? := metadataValue? call.metadata "solana.pda.bump"
      account? := metadataValue? call.metadata "solana.pda.account"
      signer := metadataValue? call.metadata "solana.pda.signer" |>.map boolFromString |>.getD false
      entrypoint? := entrypoint? call
    }
  else
    none

def cpiFromCall? (call : CapabilityCall) : Option CpiInvoke :=
  if call.capability == .crosscallCpi then
    let name := metadataValue? call.metadata "solana.cpi.name" |>.getD call.operation
    let program := metadataValue? call.metadata "solana.cpi.program" |>.getD ""
    let instruction := metadataValue? call.metadata "solana.cpi.instruction" |>.getD ""
    some {
      name := name
      program := program
      instruction := instruction
      accounts := metadataValue? call.metadata "solana.cpi.accounts" |>.map parseAccountMetas |>.getD #[]
      signerSeeds := metadataValue? call.metadata "solana.cpi.signer_seeds" |>.map splitComma |>.getD #[]
      protocol? := metadataValue? call.metadata "solana.cpi.protocol"
      dataLayout? := metadataValue? call.metadata "solana.cpi.data_layout"
      metadata := call.metadata
      signed := call.operation == "solana.cpi.invoke_signed"
      entrypoint? := entrypoint? call
    }
  else
    none

def memoryFromCall? (call : CapabilityCall) : Option MemoryAction :=
  if call.capability == .runtimeMemory then
    match entrypoint? call, metadataValue? call.metadata "solana.memory.op" >>= memoryOpFromString? with
    | some entrypoint, some op =>
        some {
          name := metadataValue? call.metadata "solana.memory.name" |>.getD call.operation
          op := op
          dstState? := metadataValue? call.metadata "solana.memory.dst_state"
          srcState? := metadataValue? call.metadata "solana.memory.src_state"
          lhsState? := metadataValue? call.metadata "solana.memory.lhs_state"
          rhsState? := metadataValue? call.metadata "solana.memory.rhs_state"
          resultState? := metadataValue? call.metadata "solana.memory.result_state"
          bytes := natFromMetadata? call.metadata "solana.memory.bytes" |>.getD 0
          value? := natFromMetadata? call.metadata "solana.memory.value"
          entrypoint := entrypoint
        }
    | _, _ => none
  else
    none

def cryptoHashFromCall? (call : CapabilityCall) : Option CryptoHashAction :=
  if call.capability == .cryptoHash &&
      metadataValue? call.metadata "solana.extension" == some "crypto" then
    match entrypoint? call, metadataValue? call.metadata "solana.crypto.op" >>= cryptoHashOpFromString? with
    | some entrypoint, some op =>
        some {
          name := metadataValue? call.metadata "solana.crypto.name" |>.getD call.operation
          op := op
          inputState := metadataValue? call.metadata "solana.crypto.input_state" |>.getD ""
          bytes := natFromMetadata? call.metadata "solana.crypto.bytes" |>.getD 0
          outputStates := metadataValue? call.metadata "solana.crypto.output_states" |>.map splitComma |>.getD #[]
          featureGated := metadataValue? call.metadata "solana.crypto.feature_gated"
            |>.map boolFromString |>.getD op.featureGated
          entrypoint := entrypoint
        }
    | _, _ => none
  else
    none

def sysvarFromCall? (call : CapabilityCall) : Option SysvarReadAction :=
  if call.capability == .envBlock &&
      metadataValue? call.metadata "solana.extension" == some "sysvar" then
    match entrypoint? call,
        metadataValue? call.metadata "solana.sysvar.kind" >>= sysvarKindFromString?,
        metadataValue? call.metadata "solana.sysvar.field" >>= sysvarFieldFromString? with
    | some entrypoint, some kind, some field =>
        if field.kind == kind then
          some {
            name := metadataValue? call.metadata "solana.sysvar.name" |>.getD call.operation
            kind := kind
            field := field
            outputState := metadataValue? call.metadata "solana.sysvar.output_state" |>.getD ""
            entrypoint := entrypoint
          }
        else
          none
    | _, _, _ => none
  else
    none

def returnDataFromCall? (call : CapabilityCall) : Option ReturnDataAction :=
  if call.capability == .runtimeReturnData &&
      metadataValue? call.metadata "solana.extension" == some "return_data" &&
      metadataValue? call.metadata "solana.return_data.op" == some "set" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.return_data.name" |>.getD call.operation
          sourceState := metadataValue? call.metadata "solana.return_data.source_state" |>.getD ""
          bytes := natFromMetadata? call.metadata "solana.return_data.bytes" |>.getD 0
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def returnDataReadFromCall? (call : CapabilityCall) : Option ReturnDataReadAction :=
  if call.capability == .runtimeReturnData &&
      metadataValue? call.metadata "solana.extension" == some "return_data" &&
      metadataValue? call.metadata "solana.return_data.op" == some "get" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.return_data.name" |>.getD call.operation
          destinationState := metadataValue? call.metadata "solana.return_data.destination_state" |>.getD ""
          maxBytes := natFromMetadata? call.metadata "solana.return_data.max_bytes" |>.getD 0
          lengthState? := metadataValue? call.metadata "solana.return_data.length_state"
          programIdStates := metadataValue? call.metadata "solana.return_data.program_id_states"
            |>.map splitComma |>.getD #[]
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def computeUnitsFromCall? (call : CapabilityCall) : Option ComputeUnitsAction :=
  if call.capability == .runtimeComputeUnits &&
      metadataValue? call.metadata "solana.extension" == some "compute_units" &&
      metadataValue? call.metadata "solana.compute_units.op" == some "remaining" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.compute_units.name" |>.getD call.operation
          outputState := metadataValue? call.metadata "solana.compute_units.output_state" |>.getD ""
          featureGated := metadataValue? call.metadata "solana.compute_units.feature_gated"
            |>.map boolFromString |>.getD true
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def computeUnitsLogFromCall? (call : CapabilityCall) : Option ComputeUnitsLogAction :=
  if call.capability == .runtimeComputeUnits &&
      metadataValue? call.metadata "solana.extension" == some "compute_units" &&
      metadataValue? call.metadata "solana.compute_units.op" == some "log_remaining" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.compute_units.name" |>.getD call.operation
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def computeBudgetFromCall? (call : CapabilityCall) : Option ComputeBudgetAdvice :=
  if call.capability == .runtimeComputeUnits &&
      metadataValue? call.metadata "solana.extension" == some "compute_budget" &&
      metadataValue? call.metadata "solana.compute_budget.op" == some "instruction" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.compute_budget.name" |>.getD call.operation
          unitLimit? := natFromMetadata? call.metadata "solana.compute_budget.unit_limit"
          unitPriceMicroLamports? :=
            natFromMetadata? call.metadata "solana.compute_budget.unit_price_micro_lamports"
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def pubkeyLogFromCall? (call : CapabilityCall) : Option PubkeyLogAction :=
  if call.capability == .eventsEmit &&
      metadataValue? call.metadata "solana.extension" == some "log" &&
      metadataValue? call.metadata "solana.log.op" == some "pubkey" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.log.name" |>.getD call.operation
          account := metadataValue? call.metadata "solana.log.account" |>.getD ""
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def dataLogFromCall? (call : CapabilityCall) : Option DataLogAction :=
  if call.capability == .eventsEmit &&
      metadataValue? call.metadata "solana.extension" == some "log" &&
      metadataValue? call.metadata "solana.log.op" == some "data" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.log.name" |>.getD call.operation
          sourceState := metadataValue? call.metadata "solana.log.source_state" |>.getD ""
          bytes := natFromMetadata? call.metadata "solana.log.bytes" |>.getD 0
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def accountReallocFromCall? (call : CapabilityCall) : Option AccountReallocAction :=
  if call.capability == .accountExplicit &&
      metadataValue? call.metadata "solana.extension" == some "account_realloc" then
    match entrypoint? call with
    | some entrypoint =>
        some {
          name := metadataValue? call.metadata "solana.account_realloc.name" |>.getD call.operation
          account := metadataValue? call.metadata "solana.account_realloc.account" |>.getD ""
          newSize := natFromMetadata? call.metadata "solana.account_realloc.new_size" |>.getD 0
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def ProgramExtensions.fromPlan (plan : CapabilityPlan) : ProgramExtensions :=
  plan.calls.foldl
    (fun acc call =>
      let acc :=
        match declaredAccountFromCall? call with
        | some account => acc.addDeclaredAccount account
        | none => acc
      let acc :=
        match allocatorFromCall? call with
        | some allocator => acc.addAllocator allocator
        | none => acc
      let acc :=
        match pdaFromCall? call with
        | some pda => acc.addPda pda
        | none => acc
      let acc :=
        match cpiFromCall? call with
        | some cpi => acc.addCpi cpi
        | none => acc
      let acc :=
        match memoryFromCall? call with
        | some action => acc.addMemory action
        | none => acc
      let acc :=
        match cryptoHashFromCall? call with
        | some action => acc.addCryptoHash action
        | none => acc
      let acc :=
        match sysvarFromCall? call with
        | some action => acc.addSysvar action
        | none => acc
      let acc :=
        match returnDataFromCall? call with
        | some action => acc.addReturnData action
        | none => acc
      let acc :=
        match returnDataReadFromCall? call with
        | some action => acc.addReturnDataRead action
        | none => acc
      let acc :=
        match computeUnitsFromCall? call with
        | some action => acc.addComputeUnits action
        | none => acc
      let acc :=
        match computeUnitsLogFromCall? call with
        | some action => acc.addComputeUnitsLog action
        | none => acc
      let acc :=
        match computeBudgetFromCall? call with
        | some action => acc.addComputeBudget action
        | none => acc
      let acc :=
        match pubkeyLogFromCall? call with
        | some action => acc.addPubkeyLog action
        | none => acc
      let acc :=
        match dataLogFromCall? call with
        | some action => acc.addDataLog action
        | none => acc
      match accountReallocFromCall? call with
      | some action => acc.addAccountRealloc action
      | none => acc)
    {}

def hasExtensions (extensions : ProgramExtensions) : Bool :=
  extensions.accounts.size > 0 ||
    extensions.allocators.size > 0 ||
    extensions.pdas.size > 0 ||
    extensions.cpis.size > 0 ||
    extensions.memoryActions.size > 0 ||
    extensions.cryptoHashActions.size > 0 ||
    extensions.sysvarActions.size > 0 ||
    extensions.returnDataActions.size > 0 ||
    extensions.returnDataReadActions.size > 0 ||
    extensions.computeUnitsActions.size > 0 ||
    extensions.computeUnitsLogActions.size > 0 ||
    extensions.computeBudgetActions.size > 0 ||
    extensions.pubkeyLogActions.size > 0 ||
    extensions.dataLogActions.size > 0 ||
    extensions.accountReallocActions.size > 0

def hasSyscallExtensions (extensions : ProgramExtensions) : Bool :=
  extensions.pdas.size > 0 ||
    extensions.cpis.size > 0 ||
    extensions.memoryActions.size > 0 ||
    extensions.cryptoHashActions.size > 0 ||
    extensions.sysvarActions.size > 0 ||
    extensions.returnDataActions.size > 0 ||
    extensions.returnDataReadActions.size > 0 ||
    extensions.computeUnitsActions.size > 0 ||
    extensions.computeUnitsLogActions.size > 0 ||
    extensions.pubkeyLogActions.size > 0 ||
    extensions.dataLogActions.size > 0 ||
    extensions.accountReallocActions.size > 0

def hasEntrypointActions (extensions : ProgramExtensions) : Bool :=
  extensions.pdaActions.size > 0 ||
    extensions.cpiActions.size > 0 ||
    extensions.memoryActions.size > 0 ||
    extensions.cryptoHashActions.size > 0 ||
    extensions.sysvarActions.size > 0 ||
    extensions.returnDataActions.size > 0 ||
    extensions.returnDataReadActions.size > 0 ||
    extensions.computeUnitsActions.size > 0 ||
    extensions.computeUnitsLogActions.size > 0 ||
    extensions.pubkeyLogActions.size > 0 ||
    extensions.dataLogActions.size > 0 ||
    extensions.accountReallocActions.size > 0

def labelPart (name : String) : String :=
  let chars := name.toList.map fun ch =>
    if ch.isAlphanum || ch == '_' then ch else '_'
  String.ofList chars

def PdaDerive.label (pda : PdaDerive) : String :=
  "sol_pda_derive_" ++ labelPart pda.name

def CpiInvoke.label (cpi : CpiInvoke) : String :=
  "sol_cpi_" ++ labelPart cpi.name

def MemoryAction.label (action : MemoryAction) : String :=
  "sol_memory_" ++ action.op.id ++ "_" ++ labelPart action.name

def CryptoHashAction.label (action : CryptoHashAction) : String :=
  "sol_crypto_" ++ action.op.id ++ "_" ++ labelPart action.name

def SysvarReadAction.label (action : SysvarReadAction) : String :=
  "sol_sysvar_" ++ action.kind.id ++ "_" ++ labelPart action.name

def ReturnDataAction.label (action : ReturnDataAction) : String :=
  "sol_return_data_set_" ++ labelPart action.name

def ReturnDataReadAction.label (action : ReturnDataReadAction) : String :=
  "sol_return_data_get_" ++ labelPart action.name

def ComputeUnitsAction.label (action : ComputeUnitsAction) : String :=
  "sol_compute_units_remaining_" ++ labelPart action.name

def ComputeUnitsLogAction.label (action : ComputeUnitsLogAction) : String :=
  "sol_compute_units_log_" ++ labelPart action.name

def PubkeyLogAction.label (action : PubkeyLogAction) : String :=
  "sol_log_pubkey_" ++ labelPart action.name

def DataLogAction.label (action : DataLogAction) : String :=
  "sol_log_data_" ++ labelPart action.name

def AccountReallocAction.label (action : AccountReallocAction) : String :=
  "sol_account_realloc_" ++ labelPart action.name

def callSyscall (name : String) : AstNode :=
  .instruction { opcode := .call, imm := some (.sym name) }

def callHelper (name : String) : AstNode :=
  .instruction { opcode := .call, imm := some (.sym name) }

def stackPtr (dst : Reg) (offset : Nat) : Array AstNode := #[
  .instruction { opcode := .mov64, dst := some dst, src := some .r10 },
  .instruction { opcode := .sub64, dst := some dst, imm := some (.num offset) }
]

def entryInputSaveOffset : Nat := 3520
def accountPtrTableOffset : Nat := 3328
def entryInstructionDataSaveOffset : Nat := 3584
def entryInstructionDataReg : Reg := .r9

def loadSavedInstructionDataPtr (dst : Reg) : Array AstNode :=
  if dst == entryInstructionDataReg then
    #[]
  else
    #[.instruction { opcode := .mov64, dst := some dst, src := some entryInstructionDataReg }]

def loadCurrentProgramIdPtr (dst scratch : Reg) : Array AstNode :=
  loadSavedInstructionDataPtr dst ++ #[
    .instruction { opcode := .mov64, dst := some scratch, src := some dst },
    .instruction { opcode := .sub64, dst := some scratch, imm := some (.num 8) },
    .instruction { opcode := .ldxdw, dst := some scratch, src := some scratch, off := some (.num 0) },
    .instruction { opcode := .add64, dst := some dst, src := some scratch }
  ]

def pdaResultOffset : Nat := 64
def pdaSeedTableOffset : Nat := 128
def pdaSeedDataOffset : Nat := 512
def pdaMaxSeedLen : Nat := 32
def pdaMaxSeeds : Nat := 16

def cpiInstructionOffset : Nat := 64
def cpiAccountMetaOffset : Nat := 128
def cpiInstructionDataOffset : Nat := 384
def cpiProgramIdOffset : Nat := 512
def cpiPlaceholderPubkeyOffset : Nat := 576
def cpiAccountInfoOffset : Nat := 1152
def cpiPlaceholderLamportsOffset : Nat := 2112
def cpiSignerEntriesOffset : Nat := 2304
def cpiSignerSeedTableOffset : Nat := 2368
def cpiSignerSeedDataOffset : Nat := 2880
def cpiMaxSeedLen : Nat := 32
def cryptoSliceTableOffset : Nat := 3072
def cryptoResultOffset : Nat := 3104
def sysvarResultOffset : Nat := 3008
def sysvarIdOffset : Nat := 3040
def memoryResultOffset : Nat := 3200
def returnDataScratchOffset : Nat := 2048
def returnDataProgramIdOffset : Nat := 3104
def logDataSliceTableOffset : Nat := 3072

def lastRestartSlotSysvarIdBytes : Array Nat :=
  #[6, 167, 213, 23, 25, 6, 221, 225,
    205, 63, 148, 125, 202, 180, 200, 244,
    244, 245, 27, 173, 15, 152, 19, 184,
    0, 210, 137, 71, 31, 192, 0, 0]

def cpiAccountBinding? (bindings : Array CpiAccountBinding) (name : String) :
    Option CpiAccountBinding :=
  bindings.find? (fun binding => binding.name == name)

def cpiValueBinding? (bindings : Array CpiValueBinding) (name : String) :
    Option CpiValueBinding :=
  bindings.find? (fun binding => binding.name == name)

def stateValueBinding? (bindings : Array CpiValueBinding) (name : String) :
    Option CpiValueBinding :=
  bindings.find? (fun binding =>
    binding.name == name &&
    binding.sourceKind == "state" &&
    !binding.relativeToInstructionData)

def inputPtr (dst : Reg) (off : Nat) : Array AstNode := #[
  .instruction { opcode := .mov64, dst := some dst, src := some .r1 },
  .instruction { opcode := .add64, dst := some dst, imm := some (.num off) }
]

def inputAccountPtr (dst : Reg) (idx : Nat) : Array AstNode :=
  stackPtr dst accountPtrTableOffset ++ #[
    .instruction { opcode := .ldxdw, dst := some dst, src := some dst, off := some (.num (idx * 8)) }
  ]

def inputAccountFieldPtr (dst : Reg) (layout : AccountInputLayout) (absOff : Nat) : Array AstNode :=
  inputAccountPtr dst layout.index ++ #[
    .instruction { opcode := .add64, dst := some dst, imm := some (.num (absOff - layout.accountStart)) }
  ]

def lowerAccountScanStep (labelPrefix : String) (idx : Nat) : Array AstNode :=
  let alignedLabel := s!"{labelPrefix}_account_scan_{idx}_aligned"
  stackPtr .r6 accountPtrTableOffset ++ #[
    .instruction { opcode := .stxdw, dst := some .r6, off := some (.num (idx * 8)), src := some .r3 },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r3, off := some (.num 80) },
    .instruction { opcode := .add64, dst := some .r3, imm := some (.num 88) },
    .instruction { opcode := .add64, dst := some .r3, src := some .r4 },
    .instruction { opcode := .add64, dst := some .r3, imm := some (.num MAX_PERMITTED_DATA_INCREASE) },
    .instruction { opcode := .add64, dst := some .r3, imm := some (.num U64_SIZE) },
    .instruction { opcode := .mov64, dst := some .r5, src := some .r3 },
    .instruction { opcode := .and64, dst := some .r5, imm := some (.num 7) },
    .instruction { opcode := .jeq, dst := some .r5, imm := some (.num 0), off := some (.sym alignedLabel) },
    .instruction { opcode := .mov64, dst := some .r6, imm := some (.num 8) },
    .instruction { opcode := .sub64, dst := some .r6, src := some .r5 },
    .instruction { opcode := .add64, dst := some .r3, src := some .r6 },
    .label alignedLabel
  ]

def lowerAccountPtrTableSetup (labelPrefix : String) (accountCount : Nat) : Array AstNode :=
  let scanSteps :=
    (List.range accountCount).foldl (fun acc idx => acc ++ lowerAccountScanStep labelPrefix idx) #[]
  #[
    .comment "scan Solana input account pointers into current stack frame",
    .instruction { opcode := .mov64, dst := some .r3, src := some .r1 },
    .instruction { opcode := .add64, dst := some .r3, imm := some (.num U64_SIZE) }
  ] ++ scanSteps

def PdaDerive.explicitSeeds (pda : PdaDerive) : Array PdaSeed :=
  pda.seeds.map parsePdaSeed

def PdaDerive.effectiveSeeds (pda : PdaDerive) : Array PdaSeed :=
  let seeds := pda.explicitSeeds
  match pda.bump? with
  | some bump =>
      if seeds.any (fun seed => seed.kind == .bump && seed.value == bump) then
        seeds
      else
        seeds.push { kind := .bump, value := bump, raw := "bump:" ++ bump }
  | none => seeds

def PdaDerive.seedValues (pda : PdaDerive) : Array String :=
  pda.explicitSeeds.map (fun seed => seed.value)

def stringBytes (value : String) : Array Nat :=
  value.toList.foldl (fun acc ch => acc.push ch.toNat) #[]

def lowerSeedBytes (seed : String) (base : Reg) : Array AstNode :=
  stringBytes seed |>.mapIdx (fun idx byte =>
    .instruction {
      opcode := .stb,
      dst := some base,
      off := some (.num idx),
      imm := some (.num byte)
    })

def lowerPdaStackSeedPtr (idx : Nat) : Array AstNode :=
  stackPtr .r5 (pdaSeedDataOffset + idx * pdaMaxSeedLen)

def lowerPdaSeedTableEntry (idx len : Nat) : Array AstNode :=
  let tableOffset := pdaSeedTableOffset + idx * 16
  stackPtr .r6 tableOffset ++ #[
    .instruction { opcode := .stxdw, dst := some .r6, off := some (.num 0), src := some .r5 },
    .instruction { opcode := .mov64, dst := some .r3, imm := some (.num len) },
    .instruction { opcode := .stxdw, dst := some .r6, off := some (.num 8), src := some .r3 }
  ]

def lowerInputBytesToPdaSeed (binding : CpiValueBinding) (byteSize : Nat) : Array AstNode :=
  let base :=
    if binding.relativeToInstructionData then
      loadSavedInstructionDataPtr .r7
    else
      #[.instruction { opcode := .mov64, dst := some .r7, src := some .r1 }]
  base ++
  (List.range byteSize).foldl
    (fun acc idx =>
      acc ++ #[
        .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num (binding.absOff + idx)) },
        .instruction { opcode := .stxb, dst := some .r5, off := some (.num idx), src := some .r3 }
      ])
    #[]

def lowerPdaZeroSeedBytes (byteSize : Nat) : Array AstNode :=
  (List.range byteSize).foldl
    (fun acc idx =>
      acc.push <| .instruction {
        opcode := .stb,
        dst := some .r5,
        off := some (.num idx),
        imm := some (.num 0)
      })
    #[]

def lowerPdaStaticSeed (pdaName : String) (idx : Nat) (seed : String) : Array AstNode :=
  let bytes := stringBytes seed
  #[
    .comment s!"solana.pda.seed {pdaName}[{idx}] \"{seed}\"",
  ] ++
  lowerPdaStackSeedPtr idx ++
  lowerSeedBytes seed .r5 ++
  lowerPdaSeedTableEntry idx bytes.size

def lowerPdaAccountSeed (bindings : Array CpiAccountBinding) (pdaName : String)
    (idx : Nat) (account : String) : Array AstNode :=
  match cpiAccountBinding? bindings account with
  | some binding =>
      #[
        .comment s!"solana.pda.seed {pdaName}[{idx}] account {account} pubkey"
      ] ++
      inputAccountFieldPtr .r5 binding.layout binding.layout.keyOff ++
      lowerPdaSeedTableEntry idx 32
  | none =>
      #[
        .comment s!"solana.pda.seed {pdaName}[{idx}] account {account} missing placeholder=zero"
      ] ++
      lowerPdaStackSeedPtr idx ++
      lowerPdaZeroSeedBytes 32 ++
      lowerPdaSeedTableEntry idx 32

def lowerPdaValueSeed (pdaName : String) (idx : Nat) (kind source : String)
    (binding : CpiValueBinding) (byteSize : Nat) : Array AstNode :=
  #[
    .comment s!"solana.pda.seed {pdaName}[{idx}] {kind} {source} from {binding.sourceKind}"
  ] ++
  lowerPdaStackSeedPtr idx ++
  lowerInputBytesToPdaSeed binding byteSize ++
  lowerPdaSeedTableEntry idx byteSize

def lowerPdaBumpSeed (bindings : Array CpiValueBinding) (pdaName : String)
    (idx : Nat) (source : String) : Array AstNode :=
  match source.toNat? with
  | some bump =>
      if bump < 256 then
        #[
          .comment s!"solana.pda.seed {pdaName}[{idx}] bump literal={bump}"
        ] ++
        lowerPdaStackSeedPtr idx ++ #[
          .instruction { opcode := .stb, dst := some .r5, off := some (.num 0), imm := some (.num bump) }
        ] ++
        lowerPdaSeedTableEntry idx 1
      else
        -- Out-of-range bump: revert instead of silently emitting a 255
        -- placeholder that would derive the wrong PDA and likely cause the
        -- program to act on an attacker-controlled account.
        #[
          .comment s!"solana.pda.seed {pdaName}[{idx}] bump literal={bump} out-of-range (revert)",
          .instruction { opcode := .ja, off := some (.sym "error_pda_bump") }
        ]
  | none =>
      match cpiValueBinding? bindings source with
      | some binding => lowerPdaValueSeed pdaName idx "bump" source binding 1
      | none =>
          -- Missing bump binding: revert instead of silently emitting 255.
          #[
            .comment s!"solana.pda.seed {pdaName}[{idx}] bump {source} missing (revert)",
            .instruction { opcode := .ja, off := some (.sym "error_pda_bump") }
          ]

def lowerPdaInstructionParamSeed (bindings : Array CpiValueBinding) (pdaName : String)
    (idx : Nat) (source : String) : Array AstNode :=
  match cpiValueBinding? bindings source with
  | some binding => lowerPdaValueSeed pdaName idx "instruction-param" source binding binding.byteSize
  | none =>
      #[
        .comment s!"solana.pda.seed {pdaName}[{idx}] instruction-param {source} missing placeholder=zero"
      ] ++
      lowerPdaStackSeedPtr idx ++
      lowerPdaZeroSeedBytes 1 ++
      lowerPdaSeedTableEntry idx 1

def lowerPdaSeed (accountBindings : Array CpiAccountBinding) (valueBindings : Array CpiValueBinding)
    (pdaName : String) (idx : Nat) (seed : PdaSeed) : Array AstNode :=
  match seed.kind with
  | .literal => lowerPdaStaticSeed pdaName idx seed.value
  | .account => lowerPdaAccountSeed accountBindings pdaName idx seed.value
  | .bump => lowerPdaBumpSeed valueBindings pdaName idx seed.value
  | .instructionParam => lowerPdaInstructionParamSeed valueBindings pdaName idx seed.value

def lowerPdaSeeds (accountBindings : Array CpiAccountBinding) (valueBindings : Array CpiValueBinding)
    (pda : PdaDerive) : Array AstNode :=
  pda.effectiveSeeds.mapIdx (fun idx seed => lowerPdaSeed accountBindings valueBindings pda.name idx seed)
    |>.foldl (fun acc nodes => acc ++ nodes) #[]

def lowerPdaResultAccountValidation (accountBindings : Array CpiAccountBinding)
    (pda : PdaDerive) : Array AstNode :=
  match pda.account? with
  | none => #[]
  | some account =>
      match cpiAccountBinding? accountBindings account with
      | none =>
          #[
            .comment s!"solana.pda.validate {pda.name} account {account} missing account binding"
          ]
      | some binding =>
          let compareWords :=
            (List.range 4).foldl
              (fun acc idx =>
                let off := idx * 8
                acc ++ #[
                  .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num off) },
                  .instruction { opcode := .ldxdw, dst := some .r8, src := some .r6, off := some (.num off) },
                  .instruction { opcode := .jne, dst := some .r3, src := some .r8, off := some (.sym "error_pda") }
                ])
              #[]
          #[
            .comment s!"solana.pda.validate {pda.name} account {account}"
          ] ++
          stackPtr .r5 pdaResultOffset ++
          inputAccountFieldPtr .r6 binding.layout binding.layout.keyOff ++
          compareWords

def callHelperPreservingInput (helperName errorLabel : String) : Array AstNode := #[
  .instruction { opcode := .stxdw, dst := some .r10, off := some (.num entryInputSaveOffset), src := some .r1 },
  callHelper helperName,
  .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num entryInputSaveOffset) },
  .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym errorLabel) }
]

def callVoidHelperPreservingInput (helperName : String) : Array AstNode := #[
  .instruction { opcode := .stxdw, dst := some .r10, off := some (.num entryInputSaveOffset), src := some .r1 },
  callHelper helperName,
  .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num entryInputSaveOffset) }
]

def lowerPdaDerive (accountBindings : Array CpiAccountBinding) (valueBindings : Array CpiValueBinding)
    (pda : PdaDerive) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.pda.derive {pda.name}",
    .label pda.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 },
    .comment "pack PDA seed byte slices"
  ] ++
  lowerAccountPtrTableSetup pda.label accountBindings.size ++
  lowerPdaSeeds accountBindings valueBindings pda ++
  stackPtr .r1 pdaSeedTableOffset ++ #[
    .instruction { opcode := .mov64, dst := some .r2, imm := some (.num pda.effectiveSeeds.size) },
  ] ++
  loadCurrentProgramIdPtr .r3 .r5 ++
  stackPtr .r4 pdaResultOffset ++ #[
    .comment "r1=seeds_ptr r2=seeds_len r3=program_id_ptr r4=result_ptr",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_create_program_address,
    .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_pda") },
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .comment s!"PDA result stored at stack offset {pdaResultOffset}",
  ] ++
  lowerPdaResultAccountValidation accountBindings pda ++ #[
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def boolByte (value : Bool) : Nat :=
  if value then 1 else 0

def cpiAccountWritable (account : AccountMeta) : Nat :=
  boolByte (account.access == "writable")

def cpiAccountSigner (account : AccountMeta) : Nat :=
  boolByte (account.signer != "none")

def storeImm (opcode : Opcode) (base : Reg) (off value : Nat) : AstNode :=
  .instruction { opcode, dst := some base, off := some (.num off), imm := some (.num value) }

def storeReg (opcode : Opcode) (base : Reg) (off : Nat) (src : Reg) : AstNode :=
  .instruction { opcode, dst := some base, off := some (.num off), src := some src }

def zeroStackQuad (base : Reg) (off : Nat) : AstNode :=
  storeImm .stdw base off 0

def loadImm (dst : Reg) (value : Nat) : AstNode :=
  .instruction { opcode := .mov64, dst := some dst, imm := some (.num value) }

def cpiMetadataValue? (cpi : CpiInvoke) (key : String) : Option String :=
  metadataValue? cpi.metadata key

def copyInputPubkeyToStack (name : String) (srcOff stackOff : Nat) : Array AstNode :=
  #[
    .comment s!"solana.cpi.program_id {name} from input account"
  ] ++
  stackPtr .r8 stackOff ++
  inputPtr .r7 srcOff ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 0) },
    storeReg .stxdw .r8 0 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 8) },
    storeReg .stxdw .r8 8 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 16) },
    storeReg .stxdw .r8 16 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 24) },
    storeReg .stxdw .r8 24 .r3
  ]

def copyInputAccountPubkeyToStack (name : String) (layout : AccountInputLayout)
    (stackOff : Nat) : Array AstNode :=
  #[
    .comment s!"solana.cpi.program_id {name} from input account"
  ] ++
  stackPtr .r8 stackOff ++
  inputAccountFieldPtr .r7 layout layout.keyOff ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 0) },
    storeReg .stxdw .r8 0 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 8) },
    storeReg .stxdw .r8 8 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 16) },
    storeReg .stxdw .r8 16 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 24) },
    storeReg .stxdw .r8 24 .r3
  ]

def lowerZero32 (base : Reg) : Array AstNode := #[
  zeroStackQuad base 0,
  zeroStackQuad base 8,
  zeroStackQuad base 16,
  zeroStackQuad base 24
]

def lowerZero32At (base : Reg) (off : Nat) : Array AstNode := #[
  zeroStackQuad base off,
  zeroStackQuad base (off + 8),
  zeroStackQuad base (off + 16),
  zeroStackQuad base (off + 24)
]

def lowerCpiSystemProgramId : Array AstNode :=
  #[
    .comment "solana.cpi.program_id system_program (32 zero bytes)"
  ] ++
  stackPtr .r8 cpiProgramIdOffset ++
  lowerZero32 .r8

def splTokenProgramIdBytes : Array Nat :=
  #[6, 221, 246, 225, 215, 101, 161, 147,
    217, 203, 225, 70, 206, 235, 121, 172,
    28, 180, 133, 237, 95, 91, 55, 145,
    58, 140, 245, 133, 126, 255, 0, 169]

def splToken2022ProgramIdBytes : Array Nat :=
  #[6, 221, 246, 225, 238, 117, 143, 222,
    24, 66, 93, 188, 228, 108, 205, 218,
    182, 26, 252, 77, 131, 185, 13, 39,
    254, 189, 249, 40, 216, 161, 139, 252]

def storePubkeyBytes (base : Reg) (bytes : Array Nat) : Array AstNode :=
  bytes.mapIdx fun idx byte => storeImm .stb base idx byte

def lowerCpiSplTokenProgramId : Array AstNode :=
  #[
    .comment "solana.cpi.program_id spl_token TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
  ] ++
  stackPtr .r8 cpiProgramIdOffset ++
  storePubkeyBytes .r8 splTokenProgramIdBytes

def lowerCpiSplToken2022ProgramId : Array AstNode :=
  #[
    .comment "solana.cpi.program_id spl_token_2022 TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
  ] ++
  stackPtr .r8 cpiProgramIdOffset ++
  storePubkeyBytes .r8 splToken2022ProgramIdBytes

def lowerCpiFallbackProgramId (program : String) : Array AstNode :=
  #[
    .comment s!"solana.cpi.program_id {program} fallback placeholder"
  ] ++
  stackPtr .r8 cpiProgramIdOffset ++
  lowerZero32 .r8

def lowerCpiProgramId (bindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  if cpi.program == "spl_token" then
    lowerCpiSplTokenProgramId
  else if cpi.program == "spl_token_2022" then
    lowerCpiSplToken2022ProgramId
  else
    match cpiAccountBinding? bindings cpi.program with
    | some binding =>
        copyInputAccountPubkeyToStack s!"{cpi.program} account[{binding.layout.index}]"
          binding.layout cpiProgramIdOffset
    | none =>
        if cpi.program == "system_program" then
          lowerCpiSystemProgramId
        else
          lowerCpiFallbackProgramId cpi.program

def lowerCpiPlaceholderPubkey (idx : Nat) (name : String) : Array AstNode :=
  let offset := cpiPlaceholderPubkeyOffset + idx * 32
  #[
    .comment s!"solana.cpi.placeholder_pubkey {name}"
  ] ++
  stackPtr .r8 offset ++
  lowerZero32 .r8 ++ #[
    storeImm .stb .r8 31 (idx + 1)
  ]

def lowerCpiPlaceholderLamports (idx : Nat) : Array AstNode :=
  let offset := cpiPlaceholderLamportsOffset + idx * 8
  stackPtr .r8 offset ++ #[
    zeroStackQuad .r8 0
  ]

def lowerCpiFallbackPlaceholders (bindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  cpi.accounts.mapIdx (fun idx account =>
    match cpiAccountBinding? bindings account.name with
    | some _ => #[]
    | none =>
        lowerCpiPlaceholderPubkey idx account.name ++
        lowerCpiPlaceholderLamports idx)
    |>.foldl (fun acc nodes => acc ++ nodes) #[]

def lowerCpiAccountMeta (bindings : Array CpiAccountBinding) (idx : Nat)
    (account : AccountMeta) : Array AstNode :=
  let metaOffset := idx * 16
  let pubkeyOffset := cpiPlaceholderPubkeyOffset + idx * 32
  let pubkeyPtr :=
    match cpiAccountBinding? bindings account.name with
    | some binding =>
        #[
          .comment s!"solana.cpi.account_meta {account.name} key_ptr account[{binding.layout.index}]"
        ] ++
        inputAccountFieldPtr .r8 binding.layout binding.layout.keyOff
    | none =>
        #[
          .comment s!"solana.cpi.account_meta {account.name} placeholder"
        ] ++
        stackPtr .r8 pubkeyOffset
  stackPtr .r7 cpiAccountMetaOffset ++ #[
    .instruction { opcode := .add64, dst := some .r7, imm := some (.num metaOffset) }
  ] ++ pubkeyPtr ++ #[
    storeReg .stxdw .r7 0 .r8,
    storeImm .stb .r7 8 (cpiAccountWritable account),
    storeImm .stb .r7 9 (cpiAccountSigner account)
  ]

def lowerCpiAccountMetas (bindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  cpi.accounts.mapIdx (lowerCpiAccountMeta bindings)
    |>.foldl (fun acc nodes => acc ++ nodes) #[]

def lowerCpiAccountInfoFallback (idx : Nat) (account : AccountMeta) : Array AstNode :=
  let infoOffset := idx * 56
  let pubkeyOffset := cpiPlaceholderPubkeyOffset + idx * 32
  let lamportsOffset := cpiPlaceholderLamportsOffset + idx * 8
  #[
    .comment s!"solana.cpi.account_info {account.name} placeholder"
  ] ++
  stackPtr .r6 cpiAccountInfoOffset ++ #[
    .instruction { opcode := .add64, dst := some .r6, imm := some (.num infoOffset) }
  ] ++
  stackPtr .r8 pubkeyOffset ++ #[
    storeReg .stxdw .r6 0 .r8
  ] ++
  stackPtr .r8 lamportsOffset ++ #[
    storeReg .stxdw .r6 8 .r8,
    zeroStackQuad .r6 16,
    zeroStackQuad .r6 24
  ] ++
  stackPtr .r8 cpiProgramIdOffset ++ #[
    storeReg .stxdw .r6 32 .r8,
    zeroStackQuad .r6 40,
    storeImm .stb .r6 48 (cpiAccountSigner account),
    storeImm .stb .r6 49 (cpiAccountWritable account),
    storeImm .stb .r6 50 0
  ]

def lowerCpiAccountInfoBound (idx : Nat) (account : AccountMeta)
    (binding : CpiAccountBinding) : Array AstNode :=
  let infoOffset := idx * 56
  let layout := binding.layout
  #[
    .comment s!"solana.cpi.account_info {account.name} account[{layout.index}]"
  ] ++
  stackPtr .r6 cpiAccountInfoOffset ++ #[
    .instruction { opcode := .add64, dst := some .r6, imm := some (.num infoOffset) }
  ] ++
  inputAccountFieldPtr .r8 layout layout.keyOff ++ #[
    storeReg .stxdw .r6 0 .r8
  ] ++
  inputAccountFieldPtr .r8 layout layout.lamportsOff ++ #[
    storeReg .stxdw .r6 8 .r8
  ] ++
  inputAccountFieldPtr .r8 layout layout.dataLenOff ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r8, off := some (.num 0) },
    storeReg .stxdw .r6 16 .r3
  ] ++
  inputAccountFieldPtr .r8 layout layout.dataStart ++ #[
    storeReg .stxdw .r6 24 .r8
  ] ++
  inputAccountFieldPtr .r8 layout layout.ownerOff ++ #[
    storeReg .stxdw .r6 32 .r8
  ] ++
  inputAccountFieldPtr .r8 layout layout.rentEpochOff ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r8, off := some (.num 0) },
    storeReg .stxdw .r6 40 .r3
  ] ++
  inputAccountFieldPtr .r8 layout layout.signerOff ++ #[
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r8, off := some (.num 0) },
    storeReg .stxb .r6 48 .r3
  ] ++
  inputAccountFieldPtr .r8 layout layout.writableOff ++ #[
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r8, off := some (.num 0) },
    storeReg .stxb .r6 49 .r3
  ] ++
  inputAccountFieldPtr .r8 layout layout.executableOff ++ #[
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r8, off := some (.num 0) },
    storeReg .stxb .r6 50 .r3
  ]

def lowerCpiAccountInfo (bindings : Array CpiAccountBinding) (idx : Nat)
    (account : AccountMeta) : Array AstNode :=
  match cpiAccountBinding? bindings account.name with
  | some binding => lowerCpiAccountInfoBound idx account binding
  | none => lowerCpiAccountInfoFallback idx account

def lowerCpiAccountInfos (bindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  cpi.accounts.mapIdx (lowerCpiAccountInfo bindings)
    |>.foldl (fun acc nodes => acc ++ nodes) #[]

def lowerCpiU64Field (bindings : Array CpiValueBinding) (cpi : CpiInvoke)
    (metadataKey fieldName : String) (fieldOff : Nat) : Array AstNode :=
  match cpiMetadataValue? cpi metadataKey with
  | some source =>
      match source.toNat? with
      | some value =>
          #[
            .comment s!"solana.cpi.value {fieldName} literal={value}",
            loadImm .r3 value,
            storeReg .stxdw .r8 fieldOff .r3
          ]
      | none =>
          match cpiValueBinding? bindings source with
          | some binding =>
              let loadValue :=
                if binding.relativeToInstructionData then
                  loadSavedInstructionDataPtr .r7 ++ #[
                    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num binding.absOff) }
                  ]
                else
                  #[
                    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r1, off := some (.num binding.absOff) }
                  ]
              #[
                .comment s!"solana.cpi.value {fieldName} from {binding.sourceKind} {source}",
              ] ++ loadValue ++ #[
                storeReg .stxdw .r8 fieldOff .r3
              ]
          | none =>
              #[
                .comment s!"solana.cpi.value {fieldName} source={source} placeholder=0",
                loadImm .r3 0,
                storeReg .stxdw .r8 fieldOff .r3
              ]
  | none =>
      #[
        .comment s!"solana.cpi.value {fieldName} missing placeholder=0",
        loadImm .r3 0,
        storeReg .stxdw .r8 fieldOff .r3
      ]

def lowerCpiU16Field (bindings : Array CpiValueBinding) (cpi : CpiInvoke)
    (metadataKey fieldName : String) (fieldOff : Nat) : Array AstNode :=
  match cpiMetadataValue? cpi metadataKey with
  | some source =>
      match source.toNat? with
      | some value =>
          #[
            .comment s!"solana.cpi.value {fieldName} literal={value}",
            loadImm .r3 value,
            storeReg .stxh .r8 fieldOff .r3
          ]
      | none =>
          match cpiValueBinding? bindings source with
          | some binding =>
              let loadValue :=
                if binding.relativeToInstructionData then
                  loadSavedInstructionDataPtr .r7 ++ #[
                    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num binding.absOff) }
                  ]
                else
                  #[
                    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r1, off := some (.num binding.absOff) }
                  ]
              #[
                .comment s!"solana.cpi.value {fieldName} from {binding.sourceKind} {source}",
              ] ++ loadValue ++ #[
                storeReg .stxh .r8 fieldOff .r3
              ]
          | none =>
              #[
                .comment s!"solana.cpi.value {fieldName} source={source} placeholder=0",
                loadImm .r3 0,
                storeReg .stxh .r8 fieldOff .r3
              ]
  | none =>
      #[
        .comment s!"solana.cpi.value {fieldName} missing placeholder=0",
        loadImm .r3 0,
        storeReg .stxh .r8 fieldOff .r3
      ]

def lowerCurrentProgramIdToData (fieldOff : Nat) : Array AstNode := #[
  .comment "solana.cpi.value owner=current_program_id",
] ++ loadCurrentProgramIdPtr .r7 .r3 ++ #[
  .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 0) },
  storeReg .stxdw .r8 fieldOff .r3,
  .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 8) },
  storeReg .stxdw .r8 (fieldOff + 8) .r3,
  .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 16) },
  storeReg .stxdw .r8 (fieldOff + 16) .r3,
  .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 24) },
  storeReg .stxdw .r8 (fieldOff + 24) .r3
]

def lowerAccountKeyToDataField (fieldName source : String)
    (layout : AccountInputLayout) (fieldOff : Nat) : Array AstNode :=
  #[
    .comment s!"solana.cpi.value {fieldName} from account {source}",
  ] ++
  inputAccountFieldPtr .r7 layout layout.keyOff ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 0) },
    storeReg .stxdw .r8 fieldOff .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 8) },
    storeReg .stxdw .r8 (fieldOff + 8) .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 16) },
    storeReg .stxdw .r8 (fieldOff + 16) .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 24) },
    storeReg .stxdw .r8 (fieldOff + 24) .r3
  ]

def lowerAccountKeyToData (source : String) (layout : AccountInputLayout) (fieldOff : Nat) : Array AstNode :=
  lowerAccountKeyToDataField "owner" source layout fieldOff

def lowerCpiPubkeyOptionField (accountBindings : Array CpiAccountBinding)
    (cpi : CpiInvoke) (metadataKey fieldName : String) (fieldOff : Nat) : Array AstNode :=
  match cpiMetadataValue? cpi metadataKey with
  | some "program" =>
      #[
        .comment s!"solana.cpi.value {fieldName}=current_program_id option=some",
        storeImm .stb .r8 fieldOff 1
      ] ++ lowerCurrentProgramIdToData (fieldOff + 1)
  | some source =>
      match cpiAccountBinding? accountBindings source with
      | some binding =>
          #[
            .comment s!"solana.cpi.value {fieldName} option=some",
            storeImm .stb .r8 fieldOff 1
          ] ++ lowerAccountKeyToDataField fieldName source binding.layout (fieldOff + 1)
      | none =>
          #[
            .comment s!"solana.cpi.value {fieldName} source={source} placeholder=some-zero",
            storeImm .stb .r8 fieldOff 1
          ] ++ lowerZero32At .r8 (fieldOff + 1)
  | none =>
      #[
        .comment s!"solana.cpi.value {fieldName} missing placeholder=some-zero",
        storeImm .stb .r8 fieldOff 1
      ] ++ lowerZero32At .r8 (fieldOff + 1)

def lowerCpiOwnerField (accountBindings : Array CpiAccountBinding) (cpi : CpiInvoke)
    (fieldOff : Nat) : Array AstNode :=
  match cpiMetadataValue? cpi "solana.cpi.owner" with
  | some "program" => lowerCurrentProgramIdToData fieldOff
  | some source =>
      match cpiAccountBinding? accountBindings source with
      | some binding => lowerAccountKeyToData source binding.layout fieldOff
      | none =>
          #[
            .comment s!"solana.cpi.value owner source={source} placeholder=zero",
          ] ++ lowerZero32At .r8 fieldOff
  | none =>
      #[
        .comment "solana.cpi.value owner missing placeholder=zero",
      ] ++ lowerZero32At .r8 fieldOff

def lowerCpiSignerSeed (cpiName : String) (idx : Nat) (seed : String) : Array AstNode :=
  let seedOffset := cpiSignerSeedDataOffset + idx * cpiMaxSeedLen
  let tableOffset := cpiSignerSeedTableOffset + idx * 16
  let bytes := stringBytes seed
  #[
    .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] \"{seed}\""
  ] ++
  stackPtr .r8 seedOffset ++
  lowerSeedBytes seed .r8 ++
  stackPtr .r7 tableOffset ++ #[
    storeReg .stxdw .r7 0 .r8,
    loadImm .r3 bytes.size,
    storeReg .stxdw .r7 8 .r3
  ]

def lowerCpiSignerSeeds (cpi : CpiInvoke) : Array AstNode :=
  if cpi.signerSeeds.isEmpty then
    #[
      .comment "solana.cpi.signer_seeds none"
    ]
  else
    let seedTable :=
      cpi.signerSeeds.mapIdx (fun idx seed => lowerCpiSignerSeed cpi.name idx seed)
        |>.foldl (fun acc nodes => acc ++ nodes) #[]
    seedTable ++
    stackPtr .r8 cpiSignerEntriesOffset ++
    stackPtr .r7 cpiSignerSeedTableOffset ++ #[
      storeReg .stxdw .r8 0 .r7,
      loadImm .r3 cpi.signerSeeds.size,
      storeReg .stxdw .r8 8 .r3
    ]

def lowerCpiSignerArgs (cpi : CpiInvoke) : Array AstNode :=
  if cpi.signerSeeds.isEmpty then
    #[
      loadImm .r4 0,
      loadImm .r5 0
    ]
  else
    stackPtr .r4 cpiSignerEntriesOffset ++ #[
      loadImm .r5 1
    ]

def lowerSystemTransferData (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data system.transfer: u32 discriminator=2, u64 lamports"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    loadImm .r3 2,
    storeReg .stxw .r8 0 .r3
  ] ++
  lowerCpiU64Field valueBindings cpi "solana.cpi.lamports_source" "lamports" 4

def lowerSystemCreateAccountData (accountBindings : Array CpiAccountBinding)
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data system.create_account: u32 discriminator=0, u64 lamports, u64 space, pubkey owner"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    loadImm .r3 0,
    storeReg .stxw .r8 0 .r3
  ] ++
  lowerCpiU64Field valueBindings cpi "solana.cpi.lamports_source" "lamports" 4 ++
  lowerCpiU64Field valueBindings cpi "solana.cpi.space_source" "space" 12 ++
  lowerCpiOwnerField accountBindings cpi 20

def cpiDecimals (cpi : CpiInvoke) : Nat :=
  match cpiMetadataValue? cpi "solana.cpi.decimals" with
  | some value => value.toNat?.getD 0
  | none => 0

def lowerSplTokenAmountData (valueBindings : Array CpiValueBinding)
    (cpi : CpiInvoke) (layoutName : String) (tag dataLen : Nat)
    (includeDecimals : Bool := false) : Array AstNode :=
  #[
    .comment (s!"solana.cpi.data {layoutName}: u8 instruction={tag}, u64 amount" ++
      (if includeDecimals then s!", u8 decimals={cpiDecimals cpi}" else ""))
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 tag
  ] ++
  lowerCpiU64Field valueBindings cpi "solana.cpi.amount_source" "amount" 1 ++
  (if includeDecimals then
    #[storeImm .stb .r8 (dataLen - 1) (cpiDecimals cpi)]
  else
    #[])

def lowerSplTokenRevokeData : Array AstNode :=
  #[
    .comment "solana.cpi.data spl-token.revoke: u8 instruction=5"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 5
  ]

def lowerSplTokenCloseAccountData : Array AstNode :=
  #[
    .comment "solana.cpi.data spl-token.close_account: u8 instruction=9"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 9
  ]

def splTokenAuthorityType (cpi : CpiInvoke) : Nat :=
  match cpiMetadataValue? cpi "solana.cpi.authority_type" with
  | some "mint_tokens" => 0
  | some "freeze_account" => 1
  | some "account_owner" => 2
  | some "close_account" => 3
  | some value => value.toNat?.getD 0
  | none => 0

def lowerSplTokenSetAuthorityNewAuthority
    (accountBindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  match cpiMetadataValue? cpi "solana.cpi.new_authority" with
  | some source =>
      match cpiAccountBinding? accountBindings source with
      | some binding => lowerAccountKeyToDataField "new_authority" source binding.layout 3
      | none =>
          #[
            .comment s!"solana.cpi.value new_authority source={source} placeholder=zero",
          ] ++ lowerZero32At .r8 3
  | none =>
      #[
        .comment "solana.cpi.value new_authority missing placeholder=zero",
      ] ++ lowerZero32At .r8 3

def lowerSplTokenSetAuthorityData
    (accountBindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  let authorityType := splTokenAuthorityType cpi
  let authorityTypeLabel := cpiMetadataValue? cpi "solana.cpi.authority_type" |>.getD (toString authorityType)
  #[
    .comment s!"solana.cpi.data spl-token.set_authority: u8 instruction=6, u8 authority_type={authorityTypeLabel}, option=some, pubkey new_authority"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 6,
    storeImm .stb .r8 1 authorityType,
    storeImm .stb .r8 2 1
  ] ++
  lowerSplTokenSetAuthorityNewAuthority accountBindings cpi

def lowerToken2022InitializeTransferFeeConfigData
    (accountBindings : Array CpiAccountBinding) (valueBindings : Array CpiValueBinding)
    (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_transfer_fee_config: u8 instruction=26, u8 transfer_fee_instruction=0, pubkey_option transfer_fee_config_authority, pubkey_option withdraw_withheld_authority, u16 transfer_fee_basis_points, u64 maximum_fee"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 26,
    storeImm .stb .r8 1 0
  ] ++
  lowerCpiPubkeyOptionField accountBindings cpi
    "solana.cpi.transfer_fee_config_authority" "transfer_fee_config_authority" 2 ++
  lowerCpiPubkeyOptionField accountBindings cpi
    "solana.cpi.withdraw_withheld_authority" "withdraw_withheld_authority" 35 ++
  lowerCpiU16Field valueBindings cpi
    "solana.cpi.transfer_fee_basis_points" "transfer_fee_basis_points" 68 ++
  lowerCpiU64Field valueBindings cpi
    "solana.cpi.maximum_fee" "maximum_fee" 70

def lowerToken2022TransferCheckedWithFeeData
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment s!"solana.cpi.data token-2022.transfer_checked_with_fee: u8 instruction=26, u8 transfer_fee_instruction=1, u64 amount, u8 decimals={cpiDecimals cpi}, u64 fee"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 26,
    storeImm .stb .r8 1 1
  ] ++
  lowerCpiU64Field valueBindings cpi "solana.cpi.amount_source" "amount" 2 ++ #[
    storeImm .stb .r8 10 (cpiDecimals cpi)
  ] ++
  lowerCpiU64Field valueBindings cpi "solana.cpi.fee_source" "fee" 11

def lowerToken2022TransferFeeTagData (layoutName : String) (subTag : Nat) : Array AstNode :=
  #[
    .comment s!"solana.cpi.data {layoutName}: u8 instruction=26, u8 transfer_fee_instruction={subTag}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 26,
    storeImm .stb .r8 1 subTag
  ]

def token2022NumTokenAccounts (cpi : CpiInvoke) : Nat :=
  match cpiMetadataValue? cpi "solana.cpi.num_token_accounts" with
  | some value => value.toNat?.getD 0
  | none => 0

def lowerToken2022WithdrawWithheldTokensFromAccountsData (cpi : CpiInvoke) :
    Array AstNode :=
  #[
    .comment s!"solana.cpi.data token-2022.withdraw_withheld_tokens_from_accounts: u8 instruction=26, u8 transfer_fee_instruction=3, u8 num_token_accounts={token2022NumTokenAccounts cpi}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 26,
    storeImm .stb .r8 1 3,
    storeImm .stb .r8 2 (token2022NumTokenAccounts cpi)
  ]

def lowerToken2022SetTransferFeeData
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.set_transfer_fee: u8 instruction=26, u8 transfer_fee_instruction=5, u16 transfer_fee_basis_points, u64 maximum_fee"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 26,
    storeImm .stb .r8 1 5
  ] ++
  lowerCpiU16Field valueBindings cpi
    "solana.cpi.transfer_fee_basis_points" "transfer_fee_basis_points" 2 ++
  lowerCpiU64Field valueBindings cpi
    "solana.cpi.maximum_fee" "maximum_fee" 4

def lowerToken2022InitializeNonTransferableMintData : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_non_transferable_mint: u8 instruction=32"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 32
  ]

/-- Initialize metadata pointer: u8 instruction=39, pubkey metadata_program_id, pubkey metadata_account. -/
def lowerToken2022InitializeMetadataPointerData (accountBindings : Array CpiAccountBinding)
    (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_metadata_pointer: u8 instruction=39, pubkey metadata_program_id, pubkey metadata_account"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 39
  ] ++
  lowerCpiOwnerField accountBindings cpi 1

/-- Initialize default account state: u8 instruction=38, u8 state (0=unfrozen, 1=frozen).
    The state value comes from `solana.cpi.default_account_state` metadata as a
    literal string (0 or 1). -/
def lowerToken2022InitializeDefaultAccountStateData (cpi : CpiInvoke) : Array AstNode :=
  let stateVal := match cpiMetadataValue? cpi "solana.cpi.default_account_state" with
    | some "1" => 1
    | _ => 0
  #[
    .comment s!"solana.cpi.data token-2022.initialize_default_account_state: u8 instruction=38, u8 state={stateVal}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 38,
    storeImm .stb .r8 1 stateVal
  ]

/-- Initialize immutable owner: u8 instruction=37 (discriminator only, no extra data). -/
def lowerToken2022InitializeImmutableOwnerData : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_immutable_owner: u8 instruction=37"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 37
  ]

/-- Memo CPI data: raw bytes from the input binding. No discriminator — the
    Memo program accepts arbitrary bytes as instruction data. This initial
    lowering copies up to 8 bytes (one u64 word) from the binding's offset;
    longer memos require a memcpy loop (future work). The binding's `byteSize`
    records the memo length for metadata. -/
def lowerMemoData (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  match cpiMetadataValue? cpi "solana.cpi.memo_source" with
  | some source =>
      match cpiValueBinding? valueBindings source with
      | some binding =>
          let len := binding.byteSize
          let loadValue :=
            if binding.relativeToInstructionData then
              loadSavedInstructionDataPtr .r7 ++ #[
                .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num binding.absOff) }
              ]
            else
              #[
                .instruction { opcode := .ldxdw, dst := some .r3, src := some .r1, off := some (.num binding.absOff) }
              ]
          #[
            .comment s!"solana.cpi.data memo.memo: raw bytes (len={len}) from {binding.sourceKind} {source}"
          ] ++ stackPtr .r8 cpiInstructionDataOffset ++ loadValue ++ #[
            storeReg .stxdw .r8 0 .r3
          ]
      | none =>
          #[.comment s!"memo.memo: source `{source}` not found in bindings — empty data"]
  | none =>
      #[.comment "memo.memo: no memo_source metadata — empty data"]

def lowerCpiInstructionData (accountBindings : Array CpiAccountBinding)
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode × Nat :=
  match cpi.dataLayout? with
  | some "system.transfer" =>
      (lowerSystemTransferData valueBindings cpi, 12)
  | some "system.create_account" =>
      (lowerSystemCreateAccountData accountBindings valueBindings cpi, 52)
  | some "spl-token.transfer_checked" =>
      (lowerSplTokenAmountData valueBindings cpi "spl-token.transfer_checked" 12 10 true, 10)
  | some "spl-token.mint_to" =>
      (lowerSplTokenAmountData valueBindings cpi "spl-token.mint_to" 7 9, 9)
  | some "spl-token.burn" =>
      (lowerSplTokenAmountData valueBindings cpi "spl-token.burn" 8 9, 9)
  | some "spl-token.approve" =>
      (lowerSplTokenAmountData valueBindings cpi "spl-token.approve" 4 9, 9)
  | some "spl-token.revoke" =>
      (lowerSplTokenRevokeData, 1)
  | some "spl-token.close_account" =>
      (lowerSplTokenCloseAccountData, 1)
  | some "spl-token.set_authority" =>
      (lowerSplTokenSetAuthorityData accountBindings cpi, 35)
  | some "token-2022.initialize_transfer_fee_config" =>
      (lowerToken2022InitializeTransferFeeConfigData accountBindings valueBindings cpi, 78)
  | some "token-2022.transfer_checked_with_fee" =>
      (lowerToken2022TransferCheckedWithFeeData valueBindings cpi, 19)
  | some "token-2022.withdraw_withheld_tokens_from_mint" =>
      (lowerToken2022TransferFeeTagData "token-2022.withdraw_withheld_tokens_from_mint" 2, 2)
  | some "token-2022.withdraw_withheld_tokens_from_accounts" =>
      (lowerToken2022WithdrawWithheldTokensFromAccountsData cpi, 3)
  | some "token-2022.harvest_withheld_tokens_to_mint" =>
      (lowerToken2022TransferFeeTagData "token-2022.harvest_withheld_tokens_to_mint" 4, 2)
  | some "token-2022.set_transfer_fee" =>
      (lowerToken2022SetTransferFeeData valueBindings cpi, 12)
  | some "token-2022.initialize_non_transferable_mint" =>
      (lowerToken2022InitializeNonTransferableMintData, 1)
  | some "token-2022.initialize_metadata_pointer" =>
      (lowerToken2022InitializeMetadataPointerData accountBindings cpi, 1)
  | some "token-2022.initialize_default_account_state" =>
      (lowerToken2022InitializeDefaultAccountStateData cpi, 2)
  | some "token-2022.initialize_immutable_owner" =>
      (lowerToken2022InitializeImmutableOwnerData, 1)
  | some "memo.memo" =>
      (lowerMemoData valueBindings cpi, 8)
  | some dl =>
      -- Known plan-scaffolded but unlowered Token-2022 extensions: fail at
      -- runtime with a logged error instead of silently emitting zero-data
      -- CPI (which would produce a no-op call). These dataLayouts have plan
      -- metadata in Token.lean but no sBPF instruction-data lowering yet.
      if dl == "token-2022.initialize_confidential_transfer_mint"
         ∨ dl == "token-2022.initialize_transfer_hook"
         ∨ dl == "token-2022.initialize_permanent_delegate"
         ∨ dl == "token-2022.initialize_interest_bearing_mint"
         ∨ dl == "token-2022.initialize_memo_transfer" then
        (#[.comment s!"UNSUPPORTED CPI dataLayout `{dl}`: plan scaffolded but sBPF lowering pending — runtime abort",
          .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 1) },
          .instruction { opcode := .exit }], 0)
      else
        (#[
          .comment s!"generic CPI instruction data empty for `{dl}`; protocol-specific ABI packing pending"
        ], 0)
  | none =>
      (#[
        .comment "generic CPI instruction data empty (no dataLayout); protocol-specific ABI packing pending"
      ], 0)

def lowerCpiInstructionRecord (cpi : CpiInvoke) (dataLen : Nat) : Array AstNode :=
  #[
    .comment "solana.cpi.instruction record: C SolInstruction"
  ] ++
  stackPtr .r5 cpiInstructionOffset ++
  stackPtr .r8 cpiProgramIdOffset ++ #[
    storeReg .stxdw .r5 0 .r8
  ] ++
  stackPtr .r7 cpiAccountMetaOffset ++ #[
    storeReg .stxdw .r5 8 .r7,
    loadImm .r3 cpi.accounts.size,
    storeReg .stxdw .r5 16 .r3
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeReg .stxdw .r5 24 .r8,
    loadImm .r3 dataLen,
    storeReg .stxdw .r5 32 .r3
  ]

def lowerCpiCall (cpi : CpiInvoke) : Array AstNode :=
  stackPtr .r1 cpiInstructionOffset ++
  stackPtr .r2 cpiAccountInfoOffset ++ #[
    loadImm .r3 cpi.accounts.size
  ] ++
  lowerCpiSignerArgs cpi ++ #[
    .comment "r1=instruction_ptr r2=account_infos_ptr r3=num_accounts r4=signer_seeds_ptr r5=num_signers",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_invoke_signed_c,
    .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_cpi") },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerSystemTransferCpi (accountBindings : Array CpiAccountBinding)
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  let (dataNodes, dataLen) := lowerCpiInstructionData accountBindings valueBindings cpi
  #[
    .comment "solana.cpi.pack system.transfer"
  ] ++
  lowerAccountPtrTableSetup cpi.label accountBindings.size ++
  lowerCpiProgramId accountBindings cpi ++
  lowerCpiFallbackPlaceholders accountBindings cpi ++
  lowerCpiAccountMetas accountBindings cpi ++
  dataNodes ++
  lowerCpiInstructionRecord cpi dataLen ++
  lowerCpiAccountInfos accountBindings cpi ++
  lowerCpiSignerSeeds cpi ++
  lowerCpiCall cpi

def lowerGenericCpiInvoke (accountBindings : Array CpiAccountBinding)
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  let (dataNodes, dataLen) := lowerCpiInstructionData accountBindings valueBindings cpi
  #[
    .comment "generic CPI C ABI packing"
  ] ++
  lowerAccountPtrTableSetup cpi.label accountBindings.size ++
  lowerCpiProgramId accountBindings cpi ++
  lowerCpiFallbackPlaceholders accountBindings cpi ++
  lowerCpiAccountMetas accountBindings cpi ++
  dataNodes ++
  lowerCpiInstructionRecord cpi dataLen ++
  lowerCpiAccountInfos accountBindings cpi ++
  lowerCpiSignerSeeds cpi ++
  lowerCpiCall cpi

def lowerCpiInvoke (accountBindings : Array CpiAccountBinding)
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.cpi {cpi.name}: {cpi.program}.{cpi.instruction}",
    .label cpi.label
  ] ++
  if cpi.protocol? == some "system" && cpi.dataLayout? == some "system.transfer" then
    lowerSystemTransferCpi accountBindings valueBindings cpi
  else
    lowerGenericCpiInvoke accountBindings valueBindings cpi

def memoryStateName (value? : Option String) (fallback : String) : String :=
  value?.getD ("missing_" ++ fallback)

def lowerMemoryStatePtr (bindings : Array CpiValueBinding) (state purpose : String)
    (dst inputBase : Reg) : Array AstNode :=
  match stateValueBinding? bindings state with
  | some binding =>
      #[
        .comment s!"solana.memory.ptr {purpose} state={state} input+{binding.absOff}",
        .instruction { opcode := .mov64, dst := some dst, src := some inputBase },
        .instruction { opcode := .add64, dst := some dst, imm := some (.num binding.absOff) }
      ]
  | none =>
      #[
        .comment s!"solana.memory.ptr {purpose} state={state} missing placeholder=stack"
      ] ++
      stackPtr dst memoryResultOffset

def MemoryAction.byteValue (action : MemoryAction) : Nat :=
  action.value?.getD 0 % 256

def lowerMemoryMemcpy (valueBindings : Array CpiValueBinding)
    (action : MemoryAction) : Array AstNode :=
  let dstState := memoryStateName action.dstState? "dst"
  let srcState := memoryStateName action.srcState? "src"
  #[
    .comment s!"solana.memory.memcpy {action.name}: dst={dstState} src={srcState} bytes={action.bytes}"
  ] ++
  lowerMemoryStatePtr valueBindings dstState "dst" .r1 .r7 ++
  lowerMemoryStatePtr valueBindings srcState "src" .r2 .r7 ++ #[
    loadImm .r3 action.bytes,
    .comment "r1=dst_ptr r2=src_ptr r3=n",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_memcpy_
  ]

def lowerMemoryMemmove (valueBindings : Array CpiValueBinding)
    (action : MemoryAction) : Array AstNode :=
  let dstState := memoryStateName action.dstState? "dst"
  let srcState := memoryStateName action.srcState? "src"
  #[
    .comment s!"solana.memory.memmove {action.name}: dst={dstState} src={srcState} bytes={action.bytes}"
  ] ++
  lowerMemoryStatePtr valueBindings dstState "dst" .r1 .r7 ++
  lowerMemoryStatePtr valueBindings srcState "src" .r2 .r7 ++ #[
    loadImm .r3 action.bytes,
    .comment "r1=dst_ptr r2=src_ptr r3=n",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_memmove_
  ]

def lowerMemoryMemset (valueBindings : Array CpiValueBinding)
    (action : MemoryAction) : Array AstNode :=
  let dstState := memoryStateName action.dstState? "dst"
  let value := action.byteValue
  #[
    .comment s!"solana.memory.memset {action.name}: dst={dstState} value={value} bytes={action.bytes}"
  ] ++
  lowerMemoryStatePtr valueBindings dstState "dst" .r1 .r7 ++ #[
    loadImm .r2 value,
    loadImm .r3 action.bytes,
    .comment "r1=dst_ptr r2=byte r3=n",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_memset_
  ]

def lowerMemoryMemcmp (valueBindings : Array CpiValueBinding)
    (action : MemoryAction) : Array AstNode :=
  let lhsState := memoryStateName action.lhsState? "lhs"
  let rhsState := memoryStateName action.rhsState? "rhs"
  let resultState := memoryStateName action.resultState? "result"
  #[
    .comment s!"solana.memory.memcmp {action.name}: lhs={lhsState} rhs={rhsState} result={resultState} bytes={action.bytes}"
  ] ++
  lowerMemoryStatePtr valueBindings lhsState "lhs" .r1 .r7 ++
  lowerMemoryStatePtr valueBindings rhsState "rhs" .r2 .r7 ++ #[
    loadImm .r3 action.bytes
  ] ++
  stackPtr .r4 memoryResultOffset ++ #[
    storeImm .stw .r4 0 0,
    .comment "r1=s1_ptr r2=s2_ptr r3=n r4=result_ptr",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_memcmp_
  ] ++
  stackPtr .r5 memoryResultOffset ++ #[
    .instruction { opcode := .ldxw, dst := some .r3, src := some .r5, off := some (.num 0) }
  ] ++
  lowerMemoryStatePtr valueBindings resultState "result" .r5 .r7 ++ #[
    storeReg .stxdw .r5 0 .r3
  ]

def lowerMemoryHelper (valueBindings : Array CpiValueBinding)
    (action : MemoryAction) : Array AstNode :=
  let body :=
    match action.op with
    | .memcpy => lowerMemoryMemcpy valueBindings action
    | .memmove => lowerMemoryMemmove valueBindings action
    | .memcmp => lowerMemoryMemcmp valueBindings action
    | .memset => lowerMemoryMemset valueBindings action
  #[
    .blankLine,
    .comment s!"solana.memory {action.name}: op={action.op.id}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 }
  ] ++ body ++ #[
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerMemoryAction (action : MemoryAction) : Array AstNode :=
  #[
    .comment s!"solana.memory.action {action.name}"
  ] ++ callVoidHelperPreservingInput action.label

def lowerCryptoHashStatePtr (bindings : Array CpiValueBinding) (state purpose : String)
    (dst inputBase : Reg) : Array AstNode :=
  match stateValueBinding? bindings state with
  | some binding =>
      #[
        .comment s!"solana.crypto.ptr {purpose} state={state} input+{binding.absOff}",
        .instruction { opcode := .mov64, dst := some dst, src := some inputBase },
        .instruction { opcode := .add64, dst := some dst, imm := some (.num binding.absOff) }
      ]
  | none =>
      #[
        .comment s!"solana.crypto.ptr {purpose} state={state} missing placeholder=stack"
      ] ++
      stackPtr dst cryptoResultOffset

def lowerCryptoHashSlice (valueBindings : Array CpiValueBinding)
    (action : CryptoHashAction) : Array AstNode :=
  lowerCryptoHashStatePtr valueBindings action.inputState "input" .r5 .r7 ++
  stackPtr .r6 cryptoSliceTableOffset ++ #[
    .instruction { opcode := .stxdw, dst := some .r6, off := some (.num 0), src := some .r5 },
    loadImm .r3 action.bytes,
    .instruction { opcode := .stxdw, dst := some .r6, off := some (.num 8), src := some .r3 }
  ]

def lowerCryptoHashOutputWord (valueBindings : Array CpiValueBinding)
    (action : CryptoHashAction) (idx : Nat) (state : String) : Array AstNode :=
  #[
    .comment s!"solana.crypto.output {action.name}[{idx}] state={state}"
  ] ++
  stackPtr .r5 cryptoResultOffset ++ #[
    .instruction { opcode := .add64, dst := some .r5, imm := some (.num (idx * 8)) },
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 0) }
  ] ++
  lowerCryptoHashStatePtr valueBindings state s!"output[{idx}]" .r5 .r7 ++ #[
    storeReg .stxdw .r5 0 .r3
  ]

def lowerCryptoHashOutputs (valueBindings : Array CpiValueBinding)
    (action : CryptoHashAction) : Array AstNode :=
  action.outputStates.mapIdx (fun idx state =>
    if idx < 4 then
      lowerCryptoHashOutputWord valueBindings action idx state
    else
      #[.comment s!"solana.crypto.output {action.name}[{idx}] state={state} ignored: hash result has four u64 words"])
    |>.foldl (fun acc nodes => acc ++ nodes) #[]

def lowerCryptoHashHelper (valueBindings : Array CpiValueBinding)
    (action : CryptoHashAction) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.crypto.hash {action.name}: op={action.op.id} input={action.inputState} bytes={action.bytes} feature_gated={action.featureGated}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 },
    .comment "pack SolBytes slice array for hash input"
  ] ++
  lowerCryptoHashSlice valueBindings action ++
  stackPtr .r1 cryptoSliceTableOffset ++ #[
    loadImm .r2 1,
    .comment "r1=slices_ptr r2=num_slices r3=hash_result_ptr",
  ] ++
  stackPtr .r3 cryptoResultOffset ++ #[
    callSyscall action.op.syscall,
    .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_crypto") },
    .comment "copy 32-byte hash result into output state words"
  ] ++
  lowerCryptoHashOutputs valueBindings action ++ #[
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerCryptoHashAction (action : CryptoHashAction) : Array AstNode :=
  #[
    .comment s!"solana.crypto.action {action.name}"
  ] ++ callHelperPreservingInput action.label "error_crypto"

def lowerSysvarOutputStatePtr (bindings : Array CpiValueBinding) (action : SysvarReadAction)
    (dst inputBase : Reg) : Array AstNode :=
  match stateValueBinding? bindings action.outputState with
  | some binding =>
      #[
        .comment s!"solana.sysvar.output {action.name} state={action.outputState} input+{binding.absOff}",
        .instruction { opcode := .mov64, dst := some dst, src := some inputBase },
        .instruction { opcode := .add64, dst := some dst, imm := some (.num binding.absOff) }
      ]
  | none =>
      #[
        .comment s!"solana.sysvar.output {action.name} state={action.outputState} missing placeholder=stack"
      ] ++
      stackPtr dst sysvarResultOffset

def lowerFixedSysvarFieldRead (valueBindings : Array CpiValueBinding)
    (action : SysvarReadAction) (fieldLabel : String) (fieldOffset : Nat)
    (loadOpcode : Opcode := .ldxdw) : Array AstNode :=
  let syscall := (SysvarField.kind action.field).syscall
  stackPtr .r1 sysvarResultOffset ++ #[
    callSyscall syscall,
    .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
    .comment s!"read {fieldLabel} from sysvar buffer"
  ] ++
  stackPtr .r5 sysvarResultOffset ++ #[
    .instruction { opcode := loadOpcode, dst := some .r3, src := some .r5, off := some (.num fieldOffset) }
  ] ++
  lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
    storeReg .stxdw .r5 0 .r3
  ]

def lowerSysvarFieldRead (valueBindings : Array CpiValueBinding)
    (action : SysvarReadAction) : Array AstNode :=
  match action.field with
  | .rentLamportsPerByteYear =>
      stackPtr .r1 sysvarResultOffset ++ #[
        callSyscall SysvarKind.rent.syscall,
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
        .comment "read Rent.lamports_per_byte_year from sysvar buffer"
      ] ++
      stackPtr .r5 sysvarResultOffset ++ #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 0) }
      ] ++
      lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r3
      ]
  | .lastRestartSlot =>
      #[
        .comment "solana.sysvar.last_restart_slot: load SysvarLastRestartS1ot1111111111111111111111 id"
      ] ++
      stackPtr .r5 sysvarIdOffset ++
      storePubkeyBytes .r5 lastRestartSlotSysvarIdBytes ++
      stackPtr .r1 sysvarIdOffset ++
      stackPtr .r2 sysvarResultOffset ++ #[
        loadImm .r3 0,
        loadImm .r4 8,
        .comment "r1=sysvar_id r2=result r3=offset r4=length",
        callSyscall ProofForge.Backend.Solana.Syscalls.sol_get_sysvar,
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
        .comment "read LastRestartSlot.last_restart_slot from generic sysvar buffer"
      ] ++
      stackPtr .r5 sysvarResultOffset ++ #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 0) }
      ] ++
      lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r3
      ]
  | .epochScheduleSlotsPerEpoch =>
      stackPtr .r1 sysvarResultOffset ++ #[
        callSyscall SysvarKind.epochSchedule.syscall,
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
        .comment "read EpochSchedule.slots_per_epoch from sysvar buffer"
      ] ++
      stackPtr .r5 sysvarResultOffset ++ #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 0) }
      ] ++
      lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r3
      ]
  | .epochScheduleLeaderScheduleSlotOffset =>
      stackPtr .r1 sysvarResultOffset ++ #[
        callSyscall SysvarKind.epochSchedule.syscall,
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
        .comment "read EpochSchedule.leader_schedule_slot_offset from sysvar buffer"
      ] ++
      stackPtr .r5 sysvarResultOffset ++ #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 8) }
      ] ++
      lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r3
      ]
  | .epochScheduleWarmup =>
      stackPtr .r1 sysvarResultOffset ++ #[
        callSyscall SysvarKind.epochSchedule.syscall,
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
        .comment "read EpochSchedule.warmup from sysvar buffer"
      ] ++
      stackPtr .r5 sysvarResultOffset ++ #[
        .instruction { opcode := .ldxb, dst := some .r3, src := some .r5, off := some (.num 16) }
      ] ++
      lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r3
      ]
  | .epochScheduleFirstNormalEpoch =>
      stackPtr .r1 sysvarResultOffset ++ #[
        callSyscall SysvarKind.epochSchedule.syscall,
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
        .comment "read EpochSchedule.first_normal_epoch from sysvar buffer"
      ] ++
      stackPtr .r5 sysvarResultOffset ++
      #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 24) }
      ] ++
      lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r3
      ]
  | .epochScheduleFirstNormalSlot =>
      stackPtr .r1 sysvarResultOffset ++ #[
        callSyscall SysvarKind.epochSchedule.syscall,
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_sysvar") },
        .comment "read EpochSchedule.first_normal_slot from sysvar buffer"
      ] ++
      stackPtr .r5 sysvarResultOffset ++
      #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 32) }
      ] ++
      lowerSysvarOutputStatePtr valueBindings action .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r3
      ]
  | .epochRewardsDistributionStartingBlockHeight =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.distribution_starting_block_height" 0
  | .epochRewardsNumPartitions =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.num_partitions" 8
  | .epochRewardsParentBlockhashWord0 =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.parent_blockhash_word0" 16
  | .epochRewardsParentBlockhashWord1 =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.parent_blockhash_word1" 24
  | .epochRewardsParentBlockhashWord2 =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.parent_blockhash_word2" 32
  | .epochRewardsParentBlockhashWord3 =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.parent_blockhash_word3" 40
  | .epochRewardsTotalPointsLow =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.total_points_low" 48
  | .epochRewardsTotalPointsHigh =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.total_points_high" 56
  | .epochRewardsTotalRewards =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.total_rewards" 64
  | .epochRewardsDistributedRewards =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.distributed_rewards" 72
  | .epochRewardsActive =>
      lowerFixedSysvarFieldRead valueBindings action
        "EpochRewards.active" 80 .ldxb

def lowerSysvarHelper (valueBindings : Array CpiValueBinding)
    (action : SysvarReadAction) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.sysvar.{action.kind.id} {action.name}: field={action.field.id}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 }
  ] ++
  lowerSysvarFieldRead valueBindings action ++ #[
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerSysvarAction (action : SysvarReadAction) : Array AstNode :=
  #[
    .comment s!"solana.sysvar.action {action.name}"
  ] ++ callHelperPreservingInput action.label "error_sysvar"

def lowerReturnDataStatePtr (bindings : Array CpiValueBinding) (state purpose : String)
    (dst inputBase : Reg) : Array AstNode :=
  match stateValueBinding? bindings state with
  | some binding =>
      #[
        .comment s!"solana.return_data.ptr {purpose} state={state} input+{binding.absOff}",
        .instruction { opcode := .mov64, dst := some dst, src := some inputBase },
        .instruction { opcode := .add64, dst := some dst, imm := some (.num binding.absOff) }
      ]
  | none =>
      #[
        .comment s!"solana.return_data.ptr {purpose} state={state} missing placeholder=stack"
      ] ++
      stackPtr dst memoryResultOffset

def lowerReturnDataHelper (valueBindings : Array CpiValueBinding)
    (action : ReturnDataAction) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.return_data.set {action.name}: source={action.sourceState} bytes={action.bytes}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 }
  ] ++
  lowerReturnDataStatePtr valueBindings action.sourceState "source" .r1 .r7 ++ #[
    loadImm .r2 action.bytes,
    .comment "r1=data_ptr r2=data_len",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_set_return_data,
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerReturnDataAction (action : ReturnDataAction) : Array AstNode :=
  #[
    .comment s!"solana.return_data.action {action.name}"
  ] ++ callVoidHelperPreservingInput action.label

def lowerReturnDataReadDestinationPtr (bindings : Array CpiValueBinding)
    (action : ReturnDataReadAction) : Array AstNode :=
  if action.destinationState.isEmpty then
    #[
      .comment s!"solana.return_data.get {action.name} destination missing placeholder=stack"
    ] ++
    stackPtr .r1 returnDataScratchOffset
  else
    lowerReturnDataStatePtr bindings action.destinationState "destination" .r1 .r7

def lowerReturnDataLengthOutput (bindings : Array CpiValueBinding)
    (action : ReturnDataReadAction) : Array AstNode :=
  match action.lengthState? with
  | none => #[]
  | some state =>
      #[
        .comment s!"solana.return_data.length {action.name} state={state}"
      ] ++
      lowerReturnDataStatePtr bindings state "length" .r5 .r7 ++ #[
        storeReg .stxdw .r5 0 .r6
      ]

def lowerReturnDataProgramIdOutput (bindings : Array CpiValueBinding)
    (action : ReturnDataReadAction) (idx : Nat) (state : String) : Array AstNode :=
  if idx < 4 then
    #[
      .comment s!"solana.return_data.program_id {action.name}[{idx}] state={state}"
    ] ++
    stackPtr .r5 returnDataProgramIdOffset ++ #[
      .instruction { opcode := .add64, dst := some .r5, imm := some (.num (idx * 8)) },
      .instruction { opcode := .ldxdw, dst := some .r3, src := some .r5, off := some (.num 0) }
    ] ++
    lowerReturnDataStatePtr bindings state s!"program_id[{idx}]" .r5 .r7 ++ #[
      storeReg .stxdw .r5 0 .r3
    ]
  else
    #[.comment s!"solana.return_data.program_id {action.name}[{idx}] state={state} ignored: program id has four u64 words"]

def lowerReturnDataProgramIdOutputs (bindings : Array CpiValueBinding)
    (action : ReturnDataReadAction) : Array AstNode :=
  action.programIdStates.mapIdx (lowerReturnDataProgramIdOutput bindings action)
    |>.foldl (fun acc nodes => acc ++ nodes) #[]

def lowerReturnDataReadHelper (valueBindings : Array CpiValueBinding)
    (action : ReturnDataReadAction) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.return_data.get {action.name}: destination={action.destinationState} max_bytes={action.maxBytes}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 }
  ] ++
  lowerReturnDataReadDestinationPtr valueBindings action ++ #[
    loadImm .r2 action.maxBytes
  ] ++
  stackPtr .r3 returnDataProgramIdOffset ++ #[
    .comment "zero return-data program id buffer before sol_get_return_data",
    storeImm .stxdw .r3 0 0,
    storeImm .stxdw .r3 8 0,
    storeImm .stxdw .r3 16 0,
    storeImm .stxdw .r3 24 0,
    .comment "r1=data_ptr r2=max_len r3=program_id_ptr",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_get_return_data,
    .instruction { opcode := .mov64, dst := some .r6, src := some .r0 }
  ] ++
  lowerReturnDataLengthOutput valueBindings action ++
  lowerReturnDataProgramIdOutputs valueBindings action ++ #[
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerReturnDataReadAction (action : ReturnDataReadAction) : Array AstNode :=
  #[
    .comment s!"solana.return_data.read_action {action.name}"
  ] ++ callVoidHelperPreservingInput action.label

def lowerComputeUnitsOutputStatePtr (bindings : Array CpiValueBinding)
    (action : ComputeUnitsAction) (dst inputBase : Reg) : Array AstNode :=
  match stateValueBinding? bindings action.outputState with
  | some binding =>
      #[
        .comment s!"solana.compute_units.output {action.name} state={action.outputState} input+{binding.absOff}",
        .instruction { opcode := .mov64, dst := some dst, src := some inputBase },
        .instruction { opcode := .add64, dst := some dst, imm := some (.num binding.absOff) }
      ]
  | none =>
      #[
        .comment s!"solana.compute_units.output {action.name} state={action.outputState} missing placeholder=stack"
      ] ++
      stackPtr dst memoryResultOffset

def lowerComputeUnitsHelper (valueBindings : Array CpiValueBinding)
    (action : ComputeUnitsAction) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.compute_units.remaining {action.name}: output={action.outputState} feature_gated={action.featureGated}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 },
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_remaining_compute_units,
    .instruction { opcode := .mov64, dst := some .r3, src := some .r0 }
  ] ++
  lowerComputeUnitsOutputStatePtr valueBindings action .r5 .r7 ++ #[
    storeReg .stxdw .r5 0 .r3,
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerComputeUnitsAction (action : ComputeUnitsAction) : Array AstNode :=
  #[
    .comment s!"solana.compute_units.action {action.name}"
  ] ++ callVoidHelperPreservingInput action.label

def lowerComputeUnitsLogHelper (action : ComputeUnitsLogAction) : Array AstNode := #[
  .blankLine,
  .comment s!"solana.compute_units.log_remaining {action.name}",
  .label action.label,
  callSyscall ProofForge.Backend.Solana.Syscalls.sol_log_compute_units_,
  .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
  .instruction { opcode := .exit }
]

def lowerComputeUnitsLogAction (action : ComputeUnitsLogAction) : Array AstNode :=
  #[
    .comment s!"solana.compute_units.log_action {action.name}"
  ] ++ callVoidHelperPreservingInput action.label

def lowerPubkeyLogAccountPtr (bindings : Array CpiAccountBinding)
    (action : PubkeyLogAction) : Array AstNode :=
  match cpiAccountBinding? bindings action.account with
  | some binding =>
      #[
        .comment s!"solana.log.pubkey.ptr {action.name} account={action.account}",
        .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
        .instruction { opcode := .add64, dst := some .r1, imm := some (.num binding.layout.keyOff) }
      ]
  | none =>
      #[
        .comment s!"solana.log.pubkey.ptr {action.name} account={action.account} missing placeholder=zero"
      ] ++
      stackPtr .r1 memoryResultOffset ++
      lowerZero32 .r1

def lowerPubkeyLogHelper (accountBindings : Array CpiAccountBinding)
    (action : PubkeyLogAction) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.log.pubkey {action.name}: account={action.account}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 }
  ] ++
  lowerPubkeyLogAccountPtr accountBindings action ++ #[
    .comment "r1=pubkey_ptr",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_log_pubkey,
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerPubkeyLogAction (action : PubkeyLogAction) : Array AstNode :=
  #[
    .comment s!"solana.log.pubkey_action {action.name}"
  ] ++ callVoidHelperPreservingInput action.label

def lowerDataLogStatePtr (bindings : Array CpiValueBinding)
    (action : DataLogAction) (dst inputBase : Reg) : Array AstNode :=
  match stateValueBinding? bindings action.sourceState with
  | some binding =>
      #[
        .comment s!"solana.log.data.ptr {action.name} state={action.sourceState} input+{binding.absOff}",
        .instruction { opcode := .mov64, dst := some dst, src := some inputBase },
        .instruction { opcode := .add64, dst := some dst, imm := some (.num binding.absOff) }
      ]
  | none =>
      #[
        .comment s!"solana.log.data.ptr {action.name} state={action.sourceState} missing placeholder=zero"
      ] ++
      stackPtr dst memoryResultOffset ++
      lowerZero32 dst

def lowerDataLogSlice (valueBindings : Array CpiValueBinding)
    (action : DataLogAction) : Array AstNode :=
  lowerDataLogStatePtr valueBindings action .r5 .r7 ++
  stackPtr .r6 logDataSliceTableOffset ++ #[
    .instruction { opcode := .stxdw, dst := some .r6, off := some (.num 0), src := some .r5 },
    loadImm .r3 action.bytes,
    .instruction { opcode := .stxdw, dst := some .r6, off := some (.num 8), src := some .r3 }
  ]

def lowerDataLogHelper (valueBindings : Array CpiValueBinding)
    (action : DataLogAction) : Array AstNode :=
  #[
    .blankLine,
    .comment s!"solana.log.data {action.name}: source={action.sourceState} bytes={action.bytes}",
    .label action.label,
    .instruction { opcode := .mov64, dst := some .r7, src := some .r1 },
    .comment "pack SolBytes slice array for sol_log_data"
  ] ++
  lowerDataLogSlice valueBindings action ++
  stackPtr .r1 logDataSliceTableOffset ++ #[
    loadImm .r2 1,
    .comment "r1=slices_ptr r2=num_slices",
    callSyscall ProofForge.Backend.Solana.Syscalls.sol_log_data,
    .instruction { opcode := .mov64, dst := some .r1, src := some .r7 },
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit }
  ]

def lowerDataLogAction (action : DataLogAction) : Array AstNode :=
  #[
    .comment s!"solana.log.data_action {action.name}"
  ] ++ callVoidHelperPreservingInput action.label

def pushUniqueMemoryHelper (actions : Array MemoryAction)
    (action : MemoryAction) : Array MemoryAction :=
  if actions.any (fun existing => existing.name == action.name && existing.op == action.op) then
    actions
  else
    actions.push action

def uniqueMemoryHelpers (extensions : ProgramExtensions) : Array MemoryAction :=
  extensions.memoryActions.foldl pushUniqueMemoryHelper #[]

def pushUniqueCryptoHashHelper (actions : Array CryptoHashAction)
    (action : CryptoHashAction) : Array CryptoHashAction :=
  if actions.any (fun existing => existing.name == action.name && existing.op == action.op) then
    actions
  else
    actions.push action

def uniqueCryptoHashHelpers (extensions : ProgramExtensions) : Array CryptoHashAction :=
  extensions.cryptoHashActions.foldl pushUniqueCryptoHashHelper #[]

def pushUniqueSysvarHelper (actions : Array SysvarReadAction)
    (action : SysvarReadAction) : Array SysvarReadAction :=
  if actions.any (fun existing =>
      existing.name == action.name &&
      existing.kind == action.kind &&
      existing.field == action.field) then
    actions
  else
    actions.push action

def uniqueSysvarHelpers (extensions : ProgramExtensions) : Array SysvarReadAction :=
  extensions.sysvarActions.foldl pushUniqueSysvarHelper #[]

def pushUniqueReturnDataHelper (actions : Array ReturnDataAction)
    (action : ReturnDataAction) : Array ReturnDataAction :=
  if actions.any (fun existing => existing.name == action.name) then
    actions
  else
    actions.push action

def uniqueReturnDataHelpers (extensions : ProgramExtensions) : Array ReturnDataAction :=
  extensions.returnDataActions.foldl pushUniqueReturnDataHelper #[]

def pushUniqueReturnDataReadHelper (actions : Array ReturnDataReadAction)
    (action : ReturnDataReadAction) : Array ReturnDataReadAction :=
  if actions.any (fun existing => existing.name == action.name) then
    actions
  else
    actions.push action

def uniqueReturnDataReadHelpers (extensions : ProgramExtensions) : Array ReturnDataReadAction :=
  extensions.returnDataReadActions.foldl pushUniqueReturnDataReadHelper #[]

def pushUniqueComputeUnitsHelper (actions : Array ComputeUnitsAction)
    (action : ComputeUnitsAction) : Array ComputeUnitsAction :=
  if actions.any (fun existing => existing.name == action.name) then
    actions
  else
    actions.push action

def uniqueComputeUnitsHelpers (extensions : ProgramExtensions) : Array ComputeUnitsAction :=
  extensions.computeUnitsActions.foldl pushUniqueComputeUnitsHelper #[]

def pushUniqueComputeUnitsLogHelper (actions : Array ComputeUnitsLogAction)
    (action : ComputeUnitsLogAction) : Array ComputeUnitsLogAction :=
  if actions.any (fun existing => existing.name == action.name) then
    actions
  else
    actions.push action

def uniqueComputeUnitsLogHelpers (extensions : ProgramExtensions) : Array ComputeUnitsLogAction :=
  extensions.computeUnitsLogActions.foldl pushUniqueComputeUnitsLogHelper #[]

def pushUniquePubkeyLogHelper (actions : Array PubkeyLogAction)
    (action : PubkeyLogAction) : Array PubkeyLogAction :=
  if actions.any (fun existing => existing.name == action.name && existing.account == action.account) then
    actions
  else
    actions.push action

def uniquePubkeyLogHelpers (extensions : ProgramExtensions) : Array PubkeyLogAction :=
  extensions.pubkeyLogActions.foldl pushUniquePubkeyLogHelper #[]

def pushUniqueDataLogHelper (actions : Array DataLogAction)
    (action : DataLogAction) : Array DataLogAction :=
  if actions.any (fun existing =>
      existing.name == action.name &&
      existing.sourceState == action.sourceState) then
    actions
  else
    actions.push action

def uniqueDataLogHelpers (extensions : ProgramExtensions) : Array DataLogAction :=
  extensions.dataLogActions.foldl pushUniqueDataLogHelper #[]

def pushUniqueAccountReallocHelper (actions : Array AccountReallocAction)
    (action : AccountReallocAction) : Array AccountReallocAction :=
  if actions.any (fun existing =>
      existing.name == action.name &&
      existing.account == action.account &&
      existing.newSize == action.newSize) then
    actions
  else
    actions.push action

def uniqueAccountReallocHelpers (extensions : ProgramExtensions) : Array AccountReallocAction :=
  extensions.accountReallocActions.foldl pushUniqueAccountReallocHelper #[]

def lowerAccountReallocHelper (accountBindings : Array CpiAccountBinding)
    (action : AccountReallocAction) : Array AstNode :=
  match cpiAccountBinding? accountBindings action.account with
  | some binding =>
      #[
        .blankLine,
        .comment s!"solana.account.realloc {action.name}: account={action.account} new_size={action.newSize} max_increase={MAX_PERMITTED_DATA_INCREASE}",
        .label action.label
      ] ++
      inputAccountFieldPtr .r7 binding.layout binding.layout.dataLenOff ++ #[
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r7, off := some (.num 0) },
        .instruction { opcode := .add64, dst := some .r2, imm := some (.num MAX_PERMITTED_DATA_INCREASE) },
        .instruction { opcode := .jlt, dst := some .r2, imm := some (.num action.newSize), off := some (.sym "error_realloc") }
      ] ++
      inputAccountFieldPtr .r7 binding.layout binding.layout.dataLenOff ++ #[
        loadImm .r2 action.newSize,
        storeReg .stxdw .r7 0 .r2,
        .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
        .instruction { opcode := .exit }
      ]
  | none =>
      #[
        .blankLine,
        .comment s!"solana.account.realloc {action.name}: missing account={action.account}",
        .label action.label,
        .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 1) },
        .instruction { opcode := .exit }
      ]

def lowerPdaAction (action : PdaAction) : Array AstNode :=
  #[
    .comment s!"solana.pda.action {action.name}"
  ] ++ callHelperPreservingInput (PdaDerive.label { name := action.name }) "error_pda"

def lowerCpiAction (action : CpiAction) : Array AstNode :=
  #[
    .comment s!"solana.cpi.action {action.name}"
  ] ++ callHelperPreservingInput (CpiInvoke.label {
    name := action.name
    program := ""
    instruction := ""
  }) "error_cpi"

def lowerAccountReallocAction (action : AccountReallocAction) : Array AstNode :=
  #[
    .comment s!"solana.account.realloc.action {action.name}"
  ] ++ callHelperPreservingInput action.label "error_realloc"

def lowerEntrypointActions (extensions : ProgramExtensions) (entrypoint : String) : Array AstNode :=
  let pdaActions := extensions.pdaActions.filter (fun action => action.entrypoint == entrypoint)
  let cpiActions := extensions.cpiActions.filter (fun action => action.entrypoint == entrypoint)
  let memoryActions := extensions.memoryActions.filter (fun action => action.entrypoint == entrypoint)
  let cryptoHashActions := extensions.cryptoHashActions.filter (fun action => action.entrypoint == entrypoint)
  let sysvarActions := extensions.sysvarActions.filter (fun action => action.entrypoint == entrypoint)
  let returnDataActions := extensions.returnDataActions.filter (fun action => action.entrypoint == entrypoint)
  let returnDataReadActions := extensions.returnDataReadActions.filter (fun action => action.entrypoint == entrypoint)
  let computeUnitsActions := extensions.computeUnitsActions.filter (fun action => action.entrypoint == entrypoint)
  let computeUnitsLogActions := extensions.computeUnitsLogActions.filter (fun action => action.entrypoint == entrypoint)
  let pubkeyLogActions := extensions.pubkeyLogActions.filter (fun action => action.entrypoint == entrypoint)
  let dataLogActions := extensions.dataLogActions.filter (fun action => action.entrypoint == entrypoint)
  let accountReallocActions := extensions.accountReallocActions.filter (fun action => action.entrypoint == entrypoint)
  if pdaActions.isEmpty && cpiActions.isEmpty && memoryActions.isEmpty && cryptoHashActions.isEmpty &&
      sysvarActions.isEmpty && returnDataActions.isEmpty && returnDataReadActions.isEmpty &&
      computeUnitsActions.isEmpty && computeUnitsLogActions.isEmpty && pubkeyLogActions.isEmpty &&
      dataLogActions.isEmpty && accountReallocActions.isEmpty then
    #[]
  else
    #[.comment s!"Solana SDK target extension actions for {entrypoint}"] ++
    pdaActions.foldl (fun acc action => acc ++ lowerPdaAction action) #[] ++
    cpiActions.foldl (fun acc action => acc ++ lowerCpiAction action) #[] ++
    memoryActions.foldl (fun acc action => acc ++ lowerMemoryAction action) #[] ++
    cryptoHashActions.foldl (fun acc action => acc ++ lowerCryptoHashAction action) #[] ++
    sysvarActions.foldl (fun acc action => acc ++ lowerSysvarAction action) #[] ++
    returnDataActions.foldl (fun acc action => acc ++ lowerReturnDataAction action) #[] ++
    returnDataReadActions.foldl (fun acc action => acc ++ lowerReturnDataReadAction action) #[] ++
    computeUnitsActions.foldl (fun acc action => acc ++ lowerComputeUnitsAction action) #[] ++
    computeUnitsLogActions.foldl (fun acc action => acc ++ lowerComputeUnitsLogAction action) #[] ++
    pubkeyLogActions.foldl (fun acc action => acc ++ lowerPubkeyLogAction action) #[] ++
    dataLogActions.foldl (fun acc action => acc ++ lowerDataLogAction action) #[] ++
    accountReallocActions.foldl (fun acc action => acc ++ lowerAccountReallocAction action) #[]

def lowerExtensionErrors : Array AstNode := #[
  .blankLine,
  .label "error_pda",
  .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 7) },
  .instruction { opcode := .exit },
  .blankLine,
  .label "error_cpi",
  .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 8) },
  .instruction { opcode := .exit },
  .blankLine,
  .label "error_crypto",
  .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 11) },
  .instruction { opcode := .exit },
  .blankLine,
  .label "error_sysvar",
  .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 12) },
  .instruction { opcode := .exit },
  .blankLine,
  .label "error_realloc",
  .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 13) },
  .instruction { opcode := .exit }
]

def lowerRuntimeAllocator (allocator : RuntimeAllocator) : Array AstNode := #[
  .blankLine,
  .comment s!"solana.allocator {allocator.name}: kind={allocator.kind} model={allocator.model} heap_start={allocator.heapStart} heap_bytes={allocator.heapBytes}"
]

def lowerRuntimeAllocators (extensions : ProgramExtensions) : Array AstNode :=
  extensions.allocators.foldl (fun acc allocator => acc ++ lowerRuntimeAllocator allocator) #[]

def lowerProgramExtensionsWithBindings
    (accountBindings : Array CpiAccountBinding) (valueBindings : Array CpiValueBinding)
    (extensions : ProgramExtensions) : Array AstNode :=
  if !hasExtensions extensions then
    #[]
  else if !hasSyscallExtensions extensions then
    #[.blankLine, .comment "Solana SDK target extension metadata"] ++
    lowerRuntimeAllocators extensions
  else
    #[.blankLine, .comment "Solana SDK target extension syscall helpers"] ++
    lowerRuntimeAllocators extensions ++
    extensions.pdas.foldl (fun acc pda => acc ++ lowerPdaDerive accountBindings valueBindings pda) #[] ++
    extensions.cpis.foldl (fun acc cpi => acc ++ lowerCpiInvoke accountBindings valueBindings cpi) #[] ++
    (uniqueMemoryHelpers extensions).foldl (fun acc action => acc ++ lowerMemoryHelper valueBindings action) #[] ++
    (uniqueCryptoHashHelpers extensions).foldl (fun acc action => acc ++ lowerCryptoHashHelper valueBindings action) #[] ++
    (uniqueSysvarHelpers extensions).foldl (fun acc action => acc ++ lowerSysvarHelper valueBindings action) #[] ++
    (uniqueReturnDataHelpers extensions).foldl (fun acc action => acc ++ lowerReturnDataHelper valueBindings action) #[] ++
    (uniqueReturnDataReadHelpers extensions).foldl (fun acc action => acc ++ lowerReturnDataReadHelper valueBindings action) #[] ++
    (uniqueComputeUnitsHelpers extensions).foldl (fun acc action => acc ++ lowerComputeUnitsHelper valueBindings action) #[] ++
    (uniqueComputeUnitsLogHelpers extensions).foldl (fun acc action => acc ++ lowerComputeUnitsLogHelper action) #[] ++
    (uniquePubkeyLogHelpers extensions).foldl (fun acc action => acc ++ lowerPubkeyLogHelper accountBindings action) #[] ++
    (uniqueDataLogHelpers extensions).foldl (fun acc action => acc ++ lowerDataLogHelper valueBindings action) #[] ++
    (uniqueAccountReallocHelpers extensions).foldl (fun acc action => acc ++ lowerAccountReallocHelper accountBindings action) #[] ++
    lowerExtensionErrors

def lowerProgramExtensionsWithAccountBindings
    (bindings : Array CpiAccountBinding) (extensions : ProgramExtensions) : Array AstNode :=
  lowerProgramExtensionsWithBindings bindings #[] extensions

def lowerProgramExtensions (extensions : ProgramExtensions) : Array AstNode :=
  lowerProgramExtensionsWithAccountBindings #[] extensions

def lowerPlan (plan : CapabilityPlan) : Array AstNode :=
  lowerProgramExtensions (ProgramExtensions.fromPlan plan)

end ProofForge.Backend.Solana.Extension
