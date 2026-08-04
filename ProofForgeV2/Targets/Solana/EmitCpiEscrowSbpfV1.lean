/-
  ProofForgeV2.Targets.Solana.EmitCpiEscrowSbpfV1 — #124 composite escrow SBPF.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole emitter for production-code-generated **test-preactivation composite
  escrow CPI ELF** text. Accepts only `ResolvedSolanaCpiEscrowIRV1`. Public
  structural Plan/IR cannot feed this emitter.

  Emits:
  * ABIv1 multi-account walker + handler-entry global preflight;
  * ordered body: UInt64/UInt8 param/literal/stateLoad/checkedAdd/stateStore;
  * per site: siteArgChecks → siteChecks → invoke (strict source order);
  * System createPdaAccount (52B, canonical PDA, invoke_signed group0);
  * Token transferChecked / transferCheckedPda (10B 0x0c codec);
  * ATA createIdempotent (data byte 01, six metas, zero signer groups);
  * exact site-time Token/ATA field predicates;
  * every nonzero syscall status propagates immediately;
  * success clears return data via sol_set_return_data(0,0).

  Final call surface only: sol_try_find_program_address,
  sol_invoke_signed_c, sol_set_return_data. No 0xec01 / callx / ACC0_.

  Caller program id pin (runtime): all-0x59. Not OutputFile / product path.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.EmitCpiPreflightSbpfV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-! ## Private assembly carrier -/

/-- Private test-preactivation assembly carrier. isProductArtifact=false. -/
structure SolanaCpiEscrowAssemblyV1 where
  private mk ::
  resolved : ResolvedSolanaCpiEscrowIRV1
  text : String
  frameBytes : Nat

namespace SolanaCpiEscrowAssemblyV1

def textOf (a : SolanaCpiEscrowAssemblyV1) : String := a.text
def frameBytesOf (a : SolanaCpiEscrowAssemblyV1) : Nat := a.frameBytes
def resolvedOf (a : SolanaCpiEscrowAssemblyV1) : ResolvedSolanaCpiEscrowIRV1 :=
  a.resolved
def isProductArtifact (_ : SolanaCpiEscrowAssemblyV1) : Bool := false
def isTestPreactivation (_ : SolanaCpiEscrowAssemblyV1) : Bool := true

end SolanaCpiEscrowAssemblyV1

/-! ## Frame layout (shared role table / temps with #118–#123) -/

-- Frame constants are defined in CpiEscrowIRV1 (escrowTempRegionEndV1 etc.).
def escrowSlotNumRolesV1 : Nat := preflightSlotNumRolesV1
def escrowSlotProgramIdV1 : Nat := preflightSlotProgramIdV1
def escrowSlotIxDataV1 : Nat := preflightSlotIxDataV1
def escrowSlotHandlerIdV1 : Nat := preflightSlotHandlerIdV1
def escrowSlotCursorV1 : Nat := preflightSlotCursorV1
def escrowInfoSizeV1 : Nat := 56
def escrowMetaSizeV1 : Nat := 16
def escrowInstructionSizeV1 : Nat := 40
def escrowSeed0LenV1 : Nat := 18

