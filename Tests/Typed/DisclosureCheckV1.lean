/-
  Tests.Typed.DisclosureCheckV1 — D2-04b explicit + PC-label / implicit disclosure suite.

  Covers public Counter-shaped programs, private→private assign OK, private→public
  assign/return/emit/revert/call/schedule/index rejection with PF-VIS-001,
  localCall arg→param visibility (public param sink / private→private OK),
  const defining-expression public sink (private-state→const + const-return
  laundering), match/if PC-label implicit flow (private/commitment condition or
  scrutinee tainting public sinks via program-counter join), assert condition
  as public sink (no subsequent-PC raise), private→private under private PC OK,
  for-loop endpoint public sinks, commitment lattice, shadowing, default=public,
  multi-error source order, human wire, and duplicate-fn incomplete analysis
  fail-closed.

  B7b3c: draft authority erase parity — checkProgramDisclosureDraftsV1 /
  checkDisclosureDraftsV1 erase to public code/message/count/order/ok/
  analysisComplete for every existing positive/negative case (including
  duplicate-fn incomplete with no invented VIS drafts).
  Engineering subset of TST-VIS-002 implicit disclosure only; authority/custody
  and formal TST-VIS-002 / TASK-D2-04 remain pending. Does not assert full
  product CLI ceremony.
-/
import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.DisclosureCheckV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace Tests.Typed.DisclosureCheckV1

open ProofForgeV2
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.DisclosureCheckV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.DisclosureCheckV1"

private unsafe def selectValidated
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source ("<disclosure-check-" ++ label ++ ">") moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def checkSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (Array DiagnosticV1) := do
  let validated ← selectValidated session label source
  pure (checkProgramDisclosureV1 validated)

/-- B7b3c: eraseArray(drafts) matches public diagnostics on code/message/count/order
    and ok/analysisComplete. -/
private def expectEraseParity
    (label : String) (validated : ValidatedSourceV1) : IO Unit := do
  let draftRes := checkProgramDisclosureDraftsV1 validated
  let publicArr := checkProgramDisclosureV1 validated
  let publicRes := checkProgramDisclosureResultV1 validated
  let erased := eraseArray draftRes.drafts
  expect (draftRes.drafts.size == publicArr.size)
    s!"{label}: erase size parity ({draftRes.drafts.size} vs {publicArr.size})"
  expect (draftRes.ok == publicRes.ok) s!"{label}: ok parity"
  expect (draftRes.analysisComplete == publicRes.analysisComplete)
    s!"{label}: analysisComplete parity"
  expect (publicRes.diagnostics.map (·.message) == publicArr.map (·.message))
    s!"{label}: result vs array messages"
  for i in [0:publicArr.size] do
    expect (erased[i]!.code == publicArr[i]!.code) s!"{label}[{i}]: code"
    expect (erased[i]!.message == publicArr[i]!.message) s!"{label}[{i}]: message"
    expect (erased[i]!.phase == publicArr[i]!.phase) s!"{label}[{i}]: phase"
    expect (erased[i]!.primary == none) s!"{label}[{i}]: erased primary empty"
    expect (erased[i]!.related.isEmpty) s!"{label}[{i}]: erased related empty"
    expect (publicArr[i]!.primary == none) s!"{label}[{i}]: public primary empty"

private unsafe def checkSourceWithParity
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (Array DiagnosticV1) := do
  let validated ← selectValidated session label source
  expectEraseParity label validated
  pure (checkProgramDisclosureV1 validated)

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

private def expectWireVis001 (diags : Array DiagnosticV1) (label : String) : IO Unit := do
  unless diags.all (fun d => d.code.wire == "PF-VIS-001") do
    throw <| IO.userError s!"{label}: expected only PF-VIS-001 wires, got {wires diags}"

private def flowMsg (src sink : String) : String :=
  s!"disclosure violation: cannot flow '{src}' into '{sink}'"

private unsafe def testPublicCounterOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PublicCounter where\n" ++
    "  state total : UInt64\n" ++
    "  entry inc(amount : UInt64) : UInt64 do\n" ++
    "    total := total + amount\n" ++
    "    return total\n" ++
    "  view get() : UInt64 do\n" ++
    "    return total\n"
  let diags ← checkSourceWithParity session "public-counter-ok" source
  expectOk diags "public-counter-ok"

