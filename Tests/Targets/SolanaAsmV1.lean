import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

/-!
# Tests.Targets.SolanaAsmV1 — S1b typed IR → SBPF assembly (.s)

Pins layout `.equ` offsets (including exactDataLen-derived post-account
region), Counter entrypoint dispatch (with ix_len≥8 guard), checked_add /
checked_mul / shift / bitwise / bool / region / callFn / emitEvent sequences,
`sol_set_return_data` / `sol_log_data`, and determinism. Does not invoke the
external `sbpf` toolchain. Sole rail cpi-elf product emit ships hybrid plan/IR/asm (ADR-0032 U1).
-/

namespace Tests.Targets.SolanaAsmV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

/-- Source-level deletion pin: legacy call/schedule observability tags and
    comments must not return to the SBPF emitter. `sol_log_data` remains legal
    only for declared events. -/
private def testLegacyCallStubDeleted : IO Unit := do
  let source ← IO.FS.readFile
    (System.FilePath.mk "ProofForgeV2/Targets/Solana/EmitSbpfAsmV1.lean")
  for forbidden in #["0xec01", "0x5c01",
      "external_call {note}", "schedule {note}"] do
    expect (!source.contains forbidden)
      s!"legacy Solana call/schedule log stub returned: {forbidden}"
  expect (source.contains
      "legacy Solana profiles do not emit external-call stubs")
    "SBPF emitter must retain an explicit external-call fail-closed branch"
  expect (source.contains
      "legacy Solana profiles do not emit schedule stubs")
    "SBPF emitter must retain an explicit schedule fail-closed branch"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

