/-
  Tests.Typed.CheckV1 — multi-pass Typed checker composition suite.

  Pins phase order (structure → type → effect → bound → disclosure), single
  resolution pass (no duplicated resolution messages), analysisComplete/ok under
  duplicate fn keys, and independent coverage of type / effect / bound /
  disclosure errors.

  B7b3d: draft-bearing sole authority (`TypedCheckDraftResultV1` /
  `checkProgramTypedDraftResultV1`), exact erase parity vs legacy unlocated
  APIs, and additive located CheckV1 hash-gate + all-or-nothing locateArray
  materialization.  Does not assert product CLI multi-error bundle (B8) or
  alpha Typed.checkV1 wiring beyond existing product-gate suites.
-/
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DiagnosticLocateV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.CheckV1
import ProofForgeV2.Typed.DiagnosticDraftV1
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
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DiagnosticLocateV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.CheckV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.CheckV1"

private unsafe def loadValidated
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source ("<typed-check-" ++ label ++ ">") moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def loadWithOrigins
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × OriginInventoryV1) := do
  match ← session.selectProgramV1WithOrigins
      source ("tests/typed-check-" ++ label ++ ".pf") moduleName none with
  | .ok pair => pure pair
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def checkResult
    (session : Language.Loader.ParserSession) (label source : String) :
    IO TypedCheckResultV1 := do
  let validated ← loadValidated session label source
  pure (checkProgramTypedResultV1 validated)

private unsafe def checkDiags
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (Array DiagnosticV1) := do
  let validated ← loadValidated session label source
  pure (checkProgramTypedV1 validated)

private unsafe def checkDraftResult
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × TypedCheckDraftResultV1) := do
  let validated ← loadValidated session label source
  pure (validated, checkProgramTypedDraftResultV1 validated)

/-- Exact erase parity: draft authority vs legacy unlocated result. -/
private def expectEraseParity
    (label : String) (draft : TypedCheckDraftResultV1) (legacy : TypedCheckResultV1) :
    IO Unit := do
  expect (draft.ok == legacy.ok) s!"{label}: ok parity"
  expect (draft.analysisComplete == legacy.analysisComplete)
    s!"{label}: analysisComplete parity"
  let erased := eraseArray draft.drafts
  expect (erased.size == legacy.diagnostics.size)
    s!"{label}: size parity draft={erased.size} legacy={legacy.diagnostics.size}"
  for i in [0:erased.size] do
    let d := erased[i]!
    let e := legacy.diagnostics[i]!
    expect (d.code == e.code) s!"{label}[{i}]: code parity"
    expect (d.message == e.message) s!"{label}[{i}]: message parity"
    expect (d.phase == e.phase) s!"{label}[{i}]: phase parity"
    expect (d.primary == none) s!"{label}[{i}]: erased primary empty"
    expect (d.related.isEmpty) s!"{label}[{i}]: erased related empty"
    expect (e.primary == none) s!"{label}[{i}]: legacy primary empty"
    expect (e.related.isEmpty) s!"{label}[{i}]: legacy related empty"

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
  B7b3d — draft sole authority, erase parity, located hash-gate + NodeId materialization.
-/

/-- No-diagnostic success: draft/legacy ok parity; empty located diagnostics. -/
private unsafe def testDraftSuccessParity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftOk where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, draft) ← checkDraftResult session "draft-ok" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-ok" draft legacy
  expectOk legacy "draft-ok-legacy"
  expect (draft.drafts.isEmpty) "draft-ok: empty drafts"
  let (v2, inv) ← loadWithOrigins session "draft-ok-loc" source
  match checkProgramTypedLocatedResultV1 v2 inv with
  | .error e => throw <| IO.userError s!"draft-ok-loc: unexpected {repr e}"
  | .ok located => do
      expect (located.ok && located.analysisComplete) "draft-ok-loc: ok+complete"
      expect located.diagnostics.isEmpty "draft-ok-loc: empty diagnostics"
  -- Deterministic rerun of draft composition.
  let draft2 := checkProgramTypedDraftResultV1 validated
  expectEraseParity "draft-ok-rerun" draft2 legacy

/-- Type-only phase: draft erase parity + located primary NodeId. -/
private unsafe def testDraftTypeOnlyParity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftType where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let (validated, draft) ← checkDraftResult session "draft-type" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-type" draft legacy
  expect (!draft.ok && draft.analysisComplete) "draft-type: not ok complete"
  expect (contains (wires legacy.diagnostics) "PF-SRC-INVALID" ||
      contains (messages legacy.diagnostics) "type mismatch")
    "draft-type: type diagnostic present"
  expect (!contains (wires legacy.diagnostics) "PF-EFFECT-001")
    "draft-type: no effect"
  expect (!contains (wires legacy.diagnostics) "PF-BOUND-001")
    "draft-type: no bound"
  expect (!contains (wires legacy.diagnostics) "PF-VIS-001")
    "draft-type: no disclosure"
  let (v2, inv) ← loadWithOrigins session "draft-type-loc" source
  let located ← match checkProgramTypedLocatedResultV1 v2 inv with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"draft-type-loc: {repr e}"
  expect (located.diagnostics.size == draft.drafts.size)
    "draft-type-loc: size"
  for i in [0:draft.drafts.size] do
    let d := draft.drafts[i]!
    let locd := located.diagnostics[i]!
    expect (d.diagnostic.code == locd.code) s!"draft-type-loc[{i}]: code"
    expect (d.diagnostic.message == locd.message) s!"draft-type-loc[{i}]: message"
    match d.location with
    | none =>
        expect (locd.primary == none) s!"draft-type-loc[{i}]: primary none"
    | some loc =>
        match originInventoryLookupPathV1 inv loc.primaryPath with
        | none => throw <| IO.userError s!"draft-type-loc[{i}]: primary path missing"
        | some origin =>
            match locd.primary with
            | none => throw <| IO.userError s!"draft-type-loc[{i}]: expected primary"
            | some o =>
                expect (o.nodeId == some origin.nodeId)
                  s!"draft-type-loc[{i}]: primary NodeId"

/-- Effect-only phase erase + located. -/
private unsafe def testDraftEffectOnlyParity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftEffect where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek()\n"
  let (validated, draft) ← checkDraftResult session "draft-effect" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-effect" draft legacy
  expect (contains (wires legacy.diagnostics) "PF-EFFECT-001")
    "draft-effect: PF-EFFECT-001"
  expect (!contains (wires legacy.diagnostics) "PF-VIS-001")
    "draft-effect: no VIS"
  let (v2, inv) ← loadWithOrigins session "draft-effect-loc" source
  let located ← match checkProgramTypedLocatedResultV1 v2 inv with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"draft-effect-loc: {repr e}"
  expect (located.diagnostics.size ≥ 1) "draft-effect-loc: ≥1"
  expect (located.diagnostics.any fun d => d.code.wire == "PF-EFFECT-001")
    "draft-effect-loc: wire"
  -- At least one located diagnostic has a real primary NodeId.
  expect (located.diagnostics.any fun d =>
      match d.primary with | some o => o.nodeId.isSome | none => false)
    "draft-effect-loc: some primary NodeId"

/-- Bound-only (loop product) erase parity. -/
private unsafe def testDraftBoundOnlyParity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftBound where\n" ++
    "  state total : UInt64\n" ++
    "  state start : UInt64\n" ++
    "  state stop : UInt64\n" ++
    "  entry run() do\n" ++
    "    for i in start ..< stop bounded 4096 do\n" ++
    "      for j in start ..< stop bounded 4096 do\n" ++
    "        for k in start ..< stop bounded 4096 do\n" ++
    "          total := i\n"
  let (validated, draft) ← checkDraftResult session "draft-bound" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-bound" draft legacy
  expect (contains (wires legacy.diagnostics) "PF-BOUND-001")
    "draft-bound: PF-BOUND-001"

/-- Disclosure-only erase parity. -/
private unsafe def testDraftDisclosureOnlyParity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftDisc where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let (validated, draft) ← checkDraftResult session "draft-disc" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-disc" draft legacy
  expect (contains (wires legacy.diagnostics) "PF-VIS-001")
    "draft-disc: PF-VIS-001"

/-- Mixed resolution-ok type + effect + bound + disclosure in phase order. -/
private unsafe def testDraftMixedPhases
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftMixed where\n" ++
    "  state total : UInt64\n" ++
    "  state start : UInt64\n" ++
    "  state stop : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    for i in start ..< stop bounded 4096 do\n" ++
    "      for j in start ..< stop bounded 4096 do\n" ++
    "        for k in start ..< stop bounded 4096 do\n" ++
    "          total := i\n" ++
    "    total := x\n" ++
    "    return true\n"
  let (validated, draft) ← checkDraftResult session "draft-mixed" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-mixed" draft legacy
  let w := wires legacy.diagnostics
  let msgs := messages legacy.diagnostics
  -- structure cycle before type before effect before bound before disclosure
  expect (contains msgs "recursive call cycle") "draft-mixed: structure cycle"
  expect (contains msgs "type mismatch") "draft-mixed: type"
  expect (contains w "PF-EFFECT-001") "draft-mixed: effect"
  expect (contains w "PF-BOUND-001") "draft-mixed: bound"
  expect (contains w "PF-VIS-001") "draft-mixed: disclosure"
  let si := msgs.findIdx? (·.contains "recursive call cycle")
  let ti := msgs.findIdx? (·.contains "type mismatch")
  let ei := w.findIdx? (· == "PF-EFFECT-001")
  let bi := w.findIdx? (· == "PF-BOUND-001")
  let vi := w.findIdx? (· == "PF-VIS-001")
  match si, ti, ei, bi, vi with
  | some s, some t, some e, some b, some v =>
      unless s < t && t < e && e < b && b < v do
        throw <| IO.userError
          s!"draft-mixed: phase order failed s={s} t={t} e={e} b={b} v={v} wires={w} msgs={msgs}"
  | _, _, _, _, _ =>
      throw <| IO.userError s!"draft-mixed: missing phase indices wires={w} msgs={msgs}"
  let (v2, inv) ← loadWithOrigins session "draft-mixed-loc" source
  let located ← match checkProgramTypedLocatedResultV1 v2 inv with
    | .ok r => pure r
    | .error err => throw <| IO.userError s!"draft-mixed-loc: {repr err}"
  expect (located.diagnostics.size == draft.drafts.size)
    "draft-mixed-loc: size"
  expect (located.diagnostics.map (·.code.wire) ==
      legacy.diagnostics.map (·.code.wire))
    "draft-mixed-loc: wire order"
  -- Every draft with a location must materialize a primary NodeId.
  for i in [0:draft.drafts.size] do
    let d := draft.drafts[i]!
    let locd := located.diagnostics[i]!
    match d.location with
    | none => pure ()
    | some _ =>
        match locd.primary with
        | none => throw <| IO.userError s!"draft-mixed-loc[{i}]: missing primary"
        | some o =>
            expect o.nodeId.isSome s!"draft-mixed-loc[{i}]: nodeId some"

/-- Resolution short-circuit: structure only; later phases skipped. -/
private unsafe def testDraftResolutionShortCircuit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftResShort where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return missing + true\n"
  let (validated, draft) ← checkDraftResult session "draft-res" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-res" draft legacy
  expect (!draft.ok) "draft-res: not ok"
  expect draft.analysisComplete "draft-res: complete (no dup-fn)"
  let msgs := messages legacy.diagnostics
  expect (contains msgs "missing" || contains msgs "unknown")
    "draft-res: resolution"
  expect (countNeedle msgs "missing" == 1)
    s!"draft-res: single missing, got {countNeedle msgs "missing"}"
  expect (!contains (wires legacy.diagnostics) "PF-EFFECT-001")
    "draft-res: no effect after short-circuit"
  expect (!contains (wires legacy.diagnostics) "PF-BOUND-001")
    "draft-res: no bound after short-circuit"
  expect (!contains (wires legacy.diagnostics) "PF-VIS-001")
    "draft-res: no disclosure after short-circuit"
  -- Drafts are path-bearing for the resolution diagnostic.
  expect (draft.drafts.any fun d => d.location.isSome)
    "draft-res: resolution draft has location"

/-- Cycle structure ordering: resolution (empty) then callGraph before later phases. -/
private unsafe def testDraftCycleStructureOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftCycle where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let (validated, draft) ← checkDraftResult session "draft-cycle" source
  let legacy := checkProgramTypedResultV1 validated
  expectEraseParity "draft-cycle" draft legacy
  let msgs := messages legacy.diagnostics
  let si := msgs.findIdx? (·.contains "recursive call cycle")
  let ti := msgs.findIdx? (·.contains "type mismatch")
  let bi := msgs.findIdx? (·.contains "unbounded recursion (call cycle)")
  match si, ti, bi with
  | some s, some t, some b =>
      unless s < t && t < b do
        throw <| IO.userError s!"draft-cycle: order s={s} t={t} b={b} msgs={msgs}"
  | _, _, _ =>
      throw <| IO.userError s!"draft-cycle: missing indices msgs={msgs}"

/-- Duplicate-fn incomplete via draft adapter over unlocated resolution. -/
private unsafe def testDraftDuplicateFnIncomplete
    (_session : Language.Loader.ParserSession) : IO Unit := do
  let progName ← mkName "DupFnDraft"
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
    throw <| IO.userError "dup-fn-draft: expected hasDuplicateKey"
  let resolution : NameResolutionResultV1 :=
    { tables := tables
      diagnostics := st.diagnostics
      ok := false }
  let legacy := checkProgramTypedWithResolutionV1 progAst resolution
  -- Draft path via unlocated conversion is what the adapter uses.
  let draftRes : NameResolutionDraftResultV1 :=
    { tables := tables
      drafts := st.diagnostics.map fun d => { diagnostic := d, location := none }
      ok := false }
  let draft := checkProgramTypedDraftWithResolutionV1 progAst draftRes
  expectEraseParity "dup-fn-draft" draft legacy
  expect (!draft.analysisComplete) "dup-fn-draft: incomplete"
  expect (!draft.ok) "dup-fn-draft: not ok"
  expect (!contains (wires legacy.diagnostics) "PF-EFFECT-001")
    "dup-fn-draft: no effect"
  expect (!contains (wires legacy.diagnostics) "PF-BOUND-001")
    "dup-fn-draft: no bound"
  expect (!contains (wires legacy.diagnostics) "PF-VIS-001")
    "dup-fn-draft: no vis"

/-- Foreign inventory sourceHash mismatch fails before path lookup. -/
private unsafe def testLocatedForeignInventory
    (session : Language.Loader.ParserSession) : IO Unit := do
  let sourceA :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocForeignA where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let sourceB :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocForeignB where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return false\n"
  let (va, _inva) ← loadWithOrigins session "loc-foreign-a" sourceA
  let (_vb, invb) ← loadWithOrigins session "loc-foreign-b" sourceB
  -- Ensure hashes actually differ.
  let ha ← match sourceHashV1 va with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"loc-foreign: hash A: {e}"
  expect (ha != originInventorySourceHashV1 invb)
    "loc-foreign: inventories must differ"
  match checkProgramTypedLocatedResultV1 va invb with
  | .ok _ =>
      throw <| IO.userError "loc-foreign: expected sourceHash error, got ok"
  | .error (.sourceHash detail) =>
      expect (detail == "sourceHashV1 does not match originInventorySourceHashV1")
        s!"loc-foreign: detail {detail}"
  | .error (.locate _) =>
      throw <| IO.userError
        "loc-foreign: must fail at sourceHash before locate (got locate)"

/-- Synthetic missing path: all-or-nothing locateArray failure (no partial). -/
private unsafe def testLocatedMissingPathAllOrNothing
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocMissingPath where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let (validated, inv) ← loadWithOrigins session "loc-missing" source
  let draft := checkProgramTypedDraftResultV1 validated
  expect (draft.drafts.size ≥ 1) "loc-missing: need ≥1 draft"
  -- Tamper first located draft primary path to a synthetic foreign path.
  let mut tampered : Array TypedDiagnosticDraftV1 := #[]
  let mut didTamper := false
  for d in draft.drafts do
    match d.location, didTamper with
    | some loc, false =>
        let badPath := loc.primaryPath.push {
          parentTag := "Foreign"
          fieldTag := "missing"
          index := UInt32.ofNat 0
        }
        tampered := tampered.push
          { d with location := some { loc with primaryPath := badPath } }
        didTamper := true
    | _, _ =>
        tampered := tampered.push d
  expect didTamper "loc-missing: tampered at least one path"
  -- Direct sole materializer: all-or-nothing fail (matches located API path).
  match locateArray inv tampered with
  | .ok diags =>
      throw <| IO.userError
        s!"loc-missing: expected locateArray error, got {diags.size} diags"
  | .error _ => pure ()
  -- Located public API with matching inventory still succeeds (untampered).
  match checkProgramTypedLocatedResultV1 validated inv with
  | .ok r =>
      expect (r.diagnostics.size == draft.drafts.size) "loc-missing: public size"
  | .error e =>
      throw <| IO.userError s!"loc-missing: public locate should succeed: {repr e}"