private unsafe def testPrivateLocalAssignOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateLocalOk where\n" ++
    "  state private secret : UInt64\n" ++
    "  entry set(private x : UInt64) : UInt64 do\n" ++
    "    secret := x\n" ++
    "    return 0\n"
  let diags ← checkSourceWithParity session "private-local-ok" source
  expectOk diags "private-local-ok"

private unsafe def testPrivateAssignToPublicRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateToPublicAssign where\n" ++
    "  state total : UInt64\n" ++
    "  entry set(private x : UInt64) : UInt64 do\n" ++
    "    total := x\n" ++
    "    return total\n"
  let diags ← checkSourceWithParity session "private-assign-public" source
  expectNotOk diags "private-assign-public"
  expectWireVis001 diags "private-assign-public"
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"private-assign-public: unexpected {messages diags}"

private unsafe def testPrivateReturnRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateReturn where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let diags ← checkSourceWithParity session "private-return" source
  expectNotOk diags "private-return"
  expectWireVis001 diags "private-return"
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"private-return: unexpected {messages diags}"

private unsafe def testPrivateViewReturnRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateViewReturn where\n" ++
    "  state private secret : UInt64\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return secret\n"
  let diags ← checkSourceWithParity session "private-view-return" source
  expectNotOk diags "private-view-return"
  expectWireVis001 diags "private-view-return"
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"private-view-return: unexpected {messages diags}"

private unsafe def testPrivateEmitRevertRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateEmitRevert where\n" ++
    "  event Ev(v : UInt64)\n" ++
    "  error Boom(v : UInt64)\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    emit Ev(x)\n" ++
    "    revert Boom(x)\n" ++
    "    return 0\n"
  let diags ← checkSourceWithParity session "private-emit-revert" source
  expectNotOk diags "private-emit-revert"
  expectWireVis001 diags "private-emit-revert"
  let msgs := messages diags
  -- emit then revert: two identical private→public violations in source order.
  unless msgs.size ≥ 2 do
    throw <| IO.userError s!"private-emit-revert: expected ≥2 diags, got {msgs}"
  unless msgs[0]! == flowMsg "private" "public"
      && msgs[1]! == flowMsg "private" "public" do
    throw <| IO.userError s!"private-emit-revert: unexpected {msgs}"

private unsafe def testPrivateCallScheduleRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateCallSchedule where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    call External.Use(x)\n" ++
    "    schedule External.Later(x)\n" ++
    "    return 0\n"
  let diags ← checkSourceWithParity session "private-call-schedule" source
  expectNotOk diags "private-call-schedule"
  expectWireVis001 diags "private-call-schedule"
  let msgs := messages diags
  unless msgs.size ≥ 2 do
    throw <| IO.userError s!"private-call-schedule: expected ≥2 diags, got {msgs}"
  unless msgs[0]! == flowMsg "private" "public"
      && msgs[1]! == flowMsg "private" "public" do
    throw <| IO.userError s!"private-call-schedule: unexpected {msgs}"

private unsafe def testPrivateIndexRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateIndex where\n" ++
    "  state arr : Array UInt64 2\n" ++
    "  entry run(private i : UInt64) : UInt64 do\n" ++
    "    return arr[i]\n"
  let diags ← checkSourceWithParity session "private-index" source
  expectNotOk diags "private-index"
  expectWireVis001 diags "private-index"
  -- Index is a public-required sink; joined rvalue is also private → return sink.
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"private-index: unexpected {messages diags}"
  unless (messages diags).size ≥ 1 do
    throw <| IO.userError s!"private-index: expected at least one diag"