/-- Sole-rail helpers (ADR-0032 U1). Body IR via full-body product lower. -/
private def solanaCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def irSolana (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← solanaCapability compiled
  fullBodyIrFromProductCapabilityV1 capability false

private def asmSolana (compiled : CompiledSemanticV1) : CompileResult String := do
  let ir ← irSolana compiled
  emitSbpfAsmV1 ir

private def filesSolana (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let capability ← solanaCapability compiled
  buildFromCapability capability

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  s!"program {name} where\n" ++ body ++
  "\nend ProofForgeV2.Examples\n"

private unsafe def emitFromSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO String := do
  let compiled ← compileSource session source moduleName path
  let ir ← liftResult <| irSolana compiled
  liftResult <| emitSbpfAsmV1 ir

/-- Layout formula for exactDataLen=16 matches the documented single-account map. -/
private def testLayoutExact16 : IO Unit := do
  let layout := computeInputLayoutV1 16
  expect (layout.exactDataLen == 16) "layout: exactDataLen"
  expect (layout.rentEpoch == 0x2870)
    s!"layout16: rentEpoch expected 0x2870, got {layout.rentEpoch}"
  expect (layout.instructionDataLen == 0x2878)
    s!"layout16: ix_len offset expected 0x2878, got {layout.instructionDataLen}"
  expect (layout.instructionData == 0x2880)
    s!"layout16: ix_data offset expected 0x2880, got {layout.instructionData}"

/-- Different exactDataLen must shift the post-account region. -/
private def testLayoutVariesWithDataLen : IO Unit := do
  let l8 := computeInputLayoutV1 8
  let l16 := computeInputLayoutV1 16
  let l24 := computeInputLayoutV1 24
  expect (l8.instructionData + 8 == l16.instructionData)
    "layout: +8 data bytes shifts instruction_data by 8 when no new align"
  expect (l16.rentEpoch < l24.rentEpoch)
    "layout: larger exactDataLen increases rent_epoch offset"
  let end8 := 0x60 + 8 + 10240
  let align8 := (8 - (end8 % 8)) % 8
  expect (l8.rentEpoch == end8 + align8)
    s!"layout8: rentEpoch formula, got {l8.rentEpoch}"

/-- Discriminator hex → LE u64 for ldxdw comparison. -/
private def testDiscriminatorLe : IO Unit := do
  let v ← liftResult <| discriminatorToLeU64V1 "0100000000000000"
  expect (v == 1) s!"disc LE: expected 1, got {v}"
  let v2 ← liftResult <| discriminatorToLeU64V1 "0000000000000001"
  expect (v2 == 0x0100000000000000) s!"disc LE high byte, got {v2}"
  match discriminatorToLeU64V1 "abcd" with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "disc: short hex must fail"

/-- Frame budget constant is the Solana default stack. -/
private def testFrameBudgetConstant : IO Unit := do
  expect (maxSbpfStackBytesV1 == 4096)
    s!"maxSbpfStackBytesV1 must be 4096, got {maxSbpfStackBytesV1}"

/-- Counter assembly: layout equ + entrypoint + three handlers + sequences. -/
private unsafe def testCounterAsm
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-asm-counter>"
  let ir ← liftResult <| irSolana compiled
  expect (ir.stateAccount.exactDataLen == 16)
    s!"counter exactDataLen must be 16 (header+one u64), got {ir.stateAccount.exactDataLen}"
  let asm ← liftResult <| emitSbpfAsmV1 ir
  -- Layout pins for exactDataLen=16
  expect (asm.contains ".equ ACC0_DATA, 0x60") "asm: ACC0_DATA"
  expect (asm.contains ".equ EXACT_DATA_LEN, 0x10") "asm: EXACT_DATA_LEN 16"
  expect (asm.contains ".equ ACC0_RENT_EPOCH, 0x2870") "asm: rent epoch 0x2870"
  expect (asm.contains ".equ INSTRUCTION_DATA_LEN, 0x2878") "asm: ix_len 0x2878"
  expect (asm.contains ".equ INSTRUCTION_DATA, 0x2880") "asm: ix_data 0x2880"
  expect (asm.contains ".globl entrypoint") "asm: globl entrypoint"
  expect (asm.contains "entrypoint:") "asm: entrypoint label"
  expect (asm.contains "mov64 r6, r1") "asm: save input base to r6"
  -- Entrypoint account-list shape before any fixed INSTRUCTION_*/ACC0_* load
  expect (asm.contains "ldxdw r1, [r6 + NUM_ACCOUNTS]")
    "asm: entrypoint reads NUM_ACCOUNTS"
  expect (asm.contains "jne r1, 1, err_unknown_disc")
    "asm: entrypoint num_accounts == 1"
  expect (asm.contains "ldxb r1, [r6 + ACC0_HEADER + 0]")
    "asm: entrypoint non-dup marker at ACC0_HEADER+0"
  expect (asm.contains "jne r1, 0xff, err_unknown_disc")
    "asm: entrypoint non-dup == 0xff"
  -- Shape pair must appear before the first fixed instruction_data_len load.
  let beforeIx :=
    match asm.splitOn "ldxdw r1, [r6 + INSTRUCTION_DATA_LEN]" with
    | head :: _ => head
    | [] => ""
  expect (beforeIx.contains "ldxdw r1, [r6 + NUM_ACCOUNTS]")
    "asm: NUM_ACCOUNTS load must precede first INSTRUCTION_DATA_LEN load"
  expect (beforeIx.contains "ldxb r1, [r6 + ACC0_HEADER + 0]")
    "asm: ACC0_HEADER+0 load must precede first INSTRUCTION_DATA_LEN load"
  -- S1b dispatch guard
  expect (asm.contains "ldxdw r1, [r6 + INSTRUCTION_DATA_LEN]")
    "asm: dispatch reads ix len"
  expect (asm.contains "jlt r1, 8, err_unknown_disc")
    "asm: dispatch ix_len >= 8 guard"
  expect (asm.contains "err_unknown_disc:")
    "asm: unknown discriminator label"
  -- Three handlers
  expect (asm.contains "initialize:") "asm: initialize handler"
  expect (asm.contains "increment:") "asm: increment handler"
  expect (asm.contains "get:") "asm: get handler"
  -- checked_add overflow sequence (SBPF wrapping guard)
  expect (asm.contains "lddw r3, 0xffffffffffffffff") "asm: checked_add max"
  expect (asm.contains "sub64 r3, r2") "asm: checked_add max-rhs"
  expect (asm.contains "jgt r1, r3,") "asm: checked_add overflow branch"
  expect (asm.contains "add64 r4, r2") "asm: checked_add perform"
  expect (asm.contains "lddw r0, 0x1001") "asm: arithmeticOverflow 0x1001"
  -- return data syscall
  expect (asm.contains "call sol_set_return_data") "asm: sol_set_return_data"
  expect (asm.contains "lddw r2, 8") "asm: return data len 8"
  -- exit
  expect (asm.contains "exit") "asm: exit present"
  -- S1b banner
  expect (asm.contains "S1b") "asm: S1b banner"
  -- Deterministic rebuild
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asm == asm2) "asm: deterministic rebuild"

/-- Sole-rail product emit ships hybrid CPI bases + assembly. -/
private unsafe def testProductEmitUnchanged
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-asm-product>"
  let files ← liftResult <| filesSolana compiled
  let paths := files.map (·.path)
  expect (paths.any (· == "Counter.cpi-plan.json")) "product: cpi-plan"
  expect (paths.any (· == "Counter.idl.json")) "product: idl"
  expect (paths.any (· == "Counter.s")) "product: assembly"
  expect (paths.any (· == "Counter.cpi-ir.json")) "product: hybrid ir"

/-- Guarded counter exercises checked_sub + compare/assert sequences. -/
private unsafe def testGuardedCounterAsm
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "GuardedAsm" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry decrement(delta : UInt64) : UInt64 do\n" ++
    "    assert count >= delta\n" ++
    "    count := count - delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.GuardedAsm" "<solana-asm-guarded>"
  let ir ← liftResult <| irSolana compiled
  let asm ← liftResult <| emitSbpfAsmV1 ir
  expect (asm.contains "jlt r1, r2,") "guarded: checked_sub underflow branch"
  expect (asm.contains "sub64 r4, r2") "guarded: checked_sub perform"
  expect (asm.contains "jge r1, r2,") "guarded: cmp_ge for assert"
  expect (asm.contains "lddw r0, 0x1002" || asm.contains "0x1002")
    "guarded: assertionFailed 0x1002"

/-- Multi-field state changes exactDataLen and therefore layout equ. -/
private unsafe def testMultiFieldLayout
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "TwoField" <|
    "  state a : UInt64\n" ++
    "  state b : UInt64\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    a := x\n" ++
    "    b := y\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    a := a + d\n" ++
    "    return a\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return a\n"
  let compiled ← compileSource session source "Examples.TwoField" "<solana-asm-twofield>"
  let ir ← liftResult <| irSolana compiled
  expect (ir.stateAccount.exactDataLen == 24)
    s!"two-field exactDataLen 24, got {ir.stateAccount.exactDataLen}"
  let layout := computeInputLayoutV1 ir.stateAccount.exactDataLen
  let asm ← liftResult <| emitSbpfAsmV1 ir
  expect (asm.contains ".equ EXACT_DATA_LEN, 0x18")
    "two-field: EXACT_DATA_LEN 0x18"
  let rentHex := "0x" ++ String.ofList (Nat.toDigits 16 layout.rentEpoch)
  expect (asm.contains s!".equ ACC0_RENT_EPOCH, {rentHex}")
    s!"two-field: rent epoch equ {rentHex}"
  expect (layout.rentEpoch == 0x60 + 24 + 10240)
    s!"two-field: rentEpoch formula (aligned), got {layout.rentEpoch}"

/-- checkedMul/Div/Mod golden sequences. -/
private unsafe def testArithMulDivMod
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ArithOps" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    count := count * x\n" ++
    "    count := count / y\n" ++
    "    count := count % y\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asm ← emitFromSource session source "Examples.ArithOps" "<solana-asm-arith>"
  -- checkedMul: zero-rhs branch + MAX/rhs overflow + mul64 + 0x1001
  expect (asm.contains "jeq r2, 0,") "mul: zero-rhs branch"
  expect (asm.contains "div64 r3, r2") "mul: MAX/rhs"
  expect (asm.contains "jgt r1, r3,") "mul: overflow branch"
  expect (asm.contains "mul64 r4, r2") "mul: perform"
  expect (asm.contains "lddw r0, 0x1001") "mul: overflow code 0x1001"
  -- checkedDiv / checkedMod zero guards
  expect (asm.contains "div64 r1, r2") "div: perform"
  expect (asm.contains "mod64 r1, r2") "mod: perform"
  expect (asm.contains "jeq r2, 0,") "div/mod: zero guard present"
  let asm2 ← emitFromSource session source "Examples.ArithOps" "<solana-asm-arith-2>"
  expect (asm == asm2) "arith: deterministic"

/-- Shift ops: jge 64 + shl overflow sequence. -/
private unsafe def testShiftOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ShiftOps" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    count := (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "    return count\n\n" ++
    "  view bigShift(x : UInt64) : UInt64 do\n" ++
    "    return x >> (32 + 32)\n"
  let asm ← emitFromSource session source "Examples.ShiftOps" "<solana-asm-shift>"
  expect (asm.contains "jge r2, 64,") "shift: count >= 64 guard"
  expect (asm.contains "lsh64 r1, r2") "shl: perform"
  expect (asm.contains "rsh64 r3, r2") "shl: overflow check rsh"
  expect (asm.contains "jne r3, r4,") "shl: lost-bits overflow branch"
  expect (asm.contains "rsh64 r1, r2") "shr: perform"
  expect (asm.contains "lddw r0, 0x1004") "shift: invalidShift 0x1004"
  expect (asm.contains "lddw r0, 0x1001") "shl: arithmeticOverflow 0x1001"

/-- Bitwise + boolean ops. -/
private unsafe def testBitBoolOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "BitBool" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    count := (x & 15) | (x ^ 3)\n" ++
    "    count := ~count\n" ++
    "    return count\n\n" ++
    "  view flag(x : UInt64) : Bool do\n" ++
    "    return !(x == 0) && (x > 0) || (x == 1)\n"
  let asm ← emitFromSource session source "Examples.BitBool" "<solana-asm-bitbool>"
  expect (asm.contains "and64 r1, r2") "bit: and64"
  expect (asm.contains "or64 r1, r2") "bit: or64"
  expect (asm.contains "xor64 r1, r2") "bit: xor64"
  expect (asm.contains "lddw r2, 0xffffffffffffffff") "bitNot: xor -1"
  expect (asm.contains "xor64 r1, r2") "bitNot: xor"
  expect (asm.contains "xor64 r1, 1") "boolNot: xor 1"

/-- ifRegion label structure. -/
private unsafe def testIfRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "IfAsm" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    if x > 0 then\n" ++
    "      count := count + x\n" ++
    "    else\n" ++
    "      count := count - x\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asm ← emitFromSource session source "Examples.IfAsm" "<solana-asm-if>"
  expect (asm.contains "if_else_") "if: else label"
  expect (asm.contains "if_end_") "if: end label"
  expect (asm.contains "jeq r1, 0,") "if: false → else"
  expect (asm.contains "ja if_end_") "if: then → end"
  expect (asm.contains "add64 r4, r2") "if: then add"
  expect (asm.contains "sub64 r4, r2") "if: else sub"

/-- switchRegion (match) label structure. -/
private unsafe def testSwitchRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MatchAsm" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      count := count + 1\n" ++
    "    | 1 => do\n" ++
    "      count := count + 2\n" ++
    "    | _ => do\n" ++
    "      count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asm ← emitFromSource session source "Examples.MatchAsm" "<solana-asm-match>"
  expect (asm.contains "sw_case_") "switch: case labels"
  expect (asm.contains "sw_end_") "switch: end label"
  expect (asm.contains "lddw r2, 0x0") "switch: case value 0"
  expect (asm.contains "lddw r2, 0x1") "switch: case value 1"
  expect (asm.contains "jeq r1, r2,") "switch: case compare"

/-- forRegion header/end loop structure. -/
private unsafe def testForRegion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ForAsm" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry addUp(n : UInt64, limit : UInt64) : UInt64 do\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asm ← emitFromSource session source "Examples.ForAsm" "<solana-asm-for>"
  expect (asm.contains "for_header_") "for: header label"
  expect (asm.contains "for_end_") "for: end label"
  expect (asm.contains "ja for_header_") "for: back edge"
  expect (asm.contains "rebind induction") "for: induction rebind"
  expect (asm.contains "lddw r0, 0x1003") "for: loopBoundExceeded 0x1003"

/-- callFn single + nested inline + fn-internal if. -/
private unsafe def testCallFn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "FnAsm" <|
    "  state count : UInt64\n\n" ++
    "  fn double(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n\n" ++
    "  fn absDelta(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    if x > y then\n" ++
    "      return x - y\n" ++
    "    else\n" ++
    "      return y - x\n\n" ++
    "  fn quadruple(x : UInt64) : UInt64 do\n" ++
    "    return double(double(x))\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := double(i)\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + double(delta)\n" ++
    "    return quadruple(count)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return absDelta(count, 0)\n"
  let asm ← emitFromSource session source "Examples.FnAsm" "<solana-asm-fn>"
  expect (asm.contains "call double") "fn: double inline comment"
  expect (asm.contains "call quadruple") "fn: quadruple inline comment"
  expect (asm.contains "call absDelta") "fn: absDelta inline comment"
  expect (asm.contains "fn ret u64") "fn: return-value copy"
  expect (asm.contains "if_else_") "fn: if inside absDelta"
  expect (asm.contains "checked_add_u64") "fn: double uses checked_add"
  -- Nested inline: quadruple → double → double comments appear multiple times
  let parts := asm.splitOn "call double"
  expect (parts.length ≥ 3) s!"fn: nested double inlines, got {parts.length - 1}"

/-- One-arm-closed if in a fn: the fn-level return must skip trailing body
    ops after the region (early-return semantics survive inlining). -/
private unsafe def testCallFnEarlyReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "FnEarlyAsm" <|
    "  state count : UInt64\n\n" ++
    "  fn pick(x : UInt64, guard : UInt64) : UInt64 do\n" ++
    "    if guard > 0 then\n" ++
    "      return x\n" ++
    "    return x + 1\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    count := pick(x, 3)\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asm ← emitFromSource session source "Examples.FnEarlyAsm" "<solana-asm-fn-early>"
  -- fn-level return jumps to the inline end label (skips trailing ops).
  expect (asm.contains "ja fn_end_") "fn-early: return jumps to inline end"
  -- both the early-return copy and the trailing fallthrough copy are present.
  expect (asm.contains "fn ret u64") "fn-early: return-value copies"

/-- emitEvent → sol_log_data + descriptor setup. -/
private unsafe def testEmitEvent
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "EmitAsm" <|
    "  state count : UInt64\n\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asm ← emitFromSource session source "Examples.EmitAsm" "<solana-asm-emit>"
  expect (asm.contains "emit_event Moved") "emit: event name comment"
  expect (asm.contains "call sol_log_data") "emit: sol_log_data"
  expect (asm.contains "lddw r2, 2") "emit: two SolBytes slices"
  expect (asm.contains "lddw r1, 0x0") "emit: event index 0 key"
  -- declared revert code base 0x2000
  expect (asm.contains "lddw r0, 0x2000") "emit: declared error Cap @ 0x2000"

/-- T8a body multi-width: u8 add overflow guard, u16 mul, u32 shl, u8 bitNot mask. -/
private unsafe def testNarrowWidthOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- u8 checked_add: high-bit rsh64 immediate + 0x1001 on overflow path.
  let srcAdd := wrapProgram "NarrowAddU8" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let a : UInt8 := 250\n" ++
    "    let b : UInt8 := a + 10\n" ++
    "    if b > 12 then\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asmAdd ← emitFromSource session srcAdd "Examples.NarrowAddU8" "<solana-asm-nu8-add>"
  expect (asmAdd.contains "checked_add_u8") "narrow-add: comment width tag"
  expect (asmAdd.contains "rsh64 r3, 8") "narrow-add: high-bit rsh by 8"
  expect (asmAdd.contains "jne r3, 0,") "narrow-add: high-bit nonzero overflow"
  expect (asmAdd.contains "lddw r0, 0x1001") "narrow-add: overflow 0x1001"
  -- u16 mul high-bit check
  let srcMul := wrapProgram "NarrowMulU16" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let a : UInt16 := 1000\n" ++
    "    let b : UInt16 := a * 3\n" ++
    "    if b > 2000 then\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asmMul ← emitFromSource session srcMul "Examples.NarrowMulU16" "<solana-asm-nu16-mul>"
  expect (asmMul.contains "checked_mul_u16") "narrow-mul: comment width tag"
  expect (asmMul.contains "mul64 r4, r2") "narrow-mul: mul64"
  expect (asmMul.contains "rsh64 r3, 16") "narrow-mul: high-bit rsh by 16"
  -- u32 shl: count≥64 + high-bit overflow
  let srcShl := wrapProgram "NarrowShlU32" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let a : UInt32 := 1\n" ++
    "    let b : UInt32 := a << 4\n" ++
    "    if b > 10 then\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asmShl ← emitFromSource session srcShl "Examples.NarrowShlU32" "<solana-asm-nu32-shl>"
  expect (asmShl.contains "shl_u32") "narrow-shl: comment width tag"
  expect (asmShl.contains "jge r2, 64,") "narrow-shl: count >= 64 guard"
  expect (asmShl.contains "lsh64 r1, r2") "narrow-shl: lsh64"
  expect (asmShl.contains "rsh64 r3, 32") "narrow-shl: high-bit rsh by 32"
  -- u8 bitNot: xor -1 then AND 0xff mask
  let srcNot := wrapProgram "NarrowNotU8" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let a : UInt8 := 10\n" ++
    "    let b : UInt8 := ~a\n" ++
    "    if b > 200 then\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asmNot ← emitFromSource session srcNot "Examples.NarrowNotU8" "<solana-asm-nu8-not>"
  expect (asmNot.contains "bitnot_u8") "narrow-not: comment width tag"
  expect (asmNot.contains "lddw r2, 0xffffffffffffffff") "narrow-not: xor -1"
  expect (asmNot.contains "lddw r2, 0xff") "narrow-not: width mask 0xff"
  expect (asmNot.contains "and64 r1, r2") "narrow-not: apply mask"
  -- T9e: UInt128 body let admitted (multiword).
  let src128 := wrapProgram "NarrowU128Body" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let a : UInt128 := 1\n" ++
    "    let b : UInt128 := a + a\n" ++
    "    if b == 2 then\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let asm128 ← emitFromSource session src128 "Examples.NarrowU128Body"
    "<solana-asm-u128-body>"
  expect (asm128.contains "checked_add_u128" || asm128.contains "add64")
    "T9e: UInt128 body add must emit multiword or add64"
  -- Determinism of narrow path.
  let asmAdd2 ← emitFromSource session srcAdd "Examples.NarrowAddU8" "<solana-asm-nu8-add-2>"
  expect (asmAdd == asmAdd2) "narrow-add: deterministic"

/-- T8b-Solana: UInt8/16/32 state + param ABI multi-width (load/store/zero + disc). -/
private unsafe def testAbiMultiWidthStateParam
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "AbiMwSol" <|
    "  state a : UInt8\n" ++
    "  state b : UInt16\n" ++
    "  state c : UInt32\n\n" ++
    "  init(x : UInt8, y : UInt16, z : UInt32) do\n" ++
    "    a := x\n" ++
    "    b := y\n" ++
    "    c := z\n\n" ++
    "  entry bump8(delta : UInt8) : UInt64 do\n" ++
    "    a := a + delta\n" ++
    "    return 0\n\n" ++
    "  entry bump16(delta : UInt16) : UInt64 do\n" ++
    "    b := b + delta\n" ++
    "    return 0\n\n" ++
    "  entry bump32(delta : UInt32) : UInt64 do\n" ++
    "    c := c + delta\n" ++
    "    return 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let compiled ← compileSource session source "Examples.AbiMwSol" "<solana-asm-abi-mw>"
  let ir ← liftResult <| irSolana compiled
  expect (ir.stateAccount.fields.size == 3) "abi-mw: three state fields"
  expect (ir.stateAccount.fields[0]!.byteWidth == 1) "abi-mw: UInt8 field byteWidth 1"
  expect (ir.stateAccount.fields[1]!.byteWidth == 2) "abi-mw: UInt16 field byteWidth 2"
  expect (ir.stateAccount.fields[2]!.byteWidth == 4) "abi-mw: UInt32 field byteWidth 4"
  -- 8-byte slot pitch retained (exactDataLen = header + 3*8).
  expect (ir.stateAccount.exactDataLen == 32)
    s!"abi-mw: exactDataLen must be 32, got {ir.stateAccount.exactDataLen}"
  -- Discriminator: bump8(u8) ≠ bump8 with all-u64 historical formula.
  let bump8 ← match ir.handlers.find? (·.name == "bump8") with
    | some h => pure h
    | none => throw <| IO.userError "abi-mw: missing bump8"
  expect (bump8.params.size == 1 && bump8.params[0]!.byteWidth == 1)
    "abi-mw: bump8 param byteWidth 1"
  let histU64 := instructionDiscriminator "bump8"
    #[{ sourceId := 0, name := "delta", dataOffset := 8, byteWidth := 8,
        endianness := .little, isInt := false }]
  expect (bump8.discriminator != histU64)
    s!"abi-mw: bump8(u8) disc must differ from bump8(u64): {bump8.discriminator}"
  let expectedU8 := instructionDiscriminator "bump8" bump8.params
  expect (bump8.discriminator == expectedU8)
    s!"abi-mw: bump8 disc must match signature, got {bump8.discriminator}"
  -- SBPF narrow sequences
  let asm ← liftResult <| emitSbpfAsmV1 ir
  expect (asm.contains "ldxb r1, [r6 + INSTRUCTION_DATA +")
    "abi-mw: ldxb for UInt8 param"
  expect (asm.contains "ldxh r1, [r6 + INSTRUCTION_DATA +")
    "abi-mw: ldxh for UInt16 param"
  expect (asm.contains "ldxw r1, [r6 + INSTRUCTION_DATA +")
    "abi-mw: ldxw for UInt32 param"
  expect (asm.contains "ldxb r1, [r6 + ACC0_DATA +")
    "abi-mw: ldxb for UInt8 state load"
  expect (asm.contains "ldxh r1, [r6 + ACC0_DATA +")
    "abi-mw: ldxh for UInt16 state load"
  expect (asm.contains "ldxw r1, [r6 + ACC0_DATA +")
    "abi-mw: ldxw for UInt32 state load"
  expect (asm.contains "stxb [r6 + ACC0_DATA +")
    "abi-mw: stxb for UInt8 store"
  expect (asm.contains "stxh [r6 + ACC0_DATA +")
    "abi-mw: stxh for UInt16 store"
  expect (asm.contains "stxw [r6 + ACC0_DATA +")
    "abi-mw: stxw for UInt32 store"
  expect (asm.contains "stb [r6 + ACC0_DATA +")
    "abi-mw: stb imm zero for UInt8 init"
  expect (asm.contains "sth [r6 + ACC0_DATA +")
    "abi-mw: sth imm zero for UInt16 init"
  expect (asm.contains "stw [r6 + ACC0_DATA +")
    "abi-mw: stw imm zero for UInt32 init"
  -- Sole-rail CPI IDL schema differs from retired plan typing spelling;
  -- IR/asm width pins above remain the authoritative multi-width checks.
  let files ← liftResult <| filesSolana compiled
  let some idl := files.find? (fun f => f.path.endsWith ".idl.json") |
    throw <| IO.userError "abi-mw: missing idl.json"
  expect (!idl.contents.isEmpty) "abi-mw: IDL non-empty"
  -- Counter discriminator unchanged (historical u64 surface).
  let counter ← compileSource session counterSourceText counterModuleNameV1
    "<solana-asm-counter-abi-reg>"
  let counterIr ← liftResult <| irSolana counter
  let some inc := counterIr.handlers.find? (·.name == "increment") |
    throw <| IO.userError "abi-mw: counter missing increment"
  let expectedInc := instructionDiscriminator "increment" inc.params
  expect (inc.discriminator == expectedInc)
    "abi-mw: Counter increment disc unchanged"
  -- Determinism
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asm == asm2) "abi-mw: deterministic"

