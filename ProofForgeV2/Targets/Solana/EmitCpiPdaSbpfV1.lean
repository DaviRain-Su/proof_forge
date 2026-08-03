/-
  ProofForgeV2.Targets.Solana.EmitCpiPdaSbpfV1 — #120 PDA-signed companion CPI SBPF.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole emitter for production-code-generated **test-preactivation PDA-signed
  CPI ELF** text. Accepts only `ResolvedSolanaCpiPdaIRV1`. Public structural
  Plan/IR cannot feed this emitter.

  Emits:
  * ABIv1 multi-account walker + handler-entry global preflight;
  * ordered body: UInt64/UInt8 param/literal/stateLoad/checkedAdd/stateStore;
  * site-time predicates immediately before each signed invoke;
  * canonical seeds (18B ASCII proof-forge:pda:v1 + seedAuthority key 32 +
    seedTag LE 8 + bump 1);
  * `sol_try_find_program_address` over first 3 seeds; require status 0,
    supplied bump nonzero and equal to returned bump, full 32B key ==
    authorityPda;
  * `sol_invoke_signed_c` with one signer group / 4 seeds;
  * every nonzero syscall status propagates immediately (including success
    clear return data);
  * full AccountInfo array once in handler-local dense order.

  Signed scratch layout (r9 = cpi base):
    +0 data16, +16 seed0/pad24, +40 tag8, +48 bump lane8,
    +56 SolSignerSeed[4]64, +120 SolSignerSeeds16, +136 Meta[2]32,
    +168 Instruction40, +208 Infos[56*N], +216+56N canonical key32,
    +248+56N bump lane8.
    scratch=256+56*N; reserve=max(scratch,240);
    CPI_BASE=max(1600,1224+reserve); frame=CPI_BASE+reserve ≤4096.
    At N=16: base2376 / frame3528.

  Non-goals: OutputFile, product activation, System/Token/ATA, stale return
  helper, #118/#119 carriers.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiPdaIRV1
import ProofForgeV2.Targets.Solana.EmitCpiPreflightSbpfV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-! ## Private assembly carrier -/

structure SolanaCpiPdaAssemblyV1 where
  private mk ::
  resolved : ResolvedSolanaCpiPdaIRV1
  text : String
  frameBytes : Nat

namespace SolanaCpiPdaAssemblyV1

def textOf (a : SolanaCpiPdaAssemblyV1) : String := a.text
def frameBytesOf (a : SolanaCpiPdaAssemblyV1) : Nat := a.frameBytes
def resolvedOf (a : SolanaCpiPdaAssemblyV1) : ResolvedSolanaCpiPdaIRV1 :=
  a.resolved
def isProductArtifact (_ : SolanaCpiPdaAssemblyV1) : Bool := false
def isTestPreactivation (_ : SolanaCpiPdaAssemblyV1) : Bool := true

end SolanaCpiPdaAssemblyV1

/-! ## Frame layout (shared role table / temps with #118/#119) -/

def pdaRoleTableBytesV1 : Nat := preflightRoleTableBytesV1
def pdaRoleStrideV1 : Nat := preflightRoleStrideV1
def pdaMaxRolesV1 : Nat := preflightMaxRolesV1
def pdaSlotNumRolesV1 : Nat := preflightSlotNumRolesV1
def pdaSlotProgramIdV1 : Nat := preflightSlotProgramIdV1
def pdaSlotIxDataV1 : Nat := preflightSlotIxDataV1
def pdaSlotHandlerIdV1 : Nat := preflightSlotHandlerIdV1
def pdaSlotCursorV1 : Nat := preflightSlotCursorV1
def pdaTempBaseV1 : Nat := 1096
def pdaMaxTempsV1 : Nat := 16
def pdaTempRegionEndV1 : Nat := pdaTempBaseV1 + pdaMaxTempsV1 * 8  -- 1224
def pdaCpiBaseMinV1 : Nat := 1600
def pdaMaxFrameBytesV1 : Nat := 4096
def pdaInfoSizeV1 : Nat := 56
def pdaMetaSizeV1 : Nat := 16
def pdaInstructionSizeV1 : Nat := 40
/-- Fixed seed0 length: ASCII `proof-forge:pda:v1`. -/
def pdaSeed0LenV1 : Nat := 18