private unsafe def testCommitmentLattice
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- commitment → public rejected
  let toPublic :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CommitmentToPublic where\n" ++
    "  state total : UInt64\n" ++
    "  entry set(commitment x : UInt64) : UInt64 do\n" ++
    "    total := x\n" ++
    "    return 0\n"
  let d1 ← checkSourceWithParity session "commitment-to-public" toPublic
  expectNotOk d1 "commitment-to-public"
  expectWireVis001 d1 "commitment-to-public"
  unless contains (messages d1) (flowMsg "commitment" "public") do
    throw <| IO.userError s!"commitment-to-public: unexpected {messages d1}"

  -- commitment → commitment OK
  let toCommit :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CommitmentToCommitment where\n" ++
    "  state commitment note : UInt64\n" ++
    "  entry set(commitment x : UInt64) : UInt64 do\n" ++
    "    note := x\n" ++
    "    return 0\n"
  let d2 ← checkSourceWithParity session "commitment-to-commitment" toCommit
  expectOk d2 "commitment-to-commitment"

  -- private → commitment rejected
  let privToCommit :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateToCommitment where\n" ++
    "  state commitment note : UInt64\n" ++
    "  entry set(private x : UInt64) : UInt64 do\n" ++
    "    note := x\n" ++
    "    return 0\n"
  let d3 ← checkSourceWithParity session "private-to-commitment" privToCommit
  expectNotOk d3 "private-to-commitment"
  expectWireVis001 d3 "private-to-commitment"
  unless contains (messages d3) (flowMsg "private" "commitment") do
    throw <| IO.userError s!"private-to-commitment: unexpected {messages d3}"

  -- public → private OK
  let pubToPriv :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PublicToPrivate where\n" ++
    "  state private secret : UInt64\n" ++
    "  entry set(amount : UInt64) : UInt64 do\n" ++
    "    secret := amount\n" ++
    "    return 0\n"
  let d4 ← checkSourceWithParity session "public-to-private" pubToPriv
  expectOk d4 "public-to-private"

private unsafe def testShadowingLocalDoesNotLeakState
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Local let `total` shadows private state; public RHS local flowing to public return is OK.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ShadowState where\n" ++
    "  state private total : UInt64\n" ++
    "  entry run(amount : UInt64) : UInt64 do\n" ++
    "    let total : UInt64 := amount\n" ++
    "    return total\n"
  let diags ← checkSourceWithParity session "shadow-state" source
  expectOk diags "shadow-state"

  -- Param named like public state, private param must not assign to state via unshadowed name...
  -- and must not false-negative: assigning private param to distinct public state fails.
  let neg :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ShadowParamNeg where\n" ++
    "  state private secret : UInt64\n" ++
    "  state public_total : UInt64\n" ++
    "  entry run(private secret : UInt64) : UInt64 do\n" ++
    "    public_total := secret\n" ++
    "    return 0\n"
  let dNeg ← checkSourceWithParity session "shadow-param-neg" neg
  expectNotOk dNeg "shadow-param-neg"
  expectWireVis001 dNeg "shadow-param-neg"
  unless contains (messages dNeg) (flowMsg "private" "public") do
    throw <| IO.userError s!"shadow-param-neg: unexpected {messages dNeg}"

private unsafe def testHumanRenderUsesVisWire
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program HumanWire where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let diags ← checkSourceWithParity session "human-wire" source
  expectNotOk diags "human-wire"
  let rendered := diags.map (·.renderHuman)
  unless rendered.any (·.startsWith "PF-VIS-001:") do
    throw <| IO.userError s!"human-wire: expected PF-VIS-001 human line, got {rendered}"

private unsafe def testDefaultVisibilityIsPublic
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Omitted visibility on state/param behaves as public: private cannot flow in.
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DefaultPublic where\n" ++
    "  state total : UInt64\n" ++
    "  entry set(private x : UInt64) : UInt64 do\n" ++
    "    total := x\n" ++
    "    return 0\n"
  let diags ← checkSourceWithParity session "default-public" source
  expectNotOk diags "default-public"
  expectWireVis001 diags "default-public"
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"default-public: unexpected {messages diags}"

  -- Explicit public matches default.
  let explicit :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ExplicitPublic where\n" ++
    "  state public total : UInt64\n" ++
    "  entry set(public amount : UInt64) : UInt64 do\n" ++
    "    total := amount\n" ++
    "    return total\n"
  let d2 ← checkSourceWithParity session "explicit-public" explicit
  expectOk d2 "explicit-public"