/-- T9e: UInt128/256 state + param + body + result multiword product. -/
private unsafe def testWideUintProduct
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "WideUint" <|
    "  state a : UInt128\n" ++
    "  state b : UInt256\n\n" ++
    "  init(x : UInt128, y : UInt256) do\n" ++
    "    a := x\n" ++
    "    b := y\n\n" ++
    "  entry add128(delta : UInt128) : UInt128 do\n" ++
    "    a := a + delta\n" ++
    "    return a\n\n" ++
    "  view get128() : UInt128 do\n" ++
    "    return a\n\n" ++
    "  view get256() : UInt256 do\n" ++
    "    return b\n"
  let compiled ← compileSource session source "Examples.WideUint" "<solana-wide-uint>"
  let ir ← liftResult <| irSolana compiled
  expect (ir.stateAccount.fields.size == 2) "T9e: two state fields"
  expect (ir.stateAccount.fields[0]!.byteWidth == 16) "T9e: UInt128 field byteWidth 16"
  expect (ir.stateAccount.fields[1]!.byteWidth == 32) "T9e: UInt256 field byteWidth 32"
  expect (ir.stateAccount.fields[0]!.byteOffset + 16 == ir.stateAccount.fields[1]!.byteOffset)
    "T9e: UInt128 pitch 16 before UInt256"
  -- header 8 + 16 + 32 = 56
  expect (ir.stateAccount.exactDataLen == 56)
    s!"T9e: exactDataLen must be 56, got {ir.stateAccount.exactDataLen}"
  let add128 ← match ir.handlers.find? (·.name == "add128") with
    | some h => pure h
    | none => throw <| IO.userError "T9e: missing add128"
  expect (add128.resultKind == .u128) "T9e: add128 resultKind u128"
  expect (add128.params.size == 1 && add128.params[0]!.byteWidth == 16)
    "T9e: add128 param byteWidth 16"
  let get128 ← match ir.handlers.find? (·.name == "get128") with
    | some h => pure h
    | none => throw <| IO.userError "T9e: missing get128"
  expect (get128.resultKind == .u128) "T9e: get128 resultKind u128"
  let get256 ← match ir.handlers.find? (·.name == "get256") with
    | some h => pure h
    | none => throw <| IO.userError "T9e: missing get256"
  expect (get256.resultKind == .u256) "T9e: get256 resultKind u256"
  let asm ← liftResult <| emitSbpfAsmV1 ir
  expect (asm.contains "ldxdw r1, [r6 + ACC0_DATA +")
    "T9e: multiword state load uses ldxdw"
  expect (asm.contains "stxdw [r6 + ACC0_DATA +")
    "T9e: multiword state store uses stxdw"
  expect (asm.contains "call sol_set_return_data")
    "T9e: wide return uses sol_set_return_data"
  let files ← liftResult <| filesSolana compiled
  let some idlFile := files.find? (fun f => f.path.endsWith ".idl.json") |
    throw <| IO.userError "T9e: missing idl"
  expect (!idlFile.contents.isEmpty) "T9e: IDL non-empty (sole-rail CPI schema)"