private def emitFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def natHexLower (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def hexImm (value : Nat) : String :=
  "0x" ++ natHexLower value

private def asmLabel (name : String) : String :=
  String.ofList (name.toList.map fun c =>
    if c.isAlphanum || c == '_' then c else '_')

private def handlerLabel (h : CpiEscrowHandlerIRV1) : String :=
  s!"handler_{h.handlerId}_{asmLabel h.name}_token"

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
  escrowTempBaseV1 + tempId * 8

private def emitHeader
    (b0 : AsmBuf) (handlerCount frameBytes cpiBase : Nat) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b "; proof-forge solana composite escrow CPI SBPF (#124)"
    b := emit b "; TEST-PREACTIVATION ONLY — production-code-generated composite escrow CPI ELF"
    b := emit b "; not a product artifact; activationDenied; no OutputFile"
    b := emit b "; Direct-mapped Loader V3 ABIv1 walker + role table (16 x 64 = 1024B)"
    b := emit b "; Packages: system-v1 runtime-native; token-classic-v1/ata-classic-v1 absent"
    b := emit b "; createPdaAccount + transferChecked + transferCheckedPda + createIdempotent"
    b := emit b "; PDA rule: current-program-tagged-v1 (seed0=proof-forge:pda:v1); ATA ata-classic-v1"
    b := emit b "; caller program id pin (runtime): all-0x59; not OutputFile"
    b := emit b "; Failure: exit with syscall status immediately (no clear, no later op)"
    b := emit b "; Success: sol_set_return_data(0,0) then continue body"
    b := emit b s!"; Handlers: {handlerCount}; frameBytes={frameBytes} (<= {escrowMaxFrameBytesV1})"
    b := emit b s!"; CPI_BASE={cpiBase} (below role table/slots/temps; no overlap)"
    b := emitBlank b
    b := emit b s!".equ MAX_PERMITTED_DATA_INCREASE, {hexImm frozenLoaderV3AbiLayoutV1.maxPermittedDataIncrease}"
    b := emit b s!".equ FULL_PREFIX, {hexImm frozenLoaderV3AbiLayoutV1.fullPrefixBytes}"
    b := emit b s!".equ ROLE_BASE, {escrowRoleTableBytesV1}"
    b := emit b s!".equ ROLE_STRIDE, {escrowRoleStrideV1}"
    b := emit b ".equ ROLE_MARKER, 0"
    b := emit b ".equ ROLE_KEY, 8"
    b := emit b ".equ ROLE_OWNER, 16"
    b := emit b ".equ ROLE_LAMPORTS, 24"
    b := emit b ".equ ROLE_DATA, 32"
    b := emit b ".equ ROLE_DATA_LEN, 40"
    b := emit b ".equ ROLE_RENT, 48"
    b := emit b ".equ ROLE_FLAGS, 56"
    b := emit b s!".equ SLOT_NUM_ROLES, {escrowSlotNumRolesV1}"
    b := emit b s!".equ SLOT_PROGRAM_ID, {escrowSlotProgramIdV1}"
    b := emit b s!".equ SLOT_IX_DATA, {escrowSlotIxDataV1}"
    b := emit b s!".equ SLOT_HANDLER_ID, {escrowSlotHandlerIdV1}"
    b := emit b s!".equ SLOT_CURSOR, {escrowSlotCursorV1}"
    b := emit b s!".equ CPI_BASE, {cpiBase}"
    b := emit b s!".equ INFO_SIZE, {escrowInfoSizeV1}"
    b := emit b s!".equ META_SIZE, {escrowMetaSizeV1}"
    b := emit b s!".equ INSTRUCTION_SIZE, {escrowInstructionSizeV1}"
    b := emit b s!".equ SEED0_LEN, {escrowSeed0LenV1}"
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
      b := emit b s!"  lddw r3, {indexImm * escrowRoleStrideV1}"
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
    (b0 : AsmBuf) (src : CpiEscrowU64SourceV1) (dstReg : String) : AsmBuf :=
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
    (b0 : AsmBuf) (src : CpiEscrowU8SourceV1) (dstReg : String) : AsmBuf :=
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
        b := emit b s!"  ldxb {dstReg}, [r1 + {off}]"
        pure b

private def emitFillAccountInfos
    (b0 : AsmBuf) (n : Nat) (infosOff : Nat) (labSuffix : String) : AsmBuf :=
  Id.run do
    let mut b := b0
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
    pure b

private def emitWriteMeta
    (b0 : AsmBuf) (metaBaseReg : String) (metaSlot : Nat)
    (localIndex : Nat) (writable signer : Bool) : AsmBuf :=
  Id.run do
    let mut b := b0
    let off := metaSlot * 16
    b := emitRoleSlotAddr b localIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b s!"  stxdw [{metaBaseReg} + {off}], r4"
    b := emit b s!"  lddw r4, {if writable then 1 else 0}"
    b := emit b s!"  stxb [{metaBaseReg} + {off + 8}], r4"
    b := emit b s!"  lddw r4, {if signer then 1 else 0}"
    b := emit b s!"  stxb [{metaBaseReg} + {off + 9}], r4"
    b := emit b "  lddw r4, 0"
    for pad in [10:16] do
      b := emit b s!"  stxb [{metaBaseReg} + {off + pad}], r4"
    pure b

/-- Emit Token transferChecked: zero signer groups. -/
private def emitInvokeTransferChecked
    (b0 : AsmBuf) (inv : CpiEscrowInvokeV1) (labSuffix : String) :
    CompileResult AsmBuf := do
  unless inv.kind == .transferChecked do
    emitFail "emit transferChecked requires transferChecked kind"
  unless inv.packageId == "token-classic-v1" &&
      inv.qn == "solana.token.transferChecked" do
    emitFail "emit transferChecked requires token.transferChecked / token-classic-v1"
  unless inv.dataLen == 10 && inv.metas.size == 4 do
    emitFail "transferChecked dataLen/metas must be 10/4"
  unless inv.outerOnly.isEmpty && inv.signerGroupId.isNone do
    emitFail "transferChecked requires zero outer-only and zero signer groups"
  let some auth := inv.authority |
    emitFail "transferChecked authority binding missing"
  let some source := inv.source | emitFail "transferChecked source missing"
  let some mint := inv.mint | emitFail "transferChecked mint missing"
  let some destination := inv.destination | emitFail "transferChecked destination missing"
  let some amount := inv.amount | emitFail "transferChecked amount missing"
  let some decimals := inv.decimals | emitFail "transferChecked decimals missing"
  let meta0 := inv.metas[0]!
  let meta1 := inv.metas[1]!
  let meta2 := inv.metas[2]!
  let meta3 := inv.metas[3]!
  unless meta0.roleId == source.roleId &&
      meta0.localIndex == source.localIndex &&
      meta1.roleId == mint.roleId &&
      meta1.localIndex == mint.localIndex &&
      meta2.roleId == destination.roleId &&
      meta2.localIndex == destination.localIndex &&
      meta3.roleId == auth.roleId &&
      meta3.localIndex == auth.localIndex do
    emitFail "transferChecked Principal/meta join diverged"
  unless inv.accountInfoCount ≤ escrowMaxRolesV1 do
    emitFail "accountInfoCount exceeds max roles"
  let n := inv.accountInfoCount
  -- +0 data16, +16 Meta[4]=64, +80 Instruction, +120 Infos
  let infosOff := 120
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; --- invokeToken transferChecked site={inv.siteId} ---"
    b := emit b "  mov64 r9, r10"
    b := emit b "  lddw r4, CPI_BASE"
    b := emit b "  sub64 r9, r4                       ; r9 = cpi scratch base"
    -- +0 data16: 0c || amount u64le || decimals u8
    b := emit b "  lddw r4, 0"
    b := emit b "  stxdw [r9 + 0], r4"
    b := emit b "  stxdw [r9 + 8], r4"
    b := emit b "  lddw r4, 0x0c"
    b := emit b "  stxb [r9 + 0], r4                  ; TokenInstruction::TransferChecked"
    -- amount at +1 is unaligned; write 8 LE bytes explicitly
    b := emitResolveU64Source b amount "r4"
    for bi in [0:8] do
      b := emit b s!"  stxb [r9 + {1 + bi}], r4"
      b := emit b "  rsh64 r4, 8"
    b := emitResolveU8Source b decimals "r4"
    b := emit b "  and64 r4, 0xff"
    b := emit b "  stxb [r9 + 9], r4                  ; decimals u8"
    -- +16 Meta[4]
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 16                       ; metas"
    b := emitWriteMeta b "r5" 0 meta0.localIndex meta0.cpiWritable meta0.cpiSigner
    b := emitWriteMeta b "r5" 1 meta1.localIndex meta1.cpiWritable meta1.cpiSigner
    b := emitWriteMeta b "r5" 2 meta2.localIndex meta2.cpiWritable meta2.cpiSigner
    b := emitWriteMeta b "r5" 3 meta3.localIndex meta3.cpiWritable meta3.cpiSigner
    -- +80 SolInstruction
    b := emit b "  mov64 r8, r9"
    b := emit b "  add64 r8, 80"
    b := emitRoleSlotAddr b inv.programLocalIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r8 + 0], r4                 ; program_id (classic Token)"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 16"
    b := emit b "  stxdw [r8 + 8], r4                 ; accounts"
    b := emit b "  lddw r4, 4"
    b := emit b "  stxdw [r8 + 16], r4                ; accounts_len"
    b := emit b "  stxdw [r8 + 24], r9                ; data"
    b := emit b "  lddw r4, 10"
    b := emit b "  stxdw [r8 + 32], r4                ; data_len"
    b := emitFillAccountInfos b n infosOff labSuffix
    -- sol_invoke_signed_c(..., 0, 0)
    b := emit b "  mov64 r1, r8"
    b := emit b "  mov64 r2, r9"
    b := emit b s!"  add64 r2, {infosOff}"
    b := emit b s!"  lddw r3, {n}"
    b := emit b "  lddw r4, 0"
    b := emit b "  lddw r5, 0"
    b := emit b "  call sol_invoke_signed_c"
    b := emit b "  jne r0, 0, cpi_failed"
    b := emit b "  lddw r1, 0"
    b := emit b "  lddw r2, 0"
    b := emit b "  call sol_set_return_data"
    b := emit b "  jne r0, 0, cpi_failed"
    pure b

