/-
  Tests.Typed.BoundCheckV1 — D2-03 termination/bound checker focused suite.

  Covers pure-fn call-cycle rejection with PF-BOUND-001, nested for-bound
  UInt32 product overflow, loops under if/match, shadowing (no false edges),
  entry/view/init non-cycle membership, human render wire, and duplicate-fn
  incomplete analysis fail-closed.  Does not assert product wiring.
-/
import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.BoundCheckV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace Tests.Typed.BoundCheckV1

open ProofForgeV2
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.BoundCheckV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.BoundCheckV1"

private unsafe def checkSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (Array DiagnosticV1) := do
  match ← session.selectProgramV1 source ("<bound-check-" ++ label ++ ">") moduleName none with
  | .ok validated => pure (checkProgramBoundsV1 validated)
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

private def expectWireBound001 (diags : Array DiagnosticV1) (label : String) : IO Unit := do
  unless diags.all (fun d => d.code.wire == "PF-BOUND-001") do
    throw <| IO.userError s!"{label}: expected only PF-BOUND-001 wires, got {wires diags}"

private unsafe def testAcyclicChain
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program Acyclic where\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return 0\n" ++
    "  fn b() : UInt64 do\n" ++
    "    return a()\n" ++
    "  fn c() : UInt64 do\n" ++
    "    return b()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return c()\n"
  let diags ← checkSource session "acyclic-chain" source
  expectOk diags "acyclic-chain"

private unsafe def testSelfRecursion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program SelfRec where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "self-recursion" source
  expectNotOk diags "self-recursion"
  expectWireBound001 diags "self-recursion"
  let msgs := messages diags
  unless contains msgs "unbounded recursion (call cycle): f" do
    throw <| IO.userError s!"self-recursion: expected cycle 'f', got {msgs}"

private unsafe def testTwoFnCycle
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TwoFn where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return g()\n" ++
    "  fn g() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "two-fn-cycle" source
  expectNotOk diags "two-fn-cycle"
  expectWireBound001 diags "two-fn-cycle"
  let msgs := messages diags
  unless contains msgs "unbounded recursion (call cycle): f, g" do
    throw <| IO.userError s!"two-fn-cycle: expected cycle 'f, g', got {msgs}"

private unsafe def testThreeFnCycle
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ThreeFn where\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return b()\n" ++
    "  fn b() : UInt64 do\n" ++
    "    return c()\n" ++
    "  fn c() : UInt64 do\n" ++
    "    return a()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "three-fn-cycle" source
  expectNotOk diags "three-fn-cycle"
  expectWireBound001 diags "three-fn-cycle"
  let msgs := messages diags
  unless contains msgs "unbounded recursion (call cycle): a, b, c" do
    throw <| IO.userError s!"three-fn-cycle: expected cycle 'a, b, c', got {msgs}"

private unsafe def testEntryViewInitCallFnNoCycle
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NonFnCallSites where\n" ++
    "  state total : UInt64\n" ++
    "  fn helper(x : UInt64) : UInt64 do\n" ++
    "    return x\n" ++
    "  init(seed : UInt64) do\n" ++
    "    total := helper(seed)\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return helper(total)\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return helper(total)\n"
  let diags ← checkSource session "non-fn-call-sites" source
  expectOk diags "non-fn-call-sites"

private unsafe def testSingleForBoundsOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program SingleFor where\n" ++
    "  state total : UInt64\n" ++
    "  entry runZero() do\n" ++
    "    for i in 0 ..< 0 bounded 0 do\n" ++
    "      total := i\n" ++
    "  entry runTen() do\n" ++
    "    for i in 0 ..< 10 bounded 10 do\n" ++
    "      total := i\n" ++
    "  entry runMax() do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      total := i\n"
  let diags ← checkSource session "single-for-ok" source
  expectOk diags "single-for-ok"