/-- Solana lane: UInt128/256 body mul lowers to true schoolbook multiword
    multiply (32-bit-split limbs, no low64 fallback); div/mod lower to true
    binary long division (restoring) over full limbs — no low64-only path. -/
private unsafe def testMultiwordMulDivMod
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "WideArith" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry mul128(x : UInt128, y : UInt128) : UInt128 do\n" ++
    "    return x * y\n\n" ++
    "  entry mul256(x : UInt256, y : UInt256) : UInt256 do\n" ++
    "    return x * y\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.WideArith" "<solana-wide-arith>"
  let ir ← liftResult (irSolana compiled)
  let asm ← liftResult <| emitSbpfAsmV1 ir
  -- schoolbook markers: 32-bit digit split + lane-ordered accumulation
  expect (asm.contains "err_mwmul_") "mwmul: overflow exit label"
  expect (asm.contains "mwmul_lane_") "mwmul: lane carry tracking labels"
  expect ((asm.splitOn "lddw r3, 0xffffffff").length ≥ 3)
    "mwmul: 32-bit mask used for digit splits"
  -- full multiword div/mod: binary long division labels + no low64 fallback
  let sourceDivMod := wrapProgram "WideDivMod" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry div128(x : UInt128, y : UInt128) : UInt128 do\n" ++
    "    return x / y\n\n" ++
    "  entry mod128(x : UInt128, y : UInt128) : UInt128 do\n" ++
    "    return x % y\n\n" ++
    "  entry div256(x : UInt256, y : UInt256) : UInt256 do\n" ++
    "    return x / y\n\n" ++
    "  entry mod256(x : UInt256, y : UInt256) : UInt256 do\n" ++
    "    return x % y\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiledDM ← compileSource session sourceDivMod "Examples.WideDivMod" "<solana-wide-divmod>"
  let irDM ← liftResult (irSolana compiledDM)
  let asmDM ← liftResult <| emitSbpfAsmV1 irDM
  expect (asmDM.contains "err_mwdiv_") "mwdiv: div-by-zero exit label"
  expect (asmDM.contains "err_mwmod_") "mwmod: div-by-zero exit label"
  expect (asmDM.contains "ok_mwdiv_") "mwdiv: success join label"
  expect (asmDM.contains "ok_mwmod_") "mwmod: success join label"
  -- Divisor-zero exits must precede the unrolled body so the zero check never
  -- regresses to a signed-i16 jump across tens of thousands of slots.
  let rec indexOfChars (hay needle : List Char) (i : Nat) : Option Nat :=
    match hay with
    | [] => none
    | _ :: rest =>
        if needle.isPrefixOf hay then some i else indexOfChars rest needle (i + 1)
  let some divErrAt := indexOfChars asmDM.toList "err_mwdiv_".toList 0 |
    throw <| IO.userError "mwdiv: missing error label position"
  let some divBodyAt := indexOfChars asmDM.toList "body_mwdiv_".toList 0 |
    throw <| IO.userError "mwdiv: missing body label position"
  let some modErrAt := indexOfChars asmDM.toList "err_mwmod_".toList 0 |
    throw <| IO.userError "mwmod: missing error label position"
  let some modBodyAt := indexOfChars asmDM.toList "body_mwmod_".toList 0 |
    throw <| IO.userError "mwmod: missing body label position"
  expect (divErrAt < divBodyAt) "mwdiv: zero exit must precede unrolled body"
  expect (modErrAt < modBodyAt) "mwmod: zero exit must precede unrolled body"
  -- binary long-division control-flow labels (per-bit sub / next-bit)
  expect (asmDM.contains "mwdiv_sub_") "mwdiv: restore-subtract label"
  expect (asmDM.contains "mwdiv_nb_") "mwdiv: next-bit label"
  expect (asmDM.contains "mwmod_sub_") "mwmod: restore-subtract label"
  expect (asmDM.contains "mwmod_nb_") "mwmod: next-bit label"
  -- borrow chain used inside rem -= divisor
  expect (asmDM.contains "mwdiv_bset_") "mwdiv: subtract borrow-set label"
  expect (asmDM.contains "mwmod_bset_") "mwmod: subtract borrow-set label"
  -- honest multiword: must NOT fall back to single-limb div64/mod64
  expect (!(asmDM.contains "div64 r1, r2")) "mwdiv: no low64 div64 fallback"
  expect (!(asmDM.contains "mod64 r1, r2")) "mwmod: no low64 mod64 fallback"
  -- unrolled bit coverage: UInt128 has 128 bits; at least that many next-bit labels
  expect ((asmDM.splitOn "mwdiv_nb_").length ≥ 129)
    "mwdiv: unrolled ≥128 next-bit steps for UInt128"
  -- Entrypoint branches must stay local even when all four wide handlers share
  -- one program. A non-match skips only `call`+`exit`; the matched long-range
  -- transfer uses BPF-to-BPF call (32-bit offset), never a 16-bit body branch.
  for name in #["div128", "mod128", "div256", "mod256"] do
    expect (asmDM.contains s!"jne r1, r2, dispatch_next_{name}\n  call {name}\n  exit\ndispatch_next_{name}:")
      s!"wide dispatch: adjacent continuation + long-range call for {name}"
    expect (!(asmDM.contains s!"jeq r1, r2, {name}\n"))
      s!"wide dispatch: no direct 16-bit branch to {name}"
  -- determinism
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asm == asm2) "mwmul: deterministic"
  let asmDM2 ← liftResult <| emitSbpfAsmV1 irDM
  expect (asmDM == asmDM2) "mwdiv/mod: deterministic"