private unsafe def testMultiErrorSourceOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MultiError where\n" ++
    "  state a : UInt64\n" ++
    "  state b : UInt64\n" ++
    "  entry run(private x : UInt64, commitment y : UInt64) : UInt64 do\n" ++
    "    a := x\n" ++
    "    b := y\n" ++
    "    return 0\n"
  let diags ← checkSourceWithParity session "multi-error" source
  expectNotOk diags "multi-error"
  expectWireVis001 diags "multi-error"
  let msgs := messages diags
  unless msgs.size ≥ 2 do
    throw <| IO.userError s!"multi-error: expected ≥2 diags, got {msgs}"
  unless msgs[0]! == flowMsg "private" "public" do
    throw <| IO.userError s!"multi-error: first should be private→public, got {msgs}"
  unless msgs[1]! == flowMsg "commitment" "public" do
    throw <| IO.userError s!"multi-error: second should be commitment→public, got {msgs}"

private def mkName (raw : String) : IO SourceNameComponentV1 :=
  match parseSourceNameComponentV1 raw with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"mkName: {e}"

/-- Duplicate fn keys: analysisComplete=false fail closed (Effect/Bound pattern). -/
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
  let draftRes := checkDisclosureDraftsV1 progAst tables
  unless !draftRes.analysisComplete do
    throw <| IO.userError "dup-fn: expected draft analysisComplete = false"
  unless !draftRes.ok do
    throw <| IO.userError "dup-fn: expected draft ok = false"
  unless draftRes.drafts.isEmpty do
    throw <| IO.userError s!"dup-fn: expected no VIS drafts, got {draftRes.drafts.size}"
  let res := checkDisclosureV1 progAst tables
  unless !res.analysisComplete do
    throw <| IO.userError "dup-fn: expected analysisComplete = false"
  unless !res.ok do
    throw <| IO.userError "dup-fn: expected ok = false"
  unless res.diagnostics.isEmpty do
    throw <| IO.userError s!"dup-fn: expected no flow diagnostics, got {messages res.diagnostics}"
  -- Public erase of incomplete drafts is empty (no invented VIS).
  expect (eraseArray draftRes.drafts).isEmpty "dup-fn: erase of incomplete empty"
  let composed :=
    if res.analysisComplete then res.diagnostics
    else st.diagnostics ++ res.diagnostics
  expectNotOk composed "dup-fn-composed"
  unless contains (messages composed) "duplicate fn declaration 'helper'" do
    throw <| IO.userError s!"dup-fn-composed: expected structural diagnostic, got {messages composed}"

private unsafe def testPrivateLetFlowsToPublicAssign
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateLet where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    let y : UInt64 := x\n" ++
    "    total := y\n" ++
    "    return 0\n"
  let diags ← checkSourceWithParity session "private-let" source
  expectNotOk diags "private-let"
  expectWireVis001 diags "private-let"
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"private-let: unexpected {messages diags}"

/-- Private/commitment args into default-public fn params are explicit sinks. -/
private unsafe def testLocalCallArgIntoPublicParamRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Discarded call: private arg into public param must still PF-VIS-001.
  let discarded :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocalCallPublicParam where\n" ++
    "  fn drop(x : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run(private secret : UInt64) : UInt64 do\n" ++
    "    let y : UInt64 := drop(secret)\n" ++
    "    return 0\n"
  let d1 ← checkSourceWithParity session "local-call-public-param" discarded
  expectNotOk d1 "local-call-public-param"
  expectWireVis001 d1 "local-call-public-param"
  unless contains (messages d1) (flowMsg "private" "public") do
    throw <| IO.userError s!"local-call-public-param: unexpected {messages d1}"

  -- Commitment arg into public param.
  let commitArg :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocalCallCommitParam where\n" ++
    "  fn drop(x : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run(commitment note : UInt64) : UInt64 do\n" ++
    "    let y : UInt64 := drop(note)\n" ++
    "    return 0\n"
  let d2 ← checkSourceWithParity session "local-call-commit-param" commitArg
  expectNotOk d2 "local-call-commit-param"
  expectWireVis001 d2 "local-call-commit-param"
  unless contains (messages d2) (flowMsg "commitment" "public") do
    throw <| IO.userError s!"local-call-commit-param: unexpected {messages d2}"

/-- Private arg into private param is an allowed explicit flow. -/
private unsafe def testLocalCallPrivateToPrivateParamOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LocalCallPrivateParam where\n" ++
    "  fn drop(private x : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run(private secret : UInt64) : UInt64 do\n" ++
    "    let y : UInt64 := drop(secret)\n" ++
    "    return y\n"
  let diags ← checkSourceWithParity session "local-call-private-param" source
  expectOk diags "local-call-private-param"