/-- Deterministic repeated draft + located outputs. -/
private unsafe def testDraftLocatedDeterminism
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DraftDet where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let (validated, inv) ← loadWithOrigins session "draft-det" source
  let d1 := checkProgramTypedDraftResultV1 validated
  let d2 := checkProgramTypedDraftResultV1 validated
  expect (d1.ok == d2.ok && d1.analysisComplete == d2.analysisComplete)
    "draft-det: flags"
  expect (d1.drafts.size == d2.drafts.size) "draft-det: size"
  for i in [0:d1.drafts.size] do
    expect (d1.drafts[i]!.diagnostic.message == d2.drafts[i]!.diagnostic.message)
      s!"draft-det[{i}]: message"
    expect (d1.drafts[i]!.diagnostic.code == d2.drafts[i]!.diagnostic.code)
      s!"draft-det[{i}]: code"
  let l1 ← match checkProgramTypedLocatedResultV1 validated inv with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"draft-det l1: {repr e}"
  let l2 ← match checkProgramTypedLocatedResultV1 validated inv with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"draft-det l2: {repr e}"
  expect (l1.diagnostics.map (·.message) == l2.diagnostics.map (·.message))
    "draft-det: located messages"
  expect (l1.diagnostics.map (·.code.wire) == l2.diagnostics.map (·.code.wire))
    "draft-det: located wires"
  for i in [0:l1.diagnostics.size] do
    expect (l1.diagnostics[i]!.primary == l2.diagnostics[i]!.primary)
      s!"draft-det[{i}]: primary"
    expect (l1.diagnostics[i]!.related == l2.diagnostics[i]!.related)
      s!"draft-det[{i}]: related"

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

/-- UInt64 integer literals lower through the shipped semantic carrier with
    exact little-endian bytes, expected-type threading, source-order ValueIds,
    provenance attribution, and no literal-only requirement. -/
private unsafe def testUInt64Literals
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "LitOnly" <|
    "  entry run() : UInt64 do\n" ++
    "    return 72623859790382856\n"
  let (validated, spans) ← loadSourceWithSpans session "lit" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "lit: CheckV1.ok"
  expect typed.analysisComplete "lit: CheckV1.analysisComplete"
  let path ← parseTestPath "lit"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"lit: normalize+provenance: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"lit: validate carrier: {repr e}"
  expect (data.types.size == 1) s!"lit: one UInt64 type, got {data.types.size}"
  let some ty := data.types[0]? |
    throw <| IO.userError "lit: missing type[0]"
  expect (ty.id == 0 && ty.name.isNone &&
      match ty.shape with | .uint 64 => true | _ => false)
    "lit: type[0] is anonymous UInt64"
  expect data.requirements.items.isEmpty
    s!"lit: literal contributes no requirements, got {data.requirements.items.size}"
  let some callable := data.callables[0]? |
    throw <| IO.userError "lit: missing entry callable"
  let some block := callable.blocks[0]? |
    throw <| IO.userError "lit: missing entry block"
  expect (block.instructions.size == 1)
    s!"lit: one literal instruction, got {block.instructions.size}"
  let some instr := block.instructions[0]? |
    throw <| IO.userError "lit: missing literal instruction"
  let some result := instr.result |
    throw <| IO.userError "lit: literal instruction missing result"
  let expectedBytes : ByteArray :=
    ByteArray.mk #[(0x08 : UInt8), 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
  expect (result.valueId == 0 && result.typeId == 0)
    s!"lit: result must be ValueId/TypeId 0, got {result.valueId}/{result.typeId}"
  match instr.op with
  | .literal tid valueBytes =>
      expect (tid == 0 && valueBytes == expectedBytes)
        s!"lit: exact UInt64 little-endian bytes, got size {valueBytes.size}"
  | _ => throw <| IO.userError "lit: expected Op.Literal"
  match block.terminator with
  | .return_ (some valueId) =>
      expect (valueId == 0) s!"lit: return ValueId 0, got {valueId}"
  | _ => throw <| IO.userError "lit: expected return some literal"
  match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier provenance with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"lit: provenance validation: {repr e}"

  -- UInt64.max is accepted and encoded as eight ff bytes; 2^64 is rejected by
  -- CheckV1 before normalization, so the normalizer never truncates it.
  let maxSource := wrap "LitMax" <|
    "  entry run() : UInt64 do\n" ++
    "    return 18446744073709551615\n"
  let maxValidated ← loadSource session "lit-max" maxSource
  let maxCarrier ← match normalizeProgramV1 maxValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"lit-max: normalize: {repr e}"
  let maxData ← match validateSemanticProgramV1 maxCarrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"lit-max: validate: {repr e}"
  let some maxCallable := maxData.callables[0]? |
    throw <| IO.userError "lit-max: missing entry callable"
  let some maxBlock := maxCallable.blocks[0]? |
    throw <| IO.userError "lit-max: missing entry block"
  let some maxInstr := maxBlock.instructions[0]? |
    throw <| IO.userError "lit-max: missing literal instruction"
  match maxInstr.op with
  | .literal _ bytes =>
      expect (bytes == ByteArray.mk (Array.replicate 8 (0xff : UInt8)))
        "lit-max: expected eight ff bytes"
  | _ => throw <| IO.userError "lit-max: expected Op.Literal"
  let overflowSource := wrap "LitOverflow" <|
    "  entry run() : UInt64 do\n" ++
    "    return 18446744073709551616\n"
  let overflowValidated ← loadSource session "lit-overflow" overflowSource
  let overflowTyped := checkProgramTypedResultV1 overflowValidated
  expect (!overflowTyped.ok && overflowTyped.analysisComplete)
    "lit-overflow: CheckV1 must reject 2^64 without becoming incomplete"
  match normalizeProgramV1 overflowValidated with
  | .error (.typedNotOk _) => pure ()
  | .error e => throw <| IO.userError s!"lit-overflow: expected typedNotOk, got {repr e}"
  | .ok _ => throw <| IO.userError "lit-overflow: normalizer must not truncate 2^64"

  -- The enclosing UInt64 result supplies the width for either add operand;
  -- source order is preserved in the binary ValueId operands and semantic hash.
  let leftSource := wrap "LitOrder" <|
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    return 1 + x\n"
  let rightSource := wrap "LitOrder" <|
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    return x + 1\n"
  let leftValidated ← loadSource session "lit-order-left" leftSource
  let rightValidated ← loadSource session "lit-order-right" rightSource
  let leftCarrier ← match normalizeProgramV1 leftValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"lit-order-left: {repr e}"
  let rightCarrier ← match normalizeProgramV1 rightValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"lit-order-right: {repr e}"
  let leftData ← match validateSemanticProgramV1 leftCarrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"lit-order-left validate: {repr e}"
  let rightData ← match validateSemanticProgramV1 rightCarrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"lit-order-right validate: {repr e}"
  let some leftCallable := leftData.callables[0]? |
    throw <| IO.userError "lit-order-left: missing entry callable"
  let some leftBlock := leftCallable.blocks[0]? |
    throw <| IO.userError "lit-order-left: missing entry block"
  let some leftBinary := leftBlock.instructions[1]? |
    throw <| IO.userError "lit-order-left: missing binary instruction"
  let some rightCallable := rightData.callables[0]? |
    throw <| IO.userError "lit-order-right: missing entry callable"
  let some rightBlock := rightCallable.blocks[0]? |
    throw <| IO.userError "lit-order-right: missing entry block"
  let some rightBinary := rightBlock.instructions[1]? |
    throw <| IO.userError "lit-order-right: missing binary instruction"
  match leftBinary.op, rightBinary.op with
  | .binary .add leftLhs leftRhs, .binary .add rightLhs rightRhs =>
      expect (leftLhs == 1 && leftRhs == 0 && rightLhs == 0 && rightRhs == 1)
        s!"lit-order: expected (1,0)/(0,1), got ({leftLhs},{leftRhs})/({rightLhs},{rightRhs})"
  | _, _ => throw <| IO.userError "lit-order: expected binary add instructions"
  expect (leftCarrier.canonicalBytes != rightCarrier.canonicalBytes)
    "lit-order: operand order must change semantic bytes"
  let leftHash ← match semanticHashV1 leftCarrier with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"lit-order-left hash: {repr e}"
  let rightHash ← match semanticHashV1 rightCarrier with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"lit-order-right hash: {repr e}"
  expect (leftHash != rightHash) "lit-order: operand order must change semanticHash"

  -- Assignment and nested return contexts both thread the same UInt64 expected
  -- type; only the add contributes arithmetic/rollback requirements.
  let assignSource := wrap "LitAssign" <|
    "  state count : UInt64\n" ++
    "  entry run() : UInt64 do\n" ++
    "    count := 41\n" ++
    "    return count + 1\n"
  let assignValidated ← loadSource session "lit-assign" assignSource
  let assignCarrier ← match normalizeProgramV1 assignValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"lit-assign: {repr e}"
  let assignData ← match validateSemanticProgramV1 assignCarrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"lit-assign validate: {repr e}"
  let some assignCallable := assignData.callables[0]? |
    throw <| IO.userError "lit-assign: missing entry callable"
  let some assignBlock := assignCallable.blocks[0]? |
    throw <| IO.userError "lit-assign: missing entry block"
  expect (assignBlock.instructions.size == 5)
    s!"lit-assign: expected literal/store/load/literal/add, got {assignBlock.instructions.size}"
  let some assignLiteral := assignBlock.instructions[0]? |
    throw <| IO.userError "lit-assign: missing assignment literal"
  let some returnLiteral := assignBlock.instructions[3]? |
    throw <| IO.userError "lit-assign: missing return literal"
  match assignLiteral.op, returnLiteral.op with
  | .literal _ a, .literal _ b =>
      expect (a == encodeU64le 41 && b == encodeU64le 1)
        "lit-assign: exact assignment/return literal bytes"
  | _, _ => throw <| IO.userError "lit-assign: expected literal ops"
  let reqIds := assignData.requirements.items.map (·.id)
  expect (reqIds == #["failure.atomic-rollback", "state.persistent",
      "value.checked-arithmetic"])
    s!"lit-assign: exact requirements, got {reqIds}"

/-- UInt64 subtraction extends the same single-block checked-arithmetic envelope
    without changing type, requirement, state, or callable identities. -/
private unsafe def testUInt64Subtraction
    (session : Language.Loader.ParserSession) : IO Unit := do
  let subSource := wrap "Subtract" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry decrement(delta : UInt64) : UInt64 do\n" ++
    "    count := count - delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let subValidated ← loadSource session "sub" subSource
  let typed := checkProgramTypedResultV1 subValidated
  expect typed.ok "sub: CheckV1.ok"
  expect typed.analysisComplete "sub: CheckV1.analysisComplete"
  let subCarrier ← match normalizeProgramV1 subValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"sub: normalize: {repr e}"
  let subData ← match validateSemanticProgramV1 subCarrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"sub: validate: {repr e}"
  expect (subData.types.size == 2)
    s!"sub: retain UInt64 + Unit closure, got {subData.types.size} types"
  let some u64Type := subData.types[0]? |
    throw <| IO.userError "sub: missing UInt64 type"
  expect (match u64Type.shape with | TypeShapeV1.uint 64 => true | _ => false)
    "sub: type[0] must remain anonymous UInt64"
  let reqIds := subData.requirements.items.map (·.id)
  expect (reqIds == #["failure.atomic-rollback", "state.persistent",
      "value.checked-arithmetic"])
    s!"sub: exact existing requirements, got {reqIds}"
  let some entryC := subData.callables[1]? |
    throw <| IO.userError "sub: missing decrement callable"
  let some block := entryC.blocks[0]? |
    throw <| IO.userError "sub: missing decrement block"
  expect (block.instructions.size == 4)
    s!"sub: expected load/sub/store/load, got {block.instructions.size}"
  let some binaryInstr := block.instructions[1]? |
    throw <| IO.userError "sub: missing binary instruction"
  let some binaryResult := binaryInstr.result |
    throw <| IO.userError "sub: binary result missing"
  match binaryInstr.op with
  | .binary .sub lhs rhs =>
      expect (binaryResult.valueId == 2 && binaryResult.typeId == 0 &&
          lhs == 1 && rhs == 0)
        s!"sub: expected vid2=load1-param0, got {binaryResult.valueId}/{lhs}/{rhs}"
  | _ => throw <| IO.userError "sub: expected exact BinaryOpV1.sub"
  let some storeInstr := block.instructions[2]? |
    throw <| IO.userError "sub: missing stateStore instruction"
  match storeInstr.op with
  | SemanticOpV1.stateStore sid vid =>
      expect (sid == 0 && vid == 2)
        s!"sub: expected store state0/vid2, got {sid}/{vid}"
  | _ => throw <| IO.userError "sub: expected stateStore"
  match block.terminator with
  | TerminatorV1.return_ (some returned) =>
      expect (returned == 3) s!"sub: expected return vid3, got {returned}"
  | _ => throw <| IO.userError "sub: expected return after stateStore"
  let subCarrier2 ← match normalizeProgramV1 subValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"sub-repeat: normalize: {repr e}"
  expect (subCarrier.canonicalBytes == subCarrier2.canonicalBytes)
    "sub: repeated normalization bytes deterministic"
  let subHash ← match semanticHashV1 subCarrier with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"sub: hash: {repr e}"
  let subHash2 ← match semanticHashV1 subCarrier2 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"sub-repeat: hash: {repr e}"
  expect (subHash == subHash2) "sub: repeated semanticHash deterministic"

  -- An otherwise identical add program must not alias subtraction bytes/hash.
  let addSource := wrap "Subtract" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry decrement(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let addValidated ← loadSource session "sub-add-nonalias" addSource
  let addCarrier ← match normalizeProgramV1 addValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"sub-add-nonalias: normalize: {repr e}"
  let addHash ← match semanticHashV1 addCarrier with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"sub-add-nonalias: hash: {repr e}"
  expect (subCarrier.canonicalBytes != addCarrier.canonicalBytes && subHash != addHash)
    "sub: BinaryOpV1.sub must not alias add bytes/hash"

private unsafe def testAssertComparison
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "Guarded" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry decrement(delta : UInt64) : UInt64 do\n" ++
    "    assert count >= delta\n" ++
    "    count := count - delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "assert-cmp" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "assert-cmp: CheckV1.ok"
  expect typed.analysisComplete "assert-cmp: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"assert-cmp: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"assert-cmp: validate: {repr e}"
  -- Interner order: state UInt64 (0), init Unit (1), entry comparison Bool (2).
  expect (data.types.size == 3)
    s!"assert-cmp: expected UInt64+Unit+Bool closure, got {data.types.size} types"
  let some boolType := data.types[2]? |
    throw <| IO.userError "assert-cmp: missing interned Bool type"
  expect (boolType.name.isNone &&
      (match boolType.shape with | TypeShapeV1.bool => true | _ => false))
    "assert-cmp: type[2] must be anonymous Bool"
  let reqIds := data.requirements.items.map (·.id)
  expect (reqIds == #["failure.atomic-rollback", "state.persistent",
      "value.checked-arithmetic"])
    s!"assert-cmp: assert must reuse existing rollback requirement, got {reqIds}"
  let some entryC := data.callables[1]? |
    throw <| IO.userError "assert-cmp: missing decrement callable"
  let some block := entryC.blocks[0]? |
    throw <| IO.userError "assert-cmp: missing decrement block"
  expect (block.instructions.size == 7)
    s!"assert-cmp: expected load/ge/assert/load/sub/store/load, got {block.instructions.size}"
  let some cmpInstr := block.instructions[1]? |
    throw <| IO.userError "assert-cmp: missing comparison instruction"
  let some cmpResult := cmpInstr.result |
    throw <| IO.userError "assert-cmp: comparison result missing"
  match cmpInstr.op with
  | .binary .ge lhs rhs =>
      expect (cmpResult.valueId == 2 && cmpResult.typeId == 2 && lhs == 1 && rhs == 0)
        s!"assert-cmp: expected vid2=ge(load1,param0) Bool, got {cmpResult.valueId}/{lhs}/{rhs}"
  | _ => throw <| IO.userError "assert-cmp: expected exact BinaryOpV1.ge"
  let some assertInstr := block.instructions[2]? |
    throw <| IO.userError "assert-cmp: missing assert instruction"
  expect assertInstr.result.isNone "assert-cmp: assert must be void"
  match assertInstr.op with
  | SemanticOpV1.assert_ cond errorId args =>
      expect (cond == 2 && errorId.isNone && args.isEmpty)
        s!"assert-cmp: expected assert(vid2,none,[]), got {cond}/{errorId.isSome}/{args.size}"
  | _ => throw <| IO.userError "assert-cmp: expected Op.Assert"
  let some subInstr := block.instructions[4]? |
    throw <| IO.userError "assert-cmp: missing sub instruction"
  match subInstr.op with
  | .binary .sub lhs rhs =>
      expect (lhs == 3 && rhs == 0)
        s!"assert-cmp: sub must consume fresh load vid3 after assert, got {lhs}/{rhs}"
  | _ => throw <| IO.userError "assert-cmp: expected BinaryOpV1.sub after assert"
  match block.terminator with
  | TerminatorV1.return_ (some returned) =>
      expect (returned == 5) s!"assert-cmp: expected return vid5, got {returned}"
  | _ => throw <| IO.userError "assert-cmp: expected return after store"
  let carrier2 ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"assert-cmp-repeat: normalize: {repr e}"
  expect (carrier.canonicalBytes == carrier2.canonicalBytes)
    "assert-cmp: repeated normalization bytes deterministic"
  -- The same program without the assert must not alias bytes/hash.
  let plainSource := wrap "Guarded" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry decrement(delta : UInt64) : UInt64 do\n" ++
    "    count := count - delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let plainValidated ← loadSource session "assert-cmp-nonalias" plainSource
  let plainCarrier ← match normalizeProgramV1 plainValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"assert-cmp-nonalias: normalize: {repr e}"
  expect (carrier.canonicalBytes != plainCarrier.canonicalBytes)
    "assert-cmp: assert program must not alias assert-free bytes"
  -- Provenance authority accepts the assert/comparison program.
  let (withSpans, spans) ← loadSourceWithSpans session "assert-cmp-prov" source
  let path ← parseTestPath "assert-cmp-prov"
  match ← (pure (normalizeProgramWithProvenanceV1 withSpans path spans)
      : IO (Except NormalizeErrorV1 _)) with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"assert-cmp-prov: provenance authority: {repr e}"