private def emitFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def natHexLower (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def hexImm (value : Nat) : String :=
  "0x" ++ natHexLower value

private def asmLabel (name : String) : String :=
  String.ofList (name.toList.map fun c =>
    if c.isAlphanum || c == '_' then c else '_')

private def handlerLabel (h : CpiPdaHandlerIRV1) : String :=
  s!"handler_{h.handlerId}_{asmLabel h.name}_pda"

private structure AsmBuf where
  text : String

private def emptyBuf : AsmBuf := ⟨""⟩

private def emit (b : AsmBuf) (line : String) : AsmBuf :=
  { text := b.text ++ line ++ "\n" }

private def emitBlank (b : AsmBuf) : AsmBuf :=
  emit b ""

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def tempSlot (tempId : Nat) : Nat :=
  pdaTempBaseV1 + tempId * 8

private def emitHeader
    (b0 : AsmBuf) (handlerCount frameBytes cpiBase : Nat) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b "; proof-forge solana cpi pda-signed companion SBPF (#120)"
    b := emit b "; TEST-PREACTIVATION ONLY — production-code-generated PDA-signed CPI ELF"
    b := emit b "; not a product artifact; activationDenied; no OutputFile"
    b := emit b "; Direct-mapped Loader V3 ABIv1 walker + role table (16 x 64 = 1024B)"
    b := emit b "; Real sol_try_find_program_address + sol_invoke_signed_c (1 signer group / 4 seeds)"
    b := emit b "; PDA rule: current-program-tagged-v1 (seed0=proof-forge:pda:v1)"
    b := emit b "; Failure: exit with syscall status immediately (no clear, no later op)"
    b := emit b "; Success: sol_set_return_data(0,0) then continue body"
    b := emit b s!"; Handlers: {handlerCount}; frameBytes={frameBytes} (<= {pdaMaxFrameBytesV1})"
    b := emit b s!"; CPI_BASE={cpiBase} (below role table/slots/temps; no overlap)"
    b := emitBlank b
    b := emit b s!".equ MAX_PERMITTED_DATA_INCREASE, {hexImm frozenLoaderV3AbiLayoutV1.maxPermittedDataIncrease}"
    b := emit b s!".equ FULL_PREFIX, {hexImm frozenLoaderV3AbiLayoutV1.fullPrefixBytes}"
    b := emit b s!".equ ROLE_BASE, {pdaRoleTableBytesV1}"
    b := emit b s!".equ ROLE_STRIDE, {pdaRoleStrideV1}"
    b := emit b ".equ ROLE_MARKER, 0"
    b := emit b ".equ ROLE_KEY, 8"
    b := emit b ".equ ROLE_OWNER, 16"
    b := emit b ".equ ROLE_LAMPORTS, 24"
    b := emit b ".equ ROLE_DATA, 32"
    b := emit b ".equ ROLE_DATA_LEN, 40"
    b := emit b ".equ ROLE_RENT, 48"
    b := emit b ".equ ROLE_FLAGS, 56"
    b := emit b s!".equ SLOT_NUM_ROLES, {pdaSlotNumRolesV1}"
    b := emit b s!".equ SLOT_PROGRAM_ID, {pdaSlotProgramIdV1}"
    b := emit b s!".equ SLOT_IX_DATA, {pdaSlotIxDataV1}"
    b := emit b s!".equ SLOT_HANDLER_ID, {pdaSlotHandlerIdV1}"
    b := emit b s!".equ SLOT_CURSOR, {pdaSlotCursorV1}"
    b := emit b s!".equ CPI_BASE, {cpiBase}"
    b := emit b s!".equ INFO_SIZE, {pdaInfoSizeV1}"
    b := emit b s!".equ META_SIZE, {pdaMetaSizeV1}"
    b := emit b s!".equ INSTRUCTION_SIZE, {pdaInstructionSizeV1}"
    b := emit b s!".equ SEED0_LEN, {pdaSeed0LenV1}"
    b := emitBlank b
    pure b

private def emitErrShape (b0 : AsmBuf) : AsmBuf :=
  let b := emit b0 "err_shape:"
  let b := emit b "  lddw r0, 1"
  emit b "  exit"

private def emitErrOverflow (b0 : AsmBuf) : AsmBuf :=
  let b := emit b0 "err_overflow:"
  let b := emit b "  lddw r0, 0x1001"
  emit b "  exit"

private def emitCpiFailed (b0 : AsmBuf) : AsmBuf :=
  let b := emit b0 "cpi_failed:"
  emit b "  exit"

private def emitRoleSlotAddr (b0 : AsmBuf) (indexImm : Nat) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b "  mov64 r2, r10"
    b := emit b "  lddw r3, ROLE_BASE"
    b := emit b "  sub64 r2, r3"
    if indexImm != 0 then
      b := emit b s!"  lddw r3, {indexImm * pdaRoleStrideV1}"
      b := emit b "  add64 r2, r3"
    pure b

private def emitWrapGuardAddImm
    (b0 : AsmBuf) (cursorReg : String) (amountImm : Nat) (errLab : String)
    (note : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; wrap-guard add {amountImm} ({note})"
    if amountImm == 0 then
      pure b
    else
      let limit := (2 ^ 64 - 1) - amountImm
      b := emit b s!"  lddw r0, {hexImm limit}"
      b := emit b s!"  jgt {cursorReg}, r0, {errLab}"
      b := emit b s!"  lddw r0, {hexImm amountImm}"
      b := emit b s!"  add64 {cursorReg}, r0"
      pure b

private def emitWrapGuardAddReg
    (b0 : AsmBuf) (cursorReg amountReg : String) (errLab : String)
    (note : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; wrap-guard add-reg ({note})"
    b := emit b "  lddw r0, 0xffffffffffffffff"
    b := emit b s!"  sub64 r0, {amountReg}"
    b := emit b s!"  jgt {cursorReg}, r0, {errLab}"
    b := emit b s!"  add64 {cursorReg}, {amountReg}"
    pure b

private def pubkeyLimbsLE (key : SolanaPubkeyV1) : CompileResult (Array Nat) := do
  let bytes := SolanaPubkeyV1.toBytes key
  unless bytes.size == 32 do
    emitFail "pubkey must be exact 32 bytes"
  let mut limbs : Array Nat := #[]
  for word in [0:4] do
    let mut limb : Nat := 0
    for bi in [0:8] do
      let b := bytes[word * 8 + bi]!.toNat
      limb := limb + b * (Nat.pow 2 (8 * bi))
    limbs := limbs.push limb
  pure limbs

private def emitCompareKey32
    (b0 : AsmBuf) (localIndex : Nat) (key : SolanaPubkeyV1) (lab : String) :
    CompileResult AsmBuf := do
  let limbs ← pubkeyLimbsLE key
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; checkExactKey local={localIndex}"
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r1, [r2 + ROLE_KEY]"
    for word in [0:4] do
      b := emit b s!"  lddw r3, {hexImm limbs[word]!}"
      b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
      b := emit b s!"  jne r4, r3, {lab}"
    pure b

private def emitOwnerCurrentProgram
    (b0 : AsmBuf) (localIndex : Nat) (lab : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; checkOwnerCurrentProgram local={localIndex}"
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r1, [r2 + ROLE_OWNER]"
    b := emit b "  ldxdw r5, [r10 - SLOT_PROGRAM_ID]"
    for word in [0:4] do
      b := emit b s!"  ldxdw r3, [r1 + {word * 8}]"
      b := emit b s!"  ldxdw r4, [r5 + {word * 8}]"
      b := emit b s!"  jne r3, r4, {lab}"
    pure b

private def emitOwnerExact
    (b0 : AsmBuf) (localIndex : Nat) (key : SolanaPubkeyV1) (lab : String) :
    CompileResult AsmBuf := do
  let limbs ← pubkeyLimbsLE key
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; checkOwnerExact local={localIndex}"
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r1, [r2 + ROLE_OWNER]"
    for word in [0:4] do
      b := emit b s!"  lddw r3, {hexImm limbs[word]!}"
      b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
      b := emit b s!"  jne r4, r3, {lab}"
    pure b

private def emitPairwiseDistinct
    (b0 : AsmBuf) (n : Nat) (lab : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; pairwise distinct keys n={n}"
    if n ≤ 1 then
      pure b
    else
      for i in [0:n] do
        for j in [i+1:n] do
          b := emit b s!"  ; distinct local {i} vs {j}"
          b := emitRoleSlotAddr b i
          b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
          b := emitRoleSlotAddr b j
          b := emit b "  ldxdw r1, [r2 + ROLE_KEY]"
          b := emit b "  lddw r8, 0"
          for word in [0:4] do
            b := emit b s!"  ldxdw r3, [r5 + {word * 8}]"
            b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
            b := emit b "  xor64 r3, r4"
            b := emit b "  or64 r8, r3"
          b := emit b s!"  jeq r8, 0, {lab}"
      pure b

private def emitDataLenCheck
    (b0 : AsmBuf) (localIndex expected : Nat) (lab : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; checkExactDataLen local={localIndex} expected={expected}"
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r1, [r2 + ROLE_DATA_LEN]"
    b := emit b s!"  lddw r3, {expected}"
    b := emit b s!"  jne r1, r3, {lab}"
    pure b

private def emitLamportsCheck
    (b0 : AsmBuf) (localIndex expected : Nat) (lab : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; checkExactLamports local={localIndex} expected={expected}"
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r1, [r2 + ROLE_LAMPORTS]"
    b := emit b "  ldxdw r1, [r1 + 0]"
    b := emit b s!"  lddw r3, {expected}"
    b := emit b s!"  jne r1, r3, {lab}"
    pure b

private def emitFlagExact
    (b0 : AsmBuf) (localIndex : Nat) (shift : Nat) (required : Bool)
    (lab : String) (note : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; {note} local={localIndex} required={required}"
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r1, [r2 + ROLE_FLAGS]"
    if shift != 0 then
      b := emit b s!"  rsh64 r1, {shift}"
    b := emit b "  and64 r1, 0xff"
    if required then
      b := emit b s!"  jne r1, 1, {lab}"
    else
      b := emit b s!"  jne r1, 0, {lab}"
    pure b

private def emitStateHeader
    (b0 : AsmBuf) (localIndex : Nat) (expected : Nat) (lab : String)
    (note : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; {note} local={localIndex} expected=0x{natHexLower expected}"
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
    b := emit b "  ldxdw r1, [r1 + 0]"
    b := emit b s!"  lddw r3, {hexImm expected}"
    b := emit b s!"  jne r1, r3, {lab}"
    pure b

private def emitPreflightOp
    (b0 : AsmBuf) (op : CpiPreflightOpV1) (errLab : String) :
    CompileResult AsmBuf := do
  match op with
  | .expectLocalRoleCount count =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; expectLocalRoleCount {count}"
        b := emit b "  ldxdw r1, [r10 - SLOT_NUM_ROLES]"
        b := emit b s!"  lddw r3, {count}"
        b := emit b s!"  jne r1, r3, {errLab}"
        pure b
  | .abiVirtualWalk localIndex =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; abiVirtualWalk local={localIndex}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_MARKER]"
        b := emit b "  jeq r1, 0, err_shape"
        pure b
  | .checkMarker localIndex expected =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkMarker local={localIndex}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_MARKER]"
        b := emit b "  ldxb r1, [r1 + 0]"
        b := emit b s!"  jne r1, {hexImm expected}, {errLab}"
        pure b
  | .checkOriginalDataLen localIndex expected =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkOriginalDataLen local={localIndex}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_MARKER]"
        b := emit b s!"  ldxw r1, [r1 + {frozenLoaderV3AbiLayoutV1.originalDataLenOffset}]"
        b := emit b s!"  jne r1, {expected}, {errLab}"
        pure b
  | .checkBoolFlagsInRange localIndex =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkBoolFlagsInRange local={localIndex}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_FLAGS]"
        b := emit b "  mov64 r3, r1"
        b := emit b "  and64 r3, 0xff"
        b := emit b s!"  jgt r3, 1, {errLab}"
        b := emit b "  mov64 r3, r1"
        b := emit b "  rsh64 r3, 8"
        b := emit b "  and64 r3, 0xff"
        b := emit b s!"  jgt r3, 1, {errLab}"
        b := emit b "  mov64 r3, r1"
        b := emit b "  rsh64 r3, 16"
        b := emit b "  and64 r3, 0xff"
        b := emit b s!"  jgt r3, 1, {errLab}"
        pure b
  | .checkRentEpochMax localIndex =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkRentEpochMax local={localIndex}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_RENT]"
        b := emit b "  lddw r3, 0xffffffffffffffff"
        b := emit b s!"  jne r1, r3, {errLab}"
        pure b
  | .checkPointerTableEntry localIndex =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkPointerTableEntry local={localIndex}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_MARKER]"
        b := emit b "  jeq r1, 0, err_shape"
        pure b
  | .checkPairwiseDistinctKeys n =>
      pure (emitPairwiseDistinct b0 n errLab)
  | .checkExactKey localIndex rawKey =>
      emitCompareKey32 b0 localIndex rawKey errLab
  | .checkOwnerCurrentProgram localIndex =>
      pure (emitOwnerCurrentProgram b0 localIndex errLab)
  | .checkOwnerExact localIndex rawOwner =>
      emitOwnerExact b0 localIndex rawOwner errLab
  | .checkExecutableRequired localIndex =>
      pure (emitFlagExact b0 localIndex 16 true errLab "checkExecutableRequired")
  | .checkExecutableForbidden localIndex =>
      pure (emitFlagExact b0 localIndex 16 false errLab "checkExecutableForbidden")
  | .checkExactDataLen localIndex bytes =>
      pure (emitDataLenCheck b0 localIndex bytes errLab)
  | .checkExactLamports localIndex lamports =>
      pure (emitLamportsCheck b0 localIndex lamports errLab)
  | .checkStateHeaderZero localIndex =>
      pure (emitStateHeader b0 localIndex 0 errLab "checkStateHeaderZero")
  | .checkStateHeaderMarker localIndex marker =>
      pure (emitStateHeader b0 localIndex marker.toNat errLab "checkStateHeaderMarker")
  | .checkEffectiveSigner localIndex required =>
      pure (emitFlagExact b0 localIndex 0 required errLab "checkEffectiveSigner")
  | .checkEffectiveWritable localIndex required =>
      pure (emitFlagExact b0 localIndex 8 required errLab "checkEffectiveWritable")

private def emitLoadTemp (b0 : AsmBuf) (tempId : Nat) (dstReg : String) : AsmBuf :=
  emit b0 s!"  ldxdw {dstReg}, [r10 - {tempSlot tempId}]"

private def emitStoreTemp (b0 : AsmBuf) (tempId : Nat) (srcReg : String) : AsmBuf :=
  emit b0 s!"  stxdw [r10 - {tempSlot tempId}], {srcReg}"

private def emitResolveU64Source
    (b0 : AsmBuf) (src : CpiPdaU64SourceV1) (dstReg : String) : AsmBuf :=
  match src with
  | .literal v =>
      Id.run do
        let mut b := b0
        b := emit b s!"  lddw {dstReg}, {hexImm v.toNat}"
        pure b
  | .param _ord off =>
      Id.run do
        let mut b := b0
        b := emit b "  ldxdw r1, [r10 - SLOT_IX_DATA]"
        b := emit b s!"  ldxdw {dstReg}, [r1 + {off}]"
        pure b

private def emitResolveU8Source
    (b0 : AsmBuf) (src : CpiPdaU8SourceV1) (dstReg : String) : AsmBuf :=
  match src with
  | .literal v =>
      Id.run do
        let mut b := b0
        b := emit b s!"  lddw {dstReg}, {hexImm v.toNat}"
        pure b
  | .param _ord off =>
      Id.run do
        let mut b := b0
        b := emit b "  ldxdw r1, [r10 - SLOT_IX_DATA]"
        -- Packed probe layout: UInt8 occupies exactly one byte.
        b := emit b s!"  ldxb {dstReg}, [r1 + {off}]"
        pure b

/-- Emit PDA-signed invoke for one companion.invokeSigned site. -/
private def emitInvokeSigned
    (b0 : AsmBuf) (inv : CpiPdaInvokeV1) (labSuffix : String) :
    CompileResult AsmBuf := do
  unless inv.packageId == "companion-v1" do
    emitFail "emit invokeSigned requires companion-v1"
  unless inv.qn == "solana.companion.invokeSigned" do
    emitFail "emit invokeSigned requires solana.companion.invokeSigned"
  unless inv.dataLen == 9 && inv.tag == 2 do
    emitFail "invokeSigned dataLen/tag must be 9/2"
  unless inv.metas.size == 2 do
    emitFail "invokeSigned expects exactly two metas"
  unless inv.outerOnly.size == 1 do
    emitFail "invokeSigned expects exactly one outer-only"
  unless inv.signerGroupId == 0 && inv.pdaRule == "current-program-tagged-v1" do
    emitFail "invokeSigned signer group / PDA rule diverged"
  unless inv.accountInfoCount ≤ pdaMaxRolesV1 do
    emitFail "accountInfoCount exceeds max roles"
  let meta0 := inv.metas[0]!
  let meta1 := inv.metas[1]!
  let oo0 := inv.outerOnly[0]!
  unless meta0.roleId == inv.account.roleId &&
      meta0.localIndex == inv.account.localIndex &&
      meta1.roleId == inv.authorityPda.roleId &&
      meta1.localIndex == inv.authorityPda.localIndex &&
      oo0.roleId == inv.seedAuthority.roleId &&
      oo0.localIndex == inv.seedAuthority.localIndex do
    emitFail "invokeSigned Principal/meta/outer-only join diverged"
  unless meta0.localIndex < inv.accountInfoCount &&
      meta1.localIndex < inv.accountInfoCount &&
      oo0.localIndex < inv.accountInfoCount &&
      inv.programLocalIndex < inv.accountInfoCount do
    emitFail "invoke local role index exceeds AccountInfo array"
  let n := inv.accountInfoCount
  let infosOff := 208
  let keyOutOff := 216 + 56 * n
  let bumpOutOff := 248 + 56 * n
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; --- invokeSigned site={inv.siteId} {inv.qn} ---"
    b := emit b "  mov64 r9, r10"
    b := emit b "  lddw r4, CPI_BASE"
    b := emit b "  sub64 r9, r4                       ; r9 = cpi scratch base"
    -- +0 data16: tag || delta
    b := emit b "  lddw r4, 0"
    b := emit b "  stxdw [r9 + 0], r4"
    b := emit b "  stxdw [r9 + 8], r4"
    b := emit b s!"  lddw r4, {inv.tag}"
    b := emit b "  stxb [r9 + 0], r4"
    b := emitResolveU64Source b inv.delta "r4"
    b := emit b "  stxdw [r9 + 1], r4"
    -- +16 seed0 18B ASCII proof-forge:pda:v1 (pad to 24)
    b := emit b "  ; seed0 = proof-forge:pda:v1 (18 bytes)"
    b := emit b "  lddw r4, 0x6f662d666f6f7270"
    b := emit b "  stxdw [r9 + 16], r4"
    b := emit b "  lddw r4, 0x3a6164703a656772"
    b := emit b "  stxdw [r9 + 24], r4"
    b := emit b "  lddw r4, 0x3176"
    b := emit b "  stxdw [r9 + 32], r4"
    -- +40 seedTag UInt64 LE
    b := emitResolveU64Source b inv.seedTag "r4"
    b := emit b "  stxdw [r9 + 40], r4"
    -- +48 bump lane (1 used); reject runtime 0
    b := emitResolveU8Source b inv.bump "r4"
    b := emit b "  and64 r4, 0xff"
    b := emit b "  jeq r4, 0, err_shape                 ; bump param 0 rejected"
    b := emit b "  stxdw [r9 + 48], r4"
    -- +56 SolSignerSeed[4]
    -- seed0: addr=r9+16, len=18
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 16"
    b := emit b "  stxdw [r9 + 56], r5"
    b := emit b "  lddw r4, SEED0_LEN"
    b := emit b "  stxdw [r9 + 64], r4"
    -- seed1: seedAuthority key pointer (input region)
    b := emitRoleSlotAddr b oo0.localIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r9 + 72], r4"
    b := emit b "  lddw r4, 32"
    b := emit b "  stxdw [r9 + 80], r4"
    -- seed2: seedTag at +40, len=8
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 40"
    b := emit b "  stxdw [r9 + 88], r5"
    b := emit b "  lddw r4, 8"
    b := emit b "  stxdw [r9 + 96], r4"
    -- seed3: bump at +48, len=1
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 48"
    b := emit b "  stxdw [r9 + 104], r5"
    b := emit b "  lddw r4, 1"
    b := emit b "  stxdw [r9 + 112], r4"
    -- +120 SolSignerSeeds (one group → seeds[0..3])
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 56"
    b := emit b "  stxdw [r9 + 120], r5"
    b := emit b "  lddw r4, 4"
    b := emit b "  stxdw [r9 + 128], r4"
    -- sol_try_find_program_address over first 3 seeds (no bump)
    b := emit b "  ; find canonical PDA over seed0/seedAuthority/seedTag"
    b := emit b "  mov64 r1, r9"
    b := emit b "  add64 r1, 56                        ; SolSignerSeed[0]"
    b := emit b "  lddw r2, 3"
    b := emit b "  ldxdw r3, [r10 - SLOT_PROGRAM_ID]"
    b := emit b "  mov64 r4, r9"
    b := emit b s!"  add64 r4, {keyOutOff}               ; address_out"
    b := emit b "  mov64 r5, r9"
    b := emit b s!"  add64 r5, {bumpOutOff}              ; bump_out"
    b := emit b "  call sol_try_find_program_address"
    b := emit b "  jne r0, 0, cpi_failed"
    -- supplied bump must equal returned canonical bump
    b := emit b "  ldxb r1, [r9 + 48]"
    b := emit b s!"  ldxb r2, [r9 + {bumpOutOff}]"
    b := emit b "  jne r1, r2, err_shape"
    -- full 32-byte returned key must equal authorityPda ROLE_KEY
    b := emitRoleSlotAddr b meta1.localIndex
    b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
    b := emit b "  mov64 r1, r9"
    b := emit b s!"  add64 r1, {keyOutOff}"
    for word in [0:4] do
      b := emit b s!"  ldxdw r3, [r5 + {word * 8}]"
      b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
      b := emit b s!"  jne r3, r4, err_shape"
    -- +136 Meta[2]
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 136                      ; metas"
    -- meta[0] account
    b := emitRoleSlotAddr b meta0.localIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r5 + 0], r4"
    b := emit b s!"  lddw r4, {if meta0.cpiWritable then 1 else 0}"
    b := emit b "  stxb [r5 + 8], r4"
    b := emit b s!"  lddw r4, {if meta0.cpiSigner then 1 else 0}"
    b := emit b "  stxb [r5 + 9], r4"
    b := emit b "  lddw r4, 0"
    for pad in [10:16] do
      b := emit b s!"  stxb [r5 + {pad}], r4"
    -- meta[1] authorityPda
    b := emitRoleSlotAddr b meta1.localIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r5 + 16], r4"
    b := emit b s!"  lddw r4, {if meta1.cpiWritable then 1 else 0}"
    b := emit b "  stxb [r5 + 24], r4"
    b := emit b s!"  lddw r4, {if meta1.cpiSigner then 1 else 0}"
    b := emit b "  stxb [r5 + 25], r4"
    b := emit b "  lddw r4, 0"
    for pad in [26:32] do
      b := emit b s!"  stxb [r5 + {pad}], r4"
    -- +168 SolInstruction
    b := emit b "  mov64 r8, r9"
    b := emit b "  add64 r8, 168"
    b := emitRoleSlotAddr b inv.programLocalIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r8 + 0], r4                 ; program_id"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 136"
    b := emit b "  stxdw [r8 + 8], r4                 ; accounts"
    b := emit b "  lddw r4, 2"
    b := emit b "  stxdw [r8 + 16], r4                ; accounts_len"
    b := emit b "  stxdw [r8 + 24], r9                ; data"
    b := emit b "  lddw r4, 9"
    b := emit b "  stxdw [r8 + 32], r4                ; data_len"
    -- +208 SolAccountInfo[N] full dense order
    b := emit b "  mov64 r5, r9"
    b := emit b s!"  add64 r5, {infosOff}"
    b := emit b "  lddw r7, 0"
    b := emit b s!"fill_info_{labSuffix}:"
    b := emit b "  mov64 r2, r10"
    b := emit b "  lddw r3, ROLE_BASE"
    b := emit b "  sub64 r2, r3"
    b := emit b "  mov64 r3, r7"
    b := emit b "  lsh64 r3, 6"
    b := emit b "  add64 r2, r3"
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r5 + 0], r4"
    b := emit b "  ldxdw r4, [r2 + ROLE_LAMPORTS]"
    b := emit b "  stxdw [r5 + 8], r4"
    b := emit b "  ldxdw r4, [r2 + ROLE_DATA_LEN]"
    b := emit b "  stxdw [r5 + 16], r4"
    b := emit b "  ldxdw r4, [r2 + ROLE_DATA]"
    b := emit b "  stxdw [r5 + 24], r4"
    b := emit b "  ldxdw r4, [r2 + ROLE_OWNER]"
    b := emit b "  stxdw [r5 + 32], r4"
    b := emit b "  ldxdw r4, [r2 + ROLE_RENT]"
    b := emit b "  stxdw [r5 + 40], r4"
    b := emit b "  ldxdw r4, [r2 + ROLE_FLAGS]"
    b := emit b "  stxb [r5 + 48], r4"
    b := emit b "  rsh64 r4, 8"
    b := emit b "  stxb [r5 + 49], r4"
    b := emit b "  rsh64 r4, 8"
    b := emit b "  stxb [r5 + 50], r4"
    b := emit b "  lddw r4, 0"
    for pad in [51:56] do
      b := emit b s!"  stxb [r5 + {pad}], r4"
    b := emit b "  add64 r5, INFO_SIZE"
    b := emit b "  add64 r7, 1"
    b := emit b s!"  lddw r3, {n}"
    b := emit b s!"  jlt r7, r3, fill_info_{labSuffix}"
    -- sol_invoke_signed_c(instruction, infos, n, signers, 1)
    b := emit b "  mov64 r1, r8"
    b := emit b "  mov64 r2, r9"
    b := emit b s!"  add64 r2, {infosOff}"
    b := emit b s!"  lddw r3, {n}"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 120                       ; SolSignerSeeds"
    b := emit b "  lddw r5, 1"
    b := emit b "  call sol_invoke_signed_c"
    b := emit b "  jne r0, 0, cpi_failed"
    b := emit b "  lddw r1, 0"
    b := emit b "  lddw r2, 0"
    b := emit b "  call sol_set_return_data"
    b := emit b "  jne r0, 0, cpi_failed"
    pure b

