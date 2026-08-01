import ProofForgeV2.Targets.Solana.EmitIRV1

/-!
# Solana EmitSbpfAsmV1 — typed IR → SBPF assembly (.s) text (S1b)

Full default-dialect Operation surface emitter. Emits SBPF assembly consumable
by the pinned `sbpf` assembler; does **not** invoke external tools or produce
ELF. No blueshift extension mnemonics (`hor64`/`lmul64`/`uhmul64`/`udiv64`/
`urem64`/`shmul64`/`srem64`).

Authority: typed `IR` / `Operation` / `Check` from `EmitIRV1` (not `.sbpf-plan`
text). Product `buildFromCapability` publishes `.sbpf-plan` + IDL for the plan
profile and additionally `{name}.s` under `solana-sbpf-elf-v1`;
`.s` remains additive.

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

Checks: instruction_data_len, owner==current_program, data_len, signer,
writable, headerEquals (account[0] only).

Ops: literal, loadParam, loadState, checkedAdd/Sub/Mul/Div/Mod,
bitAnd/Or/Xor/Not, checkedShl/Shr, boolNot/And/Or, zeroState, storeState,
setHeader, setReturnData (u64 LE / bool), compare, assert, returnNone,
revertError, ifRegion, switchRegion, forRegion, callFn (inline expand),
emitEvent (`sol_log_data`).

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
      .compare destination .. | .callFn _ destination _ => some destination
  | _ => none

/-- Max destination+1 over an op sequence (canonical temp count). -/
private partial def tempCountOf (ops : Array Operation) : Nat :=
  ops.foldl (init := 0) fun acc op =>
    let acc := match opDestination? op with
      | some d => Nat.max acc (d + 1)
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

/-- Emit check instructions; on failure jump to `errLab` (must lddw/exit). -/
private def emitCheck (b : AsmBuf) (check : Check) (errLab : String) :
    CompileResult AsmBuf := do
  match check with
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

/-- Narrow checked_add: 64-bit add then high bits above `bitWidth` must be zero. -/
private def emitNarrowCheckedAdd (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  Id.run do
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
  Id.run do
    let _ := bitWidth
    emitCheckedSub b tempBase dest lhs rhs errorCode

/-- Narrow checked_mul: 64-bit mul then high bits above `bitWidth` must be zero. -/
private def emitNarrowCheckedMul (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  Id.run do
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

/-- Narrow checked_div: zero guard only; quotient auto in-range for UInt. -/
private def emitNarrowCheckedDiv (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  Id.run do
    let _ := bitWidth
    emitCheckedDiv b tempBase dest lhs rhs errorCode

/-- Narrow checked_mod: zero guard only; remainder auto in-range. -/
private def emitNarrowCheckedMod (b : AsmBuf) (tempBase dest lhs rhs errorCode bitWidth : Nat) :
    AsmBuf :=
  Id.run do
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
  Id.run do
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
  let b := loadTemp b "r1" tempBase valueTemp
  let off := tempStackOff retTemp
  let b :=
    match byteLen with
    | 1 => emit b s!"  stxb [r10 - {off}], r1"
    | 2 => emit b s!"  stxh [r10 - {off}], r1"
    | 4 => emit b s!"  stxw [r10 - {off}], r1"
    | _ =>
        let b := storeTempAbs b retTemp "r1"
        b
  let b := emit b "  mov64 r1, r10"
  let b := emit b s!"  add64 r1, -{off}"
  let b := emit b s!"  lddw r2, {byteLen}"
  let b := emit b "  call sol_set_return_data"
  b

/-- Stash a u64 at absolute temp `retTemp` and call `sol_set_return_data`. -/
private def emitSetReturnDataU64 (b : AsmBuf) (tempBase valueTemp retTemp : Nat) :
    AsmBuf :=
  emitSetReturnDataBytes b tempBase valueTemp retTemp 8

/-- Stash a bool as a single byte and call `sol_set_return_data` with len=1. -/
private def emitSetReturnDataBool (b : AsmBuf) (tempBase valueTemp retTemp : Nat) :
    AsmBuf :=
  emitSetReturnDataBytes b tempBase valueTemp retTemp 1

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

/-- Allocate `n` consecutive absolute temps from the cursor; returns base. -/
private def allocTemps (b : AsmBuf) (n : Nat) : AsmBuf × Nat :=
  let base := b.cursor
  ({ b with cursor := b.cursor + n }, base)

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
      match inlineCtx with
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
      let b := loadTemp b "r1" tempBase lhs
      let b := loadTemp b "r2" tempBase rhs
      let b := emit b "  and64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .narrowBitOr bitWidth destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitor_u{bitWidth} %{lhs}, %{rhs}"
      let b := loadTemp b "r1" tempBase lhs
      let b := loadTemp b "r2" tempBase rhs
      let b := emit b "  or64 r1, r2"
      pure (storeTemp b tempBase destination "r1")
  | .narrowBitXor bitWidth destination lhs rhs =>
      let b := emit b s!"  ; %{destination} = bitxor_u{bitWidth} %{lhs}, %{rhs}"
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
      let mnem := narrowStoreMnemonic bitWidth
      let b := emit b
        s!"  ; store_u{bitWidth}_le account[0].data + {byteOffset}, %{value}"
      let b := loadTemp b "r1" tempBase value
      pure (emit b s!"  {mnem} [r6 + ACC0_DATA + {byteOffset}], r1")
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
          let (b, retTemp) := allocTemps b 1
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
  | .compare destination lhs rhs op =>
      let b := emit b s!"  ; %{destination} = cmp %{lhs}, %{rhs}"
      pure (emitCompare b tempBase destination lhs rhs op)
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
  -- fallthrough: unknown discriminator
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

/-- Convenience: emit assembly from a capability-bound IR build path. -/
def emitSbpfAsmFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult String := do
  let ir ← irFromCapability capability
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

/-- Capability-gated public materialize entry (S6).
    Profile `solana-sbpf-elf-v1` publishes `.s` + plan + IDL; the default
    `solana-sbpf-plan-v1` stays plan+IDL only. Lives here (not EmitIRV1) so the
    `.s` branch can call `emitSbpfAsmV1` without a circular import. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfElfV1 then
    emitElfFromIR capability ir
  else
    emitPlanAndIdlFromIR capability ir

end ProofForgeV2.Targets.Solana