/-- Emit Token transferCheckedPda: find + signed invoke. -/
private def emitInvokeTransferCheckedPda
    (b0 : AsmBuf) (inv : CpiEscrowInvokeV1) (labSuffix : String) :
    CompileResult AsmBuf := do
  unless inv.kind == .transferCheckedPda do
    emitFail "emit transferCheckedPda requires transferCheckedPda kind"
  unless inv.packageId == "token-classic-v1" &&
      inv.qn == "solana.token.transferCheckedPda" do
    emitFail "emit transferCheckedPda requires token.transferCheckedPda / token-classic-v1"
  unless inv.dataLen == 10 && inv.metas.size == 4 && inv.outerOnly.size == 1 do
    emitFail "transferCheckedPda dataLen/metas/outer shape diverged"
  unless inv.signerGroupId == some 0 &&
      inv.pdaRule == some "current-program-tagged-v1" do
    emitFail "transferCheckedPda signer group / PDA rule diverged"
  let some authPda := inv.authorityPda |
    emitFail "transferCheckedPda authorityPda binding missing"
  let some seedAuth := inv.seedAuthority |
    emitFail "transferCheckedPda seedAuthority binding missing"
  let some seedTag := inv.seedTag | emitFail "transferCheckedPda seedTag missing"
  let some bump := inv.bump | emitFail "transferCheckedPda bump missing"
  let some source := inv.source | emitFail "transferCheckedPda source missing"
  let some mint := inv.mint | emitFail "transferCheckedPda mint missing"
  let some destination := inv.destination | emitFail "transferCheckedPda destination missing"
  let some amount := inv.amount | emitFail "transferCheckedPda amount missing"
  let some decimals := inv.decimals | emitFail "transferCheckedPda decimals missing"
  let meta0 := inv.metas[0]!
  let meta1 := inv.metas[1]!
  let meta2 := inv.metas[2]!
  let meta3 := inv.metas[3]!
  let oo0 := inv.outerOnly[0]!
  unless meta0.roleId == source.roleId &&
      meta0.localIndex == source.localIndex &&
      meta1.roleId == mint.roleId &&
      meta1.localIndex == mint.localIndex &&
      meta2.roleId == destination.roleId &&
      meta2.localIndex == destination.localIndex &&
      meta3.roleId == authPda.roleId &&
      meta3.localIndex == authPda.localIndex &&
      oo0.roleId == seedAuth.roleId &&
      oo0.localIndex == seedAuth.localIndex do
    emitFail "transferCheckedPda Principal/meta/outer join diverged"
  unless inv.accountInfoCount ≤ escrowMaxRolesV1 do
    emitFail "accountInfoCount exceeds max roles"
  let n := inv.accountInfoCount
  -- Layout (see CpiEscrowIRV1):
  -- +0 data16, +16 seed0/24, +40 seedTag, +48 bump,
  -- +56 SolSignerSeed[4], +120 SolSignerSeeds, +136 Meta[4],
  -- +200 Instruction, +240 Infos, +240+56N keyOut, +272+56N bumpOut
  let infosOff := 240
  let keyOutOff := 240 + 56 * n
  let bumpOutOff := 272 + 56 * n
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; --- invokeToken transferCheckedPda site={inv.siteId} ---"
    b := emit b "  mov64 r9, r10"
    b := emit b "  lddw r4, CPI_BASE"
    b := emit b "  sub64 r9, r4                       ; r9 = cpi scratch base"
    -- zero 16B data then write TransferChecked
    b := emit b "  lddw r4, 0"
    b := emit b "  stxdw [r9 + 0], r4"
    b := emit b "  stxdw [r9 + 8], r4"
    b := emit b "  lddw r4, 0x0c"
    b := emit b "  stxb [r9 + 0], r4                  ; TokenInstruction::TransferChecked"
    -- amount at +1 is unaligned; write 8 LE bytes explicitly
    b := emitResolveU64Source b amount "r4"
    for bi in [0:8] do
      b := emit b s!"  stxb [r9 + {1 + bi}], r4"
      b := emit b "  rsh64 r4, 8"
    b := emitResolveU8Source b decimals "r4"
    b := emit b "  and64 r4, 0xff"
    b := emit b "  stxb [r9 + 9], r4"
    -- seed0 = proof-forge:pda:v1
    b := emit b "  ; seed0 = proof-forge:pda:v1 (18 bytes)"
    b := emit b "  lddw r4, 0x6f662d666f6f7270"
    b := emit b "  stxdw [r9 + 16], r4"
    b := emit b "  lddw r4, 0x3a6164703a656772"
    b := emit b "  stxdw [r9 + 24], r4"
    b := emit b "  lddw r4, 0x3176"
    b := emit b "  stxdw [r9 + 32], r4"
    b := emitResolveU64Source b seedTag "r4"
    b := emit b "  stxdw [r9 + 40], r4"
    b := emitResolveU8Source b bump "r4"
    b := emit b "  and64 r4, 0xff"
    b := emit b "  jeq r4, 0, err_shape                 ; bump param 0 rejected"
    b := emit b "  stxdw [r9 + 48], r4"
    -- SolSignerSeed[4] at +56
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 16"
    b := emit b "  stxdw [r9 + 56], r5"
    b := emit b "  lddw r4, SEED0_LEN"
    b := emit b "  stxdw [r9 + 64], r4"
    b := emitRoleSlotAddr b oo0.localIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r9 + 72], r4"
    b := emit b "  lddw r4, 32"
    b := emit b "  stxdw [r9 + 80], r4"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 40"
    b := emit b "  stxdw [r9 + 88], r5"
    b := emit b "  lddw r4, 8"
    b := emit b "  stxdw [r9 + 96], r4"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 48"
    b := emit b "  stxdw [r9 + 104], r5"
    b := emit b "  lddw r4, 1"
    b := emit b "  stxdw [r9 + 112], r4"
    -- SolSignerSeeds group at +120
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 56"
    b := emit b "  stxdw [r9 + 120], r5"
    b := emit b "  lddw r4, 4"
    b := emit b "  stxdw [r9 + 128], r4"
    -- find over first 3 seeds
    b := emit b "  ; find canonical PDA over seed0/seedAuthority/seedTag"
    b := emit b "  mov64 r1, r9"
    b := emit b "  add64 r1, 56"
    b := emit b "  lddw r2, 3"
    b := emit b "  ldxdw r3, [r10 - SLOT_PROGRAM_ID]"
    b := emit b "  mov64 r4, r9"
    b := emit b s!"  add64 r4, {keyOutOff}"
    b := emit b "  mov64 r5, r9"
    b := emit b s!"  add64 r5, {bumpOutOff}"
    b := emit b "  call sol_try_find_program_address"
    b := emit b "  jne r0, 0, cpi_failed"
    b := emit b "  ldxb r1, [r9 + 48]"
    b := emit b s!"  ldxb r2, [r9 + {bumpOutOff}]"
    b := emit b "  jne r1, r2, err_shape"
    -- returned key == authorityPda ROLE_KEY
    b := emitRoleSlotAddr b meta3.localIndex
    b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
    b := emit b "  mov64 r1, r9"
    b := emit b s!"  add64 r1, {keyOutOff}"
    for word in [0:4] do
      b := emit b s!"  ldxdw r3, [r5 + {word * 8}]"
      b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
      b := emit b s!"  jne r3, r4, err_shape"
    -- metas at +136
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 136"
    b := emitWriteMeta b "r5" 0 meta0.localIndex meta0.cpiWritable meta0.cpiSigner
    b := emitWriteMeta b "r5" 1 meta1.localIndex meta1.cpiWritable meta1.cpiSigner
    b := emitWriteMeta b "r5" 2 meta2.localIndex meta2.cpiWritable meta2.cpiSigner
    b := emitWriteMeta b "r5" 3 meta3.localIndex meta3.cpiWritable meta3.cpiSigner
    -- instruction at +200
    b := emit b "  mov64 r8, r9"
    b := emit b "  add64 r8, 200"
    b := emitRoleSlotAddr b inv.programLocalIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r8 + 0], r4"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 136"
    b := emit b "  stxdw [r8 + 8], r4"
    b := emit b "  lddw r4, 4"
    b := emit b "  stxdw [r8 + 16], r4"
    b := emit b "  stxdw [r8 + 24], r9"
    b := emit b "  lddw r4, 10"
    b := emit b "  stxdw [r8 + 32], r4"
    b := emitFillAccountInfos b n infosOff labSuffix
    -- signed invoke: 1 signer group / 4 seeds
    b := emit b "  mov64 r1, r8"
    b := emit b "  mov64 r2, r9"
    b := emit b s!"  add64 r2, {infosOff}"
    b := emit b s!"  lddw r3, {n}"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 120"
    b := emit b "  lddw r5, 1"
    b := emit b "  call sol_invoke_signed_c"
    b := emit b "  jne r0, 0, cpi_failed"
    b := emit b "  lddw r1, 0"
    b := emit b "  lddw r2, 0"
    b := emit b "  call sol_set_return_data"
    b := emit b "  jne r0, 0, cpi_failed"
    pure b

