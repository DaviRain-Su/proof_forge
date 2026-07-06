import ProofForge.Backend.Solana.Extension.Common

/-! # Solana CPI extension lowering

CPI-specific sBPF packing for program ids, account metas, account infos,
instruction data layouts, signer seeds, and invoke helpers. -/

namespace ProofForge.Backend.Solana.Extension

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Target

def boolByte (value : Bool) : Nat :=
  if value then 1 else 0

def cpiAccountWritable (account : AccountMeta) : Nat :=
  boolByte (account.access == "writable")

def cpiAccountSigner (account : AccountMeta) : Nat :=
  boolByte (account.signer != "none")

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

def lowerCpiPubkeyField (accountBindings : Array CpiAccountBinding)
    (cpi : CpiInvoke) (metadataKey fieldName : String) (fieldOff : Nat) : Array AstNode :=
  match cpiMetadataValue? cpi metadataKey with
  | some "program" => lowerCurrentProgramIdToData fieldOff
  | some source =>
      match cpiAccountBinding? accountBindings source with
      | some binding => lowerAccountKeyToDataField fieldName source binding.layout fieldOff
      | none =>
          #[
            .comment s!"solana.cpi.value {fieldName} source={source} placeholder=zero",
          ] ++ lowerZero32At .r8 fieldOff
  | none =>
      #[
        .comment s!"solana.cpi.value {fieldName} missing placeholder=zero",
      ] ++ lowerZero32At .r8 fieldOff

def lowerCpiSignerStackSeedPtr (idx : Nat) : Array AstNode :=
  stackPtr .r8 (cpiSignerSeedDataOffset + idx * cpiMaxSeedLen)

def lowerInputBytesToCpiSignerSeed (binding : CpiValueBinding) (byteSize : Nat) : Array AstNode :=
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
        .instruction { opcode := .stxb, dst := some .r8, off := some (.num idx), src := some .r3 }
      ])
    #[]

def lowerCpiSignerZeroSeedBytes (byteSize : Nat) : Array AstNode :=
  (List.range byteSize).foldl
    (fun acc idx =>
      acc.push <| .instruction {
        opcode := .stb,
        dst := some .r8,
        off := some (.num idx),
        imm := some (.num 0)
      })
    #[]

def lowerCpiSignerSeedTableEntry (idx len : Nat) : Array AstNode :=
  let tableOffset := cpiSignerSeedTableOffset - idx * 16
  stackPtr .r7 tableOffset ++ #[
    storeReg .stxdw .r7 0 .r8,
    loadImm .r3 len,
    storeReg .stxdw .r7 8 .r3
  ]

def lowerCpiSignerStaticSeed (cpiName : String) (idx : Nat) (seed : String) : Array AstNode :=
  let seedOffset := cpiSignerSeedDataOffset + idx * cpiMaxSeedLen
  let bytes := stringBytes seed
  #[
    .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] \"{seed}\""
  ] ++
  stackPtr .r8 seedOffset ++
  lowerSeedBytes seed .r8 ++
  lowerCpiSignerSeedTableEntry idx bytes.size

def lowerCpiSignerAccountSeed (bindings : Array CpiAccountBinding)
    (cpiName : String) (idx : Nat) (account : String) : Array AstNode :=
  match cpiAccountBinding? bindings account with
  | some binding =>
      #[
        .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] account {account} pubkey"
      ] ++
      lowerCpiSignerStackSeedPtr idx ++
      inputAccountFieldPtr .r7 binding.layout binding.layout.keyOff ++
      (List.range 32).foldl
        (fun acc byteIdx =>
          acc ++ #[
            .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num byteIdx) },
            .instruction { opcode := .stxb, dst := some .r8, off := some (.num byteIdx), src := some .r3 }
          ])
        #[] ++
      lowerCpiSignerSeedTableEntry idx 32
  | none =>
      #[
        .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] account {account} missing placeholder=zero"
      ] ++
      lowerCpiSignerStackSeedPtr idx ++
      lowerCpiSignerZeroSeedBytes 32 ++
      lowerCpiSignerSeedTableEntry idx 32

def lowerCpiSignerBumpSeed (bindings : Array CpiValueBinding)
    (cpiName : String) (idx : Nat) (source : String) : Array AstNode :=
  match source.toNat? with
  | some bump =>
      if bump < 256 then
        #[
          .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] bump literal={bump}"
        ] ++
        lowerCpiSignerStackSeedPtr idx ++ #[
          storeImm .stb .r8 0 bump
        ] ++
        lowerCpiSignerSeedTableEntry idx 1
      else
        #[
          .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] bump literal={bump} out-of-range (revert)",
          .instruction { opcode := .ja, off := some (.sym "error_pda_bump") }
        ]
  | none =>
      match cpiValueBinding? bindings source with
      | some binding =>
          #[
            .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] bump {source} from {binding.sourceKind}"
          ] ++
          lowerCpiSignerStackSeedPtr idx ++
          lowerInputBytesToCpiSignerSeed binding 1 ++
          lowerCpiSignerSeedTableEntry idx 1
      | none =>
          #[
            .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] bump {source} missing (revert)",
            .instruction { opcode := .ja, off := some (.sym "error_pda_bump") }
          ]

