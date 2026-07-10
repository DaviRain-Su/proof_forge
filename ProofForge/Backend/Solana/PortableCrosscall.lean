/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Portable crosscall → Solana CPI materialization (Phase B.3)

Authors write portable `crosscall.invoke` (target program id / method / args as
u64-shaped values). Solana does not expose that as EVM CALL; it materializes as
CPI-shaped execution (general peer remote — not SPL/token-only):

* Instruction data: little-endian method tag (u64) followed by packed u64 args
* Program account: runtime account index = `target` (must be an executable
  program account in the transaction account list)
* Account vector: **pure peer** CPIs use an **empty** `AccountMeta`/`AccountInfo`
  pack (method+args in ix data; host accounts stay outer-only). When a **signer
  PDA** is declared, selective packing of signer|writable|program|executable
  accounts is used (cap `MAX_PORTABLE_CPI_ACCOUNTS`) together with seeds.
* Signers: when the module declares a **signer PDA**, effective seeds pack into
  `sol_invoke_signed_c` so the program can CPI as that PDA authority (vault /
  complex contract pattern)
* Result: first 8 bytes of `sol_get_return_data` if present, else 0

Account list auto-extension (module-level schema): when portable crosscall is
detected, the materializer ensures `payer` + `callee_program` roles exist.

**Account checks (Anchor/Pinocchio analogue)** are **not** in this packer.
They are emitted once per entrypoint by `SbpfAsm.lowerAccountValidations` from
the materialized `AccountEntry` flags (`signer` / `writable` / `owner`). This
module only packs CPI frames; prologue validation is the Solana backend's
constraint layer.
-/
import ProofForge.IR.Contract
import ProofForge.Target.CrosscallMaterialize
import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Extension.Common
import ProofForge.Backend.Solana.Extension.Types
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Syscalls

namespace ProofForge.Backend.Solana.PortableCrosscall

open ProofForge.IR
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.Syscalls

/-! ## Dedicated portable CPI frame (stack metas + stack infos)

Does **not** reuse Extension CPI offsets so Source.Solana hand-tuned CPI keeps
its layout.

```
STACK (r10-relative):
  portableCpiIxOffset          SolInstruction (40)
  portableCpiMetaOffset        AccountMeta[64] (64×16 = 1024)
  portableCpiProgramIdOffset   program id (32)
  portableCpiDataOffset        ix data (portable args)
  portableReturnDataOffset     return-data buffer
  portableTargetIndexSave      target account index word
  accountPtrTableOffset        64 account ptrs (entry prologue)
  entryInputSaveOffset …

HEAP (absolute, HEAP_START_ADDRESS):
  SolAccountInfo[64]           64×56 = 3584 bytes reserved at heap start
```
-/

def portableCpiIxOffset : Nat := 64
def portableCpiMetaOffset : Nat := 128
/-- Metas: full lock limit on stack (`64 × 16` from offset 128 → ends 1152). -/
def portableCpiProgramIdOffset : Nat :=
  portableCpiMetaOffset + MAX_PORTABLE_CPI_ACCOUNTS * 16  -- 128+1024=1152
def portableCpiDataOffset : Nat := portableCpiProgramIdOffset + 32  -- 1184
/-- Absolute heap base for AccountInfo array (not r10-relative).
Prefer stack packing when the selective account count fits; heap remains a
fallback for large account sets. -/
def portableCpiInfoHeapBase : Nat := HEAP_START_ADDRESS
/-- Stack-relative AccountInfo array (PF-P2-03). Matches Extension CPI which
packs infos on the frame rather than absolute heap — avoids InvalidArgument
from address-restriction checks under current Mollusk/Agave. 16×56 = 896 B. -/
def portableCpiInfoStackOffset : Nat := 2048
def portableCpiInfoStackSlots : Nat := 16
/-- Return-data byte buffer (8 bytes). Addresses are `r10 - offset`. -/
def portableReturnDataOffset : Nat := 3200
/-- Program-id out buffer for `sol_get_return_data` (32 bytes).
Must not overlap the return-data buffer in VM address space:
`[r10-off, r10-off+len)`. With data at 3200/len 8, program id needs
offset ≥ 3232 or ≤ 3192. Was 3208 → Overlapping copy (PF-P2-03). -/
def portableReturnDataProgramIdOffset : Nat := 3240
def portableTargetIndexSaveOffset : Nat := 3280

