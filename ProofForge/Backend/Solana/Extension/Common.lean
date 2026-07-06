import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.Extension.Parse
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Syscalls
import ProofForge.Target.Plan

/-! # Shared Solana extension lowering helpers

Small naming, stack-layout, binding lookup, and sBPF instruction helpers shared by
PDA, CPI, sysvar, logging, memory, and return-data extension lowering. -/

namespace ProofForge.Backend.Solana.Extension

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Target

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

def TransferHookExtraAccountMetaListAction.label
    (action : TransferHookExtraAccountMetaListAction) : String :=
  "sol_transfer_hook_extra_meta_" ++ labelPart action.name

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
def pdaSeedTableOffset : Nat := 384
def pdaSeedDataOffset : Nat := 512
def pdaMaxSeedLen : Nat := 32
def pdaMaxSeeds : Nat := 16

def cpiInstructionOffset : Nat := 64
def cpiAccountMetaOffset : Nat := 256
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

def storeImm (opcode : Opcode) (base : Reg) (off value : Nat) : AstNode :=
  .instruction { opcode, dst := some base, off := some (.num off), imm := some (.num value) }

def storeReg (opcode : Opcode) (base : Reg) (off : Nat) (src : Reg) : AstNode :=
  .instruction { opcode, dst := some base, off := some (.num off), src := some src }

def zeroStackQuad (base : Reg) (off : Nat) : AstNode :=
  storeImm .stdw base off 0

def loadImm (dst : Reg) (value : Nat) : AstNode :=
  .instruction { opcode := .mov64, dst := some dst, imm := some (.num value) }

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

def storePubkeyBytes (base : Reg) (bytes : Array Nat) : Array AstNode :=
  bytes.mapIdx fun idx byte => storeImm .stb base idx byte

end ProofForge.Backend.Solana.Extension
