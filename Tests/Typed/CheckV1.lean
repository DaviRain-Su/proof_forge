/-
  Tests.Typed.CheckV1 — multi-pass Typed checker composition suite.

  Pins phase order (structure → type → effect → bound → disclosure), single
  resolution pass (no duplicated resolution messages), analysisComplete/ok under
  duplicate fn keys, and independent coverage of type / effect / bound /
  disclosure errors.  Does not assert product CLI or alpha Typed.checkV1 wiring.
-/
import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.CheckV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Typed.CheckV1

open ProofForgeV2
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CheckV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.CheckV1"

private unsafe def checkResult
    (session : Language.Loader.ParserSession) (label source : String) :
    IO TypedCheckResultV1 := do
  match ← session.selectProgramV1 source ("<typed-check-" ++ label ++ ">") moduleName none with
  | .ok validated => pure (checkProgramTypedResultV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def checkDiags
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (Array DiagnosticV1) := do
  match ← session.selectProgramV1 source ("<typed-check-" ++ label ++ ">") moduleName none with
  | .ok validated => pure (checkProgramTypedV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def messages (diags : Array DiagnosticV1) : Array String :=
  diags.map (·.message)

private def wires (diags : Array DiagnosticV1) : Array String :=
  diags.map (·.code.wire)

private def contains (haystack : Array String) (needle : String) : Bool :=
  haystack.any (·.contains needle)

private def countNeedle (haystack : Array String) (needle : String) : Nat :=
  haystack.foldl (fun acc s => if s.contains needle then acc + 1 else acc) 0

private def expectOk (res : TypedCheckResultV1) (label : String) : IO Unit := do
  unless res.analysisComplete do
    throw <| IO.userError s!"{label}: expected analysisComplete, got incomplete"
  unless res.ok do
    throw <| IO.userError s!"{label}: expected ok, got diagnostics {messages res.diagnostics}"
  unless res.diagnostics.isEmpty do
    throw <| IO.userError s!"{label}: expected empty diagnostics, got {messages res.diagnostics}"

private def expectNotOk (res : TypedCheckResultV1) (label : String) : IO Unit := do
  if res.ok then
    throw <| IO.userError s!"{label}: expected not ok, got ok"
  else
    pure ()

/-- Counter-shaped happy path: public UInt64 state, init, entry increment, view get. -/
private unsafe def testCounterHappyPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CounterCheck where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let res ← checkResult session "counter-ok" source
  expectOk res "counter-ok"
  -- Diagnostics-only entry matches result diagnostics.
  let diags ← checkDiags session "counter-ok-diags" source
  unless diags.isEmpty do
    throw <| IO.userError s!"counter-ok-diags: expected empty, got {messages diags}"

/-- Type error only: return Bool from UInt64 entry. -/
private unsafe def testTypeErrorOnly
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TypeOnly where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let res ← checkResult session "type-only" source
  expectNotOk res "type-only"
  unless res.analysisComplete do
    throw <| IO.userError "type-only: expected analysisComplete"
  let msgs := messages res.diagnostics
  unless contains msgs "type mismatch" do
    throw <| IO.userError s!"type-only: expected type mismatch, got {msgs}"
  unless contains msgs "UInt64" && contains msgs "Bool" do
    throw <| IO.userError s!"type-only: expected UInt64 vs Bool, got {msgs}"
  -- No false effect/bound wires required for a pure type error.
  if contains (wires res.diagnostics) "PF-EFFECT-001" then
    throw <| IO.userError s!"type-only: unexpected PF-EFFECT-001, got {wires res.diagnostics}"
  if contains (wires res.diagnostics) "PF-BOUND-001" then
    throw <| IO.userError s!"type-only: unexpected PF-BOUND-001, got {wires res.diagnostics}"

/-- Effect error: pure fn reads state. -/
private unsafe def testEffectError
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffectOnly where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek()\n"
  let res ← checkResult session "effect-only" source
  expectNotOk res "effect-only"
  unless res.analysisComplete do
    throw <| IO.userError "effect-only: expected analysisComplete"
  let w := wires res.diagnostics
  unless contains w "PF-EFFECT-001" do
    throw <| IO.userError s!"effect-only: expected PF-EFFECT-001, got {w}"
  let msgs := messages res.diagnostics
  unless contains msgs "fn 'peek' does not allow effect 'state.read'" do
    throw <| IO.userError s!"effect-only: unexpected messages {msgs}"
  let rendered := res.diagnostics.map (·.renderHuman)
  unless rendered.any (·.startsWith "PF-EFFECT-001:") do
    throw <| IO.userError s!"effect-only: expected human PF-EFFECT-001, got {rendered}"

/-- Bound recursion: self-recursive pure fn.
    Expected codes (phase order):
      * structure/CallGraph: PF-SRC-INVALID  "recursive call cycle: f"
      * type: (none when bodies type-check)
      * effect: (none — pure recursion has no disallowed effects)
      * bound: PF-BOUND-001 "unbounded recursion (call cycle): f"
    Structure diagnostics must appear before bound diagnostics. -/
private unsafe def testBoundRecursionPhaseOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program SelfRec where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let res ← checkResult session "self-rec" source
  expectNotOk res "self-rec"
  unless res.analysisComplete do
    throw <| IO.userError "self-rec: expected analysisComplete"
  let msgs := messages res.diagnostics
  let w := wires res.diagnostics
  unless contains msgs "recursive call cycle: f" do
    throw <| IO.userError s!"self-rec: expected CallGraph cycle message, got {msgs}"
  unless contains w "PF-BOUND-001" do
    throw <| IO.userError s!"self-rec: expected PF-BOUND-001, got {w}"
  unless contains msgs "unbounded recursion (call cycle): f" do
    throw <| IO.userError s!"self-rec: expected bound cycle members, got {msgs}"
  -- Phase order: structure (recursive call cycle) before bound (unbounded recursion).
  let structIdx := msgs.findIdx? (·.contains "recursive call cycle")
  let boundIdx := msgs.findIdx? (·.contains "unbounded recursion (call cycle)")
  match structIdx, boundIdx with
  | some si, some bi =>
      unless si < bi do
        throw <| IO.userError s!"self-rec: structure must precede bound, got {msgs}"
  | _, _ =>
      throw <| IO.userError s!"self-rec: missing structure/bound indices, got {msgs}"

/-- Bound loop product overflow (triple nested for bounded 4096) without a type error.
    Placed on entry so pure-fn effect allowlist does not also fire.  Endpoints are
    typed UInt64 state places (bare integer literals are not default-width). -/
private unsafe def testBoundLoopProductOverflow
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestedThree4096 where\n" ++
    "  state total : UInt64\n" ++
    "  state start : UInt64\n" ++
    "  state stop : UInt64\n" ++
    "  entry run() do\n" ++
    "    for i in start ..< stop bounded 4096 do\n" ++
    "      for j in start ..< stop bounded 4096 do\n" ++
    "        for k in start ..< stop bounded 4096 do\n" ++
    "          total := i\n"
  let res ← checkResult session "loop-overflow" source
  expectNotOk res "loop-overflow"
  unless res.analysisComplete do
    throw <| IO.userError "loop-overflow: expected analysisComplete"
  let w := wires res.diagnostics
  unless contains w "PF-BOUND-001" do
    throw <| IO.userError s!"loop-overflow: expected PF-BOUND-001, got {w}"
  let msgs := messages res.diagnostics
  unless contains msgs "loop bound product overflows UInt32 in entry 'run' (bound 4096)" do
    throw <| IO.userError s!"loop-overflow: unexpected messages {msgs}"
  if contains msgs "type mismatch" then
    throw <| IO.userError s!"loop-overflow: unexpected type error, got {msgs}"

/-- Phase-order fixture: resolution failure + would-be type error.
    Structure/resolution diagnostics appear; type body is skipped so we do not
    cascade, and resolution messages are not duplicated by re-entry. -/
private unsafe def testPhaseOrderResolutionNoDup
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ResThenType where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return missing + true\n"
  let res ← checkResult session "phase-res" source
  expectNotOk res "phase-res"
  let msgs := messages res.diagnostics
  unless contains msgs "unknown" || contains msgs "missing" do
    throw <| IO.userError s!"phase-res: expected resolution diagnostic, got {msgs}"
  -- Single resolution pass: unknown/missing must not be duplicated.
  let unknownCount := countNeedle msgs "missing"
  unless unknownCount == 1 do
    throw <| IO.userError s!"phase-res: expected single 'missing' mention, got count={unknownCount} msgs={msgs}"
  -- Type body skipped when resolution fails: no forced UInt64/Bool cascade required.
  -- (May still be empty of type mismatch.)

/-- Structure cycle + type error: structure precedes type; bound cycle follows. -/
private unsafe def testPhaseOrderStructureThenType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program StructThenType where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let res ← checkResult session "struct-type" source
  expectNotOk res "struct-type"
  let msgs := messages res.diagnostics
  let si := msgs.findIdx? (·.contains "recursive call cycle")
  let ti := msgs.findIdx? (·.contains "type mismatch")
  let bi := msgs.findIdx? (·.contains "unbounded recursion (call cycle)")
  match si, ti with
  | some s, some t =>
      unless s < t do
        throw <| IO.userError s!"struct-type: structure before type failed, got {msgs}"
  | _, _ =>
      throw <| IO.userError s!"struct-type: missing structure/type diags, got {msgs}"
  match ti, bi with
  | some t, some b =>
      unless t < b do
        throw <| IO.userError s!"struct-type: type before bound failed, got {msgs}"
  | _, _ =>
      throw <| IO.userError s!"struct-type: missing type/bound diags, got {msgs}"

private def mkName (raw : String) : IO SourceNameComponentV1 :=
  match parseSourceNameComponentV1 raw with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"mkName: {e}"

/-- Duplicate fn key: ValidatedSourceV1 rejects duplicates at decl-set validation,
    so this exercises the composition core with tables built from a raw ProgramV1
    (same pattern as EffectCheckV1/BoundCheckV1).  Expect analysisComplete=false,
    ok=false, structural duplicate diagnostic, no invented effect allowlist success. -/
private unsafe def testDuplicateFnIncomplete
    (_session : Language.Loader.ParserSession) : IO Unit := do
  let progName ← mkName "DupFn"
  let helper ← mkName "helper"
  let runName ← mkName "run"
  let ret0 : BlockV1 := { statements := #[.return_ (some (.literal (.integer 0)))] }
  let ret1 : BlockV1 := { statements := #[.return_ (some (.literal (.integer 1)))] }
  let u64 : TypeV1 := .uint 64
  let fnA : FnDeclV1 := { name := helper, params := #[], result := u64, body := ret0 }
  let fnB : FnDeclV1 := { name := helper, params := #[], result := u64, body := ret1 }
  let entryDecl : EntryDeclV1 := { name := runName, params := #[], result := u64, body := ret0 }
  let progAst : ProgramV1 :=
    { name := progName, items := #[.fn fnA, .fn fnB, .entry entryDecl] }
  let (tables, st) := (buildTables progAst).run { diagnostics := #[] }
  unless tables.fn.hasDuplicateKey do
    throw <| IO.userError "dup-fn: expected hasDuplicateKey on fn table"
  unless contains (st.diagnostics.map (·.message)) "duplicate fn declaration 'helper'" do
    throw <| IO.userError s!"dup-fn: buildTables missing duplicate, got {st.diagnostics.map (·.message)}"
  -- Full resolution-shaped result with structural diagnostics and incomplete tables.
  let resolution : NameResolutionResultV1 :=
    { tables := tables
      diagnostics := st.diagnostics
      ok := false }
  let res := checkProgramTypedWithResolutionV1 progAst resolution
  unless !res.analysisComplete do
    throw <| IO.userError "dup-fn: expected analysisComplete = false"
  unless !res.ok do
    throw <| IO.userError "dup-fn: expected ok = false"
  unless contains (messages res.diagnostics) "duplicate fn declaration 'helper'" do
    throw <| IO.userError s!"dup-fn: expected structural diagnostic, got {messages res.diagnostics}"
  -- Must not invent effect allowlist / bound / disclosure flow diagnostics.
  if contains (wires res.diagnostics) "PF-EFFECT-001" then
    throw <| IO.userError s!"dup-fn: unexpected PF-EFFECT-001 under incomplete analysis, got {wires res.diagnostics}"
  if contains (wires res.diagnostics) "PF-BOUND-001" then
    throw <| IO.userError s!"dup-fn: unexpected PF-BOUND-001 under incomplete analysis, got {wires res.diagnostics}"
  if contains (wires res.diagnostics) "PF-VIS-001" then
    throw <| IO.userError s!"dup-fn: unexpected PF-VIS-001 under incomplete analysis, got {wires res.diagnostics}"

/-- Disclosure-only negative: private param returned to public return sink.
    Composed CheckV1 must surface PF-VIS-001 from DisclosureCheckV1 rules. -/
private unsafe def testDisclosureErrorOnly
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DisclosureOnly where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let res ← checkResult session "disclosure-only" source
  expectNotOk res "disclosure-only"
  unless res.analysisComplete do
    throw <| IO.userError "disclosure-only: expected analysisComplete"
  let w := wires res.diagnostics
  unless contains w "PF-VIS-001" do
    throw <| IO.userError s!"disclosure-only: expected PF-VIS-001, got {w}"
  let msgs := messages res.diagnostics
  unless contains msgs "disclosure violation: cannot flow 'private' into 'public'" do
    throw <| IO.userError s!"disclosure-only: unexpected messages {msgs}"
  let rendered := res.diagnostics.map (·.renderHuman)
  unless rendered.any (·.startsWith "PF-VIS-001:") do
    throw <| IO.userError s!"disclosure-only: expected human PF-VIS-001, got {rendered}"
  -- Pure disclosure fixture: no type/effect/bound noise required.
  if contains msgs "type mismatch" then
    throw <| IO.userError s!"disclosure-only: unexpected type error, got {msgs}"
  if contains w "PF-EFFECT-001" then
    throw <| IO.userError s!"disclosure-only: unexpected PF-EFFECT-001, got {w}"
  if contains w "PF-BOUND-001" then
    throw <| IO.userError s!"disclosure-only: unexpected PF-BOUND-001, got {w}"

/-- Phase-order fixture: pure-fn state.read (PF-EFFECT-001) plus private→public
    return (PF-VIS-001).  Effect phase must precede disclosure phase. -/
private unsafe def testPhaseOrderEffectThenDisclosure
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffectThenVis where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let res ← checkResult session "effect-vis" source
  expectNotOk res "effect-vis"
  unless res.analysisComplete do
    throw <| IO.userError "effect-vis: expected analysisComplete"
  let w := wires res.diagnostics
  unless contains w "PF-EFFECT-001" do
    throw <| IO.userError s!"effect-vis: expected PF-EFFECT-001, got {w}"
  unless contains w "PF-VIS-001" do
    throw <| IO.userError s!"effect-vis: expected PF-VIS-001, got {w}"
  let effectIdx := w.findIdx? (· == "PF-EFFECT-001")
  let visIdx := w.findIdx? (· == "PF-VIS-001")
  match effectIdx, visIdx with
  | some ei, some vi =>
      unless ei < vi do
        throw <| IO.userError s!"effect-vis: effect must precede disclosure, got {w}"
  | _, _ =>
      throw <| IO.userError s!"effect-vis: missing effect/disclosure wires, got {w}"

/-- Phase-order fixture: pure-fn self-recursion (PF-BOUND-001) plus private→public
    return (PF-VIS-001).  Bound phase must precede disclosure phase. -/
private unsafe def testPhaseOrderBoundThenDisclosure
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundThenVis where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let res ← checkResult session "bound-vis" source
  expectNotOk res "bound-vis"
  unless res.analysisComplete do
    throw <| IO.userError "bound-vis: expected analysisComplete"
  let w := wires res.diagnostics
  unless contains w "PF-BOUND-001" do
    throw <| IO.userError s!"bound-vis: expected PF-BOUND-001, got {w}"
  unless contains w "PF-VIS-001" do
    throw <| IO.userError s!"bound-vis: expected PF-VIS-001, got {w}"
  let boundIdx := w.findIdx? (· == "PF-BOUND-001")
  let visIdx := w.findIdx? (· == "PF-VIS-001")
  match boundIdx, visIdx with
  | some bi, some vi =>
      unless bi < vi do
        throw <| IO.userError s!"bound-vis: bound must precede disclosure, got {w}"
  | _, _ =>
      throw <| IO.userError s!"bound-vis: missing bound/disclosure wires, got {w}"

/-!
  Tests.Semantic.NormalizeV1 — S1 Semantic normalizer vertical contract suite.

  Hosted in this module file (Tests.Typed.CheckV1 is a CI-registered root that
  already imports ParserSession) under absolute namespace
  `Tests.Semantic.NormalizeV1`, so ordinary `just ci` / proof_forge_next_tests
  runs it via Tests.Typed.CheckV1.run without lakefile/Tests.lean edits.
-/
namespace Tests.Semantic.NormalizeV1

open ProofForgeV2
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CheckV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.NormalizeV1"

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source ("<normalize-" ++ label ++ ">") moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: load failed: {error.render}"

private def bytesEqual (a b : ByteArray) : Bool := a == b

/-- Require CheckV1 ok∧analysisComplete then normalize → .unsupported with detail pin. -/
private unsafe def expectUnsupportedAfterCheckOk
    (session : Language.Loader.ParserSession) (label source : String)
    (detailPred : String → Bool) (detailHint : String) : IO Unit := do
  let validated ← loadSource session label source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok s!"{label}: CheckV1.ok required for normalizer-boundary pin"
  expect typed.analysisComplete s!"{label}: CheckV1.analysisComplete"
  match normalizeProgramV1 validated with
  | .ok _ => throw <| IO.userError s!"{label}: expected unsupported, got carrier"
  | .error (.unsupported detail) =>
      expect (detailPred detail)
        s!"{label}: expected unsupported detail containing {detailHint}, got {detail}"
  | .error e =>
      throw <| IO.userError s!"{label}: expected .unsupported, got {repr e}"

/-- Pin Counter lowered instruction sequences (ValueId/StateId exact). -/
private def expectCounterOps
    (initC entryC viewC : CallableV1) (u64Tid : TypeIdV1) : IO Unit := do
  let some initBlk := initC.blocks[0]? |
    throw <| IO.userError "counter-ops: missing init block[0]"
  -- init: stateStore(state0, param0) + return none
  expect (initBlk.instructions.size == 1)
    s!"counter-ops: init instr count, got {initBlk.instructions.size}"
  let some i0 := initBlk.instructions[0]? |
    throw <| IO.userError "counter-ops: missing init instr[0]"
  expect (i0.result.isNone) "counter-ops: init stateStore is void"
  match i0.op with
  | .stateStore sid vid =>
      expect (sid == 0 && vid == 0) s!"counter-ops: init store state0 param0, got {sid}/{vid}"
  | _ => throw <| IO.userError "counter-ops: init expected stateStore"
  match initBlk.terminator with
  | .return_ none => pure ()
  | _ => throw <| IO.userError "counter-ops: init return none"

  let some entryBlk := entryC.blocks[0]? |
    throw <| IO.userError "counter-ops: missing entry block[0]"
  -- entry: load count → vid1; add(load,param0) → vid2; store; load → vid3; return some vid3
  expect (entryBlk.instructions.size == 4)
    s!"counter-ops: entry instr count, got {entryBlk.instructions.size}"
  let some e0 := entryBlk.instructions[0]? |
    throw <| IO.userError "counter-ops: missing entry instr[0]"
  let some e1 := entryBlk.instructions[1]? |
    throw <| IO.userError "counter-ops: missing entry instr[1]"
  let some e2 := entryBlk.instructions[2]? |
    throw <| IO.userError "counter-ops: missing entry instr[2]"
  let some e3 := entryBlk.instructions[3]? |
    throw <| IO.userError "counter-ops: missing entry instr[3]"
  let some rd0 := e0.result |
    throw <| IO.userError "counter-ops: entry[0] missing result"
  match e0.op with
  | .stateLoad sid =>
      expect (rd0.valueId == 1 && rd0.typeId == u64Tid && sid == 0)
        s!"counter-ops: entry load vid1/state0, got {rd0.valueId}/{sid}"
  | _ => throw <| IO.userError "counter-ops: entry[0] stateLoad"
  let some rd1 := e1.result |
    throw <| IO.userError "counter-ops: entry[1] missing result"
  match e1.op with
  | .binary op lhs rhs =>
      expect (op == ProofForgeV2.Semantic.WireV1.BinaryOpV1.add
          && rd1.valueId == 2 && rd1.typeId == u64Tid && lhs == 1 && rhs == 0)
        s!"counter-ops: entry add vid2=load+param, got {rd1.valueId}/{lhs}/{rhs}"
  | _ => throw <| IO.userError "counter-ops: entry[1] binary add"
  expect e2.result.isNone "counter-ops: entry[2] void store"
  match e2.op with
  | .stateStore sid vid =>
      expect (sid == 0 && vid == 2)
        s!"counter-ops: entry store state0 vid2, got {sid}/{vid}"
  | _ => throw <| IO.userError "counter-ops: entry[2] stateStore"
  let some rd3 := e3.result |
    throw <| IO.userError "counter-ops: entry[3] missing result"
  match e3.op with
  | .stateLoad sid =>
      expect (rd3.valueId == 3 && rd3.typeId == u64Tid && sid == 0)
        s!"counter-ops: entry return-load vid3, got {rd3.valueId}/{sid}"
  | _ => throw <| IO.userError "counter-ops: entry[3] stateLoad"
  match entryBlk.terminator with
  | .return_ (some vid) =>
      expect (vid == 3) s!"counter-ops: entry return some 3, got {vid}"
  | _ => throw <| IO.userError "counter-ops: entry return some"

  let some viewBlk := viewC.blocks[0]? |
    throw <| IO.userError "counter-ops: missing view block[0]"
  expect (viewBlk.instructions.size == 1)
    s!"counter-ops: view instr count, got {viewBlk.instructions.size}"
  let some v0 := viewBlk.instructions[0]? |
    throw <| IO.userError "counter-ops: missing view instr[0]"
  let some vrd := v0.result |
    throw <| IO.userError "counter-ops: view[0] missing result"
  match v0.op with
  | .stateLoad sid =>
      expect (vrd.valueId == 0 && vrd.typeId == u64Tid && sid == 0)
        s!"counter-ops: view load vid0/state0, got {vrd.valueId}/{sid}"
  | _ => throw <| IO.userError "counter-ops: view[0] stateLoad"
  match viewBlk.terminator with
  | .return_ (some vid) =>
      expect (vid == 0) s!"counter-ops: view return some 0, got {vid}"
  | _ => throw <| IO.userError "counter-ops: view return some"

private unsafe def testCounterHappyPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "CounterNorm" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "counter" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "counter: CheckV1.ok"
  expect typed.analysisComplete "counter: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"counter: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"counter: validate failed: {repr e}"
  expect (data.qualifiedName.components.toArray.size ≥ 2)
    "counter: qualifiedName has ≥2 components"
  expect (data.types.size == 2) s!"counter: expected 2 types, got {data.types.size}"
  expect (data.types.any fun t =>
      t.name.isNone && match t.shape with | .uint 64 => true | _ => false)
    "counter: has anonymous UInt64"
  expect (data.types.any fun t =>
      t.name.isNone && match t.shape with | .unit => true | _ => false)
    "counter: has anonymous Unit"
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  expect (data.logicalState.size == 1) s!"counter: state size, got {data.logicalState.size}"
  let some st0 := data.logicalState[0]? |
    throw <| IO.userError "counter: missing state[0]"
  expect (st0.name == "count") "counter: state name count"
  expect (st0.visibility == .public_) "counter: state public"
  expect (st0.id == 0 && st0.typeId == u64Tid) "counter: state0 UInt64"
  expect (data.callables.size == 3) s!"counter: 3 callables, got {data.callables.size}"
  let some initC := data.callables[0]? |
    throw <| IO.userError "counter: missing callables[0]"
  let some entryC := data.callables[1]? |
    throw <| IO.userError "counter: missing callables[1]"
  let some viewC := data.callables[2]? |
    throw <| IO.userError "counter: missing callables[2]"
  expect (initC.kind == .initializer && initC.name.isNone) "counter: init kind/name"
  let some initBlk := initC.blocks[0]? |
    throw <| IO.userError "counter: missing init block[0]"
  expect (initC.entryBlock == 0 && initC.blocks.size == 1 && initBlk.id == 0)
    "counter: init single block 0"
  expect (initC.loopBounds.isEmpty && initC.invariantSteps.isNone)
    "counter: init empty loopBounds/invariantSteps"
  expect (entryC.kind == .entry && entryC.name == some "increment")
    "counter: entry increment"
  expect (viewC.kind == .view && viewC.name == some "get") "counter: view get"
  expect (data.constants.isEmpty && data.events.isEmpty && data.errors.isEmpty
      && data.invariants.isEmpty && data.requirements.items.isEmpty)
    "counter: empty constants/events/errors/invariants/requirements"
  expectCounterOps initC entryC viewC u64Tid
  let decoded ← match decodeSemanticProgramV1 carrier.canonicalBytes with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"counter: decode carrier failed: {repr e}"
  expect (bytesEqual decoded.canonicalBytes carrier.canonicalBytes)
    "counter: decodeSemanticProgramV1 byte identity"
  let hash ← match semanticHashV1 carrier with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"counter: semanticHash failed: {repr e}"
  expect (hash.bytes.size == 32) "counter: semanticHash is 32 bytes"

private unsafe def testStateAfterInit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "StateAfter" <|
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  state count : UInt64\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "state-after" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "state-after: CheckV1.ok"
  expect typed.analysisComplete "state-after: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"state-after: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"state-after: validate failed: {repr e}"
  expect (data.logicalState.size == 1) "state-after: one state"
  let some st0 := data.logicalState[0]? |
    throw <| IO.userError "state-after: missing state[0]"
  expect (st0.name == "count" && st0.id == 0) "state-after: count id 0"
  expect (data.callables.size == 3) "state-after: 3 callables"
  let some initC := data.callables[0]? |
    throw <| IO.userError "state-after: missing init"
  let some entryC := data.callables[1]? |
    throw <| IO.userError "state-after: missing entry"
  let some viewC := data.callables[2]? |
    throw <| IO.userError "state-after: missing view"
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  expectCounterOps initC entryC viewC u64Tid

private unsafe def testDeterminism
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "CounterDet" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let v1 ← loadSource session "det-a" source
  let v2 ← loadSource session "det-b" source
  let c1 ← match normalizeProgramV1 v1 with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"det-a: {repr e}"
  let c2 ← match normalizeProgramV1 v2 with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"det-b: {repr e}"
  expect (bytesEqual c1.canonicalBytes c2.canonicalBytes)
    "determinism: canonicalBytes equal"
  let h1 ← match semanticHashV1 c1 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"det hash1: {repr e}"
  let h2 ← match semanticHashV1 c2 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"det hash2: {repr e}"
  expect (h1 == h2) "determinism: semanticHash equal"
  let c1b ← match normalizeProgramV1 v1 with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"det-repeat: {repr e}"
  expect (bytesEqual c1.canonicalBytes c1b.canonicalBytes)
    "determinism: repeat normalize on same ValidatedSourceV1"

private unsafe def testTypedNotOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "TypeBad" <|
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let validated ← loadSource session "typed-bad" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok) "typed-bad: CheckV1 not ok"
  match normalizeProgramV1 validated with
  | .ok _ => throw <| IO.userError "typed-bad: expected no carrier"
  | .error (.typedNotOk _) => pure ()
  | .error e => throw <| IO.userError s!"typed-bad: expected typedNotOk, got {repr e}"

private unsafe def testUnsupportedLiteral
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "LitOnly" <|
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  expectUnsupportedAfterCheckOk session "lit" source
    (fun d => d.contains "literal" || d.contains "Literal" || d.contains "literals")
    "literal"

private unsafe def testUnsupportedIf
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "IfOnly" <|
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    if true then\n" ++
    "      return x\n" ++
    "    else\n" ++
    "      return x\n"
  expectUnsupportedAfterCheckOk session "if" source
    (fun d => d.contains "if" || d.contains "If")
    "if"

private unsafe def testUnsupportedFn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FnOnly" <|
    "  fn helper(x : UInt64) : UInt64 do\n" ++
    "    return x\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    return helper(x)\n"
  expectUnsupportedAfterCheckOk session "fn" source
    (fun d => d.contains "fn" || d.contains "localCall" || d.contains "local")
    "fn/localCall"

private unsafe def testUnsupportedPrivateState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "PrivState" <|
    "  state private secret : UInt64\n" ++
    "  entry ping(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  expectUnsupportedAfterCheckOk session "priv" source
    (fun d => d.contains "public" || d.contains "private" || d.contains "non-public")
    "public/non-public state"

private unsafe def testUnsupportedParamShadowsStateAssign
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ParamShadowAssign" <|
    "  state x : UInt64\n" ++
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    x := x\n" ++
    "    return x\n"
  expectUnsupportedAfterCheckOk session "param-shadow-assign" source
    (fun d =>
      d.contains "param" || d.contains "state place" || d.contains "not a param")
    "param assign / state place"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testCounterHappyPath session
  testStateAfterInit session
  testDeterminism session
  testTypedNotOk session
  testUnsupportedLiteral session
  testUnsupportedIf session
  testUnsupportedFn session
  testUnsupportedPrivateState session
  testUnsupportedParamShadowsStateAssign session
  IO.println "Tests.Semantic.NormalizeV1: ok"

end Tests.Semantic.NormalizeV1

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testCounterHappyPath session
  testTypeErrorOnly session
  testEffectError session
  testBoundRecursionPhaseOrder session
  testBoundLoopProductOverflow session
  testPhaseOrderResolutionNoDup session
  testPhaseOrderStructureThenType session
  testDuplicateFnIncomplete session
  testDisclosureErrorOnly session
  testPhaseOrderEffectThenDisclosure session
  testPhaseOrderBoundThenDisclosure session
  IO.println "Tests.Typed.CheckV1: ok"
  -- S1 normalizer vertical contract (Loader→CheckV1→Normalize→Wire); CI pin.
  Tests.Semantic.NormalizeV1.run

end Tests.Typed.CheckV1