/-- Force r3 to boolean 0/1 (Agave CPI rejects flag bytes > 1 with InvalidArgument). -/
def booleanizeR3 (zeroLabel : String) : Array AstNode :=
  #[
    .instruction {
      opcode := .jeq
      dst := some .r3
      imm := some (.num 0)
      off := some (.sym zeroLabel)
    },
    .instruction { opcode := .mov64, dst := some .r3, imm := some (.num 1) },
    .label zeroLabel
  ]

/-- Store r2 (u64) into portable instruction data at word index `wordIdx`. -/
def storeIxDataWord (wordIdx : Nat) : Array AstNode :=
  stackPtr .r8 portableCpiDataOffset ++ #[
    .instruction {
      opcode := .stxdw
      dst := some .r8
      off := some (.num (wordIdx * 8))
      src := some .r2
    }
  ]

/-- Copy 32-byte pubkey from the input account at runtime index (stack word at
`portableTargetIndexSaveOffset`) into `portableCpiProgramIdOffset`. -/
def copyProgramIdFromAccountIndex : Array AstNode :=
  #[
    .comment "portable CPI: program_id ← input account[target].key (32 bytes)"
  ] ++
  stackPtr .r6 accountPtrTableOffset ++ #[
    .instruction {
      opcode := .ldxdw
      dst := some .r2
      src := some .r10
      off := some (.num portableTargetIndexSaveOffset)
    },
    .instruction { opcode := .mul64, dst := some .r2, imm := some (.num 8) },
    .instruction { opcode := .add64, dst := some .r6, src := some .r2 },
    .instruction { opcode := .ldxdw, dst := some .r7, src := some .r6, off := some (.num 0) },
    .instruction { opcode := .add64, dst := some .r7, imm := some (.num ACCOUNT_HEADER_SIZE) }
  ] ++
  stackPtr .r8 portableCpiProgramIdOffset ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 0) },
    storeReg .stxdw .r8 0 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 8) },
    storeReg .stxdw .r8 8 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 16) },
    storeReg .stxdw .r8 16 .r3,
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r7, off := some (.num 24) },
    storeReg .stxdw .r8 24 .r3
  ]

/-- Solana limits used by portable CPI packing (re-exported for asm comments). -/
def maxPortableCpiAccounts : Nat := MAX_PORTABLE_CPI_ACCOUNTS
def maxTxAccountLocks : Nat := MAX_TX_ACCOUNT_LOCKS

/-- Load input account pointer at a **compile-time** account index into r7. -/
def loadAccountPtrFixed (accountIndex : Nat) : Array AstNode :=
  stackPtr .r6 accountPtrTableOffset ++ #[
    .instruction {
      opcode := .ldxdw
      dst := some .r7
      src := some .r6
      off := some (.num (accountIndex * 8))
    }
  ]

/-- Resolve input account pointer for runtime index (saved target) into r7. -/
def loadTargetAccountPtr : Array AstNode :=
  stackPtr .r6 accountPtrTableOffset ++ #[
    .instruction {
      opcode := .ldxdw
      dst := some .r2
      src := some .r10
      off := some (.num portableTargetIndexSaveOffset)
    },
    .instruction { opcode := .mul64, dst := some .r2, imm := some (.num 8) },
    .instruction { opcode := .add64, dst := some .r6, src := some .r2 },
    .instruction { opcode := .ldxdw, dst := some .r7, src := some .r6, off := some (.num 0) }
  ]

