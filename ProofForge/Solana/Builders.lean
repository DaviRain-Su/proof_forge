import ProofForge.Contract.Builder
import ProofForge.Solana.Programs

namespace ProofForge.Solana

open ProofForge.Target

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

def accountOrder (names : Array String) : ProofForge.Contract.Builder.ModuleM Unit :=
  ProofForge.Contract.Builder.capability .accountExplicit "solana.account_order"
    (source? := none)
    (metadata := #[
      kv "solana.extension" "account_order",
      kv "solana.account_order.names" (joinWith "," names)
    ])

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

def transferHookExtraAccountMetaListEntry
    (action : TransferHookExtraAccountMetaListAction) :
    ProofForge.Contract.Builder.EntryM Unit := do
  ProofForge.Contract.Builder.entryCapability .accountExplicit
    "solana.transfer_hook.extra_account_meta_list"
    (source? := some action.name)
    (metadata := action.metadata)

def initializeTransferHookExtraAccountMetaList
    (name account extraAccount : String) : ProofForge.Contract.Builder.EntryM Unit :=
  transferHookExtraAccountMetaListEntry {
    name := name
    account := account
    extraAccounts := #[extraAccount]
  }

def initializeTransferHookExtraAccountMetaListWithAccounts
    (name account : String) (extraAccounts : Array String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  transferHookExtraAccountMetaListEntry {
    name := name
    account := account
    extraAccounts := extraAccounts
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
    (signerSeeds : Array String := #[]) (requireProgramAccount : Bool := true) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (systemCreateAccountCall name payer newAccount lamportsSource spaceSource owner
    (signerSeeds := signerSeeds) (requireProgramAccount := requireProgramAccount))

def invokeSystemCreateAccount (name payer newAccount lamportsSource spaceSource owner : String)
    (signerSeeds : Array String := #[]) (requireProgramAccount : Bool := true) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (systemCreateAccountCall name payer newAccount lamportsSource spaceSource owner
    (signerSeeds := signerSeeds) (requireProgramAccount := requireProgramAccount))

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

def splToken2022InitializeMetadataPointer
    (name mint metadataPointerAuthority metadataAddress : String) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializeMetadataPointerCall name mint metadataPointerAuthority metadataAddress)

def invokeSplToken2022InitializeMetadataPointer
    (name mint metadataPointerAuthority metadataAddress : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializeMetadataPointerCall name mint metadataPointerAuthority metadataAddress)

def splToken2022InitializeDefaultAccountState
    (name mint : String) (accountState : Nat) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializeDefaultAccountStateCall name mint accountState)

def invokeSplToken2022InitializeDefaultAccountState
    (name mint : String) (accountState : Nat) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializeDefaultAccountStateCall name mint accountState)

def splToken2022InitializeImmutableOwner (name account : String) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializeImmutableOwnerCall name account)

def invokeSplToken2022InitializeImmutableOwner (name account : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializeImmutableOwnerCall name account)

def splToken2022InitializePermanentDelegate
    (name mint permanentDelegate : String) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializePermanentDelegateCall name mint permanentDelegate)

def invokeSplToken2022InitializePermanentDelegate
    (name mint permanentDelegate : String) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializePermanentDelegateCall name mint permanentDelegate)

def splToken2022InitializeInterestBearingMint
    (name mint rateAuthority : String) (rate : Nat) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializeInterestBearingMintCall name mint rateAuthority rate)

def invokeSplToken2022InitializeInterestBearingMint
    (name mint rateAuthority : String) (rate : Nat) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializeInterestBearingMintCall name mint rateAuthority rate)

def splToken2022EnableRequiredMemoTransfers
    (name account authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022EnableRequiredMemoTransfersCall name account authority
    (signerSeeds := signerSeeds))

def invokeSplToken2022EnableRequiredMemoTransfers
    (name account authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022EnableRequiredMemoTransfersCall name account authority
    (signerSeeds := signerSeeds))

def splToken2022InitializeTransferHook
    (name mint authority transferHookProgram : String) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializeTransferHookCall name mint authority transferHookProgram)

def invokeSplToken2022InitializeTransferHook
    (name mint authority transferHookProgram : String) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializeTransferHookCall name mint authority transferHookProgram)

def splToken2022InitializePausableConfig
    (name mint authority : String) : ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022InitializePausableConfigCall name mint authority)

def invokeSplToken2022InitializePausableConfig
    (name mint authority : String) : ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022InitializePausableConfigCall name mint authority)

def splToken2022Pause
    (name mint authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022PauseCall name mint authority (signerSeeds := signerSeeds))

def invokeSplToken2022Pause
    (name mint authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022PauseCall name mint authority (signerSeeds := signerSeeds))

def splToken2022Resume
    (name mint authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (splToken2022ResumeCall name mint authority (signerSeeds := signerSeeds))

def invokeSplToken2022Resume
    (name mint authority : String) (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (splToken2022ResumeCall name mint authority (signerSeeds := signerSeeds))

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

def associatedTokenCreate (name funding account wallet mint : String)
    (idempotent : Bool := true)
    (associatedProgram : String := associatedTokenProgram)
    (systemProgramName : String := systemProgram)
    (tokenProgramName : String := splTokenProgram)
    (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.ModuleM Unit :=
  cpi (associatedTokenCreateCall name funding account wallet mint
    (idempotent := idempotent)
    (associatedProgram := associatedProgram)
    (systemProgramName := systemProgramName)
    (tokenProgramName := tokenProgramName)
    (signerSeeds := signerSeeds))

def invokeAssociatedTokenCreate (name funding account wallet mint : String)
    (idempotent : Bool := true)
    (associatedProgram : String := associatedTokenProgram)
    (systemProgramName : String := systemProgram)
    (tokenProgramName : String := splTokenProgram)
    (signerSeeds : Array String := #[]) :
    ProofForge.Contract.Builder.EntryM Unit :=
  cpiEntry (associatedTokenCreateCall name funding account wallet mint
    (idempotent := idempotent)
    (associatedProgram := associatedProgram)
    (systemProgramName := systemProgramName)
    (tokenProgramName := tokenProgramName)
    (signerSeeds := signerSeeds))

end ProofForge.Solana