private def emitBodyOp
    (b0 : AsmBuf) (op : CpiPdaBodyOpV1) (labSuffix : String) :
    CompileResult AsmBuf := do
  match op with
  | .loadParamU64 tempId ixOff =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; loadParamU64 temp={tempId} ix@{ixOff}"
        b := emit b "  ldxdw r1, [r10 - SLOT_IX_DATA]"
        b := emit b s!"  ldxdw r3, [r1 + {ixOff}]"
        b := emitStoreTemp b tempId "r3"
        pure b
  | .loadParamU8 tempId ixOff =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; loadParamU8 temp={tempId} ix@{ixOff}"
        b := emit b "  ldxdw r1, [r10 - SLOT_IX_DATA]"
        b := emit b s!"  ldxb r3, [r1 + {ixOff}]"
        b := emitStoreTemp b tempId "r3"
        pure b
  | .loadLiteralU64 tempId value =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; loadLiteralU64 temp={tempId} value={value.toNat}"
        b := emit b s!"  lddw r3, {hexImm value.toNat}"
        b := emitStoreTemp b tempId "r3"
        pure b
  | .loadLiteralU8 tempId value =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; loadLiteralU8 temp={tempId} value={value.toNat}"
        b := emit b s!"  lddw r3, {hexImm value.toNat}"
        b := emitStoreTemp b tempId "r3"
        pure b
  | .stateLoadU64 tempId localIndex byteOffset =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; stateLoadU64 temp={tempId} local={localIndex} @{byteOffset}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
        b := emit b s!"  ldxdw r3, [r1 + {byteOffset}]"
        b := emitStoreTemp b tempId "r3"
        pure b
  | .checkedAddU64 dst lhs rhs =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkedAddU64 dst={dst} lhs={lhs} rhs={rhs}"
        b := emitLoadTemp b lhs "r1"
        b := emitLoadTemp b rhs "r3"
        b := emit b "  lddw r4, 0xffffffffffffffff"
        b := emit b "  sub64 r4, r3"
        b := emit b "  jgt r1, r4, err_overflow"
        b := emit b "  add64 r1, r3"
        b := emitStoreTemp b dst "r1"
        pure b
  | .stateStoreU64 localIndex byteOffset srcTemp writeMarker marker =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; stateStoreU64 local={localIndex} @{byteOffset} src={srcTemp}"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
        if writeMarker then
          b := emit b s!"  lddw r3, {hexImm marker.toNat}"
          b := emit b "  stxdw [r1 + 0], r3"
        b := emitLoadTemp b srcTemp "r3"
        b := emit b s!"  stxdw [r1 + {byteOffset}], r3"
        pure b
  | .siteChecks siteId ops => do
      let mut b := b0
      b := emit b s!"  ; siteChecks site={siteId} (site-time, not entry-hoisted)"
      for op in ops do
        b ← emitPreflightOp b op "err_shape"
      pure b
  | .invokeSigned inv =>
      emitInvokeSigned b0 inv labSuffix
  | .returnU64 srcTemp =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; returnU64 temp={srcTemp}"
        b := emitLoadTemp b srcTemp "r3"
        b := emit b "  mov64 r1, r10"
        b := emit b "  lddw r2, CPI_BASE"
        b := emit b "  sub64 r1, r2"
        b := emit b "  stxdw [r1 + 0], r3"
        b := emit b "  lddw r2, 8"
        b := emit b "  call sol_set_return_data"
        b := emit b "  jne r0, 0, cpi_failed"
        b := emit b "  lddw r0, 0"
        b := emit b "  exit"
        pure b
  | .returnNone =>
      pure <| Id.run do
        let mut b := b0
        b := emit b "  ; returnNone"
        b := emit b "  lddw r0, 0"
        b := emit b "  exit"
        pure b