/-- After r7 holds the account start pointer, write AccountMeta at CPI slot.
Signer/writable flags are read from the Solana input account header and
**booleanized to 0/1** (Agave rejects flag bytes > 1 with InvalidArgument).
`siteTag` must be unique per CPI site so labels do not collide. -/
def storeAccountMetaFromR7 (siteTag : String) (cpiSlot inputIndex : Nat) : Array AstNode :=
  let metaOffset := cpiSlot * 16
  let signerOff := 1
  let writableOff := 2
  let wLab := s!"{siteTag}_meta_w{cpiSlot}"
  let sLab := s!"{siteTag}_meta_s{cpiSlot}"
  #[
    .comment s!"portable CPI: AccountMeta[{cpiSlot}] ← input account[{inputIndex}] header flags"
  ] ++
  stackPtr .r6 portableCpiMetaOffset ++ #[
    .instruction { opcode := .add64, dst := some .r6, imm := some (.num metaOffset) },
    -- Zero the 16-byte meta slot (padding must not leak garbage into bools).
    -- Use `stdw` (store immediate), not `stxdw` (store register).
    storeImm .stdw .r6 0 0,
    storeImm .stdw .r6 8 0,
    -- key_ptr = account + ACCOUNT_HEADER_SIZE
    .instruction { opcode := .mov64, dst := some .r8, src := some .r7 },
    .instruction { opcode := .add64, dst := some .r8, imm := some (.num ACCOUNT_HEADER_SIZE) },
    storeReg .stxdw .r6 0 .r8,
    -- SolAccountMeta: is_writable @ 8, is_signer @ 9 (repr(C) order).
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num writableOff) }
  ] ++ booleanizeR3 wLab ++ #[
    storeReg .stxb .r6 8 .r3,
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num signerOff) }
  ] ++ booleanizeR3 sLab ++ #[
    storeReg .stxb .r6 9 .r3
  ]

/-- Load AccountInfo slot address into `dst` (stack packing, PF-P2-03). -/
def loadInfoPtr (dst : Reg) (slotIdx : Nat) : Array AstNode :=
  stackPtr dst portableCpiInfoStackOffset ++ #[
    .instruction {
      opcode := .add64
      dst := some dst
      imm := some (.num (slotIdx * 56))
    }
  ]

/-- After r7 holds the account start pointer, write SolAccountInfo at CPI slot
on the **stack frame** (same approach as Extension CPI). -/
def storeAccountInfoFromR7 (siteTag : String) (cpiSlot inputIndex : Nat) : Array AstNode :=
  let signerOff := 1
  let writableOff := 2
  let executableOff := 3
  let keyRel := ACCOUNT_HEADER_SIZE
  let ownerRel := ACCOUNT_HEADER_SIZE + PUBKEY_SIZE
  let lamportsRel := ownerRel + PUBKEY_SIZE
  let dataLenRel := lamportsRel + U64_SIZE
  let dataStartRel := dataLenRel + U64_SIZE
  let sLab := s!"{siteTag}_info_s{cpiSlot}"
  let wLab := s!"{siteTag}_info_w{cpiSlot}"
  let eLab := s!"{siteTag}_info_e{cpiSlot}"
  #[
    .comment s!"portable CPI: AccountInfo[{cpiSlot}] @ stack-{portableCpiInfoStackOffset}+{cpiSlot * 56} ← input account[{inputIndex}]"
  ] ++
  loadInfoPtr .r6 cpiSlot ++ #[
    .instruction { opcode := .mov64, dst := some .r8, src := some .r7 },
    .instruction { opcode := .add64, dst := some .r8, imm := some (.num keyRel) },
    storeReg .stxdw .r6 0 .r8,
    .instruction { opcode := .mov64, dst := some .r8, src := some .r7 },
    .instruction { opcode := .add64, dst := some .r8, imm := some (.num lamportsRel) },
    storeReg .stxdw .r6 8 .r8,
    .instruction { opcode := .mov64, dst := some .r8, src := some .r7 },
    .instruction { opcode := .add64, dst := some .r8, imm := some (.num dataLenRel) },
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r8, off := some (.num 0) },
    storeReg .stxdw .r6 16 .r3,
    .instruction { opcode := .mov64, dst := some .r8, src := some .r7 },
    .instruction { opcode := .add64, dst := some .r8, imm := some (.num dataStartRel) },
    storeReg .stxdw .r6 24 .r8,
    .instruction { opcode := .mov64, dst := some .r8, src := some .r7 },
    .instruction { opcode := .add64, dst := some .r8, imm := some (.num ownerRel) },
    storeReg .stxdw .r6 32 .r8,
    loadImm .r3 0,
    storeReg .stxdw .r6 40 .r3,
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num signerOff) }
  ] ++ booleanizeR3 sLab ++ #[
    storeReg .stxb .r6 48 .r3,
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num writableOff) }
  ] ++ booleanizeR3 wLab ++ #[
    storeReg .stxb .r6 49 .r3,
    .instruction { opcode := .ldxb, dst := some .r3, src := some .r7, off := some (.num executableOff) }
  ] ++ booleanizeR3 eLab ++ #[
    storeReg .stxb .r6 50 .r3
  ]