/-- T9a: UInt8/16/32 entry results admitted; return-data lengths 1/2/4 in SBPF. -/
private unsafe def testNarrowResultAdmitted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "NarrowRet" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry get8() : UInt8 do\n" ++
    "    return 1\n\n" ++
    "  entry get16() : UInt16 do\n" ++
    "    return 2\n\n" ++
    "  entry get32() : UInt32 do\n" ++
    "    return 3\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← liftResult (← session.selectProgramV1 source
    "<solana-narrow-ret>" "Examples.NarrowRet" none)
  let compiled ← liftResult (Compiler.compileValidatedSourceV1 validated)
  let ir ← liftResult (irSolana compiled)
  let get8 := ir.handlers.find? (·.name == "get8")
  let get16 := ir.handlers.find? (·.name == "get16")
  let get32 := ir.handlers.find? (·.name == "get32")
  expect (
      (match get8 with | some h => h.operations.any (fun | .setReturnData 1 _ => true | _ => false) | none => false) &&
      (match get16 with | some h => h.operations.any (fun | .setReturnData 2 _ => true | _ => false) | none => false) &&
      (match get32 with | some h => h.operations.any (fun | .setReturnData 4 _ => true | _ => false) | none => false))
    "T9a: Solana IR setReturnData byteLen must be 1/2/4 for UInt8/16/32"
  let asm ← liftResult (asmSolana compiled)
  expect (asm.contains "lddw r2, 1" && asm.contains "lddw r2, 2" &&
      asm.contains "lddw r2, 4" && asm.contains "call sol_set_return_data")
    "T9a: SBPF asm must set return-data lengths 1/2/4"

