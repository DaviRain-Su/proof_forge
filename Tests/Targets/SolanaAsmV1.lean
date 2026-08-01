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
external `sbpf` toolchain. Default plan-profile product emit still ships only
`.sbpf-plan` + IDL (elf profile `.s` coverage lives in SolanaElfV1).
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

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def solanaCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planSolana (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let capability ← solanaCapability compiled
  planFromCapability capability

private def irSolana (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← solanaCapability compiled
  irFromCapability capability

private def asmSolana (compiled : CompiledSemanticV1) : CompileResult String := do
  let ir ← irSolana compiled
  emitSbpfAsmV1 ir

private def filesSolana (compiled : CompiledSemanticV1) : CompileResult (Array OutputFile) := do
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

/-- Default plan-profile product emit ships .sbpf-plan + idl only (no .s). -/
private unsafe def testProductEmitUnchanged
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-asm-product>"
  let files ← liftResult <| filesSolana compiled
  let paths := files.map (·.path)
  expect (paths.any (· == "Counter.sbpf-plan")) "product: still has .sbpf-plan"
  expect (paths.any (· == "Counter.idl.json")) "product: still has idl"
  expect (!paths.any (fun p => p.endsWith ".s"))
    "product: default plan profile must not publish .s"
  let planText ← match files.find? (·.path == "Counter.sbpf-plan") with
    | some f => pure f.contents
    | none => throw <| IO.userError "missing sbpf-plan"
  expect (planText.startsWith "; PROOF-FORGE-SBPF-PLAN v1")
    "product: sbpf-plan banner unchanged"

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
  -- UInt128 body let still fail closed at Solana Plan seam.
  let src128 := wrapProgram "NarrowU128Reject" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let a : UInt128 := 1\n" ++
    "    count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled128 ← compileSource session src128 "Examples.NarrowU128Reject"
    "<solana-asm-u128-reject>"
  match irSolana compiled128 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "narrow: UInt128 body must fail closed on Solana"
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
  -- IDL types (plan-profile product emit).
  let files ← liftResult <| filesSolana compiled
  let some idl := files.find? (fun f => f.path.endsWith ".idl.json") |
    throw <| IO.userError "abi-mw: missing idl.json"
  expect (idl.contents.contains "\"type\":\"u8-le\"") "abi-mw: IDL field u8-le"
  expect (idl.contents.contains "\"type\":\"u16-le\"") "abi-mw: IDL field u16-le"
  expect (idl.contents.contains "\"type\":\"u32-le\"") "abi-mw: IDL field u32-le"
  expect (idl.contents.contains "\"type\":\"u8\"") "abi-mw: IDL arg u8"
  expect (idl.contents.contains "\"type\":\"u16\"") "abi-mw: IDL arg u16"
  expect (idl.contents.contains "\"type\":\"u32\"") "abi-mw: IDL arg u32"
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

/-- T8b: UInt128 state fail closed. -/
private unsafe def testUInt128StateRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "U128State" <|
    "  state big : UInt128\n\n" ++
    "  init() do\n" ++
    "    return\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  -- May fail at compile (Normalize unsupported) or Plan seam; both fail closed.
  let validated ← liftResult (← session.selectProgramV1 source
    "<solana-u128-state>" "Examples.U128State" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()
  | .ok compiled =>
      match irSolana compiled with
      | .error e =>
          expect (e.render.contains "UInt" || e.render.contains "width" ||
              e.render.contains "state" || e.render.contains "supported")
            s!"abi-mw: UInt128 state must fail at Solana plan, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "abi-mw: UInt128 state must fail closed on Solana"

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
  let plan ← liftResult (planSolana compiled)
  expect (plan.entries.map (·.resultKind) == #[.u8, .u16, .u32, .u64])
    "T9a: Solana resultKinds must be u8/u16/u32/u64"
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

/-- T9a: UInt128 entry result remains fail closed on Solana. -/
private unsafe def testUInt128ResultRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "U128Ret" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run() : UInt128 do\n" ++
    "    return 0\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← liftResult (← session.selectProgramV1 source
    "<solana-u128-ret>" "Examples.U128Ret" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()
  | .ok compiled =>
      match irSolana compiled with
      | .error e =>
          expect (e.render.contains "return" || e.render.contains "UInt" ||
              e.render.contains "result" || e.render.contains "supported")
            s!"T9a: UInt128 result error should mention return width, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "T9a: UInt128 entry result must fail closed"

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

unsafe def run : IO Unit := do
  testLayoutExact16
  testLayoutVariesWithDataLen
  testDiscriminatorLe
  testFrameBudgetConstant
  let session ← Tests.Language.ParserSession.shared
  testCounterAsm session
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
  testUInt128StateRejected session
  testNarrowResultAdmitted session
  testUInt128ResultRejected session
  testSourceE2E session
  IO.println "Tests.Targets.SolanaAsmV1: ok"

end Tests.Targets.SolanaAsmV1