/-- Const defining expression is a public sink; private state cannot initialize it. -/
private unsafe def testConstPrivateStateRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ConstPrivateState where\n" ++
    "  state private secret : UInt64\n" ++
    "  const leak : UInt64 := secret\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let diags ← checkSourceWithParity session "const-private-state" source
  expectNotOk diags "const-private-state"
  expectWireVis001 diags "const-private-state"
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"const-private-state: unexpected {messages diags}"

/-- Const→return laundering of private state is rejected at the const definition. -/
private unsafe def testConstReturnLaunderingRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ConstReturnLaunder where\n" ++
    "  state private secret : UInt64\n" ++
    "  const leak : UInt64 := secret\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return leak\n"
  let diags ← checkSourceWithParity session "const-return-launder" source
  expectNotOk diags "const-return-launder"
  expectWireVis001 diags "const-return-launder"
  unless contains (messages diags) (flowMsg "private" "public") do
    throw <| IO.userError s!"const-return-launder: unexpected {messages diags}"

/-- D2-04b: private scrutinee raises PC; public return arms are PF-VIS-001.
    Expression match joins scrutVis into result. Binder leak remains value-flow. -/
private unsafe def testMatchPrivateScrutineePublicArmsRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let stmt :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MatchStmtPrivateScrut where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    match flag with\n" ++
    "    | true => do\n" ++
    "      return 1\n" ++
    "    | false => do\n" ++
    "      return 0\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let d1 ← checkSourceWithParity session "match-stmt-private-scrut" stmt
  expectNotOk d1 "match-stmt-private-scrut"
  expectWireVis001 d1 "match-stmt-private-scrut"
  unless contains (messages d1) (flowMsg "private" "public") do
    throw <| IO.userError s!"match-stmt-private-scrut: unexpected {messages d1}"

  let expr :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MatchExprPrivateScrut where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    return\n" ++
    "      match flag with\n" ++
    "      | true => 1\n" ++
    "      | false => 0\n" ++
    "      | _ => 0\n"
  let d2 ← checkSourceWithParity session "match-expr-private-scrut" expr
  expectNotOk d2 "match-expr-private-scrut"
  expectWireVis001 d2 "match-expr-private-scrut"
  unless contains (messages d2) (flowMsg "private" "public") do
    throw <| IO.userError s!"match-expr-private-scrut: unexpected {messages d2}"

  -- Binder inherits private scrutinee: returning the binder is still a violation.
  let binderLeak :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MatchBinderLeak where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return\n" ++
    "      match x with\n" ++
    "      | y => y\n" ++
    "      | _ => 0\n"
  let d3 ← checkSourceWithParity session "match-binder-leak" binderLeak
  expectNotOk d3 "match-binder-leak"
  expectWireVis001 d3 "match-binder-leak"
  unless contains (messages d3) (flowMsg "private" "public") do
    throw <| IO.userError s!"match-binder-leak: unexpected {messages d3}"

  -- Public scrutinee + public arms remains OK (no regression).
  let pubMatch :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MatchPublicScrut where\n" ++
    "  entry run(flag : Bool) : UInt64 do\n" ++
    "    match flag with\n" ++
    "    | true => do\n" ++
    "      return 1\n" ++
    "    | false => do\n" ++
    "      return 0\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let d4 ← checkSourceWithParity session "match-public-scrut" pubMatch
  expectOk d4 "match-public-scrut"