/-- T9e: UInt128 entry result admitted (was fail-closed under T9a). -/
private unsafe def testUInt128ResultAdmitted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "U128Ret" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt128 do\n" ++
    "    return 0\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.U128Ret" "<solana-u128-ret>"
  let ir ← liftResult (irSolana compiled)
  let run ← match ir.handlers.find? (·.name == "run") with
    | some h => pure h
    | none => throw <| IO.userError "T9e: missing run"
  expect (run.operations.any (fun
    | .setReturnData 16 _ => true
    | _ => false))
    "T9e: UInt128 return must setReturnData 16"

/-- Source-level end-to-end covering mul/if/for/fn/revert/emit together. -/
private unsafe def testSourceE2E
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "E2EAsm" <|
    "  state count : UInt64\n\n" ++
    "  event Tick(v : UInt64)\n" ++
    "  error Boom(v : UInt64)\n\n" ++
    "  fn scale(x : UInt64) : UInt64 do\n" ++
    "    return x * 2\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    emit Tick(x)\n" ++
    "    if x > 0 then\n" ++
    "      count := count + scale(x)\n" ++
    "    else\n" ++
    "      revert Boom(y)\n" ++
    "    for i in x ..< y bounded 4 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session source "Examples.E2EAsm" "<solana-asm-e2e>"
  let ir ← liftResult <| irSolana compiled
  let asm ← liftResult <| emitSbpfAsmV1 ir
  expect (asm.contains "mul64 r4, r2") "e2e: mul"
  expect (asm.contains "if_else_") "e2e: if"
  expect (asm.contains "for_header_") "e2e: for"
  expect (asm.contains "call scale") "e2e: callFn"
  expect (asm.contains "call sol_log_data") "e2e: emit"
  expect (asm.contains "lddw r0, 0x2000") "e2e: revert"
  expect (asm.contains "jlt r1, 8, err_unknown_disc") "e2e: dispatch guard"
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asm == asm2) "e2e: deterministic"