private def emitSiteArgChecks
    (b0 : AsmBuf) (siteId : Nat) (checks : Array CpiEscrowArgCheckV1) :
    AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; siteArgChecks site={siteId} (before siteChecks)"
    for c in checks do
      match c with
      | .unusedPlaceholder => pure ()
      | .uint64AtMost name src maxV =>
          b := emit b s!"  ; uint64AtMost {name} <= {maxV}"
          b := emitResolveU64Source b src "r3"
          b := emit b s!"  lddw r4, {maxV + 1}"
          b := emit b "  jge r3, r4, err_shape"
    pure b

/-- Compare account data[baseOff..baseOff+32) to peer role key (4×u64 LE). -/
private def emitDataKeyEqualsRole
    (b0 : AsmBuf) (accountLocal peerLocal baseOff : Nat) (errLab note : String) :
    AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; {note} accountLocal={accountLocal} peerLocal={peerLocal} data@{baseOff}"
    b := emitRoleSlotAddr b accountLocal
    b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
    b := emitRoleSlotAddr b peerLocal
    b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
    for word in [0:4] do
      b := emit b s!"  ldxdw r3, [r1 + {baseOff + word * 8}]"
      b := emit b s!"  ldxdw r4, [r5 + {word * 8}]"
      b := emit b s!"  jne r3, r4, {errLab}"
    pure b