/-- Pack AccountMeta + AccountInfo: CPI slot `cpiSlot` from input account `inputIndex`. -/
def packOneAccountSlot (siteTag : String) (cpiSlot inputIndex : Nat) : Array AstNode :=
  loadAccountPtrFixed inputIndex ++
  storeAccountMetaFromR7 siteTag cpiSlot inputIndex ++
  loadAccountPtrFixed inputIndex ++
  storeAccountInfoFromR7 siteTag cpiSlot inputIndex

/-- Accounts relevant to portable peer CPI (not every readonly spectator). -/
def isPortableCpiRelevantAccount (account : AccountEntry) : Bool :=
  account.signer ||
    account.writable ||
    account.owner == "executable" ||
    account.owner == "program"

/-- Select input-account indices for portable CPI packing, preserving schema
order. Empty result means "fall back to full 0..txAccountCount-1 range". -/
def selectPortableCpiAccountIndices (accounts : Array AccountEntry) : Array Nat :=
  accounts.filterMap fun a =>
    if isPortableCpiRelevantAccount a then some a.index else none

/-- Pack selected input accounts into consecutive CPI slots.
Metas + infos both on the stack frame (capped at `portableCpiInfoStackSlots`
so AccountInfo packing fits; still well above RemoteCall's 5 accounts). -/
def packSelectedAccounts (siteTag : String) (inputIndices : Array Nat) : Array AstNode :=
  let n := min inputIndices.size (min maxPortableCpiAccounts portableCpiInfoStackSlots)
  let indices := inputIndices.extract 0 n
  let idxList := String.intercalate "," (indices.toList.map toString)
  let header : Array AstNode := #[
    .comment s!"portable CPI: selective pack {n} accounts [{idxList}] (signer|writable|program|executable; infos@stack-{portableCpiInfoStackOffset}; max={portableCpiInfoStackSlots})"
  ]
  header ++
    (List.range n).foldl
      (fun acc slot =>
        match indices[slot]? with
        | some inputIdx => acc ++ packOneAccountSlot siteTag slot inputIdx
        | none => acc)
      (#[] : Array AstNode)

/-- Backward-compatible full-range pack (indices 0..accountCount-1). -/
def packAllTxAccounts (siteTag : String) (accountCount : Nat) : Array AstNode :=
  let n := min accountCount maxPortableCpiAccounts
  let n := if n == 0 then 1 else n
  packSelectedAccounts siteTag ((List.range n).toArray)

/-- Build SolInstruction C record: program_id, N account metas, ix data. -/
def packSolInstruction (dataLen accountCount : Nat) : Array AstNode :=
  #[
    .comment s!"portable CPI: SolInstruction (program_id, {accountCount} metas, ix data)"
  ] ++
  stackPtr .r5 portableCpiIxOffset ++
  stackPtr .r8 portableCpiProgramIdOffset ++ #[
    storeReg .stxdw .r5 0 .r8
  ] ++
  stackPtr .r7 portableCpiMetaOffset ++ #[
    storeReg .stxdw .r5 8 .r7,
    loadImm .r3 accountCount,
    storeReg .stxdw .r5 16 .r3
  ] ++
  stackPtr .r8 portableCpiDataOffset ++ #[
    storeReg .stxdw .r5 24 .r8,
    loadImm .r3 dataLen,
    storeReg .stxdw .r5 32 .r3
  ]