/-- L2 / B-SOL-MAP-ELF: Map dense pilot (cap-8) ELF frame budget must fit
    within 4096 bytes. The Map upsert expands to 24 occ/key/val leaf Exprs;
    without temp reuse across consuming statements the frame grows linearly
    with all leaves. Temp reuse after consuming statements (store/assert/emit/
    revert/call/schedule/returnData) recycles frame slots, so the peak is the
    deepest single leaf tree, not the sum of all leaves. -/
private unsafe def testMapMiniElfFrameBudgetOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MapMiniFb" <|
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n\n" ++
    "  view get(k : UInt64) : UInt64 do\n" ++
    "    match m[k] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.MapMiniFb"
    "<solana-map-mini-fb>"
  -- Sole-rail full-body IR: put stores Map via multi-leaf StateStore path.
  let ir ← liftResult <| irSolana compiled
  let some putIR := ir.handlers.find? (·.name == "put") |
    throw <| IO.userError "map-mini-fb: missing put IR"
  let multi24 := putIR.operations.foldl (fun n op =>
    match op with
    | .storeStateMulti e => n + (if e.size == 24 then 1 else 0)
    | _ => n) 0
  let scalarStore := putIR.operations.foldl (fun n op =>
    match op with
    | .storeState .. | .narrowStoreState .. => n + 1
    | _ => n) 0
  expect (multi24 == 1)
    s!"map-mini-fb: put IR must have one storeStateMulti(24), got {multi24}"
  expect (scalarStore == 0)
    s!"map-mini-fb: put IR must not scalar-store Map leaves, got {scalarStore}"
  -- The put handler does a Map IndexSet (24 leaf stores) + a return.
  -- Before temp reuse: 24888 bytes (3109 temps). After: must be ≤ 4096.
  let asm ← liftResult <| emitSbpfAsmV1 ir
  -- The asm must contain the put handler label.
  expect (asm.contains "put:") "map-mini-fb: asm must contain put handler"
  expect (asm.contains "store_multi_le [24]")
    "map-mini-fb: asm must emit store_multi_le [24] (atomic aggregate, not per-leaf live write)"
  -- Frame budget gate already passed inside emitSbpfAsmV1 (it throws on
  -- overflow). If we reach here, all handlers fit within 4096 bytes.
  expect (asm.contains "entrypoint:") "map-mini-fb: asm must contain entrypoint"
  expect (asm.contains "handler put (temps=")
    "map-mini-fb: put temp annotation present (frame ≤ 4096 already gated)"

/-- L2 / B-SOL-MAP-ELF: Token (Map balances) ELF frame budget must fit
    within 4096 bytes: mint does Map IndexGet + IndexSet (48 leaf ops). -/
private unsafe def testTokenElfFrameBudgetOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "TokenFb" <|
    "  state balances : Map UInt64 UInt64\n" ++
    "  state supply : UInt64\n\n" ++
    "  init() do\n" ++
    "    balances := Map.empty()\n" ++
    "    supply := 0\n\n" ++
    "  entry mint(to : UInt64, amount : UInt64) : UInt64 do\n" ++
    "    match balances[to] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      balances[to] := v + amount\n" ++
    "      supply := supply + amount\n" ++
    "      return supply\n" ++
    "    | _ => do\n" ++
    "      balances[to] := amount\n" ++
    "      supply := supply + amount\n" ++
    "      return supply\n\n" ++
    "  entry transfer(src : UInt64, dst : UInt64, amount : UInt64) : Bool do\n" ++
    "    match balances[src] with\n" ++
    "    | Option.some(fromBal) => do\n" ++
    "      assert fromBal >= amount\n" ++
    "      match balances[dst] with\n" ++
    "      | Option.some(toBal) => do\n" ++
    "        balances[src] := fromBal - amount\n" ++
    "        balances[dst] := toBal + amount\n" ++
    "        return true\n" ++
    "      | _ => do\n" ++
    "        balances[src] := fromBal - amount\n" ++
    "        balances[dst] := amount\n" ++
    "        return true\n" ++
    "    | _ => do\n" ++
    "      assert false\n" ++
    "      return false\n\n" ++
    "  view total() : UInt64 do\n" ++
    "    return supply\n\n" ++
    "  view balanceOf(who : UInt64) : UInt64 do\n" ++
    "    match balances[who] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.TokenFb"
    "<solana-token-fb>"
  let ir ← liftResult <| irSolana compiled
  -- Before temp reuse: 58032 bytes (7254 temps). After: must be ≤ 4096.
  let asm ← liftResult <| emitSbpfAsmV1 ir
  expect (asm.contains "mint:") "token-fb: asm must contain mint handler"
  expect (asm.contains "transfer:") "token-fb: asm must contain transfer handler"

/-- L2 / B-SOL-MAP-ELF: an oversized handler must still fail closed at the
    4096-byte frame budget (the budget is not raised to make Map fit). -/
