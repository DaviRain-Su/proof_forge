import ProofForge.Backend.Solana.Extension.Common

/-! # Solana PDA extension lowering

PDA seed normalization, seed packing, derived-address syscall emission, and
optional account validation for Solana extension helpers. -/

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

end ProofForge.Backend.Solana.Extension