/-- After a successful CPI, read the first u64 of `sol_get_return_data` into r2.
If no return data (or length < 8), r2 := 0. Labels must be unique per site. -/
def decodeReturnDataU64 (retNoneLabel retEndLabel : String) : Array AstNode :=
  #[
    .comment "portable CPI: decode first u64 of sol_get_return_data → r2"
  ] ++
  stackPtr .r1 portableReturnDataOffset ++ #[
    loadImm .r2 8
  ] ++
  stackPtr .r3 portableReturnDataProgramIdOffset ++ #[
    -- Zero program-id out buffer with store-immediate (`stdw`), not `stxdw`.
    storeImm .stdw .r3 0 0,
    storeImm .stdw .r3 8 0,
    storeImm .stdw .r3 16 0,
    storeImm .stdw .r3 24 0,
    .comment "r1=data_ptr r2=max_len=8 r3=program_id_ptr (non-overlapping)",
    callSyscall sol_get_return_data,
    .instruction {
      opcode := .jlt
      dst := some .r0
      imm := some (.num 8)
      off := some (.sym retNoneLabel)
    }
  ] ++
  stackPtr .r3 portableReturnDataOffset ++ #[
    .instruction { opcode := .ldxdw, dst := some .r2, src := some .r3, off := some (.num 0) },
    .instruction { opcode := .ja, off := some (.sym retEndLabel) },
    .label retNoneLabel,
    .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 0) },
    .label retEndLabel
  ]

/-- Emit `sol_invoke_signed_c` for portable peer CPI.

**Packing policy (PF-P2-03):**
* `numSigners = 0` (pure peer method+args): **empty** AccountMeta/AccountInfo
  vectors. Method tag + args ride in ix data; `program_id` is a stack pubkey
  copy from the target input account. Outer host accounts (state, payer) are
  not forwarded — PeerOracleSum-style oracles need none. Protocol/SPL CPIs
  stay on Extension.Cpi with explicit metas.
* `numSigners > 0` (PDA authority): **selective** pack of
  `accountIndices` (signer|writable|program|executable) so the callee can see
  vault/authority accounts while seeds sign as the PDA.

When selective indices are empty but signers are present, packs account 0 as
a safe floor. Preserves r1 (entry input). Result in r2: first return-data u64
or 0. -/
def invokeSignedC (dataLen : Nat) (accountIndices : Array Nat) (numSigners : Nat)
    (signerSeedNodes : Array AstNode) (retNoneLabel retEndLabel : String) :
    Array AstNode :=
  let siteTag := retNoneLabel
  let useSelective := numSigners > 0
  let indices :=
    if !useSelective then
      (#[] : Array Nat)
    else if accountIndices.isEmpty then
      #[0]
    else
      accountIndices.extract 0 (min accountIndices.size
        (min maxPortableCpiAccounts portableCpiInfoStackSlots))
  let n := indices.size
  let packComment :=
    if useSelective then
      s!"selective AccountMeta pack"
    else
      s!"empty AccountMeta pack (pure peer method+args)"
  let signerComment :=
    if numSigners == 0 then "signers=0"
    else s!"signers={numSigners} (PDA authority)"
  let packNodes : Array AstNode :=
    if useSelective then
      packSelectedAccounts siteTag indices
    else
      #[.comment s!"portable CPI: {packComment}; infos@stack-{portableCpiInfoStackOffset}"]
  let signerArgs : Array AstNode :=
    if numSigners == 0 then
      #[
        loadImm .r4 0,
        loadImm .r5 0,
        .comment s!"r1=instruction_ptr r2=infos_ptr r3={n} r4=0 r5=0 ({packComment})"
      ]
    else
      stackPtr .r4 cpiSignerEntriesOffset ++ #[
        loadImm .r5 numSigners,
        .comment s!"r1=instruction_ptr r2=infos_ptr r3={n} r4=signer_seeds_ptr r5={numSigners}"
      ]
  #[
    .comment s!"portable crosscall → sol_invoke_signed_c (data_len={dataLen}, accounts={n}/{maxPortableCpiAccounts}, {packComment}, {signerComment})",
    .instruction {
      opcode := .stxdw
      dst := some .r10
      off := some (.num entryInputSaveOffset)
      src := some .r1
    }
  ] ++
  signerSeedNodes ++
  copyProgramIdFromAccountIndex ++
  packNodes ++
  packSolInstruction dataLen n ++
  stackPtr .r1 portableCpiIxOffset ++
  stackPtr .r2 portableCpiInfoStackOffset ++ #[
    loadImm .r3 n
  ] ++ signerArgs ++ #[
    callSyscall sol_invoke_signed_c,
    .instruction {
      opcode := .jne
      dst := some .r0
      imm := some (.num 0)
      off := some (.sym "error_cpi")
    },
    .instruction {
      opcode := .ldxdw
      dst := some .r1
      src := some .r10
      off := some (.num entryInputSaveOffset)
    }
  ] ++
  decodeReturnDataU64 retNoneLabel retEndLabel