private def emitHandlerSection
    (b0 : AsmBuf) (h : CpiPdaHandlerIRV1) : CompileResult AsmBuf := do
  unless h.tempCount ≤ pdaMaxTempsV1 do
    emitFail s!"handler {h.handlerId} tempCount {h.tempCount} > {pdaMaxTempsV1}"
  unless h.localRoleCount ≤ pdaMaxRolesV1 do
    emitFail s!"handler {h.handlerId} localRoleCount exceeds cap"
  let lab := handlerLabel h
  let mut b := b0
  b := emitBlank b
  b := emit b s!"; ===== handler {h.handlerId} {h.name} localRoles={h.localRoleCount} temps={h.tempCount} ====="
  b := emit b s!"{lab}:"
  b := emit b "  ; --- handler-entry global preflight (no site predicates) ---"
  for op in h.entryGlobalOps do
    b ← emitPreflightOp b op "err_shape"
  b := emit b "  ; --- ordered body (siteChecks immediately before each invoke) ---"
  let mut invokeIdx : Nat := 0
  for op in h.bodyOps do
    let suffix := s!"{h.handlerId}_{invokeIdx}"
    match op with
    | .invokeSigned _ =>
        b ← emitBodyOp b op suffix
        invokeIdx := invokeIdx + 1
    | _ =>
        b ← emitBodyOp b op suffix
  b := emit b "  ja err_shape"
  pure b