private unsafe def testNestedForTenByTenOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestedTen where\n" ++
    "  state total : UInt64\n" ++
    "  entry run() do\n" ++
    "    for i in 0 ..< 10 bounded 10 do\n" ++
    "      for j in 0 ..< 10 bounded 10 do\n" ++
    "        total := i\n"
  let diags ← checkSource session "nested-ten-ok" source
  expectOk diags "nested-ten-ok"

private unsafe def testNestedTwo4096Ok
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- 4096 * 4096 = 2^24 fits in UInt32.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestedTwo4096 where\n" ++
    "  state total : UInt64\n" ++
    "  fn work() : UInt64 do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        total := i\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return work()\n"
  let diags ← checkSource session "nested-two-4096-ok" source
  expectOk diags "nested-two-4096-ok"

private unsafe def testNestedThree4096Overflow
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- 4096^3 = 2^36 overflows UInt32.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestedThree4096 where\n" ++
    "  state total : UInt64\n" ++
    "  fn work() : UInt64 do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        for k in 0 ..< 4096 bounded 4096 do\n" ++
    "          total := i\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return work()\n"
  let diags ← checkSource session "nested-three-4096" source
  expectNotOk diags "nested-three-4096"
  expectWireBound001 diags "nested-three-4096"
  let msgs := messages diags
  unless contains msgs "loop bound product overflows UInt32 in fn 'work' (bound 4096)" do
    throw <| IO.userError s!"nested-three-4096: unexpected messages {msgs}"

private unsafe def testLoopInsideIfStillMultiplies
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LoopInIf where\n" ++
    "  state total : UInt64\n" ++
    "  state flag : Bool\n" ++
    "  entry run() do\n" ++
    "    if flag then\n" ++
    "      for i in 0 ..< 4096 bounded 4096 do\n" ++
    "        for j in 0 ..< 4096 bounded 4096 do\n" ++
    "          for k in 0 ..< 4096 bounded 4096 do\n" ++
    "            total := i\n" ++
    "    else\n" ++
    "      total := 0\n"
  let diags ← checkSource session "loop-in-if" source
  expectNotOk diags "loop-in-if"
  expectWireBound001 diags "loop-in-if"
  let msgs := messages diags
  unless contains msgs "loop bound product overflows UInt32 in entry 'run' (bound 4096)" do
    throw <| IO.userError s!"loop-in-if: unexpected messages {msgs}"

private unsafe def testLoopInsideMatchArmStillMultiplies
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LoopInMatch where\n" ++
    "  state total : UInt64\n" ++
    "  state flag : Bool\n" ++
    "  entry run() do\n" ++
    "    match flag with\n" ++
    "    | true => do\n" ++
    "      for i in 0 ..< 4096 bounded 4096 do\n" ++
    "        for j in 0 ..< 4096 bounded 4096 do\n" ++
    "          for k in 0 ..< 4096 bounded 4096 do\n" ++
    "            total := i\n" ++
    "    | false => do\n" ++
    "      total := 0\n"
  let diags ← checkSource session "loop-in-match" source
  expectNotOk diags "loop-in-match"
  expectWireBound001 diags "loop-in-match"
  let msgs := messages diags
  unless contains msgs "loop bound product overflows UInt32 in entry 'run' (bound 4096)" do
    throw <| IO.userError s!"loop-in-match: unexpected messages {msgs}"

private unsafe def testShadowedCalleeNoEdge
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ShadowedCallee where\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run(helper : UInt64) : UInt64 do\n" ++
    "    return helper\n"
  let diags ← checkSource session "shadowed-callee" source
  expectOk diags "shadowed-callee"

private unsafe def testLocalShadowsCalleeNoEdge
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocalShadow where\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run() : UInt64 do\n" ++
    "    let helper := 0\n" ++
    "    return helper\n"
  let diags ← checkSource session "local-shadow" source
  expectOk diags "local-shadow"

