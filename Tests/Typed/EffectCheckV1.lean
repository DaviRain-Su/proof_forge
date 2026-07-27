/-
  Tests.Typed.EffectCheckV1 — D2-02 effect/call/view checker focused suite.

  Covers AST direct effects, fn/localCall fixed-point transitive closure (incl.
  cycles), fn/view allowlists, entry/init permissiveness for currently
  expressible effects, shadowing of state/callee names, field/index state
  places, duplicate-fn incomplete analysis fail-closed, deterministic
  PF-EFFECT-001 diagnostics in declaration/effect order, and wire stability.
-/
import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.EffectCheckV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace Tests.Typed.EffectCheckV1

open ProofForgeV2
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.EffectCheckV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.EffectCheckV1"

private unsafe def checkSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (Array DiagnosticV1) := do
  match ← session.selectProgramV1 source ("<effect-check-" ++ label ++ ">") moduleName none with
  | .ok validated => pure (checkProgramEffectsV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def messages (diags : Array DiagnosticV1) : Array String :=
  diags.map (fun d => d.message)

private def wires (diags : Array DiagnosticV1) : Array String :=
  diags.map (fun d => d.code.wire)

private def contains (haystack : Array String) (needle : String) : Bool :=
  haystack.any (·.contains needle)

private def expectOk (diags : Array DiagnosticV1) (label : String) : IO Unit :=
  unless diags.isEmpty do
    throw <| IO.userError s!"{label}: expected ok, got diagnostics {messages diags}"

private def expectNotOk (diags : Array DiagnosticV1) (label : String) : IO Unit :=
  if diags.isEmpty then
    throw <| IO.userError s!"{label}: expected diagnostics, got ok"
  else
    pure ()

private def expectWireEffect001 (diags : Array DiagnosticV1) (label : String) : IO Unit := do
  unless diags.all (fun d => d.code.wire == "PF-EFFECT-001") do
    throw <| IO.userError s!"{label}: expected only PF-EFFECT-001 wires, got {wires diags}"

private unsafe def testPureFnOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PureFnOk where\n" ++
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a + b\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return add(1, 2)\n"
  let diags ← checkSource session "pure-fn-ok" source
  expectOk diags "pure-fn-ok"

private unsafe def testFnRevertAndAssertOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FnRevertOk where\n" ++
    "  error Boom()\n" ++
    "  fn guarded(x : Bool) : UInt64 do\n" ++
    "    assert x\n" ++
    "    if x then\n" ++
    "      return 1\n" ++
    "    else\n" ++
    "      revert Boom()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return guarded(true)\n"
  let diags ← checkSource session "fn-revert-assert-ok" source
  expectOk diags "fn-revert-assert-ok"

private unsafe def testFnStateReadRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FnStateRead where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek()\n"
  let diags ← checkSource session "fn-state-read" source
  expectNotOk diags "fn-state-read"
  expectWireEffect001 diags "fn-state-read"
  unless contains (messages diags) "fn 'peek' does not allow effect 'state.read'" do
    throw <| IO.userError s!"fn-state-read: unexpected messages {messages diags}"

private unsafe def testFnStateWriteRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FnStateWrite where\n" ++
    "  state total : UInt64\n" ++
    "  fn bump() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return bump()\n"
  let diags ← checkSource session "fn-state-write" source
  expectNotOk diags "fn-state-write"
  expectWireEffect001 diags "fn-state-write"
  let msgs := messages diags
  unless contains msgs "fn 'bump' does not allow effect 'state.write'" do
    throw <| IO.userError s!"fn-state-write: missing state.write, got {msgs}"
  unless contains msgs "fn 'bump' does not allow effect 'state.read'" do
    throw <| IO.userError s!"fn-state-write: missing state.read from return, got {msgs}"

private unsafe def testFnEmitCallScheduleRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FnSideEffects where\n" ++
    "  event Ev()\n" ++
    "  fn bad() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    call External.Use()\n" ++
    "    schedule External.Later()\n" ++
    "    return 0\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return bad()\n"
  let diags ← checkSource session "fn-side-effects" source
  expectNotOk diags "fn-side-effects"
  expectWireEffect001 diags "fn-side-effects"
  let msgs := messages diags
  unless contains msgs "fn 'bad' does not allow effect 'event.emit'" do
    throw <| IO.userError s!"fn-side-effects: missing event.emit, got {msgs}"
  unless contains msgs "fn 'bad' does not allow effect 'external.call.sync'" do
    throw <| IO.userError s!"fn-side-effects: missing external.call.sync, got {msgs}"
  unless contains msgs "fn 'bad' does not allow effect 'workflow.schedule'" do
    throw <| IO.userError s!"fn-side-effects: missing workflow.schedule, got {msgs}"
  -- Stable effect-kind order for one callable.
  unless msgs[0]!.contains "event.emit"
      && msgs[1]!.contains "external.call.sync"
      && msgs[2]!.contains "workflow.schedule" do
    throw <| IO.userError s!"fn-side-effects: effect order not stable, got {msgs}"

private unsafe def testViewStateReadOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ViewReadOk where\n" ++
    "  state total : UInt64\n" ++
    "  view get() : UInt64 do\n" ++
    "    return total\n"
  let diags ← checkSource session "view-state-read-ok" source
  expectOk diags "view-state-read-ok"

private unsafe def testViewStateWriteRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ViewWrite where\n" ++
    "  state total : UInt64\n" ++
    "  view set() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return total\n"
  let diags ← checkSource session "view-state-write" source
  expectNotOk diags "view-state-write"
  expectWireEffect001 diags "view-state-write"
  unless contains (messages diags) "view 'set' does not allow effect 'state.write'" do
    throw <| IO.userError s!"view-state-write: unexpected {messages diags}"

private unsafe def testViewEmitCallScheduleRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ViewSideEffects where\n" ++
    "  state total : UInt64\n" ++
    "  event Ev()\n" ++
    "  view bad() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    call External.Use()\n" ++
    "    schedule External.Later()\n" ++
    "    return total\n"
  let diags ← checkSource session "view-side-effects" source
  expectNotOk diags "view-side-effects"
  expectWireEffect001 diags "view-side-effects"
  let msgs := messages diags
  unless contains msgs "view 'bad' does not allow effect 'event.emit'" do
    throw <| IO.userError s!"view-side-effects: missing emit, got {msgs}"
  unless contains msgs "view 'bad' does not allow effect 'external.call.sync'" do
    throw <| IO.userError s!"view-side-effects: missing call, got {msgs}"
  unless contains msgs "view 'bad' does not allow effect 'workflow.schedule'" do
    throw <| IO.userError s!"view-side-effects: missing schedule, got {msgs}"

private unsafe def testViewRevertOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ViewRevertOk where\n" ++
    "  state total : UInt64\n" ++
    "  error Boom()\n" ++
    "  view get(ok : Bool) : UInt64 do\n" ++
    "    assert ok\n" ++
    "    if ok then\n" ++
    "      return total\n" ++
    "    else\n" ++
    "      revert Boom()\n"
  let diags ← checkSource session "view-revert-ok" source
  expectOk diags "view-revert-ok"

private unsafe def testEntryInitAllowEffects
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EntryInitOk where\n" ++
    "  state total : UInt64\n" ++
    "  event Ev(v : UInt64)\n" ++
    "  error Boom()\n" ++
    "  init(seed : UInt64) do\n" ++
    "    total := seed\n" ++
    "    emit Ev(total)\n" ++
    "    call External.Setup(total)\n" ++
    "    schedule External.Later(total)\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    total := x\n" ++
    "    emit Ev(total)\n" ++
    "    call External.Use(total)\n" ++
    "    schedule External.Later(total)\n" ++
    "    assert true\n" ++
    "    if false then\n" ++
    "      revert Boom()\n" ++
    "    return total\n"
  let diags ← checkSource session "entry-init-allow" source
  expectOk diags "entry-init-allow"

private unsafe def testTransitiveFnAbsorbsCalleeWrite
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TransitiveWrite where\n" ++
    "  state total : UInt64\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return 1\n" ++
    "  fn caller() : UInt64 do\n" ++
    "    return writer()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return caller()\n"
  let diags ← checkSource session "transitive-write" source
  expectNotOk diags "transitive-write"
  expectWireEffect001 diags "transitive-write"
  let msgs := messages diags
  -- Declaration order: writer before caller.
  unless contains msgs "fn 'writer' does not allow effect 'state.write'" do
    throw <| IO.userError s!"transitive-write: missing writer diagnostic, got {msgs}"
  unless contains msgs "fn 'caller' does not allow effect 'state.write'" do
    throw <| IO.userError s!"transitive-write: missing caller transitive diagnostic, got {msgs}"
  let writerIdx := msgs.findIdx? (·.contains "fn 'writer'")
  let callerIdx := msgs.findIdx? (·.contains "fn 'caller'")
  match writerIdx, callerIdx with
  | some wi, some ci =>
      unless wi < ci do
        throw <| IO.userError s!"transitive-write: declaration order violated, got {msgs}"
  | _, _ => throw <| IO.userError s!"transitive-write: missing indices in {msgs}"

private unsafe def testTransitiveViewAbsorbsCalleeWrite
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ViewTransitiveWrite where\n" ++
    "  state total : UInt64\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return 1\n" ++
    "  view get() : UInt64 do\n" ++
    "    return writer()\n"
  let diags ← checkSource session "view-transitive-write" source
  expectNotOk diags "view-transitive-write"
  expectWireEffect001 diags "view-transitive-write"
  let msgs := messages diags
  unless contains msgs "fn 'writer' does not allow effect 'state.write'" do
    throw <| IO.userError s!"view-transitive-write: missing writer, got {msgs}"
  unless contains msgs "view 'get' does not allow effect 'state.write'" do
    throw <| IO.userError s!"view-transitive-write: missing view absorption, got {msgs}"

private unsafe def testTransitiveViewCallsPureFnOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ViewCallsPure where\n" ++
    "  state total : UInt64\n" ++
    "  fn twice(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n" ++
    "  view get() : UInt64 do\n" ++
    "    return twice(total)\n"
  let diags ← checkSource session "view-calls-pure" source
  expectOk diags "view-calls-pure"

private unsafe def testParamShadowsStateNoRead
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ParamShadow where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek(total : UInt64) : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek(0)\n"
  let diags ← checkSource session "param-shadow-state" source
  expectOk diags "param-shadow-state"

private unsafe def testLocalShadowsStateNoRead
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocalShadow where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    let total : UInt64 := 0\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek()\n"
  let diags ← checkSource session "local-shadow-state" source
  expectOk diags "local-shadow-state"

private unsafe def testShadowedCalleeNoTransitiveEffect
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ShadowedCallee where\n" ++
    "  state total : UInt64\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return 1\n" ++
    "  fn caller(writer : UInt64) : UInt64 do\n" ++
    "    return writer\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return caller(0)\n"
  let diags ← checkSource session "shadowed-callee" source
  expectNotOk diags "shadowed-callee"
  let msgs := messages diags
  unless contains msgs "fn 'writer' does not allow effect 'state.write'" do
    throw <| IO.userError s!"shadowed-callee: writer should still fail, got {msgs}"
  if contains msgs "fn 'caller'" then
    throw <| IO.userError s!"shadowed-callee: caller should not absorb writer, got {msgs}"

private unsafe def testChainTransitiveThreeFns
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ChainThree where\n" ++
    "  state total : UInt64\n" ++
    "  event Ev()\n" ++
    "  fn leaf() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    return 0\n" ++
    "  fn mid() : UInt64 do\n" ++
    "    return leaf()\n" ++
    "  fn top() : UInt64 do\n" ++
    "    return mid()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return top()\n"
  let diags ← checkSource session "chain-three" source
  expectNotOk diags "chain-three"
  expectWireEffect001 diags "chain-three"
  let msgs := messages diags
  unless contains msgs "fn 'leaf' does not allow effect 'event.emit'" do
    throw <| IO.userError s!"chain-three: missing leaf, got {msgs}"
  unless contains msgs "fn 'mid' does not allow effect 'event.emit'" do
    throw <| IO.userError s!"chain-three: missing mid, got {msgs}"
  unless contains msgs "fn 'top' does not allow effect 'event.emit'" do
    throw <| IO.userError s!"chain-three: missing top, got {msgs}"

private unsafe def testHumanRenderUsesEffectWire
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program HumanWire where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek()\n"
  let diags ← checkSource session "human-wire" source
  expectNotOk diags "human-wire"
  let rendered := diags.map (·.renderHuman)
  unless rendered.any (·.startsWith "PF-EFFECT-001: ") do
    throw <| IO.userError s!"human-wire: expected PF-EFFECT-001 human line, got {rendered}"

/-- Cyclic local-call graph must still propagate multi-hop effects via fixed-point
    (no silent degrade to direct-only that drops the caller's absorbed emit). -/
private unsafe def testCycleMultiHopEffectPropagation
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CycleMultiHop where\n" ++
    "  event Ev()\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return b()\n" ++
    "  fn b() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    return a()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "cycle-multi-hop" source
  expectNotOk diags "cycle-multi-hop"
  expectWireEffect001 diags "cycle-multi-hop"
  let msgs := messages diags
  unless contains msgs "fn 'a' does not allow effect 'event.emit'" do
    throw <| IO.userError s!"cycle-multi-hop: a must absorb emit through cycle, got {msgs}"
  unless contains msgs "fn 'b' does not allow effect 'event.emit'" do
    throw <| IO.userError s!"cycle-multi-hop: b must report direct emit, got {msgs}"

/-- Three-fn cycle with effect only on the last member still reaches the first. -/
private unsafe def testCycleThreeHopEffectPropagation
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CycleThreeHop where\n" ++
    "  state total : UInt64\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return b()\n" ++
    "  fn b() : UInt64 do\n" ++
    "    return c()\n" ++
    "  fn c() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return a()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "cycle-three-hop" source
  expectNotOk diags "cycle-three-hop"
  expectWireEffect001 diags "cycle-three-hop"
  let msgs := messages diags
  unless contains msgs "fn 'a' does not allow effect 'state.write'" do
    throw <| IO.userError s!"cycle-three-hop: a must absorb write, got {msgs}"
  unless contains msgs "fn 'b' does not allow effect 'state.write'" do
    throw <| IO.userError s!"cycle-three-hop: b must absorb write, got {msgs}"
  unless contains msgs "fn 'c' does not allow effect 'state.write'" do
    throw <| IO.userError s!"cycle-three-hop: c must report write, got {msgs}"

private def mkName (raw : String) : IO SourceNameComponentV1 :=
  match parseSourceNameComponentV1 raw with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"mkName: {e}"

/-- Duplicate fn keys make call-edge attribution ambiguous.  ValidatedSourceV1
    rejects them at decl-set validation, so this exercises the independent
    `checkEffectsV1` entry with tables built from a raw ProgramV1 that still
    carries two same-name fns (as `buildTables` records both). -/
private unsafe def testDuplicateFnFailClosed
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
  -- buildTables records both fn rows and emits a structural duplicate diagnostic.
  let (tables, st) := (buildTables progAst).run { diagnostics := #[] }
  unless tables.fn.hasDuplicateKey do
    throw <| IO.userError "dup-fn: expected hasDuplicateKey on fn table"
  unless contains (st.diagnostics.map (·.message)) "duplicate fn declaration 'helper'" do
    throw <| IO.userError s!"dup-fn: buildTables missing duplicate diagnostic, got {st.diagnostics.map (·.message)}"
  let res := checkEffectsV1 progAst tables
  unless !res.analysisComplete do
    throw <| IO.userError "dup-fn: expected analysisComplete = false"
  unless !res.ok do
    throw <| IO.userError "dup-fn: expected ok = false (must not present analysis success)"
  -- Allowlist diagnostics are not produced under incomplete analysis.
  unless res.diagnostics.isEmpty do
    throw <| IO.userError s!"dup-fn: expected no effect allowlist diagnostics, got {messages res.diagnostics}"
  -- Product-style composition: incomplete ⇒ surface structural diagnostics.
  let composed :=
    if res.analysisComplete then res.diagnostics
    else st.diagnostics ++ res.diagnostics
  expectNotOk composed "dup-fn-composed"
  unless contains (messages composed) "duplicate fn declaration 'helper'" do
    throw <| IO.userError s!"dup-fn-composed: expected structural diagnostic, got {messages composed}"

/-- Local `let` shadows a callee name: no localCall edge, no transitive absorb. -/
private unsafe def testLocalLetShadowsCalleeNoTransitive
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocalLetShadowCallee where\n" ++
    "  state total : UInt64\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return 1\n" ++
    "  fn caller() : UInt64 do\n" ++
    "    let writer : UInt64 := 0\n" ++
    "    return writer\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return caller()\n"
  let diags ← checkSource session "local-let-shadow-callee" source
  expectNotOk diags "local-let-shadow-callee"
  let msgs := messages diags
  unless contains msgs "fn 'writer' does not allow effect 'state.write'" do
    throw <| IO.userError s!"local-let-shadow-callee: writer should fail, got {msgs}"
  if contains msgs "fn 'caller'" then
    throw <| IO.userError s!"local-let-shadow-callee: caller must not absorb writer, got {msgs}"

/-- Assignment to a param/local that shadows state is not `state.write`. -/
private unsafe def testAssignTargetParamLocalShadowsState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AssignShadowState where\n" ++
    "  state total : UInt64\n" ++
    "  fn viaParam(total : UInt64) : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return total\n" ++
    "  fn viaLocal() : UInt64 do\n" ++
    "    let total : UInt64 := 0\n" ++
    "    total := 1\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return viaParam(0) + viaLocal()\n"
  let diags ← checkSource session "assign-shadow-state" source
  expectOk diags "assign-shadow-state"

/-- Struct field and array index places on state: read/write classified correctly. -/
private unsafe def testFieldAndIndexStateReadWrite
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Field/index read illegal for fn; write illegal for fn and view.
  let sourceFn :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FieldIndexFn where\n" ++
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "  state p : Pair\n" ++
    "  state arr : Array UInt64 2\n" ++
    "  fn readField() : UInt64 do\n" ++
    "    return p.left\n" ++
    "  fn readIndex() : UInt64 do\n" ++
    "    return arr[0]\n" ++
    "  fn writeField() : UInt64 do\n" ++
    "    p.left := 1\n" ++
    "    return 0\n" ++
    "  fn writeIndex() : UInt64 do\n" ++
    "    arr[0] := 1\n" ++
    "    return 0\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diagsFn ← checkSource session "field-index-fn" sourceFn
  expectNotOk diagsFn "field-index-fn"
  expectWireEffect001 diagsFn "field-index-fn"
  let msgsFn := messages diagsFn
  unless contains msgsFn "fn 'readField' does not allow effect 'state.read'" do
    throw <| IO.userError s!"field-index-fn: missing field read, got {msgsFn}"
  unless contains msgsFn "fn 'readIndex' does not allow effect 'state.read'" do
    throw <| IO.userError s!"field-index-fn: missing index read, got {msgsFn}"
  unless contains msgsFn "fn 'writeField' does not allow effect 'state.write'" do
    throw <| IO.userError s!"field-index-fn: missing field write, got {msgsFn}"
  unless contains msgsFn "fn 'writeIndex' does not allow effect 'state.write'" do
    throw <| IO.userError s!"field-index-fn: missing index write, got {msgsFn}"

  let sourceView :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FieldIndexView where\n" ++
    "  struct Pair where\n" ++
    "    left : UInt64\n" ++
    "  state p : Pair\n" ++
    "  state arr : Array UInt64 2\n" ++
    "  view readOk() : UInt64 do\n" ++
    "    return p.left + arr[0]\n" ++
    "  view writeField() : UInt64 do\n" ++
    "    p.left := 1\n" ++
    "    return 0\n" ++
    "  view writeIndex() : UInt64 do\n" ++
    "    arr[0] := 1\n" ++
    "    return 0\n"
  let diagsView ← checkSource session "field-index-view" sourceView
  expectNotOk diagsView "field-index-view"
  let msgsView := messages diagsView
  if contains msgsView "view 'readOk'" then
    throw <| IO.userError s!"field-index-view: readOk should be allowed, got {msgsView}"
  unless contains msgsView "view 'writeField' does not allow effect 'state.write'" do
    throw <| IO.userError s!"field-index-view: missing field write, got {msgsView}"
  unless contains msgsView "view 'writeIndex' does not allow effect 'state.write'" do
    throw <| IO.userError s!"field-index-view: missing index write, got {msgsView}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testPureFnOk session
  testFnRevertAndAssertOk session
  testFnStateReadRejected session
  testFnStateWriteRejected session
  testFnEmitCallScheduleRejected session
  testViewStateReadOk session
  testViewStateWriteRejected session
  testViewEmitCallScheduleRejected session
  testViewRevertOk session
  testEntryInitAllowEffects session
  testTransitiveFnAbsorbsCalleeWrite session
  testTransitiveViewAbsorbsCalleeWrite session
  testTransitiveViewCallsPureFnOk session
  testParamShadowsStateNoRead session
  testLocalShadowsStateNoRead session
  testShadowedCalleeNoTransitiveEffect session
  testChainTransitiveThreeFns session
  testHumanRenderUsesEffectWire session
  testCycleMultiHopEffectPropagation session
  testCycleThreeHopEffectPropagation session
  testDuplicateFnFailClosed session
  testLocalLetShadowsCalleeNoTransitive session
  testAssignTargetParamLocalShadowsState session
  testFieldAndIndexStateReadWrite session
  IO.println "Tests.Typed.EffectCheckV1: ok"

end Tests.Typed.EffectCheckV1
