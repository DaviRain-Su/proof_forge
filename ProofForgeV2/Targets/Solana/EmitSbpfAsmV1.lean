import ProofForgeV2.Targets.Solana.EmitIRV1

/-!
# Solana EmitSbpfAsmV1 — typed IR → SBPF assembly (.s) text (S1a)

Counter-subset emitter only. Emits default-dialect SBPF assembly consumable by
the pinned `sbpf` assembler; does **not** invoke external tools or produce ELF.

Authority: typed `IR` / `Operation` / `Check` from `EmitIRV1` (not `.sbpf-plan`
text). Product `emitFromIR` is unchanged and still publishes `.sbpf-plan` + IDL.

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
* `r10` = frame pointer; IR temps live at `[r10 - 8*(t+1)]`
* `r0` = exit code / syscall result
* `r1`–`r5`, `r7`–`r9` = scratch

## S1a support surface

Checks: instruction_data_len, owner==current_program, data_len, signer,
writable, headerEquals.

Ops: literal, loadParam, loadState, checkedAdd/Sub, zeroState, storeState,
setHeader, setReturnData (u64 LE), setReturnDataBool (1 byte), compare,
assert, returnNone (exit 0), revertError (program_error code).

S1b (fail closed): mul/div/mod, shift/bit/bool ops, if/switch/for regions,
callFn, emitEvent, non-zero account indices, pureFn table.
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

/-- Stack offset (negative of frame) for IR temp `t`. -/
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
    return ← asmError s!"S1a discriminator must be 16 hex chars, got length {hex.length}"
  let chars := hex.toList
  let mut value : Nat := 0
  for i in [:8] do
    let some hi := hexDigitValue chars[2 * i]! |
      return ← asmError s!"S1a discriminator has non-hex at index {2 * i}"
    let some lo := hexDigitValue chars[2 * i + 1]! |
      return ← asmError s!"S1a discriminator has non-hex at index {2 * i + 1}"
    let byte := hi * 16 + lo
    value := value + byte * (Nat.pow 2 (8 * i))
  pure (UInt64.ofNat value)

/-- Sanitize a handler/fn name into an SBPF label identifier. -/
private def asmLabel (name : String) : String :=
  String.ofList (name.toList.map fun c =>
    if c.isAlphanum || c == '_' then c else '_')

private structure AsmBuf where
  text : String
  seq : Nat

private def emptyBuf : AsmBuf := ⟨"", 0⟩

private def emit (b : AsmBuf) (line : String) : AsmBuf :=
  { b with text := b.text ++ line ++ "\n" }

private def emitBlank (b : AsmBuf) : AsmBuf :=
  { b with text := b.text ++ "\n" }

private def fresh (b : AsmBuf) (labelPrefix : String) : AsmBuf × String :=
  let lab := s!"{labelPrefix}_{b.seq}"
  ({ b with seq := b.seq + 1 }, lab)

/-- Load IR temp `t` into register `rd`. -/
private def loadTemp (b : AsmBuf) (rd : String) (t : Nat) : AsmBuf :=
  emit b s!"  ldxdw {rd}, [r10 - {tempStackOff t}]"

/-- Store register `rs` into IR temp `t`. -/
private def storeTemp (b : AsmBuf) (t : Nat) (rs : String) : AsmBuf :=
  emit b s!"  stxdw [r10 - {tempStackOff t}], {rs}"

private def emitEqu (b : AsmBuf) (name : String) (value : Nat) : AsmBuf :=
  emit b s!".equ {name}, {hexImm value}"

