import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Solana.Extension.Types
import ProofForge.Target.Plan

namespace ProofForge.Backend.Solana.Extension

open ProofForge.Target

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

def pushUniqueString (values : Array String) (value : String) : Array String :=
  if values.any (fun existing => existing == value) then values else values.push value

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
  if acc.accounts.any (fun existing =>
      existing.name == account.name && existing.entrypoint? == account.entrypoint?) then
    { acc with
      accounts := acc.accounts.map fun existing =>
        if existing.name == account.name && existing.entrypoint? == account.entrypoint? then
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

def ProgramExtensions.pushTransferHookExtraAccountMetaListAction (acc : ProgramExtensions)
    (action : TransferHookExtraAccountMetaListAction) : ProgramExtensions :=
  if acc.transferHookExtraAccountMetaListActions.any (fun existing =>
      existing.name == action.name &&
      existing.account == action.account &&
      existing.extraAccounts == action.extraAccounts &&
      existing.entrypoint == action.entrypoint) then
    acc
  else
    { acc with transferHookExtraAccountMetaListActions :=
        acc.transferHookExtraAccountMetaListActions.push action }

def ProgramExtensions.pushAccountOrder (acc : ProgramExtensions)
    (names : Array String) : ProgramExtensions :=
  { acc with accountOrder := names.foldl pushUniqueString acc.accountOrder }

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

def ProgramExtensions.addTransferHookExtraAccountMetaList (acc : ProgramExtensions)
    (action : TransferHookExtraAccountMetaListAction) : ProgramExtensions :=
  acc.pushTransferHookExtraAccountMetaListAction action

def ProgramExtensions.addAccountOrder (acc : ProgramExtensions)
    (names : Array String) : ProgramExtensions :=
  acc.pushAccountOrder names

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

def accountOrderFromCall? (call : CapabilityCall) : Option (Array String) :=
  if call.capability == .accountExplicit &&
      metadataValue? call.metadata "solana.extension" == some "account_order" then
    metadataValue? call.metadata "solana.account_order.names" |>.map splitComma
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

def transferHookExtraAccountMetaListFromCall? (call : CapabilityCall) :
    Option TransferHookExtraAccountMetaListAction :=
  if call.capability == .accountExplicit &&
      metadataValue? call.metadata "solana.extension" == some "transfer_hook_extra_account_meta_list" then
    match entrypoint? call with
    | some entrypoint =>
        let extraAccounts :=
          match metadataValue? call.metadata "solana.transfer_hook_extra_meta.extra_accounts" with
          | some value => splitComma value
          | none =>
              metadataValue? call.metadata "solana.transfer_hook_extra_meta.extra_account"
                |>.map splitComma |>.getD #[]
        some {
          name := metadataValue? call.metadata "solana.transfer_hook_extra_meta.name"
            |>.getD call.operation
          account := metadataValue? call.metadata "solana.transfer_hook_extra_meta.account"
            |>.getD ""
          extraAccounts := extraAccounts
          entrypoint := entrypoint
        }
    | none => none
  else
    none

def ProgramExtensions.fromPlan (plan : CapabilityPlan) : ProgramExtensions :=
  plan.calls.foldl
    (fun acc call =>
      let acc :=
        match accountOrderFromCall? call with
        | some names => acc.addAccountOrder names
        | none => acc
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
      let acc :=
        match accountReallocFromCall? call with
        | some action => acc.addAccountRealloc action
        | none => acc
      match transferHookExtraAccountMetaListFromCall? call with
      | some action => acc.addTransferHookExtraAccountMetaList action
      | none => acc)
    {}

def hasExtensions (extensions : ProgramExtensions) : Bool :=
  extensions.accountOrder.size > 0 ||
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
    extensions.accountReallocActions.size > 0 ||
    extensions.transferHookExtraAccountMetaListActions.size > 0

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
    extensions.accountReallocActions.size > 0 ||
    extensions.transferHookExtraAccountMetaListActions.size > 0

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
    extensions.accountReallocActions.size > 0 ||
    extensions.transferHookExtraAccountMetaListActions.size > 0

end ProofForge.Backend.Solana.Extension