structure PortableCrosscallSite where
  entrypoint : String
  argCount : Nat
  deriving Repr

partial def collectFromExpr (entrypoint : String) (acc : Array PortableCrosscallSite) :
    Expr → Array PortableCrosscallSite
  | .crosscallInvoke _ _ args
  | .crosscallInvokeTyped _ _ args _
  | .crosscallInvokeValueTyped _ _ _ args _ =>
      acc.push { entrypoint, argCount := args.size }
  | .crosscallInvokeStaticTyped .. | .crosscallInvokeDelegateTyped ..
  | .crosscallCreate .. | .crosscallCreate2 .. => acc
  | .nearCrosscallInvokePool .. | .nearPromiseThen .. => acc
  | .effect e => collectFromEffect entrypoint acc e
  | .add a b _ | .sub a b _ | .mul a b _ | .div a b | .mod a b | .pow a b
  | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
  | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
  | .boolAnd a b | .boolOr a b | .hashTwoToOne a b =>
      collectFromExpr entrypoint (collectFromExpr entrypoint acc a) b
  | .ecrecover a b c d =>
      collectFromExpr entrypoint
        (collectFromExpr entrypoint
          (collectFromExpr entrypoint (collectFromExpr entrypoint acc a) b) c) d
  | .eip712PermitDigest a b c d e f =>
      let acc := collectFromExpr entrypoint
        (collectFromExpr entrypoint
          (collectFromExpr entrypoint (collectFromExpr entrypoint acc a) b) c) d
      collectFromExpr entrypoint (collectFromExpr entrypoint acc e) f
  | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
      collectFromExpr entrypoint acc target
  | .cast a _ | .boolNot a | .hash a | .memoryArrayLength a | .field a _
  | .nearPromiseResultStatus a | .nearPromiseResultU64 a =>
      collectFromExpr entrypoint acc a
  | .arrayLit _ xs => xs.foldl (fun a e => collectFromExpr entrypoint a e) acc
  | .structLit _ fs => fs.foldl (fun a f => collectFromExpr entrypoint a f.snd) acc
  | .arrayGet a i | .memoryArrayGet a i =>
      collectFromExpr entrypoint (collectFromExpr entrypoint acc a) i
  | .memoryArrayNew _ len => collectFromExpr entrypoint acc len
  | .hashValue a b c d =>
      collectFromExpr entrypoint
        (collectFromExpr entrypoint
          (collectFromExpr entrypoint (collectFromExpr entrypoint acc a) b) c) d
  | .literal _ | .local _ | .nativeValue | .nearPromiseResultsCount => acc
where
  collectFromEffect (entrypoint : String) (acc : Array PortableCrosscallSite) :
      Effect → Array PortableCrosscallSite
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
    | .storageStructFieldWrite _ _ v | .storageDynamicArrayPush _ v =>
        collectFromExpr entrypoint acc v
    | .storageMapContains _ k | .storageMapGet _ k | .storageArrayRead _ k =>
        collectFromExpr entrypoint acc k
    | .storageMapInsert _ k v | .storageMapSet _ k v | .storageArrayWrite _ k v
    | .storageArrayStructFieldWrite _ k _ v =>
        collectFromExpr entrypoint (collectFromExpr entrypoint acc k) v
    | .memoryArraySet a i v =>
        collectFromExpr entrypoint
          (collectFromExpr entrypoint (collectFromExpr entrypoint acc a) i) v
    | .storagePathRead _ path => path.foldl (fun a s => collectFromPath entrypoint a s) acc
    | .storagePathWrite _ path v | .storagePathAssignOp _ path _ v =>
        collectFromExpr entrypoint (path.foldl (fun a s => collectFromPath entrypoint a s) acc) v
    | .eventEmit _ fs => fs.foldl (fun a f => collectFromExpr entrypoint a f.snd) acc
    | .eventEmitIndexed _ ix data =>
        data.foldl (fun a f => collectFromExpr entrypoint a f.snd)
          (ix.foldl (fun a f => collectFromExpr entrypoint a f.snd) acc)
    | .checkErc721Received a b c d =>
        collectFromExpr entrypoint
          (collectFromExpr entrypoint
            (collectFromExpr entrypoint (collectFromExpr entrypoint acc a) b) c) d
    | .checkErc1155Received a b c d e =>
        collectFromExpr entrypoint
          (collectFromExpr entrypoint
            (collectFromExpr entrypoint
              (collectFromExpr entrypoint (collectFromExpr entrypoint acc a) b) c) d) e
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .storageDynamicArrayPop _
    | .storageArrayStructFieldRead _ _ _ | .contextRead _ => acc
  collectFromPath (entrypoint : String) (acc : Array PortableCrosscallSite) :
      StoragePathSegment → Array PortableCrosscallSite
    | .field _ => acc
    | .index i | .mapKey i => collectFromExpr entrypoint acc i

