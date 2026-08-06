import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Core.TargetIdentityV1

/-!
# Solana EmitSbpfAsmV1 — typed IR → SBPF assembly (.s) text (S1b)

Full default-dialect Operation surface emitter. Emits SBPF assembly consumable
by the pinned `sbpf` assembler; does **not** invoke external tools or produce
ELF. No blueshift extension mnemonics (`hor64`/`lmul64`/`uhmul64`/`udiv64`/
`urem64`/`shmul64`/`srem64`).

Authority: typed `IR` / `Operation` / `Check` from `EmitIRV1` (not `.sbpf-plan`
text). Product `buildFromCapability` is profile-exhaustive (#125):
* `solana-sbpf-plan-v1` → legacy `.sbpf-plan` + IDL
* `solana-sbpf-elf-v1` → legacy plan/IDL + `{name}.s`
* `solana-sbpf-cpi-elf-v1` → product base files via `productBaseFilesFromCapabilityV1`
  (never legacy Plan/IR/emitter)
* unknown profile → fail closed
Legacy ExternalCall/Schedule ops remain unreachable in this emitter.

## Input account layout (single non-dup state account)

Serialized runtime layout (see sbpf runtime `serialize.rs`):

```
NUM_ACCOUNTS        @ 0x00
ACC0_HEADER         @ 0x08   (dup=0xff, signer, writable, executable, pad)
ACC0_KEY            @ 0x10   (32B)
ACC0_OWNER          @ 0x30   (32B)
ACC0_LAMPORTS       @ 0x50
ACC0_DATA_LEN       @ 0x58
ACC0_DATA           @ 0x60   (exactDataLen + 10240 pad + 8-align)
ACC0_RENT_EPOCH     @ data_end + align
INSTRUCTION_DATA_LEN
INSTRUCTION_DATA
PROGRAM_ID          @ INSTRUCTION_DATA + ix_len  (dynamic)
```

`.equ` offsets for the fixed prefix and the post-account region are derived
from `stateAccount.exactDataLen`; `PROGRAM_ID` is computed at runtime.

## Registers

* `r1` on entry = input buffer base → saved to `r6` for the whole program
* `r10` = frame pointer; absolute temp `t` lives at `[r10 - 8*(t+1)]`
* `r0` = exit code / syscall result
* `r1`–`r5`, `r7`–`r9` = scratch

Temps inside an inlined pureFn are offset by `tempBase`. A threaded `cursor`
allocates return-data slots, event buffers, and callee frames.

## S1b support surface

Checks (handler order): num_accounts==1, account[0] non-dup `0xff`,
instruction_data_len, owner==current_program, data_len, signer, writable,
headerEquals (account[0] only). Entrypoint re-emits the account-list shape
pair before any fixed `INSTRUCTION_*` / `ACC0_*` load so 0/2-account and
duplicate encodings fail closed with program_error 1.

Ops: literal, loadParam, loadState, checkedAdd/Sub/Mul/Div/Mod,
bitAnd/Or/Xor/Not, checkedShl/Shr, boolNot/And/Or, zeroState, storeState,
storeStateMulti, setHeader, setReturnData (u64 LE / bool / multi-leaf B-RET-ABI),
compare, assert, returnNone, revertError, ifRegion, switchRegion, forRegion,
callFn (inline expand), emitEvent (`sol_log_data`), externalCall/schedule
(real CPI via `sol_invoke_signed_c`, empty AccountMeta; result-bearing call
reads `sol_get_return_data`).

## Fail closed

* non-zero account indices
* callFn index OOB / inline depth > `ir.fns.size`
* frame budget: `(cursorFinal+1)*8 > maxSbpfStackBytesV1` (4096)
* IR hard-exit `returnNone` inside pureFn is a no-op when inlined (value already
  copied by setReturnData*); handlers still exit 0
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Fixed Solana BPF account serialization constants. -/
def maxPermittedDataIncreaseV1 : Nat := 10240
def accountHeaderOffsetV1 : Nat := 0x08
def accountKeyOffsetV1 : Nat := 0x10
def accountOwnerOffsetV1 : Nat := 0x30
def accountLamportsOffsetV1 : Nat := 0x50
def accountDataLenOffsetV1 : Nat := 0x58
def accountDataOffsetV1 : Nat := 0x60

/-- Solana default stack size (bytes). Frame budget fail-closed gate. -/
def maxSbpfStackBytesV1 : Nat := 4096

/-- Derived input-buffer offsets for a single non-dup account of `exactDataLen`. -/
structure InputLayoutV1 where
  exactDataLen : Nat
  rentEpoch : Nat
  instructionDataLen : Nat
  instructionData : Nat
  deriving BEq, Repr

/-- Compute layout offsets from the plan's `exactDataLen` (no hard-coded 16). -/
def computeInputLayoutV1 (exactDataLen : Nat) : InputLayoutV1 :=
  let dataEnd := accountDataOffsetV1 + exactDataLen + maxPermittedDataIncreaseV1
  let align := (8 - (dataEnd % 8)) % 8
  let rentEpoch := dataEnd + align
  let instructionDataLen := rentEpoch + 8
  let instructionData := instructionDataLen + 8
  {
    exactDataLen
    rentEpoch
    instructionDataLen
    instructionData
  }

private def asmError (message : String) : CompileResult α :=
  .error <| .planInvariant .solana message

private def natHexLower (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def hexImm (value : Nat) : String :=
  "0x" ++ natHexLower value

/-- Stack offset (negative of frame) for absolute IR temp `t`. -/
private def tempStackOff (t : Nat) : Nat := 8 * (t + 1)

private def hexDigitValue (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

/-- Parse a 16-char lowercase hex discriminator into the LE `u64` that
    `ldxdw` loads from the first 8 instruction-data bytes. -/
def discriminatorToLeU64V1 (hex : String) : CompileResult UInt64 := do
  unless hex.length == 16 do
    return ← asmError s!"S1b discriminator must be 16 hex chars, got length {hex.length}"
  let chars := hex.toList
  let mut value : Nat := 0
  for i in [:8] do
    let some hi := hexDigitValue chars[2 * i]! |
      return ← asmError s!"S1b discriminator has non-hex at index {2 * i}"
    let some lo := hexDigitValue chars[2 * i + 1]! |
      return ← asmError s!"S1b discriminator has non-hex at index {2 * i + 1}"
    let byte := hi * 16 + lo
    value := value + byte * (Nat.pow 2 (8 * i))
  pure (UInt64.ofNat value)

/-- Sanitize a handler/fn name into an SBPF label identifier. -/
private def asmLabel (name : String) : String :=
  String.ofList (name.toList.map fun c =>
    if c.isAlphanum || c == '_' then c else '_')

/-- Assembly buffer with label sequence counter and stack cursor. -/
private structure AsmBuf where
  text : String
  seq : Nat
  /-- Next free absolute temp index (handler temps, ret slots, event buf, callee frames). -/
  cursor : Nat

private def emptyBuf (cursor : Nat := 0) : AsmBuf := ⟨"", 0, cursor⟩

private def emit (b : AsmBuf) (line : String) : AsmBuf :=
  { b with text := b.text ++ line ++ "\n" }

private def emitBlank (b : AsmBuf) : AsmBuf :=
  { b with text := b.text ++ "\n" }

private def fresh (b : AsmBuf) (labelPrefix : String) : AsmBuf × String :=
  let lab := s!"{labelPrefix}_{b.seq}"
  ({ b with seq := b.seq + 1 }, lab)

/-- Load absolute temp `absT` into register `rd`. -/
private def loadTempAbs (b : AsmBuf) (rd : String) (absT : Nat) : AsmBuf :=
  emit b s!"  ldxdw {rd}, [r10 - {tempStackOff absT}]"

/-- Store register `rs` into absolute temp `absT`. -/
private def storeTempAbs (b : AsmBuf) (absT : Nat) (rs : String) : AsmBuf :=
  emit b s!"  stxdw [r10 - {tempStackOff absT}], {rs}"

/-- Load relative temp `t` (offset by `tempBase`) into `rd`. -/
private def loadTemp (b : AsmBuf) (rd : String) (tempBase t : Nat) : AsmBuf :=
  loadTempAbs b rd (tempBase + t)

/-- Store `rs` into relative temp `t` (offset by `tempBase`). -/
private def storeTemp (b : AsmBuf) (tempBase t : Nat) (rs : String) : AsmBuf :=
  storeTempAbs b (tempBase + t) rs

private def emitEqu (b : AsmBuf) (name : String) (value : Nat) : AsmBuf :=
  emit b s!".equ {name}, {hexImm value}"

private def renderLayoutEqu (layout : InputLayoutV1) : String :=
  let b0 := emptyBuf
  let b0 := emit b0 "; PROOF-FORGE-SBPF-ASM v1 (S1b full Operation surface)"
  let b0 := emit b0 "; Generated from typed Solana IR — plan-owned offsets"
  let b0 := emitBlank b0
  let b0 := emitEqu b0 "NUM_ACCOUNTS" 0x00
  let b0 := emitEqu b0 "ACC0_HEADER" accountHeaderOffsetV1
  let b0 := emitEqu b0 "ACC0_KEY" accountKeyOffsetV1
  let b0 := emitEqu b0 "ACC0_OWNER" accountOwnerOffsetV1
  let b0 := emitEqu b0 "ACC0_LAMPORTS" accountLamportsOffsetV1
  let b0 := emitEqu b0 "ACC0_DATA_LEN" accountDataLenOffsetV1
  let b0 := emitEqu b0 "ACC0_DATA" accountDataOffsetV1
  let b0 := emitEqu b0 "MAX_PERMITTED_DATA_INCREASE" maxPermittedDataIncreaseV1
  let b0 := emitEqu b0 "EXACT_DATA_LEN" layout.exactDataLen
  let b0 := emitEqu b0 "ACC0_RENT_EPOCH" layout.rentEpoch
  let b0 := emitEqu b0 "INSTRUCTION_DATA_LEN" layout.instructionDataLen
  let b0 := emitEqu b0 "INSTRUCTION_DATA" layout.instructionData
  let b0 := emitBlank b0
  b0.text

/-- Jump to `lab` after loading `code` into r0 and exiting (used as a target). -/
private def emitErrorExit (b : AsmBuf) (lab : String) (code : Nat) : AsmBuf :=
  let b := emit b s!"{lab}:"
  let b := emit b s!"  lddw r0, {hexImm code}"
  emit b "  exit"

/-- Emit a program_error exit sequence at the current PC (no label). -/
private def emitProgramErrorInline (b : AsmBuf) (code : Nat) : AsmBuf :=
  let b := emit b s!"  lddw r0, {hexImm code}"
  emit b "  exit"

/-- LE u64 limb count for multiword body widths (T9e). -/
private def limbCountOfBitWidth (bitWidth : Nat) : Nat :=
  if bitWidth ≤ 64 then 1 else bitWidth / 64

/-- Result limb span for a destination-producing op. -/
private def opResultLimbCount : Operation → Nat
  | .narrowLoadParam bitWidth .. | .narrowLoadState bitWidth ..
  | .narrowCheckedAdd bitWidth .. | .narrowCheckedSub bitWidth ..
  | .narrowCheckedMul bitWidth .. | .narrowCheckedDiv bitWidth ..
  | .narrowCheckedMod bitWidth ..
  | .narrowBitAnd bitWidth .. | .narrowBitOr bitWidth ..
  | .narrowBitXor bitWidth .. | .narrowBitNot bitWidth ..
  | .narrowCheckedShl bitWidth .. | .narrowCheckedShr bitWidth .. =>
      limbCountOfBitWidth bitWidth
  | .literal .. | .loadParam .. | .loadState ..
  | .checkedAdd .. | .checkedSub .. | .checkedMul .. | .checkedDiv .. | .checkedMod ..
  | .signedCheckedAdd .. | .signedCheckedSub .. | .signedCheckedMul ..
  | .signedCheckedDiv .. | .signedCheckedMod .. | .checkedNeg ..
  | .signedCompare .. | .checkedSar ..
  | .bitAnd .. | .bitOr .. | .bitXor .. | .checkedShl .. | .checkedShr ..
  | .bitNot .. | .boolNot .. | .boolAnd .. | .boolOr ..
  | .compare .. | .wideCompare .. | .callFn ..
  | .externalCall _ _ _ (some _) => 1
  | _ => 0

/-- Destination temp of a value-producing op, if any. -/
private def opDestination? : Operation → Option Nat
  | .literal destination .. | .loadParam destination .. |
      .narrowLoadParam _ destination .. |
      .loadState destination .. | .narrowLoadState _ destination .. |
      .checkedAdd destination .. |
      .signedCheckedAdd destination .. | .signedCheckedSub destination .. |
      .signedCheckedMul destination .. | .signedCheckedDiv destination .. |
      .signedCheckedMod destination .. | .checkedNeg destination .. |
      .signedCompare destination .. | .checkedSar destination .. |
      .checkedSub destination .. | .checkedMul destination .. |
      .checkedDiv destination .. | .checkedMod destination .. |
      .bitAnd destination .. | .bitOr destination .. | .bitXor destination .. |
      .checkedShl destination .. | .checkedShr destination .. |
      .bitNot destination _ | .boolNot destination _ |
      .boolAnd destination .. | .boolOr destination .. |
      .narrowCheckedAdd _ destination .. | .narrowCheckedSub _ destination .. |
      .narrowCheckedMul _ destination .. | .narrowCheckedDiv _ destination .. |
      .narrowCheckedMod _ destination .. |
      .narrowBitAnd _ destination .. | .narrowBitOr _ destination .. |
      .narrowBitXor _ destination .. | .narrowBitNot _ destination _ |
      .narrowCheckedShl _ destination .. | .narrowCheckedShr _ destination .. |
      .compare destination .. | .wideCompare _ destination .. |
      .callFn _ destination _ => some destination
  | .externalCall _ _ _ (some destination) => some destination
  | _ => none

/-- Max destination+1 over an op sequence (canonical temp count). -/
private partial def tempCountOf (ops : Array Operation) : Nat :=
  ops.foldl (init := 0) fun acc op =>
    let acc := match opDestination? op with
      | some d =>
          let n := opResultLimbCount op
          Nat.max acc (d + (if n == 0 then 1 else n))
      | none => acc
    match op with
    | .ifRegion _ thenOps elseOps =>
        Nat.max acc (Nat.max (tempCountOf thenOps) (tempCountOf elseOps))
    | .switchRegion _ cases defaultOps =>
        let caseMax := cases.foldl (init := 0) fun m (_, body) =>
          Nat.max m (tempCountOf body)
        Nat.max acc (Nat.max caseMax (tempCountOf defaultOps))
    | .forRegion _ _ _ _ condOps _ bodyOps boundOps _ updateOps _ =>
        let m1 := Nat.max (tempCountOf condOps) (tempCountOf bodyOps)
        let m2 := Nat.max (tempCountOf boundOps) (tempCountOf updateOps)
        Nat.max acc (Nat.max m1 m2)
    | _ => acc

/-- Emit account-list shape pair (num_accounts==1, account[0] dup==0xff).
    Offsets `NUM_ACCOUNTS` / `ACC0_HEADER+0` are layout-prefix constants and do
    not depend on `exactDataLen`. Must run before any fixed post-account load. -/
private def emitAccountListShapeChecks (b0 : AsmBuf) (errLab : String) : AsmBuf :=
  let b := emit b0 "  ; check num_accounts == 1"
  let b := emit b "  ldxdw r1, [r6 + NUM_ACCOUNTS]"
  let b := emit b s!"  jne r1, 1, {errLab}"
  let b := emit b "  ; check account[0].dup_marker == 0xff"
  let b := emit b "  ldxb r1, [r6 + ACC0_HEADER + 0]"
  let b := emit b s!"  jne r1, 0xff, {errLab}"
  b

/-- Emit check instructions; on failure jump to `errLab` (must lddw/exit). -/
private def emitCheck (b : AsmBuf) (check : Check) (errLab : String) :
    CompileResult AsmBuf := do
  match check with
  | .numAccounts count =>
      unless count == 1 do
        return ← asmError "S1b numAccounts check supports only count=1"
      let b := emit b "  ; check num_accounts == 1"
      let b := emit b "  ldxdw r1, [r6 + NUM_ACCOUNTS]"
      let b := emit b s!"  jne r1, 1, {errLab}"
      pure b
  | .accountNonDuplicate accountIndex =>
      unless accountIndex == 0 do
        return ← asmError "S1b non-duplicate check supports only account[0]"
      let b := emit b "  ; check account[0].dup_marker == 0xff"
      let b := emit b "  ldxb r1, [r6 + ACC0_HEADER + 0]"
      let b := emit b s!"  jne r1, 0xff, {errLab}"
      pure b
  | .instructionDataLen bytes =>
      let b := emit b s!"  ; check instruction_data_len == {bytes}"
      let b := emit b "  ldxdw r1, [r6 + INSTRUCTION_DATA_LEN]"
      let b := emit b s!"  jne r1, {bytes}, {errLab}"
      pure b
  | .ownerCurrentProgram accountIndex =>
      unless accountIndex == 0 do
        return ← asmError "S1b owner check supports only account[0]"
      let b := emit b "  ; check account[0].owner == current_program"
      let b := emit b "  ldxdw r1, [r6 + INSTRUCTION_DATA_LEN]"
      let b := emit b "  mov64 r2, r6"
      let b := emit b "  add64 r2, INSTRUCTION_DATA"
      let b := emit b "  add64 r2, r1"
      let b := emit b "  ldxdw r1, [r6 + ACC0_OWNER]"
      let b := emit b "  ldxdw r3, [r2 + 0]"
      let b := emit b s!"  jne r1, r3, {errLab}"
      let b := emit b "  ldxdw r1, [r6 + ACC0_OWNER + 8]"
      let b := emit b "  ldxdw r3, [r2 + 8]"
      let b := emit b s!"  jne r1, r3, {errLab}"
      let b := emit b "  ldxdw r1, [r6 + ACC0_OWNER + 16]"
      let b := emit b "  ldxdw r3, [r2 + 16]"
      let b := emit b s!"  jne r1, r3, {errLab}"
      let b := emit b "  ldxdw r1, [r6 + ACC0_OWNER + 24]"
      let b := emit b "  ldxdw r3, [r2 + 24]"
      let b := emit b s!"  jne r1, r3, {errLab}"
      pure b
  | .accountDataLen accountIndex bytes =>
      unless accountIndex == 0 do
        return ← asmError "S1b data_len check supports only account[0]"
      let b := emit b s!"  ; check account[0].data_len == {bytes}"
      let b := emit b "  ldxdw r1, [r6 + ACC0_DATA_LEN]"
      let b := emit b s!"  jne r1, {bytes}, {errLab}"
      pure b
  | .signer accountIndex =>
      unless accountIndex == 0 do
        return ← asmError "S1b signer check supports only account[0]"
      let b := emit b "  ; check account[0].is_signer"
      let b := emit b "  ldxb r1, [r6 + ACC0_HEADER + 1]"
      let b := emit b s!"  jeq r1, 0, {errLab}"
      pure b
  | .writable accountIndex =>
      unless accountIndex == 0 do
        return ← asmError "S1b writable check supports only account[0]"
      let b := emit b "  ; check account[0].is_writable"
      let b := emit b "  ldxb r1, [r6 + ACC0_HEADER + 2]"
      let b := emit b s!"  jeq r1, 0, {errLab}"
      pure b
  | .headerEquals accountIndex byteOffset value =>
      unless accountIndex == 0 do
        return ← asmError "S1b headerEquals supports only account[0]"
      let b := emit b s!"  ; check header u64 @ {byteOffset} == 0x{natHexLower value.toNat}"
      let b := emit b s!"  ldxdw r1, [r6 + ACC0_DATA + {byteOffset}]"
      let b := emit b s!"  lddw r2, {hexImm value.toNat}"
      let b := emit b s!"  jne r1, r2, {errLab}"
      pure b

/-- Emit one comparison that writes 0/1 into dest temp. -/
private def emitCompare (b : AsmBuf) (tempBase dest lhs rhs : Nat) (op : ComparisonOp) :
    AsmBuf := Id.run do
  let (b, trueLab) := fresh b "cmp_true"
  let (b, doneLab) := fresh b "cmp_done"
  let b := loadTemp b "r1" tempBase lhs
  let b := loadTemp b "r2" tempBase rhs
  let b := emit b "  mov64 r3, 0"
  let b := match op with
    | .eq => emit b s!"  jeq r1, r2, {trueLab}"
    | .ne => emit b s!"  jne r1, r2, {trueLab}"
    | .lt => emit b s!"  jlt r1, r2, {trueLab}"
    | .le => emit b s!"  jle r1, r2, {trueLab}"
    | .gt => emit b s!"  jgt r1, r2, {trueLab}"
    | .ge => emit b s!"  jge r1, r2, {trueLab}"
  let b := emit b s!"  ja {doneLab}"
  let b := emit b s!"{trueLab}:"
  let b := emit b "  mov64 r3, 1"
  let b := emit b s!"{doneLab}:"
  storeTemp b tempBase dest "r3"

/-- Emit checked_add: dest = lhs + rhs or program_error errorCode. -/
private def emitCheckedAdd (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_add"
    let (b, okLab) := fresh b "ok_add"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b "  lddw r3, 0xffffffffffffffff"
    let b := emit b "  sub64 r3, r2"
    let b := emit b s!"  jgt r1, r3, {errLab}"
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  add64 r4, r2"
    let b := storeTemp b tempBase dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Emit checked_sub: dest = lhs - rhs or program_error errorCode. -/
private def emitCheckedSub (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_sub"
    let (b, okLab) := fresh b "ok_sub"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jlt r1, r2, {errLab}"
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  sub64 r4, r2"
    let b := storeTemp b tempBase dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Emit checked_mul with zero-rhs fast path and MAX/rhs overflow guard. -/
private def emitCheckedMul (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, zeroLab) := fresh b "mul_zero"
    let (b, errLab) := fresh b "err_mul"
    let (b, okLab) := fresh b "ok_mul"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jeq r2, 0, {zeroLab}"
    let b := emit b "  lddw r3, 0xffffffffffffffff"
    let b := emit b "  div64 r3, r2"
    let b := emit b s!"  jgt r1, r3, {errLab}"
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  mul64 r4, r2"
    let b := storeTemp b tempBase dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emit b s!"{zeroLab}:"
    let b := emit b "  lddw r4, 0"
    let b := storeTemp b tempBase dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Emit checked_div: dest = lhs / rhs or program_error on rhs==0. -/
private def emitCheckedDiv (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_div"
    let (b, okLab) := fresh b "ok_div"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jeq r2, 0, {errLab}"
    let b := emit b "  div64 r1, r2"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Emit checked_mod: dest = lhs % rhs or program_error on rhs==0. -/
private def emitCheckedMod (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_mod"
    let (b, okLab) := fresh b "ok_mod"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jeq r2, 0, {errLab}"
    let b := emit b "  mod64 r1, r2"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- intMin as i64 bit pattern: 0x8000_0000_0000_0000. -/
private def intMinI64Hex : String := "0x8000000000000000"
/-- -1 as i64 bit pattern. -/
private def negOneI64Hex : String := "0xffffffffffffffff"

/-- Checked i64 add: overflow when sign(a)==sign(b) and sign(r)!=sign(a). -/
private def emitSignedCheckedAdd (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_sadd"
    let (b, okLab) := fresh b "ok_sadd"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b "  mov64 r3, r1"
    let b := emit b "  add64 r3, r2"
    -- overflow if ((a ^ r) & (b ^ r)) has sign bit set
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  xor64 r4, r3"
    let b := emit b "  mov64 r5, r2"
    let b := emit b "  xor64 r5, r3"
    let b := emit b "  and64 r4, r5"
    let b := emit b s!"  jslt r4, 0, {errLab}"
    let b := storeTemp b tempBase dest "r3"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Checked i64 sub: a - b overflows when signs of a and b differ and sign(r)!=sign(a). -/
private def emitSignedCheckedSub (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_ssub"
    let (b, okLab) := fresh b "ok_ssub"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b "  mov64 r3, r1"
    let b := emit b "  sub64 r3, r2"
    -- overflow if ((a ^ b) & (a ^ r)) has sign bit (a and b different signs)
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  xor64 r4, r2"
    let b := emit b "  mov64 r5, r1"
    let b := emit b "  xor64 r5, r3"
    let b := emit b "  and64 r4, r5"
    let b := emit b s!"  jslt r4, 0, {errLab}"
    let b := storeTemp b tempBase dest "r3"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Checked i64 mul: multiply then reverse sdiv when a ≠ 0 and a ≠ -1. -/
private def emitSignedCheckedMul (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_smul"
    let (b, okLab) := fresh b "ok_smul"
    let (b, skipLab) := fresh b "smul_skip"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b "  mov64 r3, r1"
    let b := emit b "  mul64 r3, r2"
    let b := emit b s!"  jeq r1, 0, {skipLab}"
    let b := emit b s!"  lddw r4, {negOneI64Hex}"
    let b := emit b s!"  jeq r1, r4, {skipLab}"
    let b := emit b "  mov64 r5, r3"
    let b := emit b "  sdiv64 r5, r1"
    let b := emit b s!"  jne r5, r2, {errLab}"
    let b := emit b s!"{skipLab}:"
    let b := storeTemp b tempBase dest "r3"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Checked i64 div: zero and intMin divided by -1 overflow. -/
private def emitSignedCheckedDiv (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_sdiv"
    let (b, okLab) := fresh b "ok_sdiv"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jeq r2, 0, {errLab}"
    let b := emit b s!"  lddw r3, {intMinI64Hex}"
    let b := emit b s!"  jne r1, r3, {okLab}_do"
    let b := emit b s!"  lddw r4, {negOneI64Hex}"
    let b := emit b s!"  jeq r2, r4, {errLab}"
    let b := emit b s!"{okLab}_do:"
    let b := emit b "  sdiv64 r1, r2"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Checked i64 rem: zero divisor only (intMin rem -1 is fine). -/
private def emitSignedCheckedMod (b : AsmBuf) (tempBase dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_smod"
    let (b, okLab) := fresh b "ok_smod"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jeq r2, 0, {errLab}"
    let b := emit b "  smod64 r1, r2"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Checked i64 neg: intMin overflows. -/
private def emitCheckedNeg (b : AsmBuf) (tempBase dest source errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_neg"
    let (b, okLab) := fresh b "ok_neg"
    let b := loadTemp b "r1" tempBase source
    let b := emit b s!"  lddw r2, {intMinI64Hex}"
    let b := emit b s!"  jeq r1, r2, {errLab}"
    let b := emit b "  neg64 r1"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Signed compare → 0/1 in dest using jsgt/jslt family. -/
private def emitSignedCompare (b : AsmBuf) (tempBase dest lhs rhs : Nat)
    (op : ComparisonOp) : AsmBuf :=
  Id.run do
    let (b, trueLab) := fresh b "scmp_t"
    let (b, doneLab) := fresh b "scmp_d"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := match op with
      | .eq => emit b s!"  jeq r1, r2, {trueLab}"
      | .ne => emit b s!"  jne r1, r2, {trueLab}"
      | .lt => emit b s!"  jslt r1, r2, {trueLab}"
      | .le => emit b s!"  jsle r1, r2, {trueLab}"
      | .gt => emit b s!"  jsgt r1, r2, {trueLab}"
      | .ge => emit b s!"  jsge r1, r2, {trueLab}"
    let b := emit b "  mov64 r3, 0"
    let b := emit b s!"  ja {doneLab}"
    let b := emit b s!"{trueLab}:"
    let b := emit b "  mov64 r3, 1"
    let b := emit b s!"{doneLab}:"
    storeTemp b tempBase dest "r3"

/-- Arithmetic right shift with count ≥ 64 → error. -/
private def emitCheckedSar (b : AsmBuf) (tempBase dest lhs rhs shiftError : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_sar"
    let (b, okLab) := fresh b "ok_sar"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jge r2, 64, {errLab}"
    let b := emit b "  arsh64 r1, r2"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab shiftError
    emit b s!"{okLab}:"

/-- Emit checked_shl: count≥64 → shiftErr; lost high bits → overflowErr. -/
private def emitCheckedShl (b : AsmBuf) (tempBase dest lhs rhs shiftErr overflowErr : Nat) :
    AsmBuf :=
  Id.run do
    let (b, errShift) := fresh b "err_shl_count"
    let (b, errOverflow) := fresh b "err_shl_ovf"
    let (b, okLab) := fresh b "ok_shl"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jge r2, 64, {errShift}"
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  lsh64 r1, r2"
    let b := emit b "  mov64 r3, r1"
    let b := emit b "  rsh64 r3, r2"
    let b := emit b s!"  jne r3, r4, {errOverflow}"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errShift shiftErr
    let b := emitErrorExit b errOverflow overflowErr
    emit b s!"{okLab}:"

/-- Emit checked_shr: count≥64 → shiftErr. -/
private def emitCheckedShr (b : AsmBuf) (tempBase dest lhs rhs shiftErr : Nat) : AsmBuf :=
  Id.run do
    let (b, errShift) := fresh b "err_shr"
    let (b, okLab) := fresh b "ok_shr"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jge r2, 64, {errShift}"
    let b := emit b "  rsh64 r1, r2"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errShift shiftErr
    emit b s!"{okLab}:"

/-- Width mask for narrow body UInt (compile-time immediate). -/
private def narrowUintMaskImm (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "0xff"
  | 16 => "0xffff"
  | 32 => "0xffffffff"
  | _ => "0xffffffffffffffff"

/-- SBPF memory load mnemonic for ABI width (`ldxb`/`ldxh`/`ldxw`). -/
private def narrowLoadMnemonic (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "ldxb"
  | 16 => "ldxh"
  | 32 => "ldxw"
  | _ => "ldxdw"

/-- SBPF memory store mnemonic for ABI width (`stxb`/`stxh`/`stxw`). -/
private def narrowStoreMnemonic (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "stxb"
  | 16 => "stxh"
  | 32 => "stxw"
  | _ => "stxdw"

/-- SBPF immediate store mnemonic for ABI width (`stb`/`sth`/`stw`). -/
private def narrowImmStoreMnemonic (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "stb"
  | 16 => "sth"
  | 32 => "stw"
  | _ => "stdw"

/-- Multiword (T9e) checked add: LE limbs at base temps; final carry → overflow. -/
private def emitMultiwordCheckedAdd (b : AsmBuf) (tempBase dest lhs rhs errorCode nLimbs : Nat) :
    AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_mwadd"
    let (b, okLab) := fresh b "ok_mwadd"
    let b := emit b "  mov64 r5, 0"
    let mut b := b
    for i in [:nLimbs] do
      let (b1, cset) := fresh b "mwadd_cset"
      let (b2, cdone) := fresh b1 "mwadd_cdone"
      b := b2
      b := loadTemp b "r1" tempBase (lhs + i)
      b := loadTemp b "r2" tempBase (rhs + i)
      b := emit b "  mov64 r3, r1"
      b := emit b "  add64 r1, r2"
      b := emit b "  add64 r1, r5"
      -- carry out: (sum < a) || (cin == 1 && sum == a)
      b := emit b "  mov64 r4, 0"
      b := emit b s!"  jlt r1, r3, {cset}"
      b := emit b s!"  jeq r5, 0, {cdone}"
      b := emit b s!"  jeq r1, r3, {cset}"
      b := emit b s!"  ja {cdone}"
      b := emit b s!"{cset}:"
      b := emit b "  mov64 r4, 1"
      b := emit b s!"{cdone}:"
      b := storeTemp b tempBase (dest + i) "r1"
      b := emit b "  mov64 r5, r4"
    b := emit b s!"  jne r5, 0, {errLab}"
    b := emit b s!"  ja {okLab}"
    b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Multiword checked sub: final borrow → overflow. -/
private def emitMultiwordCheckedSub (b : AsmBuf) (tempBase dest lhs rhs errorCode nLimbs : Nat) :
    AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_mwsub"
    let (b, okLab) := fresh b "ok_mwsub"
    let b := emit b "  mov64 r5, 0"
    let mut b := b
    for i in [:nLimbs] do
      let (b1, bset) := fresh b "mwsub_bset"
      let (b2, bdone) := fresh b1 "mwsub_bdone"
      b := b2
      b := loadTemp b "r1" tempBase (lhs + i)
      b := loadTemp b "r2" tempBase (rhs + i)
      b := emit b "  mov64 r3, r1"
      b := emit b "  sub64 r1, r2"
      b := emit b "  sub64 r1, r5"
      -- borrow: (a < b) || (bin == 1 && a == b)
      b := emit b "  mov64 r4, 0"
      b := emit b s!"  jlt r3, r2, {bset}"
      b := emit b s!"  jeq r5, 0, {bdone}"
      b := emit b s!"  jeq r3, r2, {bset}"
      b := emit b s!"  ja {bdone}"
      b := emit b s!"{bset}:"
      b := emit b "  mov64 r4, 1"
      b := emit b s!"{bdone}:"
      b := storeTemp b tempBase (dest + i) "r1"
      b := emit b "  mov64 r5, r4"
    b := emit b s!"  jne r5, 0, {errLab}"
    b := emit b s!"  ja {okLab}"
    b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Multiword bitwise op (and/or/xor) per limb; no failure mode. -/
private def emitMultiwordBitOp (b : AsmBuf) (tempBase dest lhs rhs nLimbs : Nat)
    (mnemonic : String) : AsmBuf :=
  Id.run do
    let mut b := b
    for i in [:nLimbs] do
      b := loadTemp b "r1" tempBase (lhs + i)
      b := loadTemp b "r2" tempBase (rhs + i)
      b := emit b s!"  {mnemonic} r1, r2"
      b := storeTemp b tempBase (dest + i) "r1"
    pure b

/-- Multiword bitNot: xor each limb with -1. -/
private def emitMultiwordBitNot (b : AsmBuf) (tempBase dest source nLimbs : Nat) : AsmBuf :=
  Id.run do
    let mut b := b
    for i in [:nLimbs] do
      b := loadTemp b "r1" tempBase (source + i)
      b := emit b "  lddw r2, 0xffffffffffffffff"
      b := emit b "  xor64 r1, r2"
      b := storeTemp b tempBase (dest + i) "r1"
    pure b

/-- Multiword load from account/instruction data: consecutive ldxdw. -/
private def emitMultiwordMemLoad (b : AsmBuf) (tempBase dest nLimbs : Nat)
    (baseLabel : String) (byteOffset : Nat) (comment : String) : AsmBuf :=
  Id.run do
    let mut b := emit b s!"  ; {comment}"
    for i in [:nLimbs] do
      b := emit b s!"  ldxdw r1, [r6 + {baseLabel} + {byteOffset + i * 8}]"
      b := storeTemp b tempBase (dest + i) "r1"
    pure b

/-- Multiword store to account data. -/
private def emitMultiwordMemStore (b : AsmBuf) (tempBase value nLimbs byteOffset : Nat)
    (comment : String) : AsmBuf :=
  Id.run do
    let mut b := emit b s!"  ; {comment}"
    for i in [:nLimbs] do
      b := loadTemp b "r1" tempBase (value + i)
      b := emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset + i * 8}], r1"
    pure b

/-- Multiword zero of account field limbs. -/
private def emitMultiwordZeroState (b : AsmBuf) (nLimbs byteOffset : Nat) : AsmBuf :=
  Id.run do
    let mut b := emit b s!"  ; zero_u{nLimbs * 64}_le account[0].data + {byteOffset}"
    b := emit b "  lddw r1, 0"
    for i in [:nLimbs] do
      b := emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset + i * 8}], r1"
    pure b

/-- Multiword unsigned compare → Bool in dest (hi limb first). -/
private def emitMultiwordCompare (b : AsmBuf) (tempBase dest lhs rhs nLimbs : Nat)
    (op : ComparisonOp) : AsmBuf :=
  Id.run do
    match op with
    | .eq | .ne =>
        let (b, falseLab) := fresh b "mwcmp_ne"
        let (b, doneLab) := fresh b "mwcmp_done"
        let mut b := b
        for i in [:nLimbs] do
          b := loadTemp b "r1" tempBase (lhs + i)
          b := loadTemp b "r2" tempBase (rhs + i)
          b := emit b s!"  jne r1, r2, {falseLab}"
        if op == ComparisonOp.eq then
          b := emit b "  lddw r1, 1"
        else
          b := emit b "  lddw r1, 0"
        b := storeTemp b tempBase dest "r1"
        b := emit b s!"  ja {doneLab}"
        b := emit b s!"{falseLab}:"
        if op == ComparisonOp.eq then
          b := emit b "  lddw r1, 0"
        else
          b := emit b "  lddw r1, 1"
        b := storeTemp b tempBase dest "r1"
        emit b s!"{doneLab}:"
    | .lt | .le | .gt | .ge =>
        let (b, doneLab) := fresh b "mword_done"
        let mut b := b
        let eqResult : Nat :=
          match op with | .le | .ge => 1 | _ => 0
        b := emit b s!"  lddw r1, {eqResult}"
        b := storeTemp b tempBase dest "r1"
        for j in [:nLimbs] do
          let i := nLimbs - 1 - j
          let (b2, nextLab) := fresh b "mword_next"
          b := b2
          b := loadTemp b "r1" tempBase (lhs + i)
          b := loadTemp b "r2" tempBase (rhs + i)
          b := emit b s!"  jeq r1, r2, {nextLab}"
          let (b3, trueLab) := fresh b "mword_true"
          let (b4, setDone) := fresh b3 "mword_set"
          b := b4
          b := emit b "  mov64 r3, 0"
          b := match op with
            | .lt => emit b s!"  jlt r1, r2, {trueLab}"
            | .le => emit b s!"  jle r1, r2, {trueLab}"
            | .gt => emit b s!"  jgt r1, r2, {trueLab}"
            | .ge => emit b s!"  jge r1, r2, {trueLab}"
            | _ => b
          b := emit b s!"  ja {setDone}"
          b := emit b s!"{trueLab}:"
          b := emit b "  mov64 r3, 1"
          b := emit b s!"{setDone}:"
          b := storeTemp b tempBase dest "r3"
          b := emit b s!"  ja {doneLab}"
          b := emit b s!"{nextLab}:"
        emit b s!"{doneLab}:"

/-- Allocate `n` consecutive absolute temps from the cursor; returns base. -/
private def allocTemps (b : AsmBuf) (n : Nat) : AsmBuf × Nat :=
  let base := b.cursor
  ({ b with cursor := b.cursor + n }, base)

/-- Multiword checked div/mod via binary long division (restoring).

    Exact unsigned `nLimbs`-limb quotient and remainder for Solana lane
    UInt128 (`nLimbs=2`) / UInt256 (`nLimbs=4`). Algorithm (restoring /
    binary long division):

      rem := 0                          -- `nLimbs+1` limbs (extra high digit)
      quot := 0                         -- `nLimbs` limbs
      for bit from (nLimbs·64 − 1) downto 0:
        rem := (rem << 1) | dividend[bit]
        if rem ≥ divisor:               -- zero-extended divisor
          rem := rem − divisor
          quot[bit] := 1

    Divisor zero (all limbs zero) fails with `errorCode` (same program_error
    as other checked arithmetic, typically `0x1001`). Quotient and remainder
    are always in-range for unsigned division, so there is no overflow path
    beyond div-by-zero.

    Fully unrolled over the bit width so every stack offset / shift count is
    a compile-time immediate (matches schoolbook mul style; no dynamic limb
    indexing). Scratch `rem`/`quot` temps are allocated from the AsmBuf cursor
    and copied into `dest` so lhs/rhs aliasing is safe. -/
private def emitMultiwordDivMod (b : AsmBuf) (tempBase dest lhs rhs errorCode nLimbs : Nat)
    (kind : String) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b s!"err_mw{kind}"
    let (b, okLab) := fresh b s!"ok_mw{kind}"
    let nBits := nLimbs * 64
    -- rem[0 .. nLimbs-1] + remHi (extra limb for the left-shift digit)
    let (b, rem) := allocTemps b (nLimbs + 1)
    let remHi := rem + nLimbs
    let (b, quot) := allocTemps b nLimbs
    let mut b := b
    -- divisor nonzero? (OR of all limbs)
    b := emit b "  mov64 r1, 0"
    for i in [:nLimbs] do
      b := loadTemp b "r2" tempBase (rhs + i)
      b := emit b "  or64 r1, r2"
    b := emit b s!"  jeq r1, 0, {errLab}"
    -- zero rem (incl. high) and quot
    b := emit b "  lddw r1, 0"
    for i in [:nLimbs + 1] do
      b := storeTempAbs b (rem + i) "r1"
    for i in [:nLimbs] do
      b := storeTempAbs b (quot + i) "r1"
    -- bit = nBits-1 .. 0 (fully unrolled)
    for j in [:nBits] do
      let bitPos := nBits - 1 - j
      let numLimb := bitPos / 64
      let numBit := bitPos % 64
      -- rem := rem << 1  (nLimbs+1 limbs, high → low so lower digits stay fresh)
      b := loadTempAbs b "r1" remHi
      b := emit b "  lsh64 r1, 1"
      b := loadTempAbs b "r2" (rem + (nLimbs - 1))
      b := emit b "  rsh64 r2, 63"
      b := emit b "  or64 r1, r2"
      b := storeTempAbs b remHi "r1"
      for iRev in [:nLimbs] do
        let i := nLimbs - 1 - iRev
        if i > 0 then
          b := loadTempAbs b "r1" (rem + i)
          b := emit b "  lsh64 r1, 1"
          b := loadTempAbs b "r2" (rem + (i - 1))
          b := emit b "  rsh64 r2, 63"
          b := emit b "  or64 r1, r2"
          b := storeTempAbs b (rem + i) "r1"
        else
          -- rem[0] = (rem[0] << 1) | dividend[bitPos]
          b := loadTempAbs b "r1" rem
          b := emit b "  lsh64 r1, 1"
          b := loadTemp b "r2" tempBase (lhs + numLimb)
          if numBit != 0 then
            b := emit b s!"  rsh64 r2, {numBit}"
          b := emit b "  and64 r2, 1"
          b := emit b "  or64 r1, r2"
          b := storeTempAbs b rem "r1"
      -- if rem ≥ divisor (zero-extended): subtract and set quot bit
      let (b1, subLab) := fresh b s!"mw{kind}_sub"
      let (b2, nextBit) := fresh b1 s!"mw{kind}_nb"
      b := b2
      b := loadTempAbs b "r1" remHi
      b := emit b s!"  jne r1, 0, {subLab}"
      for iRev in [:nLimbs] do
        let i := nLimbs - 1 - iRev
        b := loadTempAbs b "r1" (rem + i)
        b := loadTemp b "r2" tempBase (rhs + i)
        b := emit b s!"  jgt r1, r2, {subLab}"
        b := emit b s!"  jlt r1, r2, {nextBit}"
        -- equal: fall through to next lower limb (or to subLab when i == 0)
      b := emit b s!"{subLab}:"
      -- rem_low -= divisor with borrow into remHi
      b := emit b "  mov64 r5, 0"
      for i in [:nLimbs] do
        let (b3, bset) := fresh b s!"mw{kind}_bset"
        let (b4, bdone) := fresh b3 s!"mw{kind}_bdone"
        b := b4
        b := loadTempAbs b "r1" (rem + i)
        b := loadTemp b "r2" tempBase (rhs + i)
        b := emit b "  mov64 r3, r1"
        b := emit b "  sub64 r1, r2"
        b := emit b "  sub64 r1, r5"
        b := emit b "  mov64 r4, 0"
        b := emit b s!"  jlt r3, r2, {bset}"
        b := emit b s!"  jeq r5, 0, {bdone}"
        b := emit b s!"  jeq r3, r2, {bset}"
        b := emit b s!"  ja {bdone}"
        b := emit b s!"{bset}:"
        b := emit b "  mov64 r4, 1"
        b := emit b s!"{bdone}:"
        b := storeTempAbs b (rem + i) "r1"
        b := emit b "  mov64 r5, r4"
      b := loadTempAbs b "r1" remHi
      b := emit b "  sub64 r1, r5"
      b := storeTempAbs b remHi "r1"
      -- quot[numLimb] |= 1 << numBit
      b := loadTempAbs b "r1" (quot + numLimb)
      b := emit b "  lddw r2, 1"
      if numBit != 0 then
        b := emit b s!"  lsh64 r2, {numBit}"
      b := emit b "  or64 r1, r2"
      b := storeTempAbs b (quot + numLimb) "r1"
      b := emit b s!"{nextBit}:"
    -- store quotient or remainder into dest
    if kind == "div" then
      for t in [:nLimbs] do
        b := loadTempAbs b "r1" (quot + t)
        b := storeTemp b tempBase (dest + t) "r1"
    else
      -- remainder: low nLimbs of rem (remHi is always 0 post-loop)
      for t in [:nLimbs] do
        b := loadTempAbs b "r1" (rem + t)
        b := storeTemp b tempBase (dest + t) "r1"
    b := emit b s!"  ja {okLab}"
    b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Schoolbook multiword checked mul (Solana lane: UInt128=2 limbs / UInt256=4 limbs).

    Computes the exact `2·nLimbs`-limb unsigned product of the `nLimbs`-limb
    operands at `lhs`/`rhs`, then:
      * fails with `errorCode` when any upper limb `[nLimbs .. 2·nLimbs)`
        of the exact product is non-zero (does not fit the result width);
      * otherwise copies the low `nLimbs` product limbs to `dest`.

    Each 64×64 → 128 limb product uses the 32-bit-digit schoolbook identity
    `x·y = p0 + (p1 + p2)·2^32 + p3·2^64` with
      p0 = xl·yl, p1 = xl·yh, p2 = xh·yl, p3 = xh·yh, mid = p1 + p2 (< 2^65),
      lo64 = (p0 + midLo·2^32) mod 2^64,  hi64 = p3 + midHi' + carry1,
    where `midHi' = (mid div 2^32) | (carry·2^32)` (carry = mid div 2^64;
    when carry = 1 the bit 32 of `mid div 2^32` is already set, so OR ≡ ADD)
    and `carry1 = (p0h + midLo) div 2^32`; this recovers the 128-bit product
    exactly (hi64 < 2^64).

    Lane accumulation is lane-ordered (m = i + j ascending) with explicit
    carry propagation: a lane sum `S_m = Σ_{i+j=m} lo64_{ij} +
    Σ_{i+j=m-1} hi64_{ij} + carryIn` may reach `O(nLimbs)·2^64` and wraps a
    64-bit lane, so each lane is accumulated into a running `(rlo, rhi)` pair
    (rhi tracks every wrap; total S_m < 2^67 for nLimbs ≤ 4), the low lane
    is stored as `acc[m] = rlo`, and `rhi` becomes the next lane's carryIn.
    Upper lanes (m ≥ nLimbs) must be exactly zero (checked on both rlo and
    rhi); the final lane `2·nLimbs-1` holds only carries + hi64 of
    `i+j = 2·nLimbs-2`. -/
private def emitMultiwordCheckedMul (b : AsmBuf) (tempBase dest lhs rhs errorCode nLimbs : Nat) :
    AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_mwmul"
    let (b, okLab) := fresh b "ok_mwmul"
    -- acc: low nLimbs product limbs (upper lanes checked inline).
    let (b, acc) := allocTemps b nLimbs
    -- hiTemps: stored hi64 per pair (i,j) at index i*nLimbs + j.
    let (b, hiTemps) := allocTemps b (nLimbs * nLimbs)
    -- scratch: sx sy sxl sxh syl syh sp0 sp1 sp2 sp3 sp0l sp0h
    --          smidlo smidhi scarry slo shi
    let (b, sx) := allocTemps b 17
    let sy := sx + 1
    let sxl := sx + 2
    let sxh := sx + 3
    let syl := sx + 4
    let syh := sx + 5
    let sp0 := sx + 6
    let sp1 := sx + 7
    let sp2 := sx + 8
    let sp3 := sx + 9
    let sp0l := sx + 10
    let sp0h := sx + 11
    let smidlo := sx + 12
    let smidhi := sx + 13
    let scarry := sx + 14
    let slo := sx + 15
    let shi := sx + 16
    -- running lane accumulator (rlo, rhi) + carryIn for lane 0.
    let (b, rlo) := allocTemps b 2
    let rhi := rlo + 1
    let (b, carryIn) := allocTemps b 1
    let mut b := b
    -- carryIn = 0 (lane 0 has no incoming carry)
    b := emit b "  lddw r1, 0"
    b := storeTempAbs b carryIn "r1"
    -- lane-ordered schoolbook accumulation: S_m = carryIn + Σ lo64 + Σ hi64
    for m in [0:2 * nLimbs] do
      -- running lane: rlo := carryIn, rhi := 0
      b := loadTempAbs b "r1" carryIn
      b := storeTempAbs b rlo "r1"
      b := emit b "  lddw r1, 0"
      b := storeTempAbs b rhi "r1"
      -- lo64 contributions from pairs (i, j) with i + j == m
      for i in [:nLimbs] do
        for j in [:nLimbs] do
          if i + j == m then
            b := loadTemp b "r1" tempBase (lhs + i)
            b := storeTempAbs b sx "r1"
            b := loadTemp b "r1" tempBase (rhs + j)
            b := storeTempAbs b sy "r1"
            -- xl = sx & 0xffffffff
            b := loadTempAbs b "r1" sx
            b := emit b "  mov64 r2, r1"
            b := emit b "  lddw r3, 0xffffffff"
            b := emit b "  and64 r2, r3"
            b := storeTempAbs b sxl "r2"
            -- xh = sx >> 32
            b := loadTempAbs b "r1" sx
            b := emit b "  lddw r2, 32"
            b := emit b "  rsh64 r1, r2"
            b := storeTempAbs b sxh "r1"
            -- yl = sy & 0xffffffff
            b := loadTempAbs b "r1" sy
            b := emit b "  mov64 r2, r1"
            b := emit b "  lddw r3, 0xffffffff"
            b := emit b "  and64 r2, r3"
            b := storeTempAbs b syl "r2"
            -- yh = sy >> 32
            b := loadTempAbs b "r1" sy
            b := emit b "  lddw r2, 32"
            b := emit b "  rsh64 r1, r2"
            b := storeTempAbs b syh "r1"
            -- p0 = xl * yl
            b := loadTempAbs b "r1" sxl
            b := loadTempAbs b "r2" syl
            b := emit b "  mul64 r1, r2"
            b := storeTempAbs b sp0 "r1"
            -- p1 = xl * yh
            b := loadTempAbs b "r1" sxl
            b := loadTempAbs b "r2" syh
            b := emit b "  mul64 r1, r2"
            b := storeTempAbs b sp1 "r1"
            -- p2 = xh * yl
            b := loadTempAbs b "r1" sxh
            b := loadTempAbs b "r2" syl
            b := emit b "  mul64 r1, r2"
            b := storeTempAbs b sp2 "r1"
            -- p3 = xh * yh
            b := loadTempAbs b "r1" sxh
            b := loadTempAbs b "r2" syh
            b := emit b "  mul64 r1, r2"
            b := storeTempAbs b sp3 "r1"
            -- p0l = p0 & 0xffffffff
            b := loadTempAbs b "r1" sp0
            b := emit b "  mov64 r2, r1"
            b := emit b "  lddw r3, 0xffffffff"
            b := emit b "  and64 r2, r3"
            b := storeTempAbs b sp0l "r2"
            -- p0h = p0 >> 32
            b := loadTempAbs b "r1" sp0
            b := emit b "  lddw r2, 32"
            b := emit b "  rsh64 r1, r2"
            b := storeTempAbs b sp0h "r1"
            -- mid = p1 + p2 (low 64); carry = 1 if the full sum wrapped
            b := loadTempAbs b "r1" sp1
            b := loadTempAbs b "r2" sp2
            b := emit b "  mov64 r3, r1"
            b := emit b "  add64 r1, r2"
            let (b1, midNoCarry) := fresh b "mwmul_midnc"
            b := b1
            b := emit b "  mov64 r4, 0"
            b := emit b s!"  jge r1, r3, {midNoCarry}"
            b := emit b "  mov64 r4, 1"
            b := emit b s!"{midNoCarry}:"
            -- midLo = mid & 0xffffffff ; midHi = (mid >> 32) | (carry << 32)
            b := emit b "  mov64 r2, r1"
            b := emit b "  lddw r5, 0xffffffff"
            b := emit b "  and64 r2, r5"
            b := storeTempAbs b smidlo "r2"
            b := emit b "  lddw r5, 32"
            b := emit b "  rsh64 r1, r5"
            b := emit b "  mov64 r2, r4"
            b := emit b "  lsh64 r2, r5"
            b := emit b "  add64 r1, r2"
            b := storeTempAbs b smidhi "r1"
            -- carry1 = (p0h + midLo) >> 32
            b := loadTempAbs b "r1" sp0h
            b := loadTempAbs b "r2" smidlo
            b := emit b "  add64 r1, r2"
            b := emit b "  lddw r5, 32"
            b := emit b "  rsh64 r1, r5"
            b := storeTempAbs b scarry "r1"
            -- lo64 = ((p0h + midLo) & 0xffffffff) << 32 | p0l
            b := loadTempAbs b "r1" sp0h
            b := loadTempAbs b "r2" smidlo
            b := emit b "  add64 r1, r2"
            b := emit b "  lddw r5, 0xffffffff"
            b := emit b "  and64 r1, r5"
            b := emit b "  lddw r5, 32"
            b := emit b "  lsh64 r1, r5"
            b := loadTempAbs b "r2" sp0l
            b := emit b "  or64 r1, r2"
            b := storeTempAbs b slo "r1"
            -- hi64 = p3 + midHi + carry1
            b := loadTempAbs b "r1" sp3
            b := loadTempAbs b "r2" smidhi
            b := emit b "  add64 r1, r2"
            b := loadTempAbs b "r2" scarry
            b := emit b "  add64 r1, r2"
            b := storeTempAbs b shi "r1"
            -- store hi64 for the m+1 lane
            b := loadTempAbs b "r1" shi
            b := storeTempAbs b (hiTemps + i * nLimbs + j) "r1"
            -- rlo += lo64 (wrap-tracked): rhi += carry(rlo + lo64)
            b := loadTempAbs b "r1" rlo
            b := loadTempAbs b "r2" slo
            b := emit b "  add64 r1, r2"
            let (b2, laneNoCarry) := fresh b "mwmul_lane"
            b := b2
            b := emit b "  mov64 r3, 0"
            b := emit b s!"  jge r1, r2, {laneNoCarry}"
            b := emit b "  mov64 r3, 1"
            b := emit b s!"{laneNoCarry}:"
            b := storeTempAbs b rlo "r1"
            b := loadTempAbs b "r4" rhi
            b := emit b "  add64 r4, r3"
            b := storeTempAbs b rhi "r4"
      -- hi64 contributions from pairs (i, j) with i + j == m - 1
      if m > 0 then
        for i in [:nLimbs] do
          for j in [:nLimbs] do
            if i + j == m - 1 then
              b := loadTempAbs b "r1" rlo
              b := loadTempAbs b "r2" (hiTemps + i * nLimbs + j)
              b := emit b "  add64 r1, r2"
              let (b3, laneNoCarry) := fresh b "mwmul_lane"
              b := b3
              b := emit b "  mov64 r3, 0"
              b := emit b s!"  jge r1, r2, {laneNoCarry}"
              b := emit b "  mov64 r3, 1"
              b := emit b s!"{laneNoCarry}:"
              b := storeTempAbs b rlo "r1"
              b := loadTempAbs b "r4" rhi
              b := emit b "  add64 r4, r3"
              b := storeTempAbs b rhi "r4"
      if m < nLimbs then
        -- low lane: store acc[m] = rlo, propagate rhi as carryIn
        b := loadTempAbs b "r1" rlo
        b := storeTempAbs b (acc + m) "r1"
        b := loadTempAbs b "r1" rhi
        b := storeTempAbs b carryIn "r1"
      else
        -- upper lane: exact product must have a zero digit here
        b := loadTempAbs b "r1" rlo
        b := emit b s!"  jne r1, 0, {errLab}"
        b := loadTempAbs b "r1" rhi
        b := emit b s!"  jne r1, 0, {errLab}"
    -- copy the low nLimbs product limbs to dest
    for t in [:nLimbs] do
      b := loadTempAbs b "r1" (acc + t)
      b := storeTemp b tempBase (dest + t) "r1"
    b := emit b s!"  ja {okLab}"
    b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Narrow checked_add: 64-bit add then high bits above `bitWidth` must be zero. -/
private def emitNarrowCheckedAdd (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  if bitWidth > 64 then
    emitMultiwordCheckedAdd b tempBase dest lhs rhs errorCode (limbCountOfBitWidth bitWidth)
  else Id.run do
    let (b, errLab) := fresh b "err_nadd"
    let (b, okLab) := fresh b "ok_nadd"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  add64 r4, r2"
    let b := emit b "  mov64 r3, r4"
    let b := emit b s!"  rsh64 r3, {bitWidth}"
    let b := emit b s!"  jne r3, 0, {errLab}"
    let b := storeTemp b tempBase dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Narrow checked_sub: same underflow guard as u64; result auto in-range. -/
private def emitNarrowCheckedSub (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  if bitWidth > 64 then
    emitMultiwordCheckedSub b tempBase dest lhs rhs errorCode (limbCountOfBitWidth bitWidth)
  else Id.run do
    let _ := bitWidth
    emitCheckedSub b tempBase dest lhs rhs errorCode

/-- Narrow checked_mul: 64-bit mul then high bits above `bitWidth` must be zero.
    Multiword (UInt128/256) uses true schoolbook 32-bit-split mul (no low64
    fallback); overflow when the exact product does not fit the width. -/
private def emitNarrowCheckedMul (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  if bitWidth > 64 then
    emitMultiwordCheckedMul b tempBase dest lhs rhs errorCode (limbCountOfBitWidth bitWidth)
  else Id.run do
    let (b, errLab) := fresh b "err_nmul"
    let (b, okLab) := fresh b "ok_nmul"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  mul64 r4, r2"
    let b := emit b "  mov64 r3, r4"
    let b := emit b s!"  rsh64 r3, {bitWidth}"
    let b := emit b s!"  jne r3, 0, {errLab}"
    let b := storeTemp b tempBase dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Narrow checked_div: zero guard only; quotient auto in-range for UInt.
    Multiword (UInt128/256) uses true binary long division over LE u64 limbs
    (see `emitMultiwordDivMod`); divisor zero fails with `errorCode`. -/
private def emitNarrowCheckedDiv (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  if bitWidth > 64 then
    emitMultiwordDivMod b tempBase dest lhs rhs errorCode (limbCountOfBitWidth bitWidth) "div"
  else Id.run do
    let _ := bitWidth
    emitCheckedDiv b tempBase dest lhs rhs errorCode

/-- Narrow checked_mod: zero guard only; remainder auto in-range.
    Multiword (UInt128/256) uses the same binary long division as div and
    stores the remainder limbs (see `emitMultiwordDivMod`). -/
private def emitNarrowCheckedMod (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  if bitWidth > 64 then
    emitMultiwordDivMod b tempBase dest lhs rhs errorCode (limbCountOfBitWidth bitWidth) "mod"
  else Id.run do
    let _ := bitWidth
    emitCheckedMod b tempBase dest lhs rhs errorCode

/-- Narrow shl: count ≥ 64 → shiftErr; high bits above width → overflow. -/
private def emitNarrowCheckedShl (b : AsmBuf) (tempBase dest lhs rhs shiftErr overflowErr
    bitWidth : Nat) : AsmBuf :=
  Id.run do
    let (b, errShift) := fresh b "err_nshl_count"
    let (b, errOverflow) := fresh b "err_nshl_ovf"
    let (b, okLab) := fresh b "ok_nshl"
    let b := loadTemp b "r1" tempBase lhs
    let b := loadTemp b "r2" tempBase rhs
    let b := emit b s!"  jge r2, 64, {errShift}"
    let b := emit b "  lsh64 r1, r2"
    let b := emit b "  mov64 r3, r1"
    let b := emit b s!"  rsh64 r3, {bitWidth}"
    let b := emit b s!"  jne r3, 0, {errOverflow}"
    let b := storeTemp b tempBase dest "r1"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errShift shiftErr
    let b := emitErrorExit b errOverflow overflowErr
    emit b s!"{okLab}:"

/-- Narrow shr: count ≥ 64 → shiftErr; result auto in-range. -/
private def emitNarrowCheckedShr (b : AsmBuf) (tempBase dest lhs rhs shiftErr bitWidth : Nat) :
    AsmBuf :=
  Id.run do
    let _ := bitWidth
    emitCheckedShr b tempBase dest lhs rhs shiftErr

/-- Narrow bitNot: xor -1 then AND width mask. -/
private def emitNarrowBitNot (b : AsmBuf) (tempBase dest source bitWidth : Nat) : AsmBuf :=
  if bitWidth > 64 then
    emitMultiwordBitNot b tempBase dest source (limbCountOfBitWidth bitWidth)
  else Id.run do
    let b := loadTemp b "r1" tempBase source
    let b := emit b "  lddw r2, 0xffffffffffffffff"
    let b := emit b "  xor64 r1, r2"
    let b := emit b s!"  lddw r2, {narrowUintMaskImm bitWidth}"
    let b := emit b "  and64 r1, r2"
    storeTemp b tempBase dest "r1"

/-- Stash a little-endian integer of `byteLen` ∈ {1,2,4,8} at absolute temp
    `retTemp` and call `sol_set_return_data`. UInt64/Int64 use full 8B stores;
    UInt{8,16,32} use stxb/sth/stw so return-data length matches the ABI. -/
private def emitSetReturnDataBytes (b : AsmBuf) (tempBase valueTemp retTemp byteLen : Nat) :
    AsmBuf :=
  Id.run do
    let off := tempStackOff retTemp
    let mut b := b
    if byteLen == 16 || byteLen == 32 then
      -- Multiword: valueTemp is base of consecutive limbs; pack into retTemp..
      let nLimbs := byteLen / 8
      for i in [:nLimbs] do
        b := loadTemp b "r1" tempBase (valueTemp + i)
        b := storeTempAbs b (retTemp + i) "r1"
    else
      b := loadTemp b "r1" tempBase valueTemp
      b := match byteLen with
        | 1 => emit b s!"  stxb [r10 - {off}], r1"
        | 2 => emit b s!"  stxh [r10 - {off}], r1"
        | 4 => emit b s!"  stxw [r10 - {off}], r1"
        | _ => storeTempAbs b retTemp "r1"
    b := emit b "  mov64 r1, r10"
    b := emit b s!"  add64 r1, -{off}"
    b := emit b s!"  lddw r2, {byteLen}"
    emit b "  call sol_set_return_data"

/-- Stash a u64 at absolute temp `retTemp` and call `sol_set_return_data`. -/
private def emitSetReturnDataU64 (b : AsmBuf) (tempBase valueTemp retTemp : Nat) :
    AsmBuf :=
  emitSetReturnDataBytes b tempBase valueTemp retTemp 8

/-- Stash a bool as a single byte and call `sol_set_return_data` with len=1. -/
private def emitSetReturnDataBool (b : AsmBuf) (tempBase valueTemp retTemp : Nat) :
    AsmBuf :=
  emitSetReturnDataBytes b tempBase valueTemp retTemp 1

/-- B-RET-ABI: pack N independent u64 leaf temps into a contiguous return-data
    buffer at absolute `retTemp..retTemp+N-1` and call `sol_set_return_data`
    with length `N*8`. Leaves may be non-consecutive (CSE). -/
private def emitSetReturnDataMulti (b : AsmBuf) (tempBase : Nat)
    (valueTemps : Array Nat) (retTemp : Nat) : AsmBuf :=
  Id.run do
    let n := valueTemps.size
    let mut b := b
    for i in [:n] do
      b := loadTemp b "r1" tempBase valueTemps[i]!
      b := storeTempAbs b (retTemp + i) "r1"
    let off := tempStackOff retTemp
    b := emit b "  mov64 r1, r10"
    b := emit b s!"  add64 r1, -{off}"
    b := emit b s!"  lddw r2, {n * 8}"
    emit b "  call sol_set_return_data"

/-- Resolve pureFn param index by instruction-data offset (fn table). -/
private def paramIndexByOffset (params : Array Param) (dataOffset : Nat) : Option Nat :=
  Id.run do
    for i in [:params.size] do
      if params[i]!.dataOffset == dataOffset then
        return some i
    none

/-- Inlined pureFn context: maps setReturnData* to a caller destination temp. -/
private structure InlineCtx where
  /-- Absolute temp that receives the pureFn return value. -/
  retDestAbs : Nat
  /-- Callee pureFn (for param-offset remap of loadParam). -/
  fn : FnIR
  /-- Inline-instance end label: a fn-level `return` (hard-exit marker)
      jumps here so trailing ops after a one-arm-closed region are skipped. -/
  fnEndLabel : String
  /-- Absolute base of the callee param slots (calleeBase + 0..arity-1).
      Body temps live at a disjoint region (calleeBase + arity + ..), so a
      body op writing temp `t < arity` can never clobber a param slot. -/
  paramBase : Nat

/-- Parse limb `limb` (0..3) of a 64-hex-char program id as LE u64 value. -/
private def programIdLimbLeV1 (hex64 : String) (limb : Nat) : CompileResult Nat := do
  unless hex64.length == 64 do
    return ← asmError s!"S1b program_id must be 64 hex chars, got length {hex64.length}"
  unless limb < 4 do
    return ← asmError s!"S1b program_id limb index {limb} out of range"
  let chars := hex64.toList
  let base := limb * 16
  let mut value : Nat := 0
  for i in [:8] do
    let some hi := hexDigitValue chars[base + 2 * i]! |
      return ← asmError s!"S1b program_id has non-hex at index {base + 2 * i}"
    let some lo := hexDigitValue chars[base + 2 * i + 1]! |
      return ← asmError s!"S1b program_id has non-hex at index {base + 2 * i + 1}"
    let byte := hi * 16 + lo
    value := value + byte * (Nat.pow 2 (8 * i))
  pure value

/-- BL-27: emit real CPI via `sol_invoke_signed_c` with empty AccountMeta list.
    Instruction data = method discriminator (product ABI) + LE UInt64 args.
    When `resultDest` is set, read 8B LE return data via `sol_get_return_data`
    (short/missing → `cpiReturnDataError` 0x1006). Frame budget still enforced
    via the shared cursor/allocTemps path. -/
private def emitCpiInvoke (b0 : AsmBuf) (tempBase : Nat)
    (callee : Array String) (programIdHex : String) (args : Array Nat)
    (resultDest : Option Nat) (kindNote : String) : CompileResult AsmBuf := do
  unless callee.size ≥ 2 do
    return ← asmError s!"S1b {kindNote} callee must have ≥2 components"
  let method := callee[callee.size - 1]!
  let note := String.intercalate "." callee.toList
  let n := args.size
  let discHex := externalMethodDiscriminator method n
  let discLe ← discriminatorToLeU64V1 discHex
  -- Stack layout (absolute temps, each 8B):
  --   pid[4] | data[1+n] | ix[5] | [retbuf 1 | pidOut 4] if result
  let pidBaseSlots := 4
  let dataSlots := 1 + n
  let ixSlots := 5
  let resultSlots := match resultDest with | some _ => 5 | none => 0
  let need := pidBaseSlots + dataSlots + ixSlots + resultSlots
  let (b1, bufBase) := allocTemps b0 need
  let pidBase := bufBase
  let dataBase := bufBase + pidBaseSlots
  let ixBase := dataBase + dataSlots
  let retBase := ixBase + ixSlots
  let pidOutBase := retBase + 1
  let mut b := emit b1
    s!"  ; {kindNote} {note} program_id=0x{programIdHex} ({n} args) via sol_invoke_signed_c"
  b := emit b s!"  ; method disc={discHex} (product ABI, empty AccountMeta)"
  b := emit b "  ; stack temps grow downward: reverse-pack multi-word structs"
  -- program_id: 4 LE u64 limbs in *increasing* memory (= decreasing temp index).
  -- limb0 at highest temp (lowest addr) … limb3 at pidBase (highest addr).
  for limb in [:4] do
    let v ← programIdLimbLeV1 programIdHex limb
    b := emit b s!"  lddw r1, {hexImm v}"
    b := storeTempAbs b (pidBase + 3 - limb) "r1"
  let pidPtrTemp := pidBase + 3
  -- instruction data: disc then args, reverse-packed so disc is at lowest addr.
  -- dataSlots = 1+n; disc at dataBase+n, arg i at dataBase+n-1-i.
  b := emit b s!"  lddw r1, {hexImm discLe.toNat}"
  b := storeTempAbs b (dataBase + n) "r1"
  for i in [:n] do
    b := loadTemp b "r1" tempBase args[i]!
    b := storeTempAbs b (dataBase + n - 1 - i) "r1"
  let dataPtrTemp := dataBase + n
  -- SolInstruction fields reverse-packed into ixBase..ixBase+4:
  --   ixBase+4 program_id_addr (lowest addr = &SolInstruction)
  --   ixBase+3 accounts_addr
  --   ixBase+2 accounts_len
  --   ixBase+1 data_addr
  --   ixBase+0 data_len
  b := emit b "  mov64 r1, r10"
  b := emit b s!"  add64 r1, -{tempStackOff pidPtrTemp}"
  b := storeTempAbs b (ixBase + 4) "r1"
  b := emit b "  lddw r1, 0"
  b := storeTempAbs b (ixBase + 3) "r1"  -- accounts_addr (unused, len=0)
  b := emit b "  lddw r1, 0"
  b := storeTempAbs b (ixBase + 2) "r1"  -- accounts_len = 0
  b := emit b "  mov64 r1, r10"
  b := emit b s!"  add64 r1, -{tempStackOff dataPtrTemp}"
  b := storeTempAbs b (ixBase + 1) "r1"
  b := emit b s!"  lddw r1, {hexImm (8 * dataSlots)}"
  b := storeTempAbs b ixBase "r1"
  let ixPtrTemp := ixBase + 4
  -- invoke: r1=&SolInstruction, r2=account_infos, r3=infos_len,
  --         r4=signers, r5=signers_len
  b := emit b "  mov64 r1, r10"
  b := emit b s!"  add64 r1, -{tempStackOff ixPtrTemp}"
  b := emit b "  lddw r2, 0"
  b := emit b "  lddw r3, 0"
  b := emit b "  lddw r4, 0"
  b := emit b "  lddw r5, 0"
  b := emit b "  call sol_invoke_signed_c"
  -- Callee program error aborts natively before return. On success r0=0.
  match resultDest with
  | none => pure b
  | some dest =>
      -- sol_get_return_data(buf, 8, program_id_out) → r0 = full length.
      -- retBase holds the 8B result; pidOutBase..+3 hold program_id out
      -- (reverse-pack so &pidOutBase+3 is the 32B buffer start).
      let (b2, shortLab) := fresh b "cpi_ret_short"
      let (b3, okLab) := fresh b2 "cpi_ret_ok"
      b := b3
      b := emit b "  mov64 r1, r10"
      b := emit b s!"  add64 r1, -{tempStackOff retBase}"
      b := emit b "  lddw r2, 8"
      b := emit b "  mov64 r3, r10"
      b := emit b s!"  add64 r3, -{tempStackOff (pidOutBase + 3)}"
      b := emit b "  call sol_get_return_data"
      b := emit b s!"  jlt r0, 8, {shortLab}"
      b := loadTempAbs b "r1" retBase
      b := storeTemp b tempBase dest "r1"
      b := emit b s!"  ja {okLab}"
      b := emit b s!"{shortLab}:"
      b := emit b s!"  lddw r0, {hexImm cpiReturnDataError}"
      b := emit b "  exit"
      pure (emit b s!"{okLab}:")

mutual
/-- Emit a single Operation. `inlineCtx=none` is a handler body (syscalls + exit). -/
private partial def emitOperation (b : AsmBuf) (ir : IR) (tempBase : Nat)
    (inlineCtx : Option InlineCtx) (inlineDepth : Nat) (op : Operation) :
    CompileResult AsmBuf := do
  match op with
  | .literal destination value =>
      let b := emit b s!"  ; %{destination} = const_u64 {value}"
      let b := emit b s!"  lddw r1, {hexImm value.toNat}"
      pure (storeTemp b tempBase destination "r1")
  | .loadParam destination dataOffset =>
      match inlineCtx with
      | some ctx =>
          -- pureFn param access: remap offset → pre-copied param slot.
          -- The param slot lives at `paramBase + idx`; the destination is a
          -- body temp at `tempBase + destination` (disjoint regions).
          let some idx := paramIndexByOffset ctx.fn.params dataOffset |
            return ← asmError
              s!"S1b inlined loadParam offset {dataOffset} is not a fn param"
          let b := emit b s!"  ; %{destination} = fn_param[{idx}] (offset {dataOffset})"
          let b := loadTemp b "r1" ctx.paramBase idx
          pure (storeTemp b tempBase destination "r1")
      | none =>
          let b := emit b s!"  ; %{destination} = load_u64_le(instruction_data + {dataOffset})"
          let b := emit b s!"  ldxdw r1, [r6 + INSTRUCTION_DATA + {dataOffset}]"
          pure (storeTemp b tempBase destination "r1")
  | .narrowLoadParam bitWidth destination dataOffset =>
      if bitWidth > 64 then
        let nLimbs := limbCountOfBitWidth bitWidth
        match inlineCtx with
        | some _ =>
            return ← asmError "S1b multiword narrowLoadParam not supported inlined"
        | none =>
            pure (emitMultiwordMemLoad b tempBase destination nLimbs "INSTRUCTION_DATA"
              dataOffset s!"%{destination} = load_u{bitWidth}_le(instruction_data + {dataOffset})")
      else match inlineCtx with
      | some ctx =>
          -- pureFn params are already width-normalized temps; remap like loadParam.
          let some idx := paramIndexByOffset ctx.fn.params dataOffset |
            return ← asmError
              s!"S1b inlined narrowLoadParam offset {dataOffset} is not a fn param"
          let b := emit b
            s!"  ; %{destination} = fn_param[{idx}] u{bitWidth} (offset {dataOffset})"
          let b := loadTemp b "r1" ctx.paramBase idx
          pure (storeTemp b tempBase destination "r1")
      | none =>
          let mnem := narrowLoadMnemonic bitWidth
          let b := emit b
            s!"  ; %{destination} = load_u{bitWidth}_le(instruction_data + {dataOffset})"
          let b := emit b s!"  {mnem} r1, [r6 + INSTRUCTION_DATA + {dataOffset}]"
          pure (storeTemp b tempBase destination "r1")
  | .loadState destination accountIndex byteOffset =>
      unless accountIndex == 0 do
        return ← asmError "S1b loadState supports only account[0]"
      let b := emit b s!"  ; %{destination} = load_u64_le(account[0].data + {byteOffset})"
      let b := emit b s!"  ldxdw r1, [r6 + ACC0_DATA + {byteOffset}]"
      pure (storeTemp b tempBase destination "r1")
  | .narrowLoadState bitWidth destination accountIndex byteOffset =>
      unless accountIndex == 0 do
        return ← asmError "S1b narrowLoadState supports only account[0]"
      if bitWidth > 64 then
        let nLimbs := limbCountOfBitWidth bitWidth
        pure (emitMultiwordMemLoad b tempBase destination nLimbs "ACC0_DATA" byteOffset
          s!"%{destination} = load_u{bitWidth}_le(account[0].data + {byteOffset})")
      else
        let mnem := narrowLoadMnemonic bitWidth
        let b := emit b
          s!"  ; %{destination} = load_u{bitWidth}_le(account[0].data + {byteOffset})"
        let b := emit b s!"  {mnem} r1, [r6 + ACC0_DATA + {byteOffset}]"
        pure (storeTemp b tempBase destination "r1")
  | .checkedAdd destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_add_u64 %{lhs}, %{rhs}"
      pure (emitCheckedAdd b tempBase destination lhs rhs errorCode)
  | .checkedSub destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_sub_u64 %{lhs}, %{rhs}"
      pure (emitCheckedSub b tempBase destination lhs rhs errorCode)
  | .checkedMul destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_mul_u64 %{lhs}, %{rhs}"
      pure (emitCheckedMul b tempBase destination lhs rhs errorCode)
  | .checkedDiv destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_div_u64 %{lhs}, %{rhs}"
      pure (emitCheckedDiv b tempBase destination lhs rhs errorCode)
  | .checkedMod destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_rem_u64 %{lhs}, %{rhs}"
      pure (emitCheckedMod b tempBase destination lhs rhs errorCode)
  | .signedCheckedAdd destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_add_i64 %{lhs}, %{rhs}"
      pure (emitSignedCheckedAdd b tempBase destination lhs rhs errorCode)
  | .signedCheckedSub destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_sub_i64 %{lhs}, %{rhs}"
      pure (emitSignedCheckedSub b tempBase destination lhs rhs errorCode)
  | .signedCheckedMul destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_mul_i64 %{lhs}, %{rhs}"
      pure (emitSignedCheckedMul b tempBase destination lhs rhs errorCode)
  | .signedCheckedDiv destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_div_i64 %{lhs}, %{rhs}"
      pure (emitSignedCheckedDiv b tempBase destination lhs rhs errorCode)
  | .signedCheckedMod destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_rem_i64 %{lhs}, %{rhs}"
      pure (emitSignedCheckedMod b tempBase destination lhs rhs errorCode)
  | .checkedNeg destination source errorCode =>
      let b := emit b s!"  ; %{destination} = checked_neg_i64 %{source}"
      pure (emitCheckedNeg b tempBase destination source errorCode)
  | .signedCompare destination lhs rhs op =>
      let b := emit b s!"  ; %{destination} = cmp_i64 %{lhs}, %{rhs}"
      pure (emitSignedCompare b tempBase destination lhs rhs op)
  | .checkedSar destination lhs rhs shiftError =>
      let b := emit b s!"  ; %{destination} = sar_i64 %{lhs}, %{rhs}"
      pure (emitCheckedSar b tempBase destination lhs rhs shiftError)
  | .bitAnd destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitand_u64 %{lhs}, %{rhs}"
      let b := loadTemp b "r1" tempBase lhs
      let b := loadTemp b "r2" tempBase rhs
      let b := emit b "  and64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .bitOr destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitor_u64 %{lhs}, %{rhs}"
      let b := loadTemp b "r1" tempBase lhs
      let b := loadTemp b "r2" tempBase rhs
      let b := emit b "  or64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .bitXor destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitxor_u64 %{lhs}, %{rhs}"
      let b := loadTemp b "r1" tempBase lhs
      let b := loadTemp b "r2" tempBase rhs
      let b := emit b "  xor64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .bitNot destination source =>
      let b := emit b s!"  ; %{destination} = bitnot_u64 %{source}"
      let b := loadTemp b "r1" tempBase source
      let b := emit b "  lddw r2, 0xffffffffffffffff"
      let b := emit b "  xor64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .checkedShl destination lhs rhs shiftError overflowError =>
      let b := emit b s!"  ; %{destination} = shl_u64 %{lhs}, %{rhs}"
      pure (emitCheckedShl b tempBase destination lhs rhs shiftError overflowError)
  | .checkedShr destination lhs rhs shiftError =>
      let b := emit b s!"  ; %{destination} = shr_u64 %{lhs}, %{rhs}"
      pure (emitCheckedShr b tempBase destination lhs rhs shiftError)
  | .narrowCheckedAdd bitWidth destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_add_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitNarrowCheckedAdd b tempBase destination lhs rhs errorCode bitWidth)
  | .narrowCheckedSub bitWidth destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_sub_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitNarrowCheckedSub b tempBase destination lhs rhs errorCode bitWidth)
  | .narrowCheckedMul bitWidth destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_mul_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitNarrowCheckedMul b tempBase destination lhs rhs errorCode bitWidth)
  | .narrowCheckedDiv bitWidth destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_div_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitNarrowCheckedDiv b tempBase destination lhs rhs errorCode bitWidth)
  | .narrowCheckedMod bitWidth destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_rem_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitNarrowCheckedMod b tempBase destination lhs rhs errorCode bitWidth)
  | .narrowBitAnd bitWidth destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitand_u{bitWidth} %{lhs}, %{rhs}"
      if bitWidth > 64 then
        pure (emitMultiwordBitOp b tempBase destination lhs rhs
          (limbCountOfBitWidth bitWidth) "and64")
      else
        let b := loadTemp b "r1" tempBase lhs
        let b := loadTemp b "r2" tempBase rhs
        let b := emit b "  and64 r1, r2"
        pure (storeTemp b tempBase destination "r1")
  | .narrowBitOr bitWidth destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitor_u{bitWidth} %{lhs}, %{rhs}"
      if bitWidth > 64 then
        pure (emitMultiwordBitOp b tempBase destination lhs rhs
          (limbCountOfBitWidth bitWidth) "or64")
      else
        let b := loadTemp b "r1" tempBase lhs
        let b := loadTemp b "r2" tempBase rhs
        let b := emit b "  or64 r1, r2"
        pure (storeTemp b tempBase destination "r1")
  | .narrowBitXor bitWidth destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitxor_u{bitWidth} %{lhs}, %{rhs}"
      if bitWidth > 64 then
        pure (emitMultiwordBitOp b tempBase destination lhs rhs
          (limbCountOfBitWidth bitWidth) "xor64")
      else
        let b := loadTemp b "r1" tempBase lhs
        let b := loadTemp b "r2" tempBase rhs
        let b := emit b "  xor64 r1, r2"
        pure (storeTemp b tempBase destination "r1")
  | .narrowBitNot bitWidth destination source =>
      let b := emit b s!"  ; %{destination} = bitnot_u{bitWidth} %{source}"
      pure (emitNarrowBitNot b tempBase destination source bitWidth)
  | .narrowCheckedShl bitWidth destination lhs rhs shiftError overflowError =>
      let b := emit b s!"  ; %{destination} = shl_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitNarrowCheckedShl b tempBase destination lhs rhs shiftError overflowError
        bitWidth)
  | .narrowCheckedShr bitWidth destination lhs rhs shiftError =>
      let b := emit b s!"  ; %{destination} = shr_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitNarrowCheckedShr b tempBase destination lhs rhs shiftError bitWidth)
  | .boolNot destination source =>
      let b := emit b s!"  ; %{destination} = bool_not %{source}"
      let b := loadTemp b "r1" tempBase source
      let b := emit b "  xor64 r1, 1"
      pure (storeTemp b tempBase destination "r1")
  | .boolAnd destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bool_and %{lhs}, %{rhs}"
      let b := loadTemp b "r1" tempBase lhs
      let b := loadTemp b "r2" tempBase rhs
      let b := emit b "  and64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .boolOr destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bool_or %{lhs}, %{rhs}"
      let b := loadTemp b "r1" tempBase lhs
      let b := loadTemp b "r2" tempBase rhs
      let b := emit b "  or64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .zeroState accountIndex byteOffset =>
      unless accountIndex == 0 do
        return ← asmError "S1b zeroState supports only account[0]"
      let b := emit b s!"  ; zero_u64_le account[0].data + {byteOffset}"
      let b := emit b "  lddw r1, 0"
      pure (emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset}], r1")
  | .narrowZeroState bitWidth accountIndex byteOffset =>
      unless accountIndex == 0 do
        return ← asmError "S1b narrowZeroState supports only account[0]"
      if bitWidth > 64 then
        pure (emitMultiwordZeroState b (limbCountOfBitWidth bitWidth) byteOffset)
      else
        let mnem := narrowImmStoreMnemonic bitWidth
        let b := emit b s!"  ; zero_u{bitWidth}_le account[0].data + {byteOffset}"
        pure (emit b s!"  {mnem} [r6 + ACC0_DATA + {byteOffset}], 0")
  | .storeState accountIndex byteOffset value =>
      unless accountIndex == 0 do
        return ← asmError "S1b storeState supports only account[0]"
      let b := emit b s!"  ; store_u64_le account[0].data + {byteOffset}, %{value}"
      let b := loadTemp b "r1" tempBase value
      pure (emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset}], r1")
  | .narrowStoreState bitWidth accountIndex byteOffset value =>
      unless accountIndex == 0 do
        return ← asmError "S1b narrowStoreState supports only account[0]"
      if bitWidth > 64 then
        pure (emitMultiwordMemStore b tempBase value (limbCountOfBitWidth bitWidth) byteOffset
          s!"store_u{bitWidth}_le account[0].data + {byteOffset}, %{value}")
      else
        let mnem := narrowStoreMnemonic bitWidth
        let b := emit b
          s!"  ; store_u{bitWidth}_le account[0].data + {byteOffset}, %{value}"
        let b := loadTemp b "r1" tempBase value
        pure (emit b s!"  {mnem} [r6 + ACC0_DATA + {byteOffset}], r1")
  | .storeStateMulti entries => do
      let mut b := emit b s!"  ; store_multi_le [{entries.size}] (atomic aggregate)"
      for (accountIndex, byteOffset, byteWidth, value) in entries do
        unless accountIndex == 0 do
          return ← asmError "S1b storeStateMulti supports only account[0]"
        if byteWidth == 8 then
          let b' := emit b
            s!"  ; store_u64_le account[0].data + {byteOffset}, %{value}"
          let b' := loadTemp b' "r1" tempBase value
          b := emit b' s!"  stxdw [r6 + ACC0_DATA + {byteOffset}], r1"
        else if byteWidth > 8 then
          let bitWidth := byteWidth * 8
          b := emitMultiwordMemStore b tempBase value
            (limbCountOfBitWidth bitWidth) byteOffset
            s!"store_u{bitWidth}_le account[0].data + {byteOffset}, %{value}"
        else
          let bitWidth := byteWidth * 8
          let mnem := narrowStoreMnemonic bitWidth
          let b' := emit b
            s!"  ; store_u{bitWidth}_le account[0].data + {byteOffset}, %{value}"
          let b' := loadTemp b' "r1" tempBase value
          b := emit b' s!"  {mnem} [r6 + ACC0_DATA + {byteOffset}], r1"
      pure b
  | .setHeader accountIndex byteOffset value =>
      unless accountIndex == 0 do
        return ← asmError "S1b setHeader supports only account[0]"
      let b := emit b s!"  ; store header u64 @ {byteOffset}"
      let b := emit b s!"  lddw r1, {hexImm value.toNat}"
      pure (emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset}], r1")
  | .setReturnData byteLen value =>
      match inlineCtx with
      | some ctx =>
          let b := emit b s!"  ; fn ret u{byteLen*8} %{value} → caller dest"
          let b := loadTemp b "r1" tempBase value
          pure (storeTempAbs b ctx.retDestAbs "r1")
      | none =>
          let nBuf := if byteLen > 8 then byteLen / 8 else 1
          let (b, retTemp) := allocTemps b nBuf
          let b := emit b s!"  ; set_return_data_u{byteLen*8}_le %{value}"
          pure (emitSetReturnDataBytes b tempBase value retTemp byteLen)
  | .setReturnDataBool value =>
      match inlineCtx with
      | some ctx =>
          let b := emit b s!"  ; fn ret bool %{value} → caller dest"
          let b := loadTemp b "r1" tempBase value
          pure (storeTempAbs b ctx.retDestAbs "r1")
      | none =>
          let (b, retTemp) := allocTemps b 1
          let b := emit b s!"  ; set_return_data_bool %{value}"
          pure (emitSetReturnDataBool b tempBase value retTemp)
  | .setReturnDataMulti values =>
      match inlineCtx with
      | some _ =>
          -- pureFn cannot return aggregates; inlined path is unreachable.
          asmError "S1b setReturnDataMulti is not admitted inside pureFn inline"
      | none =>
          unless values.size > 0 && values.size ≤ 8 do
            return ← asmError "S1b setReturnDataMulti leaf count must be in 1..8"
          let (b, retTemp) := allocTemps b values.size
          let b := emit b s!"  ; set_return_data_multi_le [{values.size}]"
          pure (emitSetReturnDataMulti b tempBase values retTemp)
  | .compare destination lhs rhs op =>
      let b := emit b s!"  ; %{destination} = cmp %{lhs}, %{rhs}"
      pure (emitCompare b tempBase destination lhs rhs op)
  | .wideCompare bitWidth destination lhs rhs op =>
      let b := emit b s!"  ; %{destination} = cmp_u{bitWidth} %{lhs}, %{rhs}"
      pure (emitMultiwordCompare b tempBase destination lhs rhs
        (limbCountOfBitWidth bitWidth) op)
  | .assert condition errorCode =>
      let (b, errLab) := fresh b "err_assert"
      let (b, okLab) := fresh b "ok_assert"
      let b := emit b s!"  ; assert %{condition}"
      let b := loadTemp b "r1" tempBase condition
      let b := emit b s!"  jeq r1, 0, {errLab}"
      let b := emit b s!"  ja {okLab}"
      let b := emitErrorExit b errLab errorCode
      pure (emit b s!"{okLab}:")
  | .returnNone =>
      match inlineCtx with
      | some ctx =>
          -- IR appends hard-exit markers after setReturnData* in closed arms.
          -- A fn-level `return` must skip the remaining inlined body (the
          -- value was already copied to the caller dest), so jump to the
          -- inline-instance end label instead of falling through.
          pure (emit b s!"  ja {ctx.fnEndLabel}")
      | none =>
          let b := emit b "  ; exit success"
          let b := emit b "  lddw r0, 0"
          pure (emit b "  exit")
  | .revertError errorIndex _args =>
      let code := declaredErrorBase + errorIndex
      let b := emit b s!"  ; program_error declared index {errorIndex}"
      pure (emitProgramErrorInline b code)
  | .ifRegion condition thenOps elseOps =>
      let (b, elseLab) := fresh b "if_else"
      let (b, endLab) := fresh b "if_end"
      let b := emit b s!"  ; if %{condition}"
      let b := loadTemp b "r1" tempBase condition
      let b := emit b s!"  jeq r1, 0, {elseLab}"
      let b ← emitOperations b ir tempBase inlineCtx inlineDepth thenOps
      let b := emit b s!"  ja {endLab}"
      let b := emit b s!"{elseLab}:"
      let b ← emitOperations b ir tempBase inlineCtx inlineDepth elseOps
      pure (emit b s!"{endLab}:")
  | .switchRegion scrutinee cases defaultOps =>
      let mut b := emit b s!"  ; switch %{scrutinee}"
      b := loadTemp b "r1" tempBase scrutinee
      -- Pre-allocate case labels for the jump table.
      let mut caseLabs : Array String := #[]
      for _ in [:cases.size] do
        let (b', lab) := fresh b "sw_case"
        b := b'
        caseLabs := caseLabs.push lab
      let (b', endLab) := fresh b "sw_end"
      b := b'
      for i in [:cases.size] do
        let (caseValue, _) := cases[i]!
        let lab := caseLabs[i]!
        b := emit b s!"  lddw r2, {hexImm caseValue.toNat}"
        b := emit b s!"  jeq r1, r2, {lab}"
      b ← emitOperations b ir tempBase inlineCtx inlineDepth defaultOps
      b := emit b s!"  ja {endLab}"
      for i in [:cases.size] do
        let (_, ops) := cases[i]!
        let lab := caseLabs[i]!
        b := emit b s!"{lab}:"
        b ← emitOperations b ir tempBase inlineCtx inlineDepth ops
        b := emit b s!"  ja {endLab}"
      pure (emit b s!"{endLab}:")
  | .forRegion varTemp _initial counterTemp maxIterations condOps cond bodyOps
        boundOps counterNext updateOps update =>
      let (b, headerLab) := fresh b "for_header"
      let (b, endLab) := fresh b "for_end"
      let b := emit b s!"  ; for max={maxIterations} var=%{varTemp} counter=%{counterTemp}"
      let b := emit b s!"{headerLab}:"
      let b ← emitOperations b ir tempBase inlineCtx inlineDepth condOps
      let b := loadTemp b "r1" tempBase cond
      let b := emit b s!"  jeq r1, 0, {endLab}"
      let b ← emitOperations b ir tempBase inlineCtx inlineDepth bodyOps
      let b ← emitOperations b ir tempBase inlineCtx inlineDepth boundOps
      let b ← emitOperations b ir tempBase inlineCtx inlineDepth updateOps
      -- Rebind induction + completed-iteration counter for the next header.
      let b := emit b "  ; rebind induction / counter"
      let b := loadTemp b "r1" tempBase update
      let b := storeTemp b tempBase varTemp "r1"
      let b := loadTemp b "r1" tempBase counterNext
      let b := storeTemp b tempBase counterTemp "r1"
      let b := emit b s!"  ja {headerLab}"
      pure (emit b s!"{endLab}:")
  | .callFn fnIndex destination args =>
      unless fnIndex < ir.fns.size do
        return ← asmError s!"S1b callFn index {fnIndex} out of range"
      unless inlineDepth ≤ ir.fns.size do
        return ← asmError "S1b callFn inline depth exceeded (cycle guard)"
      let fn := ir.fns[fnIndex]!
      unless args.size == fn.params.size do
        return ← asmError s!"S1b callFn arity mismatch for {fn.name}"
      let fnTemps := tempCountOf fn.operations
      -- Disjoint regions: param slots at calleeBase+0..arity-1 and body
      -- temps at calleeBase+arity+0..fnTemps-1. Body ops may write any temp
      -- 0..n-1; sharing the region with the param slots would let e.g. a
      -- loadParam remap or literal clobber an argument (S3b regression).
      let (b0, calleeBase) := allocTemps b (fn.params.size + fnTemps)
      let (b1, endLab) := fresh b0 "fn_end"
      let mut b := emit b1 s!"  ; call {fn.name} → %{destination} (inline base {calleeBase})"
      -- Param copy: caller arg temps → callee param slots 0..arity-1.
      for i in [:args.size] do
        b := loadTemp b "r1" tempBase args[i]!
        b := storeTempAbs b (calleeBase + i) "r1"
      let ctx : InlineCtx := {
        retDestAbs := tempBase + destination
        fn
        fnEndLabel := endLab
        paramBase := calleeBase
      }
      b ← emitOperations b ir (calleeBase + fn.params.size) (some ctx)
        (inlineDepth + 1) fn.operations
      pure (emit b s!"{endLab}:")
  | .emitEvent eventIndex args =>
      unless eventIndex < ir.sourcePlan.events.size do
        return ← asmError s!"S1b emitEvent index {eventIndex} out of range"
      let eventName := ir.sourcePlan.events[eventIndex]!.name
      let n := args.size
      -- Layout: keySlot, data[n] (arg0 at highest index for contiguous LE),
      -- then 4 descriptor u64s (keyPtr, keyLen, dataPtr, dataLen).
      let need := n + 5
      let (b0, bufBase) := allocTemps b need
      let keySlot := bufBase
      let mut b := emit b0 s!"  ; emit_event {eventName} (index {eventIndex}, {n} args) via sol_log_data"
      -- key = eventIndex as u64 LE
      b := emit b s!"  lddw r1, {hexImm eventIndex}"
      b := storeTempAbs b keySlot "r1"
      -- Pack args so arg0 sits at the lowest address among data slots
      -- (highest temp index). Memory [dataPtr, dataPtr+8n) is contiguous LE.
      for i in [:n] do
        let slot := bufBase + n - i
        b := loadTemp b "r1" tempBase args[i]!
        b := storeTempAbs b slot "r1"
      let dataHighSlot := if n == 0 then bufBase else bufBase + n
      let descKeyPtr := bufBase + n + 1
      let descKeyLen := bufBase + n + 2
      let descDataPtr := bufBase + n + 3
      let descDataLen := bufBase + n + 4
      -- keyPtr
      b := emit b "  mov64 r1, r10"
      b := emit b s!"  add64 r1, -{tempStackOff keySlot}"
      b := storeTempAbs b descKeyPtr "r1"
      -- keyLen = 8
      b := emit b "  lddw r1, 8"
      b := storeTempAbs b descKeyLen "r1"
      -- dataPtr (lowest address of packed args; empty → keySlot, len 0)
      b := emit b "  mov64 r1, r10"
      b := emit b s!"  add64 r1, -{tempStackOff dataHighSlot}"
      b := storeTempAbs b descDataPtr "r1"
      -- dataLen = 8*n
      b := emit b s!"  lddw r1, {hexImm (8 * n)}"
      b := storeTempAbs b descDataLen "r1"
      -- r1 = &SolBytes[2], r2 = 2
      b := emit b "  mov64 r1, r10"
      b := emit b s!"  add64 r1, -{tempStackOff descKeyPtr}"
      b := emit b "  lddw r2, 2"
      pure (emit b "  call sol_log_data")
  | .externalCall .. =>
      return ← asmError
        "legacy Solana profiles do not emit external-call stubs; use a versioned CPI profile"
  | .schedule .. =>
      return ← asmError
        "legacy Solana profiles do not emit schedule stubs"

/-- Emit a sequence of operations, threading the assembly buffer. -/
private partial def emitOperations (b0 : AsmBuf) (ir : IR) (tempBase : Nat)
    (inlineCtx : Option InlineCtx) (inlineDepth : Nat) (ops : Array Operation) :
    CompileResult AsmBuf := do
  let mut b := b0
  for op in ops do
    b ← emitOperation b ir tempBase inlineCtx inlineDepth op
  pure b
end

private def emitHandlerBody (b0 : AsmBuf) (ir : IR) (handler : HandlerIR) :
    CompileResult AsmBuf := do
  let errLab := s!"err_check_{asmLabel handler.name}"
  let mut b := b0
  for check in handler.checks do
    b ← emitCheck b check errLab
  b ← emitOperations b ir 0 none 0 handler.operations
  -- Fallthrough success after set_return_data (syscall does not halt).
  b := emit b "  lddw r0, 0"
  b := emit b "  exit"
  b := emitErrorExit b errLab 1
  pure b

/-- Emit entrypoint discriminator dispatch for all handlers. -/
private def emitDispatch (b0 : AsmBuf) (handlers : Array HandlerIR) :
    CompileResult AsmBuf := do
  let mut b := emit b0 "entrypoint:"
  b := emit b "  mov64 r6, r1"
  -- V1 single-state ABI: require exactly one non-duplicate account before any
  -- fixed INSTRUCTION_*/ACC0_* absolute load (layout assumes one full account).
  b := emitAccountListShapeChecks b "err_unknown_disc"
  -- Require at least 8 bytes of instruction data for the discriminator.
  b := emit b "  ; guard: instruction_data_len >= 8"
  b := emit b "  ldxdw r1, [r6 + INSTRUCTION_DATA_LEN]"
  b := emit b "  jlt r1, 8, err_unknown_disc"
  b := emit b "  ; load 8-byte instruction discriminator (LE u64)"
  b := emit b "  ldxdw r1, [r6 + INSTRUCTION_DATA]"
  for handler in handlers do
    let disc ← discriminatorToLeU64V1 handler.discriminator
    let lab := asmLabel handler.name
    b := emit b s!"  lddw r2, {hexImm disc.toNat}"
    b := emit b s!"  jeq r1, r2, {lab}"
  -- fallthrough: unknown discriminator / account-list shape failure → Custom(1)
  b := emit b "err_unknown_disc:"
  b := emit b "  lddw r0, 1"
  b := emit b "  exit"
  pure b

/-- Public S1b emitter: typed `IR` → default-dialect SBPF assembly text. -/
def emitSbpfAsmV1 (ir : IR) : CompileResult String := do
  validateIR ir
  unless ir.stateAccount.index == 0 do
    return ← asmError "S1b requires state account index 0"
  let layout := computeInputLayoutV1 ir.stateAccount.exactDataLen
  let mut b : AsmBuf := { text := renderLayoutEqu layout, seq := 0, cursor := 0 }
  b := emit b ".globl entrypoint"
  b := emitBlank b
  b ← emitDispatch b ir.handlers
  b := emitBlank b
  for handler in ir.handlers do
    let lab := asmLabel handler.name
    -- cursor0 = canonical handler temp count; ret/event/inline allocate above.
    let cursor0 := tempCountOf handler.operations
    b := { b with cursor := cursor0 }
    b := emit b s!"{lab}:"
    b := emit b s!"  ; handler {handler.name} (temps={cursor0})"
    b ← emitHandlerBody b ir handler
    -- Frame budget: (cursorFinal+1)*8 ≤ 4096.
    let frameBytes := (b.cursor + 1) * 8
    unless frameBytes ≤ maxSbpfStackBytesV1 do
      return ← asmError
        s!"S1b frame budget exceeded for handler '{handler.name}': {frameBytes} bytes > {maxSbpfStackBytesV1}"
    b := emitBlank b
  pure b.text

/-- Convenience: emit legacy SBPF assembly from a capability-bound IR path.
    CPI profile must not call this (product assembly is product-core owned). -/
def emitSbpfAsmFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult String := do
  let ir ← legacyIrFromCapabilityV1 capability
  emitSbpfAsmV1 ir

/-- ELF-profile product emit: assembly text + plan + IDL. -/
private def emitElfFromIR
    (capability : ResolvedEngineeringBuildV1) (ir : IR) :
    CompileResult (Array OutputFile) := do
  let base ← emitPlanAndIdlFromIR capability ir
  let asm ← emitSbpfAsmV1 ir
  pure <| base.push {
    path := s!"{ir.name}.s"
    mediaType := "text/x-sbpf-asm"
    contents := asm
  }

private def buildUnknownProfileFail (profile : CodegenProfileId) :
    CompileResult (Array OutputFile) :=
  throw <| .planInvariant .solana
    s!"unknown Solana codegen profile '{profile}' (exhaustive plan/elf/cpi only)"

/-- Capability-gated public materialize entry (S6 / #125).
    Exhaustive profile dispatch:
    * `solana-sbpf-plan-v1` → legacy plan+IDL only
    * `solana-sbpf-elf-v1` → legacy plan+IDL+`.s`
    * `solana-sbpf-cpi-elf-v1` → product base files (CpiV1 product core)
    * unknown → fail closed (no silent else fallback)
    CPI never enters legacy Plan/IR/emitter. Lives here (not EmitIRV1) so the
    `.s` branch can call `emitSbpfAsmV1` without a circular import. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfPlanV1 then
    let ir ← legacyIrFromCapabilityV1 capability
    emitPlanAndIdlFromIR capability ir
  else if profile == CodegenProfileId.solanaSbpfElfV1 then
    let ir ← legacyIrFromCapabilityV1 capability
    emitElfFromIR capability ir
  else if profile == CodegenProfileId.solanaSbpfCpiElfV1 then
    -- Product core sole base-file authority; never legacy emit.
    CpiV1.productBaseFilesFromCapabilityV1 capability
  else
    buildUnknownProfileFail profile

end ProofForgeV2.Targets.Solana