/-- D2-04b PC-label: private/commitment if conditions taint public sinks. -/
private unsafe def testIfPrivateConditionPublicSinksRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- private if then return public literal
  let retLit :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program IfPrivateReturnLit where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      return 1\n" ++
    "    else\n" ++
    "      return 0\n"
  let d1 ← checkSourceWithParity session "if-private-return" retLit
  expectNotOk d1 "if-private-return"
  expectWireVis001 d1 "if-private-return"
  unless contains (messages d1) (flowMsg "private" "public") do
    throw <| IO.userError s!"if-private-return: unexpected {messages d1}"

  -- private if then assign public state with public literal (PC taint, not value)
  let assignPub :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program IfPrivateAssignPublic where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      total := 1\n" ++
    "    return total\n"
  let d2 ← checkSourceWithParity session "if-private-assign-public" assignPub
  expectNotOk d2 "if-private-assign-public"
  expectWireVis001 d2 "if-private-assign-public"
  unless contains (messages d2) (flowMsg "private" "public") do
    throw <| IO.userError s!"if-private-assign-public: unexpected {messages d2}"

  -- commitment condition writing public state
  let commitIf :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program IfCommitAssignPublic where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(commitment flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      total := 1\n" ++
    "    return total\n"
  let d3 ← checkSourceWithParity session "if-commit-assign-public" commitIf
  expectNotOk d3 "if-commit-assign-public"
  expectWireVis001 d3 "if-commit-assign-public"
  unless contains (messages d3) (flowMsg "commitment" "public") do
    throw <| IO.userError s!"if-commit-assign-public: unexpected {messages d3}"

  -- private if then emit / revert / call / schedule with public args
  let effects :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program IfPrivateEffects where\n" ++
    "  error E(x : UInt64)\n" ++
    "  event Ev(x : UInt64)\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      emit Ev(0)\n" ++
    "      revert E(0)\n" ++
    "      call External.Use(0)\n" ++
    "      schedule External.Later(0)\n" ++
    "    return 0\n"
  let d4 ← checkSourceWithParity session "if-private-effects" effects
  expectNotOk d4 "if-private-effects"
  expectWireVis001 d4 "if-private-effects"
  unless contains (messages d4) (flowMsg "private" "public") do
    throw <| IO.userError s!"if-private-effects: unexpected {messages d4}"
  unless (messages d4).size ≥ 4 do
    throw <| IO.userError s!"if-private-effects: expected ≥4 PC sinks, got {messages d4}"

  -- private if then private_state := private_param is OK (private→private under private PC)
  let privOk :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program IfPrivateToPrivateOk where\n" ++
    "  state private secret : UInt64\n" ++
    "  entry run(private flag : Bool, private x : UInt64) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      secret := x\n" ++
    "    return 0\n"
  let d5 ← checkSourceWithParity session "if-private-to-private" privOk
  expectOk d5 "if-private-to-private"

  -- public if with public sinks OK
  let pubIf :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program IfPublicOk where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      total := 1\n" ++
    "      return 1\n" ++
    "    else\n" ++
    "      return 0\n"
  let d6 ← checkSourceWithParity session "if-public-ok" pubIf
  expectOk d6 "if-public-ok"

  -- Explicit private→public assign without branch still fails (value flow).
  let explicit :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ExplicitStillFails where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    total := x\n" ++
    "    return 0\n"
  let d7 ← checkSourceWithParity session "explicit-no-branch" explicit
  expectNotOk d7 "explicit-no-branch"
  expectWireVis001 d7 "explicit-no-branch"
  unless contains (messages d7) (flowMsg "private" "public") do
    throw <| IO.userError s!"explicit-no-branch: unexpected {messages d7}"

/-- Public assert condition is a public sink but does not raise PC for later
    statements: subsequent public sinks remain OK. Private/commitment assert
    conditions fail closed with PF-VIS-001 (assert ⇒ failure.revert / observable). -/
private unsafe def testAssertConditionPublicSinkNoPcRaise
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Public assert does not taint later public assign/return.
  let pubOk :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AssertPublicOk where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(flag : Bool) : UInt64 do\n" ++
    "    assert flag\n" ++
    "    total := 1\n" ++
    "    return total\n"
  let d0 ← checkSourceWithParity session "assert-public-ok" pubOk
  expectOk d0 "assert-public-ok"

  -- Private assert condition is itself a public-effect sink.
  let priv :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AssertPrivateCond where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    assert flag\n" ++
    "    total := 1\n" ++
    "    return total\n"
  let d1 ← checkSourceWithParity session "assert-private-cond" priv
  expectNotOk d1 "assert-private-cond"
  expectWireVis001 d1 "assert-private-cond"
  unless contains (messages d1) (flowMsg "private" "public") do
    throw <| IO.userError s!"assert-private-cond: unexpected {messages d1}"

  -- Private assert alone (no later public assign) still PF-VIS-001.
  let privOnly :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AssertPrivateOnly where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    assert flag\n" ++
    "    return 0\n"
  let d2 ← checkSourceWithParity session "assert-private-only" privOnly
  expectNotOk d2 "assert-private-only"
  expectWireVis001 d2 "assert-private-only"
  unless contains (messages d2) (flowMsg "private" "public") do
    throw <| IO.userError s!"assert-private-only: unexpected {messages d2}"

  -- Commitment assert condition likewise rejects.
  let commit :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AssertCommitCond where\n" ++
    "  entry run(commitment flag : Bool) : UInt64 do\n" ++
    "    assert flag\n" ++
    "    return 0\n"
  let d3 ← checkSourceWithParity session "assert-commit-cond" commit
  expectNotOk d3 "assert-commit-cond"
  expectWireVis001 d3 "assert-commit-cond"
  unless contains (messages d3) (flowMsg "commitment" "public") do
    throw <| IO.userError s!"assert-commit-cond: unexpected {messages d3}"

/-- for-loop start/endExclusive are public-required sinks; binder is public_. -/
private unsafe def testForEndpointsPublicSink
    (session : Language.Loader.ParserSession) : IO Unit := do
  let privStart :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ForPrivStart where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private priv : UInt64, n : UInt64) : UInt64 do\n" ++
    "    for i in priv ..< n bounded 10 do\n" ++
    "      total := i\n" ++
    "    return total\n"
  let d1 ← checkSourceWithParity session "for-priv-start" privStart
  expectNotOk d1 "for-priv-start"
  expectWireVis001 d1 "for-priv-start"
  unless contains (messages d1) (flowMsg "private" "public") do
    throw <| IO.userError s!"for-priv-start: unexpected {messages d1}"

  let privEnd :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ForPrivEnd where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private priv : UInt64) : UInt64 do\n" ++
    "    for i in 0 ..< priv bounded 10 do\n" ++
    "      total := i\n" ++
    "    return total\n"
  let d2 ← checkSourceWithParity session "for-priv-end" privEnd
  expectNotOk d2 "for-priv-end"
  expectWireVis001 d2 "for-priv-end"
  unless contains (messages d2) (flowMsg "private" "public") do
    throw <| IO.userError s!"for-priv-end: unexpected {messages d2}"

  let commitEnd :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ForCommitEnd where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(commitment note : UInt64) : UInt64 do\n" ++
    "    for i in 0 ..< note bounded 10 do\n" ++
    "      total := i\n" ++
    "    return total\n"
  let d3 ← checkSourceWithParity session "for-commit-end" commitEnd
  expectNotOk d3 "for-commit-end"
  expectWireVis001 d3 "for-commit-end"
  unless contains (messages d3) (flowMsg "commitment" "public") do
    throw <| IO.userError s!"for-commit-end: unexpected {messages d3}"

  -- Public endpoints OK; binder is public_ so assigning binder to public state OK.
  let pubOk :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ForPublicOk where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(n : UInt64) : UInt64 do\n" ++
    "    for i in 0 ..< n bounded 10 do\n" ++
    "      total := i\n" ++
    "    return total\n"
  let d4 ← checkSourceWithParity session "for-public-ok" pubOk
  expectOk d4 "for-public-ok"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testPublicCounterOk session
  testPrivateLocalAssignOk session
  testPrivateAssignToPublicRejected session
  testPrivateReturnRejected session
  testPrivateViewReturnRejected session
  testPrivateEmitRevertRejected session
  testPrivateCallScheduleRejected session
  testPrivateIndexRejected session
  testCommitmentLattice session
  testShadowingLocalDoesNotLeakState session
  testHumanRenderUsesVisWire session
  testDefaultVisibilityIsPublic session
  testMultiErrorSourceOrder session
  testDuplicateFnFailClosed session
  testPrivateLetFlowsToPublicAssign session
  testLocalCallArgIntoPublicParamRejected session
  testLocalCallPrivateToPrivateParamOk session
  testConstPrivateStateRejected session
  testConstReturnLaunderingRejected session
  testMatchPrivateScrutineePublicArmsRejected session
  testIfPrivateConditionPublicSinksRejected session
  testAssertConditionPublicSinkNoPcRaise session
  testForEndpointsPublicSink session
  IO.println "Tests.Typed.DisclosureCheckV1: ok"

end Tests.Typed.DisclosureCheckV1