private def renderLayoutEqu (layout : InputLayoutV1) : String :=
  let b0 := emptyBuf
  let b0 := emit b0 "; PROOF-FORGE-SBPF-ASM v1 (S1a Counter subset)"
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
        return ← asmError "S1a owner check supports only account[0]"
      -- Compare owner (32B) with PROGRAM_ID = input + INSTRUCTION_DATA + ix_len
      let b := emit b "  ; check account[0].owner == current_program"
      let b := emit b "  ldxdw r1, [r6 + INSTRUCTION_DATA_LEN]"
      let b := emit b "  mov64 r2, r6"
      let b := emit b "  add64 r2, INSTRUCTION_DATA"
      let b := emit b "  add64 r2, r1"
      -- r2 = program_id base; compare four u64 words
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
        return ← asmError "S1a data_len check supports only account[0]"
      let b := emit b s!"  ; check account[0].data_len == {bytes}"
      let b := emit b "  ldxdw r1, [r6 + ACC0_DATA_LEN]"
      let b := emit b s!"  jne r1, {bytes}, {errLab}"
      pure b
  | .signer accountIndex =>
      unless accountIndex == 0 do
        return ← asmError "S1a signer check supports only account[0]"
      let b := emit b "  ; check account[0].is_signer"
      let b := emit b "  ldxb r1, [r6 + ACC0_HEADER + 1]"
      let b := emit b s!"  jeq r1, 0, {errLab}"
      pure b
  | .writable accountIndex =>
      unless accountIndex == 0 do
        return ← asmError "S1a writable check supports only account[0]"
      let b := emit b "  ; check account[0].is_writable"
      let b := emit b "  ldxb r1, [r6 + ACC0_HEADER + 2]"
      let b := emit b s!"  jeq r1, 0, {errLab}"
      pure b
  | .headerEquals accountIndex byteOffset value =>
      unless accountIndex == 0 do
        return ← asmError "S1a headerEquals supports only account[0]"
      let b := emit b s!"  ; check header u64 @ {byteOffset} == 0x{natHexLower value.toNat}"
      let b := emit b s!"  ldxdw r1, [r6 + ACC0_DATA + {byteOffset}]"
      let b := emit b s!"  lddw r2, {hexImm value.toNat}"
      let b := emit b s!"  jne r1, r2, {errLab}"
      pure b

/-- Emit one comparison that writes 0/1 into dest temp. -/
private def emitCompare (b : AsmBuf) (dest lhs rhs : Nat) (op : ComparisonOp) :
    AsmBuf := Id.run do
  let (b, trueLab) := fresh b "cmp_true"
  let (b, doneLab) := fresh b "cmp_done"
  let b := loadTemp b "r1" lhs
  let b := loadTemp b "r2" rhs
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
  storeTemp b dest "r3"

