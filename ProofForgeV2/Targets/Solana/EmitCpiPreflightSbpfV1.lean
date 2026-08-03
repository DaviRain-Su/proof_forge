/-
  ProofForgeV2.Targets.Solana.EmitCpiPreflightSbpfV1 — #118 concrete preflight SBPF.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Emits a private `SolanaCpiPreflightAssemblyV1` carrier (canonical SBPF text +
  frame accessor) from `ResolvedSolanaCpiPreflightIRV1` only. Every remaining
  concrete preflight op becomes real SBPF instructions — no policy/deferred
  comment emission. Shared ABIv1 walker enforces marker/odl/bool/rent/pointer
  with explicit wrap guards before every cursor addition.

  Non-goals (fail closed / absent by construction):
  * no CPI / invoke / sol_invoke_signed / PDA symbols
  * no OutputFile / product artifact mint
  * no business mutation after checks
  * frame budget ≤ 4096
  * no public mint from arbitrary `ValidatedSolanaCpiPlanV1`

  The optional probe `entrypoint` is a **test-preactivation** surface only:
  exact instruction-data length 8 (u64 LE handlerId), runs preflight checks,
  then exits success. It is not a product artifact.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-! ## Private assembly carrier -/

/-- Private preflight-only SBPF assembly. Not an OutputFile; not product.
    Retains the resolved authority carrier. -/
structure SolanaCpiPreflightAssemblyV1 where
  private mk ::
  resolved : ResolvedSolanaCpiPreflightIRV1
  text : String
  frameBytes : Nat

namespace SolanaCpiPreflightAssemblyV1

def textOf (a : SolanaCpiPreflightAssemblyV1) : String := a.text
def frameBytesOf (a : SolanaCpiPreflightAssemblyV1) : Nat := a.frameBytes
def resolvedOf (a : SolanaCpiPreflightAssemblyV1) : ResolvedSolanaCpiPreflightIRV1 :=
  a.resolved
def preflightIrOf (a : SolanaCpiPreflightAssemblyV1) : ValidatedSolanaCpiPreflightIRV1 :=
  ResolvedSolanaCpiPreflightIRV1.validatedOf a.resolved
/-- Explicit product-boundary flag: this carrier is never a product artifact. -/
def isProductArtifact (_ : SolanaCpiPreflightAssemblyV1) : Bool := false
/-- Explicit non-product / test-preactivation flag. -/
def isTestPreactivation (_ : SolanaCpiPreflightAssemblyV1) : Bool := true

end SolanaCpiPreflightAssemblyV1

/-! ## Frame / ABI constants (ported from #115 caller.s) -/

/-- Role table: 16 roles × 8 u64 = 1024 bytes at [r10-1024 .. r10). -/
def preflightRoleTableBytesV1 : Nat := 1024
def preflightRoleStrideV1 : Nat := 64
def preflightMaxRolesV1 : Nat := 16
/-- Stack slots below the role table (8-aligned). -/
def preflightSlotNumRolesV1 : Nat := 1032
def preflightSlotProgramIdV1 : Nat := 1040
def preflightSlotIxDataV1 : Nat := 1048
def preflightSlotHandlerIdV1 : Nat := 1056
def preflightSlotCursorV1 : Nat := 1064
/-- Total frame used by this emitter (role table + working slots). -/
def preflightFrameBytesV1 : Nat := 1088
def preflightMaxFrameBytesV1 : Nat := 4096
/-- Test-only probe: exact instruction data length = 8 (u64 LE handlerId). -/
def preflightProbeIxDataLenV1 : Nat := 8

