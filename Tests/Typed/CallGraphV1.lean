import Tests.Language.ParserSession
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.ModelV1

namespace Tests.Typed.CallGraphV1

open ProofForgeV2
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.ModelV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.CallGraphV1"

private unsafe def checkSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (Array DiagnosticV1) := do
  match ← session.selectProgramV1 source ("<call-graph-" ++ label ++ ">") moduleName none with
  | .ok validated => pure (checkProgramStructureV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def messages (diags : Array DiagnosticV1) : Array String :=
  diags.map (fun d => d.message)

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
  let msgs := messages diags
  unless contains msgs "recursive call cycle: f" do
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
  let msgs := messages diags
  unless contains msgs "recursive call cycle: f, g" do
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
  let msgs := messages diags
  unless contains msgs "recursive call cycle: a, b, c" do
    throw <| IO.userError s!"three-fn-cycle: expected cycle 'a, b, c', got {msgs}"

private unsafe def testEntryCallsFnAllowed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EntryCallsFn where\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return 1\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return helper()\n"
  let diags ← checkSource session "entry-calls-fn" source
  expectOk diags "entry-calls-fn"

private unsafe def testViewCallsFnAllowed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ViewCallsFn where\n" ++
    "  state total : UInt64\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return total\n" ++
    "  view run() : UInt64 do\n" ++
    "    return helper()\n"
  let diags ← checkSource session "view-calls-fn" source
  expectOk diags "view-calls-fn"

private unsafe def testInitCallsFnAllowed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program InitCallsFn where\n" ++
    "  state total : UInt64\n" ++
    "  fn helper(seed : UInt64) : UInt64 do\n" ++
    "    return seed\n" ++
    "  init(seed : UInt64) do\n" ++
    "    total := helper(seed)\n" ++
    "  entry get() : UInt64 do\n" ++
    "    return total\n"
  let diags ← checkSource session "init-calls-fn" source
  expectOk diags "init-calls-fn"

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

private unsafe def testUnreachableFnCycle
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnreachableCycle where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return g()\n" ++
    "  fn g() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "unreachable-cycle" source
  expectNotOk diags "unreachable-cycle"
  let msgs := messages diags
  unless contains msgs "recursive call cycle: f, g" do
    throw <| IO.userError s!"unreachable-cycle: expected cycle 'f, g', got {msgs}"

private unsafe def testCyclePlusResolutionErrorPhaseOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CyclePlusError where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return g()\n" ++
    "  fn g() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return unknownName\n"
  let diags ← checkSource session "cycle-plus-error" source
  expectNotOk diags "cycle-plus-error"
  let msgs := messages diags
  unless msgs.size >= 2 do
    throw <| IO.userError s!"cycle-plus-error: expected at least two diagnostics, got {msgs}"
  unless msgs[0]!.contains "unknown name 'unknownName'" do
    throw <| IO.userError s!"cycle-plus-error: first diagnostic should be resolution error, got {msgs}"
  unless msgs[msgs.size - 1]!.contains "recursive call cycle" do
    throw <| IO.userError s!"cycle-plus-error: last diagnostic should be cycle, got {msgs}"

private unsafe def testNoCycleThroughEntryOrView
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- entry and view cannot be local-call targets, so a fn calling an entry is
  -- rejected by name resolution, not by the call graph.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NoCycleThroughEntry where\n" ++
    "  entry e() : UInt64 do\n" ++
    "    return 0\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return e()\n"
  let diags ← checkSource session "no-cycle-through-entry" source
  expectNotOk diags "no-cycle-through-entry"
  let msgs := messages diags
  unless contains msgs "name 'e' resolved to entry but expected function" do
    throw <| IO.userError s!"no-cycle-through-entry: expected wrong-category error, got {msgs}"

private unsafe def testNestedBlockShadowsCalleeNoEdge
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestedBlockShadow where\n" ++
    "  fn helper() : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run() : UInt64 do\n" ++
    "    if true then\n" ++
    "      let helper := 0\n" ++
    "      return helper\n" ++
    "    else\n" ++
    "      return helper()\n"
  let diags ← checkSource session "nested-block-shadow" source
  expectOk diags "nested-block-shadow"

private unsafe def testTarjanBackEdgeRegression
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- a is declared first but discovered after the b↔c cycle, so the back-edge
  -- lowlink update must use the stored discovery index, not the vertex id.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TarjanRegression where\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return c()\n" ++
    "  fn b() : UInt64 do\n" ++
    "    return c()\n" ++
    "  fn c() : UInt64 do\n" ++
    "    return b()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "tarjan-regression" source
  expectNotOk diags "tarjan-regression"
  let msgs := messages diags
  unless contains msgs "recursive call cycle: b, c" do
    throw <| IO.userError s!"tarjan-regression: expected cycle 'b, c', got {msgs}"

private unsafe def testTwoDisjointCycles
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TwoDisjointCycles where\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return b()\n" ++
    "  fn b() : UInt64 do\n" ++
    "    return a()\n" ++
    "  fn c() : UInt64 do\n" ++
    "    return d()\n" ++
    "  fn d() : UInt64 do\n" ++
    "    return c()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSource session "two-disjoint-cycles" source
  expectNotOk diags "two-disjoint-cycles"
  let msgs := messages diags
  unless msgs.size == 2 do
    throw <| IO.userError s!"two-disjoint-cycles: expected two diagnostics, got {msgs}"
  -- cycles are sorted by earliest member declaration ordinal
  unless msgs[0]!.contains "recursive call cycle: a, b" do
    throw <| IO.userError s!"two-disjoint-cycles: first cycle should be a,b, got {msgs}"
  unless msgs[1]!.contains "recursive call cycle: c, d" do
    throw <| IO.userError s!"two-disjoint-cycles: second cycle should be c,d, got {msgs}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testAcyclicChain session
  testSelfRecursion session
  testTwoFnCycle session
  testThreeFnCycle session
  testEntryCallsFnAllowed session
  testViewCallsFnAllowed session
  testInitCallsFnAllowed session
  testShadowedCalleeNoEdge session
  testLocalShadowsCalleeNoEdge session
  testNestedBlockShadowsCalleeNoEdge session
  testTarjanBackEdgeRegression session
  testTwoDisjointCycles session
  testUnreachableFnCycle session
  testCyclePlusResolutionErrorPhaseOrder session
  testNoCycleThroughEntryOrView session
  IO.println "Tests.Typed.CallGraphV1: ok"

end Tests.Typed.CallGraphV1