/-- Emit checked_add: dest = lhs + rhs or program_error errorCode. -/
private def emitCheckedAdd (b : AsmBuf) (dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_add"
    let (b, okLab) := fresh b "ok_add"
    let b := loadTemp b "r1" lhs
    let b := loadTemp b "r2" rhs
    -- t = UInt64.max - rhs; if lhs > t then overflow
    let b := emit b "  lddw r3, 0xffffffffffffffff"
    let b := emit b "  sub64 r3, r2"
    let b := emit b s!"  jgt r1, r3, {errLab}"
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  add64 r4, r2"
    let b := storeTemp b dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Emit checked_sub: dest = lhs - rhs or program_error errorCode. -/
private def emitCheckedSub (b : AsmBuf) (dest lhs rhs errorCode : Nat) : AsmBuf :=
  Id.run do
    let (b, errLab) := fresh b "err_sub"
    let (b, okLab) := fresh b "ok_sub"
    let b := loadTemp b "r1" lhs
    let b := loadTemp b "r2" rhs
    let b := emit b s!"  jlt r1, r2, {errLab}"
    let b := emit b "  mov64 r4, r1"
    let b := emit b "  sub64 r4, r2"
    let b := storeTemp b dest "r4"
    let b := emit b s!"  ja {okLab}"
    let b := emitErrorExit b errLab errorCode
    emit b s!"{okLab}:"

/-- Stash a u64 at `[r10 - retSlot]` and call `sol_set_return_data`. -/
private def emitSetReturnDataU64 (b : AsmBuf) (valueTemp : Nat) (retSlot : Nat) :
    AsmBuf :=
  let b := loadTemp b "r1" valueTemp
  let b := emit b s!"  stxdw [r10 - {retSlot}], r1"
  let b := emit b "  mov64 r1, r10"
  let b := emit b s!"  add64 r1, -{retSlot}"
  let b := emit b "  lddw r2, 8"
  let b := emit b "  call sol_set_return_data"
  -- r0 clobbered; r6 assumed preserved across syscall
  b

/-- Stash a bool as a single byte and call `sol_set_return_data` with len=1. -/
private def emitSetReturnDataBool (b : AsmBuf) (valueTemp : Nat) (retSlot : Nat) :
    AsmBuf :=
  let b := loadTemp b "r1" valueTemp
  let b := emit b s!"  stxb [r10 - {retSlot}], r1"
  let b := emit b "  mov64 r1, r10"
  let b := emit b s!"  add64 r1, -{retSlot}"
  let b := emit b "  lddw r2, 1"
  let b := emit b "  call sol_set_return_data"
  b

private def emitOperation (b : AsmBuf) (op : Operation) (retSlot : Nat) :
    CompileResult AsmBuf := do
  match op with
  | .literal destination value =>
      let b := emit b s!"  ; %{destination} = const_u64 {value}"
      let b := emit b s!"  lddw r1, {hexImm value.toNat}"
      pure (storeTemp b destination "r1")
  | .loadParam destination dataOffset =>
      let b := emit b s!"  ; %{destination} = load_u64_le(instruction_data + {dataOffset})"
      let b := emit b s!"  ldxdw r1, [r6 + INSTRUCTION_DATA + {dataOffset}]"
      pure (storeTemp b destination "r1")
  | .loadState destination accountIndex byteOffset =>
      unless accountIndex == 0 do
        return ← asmError "S1a loadState supports only account[0]"
      let b := emit b s!"  ; %{destination} = load_u64_le(account[0].data + {byteOffset})"
      let b := emit b s!"  ldxdw r1, [r6 + ACC0_DATA + {byteOffset}]"
      pure (storeTemp b destination "r1")
  | .checkedAdd destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_add_u64 %{lhs}, %{rhs}"
      pure (emitCheckedAdd b destination lhs rhs errorCode)
  | .checkedSub destination lhs rhs errorCode =>
      let b := emit b s!"  ; %{destination} = checked_sub_u64 %{lhs}, %{rhs}"
      pure (emitCheckedSub b destination lhs rhs errorCode)
  | .zeroState accountIndex byteOffset =>
      unless accountIndex == 0 do
        return ← asmError "S1a zeroState supports only account[0]"
      let b := emit b s!"  ; zero_u64_le account[0].data + {byteOffset}"
      let b := emit b "  lddw r1, 0"
      pure (emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset}], r1")
  | .storeState accountIndex byteOffset value =>
      unless accountIndex == 0 do
        return ← asmError "S1a storeState supports only account[0]"
      let b := emit b s!"  ; store_u64_le account[0].data + {byteOffset}, %{value}"
      let b := loadTemp b "r1" value
      pure (emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset}], r1")
  | .setHeader accountIndex byteOffset value =>
      unless accountIndex == 0 do
        return ← asmError "S1a setHeader supports only account[0]"
      let b := emit b s!"  ; store header u64 @ {byteOffset}"
      let b := emit b s!"  lddw r1, {hexImm value.toNat}"
      pure (emit b s!"  stxdw [r6 + ACC0_DATA + {byteOffset}], r1")
  | .setReturnData value =>
      let b := emit b s!"  ; set_return_data_u64_le %{value}"
      pure (emitSetReturnDataU64 b value retSlot)
  | .setReturnDataBool value =>
      let b := emit b s!"  ; set_return_data_bool %{value}"
      pure (emitSetReturnDataBool b value retSlot)
  | .compare destination lhs rhs op =>
      let b := emit b s!"  ; %{destination} = cmp %{lhs}, %{rhs}"
      pure (emitCompare b destination lhs rhs op)
  | .assert condition errorCode =>
      let (b, errLab) := fresh b "err_assert"
      let (b, okLab) := fresh b "ok_assert"
      let b := emit b s!"  ; assert %{condition}"
      let b := loadTemp b "r1" condition
      let b := emit b s!"  jeq r1, 0, {errLab}"
      let b := emit b s!"  ja {okLab}"
      let b := emitErrorExit b errLab errorCode
      pure (emit b s!"{okLab}:")
  | .returnNone =>
      let b := emit b "  ; exit success"
      let b := emit b "  lddw r0, 0"
      pure (emit b "  exit")
  | .revertError errorIndex _args =>
      let code := declaredErrorBase + errorIndex
      let b := emit b s!"  ; program_error declared index {errorIndex}"
      pure (emitProgramErrorInline b code)
  | .checkedMul .. => asmError "S1a does not support checked_mul (deferred to S1b)"
  | .checkedDiv .. => asmError "S1a does not support checked_div (deferred to S1b)"
  | .checkedMod .. => asmError "S1a does not support checked_mod (deferred to S1b)"
  | .bitAnd .. | .bitOr .. | .bitXor .. | .bitNot .. =>
      asmError "S1a does not support bitwise ops (deferred to S1b)"
  | .checkedShl .. | .checkedShr .. =>
      asmError "S1a does not support shift ops (deferred to S1b)"
  | .boolNot .. | .boolAnd .. | .boolOr .. =>
      asmError "S1a does not support boolean logic ops (deferred to S1b)"
  | .ifRegion .. => asmError "S1a does not support ifRegion (deferred to S1b)"
  | .switchRegion .. => asmError "S1a does not support switchRegion (deferred to S1b)"
  | .forRegion .. => asmError "S1a does not support forRegion (deferred to S1b)"
  | .callFn .. => asmError "S1a does not support callFn (deferred to S1b)"
  | .emitEvent .. => asmError "S1a does not support emitEvent (deferred to S1b)"