private def emitEscrowSiteCheck
    (b0 : AsmBuf) (check : CpiEscrowSiteCheckV1) (errLab labelSuffix : String) :
    CompileResult AsmBuf := do
  match check with
  | .generic op =>
      emitPreflightOp b0 op errLab
  | .tokenAccountStateInitialized localIndex =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; tokenAccountStateInitialized local={localIndex} data[108]==1"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
        b := emit b "  ldxb r3, [r1 + 108]"
        b := emit b s!"  jne r3, 1, {errLab}"
        pure b
  | .tokenAccountMintEqualsRole accountLocal mintLocal =>
      pure (emitDataKeyEqualsRole b0 accountLocal mintLocal 0 errLab
        "tokenAccountMintEqualsRole")
  | .tokenAccountOwnerEqualsRole accountLocal ownerLocal =>
      pure (emitDataKeyEqualsRole b0 accountLocal ownerLocal 32 errLab
        "tokenAccountOwnerEqualsRole")
  | .tokenAccountDelegateNone localIndex =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; tokenAccountDelegateNone local={localIndex} data[72..76] u32le==0"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
        -- u32 LE at offset 72 (may be unaligned relative to data base; byte loads)
        b := emit b "  ldxb r3, [r1 + 72]"
        b := emit b "  ldxb r4, [r1 + 73]"
        b := emit b "  lsh64 r4, 8"
        b := emit b "  or64 r3, r4"
        b := emit b "  ldxb r4, [r1 + 74]"
        b := emit b "  lsh64 r4, 16"
        b := emit b "  or64 r3, r4"
        b := emit b "  ldxb r4, [r1 + 75]"
        b := emit b "  lsh64 r4, 24"
        b := emit b "  or64 r3, r4"
        b := emit b s!"  jne r3, 0, {errLab}"
        pure b
  | .tokenMintInitialized localIndex =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; tokenMintInitialized local={localIndex} data[45]==1"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
        b := emit b "  ldxb r3, [r1 + 45]"
        b := emit b s!"  jne r3, 1, {errLab}"
        pure b
  | .tokenMintDecimalsEquals localIndex decimalsSrc =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; tokenMintDecimalsEquals local={localIndex} data[44]==decimals"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
        b := emit b "  ldxb r3, [r1 + 44]"
        b := emitResolveU8Source b decimalsSrc "r4"
        b := emit b "  and64 r4, 0xff"
        b := emit b s!"  jne r3, r4, {errLab}"
        pure b

  | .ataAddressCanonical ataLocal walletLocal tokenLocal mintLocal ataProgramLocal =>
      pure <| Id.run do
        let mut b := b0
        b := emit b "  ; ataAddressCanonical seeds=[wallet,classicToken,mint]"
        b := emit b "  mov64 r9, r10"
        b := emit b "  lddw r4, CPI_BASE"
        b := emit b "  sub64 r9, r4"
        b := emitRoleSlotAddr b walletLocal
        b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
        b := emit b "  stxdw [r9 + 16], r4"
        b := emit b "  lddw r4, 32"
        b := emit b "  stxdw [r9 + 24], r4"
        b := emitRoleSlotAddr b tokenLocal
        b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
        b := emit b "  stxdw [r9 + 32], r4"
        b := emit b "  lddw r4, 32"
        b := emit b "  stxdw [r9 + 40], r4"
        b := emitRoleSlotAddr b mintLocal
        b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
        b := emit b "  stxdw [r9 + 48], r4"
        b := emit b "  lddw r4, 32"
        b := emit b "  stxdw [r9 + 56], r4"
        b := emit b "  mov64 r1, r9"
        b := emit b "  add64 r1, 16"
        b := emitRoleSlotAddr b ataProgramLocal
        b := emit b "  ldxdw r3, [r2 + ROLE_KEY]"
        b := emit b "  lddw r2, 3"
        b := emit b "  mov64 r4, r9"
        b := emit b "  add64 r4, 64"
        b := emit b "  mov64 r5, r9"
        b := emit b "  add64 r5, 96"
        b := emit b "  call sol_try_find_program_address"
        b := emit b "  jne r0, 0, cpi_failed"
        b := emitRoleSlotAddr b ataLocal
        b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
        b := emit b "  mov64 r1, r9"
        b := emit b "  add64 r1, 64"
        for word in [0:4] do
          b := emit b s!"  ldxdw r3, [r5 + {word * 8}]"
          b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
          b := emit b s!"  jne r3, r4, {errLab}"
        pure b
  | .ataAccountPrestateClosed ataLocal walletLocal mintLocal systemLocal tokenLocal =>
      pure <| Id.run do
        let mut b := b0
        let freshLab := s!"ata_pre_fresh_{labelSuffix}"
        let doneLab := s!"ata_pre_done_{labelSuffix}"
        b := emit b "  ; ataAccountPrestateClosed: fresh System OR existing classic Token"
        b := emitRoleSlotAddr b ataLocal
        b := emit b "  ldxdw r1, [r2 + ROLE_OWNER]"
        b := emitRoleSlotAddr b systemLocal
        b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
        b := emit b "  lddw r3, 0"
        for word in [0:4] do
          b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
          b := emit b s!"  ldxdw r2, [r5 + {word * 8}]"
          b := emit b "  xor64 r4, r2"
          b := emit b "  or64 r3, r4"
        b := emit b s!"  jeq r3, 0, {freshLab}"
        b := emitRoleSlotAddr b ataLocal
        b := emit b "  ldxdw r1, [r2 + ROLE_OWNER]"
        b := emitRoleSlotAddr b tokenLocal
        b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
        for word in [0:4] do
          b := emit b s!"  ldxdw r3, [r1 + {word * 8}]"
          b := emit b s!"  ldxdw r4, [r5 + {word * 8}]"
          b := emit b s!"  jne r3, r4, {errLab}"
        b := emitDataLenCheck b ataLocal 165 errLab
        b := emitRoleSlotAddr b ataLocal
        b := emit b "  ldxdw r1, [r2 + ROLE_DATA]"
        b := emit b "  ldxb r3, [r1 + 108]"
        b := emit b s!"  jne r3, 1, {errLab}"
        b := emitDataKeyEqualsRole b ataLocal mintLocal 0 errLab "ATA mint join"
        b := emitDataKeyEqualsRole b ataLocal walletLocal 32 errLab "ATA wallet-owner join"
        b := emit b s!"  ja {doneLab}"
        b := emit b s!"{freshLab}:"
        b := emitDataLenCheck b ataLocal 0 errLab
        b := emitRoleSlotAddr b ataLocal
        b := emit b "  ldxdw r1, [r2 + ROLE_LAMPORTS]"
        b := emit b "  ldxdw r3, [r1 + 0]"
        b := emit b s!"  jne r3, 0, {errLab}"
        b := emit b s!"{doneLab}:"
        pure b