private def emitProbeEntrypoint
    (b0 : AsmBuf) (handlers : Array CpiPdaHandlerIRV1) : AsmBuf :=
  Id.run do
    let mut b := b0
    let fullPrefix := frozenLoaderV3AbiLayoutV1.fullPrefixBytes
    let growth := frozenLoaderV3AbiLayoutV1.maxPermittedDataIncrease
    b := emitBlank b
    b := emit b "; ----- test-preactivation entrypoint (NOT a product artifact) -----"
    b := emit b "; Instruction data: handlerId u64 LE + non-Principal UInt64/UInt8 params."
    b := emit b "; Per-handler exact length enforced after dispatch."
    b := emit b ".globl entrypoint"
    b := emit b "entrypoint:"
    b := emit b "  mov64 r6, r1"
    b := emit b "  ldxdw r1, [r6 + 0]"
    b := emit b s!"  jgt r1, {pdaMaxRolesV1}, err_shape"
    b := emit b "  stxdw [r10 - SLOT_NUM_ROLES], r1"
    b := emit b "  mov64 r9, r1"
    b := emit b "  mov64 r8, r6"
    b := emitWrapGuardAddImm b "r8" 8 "err_shape" "input base → first marker"
    b := emit b "  lddw r7, 0"
    b := emit b "  jeq r9, 0, ep_parse_roles_done"
    b := emit b "ep_parse_role:"
    b := emit b "  ldxb r1, [r8 + 0]"
    b := emit b s!"  jne r1, {hexImm frozenLoaderV3AbiLayoutV1.marker}, err_shape"
    b := emit b s!"  ldxw r1, [r8 + {frozenLoaderV3AbiLayoutV1.originalDataLenOffset}]"
    b := emit b s!"  jne r1, {frozenLoaderV3AbiLayoutV1.originalDataLenEntryValue}, err_shape"
    b := emit b "  mov64 r2, r10"
    b := emit b "  lddw r3, ROLE_BASE"
    b := emit b "  sub64 r2, r3"
    b := emit b "  mov64 r3, r7"
    b := emit b "  lsh64 r3, 6"
    b := emit b "  add64 r2, r3"
    b := emit b "  stxdw [r2 + ROLE_MARKER], r8"
    b := emit b "  mov64 r1, r8"
    b := emitWrapGuardAddImm b "r1" frozenLoaderV3AbiLayoutV1.keyOffset "err_shape" "key offset"
    b := emit b "  stxdw [r2 + ROLE_KEY], r1"
    b := emit b "  mov64 r1, r8"
    b := emitWrapGuardAddImm b "r1" frozenLoaderV3AbiLayoutV1.ownerOffset "err_shape" "owner offset"
    b := emit b "  stxdw [r2 + ROLE_OWNER], r1"
    b := emit b "  mov64 r1, r8"
    b := emitWrapGuardAddImm b "r1" frozenLoaderV3AbiLayoutV1.lamportsOffset "err_shape" "lamports offset"
    b := emit b "  stxdw [r2 + ROLE_LAMPORTS], r1"
    b := emit b "  mov64 r1, r8"
    b := emitWrapGuardAddImm b "r1" fullPrefix "err_shape" "full prefix → data"
    b := emit b "  stxdw [r2 + ROLE_DATA], r1"
    b := emit b s!"  ldxdw r1, [r8 + {frozenLoaderV3AbiLayoutV1.dataLenOffset}]"
    b := emit b "  stxdw [r2 + ROLE_DATA_LEN], r1"
    b := emit b "  mov64 r4, r1"
    b := emit b s!"  ldxb r1, [r8 + {frozenLoaderV3AbiLayoutV1.isSignerOffset}]"
    b := emit b "  jgt r1, 1, err_shape"
    b := emit b s!"  ldxb r3, [r8 + {frozenLoaderV3AbiLayoutV1.isWritableOffset}]"
    b := emit b "  jgt r3, 1, err_shape"
    b := emit b "  lsh64 r3, 8"
    b := emit b "  or64 r1, r3"
    b := emit b s!"  ldxb r3, [r8 + {frozenLoaderV3AbiLayoutV1.executableOffset}]"
    b := emit b "  jgt r3, 1, err_shape"
    b := emit b "  lsh64 r3, 16"
    b := emit b "  or64 r1, r3"
    b := emit b "  stxdw [r2 + ROLE_FLAGS], r1"
    b := emit b "  mov64 r5, r8"
    b := emitWrapGuardAddImm b "r5" fullPrefix "err_shape" "cursor full prefix"
    b := emitWrapGuardAddReg b "r5" "r4" "err_shape" "cursor data_len"
    b := emitWrapGuardAddImm b "r5" growth "err_shape" "cursor growth reserve"
    b := emit b "  mov64 r1, r4"
    b := emit b "  and64 r1, 7"
    b := emit b "  jeq r1, 0, ep_role_aligned"
    b := emit b "  lddw r3, 8"
    b := emit b "  sub64 r3, r1"
    b := emitWrapGuardAddReg b "r5" "r3" "err_shape" "cursor alignment pad"
    b := emit b "ep_role_aligned:"
    b := emit b "  ldxdw r1, [r5 + 0]"
    b := emit b "  lddw r3, 0xffffffffffffffff"
    b := emit b "  jne r1, r3, err_shape"
    b := emit b "  stxdw [r2 + ROLE_RENT], r1"
    b := emitWrapGuardAddImm b "r5" 8 "err_shape" "cursor rent+8"
    b := emit b "  mov64 r8, r5"
    b := emit b "  add64 r7, 1"
    b := emit b "  mov64 r1, r7"
    b := emit b "  ldxdw r3, [r10 - SLOT_NUM_ROLES]"
    b := emit b "  jlt r1, r3, ep_parse_role"
    b := emit b "ep_parse_roles_done:"
    b := emit b "  ldxdw r1, [r8 + 0]"
    b := emit b "  jlt r1, 8, err_shape"
    b := emit b "  stxdw [r10 - SLOT_CURSOR], r1       ; save ix_data_len"
    b := emit b "  mov64 r2, r8"
    b := emitWrapGuardAddImm b "r2" 8 "err_shape" "ix data pointer"
    b := emit b "  stxdw [r10 - SLOT_IX_DATA], r2"
    b := emit b "  ldxdw r3, [r2 + 0]"
    b := emit b "  stxdw [r10 - SLOT_HANDLER_ID], r3"
    b := emit b "  mov64 r5, r2"
    b := emitWrapGuardAddReg b "r5" "r1" "err_shape" "program id after ix data"
    b := emit b "  stxdw [r10 - SLOT_PROGRAM_ID], r5"
    b := emitWrapGuardAddImm b "r5" 32 "err_shape" "program id +32"
    b := emit b "  mov64 r1, r5"
    b := emit b "  and64 r1, 7"
    b := emit b "  jeq r1, 0, ep_ptr_table"
    b := emit b "  lddw r3, 8"
    b := emit b "  sub64 r3, r1"
    b := emit b "ep_check_zero_pad:"
    b := emit b "  ldxb r1, [r5 + 0]"
    b := emit b "  jne r1, 0, err_shape"
    b := emitWrapGuardAddImm b "r5" 1 "err_shape" "padding byte"
    b := emit b "  sub64 r3, 1"
    b := emit b "  jne r3, 0, ep_check_zero_pad"
    b := emit b "ep_ptr_table:"
    b := emit b "  lddw r7, 0"
    b := emit b "  ldxdw r3, [r10 - SLOT_NUM_ROLES]"
    b := emit b "  jeq r3, 0, ep_pointer_table_done"
    b := emit b "ep_check_ptr:"
    b := emit b "  mov64 r2, r10"
    b := emit b "  lddw r3, ROLE_BASE"
    b := emit b "  sub64 r2, r3"
    b := emit b "  mov64 r3, r7"
    b := emit b "  lsh64 r3, 6"
    b := emit b "  add64 r2, r3"
    b := emit b "  ldxdw r1, [r2 + ROLE_MARKER]"
    b := emit b "  ldxdw r3, [r5 + 0]"
    b := emit b "  jne r1, r3, err_shape"
    b := emitWrapGuardAddImm b "r5" 8 "err_shape" "pointer-table +8"
    b := emit b "  add64 r7, 1"
    b := emit b "  ldxdw r3, [r10 - SLOT_NUM_ROLES]"
    b := emit b "  jlt r7, r3, ep_check_ptr"
    b := emit b "ep_pointer_table_done:"
    b := emit b "  ldxdw r1, [r10 - SLOT_HANDLER_ID]"
    for h in handlers do
      b := emit b s!"  jeq r1, {h.handlerId}, dispatch_{h.handlerId}"
    b := emit b "  ja err_shape"
    for h in handlers do
      b := emitBlank b
      b := emit b s!"dispatch_{h.handlerId}:"
      b := emit b "  ldxdw r1, [r10 - SLOT_CURSOR]"
      b := emit b s!"  jne r1, {h.probeIxDataLen}, err_shape"
      b := emit b s!"  ja {handlerLabel h}"
    pure b