private unsafe def testFnParamShadowsCalleeNoSelfCycle
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Param named like the fn itself does not create a self-edge.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ParamShadowSelf where\n" ++
    "  fn f(f : UInt64) : UInt64 do\n" ++
    "    return f\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return f(1)\n"
  let diags ← checkSource session "param-shadow-self" source
  expectOk diags "param-shadow-self"

private unsafe def testHumanRenderUsesBoundWire
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program HumanWire where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "human-wire" source
  expectNotOk diags "human-wire"
  let rendered := diags.map (·.renderHuman)
  unless rendered.any (·.startsWith "PF-BOUND-001:") do
    throw <| IO.userError s!"human-wire: expected PF-BOUND-001 human line, got {rendered}"

private def mkName (raw : String) : IO SourceNameComponentV1 :=
  match parseSourceNameComponentV1 raw with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"mkName: {e}"

/-- Duplicate fn keys make call-edge attribution ambiguous.  ValidatedSourceV1
    rejects them at decl-set validation, so this exercises the independent
    `checkBoundsV1` entry with tables built from a raw ProgramV1. -/
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
  let (tables, st) := (buildTables progAst).run { diagnostics := #[] }
  unless tables.fn.hasDuplicateKey do
    throw <| IO.userError "dup-fn: expected hasDuplicateKey on fn table"
  unless contains (st.diagnostics.map (·.message)) "duplicate fn declaration 'helper'" do
    throw <| IO.userError s!"dup-fn: buildTables missing duplicate diagnostic, got {st.diagnostics.map (·.message)}"
  let res := checkBoundsV1 progAst tables
  unless !res.analysisComplete do
    throw <| IO.userError "dup-fn: expected analysisComplete = false"
  unless !res.ok do
    throw <| IO.userError "dup-fn: expected ok = false (must not present analysis success)"
  unless res.diagnostics.isEmpty do
    throw <| IO.userError s!"dup-fn: expected no bound diagnostics, got {messages res.diagnostics}"
  let composed :=
    if res.analysisComplete then res.diagnostics
    else st.diagnostics ++ res.diagnostics
  expectNotOk composed "dup-fn-composed"
  unless contains (messages composed) "duplicate fn declaration 'helper'" do
    throw <| IO.userError s!"dup-fn-composed: expected structural diagnostic, got {messages composed}"

private unsafe def testCycleThenLoopPhaseOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Both a cycle and a nested overflow: cycle diagnostics precede loop diags.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CycleAndLoop where\n" ++
    "  state total : UInt64\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return g()\n" ++
    "  fn g() : UInt64 do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        for k in 0 ..< 4096 bounded 4096 do\n" ++
    "          total := i\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "cycle-then-loop" source
  expectNotOk diags "cycle-then-loop"
  expectWireBound001 diags "cycle-then-loop"
  let msgs := messages diags
  unless msgs.size >= 2 do
    throw <| IO.userError s!"cycle-then-loop: expected ≥2 diagnostics, got {msgs}"
  unless msgs[0]!.contains "unbounded recursion (call cycle)" do
    throw <| IO.userError s!"cycle-then-loop: first should be cycle, got {msgs}"
  unless msgs.any (·.contains "loop bound product overflows") do
    throw <| IO.userError s!"cycle-then-loop: expected loop overflow, got {msgs}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testAcyclicChain session
  testSelfRecursion session
  testTwoFnCycle session
  testThreeFnCycle session
  testEntryViewInitCallFnNoCycle session
  testSingleForBoundsOk session
  testNestedForTenByTenOk session
  testNestedTwo4096Ok session
  testNestedThree4096Overflow session
  testLoopInsideIfStillMultiplies session
  testLoopInsideMatchArmStillMultiplies session
  testShadowedCalleeNoEdge session
  testLocalShadowsCalleeNoEdge session
  testFnParamShadowsCalleeNoSelfCycle session
  testHumanRenderUsesBoundWire session
  testDuplicateFnFailClosed session
  testCycleThenLoopPhaseOrder session
  IO.println "Tests.Typed.BoundCheckV1: ok"

end Tests.Typed.BoundCheckV1