private def emitInvokeCreatePdaAccount
    (b0 : AsmBuf) (inv : CpiEscrowInvokeV1) (labSuffix : String) :
    CompileResult AsmBuf := do
  unless inv.kind == .createPdaAccount do
    emitFail "emit createPdaAccount requires createPdaAccount kind"
  unless inv.packageId == "system-v1" &&
      inv.qn == "solana.system.createPdaAccount" do
    emitFail "emit createPdaAccount requires system.createPdaAccount / system-v1"
  unless inv.dataLen == 52 && inv.metas.size == 2 && inv.outerOnly.size == 1 do
    emitFail "createPdaAccount dataLen/metas/outer shape diverged"
  unless inv.signerGroupId == some 0 &&
      inv.pdaRule == some "current-program-tagged-v1" do
    emitFail "createPdaAccount signer group / PDA rule diverged"
  let some payer := inv.payer | emitFail "createPdaAccount payer missing"
  let some pdaB := inv.pda | emitFail "createPdaAccount pda missing"
  let some seedAuth := inv.seedAuthority | emitFail "createPdaAccount seedAuthority missing"
  let some seedTag := inv.seedTag | emitFail "createPdaAccount seedTag missing"
  let some bump := inv.bump | emitFail "createPdaAccount bump missing"
  let some lamports := inv.lamports | emitFail "createPdaAccount lamports missing"
  let some space := inv.space | emitFail "createPdaAccount space missing"
  let meta0 := inv.metas[0]!
  let meta1 := inv.metas[1]!
  let oo0 := inv.outerOnly[0]!
  unless meta0.roleId == payer.roleId &&
      meta0.localIndex == payer.localIndex &&
      meta1.roleId == pdaB.roleId &&
      meta1.localIndex == pdaB.localIndex &&
      oo0.roleId == seedAuth.roleId &&
      oo0.localIndex == seedAuth.localIndex do
    emitFail "createPda Principal/meta/outer join diverged"
  unless inv.accountInfoCount ≤ escrowMaxRolesV1 do
    emitFail "accountInfoCount exceeds max roles"
  let n := inv.accountInfoCount
  -- Scratch exclusive end = 289 + 56*N (bumpOut is 1 byte at 288+56N).
  let infosOff := 256
  let keyOutOff := 256 + 56 * n
  let bumpOutOff := 288 + 56 * n
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; --- invokeEscrow createPdaAccount site={inv.siteId} ---"
    b := emit b "  mov64 r9, r10"
    b := emit b "  lddw r4, CPI_BASE"
    b := emit b "  sub64 r9, r4                       ; r9 = cpi scratch base"
    b := emit b "  lddw r4, 0"
    for off in [0:64:8] do
      b := emit b s!"  stxdw [r9 + {off}], r4"
    b := emit b "  lddw r4, 0"
    b := emit b "  stxw [r9 + 0], r4                  ; SystemInstruction::CreateAccount"
    b := emitResolveU64Source b lamports "r4"
    b := emit b "  stxdw [r9 + 4], r4"
    b := emitResolveU64Source b space "r4"
    b := emit b "  stxdw [r9 + 12], r4"
    b := emit b "  ldxdw r1, [r10 - SLOT_PROGRAM_ID]"
    for word in [0:4] do
      b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
      b := emit b s!"  stxdw [r9 + {20 + word * 8}], r4"
    b := emit b "  ; seed0 = proof-forge:pda:v1 (18 bytes)"
    b := emit b "  lddw r4, 0x6f662d666f6f7270"
    b := emit b "  stxdw [r9 + 64], r4"
    b := emit b "  lddw r4, 0x3a6164703a656772"
    b := emit b "  stxdw [r9 + 72], r4"
    b := emit b "  lddw r4, 0x3176"
    b := emit b "  stxdw [r9 + 80], r4"
    b := emitResolveU64Source b seedTag "r4"
    b := emit b "  stxdw [r9 + 88], r4"
    b := emitResolveU8Source b bump "r4"
    b := emit b "  and64 r4, 0xff"
    b := emit b "  jeq r4, 0, err_shape                 ; bump param 0 rejected"
    b := emit b "  stxdw [r9 + 96], r4"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 64"
    b := emit b "  stxdw [r9 + 104], r5"
    b := emit b "  lddw r4, SEED0_LEN"
    b := emit b "  stxdw [r9 + 112], r4"
    b := emitRoleSlotAddr b oo0.localIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r9 + 120], r4"
    b := emit b "  lddw r4, 32"
    b := emit b "  stxdw [r9 + 128], r4"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 88"
    b := emit b "  stxdw [r9 + 136], r5"
    b := emit b "  lddw r4, 8"
    b := emit b "  stxdw [r9 + 144], r4"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 96"
    b := emit b "  stxdw [r9 + 152], r5"
    b := emit b "  lddw r4, 1"
    b := emit b "  stxdw [r9 + 160], r4"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 104"
    b := emit b "  stxdw [r9 + 168], r5"
    b := emit b "  lddw r4, 4"
    b := emit b "  stxdw [r9 + 176], r4"
    b := emit b "  ; find canonical PDA over seed0/seedAuthority/seedTag"
    b := emit b "  mov64 r1, r9"
    b := emit b "  add64 r1, 104"
    b := emit b "  lddw r2, 3"
    b := emit b "  ldxdw r3, [r10 - SLOT_PROGRAM_ID]"
    b := emit b "  mov64 r4, r9"
    b := emit b s!"  add64 r4, {keyOutOff}"
    b := emit b "  mov64 r5, r9"
    b := emit b s!"  add64 r5, {bumpOutOff}"
    b := emit b "  call sol_try_find_program_address"
    b := emit b "  jne r0, 0, cpi_failed"
    b := emit b "  ldxb r1, [r9 + 96]"
    b := emit b s!"  ldxb r2, [r9 + {bumpOutOff}]"
    b := emit b "  jne r1, r2, err_shape"
    b := emitRoleSlotAddr b meta1.localIndex
    b := emit b "  ldxdw r5, [r2 + ROLE_KEY]"
    b := emit b "  mov64 r1, r9"
    b := emit b s!"  add64 r1, {keyOutOff}"
    for word in [0:4] do
      b := emit b s!"  ldxdw r3, [r5 + {word * 8}]"
      b := emit b s!"  ldxdw r4, [r1 + {word * 8}]"
      b := emit b s!"  jne r3, r4, err_shape"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 184"
    b := emitWriteMeta b "r5" 0 meta0.localIndex meta0.cpiWritable meta0.cpiSigner
    b := emitWriteMeta b "r5" 1 meta1.localIndex meta1.cpiWritable meta1.cpiSigner
    b := emit b "  mov64 r8, r9"
    b := emit b "  add64 r8, 216"
    b := emitRoleSlotAddr b inv.programLocalIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r8 + 0], r4"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 184"
    b := emit b "  stxdw [r8 + 8], r4"
    b := emit b "  lddw r4, 2"
    b := emit b "  stxdw [r8 + 16], r4"
    b := emit b "  stxdw [r8 + 24], r9"
    b := emit b "  lddw r4, 52"
    b := emit b "  stxdw [r8 + 32], r4"
    b := emitFillAccountInfos b n infosOff labSuffix
    b := emit b "  mov64 r1, r8"
    b := emit b "  mov64 r2, r9"
    b := emit b s!"  add64 r2, {infosOff}"
    b := emit b s!"  lddw r3, {n}"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 168"
    b := emit b "  lddw r5, 1"
    b := emit b "  call sol_invoke_signed_c"
    b := emit b "  jne r0, 0, cpi_failed"
    b := emit b "  lddw r1, 0"
    b := emit b "  lddw r2, 0"
    b := emit b "  call sol_set_return_data"
    b := emit b "  jne r0, 0, cpi_failed"
    pure b