private unsafe def testAllComparisonOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "Compares" <|
    "  entry check(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    assert a == b\n" ++
    "    assert a != b\n" ++
    "    assert a < b\n" ++
    "    assert a <= b\n" ++
    "    assert a > b\n" ++
    "    assert a >= b\n" ++
    "    return a\n"
  let validated ← loadSource session "cmp-ops" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "cmp-ops: CheckV1.ok"
  expect typed.analysisComplete "cmp-ops: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"cmp-ops: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"cmp-ops: validate: {repr e}"
  -- No state/init: types are UInt64 (0) then Bool (1); rollback is the only requirement.
  expect (data.types.size == 2)
    s!"cmp-ops: expected UInt64+Bool closure, got {data.types.size}"
  let reqIds := data.requirements.items.map (·.id)
  expect (reqIds == #["failure.atomic-rollback"])
    s!"cmp-ops: comparisons add no requirement beyond assert rollback, got {reqIds}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "cmp-ops: missing check callable"
  let some block := entryC.blocks[0]? |
    throw <| IO.userError "cmp-ops: missing check block"
  expect (block.instructions.size == 12)
    s!"cmp-ops: expected 6 comparisons + 6 asserts, got {block.instructions.size}"
  let opOf : Nat → ProofForgeV2.Semantic.WireV1.BinaryOpV1
    | 0 => .eq | 1 => .ne | 2 => .lt | 3 => .le | 4 => .gt | _ => .ge
  for i in [:6] do
    let some cmpInstr := block.instructions[i * 2]? |
      throw <| IO.userError s!"cmp-ops: missing comparison {i}"
    let some cmpResult := cmpInstr.result |
      throw <| IO.userError s!"cmp-ops: comparison {i} result missing"
    match cmpInstr.op with
    | .binary op lhs rhs =>
        expect (op == opOf i && cmpResult.valueId == UInt32.ofNat (i + 2) &&
            cmpResult.typeId == 1 && lhs == 0 && rhs == 1)
          s!"cmp-ops: comparison {i} expected {repr (opOf i)} on params, got {repr op}"
    | _ => throw <| IO.userError s!"cmp-ops: comparison {i} expected binary"
    let some assertInstr := block.instructions[i * 2 + 1]? |
      throw <| IO.userError s!"cmp-ops: missing assert {i}"
    expect assertInstr.result.isNone s!"cmp-ops: assert {i} must be void"
    match assertInstr.op with
    | SemanticOpV1.assert_ cond errorId args =>
        expect (cond == UInt32.ofNat (i + 2) && errorId.isNone && args.isEmpty)
          s!"cmp-ops: assert {i} must bind comparison vid{i + 2}"
    | _ => throw <| IO.userError s!"cmp-ops: assert {i} expected Op.Assert"
  match block.terminator with
  | TerminatorV1.return_ (some returned) =>
      expect (returned == 0) s!"cmp-ops: expected return param vid0, got {returned}"
  | _ => throw <| IO.userError "cmp-ops: expected return after asserts"

private unsafe def testAssertBoolLiteral
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BoolLit" <|
    "  entry check(x : UInt64) : UInt64 do\n" ++
    "    assert true\n" ++
    "    return x\n"
  let validated ← loadSource session "bool-lit" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "bool-lit: CheckV1.ok"
  expect typed.analysisComplete "bool-lit: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"bool-lit: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"bool-lit: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "bool-lit: missing check callable"
  let some block := entryC.blocks[0]? |
    throw <| IO.userError "bool-lit: missing check block"
  expect (block.instructions.size == 2)
    s!"bool-lit: expected literal + assert, got {block.instructions.size}"
  let some litInstr := block.instructions[0]? |
    throw <| IO.userError "bool-lit: missing literal instruction"
  let some litResult := litInstr.result |
    throw <| IO.userError "bool-lit: literal result missing"
  match litInstr.op with
  | .literal typeId bytes =>
      expect (litResult.valueId == 1 && litResult.typeId == 1 &&
          typeId == 1 && bytes == ByteArray.mk #[1])
        s!"bool-lit: expected literal Bool(1) true, got tid{typeId}/{bytes.toList}"
  | _ => throw <| IO.userError "bool-lit: expected Op.Literal"
  let some assertInstr := block.instructions[1]? |
    throw <| IO.userError "bool-lit: missing assert instruction"
  match assertInstr.op with
  | SemanticOpV1.assert_ cond errorId args =>
      expect (cond == 1 && errorId.isNone && args.isEmpty)
        s!"bool-lit: expected assert(vid1), got {cond}"
  | _ => throw <| IO.userError "bool-lit: expected Op.Assert"

private unsafe def testBoolViewResult
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BoolView" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view positive() : Bool do\n" ++
    "    return count > 0\n" ++
    "  view saturated() : Bool do\n" ++
    "    return count == 18446744073709551615\n"
  let validated ← loadSource session "bool-view" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "bool-view: CheckV1.ok"
  expect typed.analysisComplete "bool-view: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"bool-view: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"bool-view: validate: {repr e}"
  -- Types: state UInt64 (0), init Unit (1), first comparison Bool (2).
  expect (data.types.size == 3)
    s!"bool-view: expected UInt64+Unit+Bool closure, got {data.types.size}"
  let some boolType := data.types[2]? |
    throw <| IO.userError "bool-view: missing interned Bool type"
  expect (boolType.name.isNone &&
      (match boolType.shape with | TypeShapeV1.bool => true | _ => false))
    "bool-view: type[2] must be anonymous Bool"
  expect (data.callables.size == 4) "bool-view: init + entry + 2 views"
  let some posC := data.callables[2]? |
    throw <| IO.userError "bool-view: missing positive view"
  expect (posC.kind == .view && posC.name == some "positive")
    "bool-view: positive view kind/name"
  expect (posC.result.typeId == 2 && posC.result.visibility == .public_)
    "bool-view: positive result must be public Bool"
  let some posBlk := posC.blocks[0]? |
    throw <| IO.userError "bool-view: missing positive block"
  expect (posBlk.instructions.size == 3)
    s!"bool-view: expected load + literal + gt, got {posBlk.instructions.size}"
  let some gtInstr := posBlk.instructions[2]? |
    throw <| IO.userError "bool-view: missing gt instruction"
  let some gtResult := gtInstr.result |
    throw <| IO.userError "bool-view: gt result missing"
  match gtInstr.op with
  | .binary .gt lhs rhs =>
      expect (gtResult.valueId == 2 && gtResult.typeId == 2 && lhs == 0 && rhs == 1)
        s!"bool-view: expected vid2=gt(load0,lit1) Bool, got {gtResult.valueId}/{lhs}/{rhs}"
  | _ => throw <| IO.userError "bool-view: expected BinaryOpV1.gt"
  match posBlk.terminator with
  | TerminatorV1.return_ (some returned) =>
      expect (returned == 2) s!"bool-view: expected return vid2, got {returned}"
  | _ => throw <| IO.userError "bool-view: expected return of comparison"
  let some satC := data.callables[3]? |
    throw <| IO.userError "bool-view: missing saturated view"
  expect (satC.result.typeId == 2) "bool-view: saturated result must be Bool"
  let carrier2 ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"bool-view-repeat: normalize: {repr e}"
  expect (carrier.canonicalBytes == carrier2.canonicalBytes)
    "bool-view: repeated normalization bytes deterministic"
  -- Provenance authority accepts a Bool-result program.
  let (withSpans, spans) ← loadSourceWithSpans session "bool-view-prov" source
  let path ← parseTestPath "bool-view-prov"
  match ← (pure (normalizeProgramWithProvenanceV1 withSpans path spans)
      : IO (Except NormalizeErrorV1 _)) with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"bool-view-prov: provenance authority: {repr e}"

private unsafe def testBoolEntryResultAndLiteral
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BoolEntry" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry equalsCount(delta : UInt64) : Bool do\n" ++
    "    return count == delta\n" ++
    "  view yes() : Bool do\n" ++
    "    return true\n"
  let validated ← loadSource session "bool-entry" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "bool-entry: CheckV1.ok"
  expect typed.analysisComplete "bool-entry: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"bool-entry: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"bool-entry: validate: {repr e}"
  let some entryC := data.callables[1]? |
    throw <| IO.userError "bool-entry: missing matches entry"
  expect (entryC.kind == .entry && entryC.result.typeId == 2)
    "bool-entry: entry result must be Bool"
  let some viewC := data.callables[2]? |
    throw <| IO.userError "bool-entry: missing yes view"
  let some viewBlk := viewC.blocks[0]? |
    throw <| IO.userError "bool-entry: missing yes block"
  expect (viewBlk.instructions.size == 1)
    s!"bool-entry: expected single Bool literal, got {viewBlk.instructions.size}"
  let some litInstr := viewBlk.instructions[0]? |
    throw <| IO.userError "bool-entry: missing literal instruction"
  match litInstr.op with
  | .literal typeId bytes =>
      expect (typeId == 2 && bytes == ByteArray.mk #[1])
        s!"bool-entry: expected literal Bool true, got tid{typeId}/{bytes.toList}"
  | _ => throw <| IO.userError "bool-entry: expected Op.Literal"
  match viewBlk.terminator with
  | TerminatorV1.return_ (some returned) =>
      expect (returned == 0) s!"bool-entry: expected return vid0, got {returned}"
  | _ => throw <| IO.userError "bool-entry: expected return of literal"

private unsafe def testIfMultiBlock
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "IfFlow" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    else\n" ++
    "      count := delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "if-flow" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "if-flow: CheckV1.ok"
  expect typed.analysisComplete "if-flow: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"if-flow: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"if-flow: validate: {repr e}"
  let some entryC := data.callables[1]? |
    throw <| IO.userError "if-flow: missing bump callable"
  expect (entryC.blocks.size == 4)
    s!"if-flow: expected cond/then/else/join blocks, got {entryC.blocks.size}"
  -- block0: load count(vid1), literal 0(vid2), gt(vid3 Bool), branch
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "if-flow: missing block0"
  expect (blk0.instructions.size == 3)
    s!"if-flow: block0 expected 3 instrs, got {blk0.instructions.size}"
  match blk0.terminator with
  | .branch cond thenT elseT =>
      expect (cond == 3 && thenT.blockId == 1 && thenT.args.isEmpty &&
          elseT.blockId == 2 && elseT.args.isEmpty)
        s!"if-flow: branch must target then=1 else=2, got {cond}/{thenT.blockId}/{elseT.blockId}"
  | _ => throw <| IO.userError "if-flow: block0 must terminate in branch"
  -- then: load count(vid4), add(vid5), store, jump join
  let some blk1 := entryC.blocks[1]? |
    throw <| IO.userError "if-flow: missing then block"
  expect (blk1.instructions.size == 3)
    s!"if-flow: then expected load/add/store, got {blk1.instructions.size}"
  match blk1.terminator with
  | .jump t =>
      expect (t.blockId == 3 && t.args.isEmpty)
        s!"if-flow: then must jump join=3, got {t.blockId}"
  | _ => throw <| IO.userError "if-flow: then must terminate in jump"
  -- else: store param delta (vid0), jump join
  let some blk2 := entryC.blocks[2]? |
    throw <| IO.userError "if-flow: missing else block"
  expect (blk2.instructions.size == 1)
    s!"if-flow: else expected single store, got {blk2.instructions.size}"
  match blk2.terminator with
  | .jump t =>
      expect (t.blockId == 3 && t.args.isEmpty)
        s!"if-flow: else must jump join=3, got {t.blockId}"
  | _ => throw <| IO.userError "if-flow: else must terminate in jump"
  -- join: load count(vid6), return vid6
  let some blk3 := entryC.blocks[3]? |
    throw <| IO.userError "if-flow: missing join block"
  expect (blk3.instructions.size == 1)
    s!"if-flow: join expected single load, got {blk3.instructions.size}"
  match blk3.terminator with
  | .return_ (some vid) =>
      expect (vid == 6) s!"if-flow: join must return vid6, got {vid}"
  | _ => throw <| IO.userError "if-flow: join must return"
  let carrier2 ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"if-flow-repeat: normalize: {repr e}"
  expect (carrier.canonicalBytes == carrier2.canonicalBytes)
    "if-flow: repeated normalization bytes deterministic"
  -- Provenance authority accepts the multi-block program.
  let (withSpans, spans) ← loadSourceWithSpans session "if-flow-prov" source
  let path ← parseTestPath "if-flow-prov"
  match ← (pure (normalizeProgramWithProvenanceV1 withSpans path spans)
      : IO (Except NormalizeErrorV1 _)) with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"if-flow-prov: provenance authority: {repr e}"

private unsafe def testIfBothBranchesReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "IfBoth" <|
    "  state count : UInt64\n" ++
    "  entry pick(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      return count\n" ++
    "    else\n" ++
    "      return delta\n"
  let validated ← loadSource session "if-both" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "if-both: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"if-both: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"if-both: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "if-both: missing pick callable"
  expect (entryC.blocks.size == 3)
    s!"if-both: both-return if must not materialize a join, got {entryC.blocks.size}"
  let some blk1 := entryC.blocks[1]? |
    throw <| IO.userError "if-both: missing then block"
  match blk1.terminator with
  | .return_ (some _) => pure ()
  | _ => throw <| IO.userError "if-both: then must return"
  let some blk2 := entryC.blocks[2]? |
    throw <| IO.userError "if-both: missing else block"
  match blk2.terminator with
  | .return_ (some _) => pure ()
  | _ => throw <| IO.userError "if-both: else must return"

private unsafe def testIfNoElse
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "IfNoElse" <|
    "  state count : UInt64\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    return count\n"
  let validated ← loadSource session "if-noelse" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "if-noelse: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"if-noelse: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"if-noelse: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "if-noelse: missing bump callable"
  expect (entryC.blocks.size == 3)
    s!"if-noelse: expected cond/then/join (else falls to join), got {entryC.blocks.size}"
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "if-noelse: missing block0"
  match blk0.terminator with
  | .branch _ thenT elseT =>
      expect (thenT.blockId == 1 && elseT.blockId == 2)
        s!"if-noelse: absent else must target join=2, got {elseT.blockId}"
  | _ => throw <| IO.userError "if-noelse: block0 must branch"
  let some blk2 := entryC.blocks[2]? |
    throw <| IO.userError "if-noelse: missing join block"
  match blk2.terminator with
  | .return_ (some _) => pure ()
  | _ => throw <| IO.userError "if-noelse: join must return"

private unsafe def testNestedIf
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "NestedIf" <|
    "  state count : UInt64\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      if delta > 0 then\n" ++
    "        count := count + delta\n" ++
    "      else\n" ++
    "        count := 1\n" ++
    "    else\n" ++
    "      count := 2\n" ++
    "    return count\n"
  let validated ← loadSource session "nested-if" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "nested-if: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"nested-if: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"nested-if: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "nested-if: missing bump callable"
  -- outer cond(0) + inner cond(1) + inner then(2) + inner else(3) + inner join(4)
  -- + outer else(5) + outer join(6)
  expect (entryC.blocks.size == 7)
    s!"nested-if: expected 7 blocks, got {entryC.blocks.size}"
  let some blk1 := entryC.blocks[1]? |
    throw <| IO.userError "nested-if: missing inner-cond block"
  match blk1.terminator with
  | .branch _ thenT elseT =>
      expect (thenT.blockId == 2 && elseT.blockId == 3)
        s!"nested-if: inner branch targets, got {thenT.blockId}/{elseT.blockId}"
  | _ => throw <| IO.userError "nested-if: block1 must be inner branch"
  let some blk4 := entryC.blocks[4]? |
    throw <| IO.userError "nested-if: missing inner join block"
  match blk4.terminator with
  | .jump t =>
      expect (t.blockId == 6)
        s!"nested-if: inner join must jump outer join=6, got {t.blockId}"
  | _ => throw <| IO.userError "nested-if: inner join must jump"
  let some blk6 := entryC.blocks[6]? |
    throw <| IO.userError "nested-if: missing outer join block"
  match blk6.terminator with
  | .return_ (some _) => pure ()
  | _ => throw <| IO.userError "nested-if: outer join must return"

private unsafe def testMatchUIntLiterals
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MatchUint" <|
    "  state count : UInt64\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n"
  let validated ← loadSource session "match-uint" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "match-uint: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"match-uint: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"match-uint: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "match-uint: missing apply callable"
  -- scrut block(0) + case0(1) + case1(2) + default(3) + join(4)
  expect (entryC.blocks.size == 5)
    s!"match-uint: expected 5 blocks, got {entryC.blocks.size}"
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "match-uint: missing scrut block"
  match blk0.terminator with
  | .switch scrut cases (some defaultT) =>
      expect (scrut == 0) s!"match-uint: scrutinee must be param vid0, got {scrut}"
      expect (cases.size == 2) s!"match-uint: expected 2 cases, got {cases.size}"
      let some c0 := cases[0]? |
        throw <| IO.userError "match-uint: missing case0"
      expect (c0.valueBytes == encodeU64le 0 && c0.target.blockId == 1)
        s!"match-uint: case0 must be 0→block1"
      let some c1 := cases[1]? |
        throw <| IO.userError "match-uint: missing case1"
      expect (c1.valueBytes == encodeU64le 1 && c1.target.blockId == 2)
        s!"match-uint: case1 must be 1→block2"
      expect (defaultT.blockId == 3)
        s!"match-uint: default must target block3, got {defaultT.blockId}"
  | _ => throw <| IO.userError "match-uint: scrut block must switch"
  let some blk1 := entryC.blocks[1]? |
    throw <| IO.userError "match-uint: missing case0 block"
  match blk1.terminator with
  | .return_ (some _) => pure ()
  | _ => throw <| IO.userError "match-uint: case0 must return"
  let some blk2 := entryC.blocks[2]? |
    throw <| IO.userError "match-uint: missing case1 block"
  match blk2.terminator with
  | .jump t =>
      expect (t.blockId == 4) s!"match-uint: case1 must jump join=4, got {t.blockId}"
  | _ => throw <| IO.userError "match-uint: case1 must jump"
  let some blk3 := entryC.blocks[3]? |
    throw <| IO.userError "match-uint: missing default block"
  match blk3.terminator with
  | .jump t =>
      expect (t.blockId == 4) s!"match-uint: default must jump join=4, got {t.blockId}"
  | _ => throw <| IO.userError "match-uint: default must jump"
  let some blk4 := entryC.blocks[4]? |
    throw <| IO.userError "match-uint: missing join block"
  match blk4.terminator with
  | .return_ (some _) => pure ()
  | _ => throw <| IO.userError "match-uint: join must return"

private unsafe def testMatchBoolAndBind
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MatchBind" <|
    "  state count : UInt64\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | rest => do\n" ++
    "      count := count + rest\n" ++
    "    return count\n"
  let validated ← loadSource session "match-bind" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "match-bind: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"match-bind: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"match-bind: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "match-bind: missing apply callable"
  -- Catch-all-only match is straight-line: binder aliases the scrutinee and
  -- the arm body lowers inline into the single block (no block, no jump).
  expect (entryC.blocks.size == 1)
    s!"match-bind: catch-all-only match must stay single-block, got {entryC.blocks.size}"
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "match-bind: missing entry block"
  -- Body: load count(vid1), add(load, binder=scrut vid0)→vid2, store; load(vid3); return vid3.
  expect (blk0.instructions.size == 4)
    s!"match-bind: expected load/add/store/load, got {blk0.instructions.size}"
  let some addInstr := blk0.instructions[1]? |
    throw <| IO.userError "match-bind: missing add instruction"
  match addInstr.op with
  | .binary .add lhs rhs =>
      expect (lhs == 1 && rhs == 0)
        s!"match-bind: binder must alias scrutinee vid0, got {lhs}/{rhs}"
  | _ => throw <| IO.userError "match-bind: expected binary add on binder"
  match blk0.terminator with
  | .return_ (some vid) =>
      expect (vid == 3) s!"match-bind: expected return vid3, got {vid}"
  | _ => throw <| IO.userError "match-bind: expected return"

private unsafe def testUnsupportedStatementAfterTerminalIf
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "DeadAfterIf" <|
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    if x > 0 then\n" ++
    "      return x\n" ++
    "    else\n" ++
    "      return 0\n" ++
    "    return 1\n"
  expectUnsupportedAfterCheckOk session "dead-after-if" source
    (fun d => d.contains "after return")
    "statements after return"

private unsafe def testUnsupportedMatchDuplicateLiteral
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "DupLit" <|
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    match x with\n" ++
    "    | 1 => do\n" ++
    "      return 1\n" ++
    "    | 1 => do\n" ++
    "      return 2\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  expectUnsupportedAfterCheckOk session "dup-lit" source
    (fun d => d.contains "duplicate")
    "duplicate literal"

private unsafe def testUnsupportedMatchConstructorPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Enum types register in Pass0, but entry params remain legal-UInt only and
  -- constructor patterns stay fail closed. The first gate is usually the
  -- named Color parameter (before match arms are lowered).
  let source := wrap "CtorPat" <|
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "  entry f(c : Color) : UInt64 do\n" ++
    "    match c with\n" ++
    "    | Color.Red() => do\n" ++
    "      return 1\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  expectUnsupportedAfterCheckOk session "ctor-pat" source
    (fun d =>
      d.contains "named" || d.contains "parameter" || d.contains "UInt" ||
      d.contains "constructor")
    "named param / constructor pattern"

/-- Event/error declaration tables plus emit/revert lowering: exact table
    shapes, canonical EffectId order, revert terminator closing the path. -/
private unsafe def testEmitRevertMultiBlock
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "EventFlow" <|
    "  state count : UInt64\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "event-flow" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "event-flow: CheckV1.ok"
  expect typed.analysisComplete "event-flow: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"event-flow: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"event-flow: validate: {repr e}"
  -- Declaration tables: source order, UInt64 public fields.
  let some eventDecl := data.events[0]? |
    throw <| IO.userError "event-flow: missing event declaration"
  expect (data.events.size == 1 && eventDecl.name == "Moved" &&
      eventDecl.fields.map (·.name) == #["src", "dst"] &&
      eventDecl.fields.all (·.visibility == .public_))
    "event-flow: event table must preserve declaration order and public fields"
  let some errorDecl := data.errors[0]? |
    throw <| IO.userError "event-flow: missing error declaration"
  expect (data.errors.size == 1 && errorDecl.name == "Cap" &&
      errorDecl.fields.map (·.name) == #["limit"])
    "event-flow: error table must preserve declaration order"
  let some entryC := data.callables[1]? |
    throw <| IO.userError "event-flow: missing bump callable"
  -- block0: emit(effectId 0, event 0, [load count, param delta]) then branch.
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "event-flow: missing block0"
  let emitOps := blk0.instructions.filter fun instr =>
    match instr.op with | .emit .. => true | _ => false
  expect (emitOps.size == 1)
    s!"event-flow: block0 must contain exactly one emit, got {emitOps.size}"
  let some emitInstr := emitOps[0]? |
    throw <| IO.userError "event-flow: missing emit instruction"
  match emitInstr with
  | { result, op := .emit effectId eventId args } =>
      expect (result.isNone && effectId == 0 && eventId == 0 && args.size == 2)
        "event-flow: emit must be void with effectId 0, event 0, two args"
  | _ => throw <| IO.userError "event-flow: emit op shape mismatch"
  -- then-block: revert(error 0, [param delta]) terminator closes the path.
  let some blk1 := entryC.blocks[1]? |
    throw <| IO.userError "event-flow: missing then block"
  match blk1.terminator with
  | .revert errorId args =>
      expect (errorId == 0 && args.size == 1)
        "event-flow: revert must bind error 0 with one arg"
  | _ => throw <| IO.userError "event-flow: then block must terminate in revert"
  -- else path flows to the join, which returns (four blocks total).
  expect (entryC.blocks.size == 4)
    s!"event-flow: expected cond/then-revert/else/join blocks, got {entryC.blocks.size}"
  let some blk3 := entryC.blocks[3]? |
    throw <| IO.userError "event-flow: missing join block"
  match blk3.terminator with
  | .return_ (some _) => pure ()
  | _ => throw <| IO.userError "event-flow: join block must return"

/-- Requirements wire order: `effect.event` is first among contributed keys;
    programs without events keep the existing four-key shape. -/
private unsafe def testEmitRequirementsWireOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "EventFlow" <|
    "  state count : UInt64\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "event-req" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"event-req: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"event-req: validate: {repr e}"
  expect (data.requirements.items.map (·.id) == #[
      "effect.event", "failure.atomic-rollback", "state.persistent",
      "value.checked-arithmetic"])
    s!"event-req: wire order must put effect.event first, got {data.requirements.items.map (·.id)}"

/-- Emit in a view is an effect violation: CheckV1 rejects before Normalize. -/
private unsafe def testEmitInViewTypedNotOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ViewEmit" <|
    "  state count : UInt64\n" ++
    "  event Seen(spot : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  view get() : UInt64 do\n" ++
    "    emit Seen(count)\n" ++
    "    return count\n"
  let validated ← loadSource session "view-emit" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok) "view-emit: CheckV1 must reject emit in a view"
  match normalizeProgramV1 validated with
  | .ok _ => throw <| IO.userError "view-emit: normalize must not accept typed-not-ok"
  | .error (.typedNotOk _) => pure ()
  | .error e =>
      throw <| IO.userError s!"view-emit: expected .typedNotOk, got {repr e}"

/-- Bool event fields pass CheckV1 but fail closed at the normalizer. -/
private unsafe def testUnsupportedEventBoolField
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BoolEvent" <|
    "  event Toggled(on : Bool)\n" ++
    "  entry ping(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  expectUnsupportedAfterCheckOk session "event-bool-field" source
    (fun d => d.contains "UInt64" || d.contains "field")
    "UInt64 event field"

/-- Non-public event fields pass CheckV1 but fail closed at the normalizer. -/
private unsafe def testUnsupportedEventPrivateField
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "PrivEvent" <|
    "  event Hidden(private spot : UInt64)\n" ++
    "  entry ping(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  expectUnsupportedAfterCheckOk session "event-private-field" source
    (fun d => d.contains "public")
    "public event field"

private unsafe def testUnsupportedBoolState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BoolState" <|
    "  state flag : Bool\n" ++
    "  entry ping(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  expectUnsupportedAfterCheckOk session "bool-state" source
    (fun d => d.contains "UInt64" || d.contains "state")
    "UInt64 state"

private unsafe def testUnsupportedBoolParam
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BoolParam" <|
    "  state count : UInt64\n" ++
    "  entry ping(flag : Bool) : UInt64 do\n" ++
    "    return count\n"
  expectUnsupportedAfterCheckOk session "bool-param" source
    (fun d => d.contains "UInt64" || d.contains "param")
    "UInt64 param"

private unsafe def testUnsupportedAssertElse
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Entry precedes the error declaration so the assert-else gate (not the
  -- item-level error gate) produces the unsupported detail.
  let source := wrap "AssertElse" <|
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else bad\n" ++
    "    return x\n" ++
    "  error bad()\n"
  expectUnsupportedAfterCheckOk session "assert-else" source
    (fun d => d.contains "assert" || d.contains "else")
    "assert-else"

private unsafe def testUnsupportedNestedComparison
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- `(a == b) == true` is CheckV1-ok (eq on Bool operands is serializable),
  -- but the S1 normalizer lowers comparisons on UInt64 operands only.
  let source := wrap "NestedCmp" <|
    "  entry f(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    assert (a == b) == true\n" ++
    "    return a\n"
  expectUnsupportedAfterCheckOk session "nested-cmp" source
    (fun d => d.contains "UInt64" || d.contains "comparison")
    "UInt64 comparison operands"

/-- Identity fn + direct local call: now a supported positive case (the
    former normalize-boundary negative). -/
private unsafe def testFnIdentitySupported
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FnOnly" <|
    "  fn helper(x : UInt64) : UInt64 do\n" ++
    "    return x\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    return helper(x)\n"
  let validated ← loadSource session "fn-identity" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "fn-identity: CheckV1.ok"
  match normalizeProgramV1 validated with
  | .ok carrier =>
      match validateSemanticProgramV1 carrier with
      | .ok data =>
          let kinds := data.callables.map (·.kind)
          expect (data.callables.size == 2 && kinds == #[.pureFn, .entry])
            "fn-identity: pureFn + entry must both normalize"
      | .error e => throw <| IO.userError s!"fn-identity: validate: {repr e}"
  | .error e => throw <| IO.userError s!"fn-identity: normalize must now succeed, got {repr e}"

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

/-- Provenance for emit/revert: declaration entities, instruction/effect
    entities on the emit statement, and the revert terminator entity. -/
private unsafe def testEmitRevertProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "EventFlow" <|
    "  state count : UInt64\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "event-prov" source
  let path ← parseTestPath "event-prov"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"event-prov: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"event-prov: normalize: {repr e}"
  match validateSemanticProgramV1 carrier with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"event-prov: validate: {repr e}"
  -- Declaration entities bind their item nodes.
  let eventItemPath := childPathT #[] "Program" "items" 1
  let errorItemPath := childPathT #[] "Program" "items" 2
  let eventItemOrigin ← originAtExplicitPath validated inventory eventItemPath
  let errorItemOrigin ← originAtExplicitPath validated inventory errorItemPath
  let some eventOrigin := findOrigin provenance (.event 0) |
    throw <| IO.userError "event-prov: missing event decl origin"
  let some errorOrigin := findOrigin provenance (.errorRef 0) |
    throw <| IO.userError "event-prov: missing error decl origin"
  expect (eventOrigin == eventItemOrigin && errorOrigin == errorItemOrigin)
    "event-prov: declaration entities must bind their item nodes"
  -- The emit statement binds both its instruction and effect entities.
  let entryItemPath := childPathT #[] "Program" "items" 4
  let bodyPath := directChildT entryItemPath "EntryDecl" "body"
  let emitStmtPath := childPathT bodyPath "Block" "statements" 0
  let ifStmtPath := childPathT bodyPath "Block" "statements" 1
  let thenPath := directChildT ifStmtPath "Stmt.If" "thenBlock"
  let revertStmtPath := childPathT thenPath "Block" "statements" 0
  let emitStmtOrigin ← originAtExplicitPath validated inventory emitStmtPath
  let revertStmtOrigin ← originAtExplicitPath validated inventory revertStmtPath
  -- block0: stateLoad(instr0) → emit(instr1) → stateLoad(instr2) → gt(instr3).
  let some instrOrigin := findOrigin provenance (.instruction 1 0 1) |
    throw <| IO.userError "event-prov: missing emit instruction origin"
  let some effectOrigin := findOrigin provenance (.effect 1 0) |
    throw <| IO.userError "event-prov: missing effect origin"
  expect (instrOrigin == emitStmtOrigin && effectOrigin == emitStmtOrigin)
    "event-prov: emit instruction/effect entities must bind the emit statement"
  -- The revert terminator binds the revert statement inside the then block.
  let some termOrigin := findOrigin provenance (.terminator 1 1) |
    throw <| IO.userError "event-prov: missing revert terminator origin"
  expect (termOrigin == revertStmtOrigin)
    "event-prov: revert terminator must bind the revert statement"

/-- Fn declarations and local calls: pureFn callables with canonical ids,
    Op.PureCall with exact args, and nested fn→fn calls. -/
private unsafe def testFnLocalCall
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FnFlow" <|
    "  state count : UInt64\n" ++
    "  fn double(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n" ++
    "  fn quadruple(y : UInt64) : UInt64 do\n" ++
    "    return double(y) + double(y)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := double(count) + quadruple(delta)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "fn-flow" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "fn-flow: CheckV1.ok"
  expect typed.analysisComplete "fn-flow: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"fn-flow: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"fn-flow: validate: {repr e}"
  -- Unified callable table: double, quadruple, init, bump, get in source order.
  let kinds := data.callables.map (·.kind)
  let names := data.callables.map (·.name)
  expect (data.callables.size == 5 &&
      kinds == #[.pureFn, .pureFn, .initializer, .entry, .view] &&
      names == #[some "double", some "quadruple", none, some "bump", some "get"])
    "fn-flow: callable table must keep fns in unified source order"
  -- double: pureFn with one UInt64 param and UInt64 result, single block.
  let some doubleC := data.callables[0]? |
    throw <| IO.userError "fn-flow: missing double callable"
  let some doubleParam := doubleC.params[0]? |
    throw <| IO.userError "fn-flow: missing double param"
  expect (doubleC.params.size == 1 && doubleC.result.typeId == doubleParam.typeId)
    "fn-flow: double must have one param and a matching result type"
  -- quadruple: two nested PureCall instructions targeting double (id 0).
  let some quadC := data.callables[1]? |
    throw <| IO.userError "fn-flow: missing quadruple callable"
  let some quadBlk := quadC.blocks[0]? |
    throw <| IO.userError "fn-flow: missing quadruple block"
  let callInstrs := quadBlk.instructions.filter fun instr =>
    match instr.op with | .pureCall .. => true | _ => false
  expect (callInstrs.size == 2)
    s!"fn-flow: quadruple must lower two nested pure calls, got {callInstrs.size}"
  let some firstCall := callInstrs[0]? |
    throw <| IO.userError "fn-flow: missing first pure call"
  match firstCall with
  | { result := some _, op := .pureCall calleeId args } =>
      expect (calleeId == 0 && args.size == 1 && args[0]? == some 0)
        "fn-flow: first pure call must target double with the fn param"
  | _ => throw <| IO.userError "fn-flow: first pure call shape mismatch"
  -- bump: PureCall ops target double (0) and quadruple (1).
  let some bumpC := data.callables[3]? |
    throw <| IO.userError "fn-flow: missing bump callable"
  let some bumpBlk := bumpC.blocks[0]? |
    throw <| IO.userError "fn-flow: missing bump block"
  let bumpCalls := bumpBlk.instructions.filterMap fun instr =>
    match instr.op with | .pureCall calleeId _ => some calleeId | _ => none
  expect (bumpCalls == #[0, 1])
    s!"fn-flow: bump must call double then quadruple, got {bumpCalls}"

/-- Fn with a declared revert: the revert effect is allowed inside fn and
    propagates through the calling entry. -/
private unsafe def testFnRevertPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FnRevert" <|
    "  error Cap(limit : UInt64)\n" ++
    "  fn check(x : UInt64, lim : UInt64) : UInt64 do\n" ++
    "    if x > lim then\n" ++
    "      revert Cap(lim)\n" ++
    "    else\n" ++
    "      return x\n" ++
    "  entry clamp(v : UInt64) : UInt64 do\n" ++
    "    return check(v, 10)\n"
  let validated ← loadSource session "fn-revert" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "fn-revert: CheckV1.ok (fn revert is the only allowed fn effect)"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"fn-revert: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"fn-revert: validate: {repr e}"
  let some checkC := data.callables[0]? |
    throw <| IO.userError "fn-revert: missing check callable"
  expect (checkC.kind == .pureFn && checkC.blocks.size == 3)
    s!"fn-revert: check must lower to cond/revert/else blocks, got {checkC.blocks.size}"
  let some revertBlk := checkC.blocks[1]? |
    throw <| IO.userError "fn-revert: missing revert block"
  match revertBlk.terminator with
  | .revert errorId args =>
      expect (errorId == 0 && args.size == 1)
        "fn-revert: revert must bind Cap with one arg"
  | _ => throw <| IO.userError "fn-revert: then block must terminate in revert"

/-- State reads inside fn violate the fn effect allowlist at CheckV1. -/
private unsafe def testFnStateReadTypedNotOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FnStateRead" <|
    "  state count : UInt64\n" ++
    "  fn sneak(x : UInt64) : UInt64 do\n" ++
    "    return count + x\n" ++
    "  entry run(v : UInt64) : UInt64 do\n" ++
    "    return sneak(v)\n"
  let validated ← loadSource session "fn-state-read" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok) "fn-state-read: CheckV1 must reject state.read in fn"
  match normalizeProgramV1 validated with
  | .ok _ => throw <| IO.userError "fn-state-read: normalize must not accept typed-not-ok"
  | .error (.typedNotOk _) => pure ()
  | .error e =>
      throw <| IO.userError s!"fn-state-read: expected .typedNotOk, got {repr e}"

/-- A two-fn local-call cycle is rejected by the call-graph check. -/
private unsafe def testFnCallCycleTypedNotOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FnCycle" <|
    "  fn ping(x : UInt64) : UInt64 do\n" ++
    "    return pong(x)\n" ++
    "  fn pong(x : UInt64) : UInt64 do\n" ++
    "    return ping(x)\n" ++
    "  entry run(v : UInt64) : UInt64 do\n" ++
    "    return ping(v)\n"
  let validated ← loadSource session "fn-cycle" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok) "fn-cycle: CheckV1 must reject the ping/pong call cycle"
  match normalizeProgramV1 validated with
  | .ok _ => throw <| IO.userError "fn-cycle: normalize must not accept typed-not-ok"
  | .error (.typedNotOk _) => pure ()
  | .error e =>
      throw <| IO.userError s!"fn-cycle: expected .typedNotOk, got {repr e}"

/-- Provenance for fn/localCall: fn callable/param entities and the localCall
    instruction/value entities binding the exact source nodes. -/
private unsafe def testFnLocalCallProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FnFlow" <|
    "  state count : UInt64\n" ++
    "  fn double(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := double(count)\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "fn-prov" source
  let path ← parseTestPath "fn-prov"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"fn-prov: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"fn-prov: normalize: {repr e}"
  match validateSemanticProgramV1 carrier with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"fn-prov: validate: {repr e}"
  -- Fn callable entity binds the FnDecl item node.
  let fnItemPath := childPathT #[] "Program" "items" 1
  let fnItemOrigin ← originAtExplicitPath validated inventory fnItemPath
  let some fnCallableOrigin := findOrigin provenance (.callable 0) |
    throw <| IO.userError "fn-prov: missing fn callable origin"
  expect (fnCallableOrigin == fnItemOrigin)
    "fn-prov: fn callable must bind the FnDecl item"
  -- The localCall instruction and result value bind the local-call expression.
  let entryItemPath := childPathT #[] "Program" "items" 3
  let bodyPath := directChildT entryItemPath "EntryDecl" "body"
  let assignStmtPath := childPathT bodyPath "Block" "statements" 0
  let callPath := directChildT assignStmtPath "Stmt.Assign" "value"
  let callOrigin ← originAtExplicitPath validated inventory callPath
  let some instrOrigin := findOrigin provenance (.instruction 2 0 1) |
    throw <| IO.userError "fn-prov: missing localCall instruction origin"
  let some valueOrigin := findOrigin provenance (.value 2 2) |
    throw <| IO.userError "fn-prov: missing localCall value origin"
  expect (instrOrigin == callOrigin && valueOrigin == callOrigin)
    "fn-prov: localCall instruction/value must bind the local-call expression"

/-- Mul/div/mod arithmetic: exact Op.Binary op sequence with source-order
    operand ValueIds; unary neg/bitNot/not with result types. -/
private unsafe def testMulDivModUnary
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ArithFlow" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry scale(factor : UInt64, divisor : UInt64) : UInt64 do\n" ++
    "    count := count * factor / divisor + count % divisor\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "arith-flow" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "arith-flow: CheckV1.ok"
  expect typed.analysisComplete "arith-flow: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"arith-flow: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"arith-flow: validate: {repr e}"
  let some entryC := data.callables[1]? |
    throw <| IO.userError "arith-flow: missing scale callable"
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "arith-flow: missing block0"
  -- v0=factor, v1=divisor, v2=load count, v3=mul, v4=div, v5=load count,
  -- v6=mod, v7=add, store, v8=load count, return v8.
  let expectedOps : Array ProofForgeV2.Semantic.WireV1.BinaryOpV1 := #[.mul, .div, .mod, .add]
  let mut found : Array ProofForgeV2.Semantic.WireV1.BinaryOpV1 := #[]
  for instr in blk0.instructions do
    match instr.op with
    | .binary op _ _ => found := found.push op
    | _ => pure ()
  expect (found == expectedOps)
    s!"arith-flow: expected mul/div/mod/add op sequence, got {found.size} ops"
  let some mulInstr := blk0.instructions[1]? |
    throw <| IO.userError "arith-flow: missing mul instruction"
  match mulInstr with
  | { result := some r, op := .binary .mul l rv } =>
      expect (l == 2 && rv == 0 && r.valueId == 3)
        s!"arith-flow: mul must bind load(factor), got l={l} r={rv}"
  | _ => throw <| IO.userError "arith-flow: mul shape mismatch"
  let some divInstr := blk0.instructions[2]? |
    throw <| IO.userError "arith-flow: missing div instruction"
  match divInstr with
  | { result := some r, op := .binary .div l rv } =>
      expect (l == 3 && rv == 1 && r.valueId == 4)
        "arith-flow: div must apply to the mul result and divisor"
  | _ => throw <| IO.userError "arith-flow: div shape mismatch"

/-- External call and workflow schedule lowering: void ops with the shared
    canonical EffectId sequence, verbatim qualified callees, and per-target
    capability-gated S2 requirements; single-component callees, Bool args,
    and fn/view effect violations fail at the right layer. -/
private unsafe def testCallScheduleLowering
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ExtFlow" <|
    "  state count : UInt64\n" ++
    "  event Ping(x : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Ping(count)\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  entry later(delta : UInt64) : UInt64 do\n" ++
    "    schedule Ledger.daily(count)\n" ++
    "    schedule Ledger.weekly(delta)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "ext-flow" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "ext-flow: CheckV1.ok"
  expect typed.analysisComplete "ext-flow: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"ext-flow: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"ext-flow: validate: {repr e}"
  expect (data.requirements.items.map (·.id) ==
      #["effect.asynchronous-workflow", "effect.event", "effect.synchronous-call",
        "failure.atomic-rollback", "state.persistent", "value.checked-arithmetic"])
    s!"ext-flow: wire-order requirements, got {data.requirements.items.map (·.id)}"
  let some bump := data.callables[1]? |
    throw <| IO.userError "ext-flow: missing bump callable"
  let some blk0 := bump.blocks[0]? |
    throw <| IO.userError "ext-flow: missing bump block0"
  -- emit (effectId 0) then call (effectId 1): one shared EffectId sequence.
  let some emitInstr := blk0.instructions[1]? |
    throw <| IO.userError "ext-flow: missing emit instruction"
  match emitInstr with
  | { result := none, op := .emit effectId eventId args } =>
      expect (effectId == 0 && eventId == 0 && args.size == 1)
        "ext-flow: emit must take effectId 0 in the shared sequence"
  | _ => throw <| IO.userError "ext-flow: emit shape mismatch"
  let some callInstr := blk0.instructions[3]? |
    throw <| IO.userError "ext-flow: missing call instruction"
  match callInstr with
  | { result := none, op := .externalCall effectId callee args } =>
      expect (effectId == 1 && args.size == 1 &&
          callee.components.toArray == #["Oracle", "feed"])
        "ext-flow: call must take effectId 1 with the verbatim qualified callee"
  | _ => throw <| IO.userError "ext-flow: call shape mismatch"
  let some later := data.callables[2]? |
    throw <| IO.userError "ext-flow: missing later callable"
  let some lat0 := later.blocks[0]? |
    throw <| IO.userError "ext-flow: missing later block0"
  let mut schedEffects : Array UInt32 := #[]
  for instr in lat0.instructions do
    match instr.op with
    | .schedule effectId _ _ => schedEffects := schedEffects.push effectId
    | _ => pure ()
  expect (schedEffects == #[0, 1])
    s!"ext-flow: schedules must number 0,1 per callable, got {schedEffects}"
  -- Single-component callees are rejected at the parser boundary (source
  -- qualified ids require at least two components; the normalizer's own
  -- ≥2 check is defensive for hand-built ASTs).
  let oneCompSource := wrap "OneComp" <|
    "  entry run(n : UInt64) : UInt64 do\n" ++
    "    call Oracle(n)\n" ++
    "    return n\n"
  match ← session.selectProgramV1 oneCompSource (testSourcePath "one-comp") moduleName none with
  | .ok _ => throw <| IO.userError "one-comp: single-component callee must fail at the loader"
  | .error _ => pure ()
  -- Bool call argument fails the UInt64 envelope at the normalizer.
  let boolArgSource := wrap "BoolArg" <|
    "  entry run(n : UInt64) : UInt64 do\n" ++
  "    call Oracle.feed(n > 0)\n" ++
    "    return n\n"
  let boolArg ← loadSource session "bool-arg" boolArgSource
  expect (checkProgramTypedResultV1 boolArg).ok "bool-arg: CheckV1.ok"
  match normalizeProgramV1 boolArg with
  | .ok _ => throw <| IO.userError "bool-arg: Bool argument must fail"
  | .error _ => pure ()
  -- fn with a call: PF-EFFECT-001 typedNotOk (fn allows only failure.revert).
  let fnCallSource := wrap "FnCall" <|
    "  fn helper(n : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(n)\n" ++
    "    return n\n" ++
    "  entry run(n : UInt64) : UInt64 do\n" ++
    "    return helper(n)\n"
  let fnCall ← loadSource session "fn-call" fnCallSource
  match normalizeProgramV1 fnCall with
  | .error (.typedNotOk _) => pure ()
  | .ok _ => throw <| IO.userError "fn-call: fn with call must be typedNotOk"
  | .error e => throw <| IO.userError s!"fn-call: expected typedNotOk, got {repr e}"

/-- Provenance for call/schedule: every frozen S2 requirement id must have
    producing origin sites (effect.synchronous-call at the call statement,
    effect.asynchronous-workflow at the schedule statement), and the void
    instruction/effect entities bind those exact statement nodes. -/
private unsafe def testCallScheduleProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ExtProv" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Peer.go(count)\n" ++
    "    schedule ledger.daily(delta)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "ext-prov" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "ext-prov: CheckV1.ok"
  expect typed.analysisComplete "ext-prov: CheckV1.analysisComplete"
  let path ← parseTestPath "ext-prov"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"ext-prov: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error (.unsupported d) =>
        throw <| IO.userError s!"ext-prov: normalize+provenance unsupported: {d}"
    | .error e => throw <| IO.userError s!"ext-prov: normalize+provenance: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"ext-prov: validate: {repr e}"
  expect (data.requirements.items.map (·.id) ==
      #["effect.asynchronous-workflow", "effect.synchronous-call",
        "failure.atomic-rollback", "state.persistent"])
    s!"ext-prov: wire-order requirements, got {data.requirements.items.map (·.id)}"
  -- Statement paths: items 0=state, 1=init, 2=entry bump, 3=view.
  let entryItemPath := childPathT #[] "Program" "items" 2
  let bodyPath := directChildT entryItemPath "EntryDecl" "body"
  let callStmtPath := childPathT bodyPath "Block" "statements" 0
  let schedStmtPath := childPathT bodyPath "Block" "statements" 1
  let callOrigin ← originAtExplicitPath validated inventory callStmtPath
  let schedOrigin ← originAtExplicitPath validated inventory schedStmtPath
  -- Requirement sites (wire order): 0=async, 1=sync, 2=rollback, 3=persist.
  -- RequirementsInferV1: call → sync+rollback; schedule → async only.
  let reqAsync := findOrigins provenance (.requirement 0)
  let reqSync := findOrigins provenance (.requirement 1)
  let reqRollback := findOrigins provenance (.requirement 2)
  expect (reqAsync == #[schedOrigin])
    "ext-prov: effect.asynchronous-workflow must bind the schedule statement"
  expect (reqSync == #[callOrigin])
    "ext-prov: effect.synchronous-call must bind the call statement"
  expect (reqRollback == #[callOrigin])
    "ext-prov: failure.atomic-rollback must bind the call statement"
  -- Entity attribution: bump is callable 1; block0 is
  -- stateLoad(count) → externalCall → schedule → stateLoad(count for return).
  let some callInstrOrigin := findOrigin provenance (.instruction 1 0 1) |
    throw <| IO.userError "ext-prov: missing call instruction origin"
  let some callEffectOrigin := findOrigin provenance (.effect 1 0) |
    throw <| IO.userError "ext-prov: missing call effect origin"
  expect (callInstrOrigin == callOrigin && callEffectOrigin == callOrigin)
    "ext-prov: call instruction/effect entities must bind the call statement"
  let some schedInstrOrigin := findOrigin provenance (.instruction 1 0 2) |
    throw <| IO.userError "ext-prov: missing schedule instruction origin"
  let some schedEffectOrigin := findOrigin provenance (.effect 1 1) |
    throw <| IO.userError "ext-prov: missing schedule effect origin"
  expect (schedInstrOrigin == schedOrigin && schedEffectOrigin == schedOrigin)
    "ext-prov: schedule instruction/effect entities must bind the schedule statement"
  match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier provenance with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ext-prov: provenance authority: {repr e}"

/-- Shift, bitwise, and strict logical binary operators: exact op/type pins
    (UInt32 shift counts intern on first use), plus typed-not-ok negatives
    for non-Bool logical operands and UInt64 shift counts. -/
private unsafe def testShiftBitwiseLogical
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BitLogic" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry shiftMask(x : UInt64) : UInt64 do\n" ++
    "    count := (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "    return count\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > 0 && b > 0\n" ++
    "  entry strictOr(a : UInt64, b : UInt64) : Bool do\n" ++
    "    let one : UInt64 := 1\n" ++
    "    return a > 0 || (one / b) == one\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "bit-logic" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "bit-logic: CheckV1.ok"
  expect typed.analysisComplete "bit-logic: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"bit-logic: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"bit-logic: validate: {repr e}"
  -- Exactly one anonymous UInt32 type (interned on the first shift count).
  let u32Decls := data.types.filter fun t =>
    t.name.isNone && match t.shape with | .uint 32 => true | _ => false
  expect (u32Decls.size == 1)
    s!"bit-logic: shift counts must intern exactly one anonymous UInt32 type, got {u32Decls.size}"
  let some shiftMask := data.callables[1]? |
    throw <| IO.userError "bit-logic: missing shiftMask callable"
  let some blk0 := shiftMask.blocks[0]? |
    throw <| IO.userError "bit-logic: missing shiftMask block0"
  let u64Decls := data.types.filter fun t =>
    t.name.isNone && match t.shape with | .uint 64 => true | _ => false
  expect (u64Decls.size == 1) "bit-logic: exactly one anonymous UInt64 type"
  let some u64Decl := u64Decls[0]? |
    throw <| IO.userError "bit-logic: missing anonymous UInt64 decl"
  let u64Tid := u64Decl.id
  let some u32Decl := u32Decls[0]? |
    throw <| IO.userError "bit-logic: missing anonymous UInt32 decl"
  let u32Tid := u32Decl.id
  let expectedOps : Array ProofForgeV2.Semantic.WireV1.BinaryOpV1 :=
    #[.shl, .bitAnd, .shr, .bitXor, .bitOr]
  let mut found : Array ProofForgeV2.Semantic.WireV1.BinaryOpV1 := #[]
  for instr in blk0.instructions do
    match instr.op with
    | .binary op _ _ => found := found.push op
    | _ => pure ()
  expect (found == expectedOps)
    s!"bit-logic: expected shl/bitAnd/shr/bitXor/bitOr op sequence, got {found.size} ops"
  let some shlInstr := blk0.instructions[1]? |
    throw <| IO.userError "bit-logic: missing shl instruction"
  match shlInstr with
  | { result := some r, op := .binary .shl l rv } =>
      expect (l == 0 && rv == 1 && r.valueId == 2 && r.typeId == u64Tid)
        "bit-logic: shl must bind x with a UInt64 result"
  | _ => throw <| IO.userError "bit-logic: shl shape mismatch"
  let some litInstr := blk0.instructions[0]? |
    throw <| IO.userError "bit-logic: missing shift-count literal"
  match litInstr with
  | { result := some r, op := .literal tid bytes } =>
      expect (tid == u32Tid && r.typeId == u32Tid && bytes.size == 4)
        "bit-logic: shift count must be a 4-byte UInt32 literal"
  | _ => throw <| IO.userError "bit-logic: shift-count literal shape mismatch"
  let some strictOr := data.callables[3]? |
    throw <| IO.userError "bit-logic: missing strictOr callable"
  let some orBlk := strictOr.blocks[0]? |
    throw <| IO.userError "bit-logic: missing strictOr block0"
  let mut foundOr : Array ProofForgeV2.Semantic.WireV1.BinaryOpV1 := #[]
  for instr in orBlk.instructions do
    match instr.op with
    | .binary op _ _ => foundOr := foundOr.push op
    | _ => pure ()
  expect (foundOr == #[.gt, .div, .eq, .or])
    s!"bit-logic: strictOr must evaluate both sides (gt/div/eq/or), got {foundOr.size} ops"
  -- Logical operator on non-Bool operands: CheckV1 rejects.
  let badLogicalSource := wrap "BadLogical" <|
    "  entry bad(a : UInt64) : Bool do\n" ++
    "    return a && a > 0\n"
  let badLogical ← loadSource session "bad-logical" badLogicalSource
  expect (!(checkProgramTypedResultV1 badLogical).ok)
    "bad-logical: CheckV1 must reject a UInt64 logical operand"
  -- UInt64 shift count: CheckV1 rejects (counts are UInt32).
  let badShiftSource := wrap "BadShift" <|
    "  entry bad(x : UInt64, k : UInt64) : UInt64 do\n" ++
    "    return x << k\n"
  let badShift ← loadSource session "bad-shift" badShiftSource
  expect (!(checkProgramTypedResultV1 badShift).ok)
    "bad-shift: CheckV1 must reject a UInt64 shift count"

/-- Immutable let bindings and bounded for loops: exact multi-block CFG with
    a single-param loop header, latch back edge, and canonical loopBounds;
    let single-evaluation; reassignment and oversized bounds fail closed. -/
private unsafe def testLetForLoop
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "LoopSum" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry addUp(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n + 4\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry scan(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 2 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n" ++
    "  entry addUpTight(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n + 4 bounded 3 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry never(n : UInt64) : UInt64 do\n" ++
    "    let one : UInt64 := 1\n" ++
    "    for i in one ..< n bounded 0 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry square(dummy : UInt64) : UInt64 do\n" ++
    "    let x : UInt64 := count + 1\n" ++
    "    count := x * x\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "loop-sum" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "loop-sum: CheckV1.ok"
  expect typed.analysisComplete "loop-sum: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"loop-sum: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"loop-sum: validate: {repr e}"
  expect (data.callables.size == 7) "loop-sum: init + five entries + get"
  let some addUp := data.callables[1]? |
    throw <| IO.userError "loop-sum: missing addUp callable"
  expect (addUp.blocks.size == 4)
    s!"loop-sum: addUp must lower to pre/header/body/exit blocks, got {addUp.blocks.size}"
  -- Canonical ValueIds: param n=v0; block-param range [1]; instruction
  -- results v2.. above it (forCount=1).
  let some blk0 := addUp.blocks[0]? |
    throw <| IO.userError "loop-sum: missing pre-header"
  expect (blk0.params.isEmpty) "loop-sum: pre-header has no params"
  let some litInstr := blk0.instructions[0]? |
    throw <| IO.userError "loop-sum: missing literal 4"
  match litInstr with
  | { result := some r, op := .literal _ _ } =>
      expect (r.valueId == 2) "loop-sum: literal 4 must be v2"
  | _ => throw <| IO.userError "loop-sum: literal shape mismatch"
  let some addInstr := blk0.instructions[1]? |
    throw <| IO.userError "loop-sum: missing limit add"
  match addInstr with
  | { result := some r, op := .binary .add l rv } =>
      expect (l == 0 && rv == 2 && r.valueId == 3)
        "loop-sum: limit must be n + 4"
  | _ => throw <| IO.userError "loop-sum: limit add shape mismatch"
  match blk0.terminator with
  | .jump target =>
      expect (target.blockId == 1 && target.args == #[0])
        "loop-sum: pre-header must jump to the header with the start value"
  | _ => throw <| IO.userError "loop-sum: pre-header must jump"
  let some header := addUp.blocks[1]? |
    throw <| IO.userError "loop-sum: missing header"
  let some headerParam := header.params[0]? |
    throw <| IO.userError "loop-sum: missing header param"
  expect (header.params.size == 1 && headerParam.valueId == 1)
    "loop-sum: header must carry exactly the induction param v1"
  let some condInstr := header.instructions[0]? |
    throw <| IO.userError "loop-sum: missing loop condition"
  match condInstr with
  | { result := some r, op := .binary .lt l rv } =>
      expect (l == 1 && rv == 3 && r.valueId == 4)
        "loop-sum: condition must be i < limit"
  | _ => throw <| IO.userError "loop-sum: condition shape mismatch"
  match header.terminator with
  | .branch cond thenT elseT =>
      expect (cond == 4 && thenT.blockId == 2 && elseT.blockId == 3)
        "loop-sum: header must branch to body/exit"
  | _ => throw <| IO.userError "loop-sum: header must branch"
  let some body := addUp.blocks[2]? |
    throw <| IO.userError "loop-sum: missing body"
  let some bodyAdd := body.instructions[1]? |
    throw <| IO.userError "loop-sum: missing body add"
  match bodyAdd with
  | { result := some r, op := .binary .add l rv } =>
      expect (l == 5 && rv == 1 && r.valueId == 6)
        "loop-sum: body must add the induction param"
  | _ => throw <| IO.userError "loop-sum: body add shape mismatch"
  let some incInstr := body.instructions[4]? |
    throw <| IO.userError "loop-sum: missing increment"
  match incInstr with
  | { result := some r, op := .binary .add l rv } =>
      expect (l == 1 && rv == 7 && r.valueId == 8)
        "loop-sum: latch must increment the induction param"
  | _ => throw <| IO.userError "loop-sum: increment shape mismatch"
  match body.terminator with
  | .jump target =>
      expect (target.blockId == 1 && target.args == #[8])
        "loop-sum: latch must jump back with the incremented value"
  | _ => throw <| IO.userError "loop-sum: latch must jump back"
  expect (addUp.loopBounds == #[{ header := 1, backEdgeFrom := 2, maxIterations := 8 }])
    "loop-sum: loopBounds must record exactly the (header, latch, 8) back edge"
  -- square: let single-evaluation (mul reuses the add result on both sides).
  let some square := data.callables[5]? |
    throw <| IO.userError "loop-sum: missing square callable"
  let some sqBlk := square.blocks[0]? |
    throw <| IO.userError "loop-sum: missing square block"
  let some mulInstr := sqBlk.instructions[3]? |
    throw <| IO.userError "loop-sum: missing square mul"
  match mulInstr with
  | { result := some r, op := .binary .mul l rv } =>
      expect (l == 3 && rv == 3 && r.valueId == 4)
        "loop-sum: let must evaluate `count + 1` once and reuse the value"
  | _ => throw <| IO.userError "loop-sum: square mul shape mismatch"
  -- Reassignment of a let-local fails closed at the assign arm.
  let reassignSource := wrap "ReassignLocal" <|
    "  entry bad(n : UInt64) : UInt64 do\n" ++
    "    let x : UInt64 := n\n" ++
    "    x := 5\n" ++
    "    return x\n"
  let reassign ← loadSource session "reassign-local" reassignSource
  expect (checkProgramTypedResultV1 reassign).ok "reassign-local: CheckV1.ok"
  match normalizeProgramV1 reassign with
  | .ok _ => throw <| IO.userError "reassign-local: must fail closed"
  | .error _ => pure ()
  -- The parser caps the bound at the wire maximum (4096): 4097 is rejected
  -- at the loader and never reaches the normalizer; 4096 lowers cleanly.
  let bigBoundSource := wrap "BigBound" <|
    "  state count : UInt64\n" ++
    "  entry bad(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 4097 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n"
  match ← session.selectProgramV1 bigBoundSource (testSourcePath "big-bound") moduleName none with
  | .ok _ => throw <| IO.userError "big-bound: bound 4097 must fail at the loader"
  | .error _ => pure ()
  let maxBoundSource := wrap "MaxBound" <|
    "  state count : UInt64\n" ++
    "  entry ok(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 4096 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n"
  let maxBound ← loadSource session "max-bound" maxBoundSource
  expect (checkProgramTypedResultV1 maxBound).ok "max-bound: CheckV1.ok"
  let maxCarrier ← match normalizeProgramV1 maxBound with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"max-bound: normalize: {repr e}"
  match validateSemanticProgramV1 maxCarrier with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"max-bound: validate: {repr e}"

/-- Loop/let provenance: header param, synthesized condition/latch entities,
    and block entities bind the exact for/body/let statement nodes; the
    retro-fixed mul binary arm and the two-instruction checked-negation
    desugar are covered through the sole provenance rebuild. -/
private unsafe def testLetForProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ProvLoop" <|
    "  state count : UInt64\n" ++
    "  entry addUp(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n * 2\n" ++
    "    for i in n ..< limit bounded 4 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry neg(x : UInt64) : UInt64 do\n" ++
    "    return -x\n"
  let (validated, spans) ← loadSourceWithSpans session "prov-loop" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "prov-loop: CheckV1.ok"
  expect typed.analysisComplete "prov-loop: CheckV1.analysisComplete"
  let path ← parseTestPath "prov-loop"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"prov-loop: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"prov-loop: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"prov-loop: validate: {repr e}"
  expect (data.callables.size == 2) "prov-loop: addUp + neg"
  -- addUp: let (stmt 0), for (stmt 1), return (stmt 2).
  let itemPath := childPathT #[] "Program" "items" 1
  let bodyPath := directChildT itemPath "EntryDecl" "body"
  let letStmtPath := childPathT bodyPath "Block" "statements" 0
  let letValuePath := directChildT letStmtPath "Stmt.Let" "value"
  let forStmtPath := childPathT bodyPath "Block" "statements" 1
  let forBodyPath := directChildT forStmtPath "Stmt.For" "body"
  let forOrigin ← originAtExplicitPath validated inventory forStmtPath
  let forBodyOrigin ← originAtExplicitPath validated inventory forBodyPath
  -- mul retro-fix: the let value binary instruction/result bind the `n * 2`
  -- expression node (previously the binary arm rejected mul/div/mod).
  let letValueOrigin ← originAtExplicitPath validated inventory letValuePath
  let some mulInstrOrigin := findOrigin provenance (.instruction 0 0 1) |
    throw <| IO.userError "prov-loop: missing mul instruction origin"
  let some mulValueOrigin := findOrigin provenance (.value 0 3) |
    throw <| IO.userError "prov-loop: missing mul value origin"
  expect (mulInstrOrigin == letValueOrigin && mulValueOrigin == letValueOrigin)
    "prov-loop: mul instruction/value must bind the let value expression"
  -- Loop structure: header block, induction param, condition, and latch all
  -- bind the for statement; the body block binds the for body.
  let some headerOrigin := findOrigin provenance (.block 0 1) |
    throw <| IO.userError "prov-loop: missing header block origin"
  let some paramOrigin := findOrigin provenance (.value 0 1) |
    throw <| IO.userError "prov-loop: missing induction param origin"
  let some condOrigin := findOrigin provenance (.instruction 0 1 0) |
    throw <| IO.userError "prov-loop: missing condition origin"
  let some bodyBlockOrigin := findOrigin provenance (.block 0 2) |
    throw <| IO.userError "prov-loop: missing body block origin"
  let some latchLitOrigin := findOrigin provenance (.instruction 0 2 3) |
    throw <| IO.userError "prov-loop: missing latch literal origin"
  let some latchIncOrigin := findOrigin provenance (.instruction 0 2 4) |
    throw <| IO.userError "prov-loop: missing latch increment origin"
  let some exitOrigin := findOrigin provenance (.block 0 3) |
    throw <| IO.userError "prov-loop: missing exit block origin"
  expect (headerOrigin == forOrigin && paramOrigin == forOrigin &&
      condOrigin == forOrigin && latchLitOrigin == forOrigin &&
      latchIncOrigin == forOrigin && exitOrigin == forOrigin)
    "prov-loop: synthesized loop entities must bind the for statement"
  expect (bodyBlockOrigin == forBodyOrigin)
    "prov-loop: body block must bind the for body"
  -- Checked-negation retro-fix: the desugared `0 - x` produces two
  -- instruction/value entity pairs, all binding the unary expression node.
  let negItemPath := childPathT #[] "Program" "items" 2
  let negBodyPath := directChildT negItemPath "EntryDecl" "body"
  let negStmtPath := childPathT negBodyPath "Block" "statements" 0
  let unaryPath := directChildT negStmtPath "Stmt.Return" "value"
  let unaryOrigin ← originAtExplicitPath validated inventory unaryPath
  let some zeroInstrOrigin := findOrigin provenance (.instruction 1 0 0) |
    throw <| IO.userError "prov-loop: missing zero literal origin"
  let some zeroValueOrigin := findOrigin provenance (.value 1 1) |
    throw <| IO.userError "prov-loop: missing zero value origin"
  let some subInstrOrigin := findOrigin provenance (.instruction 1 0 1) |
    throw <| IO.userError "prov-loop: missing sub instruction origin"
  let some subValueOrigin := findOrigin provenance (.value 1 2) |
    throw <| IO.userError "prov-loop: missing sub value origin"
  expect (zeroInstrOrigin == unaryOrigin && zeroValueOrigin == unaryOrigin &&
      subInstrOrigin == unaryOrigin && subValueOrigin == unaryOrigin)
    "prov-loop: desugared negation entities must bind the unary expression"

/-- Unary neg/bitNot/not: op kinds and result types; `!` feeding a branch. -/
private unsafe def testUnaryOps
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "UnaryFlow" <|
    "  entry ops(x : UInt64) : UInt64 do\n" ++
    "    if !(x > 5) then\n" ++
    "      return ~x + -0\n" ++
    "    else\n" ++
    "      return 0\n"
  let validated ← loadSource session "unary-flow" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "unary-flow: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"unary-flow: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"unary-flow: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "unary-flow: missing ops callable"
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "unary-flow: missing cond block"
  -- block0: literal 5(v1), gt(x,v1)(v2 bool), not(v2)(v3 bool), branch v3.
  let some notInstr := blk0.instructions[2]? |
    throw <| IO.userError "unary-flow: missing not instruction"
  match notInstr with
  | { result := some r, op := .unary .not o } =>
      expect (o == 2 && r.valueId == 3)
        "unary-flow: not must negate the gt comparison"
  | _ => throw <| IO.userError "unary-flow: not shape mismatch"
  match blk0.terminator with
  | .branch cond _ _ =>
      expect (cond == 3) "unary-flow: branch must use the not result"
  | _ => throw <| IO.userError "unary-flow: cond block must branch"
  let some thenBlk := entryC.blocks[1]? |
    throw <| IO.userError "unary-flow: missing then block"
  -- then: bitNot(x)(v4), literal 0(v5), literal 0(v6), sub(v6,v5)(v7),
  -- add(v4,v7)(v8), return v8. Checked negation desugars to `0 - x`.
  let some bitNotInstr := thenBlk.instructions[0]? |
    throw <| IO.userError "unary-flow: missing bitNot instruction"
  match bitNotInstr with
  | { result := some r, op := .unary .bitNot o } =>
      expect (o == 0 && r.valueId == 4)
        "unary-flow: bitNot must apply to the param"
  | _ => throw <| IO.userError "unary-flow: bitNot shape mismatch"
  let some subInstr := thenBlk.instructions[3]? |
    throw <| IO.userError "unary-flow: missing desugared sub instruction"
  match subInstr with
  | { result := some r, op := .binary .sub l rv } =>
      expect (l == 6 && rv == 5 && r.valueId == 7)
        "unary-flow: checked negation must desugar to `0 - x`"
  | _ => throw <| IO.userError "unary-flow: desugared sub shape mismatch"

/-- Literal instruction and result value both bind the source literal expression
    node, not the enclosing return statement or an arbitrary nearby origin. -/
private unsafe def testUInt64LiteralProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "LitProv" <|
    "  entry run() : UInt64 do\n" ++
    "    return 72623859790382856\n"
  let (validated, spans) ← loadSourceWithSpans session "lit-prov" source
  let path ← parseTestPath "lit-prov"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"lit-prov: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"lit-prov: normalize: {repr e}"
  match validateSemanticProgramV1 carrier with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"lit-prov: validate: {repr e}"
  let itemPath := childPathT #[] "Program" "items" 0
  let bodyPath := directChildT itemPath "EntryDecl" "body"
  let stmtPath := childPathT bodyPath "Block" "statements" 0
  let literalPath := directChildT stmtPath "Stmt.Return" "value"
  let literalOrigin ← originAtExplicitPath validated inventory literalPath
  let some instrOrigin := findOrigin provenance (.instruction 0 0 0) |
    throw <| IO.userError "lit-prov: missing instruction origin"
  let some valueOrigin := findOrigin provenance (.value 0 0) |
    throw <| IO.userError "lit-prov: missing value origin"
  expect (instrOrigin == literalOrigin && valueOrigin == literalOrigin)
    "lit-prov: instruction/value origins must equal literal expression origin"

/-- Subtraction instruction/result and both checked-arithmetic requirements bind
    the exact binary expression node through the sole provenance rebuild. -/
private unsafe def testUInt64SubtractionProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "SubProv" <|
    "  entry run(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    return x - y\n"
  let (validated, spans) ← loadSourceWithSpans session "sub-prov" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "sub-prov: CheckV1.ok"
  expect typed.analysisComplete "sub-prov: CheckV1.analysisComplete"
  let path ← parseTestPath "sub-prov"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"sub-prov: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"sub-prov: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"sub-prov: validate: {repr e}"
  expect (data.requirements.items.map (·.id) ==
      #["failure.atomic-rollback", "value.checked-arithmetic"])
    "sub-prov: exact checked-arithmetic requirement order"
  let itemPath := childPathT #[] "Program" "items" 0
  let bodyPath := directChildT itemPath "EntryDecl" "body"
  let stmtPath := childPathT bodyPath "Block" "statements" 0
  let binaryPath := directChildT stmtPath "Stmt.Return" "value"
  let binaryOrigin ← originAtExplicitPath validated inventory binaryPath
  let some instrOrigin := findOrigin provenance (.instruction 0 0 0) |
    throw <| IO.userError "sub-prov: missing instruction origin"
  let some valueOrigin := findOrigin provenance (.value 0 2) |
    throw <| IO.userError "sub-prov: missing result value origin"
  let some rollbackOrigin := findOrigin provenance (.requirement 0) |
    throw <| IO.userError "sub-prov: missing rollback requirement origin"
  let some arithmeticOrigin := findOrigin provenance (.requirement 1) |
    throw <| IO.userError "sub-prov: missing arithmetic requirement origin"
  expect (instrOrigin == binaryOrigin && valueOrigin == binaryOrigin &&
      rollbackOrigin == binaryOrigin && arithmeticOrigin == binaryOrigin)
    "sub-prov: instruction/value/requirements must bind the subtraction expression"
  match ProofForgeV2.Semantic.NormalizeV1.validateSemanticProvenanceV1
      validated path spans carrier provenance with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"sub-prov: authority: {repr e}"

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
  -- Bool result contributes catalog value.bool and now freezes.
  let boolSrc := wrap "FreezeBool" <|
    "  entry run() : Bool do\n" ++
    "    return true\n"
  let boolProg ← loadSource session "freeze-bool" boolSrc
  match freezeProgramRequirementsV1 boolProg.program with
  | .ok frozen =>
      expect (frozen.items.map (·.id) == #["value.bool"])
        s!"freeze-bool: expected catalog value.bool freeze, got {frozen.items.map (·.id)}"
  | .error detail =>
      throw <| IO.userError s!"freeze-bool: expected catalog freeze, got {detail}"
  -- emit contributes catalog effect.event and now freezes.
  let emitSrc := wrap "FreezeEmit" <|
    "  event Tick()\n" ++
    "  entry run() : Unit do\n" ++
    "    emit Tick()\n" ++
    "    return\n"
  let emitProg ← loadSource session "freeze-emit" emitSrc
  match freezeProgramRequirementsV1 emitProg.program with
  | .ok frozen =>
      expect (frozen.items.map (·.id) == #["effect.event"])
        s!"freeze-emit: expected catalog effect.event freeze, got {frozen.items.map (·.id)}"
  | .error detail =>
      throw <| IO.userError s!"freeze-emit: expected catalog freeze, got {detail}"
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

/-- Local LE encoder for multi-width valueBytes pins (matches Wire UInt/Int layout). -/
private def encodeNatLeBytes (n : Nat) (byteLen : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity byteLen
  let mut v := n
  for _ in [:byteLen] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def findAnonUintTid (types : Array TypeDeclV1) (width : Nat) : Option TypeIdV1 :=
  match types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .uint w => w.toNat == width | _ => false with
  | some i => some (UInt32.ofNat i)
  | none => none

private def findAnonIntTid (types : Array TypeDeclV1) (width : Nat) : Option TypeIdV1 :=
  match types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .int w => w.toNat == width | _ => false with
  | some i => some (UInt32.ofNat i)
  | none => none

/-- T1 multi-width: anonymous UInt{8,16,32,128,256} state + init/entry/view with
    exact LE literal bytes, same-width arith, and comparison → Bool. -/
private unsafe def testMultiWidthUIntState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × Nat × Nat × ByteArray) := #[
    ("UInt8", 8, 41, encodeNatLeBytes 41 1),
    ("UInt16", 16, 0x0201, encodeNatLeBytes 0x0201 2),
    ("UInt32", 32, 0x04030201, encodeNatLeBytes 0x04030201 4),
    ("UInt128", 128, 0x0102, encodeNatLeBytes 0x0102 16),
    ("UInt256", 256, 0xabcd, encodeNatLeBytes 0xabcd 32)
  ]
  for (tyName, width, lit, expectedBytes) in cases do
    let label := s!"mw-uint-{width}"
    let source := wrap s!"MwUint{width}" <|
      s!"  state count : {tyName}\n" ++
      s!"  init(initial : {tyName}) do\n" ++
      "    count := initial\n" ++
      s!"  entry increment(delta : {tyName}) : {tyName} do\n" ++
      "    count := count + delta\n" ++
      "    return count\n" ++
      s!"  view get() : {tyName} do\n" ++
      "    return count\n" ++
      s!"  entry seed() : {tyName} do\n" ++
      s!"    count := {lit}\n" ++
      "    return count\n" ++
      s!"  entry cmp(x : {tyName}) : Bool do\n" ++
      "    return x < 10\n"
    let validated ← loadSource session label source
    let typed := checkProgramTypedResultV1 validated
    expect typed.ok s!"{label}: CheckV1.ok"
    expect typed.analysisComplete s!"{label}: analysisComplete"
    let carrier ← match normalizeProgramV1 validated with
      | .ok c => pure c
      | .error e => throw <| IO.userError s!"{label}: normalize: {repr e}"
    let data ← match validateSemanticProgramV1 carrier with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"{label}: validate: {repr e}"
    let some tid := findAnonUintTid data.types width |
      throw <| IO.userError s!"{label}: missing anonymous UInt{width}"
    let some st0 := data.logicalState[0]? |
      throw <| IO.userError s!"{label}: missing state"
    expect (st0.typeId == tid) s!"{label}: state TypeId must be UInt{width}"
    -- seed entry: literal then store then load then return
    let some seedC := data.callables.find? (fun c => c.name == some "seed") |
      throw <| IO.userError s!"{label}: missing seed entry"
    let some seedBlk := seedC.blocks[0]? |
      throw <| IO.userError s!"{label}: missing seed block"
    let some litInstr := seedBlk.instructions[0]? |
      throw <| IO.userError s!"{label}: missing seed literal"
    match litInstr.op with
    | .literal litTid bytes =>
        expect (litTid == tid && bytes == expectedBytes)
          s!"{label}: exact UInt{width} LE bytes size={bytes.size}"
    | _ => throw <| IO.userError s!"{label}: seed expected Op.Literal"
    -- comparison entry must produce Bool from same-width operands
    let some cmpC := data.callables.find? (fun c => c.name == some "cmp") |
      throw <| IO.userError s!"{label}: missing cmp entry"
    let some cmpBlk := cmpC.blocks[0]? |
      throw <| IO.userError s!"{label}: missing cmp block"
    expect (cmpBlk.instructions.any fun instr =>
        match instr.op with | .binary .lt _ _ => true | _ => false)
      s!"{label}: cmp must lower binary lt"
    let some incC := data.callables.find? (fun c => c.name == some "increment") |
      throw <| IO.userError s!"{label}: missing increment"
    let some incBlk := incC.blocks[0]? |
      throw <| IO.userError s!"{label}: missing increment block"
    expect (incBlk.instructions.any fun instr =>
        match instr.op with
        | .binary .add _ _ =>
            match instr.result with
            | some r => r.typeId == tid
            | none => false
        | _ => false)
      s!"{label}: add result TypeId must be UInt{width}"

/-- T1 multi-width: positive Int{8..256} entry/view result + exact LE bits. -/
private unsafe def testMultiWidthIntResults
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × Nat × Nat × ByteArray) := #[
    ("Int8", 8, 127, encodeNatLeBytes 127 1),
    ("Int16", 16, 300, encodeNatLeBytes 300 2),
    ("Int32", 32, 1000, encodeNatLeBytes 1000 4),
    ("Int64", 64, 42, encodeNatLeBytes 42 8),
    ("Int128", 128, 7, encodeNatLeBytes 7 16),
    ("Int256", 256, 9, encodeNatLeBytes 9 32)
  ]
  for (tyName, width, lit, expectedBytes) in cases do
    let label := s!"mw-int-{width}"
    let source := wrap s!"MwInt{width}" <|
      s!"  entry run() : {tyName} do\n" ++
      s!"    return {lit}\n" ++
      s!"  view peek() : {tyName} do\n" ++
      s!"    return {lit}\n"
    let validated ← loadSource session label source
    let typed := checkProgramTypedResultV1 validated
    expect typed.ok s!"{label}: CheckV1.ok"
    let carrier ← match normalizeProgramV1 validated with
      | .ok c => pure c
      | .error e => throw <| IO.userError s!"{label}: normalize: {repr e}"
    let data ← match validateSemanticProgramV1 carrier with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"{label}: validate: {repr e}"
    let some tid := findAnonIntTid data.types width |
      throw <| IO.userError s!"{label}: missing anonymous Int{width}"
    let some entryC := data.callables[0]? |
      throw <| IO.userError s!"{label}: missing entry"
    expect (entryC.result.typeId == tid) s!"{label}: entry result Int{width}"
    let some blk := entryC.blocks[0]? |
      throw <| IO.userError s!"{label}: missing block"
    let some instr := blk.instructions[0]? |
      throw <| IO.userError s!"{label}: missing literal"
    match instr.op with
    | .literal litTid bytes =>
        expect (litTid == tid && bytes == expectedBytes)
          s!"{label}: exact Int{width} positive LE bits"
    | _ => throw <| IO.userError s!"{label}: expected Op.Literal"
    -- Int unary neg remains fail-closed (Op.Unary.neg deferred; no Int params in this slice)
    let negSrc := wrap s!"MwIntNeg{width}" <|
      s!"  entry run() : {tyName} do\n" ++
      "    return -1\n"
    let negValidated ← loadSource session s!"{label}-neg" negSrc
    let negTyped := checkProgramTypedResultV1 negValidated
    expect negTyped.ok s!"{label}-neg: CheckV1 accepts Int unary-neg literal"
    match normalizeProgramV1 negValidated with
    | .ok _ => throw <| IO.userError s!"{label}-neg: must fail closed (no Op.Unary.neg yet)"
    | .error (.unsupported detail) =>
        expect (detail.contains "neg" || detail.contains "Int" || detail.contains "negation")
          s!"{label}-neg: expected neg/Int detail, got {detail}"
    | .error e =>
        throw <| IO.userError s!"{label}-neg: expected unsupported, got {repr e}"

/-- T1 multi-width match scrutinee on UInt8 with exact case valueBytes. -/
private unsafe def testMultiWidthMatchScrut
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MwMatchU8" <|
    "  state count : UInt8\n" ++
    "  entry apply(delta : UInt8) : UInt8 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n"
  let validated ← loadSource session "mw-match-u8" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "mw-match-u8: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"mw-match-u8: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"mw-match-u8: validate: {repr e}"
  let some tid := findAnonUintTid data.types 8 |
    throw <| IO.userError "mw-match-u8: missing UInt8"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "mw-match-u8: missing entry"
  let some blk0 := entryC.blocks[0]? |
    throw <| IO.userError "mw-match-u8: missing scrut block"
  match blk0.terminator with
  | .switch _ cases (some _) =>
      expect (cases.size == 2) s!"mw-match-u8: 2 cases, got {cases.size}"
      let some c0 := cases[0]? |
        throw <| IO.userError "mw-match-u8: missing case0"
      expect (c0.typeId == tid && c0.valueBytes == encodeNatLeBytes 0 1)
        s!"mw-match-u8: case0 must be UInt8 0, size={c0.valueBytes.size}"
      let some c1 := cases[1]? |
        throw <| IO.userError "mw-match-u8: missing case1"
      expect (c1.typeId == tid && c1.valueBytes == encodeNatLeBytes 1 1)
        "mw-match-u8: case1 must be UInt8 1"
  | _ => throw <| IO.userError "mw-match-u8: expected switch"

/-- Mixed-width arithmetic is rejected by CheckV1 before Normalize. -/
private unsafe def testMixedWidthOperandsTypedNotOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MwMixed" <|
    "  entry run(a : UInt8, b : UInt64) : UInt64 do\n" ++
    "    return a + b\n"
  let validated ← loadSource session "mw-mixed" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok && typed.analysisComplete)
    "mw-mixed: CheckV1 must reject mixed-width add"
  match normalizeProgramV1 validated with
  | .error (.typedNotOk _) => pure ()
  | .error e => throw <| IO.userError s!"mw-mixed: expected typedNotOk, got {repr e}"
  | .ok _ => throw <| IO.userError "mw-mixed: must not normalize mixed-width"

/-- UInt32 shift count still shares the sole anonymous UInt32 TypeId with shift lhs. -/
private unsafe def testMultiWidthShiftUInt32Shared
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MwShiftU32" <|
    "  entry run(x : UInt32, n : UInt32) : UInt32 do\n" ++
    "    return x << n\n"
  let validated ← loadSource session "mw-shift-u32" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "mw-shift-u32: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"mw-shift-u32: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"mw-shift-u32 validate: {repr e}"
  let uint32Count := data.types.foldl (fun acc t =>
      acc + (if t.name.isNone && match t.shape with | .uint 32 => true | _ => false
             then 1 else 0)) 0
  expect (uint32Count == 1)
    s!"mw-shift-u32: sole anonymous UInt32, got {uint32Count}"

/-- UInt64 golden LE bytes remain byte-identical after multi-width expansion. -/
private unsafe def testUInt64LiteralBytesUnchanged
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "U64Compat" <|
    "  entry run() : UInt64 do\n" ++
    "    return 72623859790382856\n"
  let validated ← loadSource session "u64-compat" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"u64-compat: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"u64-compat validate: {repr e}"
  let some blk := data.callables[0]?.bind (·.blocks[0]?) |
    throw <| IO.userError "u64-compat: missing block"
  let some instr := blk.instructions[0]? |
    throw <| IO.userError "u64-compat: missing instr"
  let expectedBytes : ByteArray :=
    ByteArray.mk #[(0x08 : UInt8), 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
  match instr.op with
  | .literal _ bytes =>
      expect (bytes == expectedBytes) "u64-compat: golden LE bytes unchanged"
  | _ => throw <| IO.userError "u64-compat: expected literal"

/-- T2: named Struct/Enum register as contiguous types prefix; field UInt64
    lands after named; program still has a UInt64 entry so CheckV1/Normalize
    succeed without constructor lowering. -/
private unsafe def testNamedStructEnumRegistration
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "NamedTypesReg" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 1\n"
  let validated ← loadSource session "named-reg" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "named-reg: CheckV1.ok"
  expect typed.analysisComplete "named-reg: analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"named-reg: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"named-reg: validate: {repr e}"
  -- Named prefix: Point then Color, then anonymous UInt64 (field + result).
  expect (data.types.size ≥ 3)
    s!"named-reg: expected ≥3 types, got {data.types.size}"
  let some t0 := data.types[0]? |
    throw <| IO.userError "named-reg: missing type[0]"
  let some t1 := data.types[1]? |
    throw <| IO.userError "named-reg: missing type[1]"
  expect (t0.name == some "Point" && t0.id == 0)
    s!"named-reg: type[0] must be named Point, got {repr t0.name}"
  expect (t1.name == some "Color" && t1.id == 1)
    s!"named-reg: type[1] must be named Color, got {repr t1.name}"
  match t0.shape with
  | .struct fields =>
      expect (fields.size == 2) s!"named-reg: Point 2 fields, got {fields.size}"
      let some fx := fields[0]? |
        throw <| IO.userError "named-reg: missing Point.x"
      let some fy := fields[1]? |
        throw <| IO.userError "named-reg: missing Point.y"
      expect (fx.name == "x" && fy.name == "y") "named-reg: Point field names"
      -- Field types must be the same anonymous UInt64 after the named prefix.
      expect (fx.typeId == fy.typeId)
        s!"named-reg: Point fields share UInt64 TypeId, got {fx.typeId}/{fy.typeId}"
      expect (fx.typeId.toNat ≥ 2)
        s!"named-reg: anonymous UInt64 must follow named prefix, tid={fx.typeId}"
      let some u64 := data.types[fx.typeId.toNat]? |
        throw <| IO.userError "named-reg: missing field TypeId"
      expect (u64.name.isNone && match u64.shape with | .uint 64 => true | _ => false)
        "named-reg: field type is anonymous UInt64"
  | _ => throw <| IO.userError "named-reg: type[0] must be .struct"
  match t1.shape with
  | .enum variants =>
      expect (variants.size == 3)
        s!"named-reg: Color 3 variants, got {variants.size}"
      let names := variants.map (·.name)
      expect (names == #["Red", "Green", "Blue"])
        s!"named-reg: Color variant order, got {names}"
      expect (variants.all (·.payloadTypes.isEmpty))
        "named-reg: Color variants have empty payloads"
  | _ => throw <| IO.userError "named-reg: type[1] must be .enum"
  -- No named type may appear after the first anonymous.
  let mut seenAnon := false
  for t in data.types do
    match t.name with
    | some n =>
        expect (!seenAnon)
          s!"named-reg: named '{n}' after anonymous violates prefix rank"
    | none => seenAnon := true

/-- T2: nested named field references resolve to earlier Pass0 TypeIds. -/
private unsafe def testNamedNestedStructFieldOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "NamedNested" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  struct Line where\n" ++
    "    a : Point\n" ++
    "    b : Point\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let validated ← loadSource session "named-nested" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "named-nested: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"named-nested: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"named-nested: validate: {repr e}"
  let some t0 := data.types[0]? |
    throw <| IO.userError "named-nested: missing type[0]"
  let some t1 := data.types[1]? |
    throw <| IO.userError "named-nested: missing type[1]"
  expect (t0.name == some "Point" && t1.name == some "Line")
    "named-nested: Point then Line named prefix"
  match t1.shape with
  | .struct fields =>
      expect (fields.size == 2) s!"named-nested: Line 2 fields, got {fields.size}"
      let some fa := fields[0]? |
        throw <| IO.userError "named-nested: missing Line.a"
      let some fb := fields[1]? |
        throw <| IO.userError "named-nested: missing Line.b"
      expect (fa.name == "a" && fb.name == "b") "named-nested: Line field names"
      expect (fa.typeId == 0 && fb.typeId == 0)
        s!"named-nested: Line fields must be Point TypeId 0, got {fa.typeId}/{fb.typeId}"
  | _ => throw <| IO.userError "named-nested: Line must be .struct"

/-- T2: later-declared named used as earlier field still resolves (phase-1 slots). -/
private unsafe def testNamedForwardFieldReference
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Source order: Wrapper first (field Inner), then Inner. Pass0 phase-1
  -- allocates both before field fill so Wrapper.inner → TypeId of Inner.
  let source := wrap "NamedForward" <|
    "  struct Wrapper where\n" ++
    "    inner : Inner\n" ++
    "  struct Inner where\n" ++
    "    v : UInt64\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let validated ← loadSource session "named-forward" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "named-forward: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"named-forward: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"named-forward: validate: {repr e}"
  let some tw := data.types[0]? |
    throw <| IO.userError "named-forward: missing Wrapper"
  let some ti := data.types[1]? |
    throw <| IO.userError "named-forward: missing Inner"
  expect (tw.name == some "Wrapper" && ti.name == some "Inner")
    "named-forward: Wrapper then Inner source order"
  match tw.shape with
  | .struct fields =>
      let some f0 := fields[0]? |
        throw <| IO.userError "named-forward: missing Wrapper.inner"
      expect (f0.name == "inner" && f0.typeId == 1)
        s!"named-forward: Wrapper.inner must be Inner TypeId 1, got {f0.typeId}"
  | _ => throw <| IO.userError "named-forward: Wrapper must be .struct"

/-- T2: enum with UInt64 payload interns anonymous payload after named prefix. -/
private unsafe def testNamedEnumPayloadTypes
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "NamedEnumPay" <|
    "  enum Shape where\n" ++
    "    | Circle(UInt64)\n" ++
    "    | Rect(UInt64, UInt64)\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let validated ← loadSource session "named-enum-pay" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "named-enum-pay: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"named-enum-pay: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"named-enum-pay: validate: {repr e}"
  let some t0 := data.types[0]? |
    throw <| IO.userError "named-enum-pay: missing Shape"
  expect (t0.name == some "Shape") "named-enum-pay: Shape at type[0]"
  match t0.shape with
  | .enum variants =>
      expect (variants.size == 2) s!"named-enum-pay: 2 variants, got {variants.size}"
      let some c := variants[0]? |
        throw <| IO.userError "named-enum-pay: missing Circle"
      let some r := variants[1]? |
        throw <| IO.userError "named-enum-pay: missing Rect"
      expect (c.name == "Circle" && c.payloadTypes.size == 1)
        "named-enum-pay: Circle one payload"
      expect (r.name == "Rect" && r.payloadTypes.size == 2)
        "named-enum-pay: Rect two payloads"
      let some p0 := c.payloadTypes[0]? |
        throw <| IO.userError "named-enum-pay: Circle payload"
      expect (p0.toNat ≥ 1)
        s!"named-enum-pay: payload UInt64 after named, tid={p0}"
      let some r0 := r.payloadTypes[0]? |
        throw <| IO.userError "named-enum-pay: Rect p0"
      let some r1 := r.payloadTypes[1]? |
        throw <| IO.userError "named-enum-pay: Rect p1"
      expect (r0 == p0 && r1 == p0)
        "named-enum-pay: all UInt64 payloads share TypeId"
  | _ => throw <| IO.userError "named-enum-pay: Shape must be .enum"

/-- T2: named struct as state type still fails closed (declaration sites stay
    public legal-UInt only; aggregate state values are T3). -/
private unsafe def testNamedStructStateUnsupported
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "NamedState" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "  state p : Point\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let validated ← loadSource session "named-state" source
  let typed := checkProgramTypedResultV1 validated
  if typed.ok then
    match normalizeProgramV1 validated with
    | .ok _ =>
        throw <| IO.userError
          "named-state: expected unsupported named struct state, got carrier"
    | .error (.unsupported detail) =>
        expect (detail.contains "UInt" || detail.contains "state" ||
            detail.contains "anonymous" || detail.contains "named")
          s!"named-state: expected UInt/state detail, got {detail}"
    | .error e =>
        throw <| IO.userError s!"named-state: expected .unsupported, got {repr e}"
  else
    -- Typed rejected named state: Normalize boundary not reached (acceptable).
    pure ()

/-- T3: aggregate type interning via struct field types (Array/Map/Option/Bytes/Field/Principal). -/
private unsafe def testAggregateTypeInterning
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "AggIntern" <|
    "  struct Bundle where\n" ++
    "    arr : Array UInt64 2\n" ++
    "    opt : Option Bool\n" ++
    "    mp : Map UInt64 UInt8\n" ++
    "    bs : Bytes 4\n" ++
    "    f : Field bn254_fr\n" ++
    "    who : Principal\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let validated ← loadSource session "agg-intern" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok "agg-intern: CheckV1.ok"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"agg-intern: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"agg-intern: validate: {repr e}"
  let some t0 := data.types[0]? |
    throw <| IO.userError "agg-intern: missing Bundle"
  expect (t0.name == some "Bundle") "agg-intern: Bundle named prefix"
  match t0.shape with
  | .struct fields =>
      expect (fields.size == 6) s!"agg-intern: 6 fields, got {fields.size}"
      let shapes := fields.map fun f =>
        match data.types[f.typeId.toNat]? with
        | some d => d.shape
        | none => .unit
      let hasArray := shapes.any fun s => match s with | .array _ 2 => true | _ => false
      let hasOpt := shapes.any fun s => match s with | .option _ => true | _ => false
      let hasMap := shapes.any fun s => match s with | .map _ _ => true | _ => false
      let hasBytes := shapes.any fun s => match s with | .bytes 4 => true | _ => false
      let hasField := shapes.any fun s => match s with | .field _ => true | _ => false
      let hasPrin := shapes.any fun s => match s with | .principal => true | _ => false
      expect (hasArray && hasOpt && hasMap && hasBytes && hasField && hasPrin)
        "agg-intern: all aggregate field shapes present"
  | _ => throw <| IO.userError "agg-intern: Bundle must be struct"

/-- T3: illegal Map key (Option) fails closed at intern. -/
private unsafe def testAggregateIllegalMapKey
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "AggMapKey" <|
    "  struct Bad where\n" ++
    "    m : Map Option Bool Bool\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let validated ← loadSource session "agg-map-key" source
  let typed := checkProgramTypedResultV1 validated
  if typed.ok then
    match normalizeProgramV1 validated with
    | .ok _ => throw <| IO.userError "agg-map-key: expected unsupported"
    | .error (.unsupported detail) =>
        expect (detail.contains "Map key" || detail.contains "legal map key")
          s!"agg-map-key: detail={detail}"
    | .error e => throw <| IO.userError s!"agg-map-key: {repr e}"
  else
    pure ()

/-- T3: unknown Field catalog id fails at source parse boundary. -/
private unsafe def testAggregateFieldCatalogReject
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "AggFieldBad" <|
    "  struct Bad where\n" ++
    "    f : Field bls12_381\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  match ← session.selectProgramV1 source (testSourcePath "agg-field-bad")
      moduleName none with
  | .ok _ =>
      throw <| IO.userError "agg-field-bad: parse must reject non-catalog Field id"
  | .error _ => pure ()

/-- T3: struct construct + fieldGet + fieldSet rebind. -/
private unsafe def testStructConstructFieldGetSet
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "StructVal" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let p : Point := Point.new(1, 2)\n" ++
    "    let a : UInt64 := p.x\n" ++
    "    p.x := 9\n" ++
    "    return p.x\n"
  let validated ← loadSource session "struct-val" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok s!"struct-val: CheckV1.ok diags={typed.diagnostics.map (·.message)}"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"struct-val: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"struct-val: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "struct-val: missing entry"
  let some blk := entryC.blocks[0]? |
    throw <| IO.userError "struct-val: missing block"
  let isConstruct (instr : InstructionV1) : Bool :=
    match instr.op with | .construct _ _ _ => true | _ => false
  let isFieldGet (instr : InstructionV1) : Bool :=
    match instr.op with | .fieldGet _ _ => true | _ => false
  let isFieldSet (instr : InstructionV1) : Bool :=
    match instr.op with | .fieldSet _ _ _ => true | _ => false
  expect (blk.instructions.any isConstruct) "struct-val: Op.Construct present"
  expect (blk.instructions.any isFieldGet) "struct-val: Op.FieldGet present"
  expect (blk.instructions.any isFieldSet) "struct-val: Op.FieldSet present"
  -- construct typeId is Point (named type 0)
  let some ctorInstr := blk.instructions.find? isConstruct |
    throw <| IO.userError "struct-val: missing construct instr"
  match ctorInstr.op with
  | .construct tid idx args =>
      expect (tid == 0 && idx == 0 && args.size == 2)
        s!"struct-val: construct Point tid0 idx0 2args, got {tid}/{idx}/{args.size}"
  | _ => throw <| IO.userError "struct-val: expected construct"

/-- T3: enum construct with payload. -/
private unsafe def testEnumConstruct
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "EnumVal" <|
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Blue(UInt64)\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let c : Color := Color.Blue(7)\n" ++
    "    let d : Color := Color.Red()\n" ++
    "    return 1\n"
  let validated ← loadSource session "enum-val" source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok s!"enum-val: CheckV1.ok diags={typed.diagnostics.map (·.message)}"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"enum-val: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"enum-val: validate: {repr e}"
  let some entryC := data.callables[0]? |
    throw <| IO.userError "enum-val: missing entry"
  let some blk := entryC.blocks[0]? |
    throw <| IO.userError "enum-val: missing block"
  let constructs := blk.instructions.filterMap fun instr =>
    match instr.op with
    | .construct tid idx args => some (tid, idx, args.size)
    | _ => none
  expect (constructs.size == 2) s!"enum-val: 2 constructs, got {constructs.size}"
  -- Blue is variant index 1 with 1 payload; Red is index 0 with 0 payload.
  expect (constructs.any fun (_, idx, n) => idx == 1 && n == 1)
    "enum-val: Blue construct idx1 arity1"
  expect (constructs.any fun (_, idx, n) => idx == 0 && n == 0)
    "enum-val: Red construct idx0 arity0"

/-- T3: constructor arity mismatch fails (TypeCheck or Normalize). -/
private unsafe def testStructConstructArityMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "StructArity" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let p : Point := Point.new(1)\n" ++
    "    return 0\n"
  let validated ← loadSource session "struct-arity" source
  let typed := checkProgramTypedResultV1 validated
  if typed.ok then
    match normalizeProgramV1 validated with
    | .ok _ => throw <| IO.userError "struct-arity: expected failure"
    | .error (.unsupported detail) =>
        expect (detail.contains "argument" || detail.contains "constructor")
          s!"struct-arity: detail={detail}"
    | .error e => throw <| IO.userError s!"struct-arity: {repr e}"
  else
    expect (typed.diagnostics.any fun d =>
        d.message.contains "constructor" || d.message.contains "argument")
      "struct-arity: TypeCheck arity diagnostic"

/-- T3: fieldGet on non-struct fails closed at Normalize (when Check passes via cast).
    Practical pin: nested field on UInt64 place is TypeCheck-rejected. -/
private unsafe def testFieldGetNonStructTypedNotOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "FieldBad" <|
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    return x.y\n"
  let validated ← loadSource session "field-bad" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok) "field-bad: CheckV1 rejects field on UInt64"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testCounterHappyPath session
  testStateAfterInit session
  testDeterminism session
  testTypedNotOk session
  testUInt64Literals session
  testUInt64Subtraction session
  testAssertComparison session
  testAllComparisonOps session
  testAssertBoolLiteral session
  testBoolViewResult session
  testBoolEntryResultAndLiteral session
  testIfMultiBlock session
  testIfBothBranchesReturn session
  testIfNoElse session
  testNestedIf session
  testMatchUIntLiterals session
  testMatchBoolAndBind session
  testUnsupportedStatementAfterTerminalIf session
  testUnsupportedMatchDuplicateLiteral session
  testUnsupportedMatchConstructorPattern session
  testEmitRevertMultiBlock session
  testEmitRequirementsWireOrder session
  testEmitInViewTypedNotOk session
  testUnsupportedEventBoolField session
  testUnsupportedEventPrivateField session
  testEmitRevertProvenance session
  testFnLocalCall session
  testFnRevertPath session
  testFnStateReadTypedNotOk session
  testFnCallCycleTypedNotOk session
  testFnLocalCallProvenance session
  testMulDivModUnary session
  testUnaryOps session
  testShiftBitwiseLogical session
  testCallScheduleLowering session
  testCallScheduleProvenance session
  testLetForLoop session
  testLetForProvenance session
  testUInt64LiteralProvenance session
  testUInt64SubtractionProvenance session
  testFnIdentitySupported session
  testUnsupportedPrivateState session
  testUnsupportedBoolState session
  testUnsupportedBoolParam session
  testUnsupportedAssertElse session
  testUnsupportedNestedComparison session
  testUnsupportedParamShadowsStateAssign session
  testCounterRequirementsAndProvenance session
  testMultiSiteProvenanceAttribution session
  testMissingRequirementProducingSite session
  testFreezeRejectsForeignKeys session
  -- T1 multi-width anonymous integers
  testMultiWidthUIntState session
  testMultiWidthIntResults session
  testMultiWidthMatchScrut session
  testMixedWidthOperandsTypedNotOk session
  testMultiWidthShiftUInt32Shared session
  testUInt64LiteralBytesUnchanged session
  -- T2 named Struct/Enum registration
  testNamedStructEnumRegistration session
  testNamedNestedStructFieldOrder session
  testNamedForwardFieldReference session
  testNamedEnumPayloadTypes session
  testNamedStructStateUnsupported session
  -- T3 aggregate values
  testAggregateTypeInterning session
  testAggregateIllegalMapKey session
  testAggregateFieldCatalogReject session
  testStructConstructFieldGetSet session
  testEnumConstruct session
  testStructConstructArityMismatch session
  testFieldGetNonStructTypedNotOk session
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
  -- B7b3d draft authority / erase / located
  testDraftSuccessParity session
  testDraftTypeOnlyParity session
  testDraftEffectOnlyParity session
  testDraftBoundOnlyParity session
  testDraftDisclosureOnlyParity session
  testDraftMixedPhases session
  testDraftResolutionShortCircuit session
  testDraftCycleStructureOrder session
  testDraftDuplicateFnIncomplete session
  testLocatedForeignInventory session
  testLocatedMissingPathAllOrNothing session
  testDraftLocatedDeterminism session
  IO.println "Tests.Typed.CheckV1: ok"
  -- S1 normalizer vertical contract (Loader→CheckV1→Normalize→Wire); CI pin.
  Tests.Semantic.NormalizeV1.run

end Tests.Typed.CheckV1