/-! ## Public emit entry -/

def emitCpiPdaSbpfV1
    (resolved : ResolvedSolanaCpiPdaIRV1) :
    CompileResult SolanaCpiPdaAssemblyV1 := do
  let cand := ResolvedSolanaCpiPdaIRV1.candidateOf resolved
  unless cand.maxOuterRoles == pdaMaxRolesV1 do
    emitFail s!"maxOuterRoles must be {pdaMaxRolesV1}"
  unless cand.maxFrameBytes == pdaMaxFrameBytesV1 do
    emitFail "maxFrameBytes must be 4096"
  let maxScratch := pdaMaxSiteScratchV1 cand
  let scratchReserve := Nat.max maxScratch 240
  let cpiBase := Nat.max pdaCpiBaseMinV1
    (pdaTempRegionEndV1 + scratchReserve)
  let frameBytes := cpiBase + scratchReserve
  unless frameBytes ≤ pdaMaxFrameBytesV1 do
    emitFail s!"PDA CPI frame {frameBytes} exceeds {pdaMaxFrameBytesV1}"
  unless cpiBase ≥ pdaTempRegionEndV1 + scratchReserve do
    emitFail "CPI scratch overlaps temp/role region"
  let mut b := emptyBuf
  b := emitHeader b cand.handlers.size frameBytes cpiBase
  b := emitProbeEntrypoint b cand.handlers
  for h in cand.handlers do
    b ← emitHandlerSection b h
  b := emitBlank b
  b := emitCpiFailed b
  b := emitBlank b
  b := emitErrOverflow b
  b := emitBlank b
  b := emitErrShape b
  let text := b.text
  if hasSubstr text "ACC0_" then
    emitFail "PDA assembly must not contain ACC0 fixed slots"
  if hasSubstr text "0xec01" then
    emitFail "PDA assembly must not contain legacy 0xec01 call stub"
  unless hasSubstr text "call sol_try_find_program_address" do
    emitFail "PDA assembly must contain sol_try_find_program_address"
  unless hasSubstr text "call sol_invoke_signed_c" do
    emitFail "PDA assembly must contain sol_invoke_signed_c"
  unless hasSubstr text "call sol_set_return_data" do
    emitFail "PDA assembly must contain sol_set_return_data"
  unless hasSubstr text "TEST-PREACTIVATION ONLY" do
    emitFail "PDA assembly missing preactivation banner"
  unless hasSubstr text "not a product artifact" do
    emitFail "PDA assembly missing product-boundary banner"
  pure ⟨resolved, text, frameBytes⟩

end ProofForgeV2.Targets.Solana.CpiV1