/-- Emit classic ATA CreateIdempotent: six metas, zero signer groups. -/
private def emitInvokeCreateIdempotent
    (b0 : AsmBuf) (inv : CpiEscrowInvokeV1) (labSuffix : String) :
    CompileResult AsmBuf := do
  unless inv.kind == .createIdempotent &&
      inv.packageId == "ata-classic-v1" &&
      inv.qn == "solana.ata.createIdempotent" do
    emitFail "emit ATA invoke requires createIdempotent / ata-classic-v1"
  unless inv.dataLen == 1 && inv.metas.size == 6 &&
      inv.outerOnly.isEmpty && inv.signerGroupId.isNone &&
      inv.pdaRule == some "ata-classic-v1" do
    emitFail "ATA invoke data/metas/signer/PDA shape diverged"
  let some payer := inv.payer | emitFail "ATA payer missing"
  let some ataB := inv.ata | emitFail "ATA ata missing"
  let some wallet := inv.wallet | emitFail "ATA wallet missing"
  let some mint := inv.mint | emitFail "ATA mint missing"
  let some systemLocal := inv.systemProgramLocalIndex | emitFail "ATA system local missing"
  let some tokenLocal := inv.tokenProgramLocalIndex | emitFail "ATA token local missing"
  let meta0 := inv.metas[0]!
  let meta1 := inv.metas[1]!
  let meta2 := inv.metas[2]!
  let meta3 := inv.metas[3]!
  let meta4 := inv.metas[4]!
  let meta5 := inv.metas[5]!
  unless meta0.roleId == payer.roleId &&
      meta0.localIndex == payer.localIndex &&
      meta1.roleId == ataB.roleId &&
      meta1.localIndex == ataB.localIndex &&
      meta2.roleId == wallet.roleId &&
      meta2.localIndex == wallet.localIndex &&
      meta3.roleId == mint.roleId &&
      meta3.localIndex == mint.localIndex &&
      meta4.localIndex == systemLocal &&
      meta5.localIndex == tokenLocal do
    emitFail "ATA Principal/fixed-program meta join diverged"
  unless inv.accountInfoCount ≤ escrowMaxRolesV1 do
    emitFail "ATA accountInfoCount exceeds max roles"
  let n := inv.accountInfoCount
  let infosOff := 240
  pure <| Id.run do
    let mut b := b0
    b := emit b s!"  ; --- invokeEscrow createIdempotent site={inv.siteId} ---"
    b := emit b "  mov64 r9, r10"
    b := emit b "  lddw r4, CPI_BASE"
    b := emit b "  sub64 r9, r4                       ; r9 = cpi scratch base"
    b := emit b "  lddw r4, 0"
    b := emit b "  stxdw [r9 + 0], r4"
    b := emit b "  stxdw [r9 + 8], r4"
    b := emit b "  lddw r4, 1"
    b := emit b "  stxb [r9 + 0], r4                  ; CreateIdempotent"
    b := emit b "  mov64 r5, r9"
    b := emit b "  add64 r5, 104"
    b := emitWriteMeta b "r5" 0 meta0.localIndex meta0.cpiWritable meta0.cpiSigner
    b := emitWriteMeta b "r5" 1 meta1.localIndex meta1.cpiWritable meta1.cpiSigner
    b := emitWriteMeta b "r5" 2 meta2.localIndex meta2.cpiWritable meta2.cpiSigner
    b := emitWriteMeta b "r5" 3 meta3.localIndex meta3.cpiWritable meta3.cpiSigner
    b := emitWriteMeta b "r5" 4 meta4.localIndex meta4.cpiWritable meta4.cpiSigner
    b := emitWriteMeta b "r5" 5 meta5.localIndex meta5.cpiWritable meta5.cpiSigner
    b := emit b "  mov64 r8, r9"
    b := emit b "  add64 r8, 200"
    b := emitRoleSlotAddr b inv.programLocalIndex
    b := emit b "  ldxdw r4, [r2 + ROLE_KEY]"
    b := emit b "  stxdw [r8 + 0], r4"
    b := emit b "  mov64 r4, r9"
    b := emit b "  add64 r4, 104"
    b := emit b "  stxdw [r8 + 8], r4"
    b := emit b "  lddw r4, 6"
    b := emit b "  stxdw [r8 + 16], r4"
    b := emit b "  stxdw [r8 + 24], r9"
    b := emit b "  lddw r4, 1"
    b := emit b "  stxdw [r8 + 32], r4"
    b := emitFillAccountInfos b n infosOff labSuffix
    b := emit b "  mov64 r1, r8"
    b := emit b "  mov64 r2, r9"
    b := emit b s!"  add64 r2, {infosOff}"
    b := emit b s!"  lddw r3, {n}"
    b := emit b "  lddw r4, 0"
    b := emit b "  lddw r5, 0"
    b := emit b "  call sol_invoke_signed_c"
    b := emit b "  jne r0, 0, cpi_failed"
    b := emit b "  lddw r1, 0"
    b := emit b "  lddw r2, 0"
    b := emit b "  call sol_set_return_data"
    b := emit b "  jne r0, 0, cpi_failed"
    pure b

