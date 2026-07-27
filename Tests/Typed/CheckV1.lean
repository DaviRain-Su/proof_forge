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

end Tests.Typed.CheckV1
