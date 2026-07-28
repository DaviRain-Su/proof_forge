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
import ProofForgeV2.Semantic.ProvenanceV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.WireV1

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

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProvenanceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.CheckV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.NormalizeV1"

/-- Project-relative path accepted by SourceOrigin validation (no angle brackets). -/
private def testSourcePath (label : String) : String :=
  "tests/normalize-" ++ label ++ ".pf"

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source (testSourcePath label) moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: load failed: {error.render}"

private unsafe def loadSourceWithSpans
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans source (testSourcePath label) moduleName none with
  | .ok pair => pure pair
  | .error error => throw <| IO.userError s!"{label}: load+spans failed: {error.render}"

private def parseTestPath (label : String) : IO ProjectRelativePath := do
  match parseProjectRelativePath (testSourcePath label) with
  | .ok p => pure p
  | .error e => throw <| IO.userError s!"{label}: path: {e}"

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
      && data.invariants.isEmpty)
    "counter: empty constants/events/errors/invariants"
  -- S2 exact requirements freeze (SPEC wire order, not first-seen).
  expect (data.requirements.items.size == 3)
    s!"counter: expected 3 requirements, got {data.requirements.items.size}"
  let expectReq (i : Nat) (id : String) : IO Unit := do
    let some item := data.requirements.items[i]? |
      throw <| IO.userError s!"counter: missing requirement[{i}]"
    expect (item.id == id) s!"counter: req[{i}] id, got {item.id}"
    expect (item.version.major == 1 && item.version.minor == 0 &&
        item.version.patch == 0 && item.version.prerelease.isEmpty &&
        item.version.build.isEmpty)
      s!"counter: req[{i}] version 1.0.0"
    expect item.predicates.isEmpty s!"counter: req[{i}] empty predicates"
    let dig ← match ProofForgeV2.Semantic.RequirementsV1.engineeringRequirementDigestV1 id with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"counter: digest {id}: {e}"
    expect (item.digest == dig) s!"counter: req[{i}] engineering digest"
  expectReq 0 "failure.atomic-rollback"
  expectReq 1 "state.persistent"
  expectReq 2 "value.checked-arithmetic"
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

/-- Low-level Wire join helper (not source-bound authority). -/
private def joinHelper
    (moduleQn idQn : QualifiedName)
    (srcHash : Digest)
    (expectedMap : Array OriginBindingV1)
    (inventory : SourceNodeInventoryV1)
    (carrier : SemanticProgramV1)
    (provenance : SemanticProvenanceV1) :
    Except SemanticWireErrorV1 Unit :=
  validateSemanticProvenanceJoinV1
    moduleQn idQn srcHash expectedMap inventory carrier provenance

private def joinDigestHelper
    (moduleQn idQn : QualifiedName)
    (srcHash : Digest)
    (expectedMap : Array OriginBindingV1)
    (inventory : SourceNodeInventoryV1)
    (carrier : SemanticProgramV1)
    (provenance : SemanticProvenanceV1) :
    Except SemanticWireErrorV1 Digest :=
  semanticProvenanceDigestJoinV1
    moduleQn idQn srcHash expectedMap inventory carrier provenance

private def findOrigin
    (provenance : SemanticProvenanceV1) (entity : SemanticEntityRefV1) :
    Option SourceOrigin :=
  provenance.originMap.findSome? fun b =>
    if b.entity == entity then b.origins[0]? else none

private def findOrigins
    (provenance : SemanticProvenanceV1) (entity : SemanticEntityRefV1) :
    Array SourceOrigin :=
  match provenance.originMap.findSome? fun b =>
    if b.entity == entity then some b.origins else none with
  | some os => os
  | none => #[]

private def childPathT
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    NormalizedSyntacticPathV1 :=
  path.push {
    parentTag := parentTag
    fieldTag := fieldTag
    index := UInt32.ofNat index
  }

private def directChildT
    (path : NormalizedSyntacticPathV1) (parentTag fieldTag : String) :
    NormalizedSyntacticPathV1 :=
  childPathT path parentTag fieldTag 0

/-- Test-only reconstruction of the retired delimiter key, used to exhibit the
    alias that production length framing must distinguish. -/
private def legacyDelimiterPathKey
    (path : NormalizedSyntacticPathV1) : String :=
  Id.run do
    let mut parts : Array String := Array.mkEmpty path.size
    for seg in path do
      parts := parts.push
        s!"{seg.parentTag}\x1f{seg.fieldTag}\x1f{seg.index.toNat}"
    pure (String.intercalate "\x1e" parts.toList)

/-- Independent origin at an explicit syntactic path via assignNodeIdsV1 + inventory. -/
private def originAtExplicitPath
    (source : ValidatedSourceV1)
    (inventory : SourceNodeInventoryV1)
    (path : NormalizedSyntacticPathV1) :
    IO SourceOrigin := do
  let table ← match assignNodeIdsV1
      source.moduleName source.programIdentity source.program with
    | .ok t => pure t
    | .error e => throw <| IO.userError s!"assignNodeIdsV1: {e}"
  let assignments := nodeAssignmentsPreorderV1 table
  let mut nodeId? : Option NodeId := none
  for a in assignments do
    if a.path == path then
      nodeId? := some a.nodeId
  let some nid := nodeId? |
    throw <| IO.userError s!"no NodeId for path key={pathLookupKeyV1 path}"
  let mut origin? : Option SourceOrigin := none
  for o in inventory.nodes do
    if o.nodeId == nid then
      origin? := some o
  let some origin := origin? |
    throw <| IO.userError "NodeId not present in inventory"
  pure origin