private def emitBodyOp
    (b0 : AsmBuf) (op : CpiEscrowBodyOpV1) (labSuffix : String) :
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
  | .siteArgChecks siteId checks =>
      pure (emitSiteArgChecks b0 siteId checks)
  | .siteChecks siteId ops => do
      let mut b := b0
      b := emit b s!"  ; siteChecks site={siteId} (site-time, not entry-hoisted)"
      for op in ops do
        b ← emitEscrowSiteCheck b op "err_shape" labSuffix
      pure b
  | .invokeEscrow inv =>
      match inv.kind with
      | .transferChecked => emitInvokeTransferChecked b0 inv labSuffix
      | .transferCheckedPda => emitInvokeTransferCheckedPda b0 inv labSuffix
      | .createPdaAccount => emitInvokeCreatePdaAccount b0 inv labSuffix
      | .createIdempotent => emitInvokeCreateIdempotent b0 inv labSuffix
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


/-- Emit System createPdaAccount: find + signed invoke (owner = current program). -/
private def emitHandlerSection
    (b0 : AsmBuf) (h : CpiEscrowHandlerIRV1) : CompileResult AsmBuf := do
  unless h.tempCount ≤ escrowMaxTempsV1 do
    emitFail s!"handler {h.handlerId} tempCount {h.tempCount} > {escrowMaxTempsV1}"
  unless h.localRoleCount ≤ escrowMaxRolesV1 do
    emitFail s!"handler {h.handlerId} localRoleCount exceeds cap"
  let lab := handlerLabel h
  let mut b := b0
  b := emitBlank b
  b := emit b s!"; ===== handler {h.handlerId} {h.name} localRoles={h.localRoleCount} temps={h.tempCount} ====="
  b := emit b s!"{lab}:"
  b := emit b "  ; --- handler-entry global preflight (no site predicates) ---"
  for op in h.entryGlobalOps do
    b ← emitPreflightOp b op "err_shape"
  b := emit b "  ; --- ordered body (siteArgChecks → siteChecks → invoke) ---"
  let mut invokeIdx : Nat := 0
  for op in h.bodyOps do
    let suffix := s!"{h.handlerId}_{invokeIdx}"
    match op with
    | .invokeEscrow _ =>
        b ← emitBodyOp b op suffix
        invokeIdx := invokeIdx + 1
    | _ =>
        b ← emitBodyOp b op suffix
  b := emit b "  ja err_shape"
  pure b

private def emitProbeEntrypoint
    (b0 : AsmBuf) (handlers : Array CpiEscrowHandlerIRV1) : AsmBuf :=
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
    b := emit b s!"  jgt r1, {escrowMaxRolesV1}, err_shape"
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
    b := emit b "  stxdw [r10 - SLOT_CURSOR], r1"
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

/-- Round up to a multiple of 8 so CPI_BASE / scratch bases keep
    sol_invoke_signed_c / SolInstruction pointers 8-byte aligned. -/
private def alignUp8 (n : Nat) : Nat :=
  ((n + 7) / 8) * 8

def emitCpiEscrowSbpfV1
    (resolved : ResolvedSolanaCpiEscrowIRV1) :
    CompileResult SolanaCpiEscrowAssemblyV1 := do
  let cand := ResolvedSolanaCpiEscrowIRV1.candidateOf resolved
  unless cand.maxOuterRoles == escrowMaxRolesV1 do
    emitFail s!"maxOuterRoles must be {escrowMaxRolesV1}"
  unless cand.maxFrameBytes == escrowMaxFrameBytesV1 do
    emitFail "maxFrameBytes must be 4096"
  let maxScratch := escrowMaxSiteScratchV1 cand
  -- Exclusive-end scratch (e.g. createPda 289+56N) may be non-multiple of 8.
  -- Align reserve and CPI_BASE so every site base r9 = r10 - CPI_BASE is 8-aligned.
  let scratchReserve := alignUp8 (Nat.max maxScratch 240)
  let cpiBase := alignUp8
    (Nat.max escrowCpiBaseMinV1 (escrowTempRegionEndV1 + scratchReserve))
  let frameBytes := cpiBase + scratchReserve
  unless scratchReserve % 8 == 0 do
    emitFail s!"scratchReserve {scratchReserve} must be 8-byte aligned"
  unless cpiBase % 8 == 0 do
    emitFail s!"CPI_BASE {cpiBase} must be 8-byte aligned"
  unless frameBytes ≤ escrowMaxFrameBytesV1 do
    emitFail s!"Escrow CPI frame {frameBytes} exceeds {escrowMaxFrameBytesV1}"
  unless cpiBase ≥ escrowTempRegionEndV1 + scratchReserve do
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
    emitFail "Escrow assembly must not contain ACC0 fixed slots"
  if hasSubstr text "0xec01" then
    emitFail "Escrow assembly must not contain legacy 0xec01 call stub"
  if hasSubstr text "callx" then
    emitFail "Escrow assembly must not contain callx"
  unless hasSubstr text "call sol_invoke_signed_c" do
    emitFail "Escrow assembly must contain sol_invoke_signed_c"
  unless hasSubstr text "call sol_set_return_data" do
    emitFail "Escrow assembly must contain sol_set_return_data"
  unless hasSubstr text "TEST-PREACTIVATION ONLY" do
    emitFail "Escrow assembly missing preactivation banner"
  unless hasSubstr text "not a product artifact" do
    emitFail "Escrow assembly missing product-boundary banner"
  pure ⟨resolved, text, frameBytes⟩

end ProofForgeV2.Targets.Solana.CpiV1