partial def collectFromStmt (entrypoint : String) (acc : Array PortableCrosscallSite) :
    Statement → Array PortableCrosscallSite
  | .letBind _ _ v | .letMutBind _ _ v | .return v => collectFromExpr entrypoint acc v
  | .assign a b | .assignOp a _ b | .assertEq a b _ _ =>
      collectFromExpr entrypoint (collectFromExpr entrypoint acc a) b
  | .effect e => collectFromExpr entrypoint acc (.effect e)
  | .assert c _ _ => collectFromExpr entrypoint acc c
  | .ifElse c t e =>
      e.foldl (collectFromStmt entrypoint)
        (t.foldl (collectFromStmt entrypoint) (collectFromExpr entrypoint acc c))
  | .boundedFor _ _ _ body => body.foldl (collectFromStmt entrypoint) acc
  | .whileLoop c body =>
      body.foldl (collectFromStmt entrypoint) (collectFromExpr entrypoint acc c)
  | .revert _ | .revertWithError _ | .release _ => acc

def collectSites (module : Module) : Array PortableCrosscallSite :=
  module.entrypoints.foldl
    (fun acc ep => ep.body.foldl (collectFromStmt ep.name) acc)
    #[]

def moduleHasPortableCrosscall (module : Module) : Bool :=
  !(collectSites module).isEmpty

/-- Ensure a `callee_program` executable account exists when portable crosscall
is used so CPI program-id can be resolved by account index. -/
def ensureCalleeProgramAccount (module : Module) (accounts : Array AccountEntry) :
    Array AccountEntry :=
  if !moduleHasPortableCrosscall module then
    accounts
  else if accounts.any (fun a => a.name == "callee_program") then
    accounts
  else
    pushAccount accounts {
      name := "callee_program"
      index := 0
      signer := false
      writable := false
      owner := "executable"
    }

def materializationNote (module : Module) : String :=
  let sites := collectSites module
  if sites.isEmpty then
    "no portable crosscall sites"
  else
    let peer? :=
      match module.nearCrosscallStrings[0]? with
      | some s => if s.isEmpty then none else some s
      | none => none
    let inferNote :=
      match peer? with
      | none =>
          " inferredAccounts=MISSING_PEER (declareRemote required; packing uses synthetic peer)"
      | some peer =>
          match ProofForge.Target.CrosscallMaterialize.inferSolanaAccounts module peer with
          | .ok (accs : Array ProofForge.Target.CrosscallMaterialize.InferredAccount) =>
              let names :=
                String.intercalate ","
                  (accs.toList.map
                    (fun (a : ProofForge.Target.CrosscallMaterialize.InferredAccount) => a.name))
              s!" inferredAccounts=[{names}] (authors do not pass metas; also in AccountEntry schema)"
          | .error e => s!" inferredAccounts=ERROR({e})"
    s!"portable crosscall.invoke ×{sites.size} → Solana CPI via sol_invoke_signed_c \
(ix data; pure peer uses empty AccountMeta pack; PDA-signed CPI selectively packs \
signer|writable|program|executable up to {MAX_PORTABLE_CPI_ACCOUNTS}; \
return-data u64){inferNote}"
end ProofForge.Backend.Solana.PortableCrosscall