def lowerCpiSignerInstructionParamSeed (bindings : Array CpiValueBinding)
    (cpiName : String) (idx : Nat) (source : String) : Array AstNode :=
  match cpiValueBinding? bindings source with
  | some binding =>
      #[
        .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] instruction-param {source} from {binding.sourceKind}"
      ] ++
      lowerCpiSignerStackSeedPtr idx ++
      lowerInputBytesToCpiSignerSeed binding binding.byteSize ++
      lowerCpiSignerSeedTableEntry idx binding.byteSize
  | none =>
      #[
        .comment s!"solana.cpi.signer_seed {cpiName}[{idx}] instruction-param {source} missing placeholder=zero"
      ] ++
      lowerCpiSignerStackSeedPtr idx ++
      lowerCpiSignerZeroSeedBytes 1 ++
      lowerCpiSignerSeedTableEntry idx 1

def lowerCpiSignerSeed (accountBindings : Array CpiAccountBinding)
    (valueBindings : Array CpiValueBinding) (cpiName : String) (idx : Nat)
    (raw : String) : Array AstNode :=
  let seed := parsePdaSeed raw
  match seed.kind with
  | .literal => lowerCpiSignerStaticSeed cpiName idx seed.value
  | .account => lowerCpiSignerAccountSeed accountBindings cpiName idx seed.value
  | .bump => lowerCpiSignerBumpSeed valueBindings cpiName idx seed.value
  | .instructionParam => lowerCpiSignerInstructionParamSeed valueBindings cpiName idx seed.value

def lowerCpiSignerSeeds (accountBindings : Array CpiAccountBinding)
    (valueBindings : Array CpiValueBinding) (cpi : CpiInvoke) : Array AstNode :=
  if cpi.signerSeeds.isEmpty then
    #[
      .comment "solana.cpi.signer_seeds none"
    ]
  else
    let seedTable :=
      cpi.signerSeeds.mapIdx (fun idx seed =>
        lowerCpiSignerSeed accountBindings valueBindings cpi.name idx seed)
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

/-- Initialize metadata pointer: u8 instruction=39, u8 sub=0, pubkey authority,
    pubkey metadata_address. -/
def lowerToken2022InitializeMetadataPointerData (accountBindings : Array CpiAccountBinding)
    (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_metadata_pointer: u8 instruction=39, u8 metadata_pointer_instruction=0, pubkey authority, pubkey metadata_address"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 39,
    storeImm .stb .r8 1 0
  ] ++
  lowerCpiPubkeyField accountBindings cpi
    "solana.cpi.metadata_pointer_authority" "metadata_pointer_authority" 2 ++
  lowerCpiPubkeyField accountBindings cpi
    "solana.cpi.metadata_address" "metadata_address" 34

/-- Initialize default account state: u8 instruction=28, u8 sub=0, u8 state.
    SPL Token encodes initialized as 1 and frozen as 2. The state value comes
    from `solana.cpi.default_account_state` metadata as a literal string. -/
def lowerToken2022InitializeDefaultAccountStateData (cpi : CpiInvoke) : Array AstNode :=
  let stateVal :=
    match cpiMetadataValue? cpi "solana.cpi.default_account_state" with
    | some value => value.toNat?.getD 1
    | none => 1
  #[
    .comment s!"solana.cpi.data token-2022.initialize_default_account_state: u8 instruction=28, u8 default_account_state_instruction=0, u8 state={stateVal}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 28,
    storeImm .stb .r8 1 0,
    storeImm .stb .r8 2 stateVal
  ]

/-- Initialize immutable owner: u8 instruction=22 (discriminator only, no extra data). -/
def lowerToken2022InitializeImmutableOwnerData : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_immutable_owner: u8 instruction=22"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 22
  ]

def lowerToken2022InitializePermanentDelegateData
    (accountBindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_permanent_delegate: u8 instruction=35, pubkey delegate"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 35
  ] ++
  lowerCpiPubkeyField accountBindings cpi
    "solana.cpi.permanent_delegate" "permanent_delegate" 1

def token2022InterestRate (cpi : CpiInvoke) : Nat :=
  match cpiMetadataValue? cpi "solana.cpi.interest_rate" with
  | some value => value.toNat?.getD 0
  | none => 0

def lowerToken2022InitializeInterestBearingMintData
    (accountBindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  let rate := token2022InterestRate cpi
  #[
    .comment s!"solana.cpi.data token-2022.initialize_interest_bearing_mint: u8 instruction=33, u8 interest_bearing_mint_instruction=0, pubkey rate_authority, i16 rate={rate}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 33,
    storeImm .stb .r8 1 0
  ] ++
  lowerCpiPubkeyField accountBindings cpi
    "solana.cpi.interest_rate_authority" "interest_rate_authority" 2 ++ #[
    loadImm .r3 rate,
    storeReg .stxh .r8 34 .r3
  ]