private unsafe def testFrameBudgetFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- 300 state fields → sum chain depth 300 > 256 → Plan lowering rejects.
  let mut stateDecls := ""
  let mut initStores := ""
  for i in [:300] do
    stateDecls := stateDecls ++ "  state s" ++ toString i ++ " : UInt64\n"
    initStores := initStores ++ "    s" ++ toString i ++ " := 0\n"
  let mut sumExpr := "s0"
  for i in [1:300] do
    sumExpr := sumExpr ++ " + s" ++ toString i
  let source := wrapProgram "OversizedFrame" <|
    stateDecls ++ "\n" ++
    "  init() do\n" ++
    initStores ++ "\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return " ++ sumExpr ++ "\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return s0\n"
  match ← session.selectProgramV1 source "OversizedFrame.lean"
    "Examples.OversizedFrame" none with
  | .error e =>
    let msg := e.render
    expect (msg.contains "exceeds depth 256" || msg.contains "exceeds nesting" || msg.contains "BOUND")
      s!"oversized-frame: expected depth/bound error, got: {msg}"
  | .ok validated =>
    match Compiler.compileValidatedSourceV1 validated with
    | .error e =>
      let msg := e.render
      expect (msg.contains "exceeds depth 256" || msg.contains "frame budget")
        s!"oversized-frame: expected depth/frame error, got: {msg}"
    | .ok compiled =>
      let ir ← liftResult <| irSolana compiled
      match emitSbpfAsmV1 ir with
      | .ok _ =>
        throw <| IO.userError
          "oversized-frame: expected error but asm emitted successfully"
      | .error e =>
        let msg := e.render
        expect (msg.contains "frame budget exceeded" || msg.contains "exceeds depth")
          s!"oversized-frame: error must mention frame budget or depth, got: {msg}"

/-- #113: V1 single-state IR checks start with account-list shape; forged
    missing/reordered shape checks fail validateIR; plan text and asm emit the
    pair before fixed instruction/owner/data loads. -/
private unsafe def testAccountListShapeChecks
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-asm-account-list-shape>"
  let ir ← liftResult <| irSolana compiled
  let initH ← match ir.handlers.find? (·.name == "initialize") with
    | some h => pure h
    | none => throw <| IO.userError "account-list: missing initialize handler"
  let getH ← match ir.handlers.find? (·.name == "get") with
    | some h => pure h
    | none => throw <| IO.userError "account-list: missing get handler"
  -- Canonical order prefix for every handler: numAccounts 1, nonDup 0, …
  expect (initH.checks.size >= 4)
    s!"account-list: initialize checks too short ({initH.checks.size})"
  expect (initH.checks[0]! == .numAccounts 1)
    s!"account-list: checks[0] must be numAccounts 1, got {repr initH.checks[0]!}"
  expect (initH.checks[1]! == .accountNonDuplicate 0)
    s!"account-list: checks[1] must be accountNonDuplicate 0, got {repr initH.checks[1]!}"
  expect (initH.checks[2]! == .instructionDataLen 16)
    s!"account-list: checks[2] must be instructionDataLen 16 (disc+u64), got {repr initH.checks[2]!}"
  expect (getH.checks[0]! == .numAccounts 1)
    "account-list: get checks[0] must be numAccounts 1"
  expect (getH.checks[1]! == .accountNonDuplicate 0)
    "account-list: get checks[1] must be accountNonDuplicate 0"
  -- Sole-rail assembly carries account-list shape checks (retired .sbpf-plan audit).
  let files ← liftResult <| filesSolana compiled
  let asmText ← match files.find? (·.path == "Counter.s") with
    | some f => pure f.contents
    | none => throw <| IO.userError "account-list: missing Counter.s"
  expect (asmText.contains "num_accounts" || asmText.contains "NUM_ACCOUNTS" ||
      asmText.contains "jneq r1, 1")
    "account-list: assembly must enforce exact account count"
  expect (asmText.contains "entrypoint:")
    "account-list: assembly has entrypoint"
  -- Forged missing first check (drop numAccounts)
  let missing := withHandlers ir (ir.handlers.map fun h =>
    { h with checks := h.checks.extract 1 h.checks.size })
  match validateIR missing with
  | .ok _ =>
      throw <| IO.userError "account-list: validateIR must reject missing numAccounts check"
  | .error e =>
      expect (e.render.contains "checks are incomplete" ||
          e.render.contains "out of order")
        s!"account-list: missing-check error must mention incomplete/order, got: {e.render}"
  -- Forged reorder: put instructionDataLen before the shape pair
  let reordered := withHandlers ir (ir.handlers.map fun h =>
    if h.checks.size < 3 then h
    else
      let c0 := h.checks[0]!
      let c1 := h.checks[1]!
      let c2 := h.checks[2]!
      let rest := h.checks.extract 3 h.checks.size
      { h with checks := #[c2, c0, c1] ++ rest })
  match validateIR reordered with
  | .ok _ =>
      throw <| IO.userError "account-list: validateIR must reject reordered shape checks"
  | .error e =>
      expect (e.render.contains "checks are incomplete" ||
          e.render.contains "out of order")
        s!"account-list: reorder error must mention incomplete/order, got: {e.render}"
  -- Forged drop non-dup only (keep numAccounts, skip index 1)
  let dropNonDup := withHandlers ir (ir.handlers.map fun h =>
    if h.checks.size < 2 then h
    else
      let c0 := h.checks[0]!
      let rest := h.checks.extract 2 h.checks.size
      { h with checks := #[c0] ++ rest })
  match validateIR dropNonDup with
  | .ok _ =>
      throw <| IO.userError "account-list: validateIR must reject missing non-dup check"
  | .error e =>
      expect (e.render.contains "checks are incomplete" ||
          e.render.contains "out of order")
        s!"account-list: drop-non-dup error must mention incomplete/order, got: {e.render}"
  -- Asm still deterministic with shape guards
  let asm ← liftResult <| emitSbpfAsmV1 ir
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asm == asm2) "account-list: asm deterministic with shape checks"

unsafe def run : IO Unit := do
  testLegacyCallStubDeleted
  testLayoutExact16
  testLayoutVariesWithDataLen
  testDiscriminatorLe
  testFrameBudgetConstant
  let session ← Tests.Language.ParserSession.shared
  testCounterAsm session
  testAccountListShapeChecks session
  testProductEmitUnchanged session
  testGuardedCounterAsm session
  testMultiFieldLayout session
  testArithMulDivMod session
  testShiftOps session
  testBitBoolOps session
  testIfRegion session
  testSwitchRegion session
  testForRegion session
  testCallFn session
  testCallFnEarlyReturn session
  testEmitEvent session
  testNarrowWidthOps session
  testAbiMultiWidthStateParam session
  testWideUintProduct session
  testMultiwordMulDivMod session
  testMapMiniElfFrameBudgetOk session
  testTokenElfFrameBudgetOk session
  testFrameBudgetFailClosed session
  testNarrowResultAdmitted session
  testUInt128ResultAdmitted session
  testSourceE2E session
  IO.println "Tests.Targets.SolanaAsmV1: ok"

end Tests.Targets.SolanaAsmV1
