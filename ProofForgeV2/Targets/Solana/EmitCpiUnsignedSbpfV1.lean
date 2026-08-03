/-
  ProofForgeV2.Targets.Solana.EmitCpiUnsignedSbpfV1 — #119 unsigned companion CPI SBPF.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole emitter for production-code-generated **test-preactivation unsigned-CPI
  ELF** text. Accepts only `ResolvedSolanaCpiUnsignedIRV1` (which retains the
  #118 Semantic-bound preflight authority chain). Public structural Plan/IR
  cannot feed this emitter.

  Emits:
  * ABIv1 multi-account walker + handler-entry global preflight;
  * ordered body: UInt64 param/literal/stateLoad/checkedAdd/stateStore;
  * site-time predicates immediately before each unsigned invoke;
  * `sol_invoke_signed_c` zero-signer ABI (r1 SolInstruction*, r2 full
    SolAccountInfo[], r3 localRoleCount, r4=0, r5=0);
  * on nonzero status: exit immediately with that status (no clear, no later op);
  * on success: `sol_set_return_data(0,0)` then continue;
  * top-level returnU64 sets 8-byte return data.

  Non-goals: OutputFile, product activation, PDA/signer groups, System/Token/ATA,
  legacy ACC0 slots, schedule. Frame ≤ 4096; CPI scratch does not overlap the
  #118 role table/slots (role table 1024B + slots to 1088; temps + CPI below).
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiUnsignedIRV1
import ProofForgeV2.Targets.Solana.EmitCpiPreflightSbpfV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-! ## Private assembly carrier -/

structure SolanaCpiUnsignedAssemblyV1 where
  private mk ::
  resolved : ResolvedSolanaCpiUnsignedIRV1
  text : String
  frameBytes : Nat

namespace SolanaCpiUnsignedAssemblyV1

def textOf (a : SolanaCpiUnsignedAssemblyV1) : String := a.text
def frameBytesOf (a : SolanaCpiUnsignedAssemblyV1) : Nat := a.frameBytes
def resolvedOf (a : SolanaCpiUnsignedAssemblyV1) : ResolvedSolanaCpiUnsignedIRV1 :=
  a.resolved
def isProductArtifact (_ : SolanaCpiUnsignedAssemblyV1) : Bool := false
def isTestPreactivation (_ : SolanaCpiUnsignedAssemblyV1) : Bool := true

end SolanaCpiUnsignedAssemblyV1

/-! ## Frame layout

  Role table [r10-1024 .. r10) — same as #118 (16×64).
  Slots (shared with #118):
    1032 num_roles, 1040 program_id, 1048 ix_data, 1056 handler_id, 1064 cursor
  Temps: 16 × 8 = 128 bytes at [r10-1216 .. r10-1088)
    temp i at r10 - (1088 + 8 + i*8) = r10 - (1096 + i*8)
  CPI scratch base computed as ROLE_TABLE + slots + temps + pad, ≥ 1600 default.
-/

def unsignedRoleTableBytesV1 : Nat := preflightRoleTableBytesV1
def unsignedRoleStrideV1 : Nat := preflightRoleStrideV1
def unsignedMaxRolesV1 : Nat := preflightMaxRolesV1
def unsignedSlotNumRolesV1 : Nat := preflightSlotNumRolesV1
def unsignedSlotProgramIdV1 : Nat := preflightSlotProgramIdV1
def unsignedSlotIxDataV1 : Nat := preflightSlotIxDataV1
def unsignedSlotHandlerIdV1 : Nat := preflightSlotHandlerIdV1
def unsignedSlotCursorV1 : Nat := preflightSlotCursorV1
/-- First temp lives at r10 - unsignedTempBaseV1; temp i at base + i*8. -/
def unsignedTempBaseV1 : Nat := 1096
def unsignedMaxTempsV1 : Nat := 16
def unsignedTempRegionEndV1 : Nat := unsignedTempBaseV1 + unsignedMaxTempsV1 * 8  -- 1224
/-- Default CPI base when computed scratch would be lower (keeps headroom). -/
def unsignedCpiBaseMinV1 : Nat := 1600
def unsignedMaxFrameBytesV1 : Nat := 4096
def unsignedInfoSizeV1 : Nat := 56
def unsignedMetaSizeV1 : Nat := 16
def unsignedInstructionSizeV1 : Nat := 40

private def emitFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def natHexLower (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def hexImm (value : Nat) : String :=
  "0x" ++ natHexLower value

private def asmLabel (name : String) : String :=
  String.ofList (name.toList.map fun c =>
    if c.isAlphanum || c == '_' then c else '_')

private def handlerLabel (h : CpiUnsignedHandlerIRV1) : String :=
  s!"handler_{h.handlerId}_{asmLabel h.name}_unsigned"

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
  unsignedTempBaseV1 + tempId * 8

private def emitHeader
    (b0 : AsmBuf) (handlerCount frameBytes cpiBase : Nat) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b "; proof-forge solana cpi unsigned companion SBPF (#119)"
    b := emit b "; TEST-PREACTIVATION ONLY — production-code-generated unsigned-CPI ELF"
    b := emit b "; not a product artifact; activationDenied; no OutputFile"
    b := emit b "; Direct-mapped Loader V3 ABIv1 walker + role table (16 x 64 = 1024B)"
    b := emit b "; Real sol_invoke_signed_c (zero signers) to pinned companion-v1"
    b := emit b "; Failure: exit with syscall status immediately (no clear, no later op)"
    b := emit b "; Success: sol_set_return_data(0,0) then continue body"
    b := emit b s!"; Handlers: {handlerCount}; frameBytes={frameBytes} (<= {unsignedMaxFrameBytesV1})"
    b := emit b s!"; CPI_BASE={cpiBase} (below role table/slots/temps; no overlap)"
    b := emitBlank b
    b := emit b s!".equ MAX_PERMITTED_DATA_INCREASE, {hexImm frozenLoaderV3AbiLayoutV1.maxPermittedDataIncrease}"
    b := emit b s!".equ FULL_PREFIX, {hexImm frozenLoaderV3AbiLayoutV1.fullPrefixBytes}"
    b := emit b s!".equ ROLE_BASE, {unsignedRoleTableBytesV1}"
    b := emit b s!".equ ROLE_STRIDE, {unsignedRoleStrideV1}"
    b := emit b ".equ ROLE_MARKER, 0"
    b := emit b ".equ ROLE_KEY, 8"
    b := emit b ".equ ROLE_OWNER, 16"
    b := emit b ".equ ROLE_LAMPORTS, 24"
    b := emit b ".equ ROLE_DATA, 32"
    b := emit b ".equ ROLE_DATA_LEN, 40"
    b := emit b ".equ ROLE_RENT, 48"
    b := emit b ".equ ROLE_FLAGS, 56"
    b := emit b s!".equ SLOT_NUM_ROLES, {unsignedSlotNumRolesV1}"
    b := emit b s!".equ SLOT_PROGRAM_ID, {unsignedSlotProgramIdV1}"
    b := emit b s!".equ SLOT_IX_DATA, {unsignedSlotIxDataV1}"
    b := emit b s!".equ SLOT_HANDLER_ID, {unsignedSlotHandlerIdV1}"
    b := emit b s!".equ SLOT_CURSOR, {unsignedSlotCursorV1}"
    b := emit b s!".equ CPI_BASE, {cpiBase}"
    b := emit b s!".equ INFO_SIZE, {unsignedInfoSizeV1}"
    b := emit b s!".equ META_SIZE, {unsignedMetaSizeV1}"
    b := emit b s!".equ INSTRUCTION_SIZE, {unsignedInstructionSizeV1}"
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

/-- Propagate raw CPI/syscall status in r0. -/
private def emitCpiFailed (b0 : AsmBuf) : AsmBuf :=
  let b := emit b0 "cpi_failed:"
  -- r0 already holds the nonzero status from the syscall.
  emit b "  exit"

private def emitRoleSlotAddr (b0 : AsmBuf) (indexImm : Nat) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b "  mov64 r2, r10"
    b := emit b "  lddw r3, ROLE_BASE"
    b := emit b "  sub64 r2, r3"
    if indexImm != 0 then
      b := emit b s!"  lddw r3, {indexImm * unsignedRoleStrideV1}"
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

/-! ## Preflight op emission (shared with #118 semantics) -/

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
    (b0 : AsmBuf) (src : CpiUnsignedU64SourceV1) (dstReg : String) : AsmBuf :=
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

/-- Emit unsigned invoke for one companion site. Clobbers r0–r9 carefully. -/
private def emitInvokeUnsigned
    (b0 : AsmBuf) (inv : CpiUnsignedInvokeV1) (labSuffix : String) :
    CompileResult AsmBuf := do
  unless inv.packageId == "companion-v1" do
    emitFail "emit invoke requires companion-v1"
  unless inv.dataLen == 9 do
    emitFail "companion invoke/fail dataLen must be 9"
  unless inv.metas.size == 1 do
    emitFail "companion invoke/fail expects exactly one meta"
  unless inv.principalBindings.size == 1 do
    emitFail "companion invoke/fail expects exactly one Principal binding"
  let meta0 := inv.metas[0]!
  let principal0 := inv.principalBindings[0]!
  unless principal0.argIndex == 0 && principal0.roleId == meta0.roleId &&
      principal0.localIndex == meta0.localIndex do
    emitFail "companion Principal binding must join meta[0] exactly"
  unless inv.accountInfoCount ≤ unsignedMaxRolesV1 do
    emitFail "accountInfoCount exceeds max roles"
  unless meta0.localIndex < inv.accountInfoCount &&
      inv.programLocalIndex < inv.accountInfoCount do
    emitFail "invoke local role index exceeds AccountInfo array"
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; --- invokeUnsigned site={inv.siteId} {inv.qn} tag={inv.tag} ---"
    b := emit b "  mov64 r9, r10"
    b := emit b "  lddw r4, CPI_BASE"
    b := emit b "  sub64 r9, r4                       ; r9 = cpi scratch base"
    -- zero 16B data slot, then tag || delta
    b := emit b "  lddw r4, 0"
    b := emit b "  stxdw [r9 + 0], r4"
    b := emit b "  stxdw [r9 + 8], r4"
    b := emit b s!"  lddw r4, {inv.tag}"
    b := emit b "  stxb [r9 + 0], r4"
    b := emitResolveU64Source b inv.delta "r4"
    b := emit b "  stxdw [r9 + 1], r4"
    -- meta[0]
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 16                       ; metas"
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
    -- SolInstruction at +32
    b := emit b "  mov64 r8, r9"
    b := emit b "  add64 r8, 32"
    b := emitRoleSlotAddr b inv.programLocalIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r8 + 0], r4                 ; program_id"
    b := emit b "  stxdw [r8 + 8], r5                 ; accounts"
    b := emit b "  lddw r4, 1"
    b := emit b "  stxdw [r8 + 16], r4                ; accounts_len"
    b := emit b "  stxdw [r8 + 24], r9                ; data"
    b := emit b "  lddw r4, 9"
    b := emit b "  stxdw [r8 + 32], r4                ; data_len"
    -- SolAccountInfo[localRoleCount] at +72
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 72"
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
    b := emit b s!"  lddw r3, {inv.accountInfoCount}"
    b := emit b s!"  jlt r7, r3, fill_info_{labSuffix}"
    -- sol_invoke_signed_c(instruction, infos, n, 0, 0)
    b := emit b "  mov64 r1, r8"
    b := emit b "  mov64 r2, r9"
    b := emit b "  add64 r2, 72"
    b := emit b s!"  lddw r3, {inv.accountInfoCount}"
    b := emit b "  lddw r4, 0"
    b := emit b "  lddw r5, 0"
    b := emit b "  call sol_invoke_signed_c"
    b := emit b "  jne r0, 0, cpi_failed"
    -- success clear return data
    b := emit b "  lddw r1, 0"
    b := emit b "  lddw r2, 0"
    b := emit b "  call sol_set_return_data"
    b := emit b "  jne r0, 0, cpi_failed"
    pure b

private def emitBodyOp
    (b0 : AsmBuf) (op : CpiUnsignedBodyOpV1) (labSuffix : String) :
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
  | .loadLiteralU64 tempId value =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; loadLiteralU64 temp={tempId} value={value.toNat}"
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
  | .invokeUnsigned inv =>
      emitInvokeUnsigned b0 inv labSuffix
  | .returnU64 srcTemp =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; returnU64 temp={srcTemp}"
        b := emitLoadTemp b srcTemp "r3"
        -- stash at r10 - CPI_BASE (reuse first 8B of CPI region as ret buffer)
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
    (b0 : AsmBuf) (h : CpiUnsignedHandlerIRV1) : CompileResult AsmBuf := do
  unless h.tempCount ≤ unsignedMaxTempsV1 do
    emitFail s!"handler {h.handlerId} tempCount {h.tempCount} > {unsignedMaxTempsV1}"
  unless h.localRoleCount ≤ unsignedMaxRolesV1 do
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
    | .invokeUnsigned _ =>
        b ← emitBodyOp b op suffix
        invokeIdx := invokeIdx + 1
    | _ =>
        b ← emitBodyOp b op suffix
  -- If body did not exit via return, fall through as shape error.
  b := emit b "  ja err_shape"
  pure b

/-! ## Entrypoint: ABIv1 walker + multi-handler probe dispatch -/

private def emitProbeEntrypoint
    (b0 : AsmBuf) (handlers : Array CpiUnsignedHandlerIRV1) : AsmBuf :=
  Id.run do
    let mut b := b0
    let fullPrefix := frozenLoaderV3AbiLayoutV1.fullPrefixBytes
    let growth := frozenLoaderV3AbiLayoutV1.maxPermittedDataIncrease
    b := emitBlank b
    b := emit b "; ----- test-preactivation entrypoint (NOT a product artifact) -----"
    b := emit b "; Instruction data: handlerId u64 LE + non-Principal UInt64 params."
    b := emit b "; Per-handler exact length enforced after dispatch."
    b := emit b ".globl entrypoint"
    b := emit b "entrypoint:"
    b := emit b "  mov64 r6, r1"
    b := emit b "  ldxdw r1, [r6 + 0]"
    b := emit b s!"  jgt r1, {unsignedMaxRolesV1}, err_shape"
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
    -- ix data length: at least 8 (handlerId); exact length per handler after dispatch
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

def emitCpiUnsignedSbpfV1
    (resolved : ResolvedSolanaCpiUnsignedIRV1) :
    CompileResult SolanaCpiUnsignedAssemblyV1 := do
  let cand := ResolvedSolanaCpiUnsignedIRV1.candidateOf resolved
  unless cand.maxOuterRoles == unsignedMaxRolesV1 do
    emitFail s!"maxOuterRoles must be {unsignedMaxRolesV1}"
  unless cand.maxFrameBytes == unsignedMaxFrameBytesV1 do
    emitFail "maxFrameBytes must be 4096"
  let maxScratch := unsignedMaxSiteScratchV1 cand
  let scratchReserve := Nat.max maxScratch 240
  -- CPI writes start at [r10-CPI_BASE] and grow toward higher addresses. Its
  -- complete interval is therefore offsets [CPI_BASE-scratchReserve, CPI_BASE].
  -- Put that lower-offset edge after the temp region; the old base-only check
  -- was insufficient at the 16-role boundary.
  let cpiBase := Nat.max unsignedCpiBaseMinV1
    (unsignedTempRegionEndV1 + scratchReserve)
  let frameBytes := cpiBase + scratchReserve
  unless frameBytes ≤ unsignedMaxFrameBytesV1 do
    emitFail s!"unsigned CPI frame {frameBytes} exceeds {unsignedMaxFrameBytesV1}"
  unless cpiBase ≥ unsignedTempRegionEndV1 + scratchReserve do
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
    emitFail "unsigned assembly must not contain ACC0 fixed slots"
  if hasSubstr text "0xec01" then
    emitFail "unsigned assembly must not contain legacy 0xec01 call stub"
  unless hasSubstr text "call sol_invoke_signed_c" do
    emitFail "unsigned assembly must contain sol_invoke_signed_c"
  unless hasSubstr text "call sol_set_return_data" do
    emitFail "unsigned assembly must contain sol_set_return_data"
  unless hasSubstr text "TEST-PREACTIVATION ONLY" do
    emitFail "unsigned assembly missing preactivation banner"
  unless hasSubstr text "not a product artifact" do
    emitFail "unsigned assembly missing product-boundary banner"
  -- Static: after cpi_failed there must be no state store / invoke / emit.
  -- cpi_failed is immediate exit; body store/call only appear on success paths.
  pure ⟨resolved, text, frameBytes⟩

end ProofForgeV2.Targets.Solana.CpiV1