def token2022MemoTransferInstruction (cpi : CpiInvoke) : Nat :=
  match cpiMetadataValue? cpi "solana.cpi.memo_transfer_required" with
  | some "false" => 1
  | some "disable" => 1
  | some "disabled" => 1
  | _ => 0

def lowerToken2022MemoTransferData (cpi : CpiInvoke) : Array AstNode :=
  let subTag := token2022MemoTransferInstruction cpi
  #[
    .comment s!"solana.cpi.data token-2022.enable_required_memo_transfers: u8 instruction=30, u8 memo_transfer_instruction={subTag}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 30,
    storeImm .stb .r8 1 subTag
  ]

/-- Initialize transfer hook: u8 instruction=36, u8 sub=0, pubkey authority,
    pubkey transfer_hook_program_id. This initializes the mint extension; hook
    execute/extra-account-meta routing is tracked separately. -/
def lowerToken2022InitializeTransferHookData
    (accountBindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_transfer_hook: u8 instruction=36, u8 transfer_hook_instruction=0, pubkey authority, pubkey transfer_hook_program_id"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 36,
    storeImm .stb .r8 1 0
  ] ++
  lowerCpiPubkeyField accountBindings cpi
    "solana.cpi.transfer_hook_authority" "transfer_hook_authority" 2 ++
  lowerCpiPubkeyField accountBindings cpi
    "solana.cpi.transfer_hook_program" "transfer_hook_program" 34

def lowerToken2022InitializePausableConfigData
    (accountBindings : Array CpiAccountBinding) (cpi : CpiInvoke) : Array AstNode :=
  #[
    .comment "solana.cpi.data token-2022.initialize_pausable_config: u8 instruction=44, u8 pausable_instruction=0, pubkey authority"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 44,
    storeImm .stb .r8 1 0
  ] ++
  lowerCpiPubkeyField accountBindings cpi
    "solana.cpi.pausable_authority" "pausable_authority" 2

def lowerToken2022PausableTagData (layoutName : String) (subTag : Nat) : Array AstNode :=
  #[
    .comment s!"solana.cpi.data {layoutName}: u8 instruction=44, u8 pausable_instruction={subTag}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 44,
    storeImm .stb .r8 1 subTag
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

def lowerAssociatedTokenCreateData (layout : String) (tag : Nat) : Array AstNode :=
  #[
    .comment s!"solana.cpi.data {layout}: u8 instruction={tag}"
  ] ++
  stackPtr .r8 cpiInstructionDataOffset ++ #[
    storeImm .stb .r8 0 tag
  ]

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
  | some "associated-token.create" =>
      (lowerAssociatedTokenCreateData "associated-token.create" 0, 1)
  | some "associated-token.create_idempotent" =>
      (lowerAssociatedTokenCreateData "associated-token.create_idempotent" 1, 1)
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
      (lowerToken2022InitializeMetadataPointerData accountBindings cpi, 66)
  | some "token-2022.initialize_default_account_state" =>
      (lowerToken2022InitializeDefaultAccountStateData cpi, 3)
  | some "token-2022.initialize_immutable_owner" =>
      (lowerToken2022InitializeImmutableOwnerData, 1)
  | some "token-2022.initialize_permanent_delegate" =>
      (lowerToken2022InitializePermanentDelegateData accountBindings cpi, 33)
  | some "token-2022.initialize_interest_bearing_mint" =>
      (lowerToken2022InitializeInterestBearingMintData accountBindings cpi, 36)
  | some "token-2022.enable_required_memo_transfers" =>
      (lowerToken2022MemoTransferData cpi, 2)
  | some "token-2022.initialize_transfer_hook" =>
      (lowerToken2022InitializeTransferHookData accountBindings cpi, 66)
  | some "token-2022.initialize_pausable_config" =>
      (lowerToken2022InitializePausableConfigData accountBindings cpi, 34)
  | some "token-2022.pause" =>
      (lowerToken2022PausableTagData "token-2022.pause" 1, 2)
  | some "token-2022.resume" =>
      (lowerToken2022PausableTagData "token-2022.resume" 2, 2)
  | some "memo.memo" =>
      (lowerMemoData valueBindings cpi, 8)
  | some dl =>
      -- Known plan-scaffolded but unlowered Token-2022 extensions: fail at
      -- runtime with a logged error instead of silently emitting zero-data
      -- CPI (which would produce a no-op call). These dataLayouts have plan
      -- metadata in Token.lean but no sBPF instruction-data lowering yet.
      if dl == "token-2022.initialize_confidential_transfer_mint"
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
  lowerCpiSignerSeeds accountBindings valueBindings cpi ++
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
  lowerCpiSignerSeeds accountBindings valueBindings cpi ++
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

end ProofForge.Backend.Solana.Extension
