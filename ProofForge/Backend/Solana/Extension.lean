import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.Extension.Common
import ProofForge.Backend.Solana.Extension.Cpi
import ProofForge.Backend.Solana.Extension.Parse
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Syscalls
import ProofForge.Target.Plan

namespace ProofForge.Backend.Solana.Extension

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Target

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

def lowerPdaStackSeedPtr (idx : Nat) : Array AstNode :=
  stackPtr .r5 (pdaSeedDataOffset + idx * pdaMaxSeedLen)

def lowerPdaSeedTableEntry (idx len : Nat) : Array AstNode :=
  let tableOffset := pdaSeedTableOffset - idx * 16
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

def transferHookExecuteDiscriminatorBytes : Array Nat :=
  #[105, 37, 101, 197, 75, 251, 102, 26]

def lowerCopyAccountKeyToData (sourceLayout : AccountInputLayout) (dataOff : Nat) :
    Array AstNode :=
  inputAccountFieldPtr .r7 sourceLayout sourceLayout.keyOff ++
  (List.range 32).foldl
    (fun acc idx =>
      acc ++ #[
        .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num idx) },
        storeReg .stxb .r8 (dataOff + idx) .r3
      ])
    #[]

def lowerTransferHookExtraAccountMetaListHelper
    (accountBindings : Array CpiAccountBinding)
    (action : TransferHookExtraAccountMetaListAction) : Array AstNode :=
  match cpiAccountBinding? accountBindings action.account with
  | some accountBinding =>
      let extraBindings :=
        action.extraAccounts.map (fun account => cpiAccountBinding? accountBindings account)
      if extraBindings.any (fun binding => binding.isNone) then
        #[
          .blankLine,
          .comment s!"solana.transfer_hook.extra_account_meta_list {action.name}: missing extra account binding",
          .label action.label,
          .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 1) },
          .instruction { opcode := .exit }
        ]
      else
      let extraBindings := extraBindings.filterMap id
      let count := extraBindings.size
      let listLen := 4 + count * 35
      let metaNodes :=
        extraBindings.foldl
          (fun acc binding =>
            let idx := acc.fst
            let nodes := acc.snd
            let metaOff := 16 + idx * 35
            (idx + 1,
              nodes ++ #[
                storeImm .stb .r8 metaOff 0
              ] ++ lowerCopyAccountKeyToData binding.layout (metaOff + 1) ++ #[
                storeImm .stb .r8 (metaOff + 33) 0,
                storeImm .stb .r8 (metaOff + 34) 0
              ]))
          (0, #[])
          |>.snd
      #[
        .blankLine,
        .comment s!"solana.transfer_hook.extra_account_meta_list {action.name}: account={action.account} extra_accounts={String.intercalate "," action.extraAccounts.toList}",
        .label action.label
      ] ++
      inputAccountFieldPtr .r8 accountBinding.layout accountBinding.layout.dataStart ++
      transferHookExecuteDiscriminatorBytes.mapIdx (fun idx byte => storeImm .stb .r8 idx byte) ++
      #[
        .comment s!"solana.transfer_hook.extra_account_meta_list: TLV ExecuteInstruction, static account metas={count}",
        storeImm .stw .r8 8 listLen,
        storeImm .stw .r8 12 count
      ] ++ metaNodes ++ #[
        .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
        .instruction { opcode := .exit }
      ]
  | none =>
      #[
        .blankLine,
        .comment s!"solana.transfer_hook.extra_account_meta_list {action.name}: missing account binding",
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

def lowerTransferHookExtraAccountMetaListAction
    (action : TransferHookExtraAccountMetaListAction) : Array AstNode :=
  #[
    .comment s!"solana.transfer_hook.extra_account_meta_list.action {action.name}"
  ] ++ callHelperPreservingInput action.label "error_transfer_hook_extra_meta"

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
  let transferHookExtraAccountMetaListActions :=
    extensions.transferHookExtraAccountMetaListActions.filter (fun action => action.entrypoint == entrypoint)
  if pdaActions.isEmpty && cpiActions.isEmpty && memoryActions.isEmpty && cryptoHashActions.isEmpty &&
      sysvarActions.isEmpty && returnDataActions.isEmpty && returnDataReadActions.isEmpty &&
      computeUnitsActions.isEmpty && computeUnitsLogActions.isEmpty && pubkeyLogActions.isEmpty &&
      dataLogActions.isEmpty && accountReallocActions.isEmpty &&
      transferHookExtraAccountMetaListActions.isEmpty then
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
    accountReallocActions.foldl (fun acc action => acc ++ lowerAccountReallocAction action) #[] ++
    transferHookExtraAccountMetaListActions.foldl
      (fun acc action => acc ++ lowerTransferHookExtraAccountMetaListAction action) #[]

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
  .instruction { opcode := .exit },
  .blankLine,
  .label "error_transfer_hook_extra_meta",
  .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 14) },
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
    extensions.transferHookExtraAccountMetaListActions.foldl
      (fun acc action => acc ++ lowerTransferHookExtraAccountMetaListHelper accountBindings action) #[] ++
    lowerExtensionErrors

def lowerProgramExtensionsWithAccountBindings
    (bindings : Array CpiAccountBinding) (extensions : ProgramExtensions) : Array AstNode :=
  lowerProgramExtensionsWithBindings bindings #[] extensions

def lowerProgramExtensions (extensions : ProgramExtensions) : Array AstNode :=
  lowerProgramExtensionsWithAccountBindings #[] extensions

def lowerPlan (plan : CapabilityPlan) : Array AstNode :=
  lowerProgramExtensions (ProgramExtensions.fromPlan plan)

end ProofForge.Backend.Solana.Extension