private def sortOriginsByWire
    (origins : Array SourceOrigin) : IO (Array SourceOrigin) := do
  let mut keyed : Array (ByteArray × SourceOrigin) := #[]
  for o in origins do
    match encodeSourceOrigin o with
    | .ok kb => keyed := keyed.push (kb, o)
    | .error e => throw <| IO.userError s!"encodeSourceOrigin: {repr e}"
  let sorted := keyed.qsort fun a b =>
    let n := Nat.min a.1.size b.1.size
    let rec loop (i : Nat) : Ordering :=
      if i < n then
        let bl := a.1.get! i
        let br := b.1.get! i
        if bl.toNat < br.toNat then .lt
        else if bl.toNat > br.toNat then .gt
        else loop (i + 1)
      else if a.1.size < b.1.size then .lt
      else if a.1.size > b.1.size then .gt
      else .eq
    loop 0 == .lt
  pure (sorted.map (·.2))

/-- S2: Counter requirements + exact attribution + complete join / negatives. -/
private unsafe def testCounterRequirementsAndProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let sourceText := wrap "CounterProv" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "prov" sourceText
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "prov: CheckV1.ok"
  expect typed.analysisComplete "prov: CheckV1.analysisComplete"
  let path ← parseTestPath "prov"
  -- Source OriginJoin is sole exact join; Semantic inventory is a thin projection.
  let sourceInv ← match joinOriginsV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"prov: source origin join: {repr e}"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"prov: inventory: {repr e}"
  expect (!inventory.nodes.isEmpty) "prov: inventory nonempty"
  let srcHash ← match sourceHashV1 validated with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"prov: sourceHash: {e}"
  expect (originInventorySourceHashV1 sourceInv == srcHash)
    "prov: Source inventory sourceHash == sourceHashV1"
  expect (inventory.sourceHash == originInventorySourceHashV1 sourceInv)
    "prov: Semantic projection sourceHash == Source inventory"
  expect (inventory.nodes == originInventoryOriginsV1 sourceInv)
    "prov: Semantic projection nodes == Source NodeId-ordered origins"
  expect (inventory.sourceHash == srcHash) "prov: inventory.sourceHash == sourceHashV1"
  match validateSourceNodeInventoryExactV1 validated inventory with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"prov: inventory exact: {repr e}"
  let pair ← match normalizeProgramWithProvenanceV1 validated path spans with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"prov: normalize+provenance: {repr e}"
  let (carrier, provenance) := pair
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"prov: validate program: {repr e}"
  -- Requirements exact
  expect (data.requirements.items.size == 3) "prov: 3 requirements"
  let some r0 := data.requirements.items[0]? |
    throw <| IO.userError "prov: missing req0"
  let some r1 := data.requirements.items[1]? |
    throw <| IO.userError "prov: missing req1"
  let some r2 := data.requirements.items[2]? |
    throw <| IO.userError "prov: missing req2"
  expect (r0.id == "failure.atomic-rollback")
    "prov: req0 failure.atomic-rollback"
  expect (r1.id == "state.persistent")
    "prov: req1 state.persistent"
  expect (r2.id == "value.checked-arithmetic")
    "prov: req2 value.checked-arithmetic"
  let semHash ← match semanticHashV1 carrier with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"prov: semanticHash: {repr e}"
  expect (provenance.schema.value == semanticProvenanceSchemaIdV1)
    "prov: schema id"
  expect (provenance.qualifiedName == data.qualifiedName)
    "prov: qualifiedName joins program"
  expect (provenance.sourceHash == srcHash) "prov: sourceHash"
  expect (provenance.semanticHash == semHash) "prov: semanticHash"
  let expectedEntities := collectProgramEntityRefsV1 data
  expect (provenance.originMap.size == expectedEntities.size)
    s!"prov: originMap size {provenance.originMap.size} vs entities {expectedEntities.size}"
  -- Exact distinct origins for representative entities (not a single default NodeId).
  expect (data.logicalState.size == 1) "prov: one state"
  expect (data.callables.size == 3) "prov: init/entry/view"
  let some stateOrigin := findOrigin provenance (.state 0) |
    throw <| IO.userError "prov: missing state origin"
  let some initOrigin := findOrigin provenance (.callable 0) |
    throw <| IO.userError "prov: missing init callable origin"
  let some entryOrigin := findOrigin provenance (.callable 1) |
    throw <| IO.userError "prov: missing entry callable origin"
  let some viewOrigin := findOrigin provenance (.callable 2) |
    throw <| IO.userError "prov: missing view callable origin"
  expect (stateOrigin != initOrigin) "prov: state origin ≠ init origin"
  expect (initOrigin != entryOrigin) "prov: init origin ≠ entry origin"
  expect (entryOrigin != viewOrigin) "prov: entry origin ≠ view origin"
  expect (stateOrigin != entryOrigin) "prov: state origin ≠ entry origin"
  -- Entry body lowering (NormalizeV1):
  --   count := count + delta  → StateLoad count, Binary add, StateStore
  --   return count            → StateLoad count, Return terminator
  -- Instruction indices: 0=load, 1=add, 2=store, 3=load-for-return.
  let some entryC := data.callables[1]? |
    throw <| IO.userError "prov: missing entry callable data"
  let some entryBlock := entryC.blocks[0]? |
    throw <| IO.userError "prov: missing entry block"
  expect (entryBlock.instructions.size == 4)
    s!"prov: entry instr count {entryBlock.instructions.size}"
  let some addOrigin :=
      findOrigin provenance (.instruction 1 0 1) |
    throw <| IO.userError "prov: missing binary-add instruction origin"
  let some storeOrigin :=
      findOrigin provenance (.instruction 1 0 2) |
    throw <| IO.userError "prov: missing stateStore instruction origin"
  let some retOrigin :=
      findOrigin provenance (.terminator 1 0) |
    throw <| IO.userError "prov: missing entry terminator origin"
  expect (addOrigin != storeOrigin) "prov: add origin ≠ store origin"
  expect (storeOrigin != retOrigin) "prov: store origin ≠ return origin"
  expect (addOrigin != stateOrigin) "prov: add origin ≠ state decl origin"
  -- Requirements: persistent from state; arithmetic/rollback from add expr (same site).
  let some req0Origin := findOrigin provenance (.requirement 0) |
    throw <| IO.userError "prov: missing requirement 0 origin"
  let some req1Origin := findOrigin provenance (.requirement 1) |
    throw <| IO.userError "prov: missing requirement 1 origin"
  let some req2Origin := findOrigin provenance (.requirement 2) |
    throw <| IO.userError "prov: missing requirement 2 origin"
  expect (req1Origin == stateOrigin)
    "prov: state.persistent origin == state decl"
  expect (req0Origin == addOrigin)
    "prov: failure.atomic-rollback origin == binary add"
  expect (req2Origin == addOrigin)
    "prov: value.checked-arithmetic origin == binary add"
  expect (req1Origin != req0Origin)
    "prov: state.persistent origin ≠ arithmetic/rollback origin"
  -- Module + identity for Wire join
  let moduleQn ← match sourceQualifiedNameToCommonV1 validated.moduleName with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"prov: moduleQn: {repr e}"
  let idQn := provenance.qualifiedName
  match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1 validated path spans carrier provenance with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"prov: complete join: {repr e}"
  match joinHelper moduleQn idQn srcHash provenance.originMap inventory carrier provenance with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"prov: wire join: {repr e}"
  let dig1 ← match ProofForgeV2.Semantic.NormalizeV1.semanticProvenanceDigestV1
      validated path spans carrier provenance with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"prov: digest1: {repr e}"
  let dig2 ← match ProofForgeV2.Semantic.NormalizeV1.semanticProvenanceDigestV1
      validated path spans carrier provenance with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"prov: digest2: {repr e}"
  expect (dig1 == dig2) "prov: digest deterministic"
  let enc ← match encodeSemanticProvenanceV1 provenance with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"prov: encode: {repr e}"
  let dec ← match decodeSemanticProvenanceV1 enc with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"prov: decode: {repr e}"
  expect (dec == provenance) "prov: provenance round-trip"
  expect (dig1 == sha256Bytes enc) "prov: digest is SHA-256 of canonical envelope"
  -- Arbitrary inventory-valid origin reassignment must FAIL validation + digest.
  if inventory.nodes.size < 2 then
    throw <| IO.userError
      "prov: inventory must have ≥2 nodes for origin substitution negative"
  let some last := provenance.originMap[provenance.originMap.size - 1]? |
    throw <| IO.userError "prov: empty originMap"
  let some curOrigin := last.origins[0]? |
    throw <| IO.userError "prov: last binding missing origin"
  -- Pick an inventory origin different from the expected one for this entity.
  let mut altOrigin? : Option SourceOrigin := none
  for n in inventory.nodes do
    if n != curOrigin then
      altOrigin? := some n
  let some altOrigin := altOrigin? |
    throw <| IO.userError "prov: no alternate inventory origin for substitution"
  let mutatedBinding : OriginBindingV1 := {
    entity := last.entity
    origins := #[altOrigin]
  }
  let mut mutMap := provenance.originMap.pop
  mutMap := mutMap.push mutatedBinding
  let mutatedBad : SemanticProvenanceV1 := { provenance with originMap := mutMap }
  expect (match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier mutatedBad with
    | .error _ => true | .ok () => false)
    "prov: arbitrary inventory-valid origin substitution → complete join fails"
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier mutatedBad with
    | .error .badProvenance => true | _ => false)
    "prov: origin substitution vs expectedOriginMap → badProvenance"
  -- Digest must not swallow validation failure.
  expect (match ProofForgeV2.Semantic.NormalizeV1.semanticProvenanceDigestV1
      validated path spans carrier mutatedBad with
    | .error _ => true | .ok _ => false)
    "prov: digest fails closed on origin substitution"
  expect (match joinDigestHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier mutatedBad with
    | .error .badProvenance => true | _ => false)
    "prov: wire digest fails closed on origin substitution"
  expect (mutatedBad.semanticHash == semHash)
    "prov: origin mutation keeps semanticHash field"
  let sem2 ← match semanticHashV1 carrier with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"prov: sem2: {repr e}"
  expect (sem2 == semHash) "prov: semanticHash independent of provenance"
  -- Re-normalize: same semanticHash
  let carrier2 ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"prov: renorm: {repr e}"
  let semR ← match semanticHashV1 carrier2 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"prov: semR: {repr e}"
  expect (semR == semHash) "prov: re-normalize stable semanticHash"
  -- Inventory negatives: Source OriginJoin + Semantic thin projection parity.
  let some (p0, sp0) := spans[0]? |
    throw <| IO.userError "prov: spans empty"
  let dupSpans := spans.push (p0, sp0)
  expect (match joinOriginsV1 validated path dupSpans with
    | .error (.inventory detail) => detail.startsWith "duplicate span path"
    | _ => false)
    "prov: Source duplicate span path rejected"
  expect (match buildSourceNodeInventoryV1 validated path dupSpans with
    | .error (.inventory detail) => detail.startsWith "duplicate span path"
    | _ => false)
    "prov: Semantic projection duplicate span path rejected"
  -- Extra distinct span path absent from the production assignment table.
  let extraPath := p0.push {
    parentTag := "Foreign"
    fieldTag := "extra"
    index := UInt32.ofNat 0
  }
  let extraSpans := spans.push (extraPath, sp0)
  expect (match joinOriginsV1 validated path extraSpans with
    | .error (.inventory detail) => detail.startsWith "extra span path"
    | _ => false)
    "prov: Source extra span path rejected"
  expect (match buildSourceNodeInventoryV1 validated path extraSpans with
    | .error (.inventory detail) => detail.startsWith "extra span path"
    | _ => false)
    "prov: Semantic projection extra span path rejected"
  -- Delimiter-bearing alias: would collide under legacy \x1f/\x1e key encoding
  -- but is a distinct structural path under Source length-framed pathLookupKeyV1.
  -- [{X, Y\x1fZ, 0}] vs [{X\x1fY, Z, 0}] share one legacy key.
  let aliasA : NormalizedSyntacticPathV1 := #[{
    parentTag := "X", fieldTag := "Y\x1fZ", index := 0 }]
  let aliasB : NormalizedSyntacticPathV1 := #[{
    parentTag := "X\x1fY", fieldTag := "Z", index := 0 }]
  expect (legacyDelimiterPathKey aliasA ==
      legacyDelimiterPathKey aliasB)
    "prov: legacy delimiter keys collide for alias pair"
  expect (pathLookupKeyV1 aliasA != pathLookupKeyV1 aliasB)
    "prov: Source length-framed keys distinguish delimiter alias pair"
  -- Replacing a real span path with aliasA → missing real path detection.
  let mut replacedSpans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1) := #[]
  let mut replaced := false
  for (p, sp) in spans do
    if !replaced && p == p0 then
      replacedSpans := replacedSpans.push (aliasA, sp)
      replaced := true
    else
      replacedSpans := replacedSpans.push (p, sp)
  expect replaced "prov: replaced first span path with delimiter alias"
  expect (match joinOriginsV1 validated path replacedSpans with
    | .error (.inventory detail) =>
        detail.startsWith "missing span" || detail.startsWith "extra span path"
    | _ => false)
    "prov: Source delimiter-alias path swap → missing/extra detection"
  expect (match buildSourceNodeInventoryV1 validated path replacedSpans with
    | .error (.inventory detail) =>
        detail.startsWith "missing span" || detail.startsWith "extra span path"
    | _ => false)
    "prov: Semantic delimiter-alias path swap → missing/extra detection"
  -- Extra alias path (both real and alias present) → extra span rejection.
  let aliasExtraSpans := spans.push (aliasA, sp0)
  expect (match buildSourceNodeInventoryV1 validated path aliasExtraSpans with
    | .error (.inventory detail) => detail.startsWith "extra span path"
    | _ => false)
    "prov: delimiter-alias extra span rejected as distinct path"
  -- aliasB is also distinct under new encoding.
  let aliasBExtra := spans.push (aliasB, sp0)
  expect (match buildSourceNodeInventoryV1 validated path aliasBExtra with
    | .error (.inventory detail) => detail.startsWith "extra span path"
    | _ => false)
    "prov: second delimiter-alias extra span rejected"
  -- Missing span: drop last span entry
  if spans.size > 0 then
    let missingSpans := spans.pop
    expect (match joinOriginsV1 validated path missingSpans with
      | .error (.inventory _) => true | _ => false)
      "prov: Source missing span path rejected"
    expect (match buildSourceNodeInventoryV1 validated path missingSpans with
      | .error (.inventory _) => true | _ => false)
      "prov: Semantic projection missing span path rejected"
  -- Structure-valid same-qualifiedName carrier substitution fails authority.
  let altText := wrap "CounterProv" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let altValidated ← loadSource session "prov-alt-carrier" altText
  -- Same program identity name CounterProv under same module → same qualifiedName
  -- once normalized, but different body ⇒ different carrier bytes.
  let altCarrier ← match normalizeProgramV1 altValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"prov: alt normalize: {repr e}"
  expect (altCarrier.canonicalBytes != carrier.canonicalBytes)
    "prov: alt carrier differs"
  let altData ← match validateSemanticProgramV1 altCarrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"prov: alt validate: {repr e}"
  expect (altData.qualifiedName == data.qualifiedName)
    "prov: alt carrier same qualifiedName"
  expect (match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans altCarrier provenance with
    | .error _ => true | .ok () => false)
    "prov: same-qname structure-valid carrier substitution → authority fails"
  expect (match ProofForgeV2.Semantic.NormalizeV1.semanticProvenanceDigestV1
      validated path spans altCarrier provenance with
    | .error _ => true | .ok _ => false)
    "prov: digest fails on carrier substitution before attribution self-justify"
  -- Inventory exact: extra foreign NodeId
  let foreignNode : NodeId :=
    { bytes := ByteArray.mk (Array.replicate 16 (0xbb : UInt8)) }
  let some o0 := inventory.nodes[0]? |
    throw <| IO.userError "prov: inventory missing node 0"
  let foreignOriginNode : SourceOrigin := {
    sourcePath := path
    startByte := o0.startByte
    endByte := o0.endByte
    nodeId := foreignNode
  }
  let extraInv : SourceNodeInventoryV1 := {
    sourceHash := srcHash
    nodes := inventory.nodes.push foreignOriginNode
  }
  expect (match validateSourceNodeInventoryExactV1 validated extraInv with
    | .error (.inventory _) => true | _ => false)
    "prov: extra foreign inventory NodeId rejected"
  -- Missing inventory node
  let missingInv : SourceNodeInventoryV1 := {
    sourceHash := srcHash
    nodes := inventory.nodes.pop
  }
  expect (match validateSourceNodeInventoryExactV1 validated missingInv with
    | .error (.inventory _) => true | _ => false)
    "prov: missing inventory node rejected"
  -- Nonascending inventory nodes (reverse if size≥2)
  if inventory.nodes.size ≥ 2 then
    let revNodes := inventory.nodes.reverse
    let nonAscInv : SourceNodeInventoryV1 := {
      sourceHash := srcHash
      nodes := revNodes
    }
    expect (match validateSourceNodeInventoryExactV1 validated nonAscInv with
      | .error (.inventory _) => true | _ => false)
      "prov: nonascending inventory nodes rejected"
  -- Duplicate inventory NodeId
  if inventory.nodes.size ≥ 1 then
    let dupInv : SourceNodeInventoryV1 := {
      sourceHash := srcHash
      nodes := inventory.nodes.push o0
    }
    expect (match validateSourceNodeInventoryExactV1 validated dupInv with
      | .error (.inventory _) => true | _ => false)
      "prov: duplicate inventory NodeId rejected"
  -- Span-bound inventory exactness: rebuilt path/start/end/nodeId match.
  match validateSourceNodeInventorySpanBoundExactV1 validated path spans inventory with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"prov: span-bound inventory: {repr e}"
  -- Coordinated inventory path/span mutation preserving NodeId + sourceHash:
  -- low-level builder can self-certify on the mutated inventory, but public
  -- authority (rebuilds from trusted path+spans) must reject unconditionally.
  if inventory.nodes.isEmpty then
    throw <| IO.userError "prov: inventory empty for coordinated span mutation"
  let some oHead := inventory.nodes[0]? |
    throw <| IO.userError "prov: inventory missing head for coordinated mutation"
  let mutPath ← match parseProjectRelativePath "tests/normalize-prov-coord-mut.pf" with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"prov: mut path: {e}"
  let newEnd : UInt64 :=
    if oHead.endByte > oHead.startByte then oHead.endByte - 1 else oHead.endByte + 1
  let oMut : SourceOrigin := {
    sourcePath := mutPath
    startByte := oHead.startByte
    endByte := newEnd
    nodeId := oHead.nodeId
  }
  match validateSourceOrigin oMut with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"prov: mutated origin invalid: {e}"
  expect (oMut != oHead) "prov: mutated origin differs in path/span fields"
  expect (oMut.nodeId == oHead.nodeId) "prov: coordinated mutation preserves NodeId"
  let mut mutatedNodes : Array SourceOrigin := #[oMut]
  let mut mi : Nat := 1
  while mi < inventory.nodes.size do
    match inventory.nodes[mi]? with
    | some o => mutatedNodes := mutatedNodes.push o
    | none => pure ()
    mi := mi + 1
  let mutatedInv : SourceNodeInventoryV1 := {
    sourceHash := srcHash
    nodes := mutatedNodes
  }
  -- NodeId-set helper still accepts (limit documented): path/span not checked.
  match validateSourceNodeInventoryExactV1 validated mutatedInv with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError
        s!"prov: NodeId-set helper must accept span mutation: {repr e}"
  -- Span-bound helper rejects path/span field mismatch.
  expect (match validateSourceNodeInventorySpanBoundExactV1
      validated path spans mutatedInv with
    | .error (.inventory _) => true | _ => false)
    "prov: span-bound inventory rejects path/span coordinated mutation"
  -- Low-level provenance from mutated inventory is self-consistent.
  let lowMutProv ← match buildSemanticProvenanceV1 validated carrier mutatedInv with
    | .ok p => pure p
    | .error e =>
        throw <| IO.userError
          s!"prov: low-level build on mutated inventory: {repr e}"
  expect (lowMutProv != provenance)
    "prov: mutated-inventory provenance differs from trusted"
  -- Public authority with original trusted path+spans rejects coordinated mut.
  expect (match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier lowMutProv with
    | .error _ => true | .ok () => false)
    "prov: authority rejects coordinated inventory path/span mutation"
  expect (match ProofForgeV2.Semantic.NormalizeV1.semanticProvenanceDigestV1
      validated path spans carrier lowMutProv with
    | .error _ => true | .ok _ => false)
    "prov: authority digest rejects coordinated inventory path/span mutation"
  -- Authoritative construction from original path+spans still succeeds.
  let pairOk ← match normalizeProgramWithProvenanceV1 validated path spans with
    | .ok p => pure p
    | .error e =>
        throw <| IO.userError
          s!"prov: authority construction after mutation test: {repr e}"
  let (_cOk, pOk) := pairOk
  expect (pOk == provenance)
    "prov: authority construction stable vs earlier trusted provenance"
  -- Wrong sourceModule (not a prefix of identity)
  let wrongModule ← match parseQualifiedName #["Other", "Module"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"prov: wrong module parse: {e}"
  expect (match joinHelper wrongModule idQn srcHash provenance.originMap
      inventory carrier provenance with
    | .error .badProvenance => true | _ => false)
    "prov: wrong sourceModule → badProvenance"
  -- Mutually replaced foreign inventory+provenance source hashes vs true expected
  let foreignSrc : Digest :=
    { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (7 : UInt8)) }
  let foreignProvBoth : SemanticProvenanceV1 :=
    { provenance with sourceHash := foreignSrc }
  let foreignInvBoth : SourceNodeInventoryV1 :=
    { inventory with sourceHash := foreignSrc }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      foreignInvBoth carrier foreignProvBoth with
    | .error .badProvenance => true | _ => false)
    "prov: mutually foreign inventory+provenance hashes vs expected → badProvenance"
  expect (match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier foreignProvBoth with
    | .error _ => true | .ok () => false)
    "prov: complete join rejects mutually foreign hashes"
  -- Negatives: incomplete empty map
  let emptyProv : SemanticProvenanceV1 := { provenance with originMap := #[] }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier emptyProv with
    | .error .badProvenance => true | _ => false)
    "prov: empty originMap → badProvenance"
  -- Missing one entity (drop last)
  let missingMap := provenance.originMap.pop
  let missingProv : SemanticProvenanceV1 := { provenance with originMap := missingMap }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier missingProv with
    | .error .badProvenance => true | _ => false)
    "prov: missing entity → badProvenance"
  -- Wrong requirement index
  let mut wrongReqMap := #[]
  for b in provenance.originMap do
    match b.entity with
    | .requirement _ =>
        wrongReqMap := wrongReqMap.push {
          entity := .requirement 99
          origins := b.origins
        }
    | _ => wrongReqMap := wrongReqMap.push b
  let wrongReqProv : SemanticProvenanceV1 := { provenance with originMap := wrongReqMap }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier wrongReqProv with
    | .error .badProvenance => true | _ => false)
    "prov: wrong requirement index → badProvenance"
  -- Foreign sourceHash alone
  let foreignProv : SemanticProvenanceV1 := { provenance with sourceHash := foreignSrc }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier foreignProv with
    | .error .badProvenance => true | _ => false)
    "prov: foreign sourceHash → badProvenance"
  -- Foreign semanticHash
  let foreignSem : Digest :=
    { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (9 : UInt8)) }
  let foreignSemProv : SemanticProvenanceV1 :=
    { provenance with semanticHash := foreignSem }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier foreignSemProv with
    | .error .badProvenance => true | _ => false)
    "prov: foreign semanticHash → badProvenance"
  -- Inventory with wrong sourceHash
  let badInv : SourceNodeInventoryV1 :=
    { inventory with sourceHash := foreignSrc }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      badInv carrier provenance with
    | .error .badProvenance => true | _ => false)
    "prov: inventory wrong sourceHash → badProvenance"
  -- Origin with unknown NodeId not in inventory
  let bogusNode : NodeId :=
    { bytes := ByteArray.mk (Array.replicate 16 (0xaa : UInt8)) }
  let some firstBind := provenance.originMap[0]? |
    throw <| IO.userError "prov: no bindings"
  let foreignOrigin : SourceOrigin := {
    sourcePath := path
    startByte := 0
    endByte := 1
    nodeId := bogusNode
  }
  let foreignOriginMap := provenance.originMap.set! 0 {
    entity := firstBind.entity
    origins := #[foreignOrigin]
  }
  let foreignOriginProv : SemanticProvenanceV1 :=
    { provenance with originMap := foreignOriginMap }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier foreignOriginProv with
    | .error .badProvenance => true | _ => false)
    "prov: unknown NodeId origin → badProvenance"
  -- Empty origins on a full entity map → badProvenance
  let emptyOriginsMap := provenance.originMap.set! 0 {
    entity := firstBind.entity
    origins := #[]
  }
  let emptyOriginsProv : SemanticProvenanceV1 :=
    { provenance with originMap := emptyOriginsMap }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier emptyOriginsProv with
    | .error .badProvenance => true | _ => false)
    "prov: empty origins binding → badProvenance"
  -- Non-ascending entity encode order (swap first two bindings)
  let some b0 := provenance.originMap[0]? |
    throw <| IO.userError "prov: originMap missing binding 0"
  let some b1 := provenance.originMap[1]? |
    throw <| IO.userError "prov: originMap must have ≥2 bindings for entity-order test"
  let swappedMap := (provenance.originMap.set! 0 b1).set! 1 b0
  let swappedProv : SemanticProvenanceV1 :=
    { provenance with originMap := swappedMap }
  expect (match joinHelper moduleQn idQn srcHash provenance.originMap
      inventory carrier swappedProv with
    | .error .badProvenance => true | _ => false)
    "prov: non-ascending entity order → badProvenance"
  -- sourceIdentity ≠ provenance.qualifiedName → badProvenance
  let wrongIdentity ← match parseQualifiedName #["Tests", "WrongIdentityProv"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"prov: wrong identity parse: {e}"
  expect (wrongIdentity != idQn) "prov: wrong identity differs"
  expect (match joinHelper moduleQn wrongIdentity srcHash provenance.originMap
      inventory carrier provenance with
    | .error .badProvenance => true | _ => false)
    "prov: sourceIdentity mismatch → badProvenance"
  -- Noncanonical provenance bytes
  let goodBytes ← match encodeSemanticProvenanceV1 provenance with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"prov: enc good: {repr e}"
  expect (goodBytes.size > 8) "prov: encoded provenance has body"
  let truncated := goodBytes.extract 0 (goodBytes.size - 1)
  expect (match decodeSemanticProvenanceV1 truncated with
    | .error _ => true | .ok _ => false)
    "prov: truncated provenance bytes rejected by decode"