private def emitFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def natHexLower (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def hexImm (value : Nat) : String :=
  "0x" ++ natHexLower value

private def asmLabel (name : String) : String :=
  String.ofList (name.toList.map fun c =>
    if c.isAlphanum || c == '_' then c else '_')

private def handlerLabel (h : CpiPreflightHandlerIRV1) : String :=
  s!"handler_{h.handlerId}_{asmLabel h.name}_preflight"

/-! ## Assembly buffer -/

private structure AsmBuf where
  text : String

private def emptyBuf : AsmBuf := ⟨""⟩

private def emit (b : AsmBuf) (line : String) : AsmBuf :=
  { text := b.text ++ line ++ "\n" }

private def emitBlank (b : AsmBuf) : AsmBuf :=
  emit b ""

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

/-! ## Shared header / equ / err -/

private def emitHeader (b0 : AsmBuf) (handlerCount : Nat) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b "; proof-forge solana cpi preflight SBPF (#118 concrete)"
    b := emit b "; TEST-PREACTIVATION ONLY — not a product artifact"
    b := emit b "; Direct-mapped Loader V3 ABIv1 walker + role table (16 x 64 = 1024B)"
    b := emit b "; Local handles only; no fixed account-zero slots; no CPI/invoke/PDA"
    b := emit b "; Wrap guards before every cursor addition; OOR fail closed"
    b := emit b s!"; Handlers: {handlerCount}; frameBytes={preflightFrameBytesV1} (<= {preflightMaxFrameBytesV1})"
    b := emit b s!"; Probe ix data length exact {preflightProbeIxDataLenV1} (handlerId u64 LE)"
    b := emitBlank b
    b := emit b s!".equ MAX_PERMITTED_DATA_INCREASE, {hexImm frozenLoaderV3AbiLayoutV1.maxPermittedDataIncrease}"
    b := emit b s!".equ FULL_PREFIX, {hexImm frozenLoaderV3AbiLayoutV1.fullPrefixBytes}"
    b := emit b s!".equ ROLE_BASE, {preflightRoleTableBytesV1}"
    b := emit b s!".equ ROLE_STRIDE, {preflightRoleStrideV1}"
    b := emit b ".equ ROLE_MARKER, 0"
    b := emit b ".equ ROLE_KEY, 8"
    b := emit b ".equ ROLE_OWNER, 16"
    b := emit b ".equ ROLE_LAMPORTS, 24"
    b := emit b ".equ ROLE_DATA, 32"
    b := emit b ".equ ROLE_DATA_LEN, 40"
    b := emit b ".equ ROLE_RENT, 48"
    b := emit b ".equ ROLE_FLAGS, 56"
    b := emit b s!".equ SLOT_NUM_ROLES, {preflightSlotNumRolesV1}"
    b := emit b s!".equ SLOT_PROGRAM_ID, {preflightSlotProgramIdV1}"
    b := emit b s!".equ SLOT_IX_DATA, {preflightSlotIxDataV1}"
    b := emit b s!".equ SLOT_HANDLER_ID, {preflightSlotHandlerIdV1}"
    b := emit b s!".equ SLOT_CURSOR, {preflightSlotCursorV1}"
    b := emit b s!".equ PROBE_IX_DATA_LEN, {preflightProbeIxDataLenV1}"
    b := emitBlank b
    pure b

private def emitErrShape (b0 : AsmBuf) : AsmBuf :=
  let b := emit b0 "err_shape:"
  let b := emit b "  lddw r0, 1"
  emit b "  exit"

/-- Emit role-slot address for local index into r2. Clobbers r3. -/
private def emitRoleSlotAddr (b0 : AsmBuf) (indexImm : Nat) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b "  mov64 r2, r10"
    b := emit b "  lddw r3, ROLE_BASE"
    b := emit b "  sub64 r2, r3"
    if indexImm != 0 then
      b := emit b s!"  lddw r3, {indexImm * preflightRoleStrideV1}"
      b := emit b "  add64 r2, r3"
    pure b

/-- Checked add: if `cursorReg > u64::MAX - amountImm` then err; else add.
    Clobbers only r0. The walker deliberately reserves r0 as scratch until a
    terminal success/error value is written, so live r1–r9 values (including
    alignment and zero-padding counters) survive every checked cursor add.
    `amountImm` must be ≤ 2^64-1; limit is precomputed at emit time. -/
private def emitWrapGuardAddImm
    (b0 : AsmBuf) (cursorReg : String) (amountImm : Nat) (errLab : String)
    (note : String) : AsmBuf :=
  Id.run do
    let mut b := b0
    b := emit b s!"  ; wrap-guard add {amountImm} ({note})"
    if amountImm == 0 then
      pure b
    else
      -- limit = u64::MAX - amountImm, computed at emit time; r0 is scratch.
      let limit := (2 ^ 64 - 1) - amountImm
      b := emit b s!"  lddw r0, {hexImm limit}"
      b := emit b s!"  jgt {cursorReg}, r0, {errLab}"
      -- Prefer lddw+add for large immediates; small values still use lddw for uniformity.
      b := emit b s!"  lddw r0, {hexImm amountImm}"
      b := emit b s!"  add64 {cursorReg}, r0"
      pure b

/-- Checked add of register amount into cursorReg. Clobbers only reserved r0;
    cursorReg and amountReg therefore remain valid even when amountReg is r3. -/
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

/-! ## Per-op emission (handler-local; every remaining op is real SBPF) -/

private def emitOp
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
      -- Shared walker already parsed this local; pin a real role-slot reload.
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; abiVirtualWalk local={localIndex} (walker-checked; pin reload)"
        b := emitRoleSlotAddr b localIndex
        b := emit b "  ldxdw r1, [r2 + ROLE_MARKER]"
        b := emit b "  jeq r1, 0, err_shape"
        pure b
  | .checkMarker localIndex expected =>
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkMarker local={localIndex} expected={expected}"
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
      -- Walker already matched pointer table; re-assert non-null marker_vm.
      pure <| Id.run do
        let mut b := b0
        b := emit b s!"  ; checkPointerTableEntry local={localIndex} (walker-checked; pin reload)"
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

private def emitHandlerSection
    (b0 : AsmBuf) (h : CpiPreflightHandlerIRV1) : CompileResult AsmBuf := do
  let lab := handlerLabel h
  let mut b := b0
  b := emitBlank b
  b := emit b s!"; ===== handler {h.handlerId} {h.name} localRoles={h.localRoleCount} ====="
  b := emit b s!"{lab}:"
  unless h.localRoleCount ≤ preflightMaxRolesV1 do
    emitFail s!"handler {h.handlerId} localRoleCount {h.localRoleCount} > {preflightMaxRolesV1}"
  for op in h.ops do
    b ← emitOp b op "err_shape"
  b := emit b "  ; preflight checks passed — no business mutation"
  b := emit b "  lddw r0, 0"
  b := emit b "  exit"
  pure b

/-! ## Entrypoint (test-preactivation) with wrap-guarded ABIv1 walker -/

private def emitProbeEntrypoint
    (b0 : AsmBuf) (handlers : Array CpiPreflightHandlerIRV1) : AsmBuf :=
  Id.run do
    let mut b := b0
    let fullPrefix := frozenLoaderV3AbiLayoutV1.fullPrefixBytes
    let growth := frozenLoaderV3AbiLayoutV1.maxPermittedDataIncrease
    b := emitBlank b
    b := emit b "; ----- test-preactivation entrypoint (NOT a product artifact) -----"
    b := emit b "; Instruction data: exact 8 bytes = u64 LE handlerId."
    b := emit b "; Multi-handler dispatch is structural on Plan handlerId density;"
    b := emit b "; full product ABI remains fail-closed outside this probe."
    b := emit b ".globl entrypoint"
    b := emit b "entrypoint:"
    b := emit b "  mov64 r6, r1"
    -- num_accounts
    b := emit b "  ldxdw r1, [r6 + 0]"
    b := emit b s!"  jgt r1, {preflightMaxRolesV1}, err_shape"
    b := emit b "  stxdw [r10 - SLOT_NUM_ROLES], r1"
    b := emit b "  mov64 r9, r1"
    b := emit b "  mov64 r8, r6"
    b := emitWrapGuardAddImm b "r8" 8 "err_shape" "input base → first marker"
    b := emit b "  lddw r7, 0"
    b := emit b "  jeq r9, 0, ep_parse_roles_done"
    b := emit b "ep_parse_role:"
    -- marker + original_data_len
    b := emit b "  ldxb r1, [r8 + 0]"
    b := emit b s!"  jne r1, {hexImm frozenLoaderV3AbiLayoutV1.marker}, err_shape"
    b := emit b s!"  ldxw r1, [r8 + {frozenLoaderV3AbiLayoutV1.originalDataLenOffset}]"
    b := emit b s!"  jne r1, {frozenLoaderV3AbiLayoutV1.originalDataLenEntryValue}, err_shape"
    -- role slot
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
    -- bool flags
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
    -- virtual cursor: marker + fullPrefix + data_len + growth + align + rent+8
    b := emit b "  mov64 r5, r8"
    b := emitWrapGuardAddImm b "r5" fullPrefix "err_shape" "cursor full prefix"
    b := emitWrapGuardAddReg b "r5" "r4" "err_shape" "cursor data_len"
    b := emitWrapGuardAddImm b "r5" growth "err_shape" "cursor growth reserve"
    -- alignment pad 0..7
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
    -- instruction data: exact length 8
    b := emit b "  ldxdw r1, [r8 + 0]"
    b := emit b "  jne r1, PROBE_IX_DATA_LEN, err_shape"
    b := emit b "  mov64 r2, r8"
    b := emitWrapGuardAddImm b "r2" 8 "err_shape" "ix data pointer"
    b := emit b "  stxdw [r10 - SLOT_IX_DATA], r2"
    b := emit b "  ldxdw r3, [r2 + 0]"
    b := emit b "  stxdw [r10 - SLOT_HANDLER_ID], r3"
    b := emit b "  mov64 r5, r2"
    b := emitWrapGuardAddImm b "r5" preflightProbeIxDataLenV1 "err_shape" "program id after ix data"
    b := emit b "  stxdw [r10 - SLOT_PROGRAM_ID], r5"
    b := emitWrapGuardAddImm b "r5" 32 "err_shape" "program id +32"
    -- zero pad to 8
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
    -- dispatch by handlerId u64
    b := emit b "  ldxdw r1, [r10 - SLOT_HANDLER_ID]"
    for h in handlers do
      b := emit b s!"  jeq r1, {h.handlerId}, {handlerLabel h}"
    b := emit b "  ja err_shape"
    pure b

/-! ## Public emit entry (resolved authority only) -/

private def finalizeAssembly
    (resolved : ResolvedSolanaCpiPreflightIRV1)
    (handlers : Array CpiPreflightHandlerIRV1)
    (b0 : AsmBuf) (withEntrypoint : Bool) :
    CompileResult SolanaCpiPreflightAssemblyV1 := do
  unless preflightFrameBytesV1 ≤ preflightMaxFrameBytesV1 do
    emitFail "preflight frame budget exceeds 4096"
  let cand := ResolvedSolanaCpiPreflightIRV1.candidateOf resolved
  unless cand.maxOuterRoles == preflightMaxRolesV1 do
    emitFail s!"maxOuterRoles must be {preflightMaxRolesV1}"
  for h in handlers do
    unless h.localRoleCount ≤ preflightMaxRolesV1 do
      emitFail s!"handler {h.handlerId} localRoleCount {h.localRoleCount} exceeds {preflightMaxRolesV1}"
  let mut b := b0
  b := emitHeader b handlers.size
  if withEntrypoint then
    b := emitProbeEntrypoint b handlers
  else
    b := emit b "; Per-handler validated sections only (no multi-handler product ABI claim)."
    b := emit b "; Callers of a section must have already populated the role table via"
    b := emit b "; the shared ABIv1 walker contract documented in CpiPreflightIRV1."
  for h in handlers do
    b ← emitHandlerSection b h
  b := emitBlank b
  b := emitErrShape b
  let text := b.text
  if hasSubstr text "ACC0_" then
    emitFail "preflight assembly must not contain ACC0 fixed slots"
  if hasSubstr text "sol_invoke" || hasSubstr text "invoke_signed" then
    emitFail "preflight assembly must not contain invoke/CPI symbols"
  -- No comment-only policy markers from the old DTO emitter surface.
  if hasSubstr text "deferred-before-site" then
    emitFail "preflight assembly must not contain deferred-before-site policy comments"
  if hasSubstr text "owner any local=" then
    emitFail "preflight assembly must not contain comment-only owner-any markers"
  if hasSubstr text "provisioning " then
    emitFail "preflight assembly must not contain comment-only provisioning markers"
  if hasSubstr text "initialization " && hasSubstr text "; initialization " then
    emitFail "preflight assembly must not contain comment-only initialization markers"
  pure ⟨resolved, text, preflightFrameBytesV1⟩

/-- Emit private preflight SBPF assembly from a **resolved** preflight IR.
    Accepts only `ResolvedSolanaCpiPreflightIRV1` (Semantic-derived authority).
    Returns `SolanaCpiPreflightAssemblyV1` (not OutputFile). -/
def emitCpiPreflightSbpfV1
    (resolved : ResolvedSolanaCpiPreflightIRV1) :
    CompileResult SolanaCpiPreflightAssemblyV1 :=
  finalizeAssembly resolved
    (ResolvedSolanaCpiPreflightIRV1.candidateOf resolved).handlers emptyBuf true

/-- Emit validated per-handler assembly sections only (no shared entrypoint).
    Still requires the resolved authority carrier. -/
def emitCpiPreflightHandlerSectionsV1
    (resolved : ResolvedSolanaCpiPreflightIRV1) :
    CompileResult SolanaCpiPreflightAssemblyV1 :=
  finalizeAssembly resolved
    (ResolvedSolanaCpiPreflightIRV1.candidateOf resolved).handlers emptyBuf false

end ProofForgeV2.Targets.Solana.CpiV1