private def emitHandlerBody (b0 : AsmBuf) (handler : HandlerIR) (retSlot : Nat) :
    CompileResult AsmBuf := do
  let errLab := s!"err_check_{asmLabel handler.name}"
  let mut b := b0
  for check in handler.checks do
    b ← emitCheck b check errLab
  for op in handler.operations do
    b ← emitOperation b op retSlot
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
  b := emit b "  ; load 8-byte instruction discriminator (LE u64)"
  b := emit b "  ldxdw r1, [r6 + INSTRUCTION_DATA]"
  for handler in handlers do
    let disc ← discriminatorToLeU64V1 handler.discriminator
    let lab := asmLabel handler.name
    b := emit b s!"  lddw r2, {hexImm disc.toNat}"
    b := emit b s!"  jeq r1, r2, {lab}"
  -- fallthrough: unknown discriminator
  b := emit b "  lddw r0, 1"
  b := emit b "  exit"
  pure b

/-- Public S1a emitter: typed `IR` → default-dialect SBPF assembly text. -/
def emitSbpfAsmV1 (ir : IR) : CompileResult String := do
  validateIR ir
  unless ir.fns.isEmpty do
    return ← asmError "S1a does not support pureFn table (deferred to S1b)"
  unless ir.stateAccount.index == 0 do
    return ← asmError "S1a requires state account index 0"
  let layout := computeInputLayoutV1 ir.stateAccount.exactDataLen
  -- Return-data stash sits below all IR temps: reserve room for up to 64 temps
  -- plus one return slot (S1a Counter uses ≪ 64).
  let retSlot : Nat := 8 * 65
  let mut b : AsmBuf := { text := renderLayoutEqu layout, seq := 0 }
  b := emit b ".globl entrypoint"
  b := emitBlank b
  b ← emitDispatch b ir.handlers
  b := emitBlank b
  for handler in ir.handlers do
    let lab := asmLabel handler.name
    b := emit b s!"{lab}:"
    b := emit b s!"  ; handler {handler.name}"
    b ← emitHandlerBody b handler retSlot
    b := emitBlank b
  pure b.text

/-- Convenience: emit assembly from a capability-bound IR build path. -/
def emitSbpfAsmFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult String := do
  let ir ← irFromCapability capability
  emitSbpfAsmV1 ir

end ProofForgeV2.Targets.Solana