/-- S2 multi-site fixture: two states + two add expressions; independent path origins. -/
private unsafe def testMultiSiteProvenanceAttribution
    (session : Language.Loader.ParserSession) : IO Unit := do
  let sourceText := wrap "MultiSite" <|
    "  state count : UInt64\n" ++
    "  state total : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "    total := initial\n" ++
    "  entry bump(d1 : UInt64, d2 : UInt64) : UInt64 do\n" ++
    "    count := count + d1\n" ++
    "    total := total + d2\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "multi" sourceText
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "multi: CheckV1.ok"
  expect typed.analysisComplete "multi: CheckV1.analysisComplete"
  let path ← parseTestPath "multi"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"multi: inventory: {repr e}"
  let pair ← match normalizeProgramWithProvenanceV1 validated path spans with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"multi: normalize+prov: {repr e}"
  let (carrier, provenance) := pair
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"multi: validate: {repr e}"
  expect (data.logicalState.size == 2) "multi: two states"
  expect (data.requirements.items.size == 3) "multi: three requirements"
  -- Explicit syntactic paths (NodeTraversal preorder field layout).
  let item0 := childPathT #[] "Program" "items" 0
  let item1 := childPathT #[] "Program" "items" 1
  let item3 := childPathT #[] "Program" "items" 3  -- entry bump
  let entryBody := directChildT item3 "EntryDecl" "body"
  let stmt0 := childPathT entryBody "Block" "statements" 0
  let stmt1 := childPathT entryBody "Block" "statements" 1
  let stmt2 := childPathT entryBody "Block" "statements" 2
  let add0Path := directChildT stmt0 "Stmt.Assign" "value"  -- Expr.Binary
  let add1Path := directChildT stmt1 "Stmt.Assign" "value"
  let store0Path := stmt0  -- StateStore binds assign stmt
  let retPath := stmt2
  let expState0 ← originAtExplicitPath validated inventory item0
  let expState1 ← originAtExplicitPath validated inventory item1
  let expAdd0 ← originAtExplicitPath validated inventory add0Path
  let expAdd1 ← originAtExplicitPath validated inventory add1Path
  let expStore0 ← originAtExplicitPath validated inventory store0Path
  let expRet ← originAtExplicitPath validated inventory retPath
  let expEntry ← originAtExplicitPath validated inventory item3
  expect (expState0 != expState1) "multi: state origins distinct"
  expect (expAdd0 != expAdd1) "multi: add origins distinct"
  expect (expAdd0 != expStore0) "multi: add0 ≠ store0"
  expect (expStore0 != expRet) "multi: store ≠ return"
  -- Provenance bindings must match independent assignNodeIdsV1/inventory origins.
  let some gotState0 := findOrigin provenance (.state 0) |
    throw <| IO.userError "multi: missing state0 origin"
  let some gotState1 := findOrigin provenance (.state 1) |
    throw <| IO.userError "multi: missing state1 origin"
  expect (gotState0 == expState0) "multi: state0 NodeId exact"
  expect (gotState1 == expState1) "multi: state1 NodeId exact"
  let some gotEntry := findOrigin provenance (.callable 1) |
    throw <| IO.userError "multi: missing entry callable origin"
  expect (gotEntry == expEntry) "multi: entry callable NodeId exact"
  -- Entry instructions: load, add, store, load, add, store, load-for-return
  let some entryC := data.callables[1]? |
    throw <| IO.userError "multi: missing entry"
  let some eblock := entryC.blocks[0]? |
    throw <| IO.userError "multi: missing entry block"
  expect (eblock.instructions.size == 7)
    s!"multi: entry instrs {eblock.instructions.size}"
  let some gotAdd0 := findOrigin provenance (.instruction 1 0 1) |
    throw <| IO.userError "multi: missing add0 instr origin"
  let some gotAdd1 := findOrigin provenance (.instruction 1 0 4) |
    throw <| IO.userError "multi: missing add1 instr origin"
  let some gotStore0 := findOrigin provenance (.instruction 1 0 2) |
    throw <| IO.userError "multi: missing store0 origin"
  let some gotRet := findOrigin provenance (.terminator 1 0) |
    throw <| IO.userError "multi: missing terminator origin"
  expect (gotAdd0 == expAdd0) "multi: add0 instruction NodeId exact"
  expect (gotAdd1 == expAdd1) "multi: add1 instruction NodeId exact"
  expect (gotStore0 == expStore0) "multi: store0 NodeId exact"
  expect (gotRet == expRet) "multi: return terminator NodeId exact"
  -- Requirements multi-origin: both adds for arithmetic/rollback; both states for persistent.
  let reqRollback := findOrigins provenance (.requirement 0)
  let reqPersist := findOrigins provenance (.requirement 1)
  let reqArith := findOrigins provenance (.requirement 2)
  let expAdds ← sortOriginsByWire #[expAdd0, expAdd1]
  let expStates ← sortOriginsByWire #[expState0, expState1]
  expect (reqRollback.size == 2) s!"multi: rollback origins {reqRollback.size}"
  expect (reqArith.size == 2) s!"multi: arith origins {reqArith.size}"
  expect (reqPersist.size == 2) s!"multi: persist origins {reqPersist.size}"
  expect (reqRollback == expAdds)
    "multi: failure.atomic-rollback exact both add origins wire-order"
  expect (reqArith == expAdds)
    "multi: value.checked-arithmetic exact both add origins wire-order"
  expect (reqPersist == expStates)
    "multi: state.persistent exact both state origins wire-order"
  -- Drop/duplicate/reorder sensitivity: wrong multi-origin must fail rebuild compare.
  let dropped : SemanticProvenanceV1 :=
    { provenance with originMap := provenance.originMap.map fun b =>
        match b.entity with
        | .requirement 0 => { b with origins := #[expAdd0] }  -- dropped add1
        | _ => b }
  expect (match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier dropped with
    | .error _ => true | .ok () => false)
    "multi: dropped requirement origin site fails authority"
  let duped : SemanticProvenanceV1 :=
    { provenance with originMap := provenance.originMap.map fun b =>
        match b.entity with
        | .requirement 2 => { b with origins := #[expAdd0, expAdd0] }
        | _ => b }
  expect (match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier duped with
    | .error _ => true | .ok () => false)
    "multi: duplicated requirement origin fails authority"
  -- Reordered origins (reverse canonical wire order) fail authority.
  expect (expAdds.size == 2) "multi: exactly two canonical add origins"
  let reversedAdds := expAdds.reverse
  expect (reversedAdds != expAdds)
    "multi: reversing two distinct canonical origins must change order"
  let reordered : SemanticProvenanceV1 :=
    { provenance with originMap := provenance.originMap.map fun b =>
        match b.entity with
        | .requirement 0 => { b with origins := reversedAdds }
        | _ => b }
  expect (match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier reordered with
    | .error _ => true | .ok () => false)
    "multi: reordered requirement origins fail authority"
  match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier provenance with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"multi: authority: {repr e}"

/-- S2 provenance must reject a structure-valid carried requirement that has
    no independently reconstructed producing source site. -/
private unsafe def testMissingRequirementProducingSite
    (session : Language.Loader.ParserSession) : IO Unit := do
  let sourceText := wrap "MissingReqSite" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry set(value : UInt64) : UInt64 do\n" ++
    "    count := value\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "missing-req-site" sourceText
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "missing-req-site: CheckV1.ok"
  let sourcePath ← parseTestPath "missing-req-site"
  let inventory ← match buildSourceNodeInventoryV1 validated sourcePath spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"missing-req-site: inventory: {repr e}"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"missing-req-site: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"missing-req-site: carrier: {repr e}"
  expect (data.requirements.items.size == 1)
    "missing-req-site: source contributes only state.persistent"
  let some persistent := data.requirements.items[0]? |
    throw <| IO.userError "missing-req-site: missing persistent requirement"
  expect (persistent.id == "state.persistent")
    "missing-req-site: sole source requirement is state.persistent"
  let rollback ← match mkS2RequirementRequestV1 "failure.atomic-rollback" with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"missing-req-site: rollback request: {e}"
  let arithmetic ← match mkS2RequirementRequestV1 "value.checked-arithmetic" with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"missing-req-site: arithmetic request: {e}"
  let mutatedData : SemanticProgramDataV1 := {
    data with requirements := { items := #[rollback, persistent, arithmetic] }
  }
  let mutatedBytes ← match encodeSemanticProgramDataV1 mutatedData with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"missing-req-site: encode carrier: {repr e}"
  let mutatedCarrier ← match decodeSemanticProgramV1 mutatedBytes with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"missing-req-site: decode carrier: {repr e}"
  match buildSemanticProvenanceV1 validated mutatedCarrier inventory with
  | .error (.unsupported detail) =>
      expect (detail.contains "missing producing site" &&
          detail.contains "failure.atomic-rollback" && detail.contains "index=0")
        s!"missing-req-site: isolated error detail: {detail}"
  | .error e =>
      throw <| IO.userError s!"missing-req-site: wrong error phase: {repr e}"
  | .ok _ =>
      throw <| IO.userError
        "missing-req-site: carried requirement without source site was accepted"

/-- S2: freezeProgramRequirementsV1 rejects non-catalog contribution keys. -/
private unsafe def testFreezeRejectsForeignKeys
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- private state contributes disclosure.private-state (foreign to S2 catalog)
  let privateStateSrc := wrap "FreezePrivState" <|
    "  state private secret : UInt64\n" ++
    "  entry ping(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let privState ← loadSource session "freeze-priv-state" privateStateSrc
  match freezeProgramRequirementsV1 privState.program with
  | .ok _ =>
      throw <| IO.userError "freeze-priv-state: expected non-catalog rejection"
  | .error detail =>
      expect (detail ==
          "S2 semantic requirements freeze rejects non-catalog key 'disclosure.private-state'")
        s!"freeze-priv-state detail: {detail}"
  -- unused private param contributes disclosure.private-witness
  let privateParamSrc := wrap "FreezePrivParam" <|
    "  entry run(private secret : UInt64) : UInt64 do\n" ++
    "    return 0\n"
  let privParam ← loadSource session "freeze-priv-param" privateParamSrc
  match freezeProgramRequirementsV1 privParam.program with
  | .ok _ =>
      throw <| IO.userError "freeze-priv-param: expected non-catalog rejection"
  | .error detail =>
      expect (detail ==
          "S2 semantic requirements freeze rejects non-catalog key 'disclosure.private-witness'")
        s!"freeze-priv-param detail: {detail}"
  -- Bool result contributes value.bool
  let boolSrc := wrap "FreezeBool" <|
    "  entry run() : Bool do\n" ++
    "    return true\n"
  let boolProg ← loadSource session "freeze-bool" boolSrc
  match freezeProgramRequirementsV1 boolProg.program with
  | .ok _ =>
      throw <| IO.userError "freeze-bool: expected non-catalog rejection"
  | .error detail =>
      expect (detail ==
          "S2 semantic requirements freeze rejects non-catalog key 'value.bool'")
        s!"freeze-bool detail: {detail}"
  -- emit contributes effect.event
  let emitSrc := wrap "FreezeEmit" <|
    "  event Tick()\n" ++
    "  entry run() : Unit do\n" ++
    "    emit Tick()\n" ++
    "    return\n"
  let emitProg ← loadSource session "freeze-emit" emitSrc
  match freezeProgramRequirementsV1 emitProg.program with
  | .ok _ =>
      throw <| IO.userError "freeze-emit: expected non-catalog rejection"
  | .error detail =>
      expect (detail ==
          "S2 semantic requirements freeze rejects non-catalog key 'effect.event'")
        s!"freeze-emit detail: {detail}"
  -- End-to-end: CheckV1-ok Counter-like with unused private param hits freeze via normalize
  let e2eSrc := wrap "FreezeE2EPrivParam" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64, private witness : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let e2e ← loadSource session "freeze-e2e-priv" e2eSrc
  let typed := checkProgramTypedResultV1 e2e
  expect typed.ok "freeze-e2e: CheckV1.ok"
  expect typed.analysisComplete "freeze-e2e: CheckV1.analysisComplete"
  match normalizeProgramV1 e2e with
  | .ok _ =>
      throw <| IO.userError "freeze-e2e: expected unsupported (foreign freeze)"
  | .error (.unsupported detail) =>
      expect (detail.contains
          "S2 semantic requirements freeze rejects non-catalog key 'disclosure.private-witness'" ||
          detail.contains "disclosure.private-witness")
        s!"freeze-e2e detail: {detail}"
  | .error e =>
      throw <| IO.userError s!"freeze-e2e: expected unsupported, got {repr e}"

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
  testCounterRequirementsAndProvenance session
  testMultiSiteProvenanceAttribution session
  testMissingRequirementProducingSite session
  testFreezeRejectsForeignKeys session
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
