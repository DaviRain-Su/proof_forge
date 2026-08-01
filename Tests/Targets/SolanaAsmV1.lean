import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

/-!
# Tests.Targets.SolanaAsmV1 — S1a typed IR → SBPF assembly (.s)

Pins layout `.equ` offsets (including exactDataLen-derived post-account
region), Counter entrypoint dispatch, checked_add overflow sequence,
`sol_set_return_data`, and fail-closed unsupported ops. Does not invoke
the external `sbpf` toolchain.
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

private def irSolana (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← solanaCapability compiled
  irFromCapability capability

private def filesSolana (compiled : CompiledSemanticV1) : CompileResult (Array OutputFile) := do
  let capability ← solanaCapability compiled
  buildFromCapability capability

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  s!"program {name} where\n" ++ body ++
  "\nend ProofForgeV2.Examples\n"

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
  -- 8-byte alignment: dataEnd = 0x60 + D + 0x2800
  let end8 := 0x60 + 8 + 10240
  let align8 := (8 - (end8 % 8)) % 8
  expect (l8.rentEpoch == end8 + align8)
    s!"layout8: rentEpoch formula, got {l8.rentEpoch}"

/-- Discriminator hex → LE u64 for ldxdw comparison. -/
private def testDiscriminatorLe : IO Unit := do
  -- bytes 01 00 00 00 00 00 00 00 → LE u64 = 1
  let v ← liftResult <| discriminatorToLeU64V1 "0100000000000000"
  expect (v == 1) s!"disc LE: expected 1, got {v}"
  let v2 ← liftResult <| discriminatorToLeU64V1 "0000000000000001"
  expect (v2 == 0x0100000000000000) s!"disc LE high byte, got {v2}"
  match discriminatorToLeU64V1 "abcd" with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "disc: short hex must fail"

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
  -- Deterministic rebuild
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asm == asm2) "asm: deterministic rebuild"

/-- Product emit still only ships .sbpf-plan + idl (no .s in product path). -/
private unsafe def testProductEmitUnchanged
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-asm-product>"
  let files ← liftResult <| filesSolana compiled
  let paths := files.map (·.path)
  expect (paths.any (· == "Counter.sbpf-plan")) "product: still has .sbpf-plan"
  expect (paths.any (· == "Counter.idl.json")) "product: still has idl"
  expect (!paths.any (fun p => p.endsWith ".s"))
    "product: must not yet publish .s (S1a emitter is additive-only)"
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

/-- S1b ops fail closed at the assembly boundary. -/
private unsafe def testUnsupportedOpsFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- if-region is outside S1a
  let ifSrc := wrapProgram "IfAsm" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    if x > 0 then\n" ++
    "      count := count + x\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session ifSrc "Examples.IfAsm" "<solana-asm-if>"
  let ir ← liftResult <| irSolana compiled
  match emitSbpfAsmV1 ir with
  | .ok _ => throw <| IO.userError "if-region must fail closed at S1a asm emit"
  | .error e =>
      expect (e.render.contains "ifRegion" || e.render.contains "S1a")
        s!"if-region fail detail: {e.render}"
  -- mul
  let mulSrc := wrapProgram "MulAsm" <|
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    count := count * x\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let mulCompiled ← compileSource session mulSrc "Examples.MulAsm" "<solana-asm-mul>"
  let mulIr ← liftResult <| irSolana mulCompiled
  match emitSbpfAsmV1 mulIr with
  | .ok _ => throw <| IO.userError "mul must fail closed at S1a asm emit"
  | .error e =>
      expect (e.render.contains "mul" || e.render.contains "S1a")
        s!"mul fail detail: {e.render}"

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
  -- header 8 + 2*8 = 24
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

unsafe def run : IO Unit := do
  testLayoutExact16
  testLayoutVariesWithDataLen
  testDiscriminatorLe
  let session ← Tests.Language.ParserSession.shared
  testCounterAsm session
  testProductEmitUnchanged session
  testGuardedCounterAsm session
  testUnsupportedOpsFailClosed session
  testMultiFieldLayout session
  IO.println "Tests.Targets.SolanaAsmV1: ok"

end Tests.Targets.SolanaAsmV1
