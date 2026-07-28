/-
  B7b1 + B7b2 + B7b3a + B7b3b + B7b3c: Typed diagnostic-draft path materialization
  through B7a OriginInventoryV1.

  B7b1 (name-resolution / call-graph):
  * unknown Place.Name primary path
  * nested Type.Named (Array/Option) primary path
  * later-primary + first-related duplicate declarations
  * wrong-category related declaration item
  * struct name + enum-variant constructor ambiguity related (Bar EnumDecl)
  * self / two-fn cycles with declaration + callsite related paths
  * stableContext tokens (typed.nr.* / typed.callgraph.cycle)
  * resolution-before-callgraph phase order after erase

  B7b2 (TypeCheckV1 families):
  * places / patterns / expressions / match exhaust+arm / statements /
    const / callable / invariant drafts with primary (+ related for decl contracts)
  * typeCheckProgramDraftsV1 erase parity vs typeCheckProgramV1
  * resolution-not-ok short-circuit erase parity
  * every draft path ∈ canonicalNodeVisitsV1
  * locate via selectProgramV1WithOrigins → exact real NodeIds

  B7b3a (EffectCheckV1 producer paths):
  * direct fn state.read/write + emit/call/schedule/assert/revert sites
  * multi-effect EffectKind order + primary FnDecl/ViewDecl
  * view disallow vs view-ok state.read
  * transitive 1-hop / multi-hop causal related (direct ∪ effect-carrying LocalCall)
  * duplicate callsites retained; cycle finite; shadowing; incomplete dup-fn
  * every draft path ∈ canonicalNodeVisitsV1; locate exact NodeId sets
  * public checkProgramEffects* erase parity on code/message/order/ok/analysisComplete

  B7b3b (BoundCheckV1 producer paths):
  * self / 2- / 3-fn recursion cycles: primary min-ordinal FnDecl; related =
    remaining SCC FnDecls (ordinal) + in-SCC Expr.LocalCall sites (source order)
  * loop-product overflow: primary overflowing Stmt.For; related = enclosing
    callable item + ancestor Stmt.For (fn/entry/view/init; if/match; siblings)
  * every draft path ∈ canonicalNodeVisitsV1; locate exact NodeId sets
  * public checkProgramBounds* erase parity on code/message/order/ok/analysisComplete
  * duplicate-fn incomplete: no invented bound drafts

  B7b3c (DisclosureCheckV1 producer paths):
  * explicit sinks: assign/return/emit/revert/call/schedule/index/for/assert/const
  * localCall → fn Param; state/param/local/const provenance + shadowing
  * statement/expression match + binders; nested if/match PC taint + restore
  * B7b3cR: if/match related includes exact condition/scrutinee Expr root
    (+ Param/State decl causes); nested equal-private keeps both control roots;
    nested lower-secrecy under more-secret outer excludes inner control;
    primary/erase/code/message/count/order/ok/analysisComplete unchanged
  * equal-label cause union; multi-error order; exact primary/related NodeIds
  * every draft path ∈ canonicalNodeVisitsV1; VisibilityEvidence label parity
  * public checkProgramDisclosure* erase parity; duplicate-fn incomplete
-/
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DiagnosticLocateV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.BoundCheckV1
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.DisclosureCheckV1
import ProofForgeV2.Typed.EffectCheckV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

namespace Tests.Typed.DiagnosticLocationsV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DiagnosticLocateV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.BoundCheckV1
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.DisclosureCheckV1
open ProofForgeV2.Typed.EffectCheckV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1
open ProofForgeV2.Typed.TypeCheckV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def moduleName : String := "Tests.DiagnosticLocationsV1"

private def mkName (raw : String) : IO SourceNameComponentV1 :=
  match parseSourceNameComponentV1 raw with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"mkName: {e}"

private unsafe def selectWithOrigins
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × OriginInventoryV1) := do
  match ← session.selectProgramV1WithOrigins
      source ("tests/diag-loc-" ++ label ++ ".pf") moduleName none with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def pathInVisits
    (visits : Array NodeVisitV1) (path : NormalizedSyntacticPathV1) : Bool :=
  visits.any (·.path == path)

private def requireLocation
    (label : String) (draft : TypedDiagnosticDraftV1) : IO DiagnosticLocationDraftV1 :=
  match draft.location with
  | some loc => pure loc
  | none => throw <| IO.userError s!"{label}: expected location draft, got none"

private def eraseParity
    (label : String) (drafts : Array TypedDiagnosticDraftV1)
    (erased : Array DiagnosticV1) : IO Unit := do
  expect (drafts.size == erased.size) s!"{label}: erase size parity"
  for i in [0:drafts.size] do
    let d := drafts[i]!
    let e := erased[i]!
    expect (d.diagnostic.code == e.code) s!"{label}[{i}]: code parity"
    expect (d.diagnostic.message == e.message) s!"{label}[{i}]: message parity"
    expect (d.diagnostic.phase == e.phase) s!"{label}[{i}]: phase parity"
    expect (e.primary == none) s!"{label}[{i}]: erased primary empty"
    expect (e.related.isEmpty) s!"{label}[{i}]: erased related empty"

private def locateAll
    (label : String) (inv : OriginInventoryV1)
    (drafts : Array TypedDiagnosticDraftV1) : IO (Array DiagnosticV1) :=
  match locateArray inv drafts with
  | .ok located => pure located
  | .error err =>
      throw <| IO.userError s!"{label}: locateArray failed: {repr err}"

private def expectNodeIdSome
    (label : String) (origin : Option DiagnosticOriginV1) : IO NodeId :=
  match origin with
  | none => throw <| IO.userError s!"{label}: expected some primary origin"
  | some o =>
      match o.nodeId with
      | none => throw <| IO.userError s!"{label}: expected nodeId=some"
      | some id => pure id

private def inventoryNodeId
    (inv : OriginInventoryV1) (path : NormalizedSyntacticPathV1) (label : String) :
    IO NodeId :=
  match originInventoryLookupPathV1 inv path with
  | none => throw <| IO.userError s!"{label}: path missing from inventory"
  | some origin => pure origin.nodeId

/-- Set equality of NodeIds: each draft related path materializes to a NodeId that
    appears in located.related, and every located related NodeId is the inventory
    id of some draft related path. Order-insensitive (normalizeRelated may reorder). -/
private def expectRelatedNodeIdSet
    (label : String) (inv : OriginInventoryV1)
    (relatedOrigins : Array DiagnosticOriginV1)
    (relatedPaths : Array NormalizedSyntacticPathV1) : IO Unit := do
  let mut expected : Array NodeId := #[]
  for (path, i) in relatedPaths.zipIdx do
    let id ← inventoryNodeId inv path s!"{label} relatedPath[{i}]"
    unless expected.any (· == id) do
      expected := expected.push id
  let mut actual : Array NodeId := #[]
  for (origin, i) in relatedOrigins.zipIdx do
    match origin.nodeId with
    | none => throw <| IO.userError s!"{label}: related[{i}] nodeId=none"
    | some id =>
        unless actual.any (· == id) do
          actual := actual.push id
  expect (expected.size == actual.size)
    s!"{label}: related NodeId unique-set size (expected={expected.size} actual={actual.size})"
  for id in expected do
    expect (actual.any (· == id))
      s!"{label}: draft-path NodeId missing from located.related"
  for id in actual do
    expect (expected.any (· == id))
      s!"{label}: located related NodeId not from any draft relatedPath"

private def expectStableContext
    (label : String) (draft : TypedDiagnosticDraftV1) (token : String) : IO Unit :=
  expect (draft.diagnostic.stableContext == some token)
    s!"{label}: stableContext want {token} got {repr draft.diagnostic.stableContext}"

/-- Unknown Place.Name: primary at Place.Name; no related; locate exact NodeId. -/
private unsafe def testUnknownPlaceName
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program UnknownPlace where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return missing\n"
  let (validated, inv) ← selectWithOrigins session "unknown-place" source
  let draftResult := resolveProgramDraftsV1 validated
  expect (!draftResult.ok) "unknown-place: not ok"
  expect (draftResult.drafts.size == 1) "unknown-place: one draft"
  let draft := draftResult.drafts[0]!
  expect (draft.diagnostic.message == "unknown name 'missing' (expected value)")
    "unknown-place: message"
  expect (draft.diagnostic.code == .sourceInvalid) "unknown-place: code"
  expectStableContext "unknown-place" draft stableUnknownName
  let loc ← requireLocation "unknown-place" draft
  expect (loc.relatedPaths.isEmpty) "unknown-place: no related"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (pathInVisits visits loc.primaryPath)
    "unknown-place: primary ∈ canonicalNodeVisitsV1"
  let some visit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "unknown-place: visit lookup"
  expect (visit.constructorTag == "Place.Name")
    "unknown-place: primary tag Place.Name"
  let erased := eraseArray draftResult.drafts
  eraseParity "unknown-place" draftResult.drafts erased
  let publicResult := resolveProgramV1 validated
  expect (publicResult.diagnostics.map (·.message) == erased.map (·.message))
    "unknown-place: public erase projection messages"
  let located ← locateAll "unknown-place" inv draftResult.drafts
  let primaryId ← expectNodeIdSome "unknown-place" located[0]!.primary
  let expectedId ← inventoryNodeId inv loc.primaryPath "unknown-place"
  expect (primaryId == expectedId) "unknown-place: primary NodeId exact"

/-- Nested Type.Named under Array: primary is Type.Named leaf, not Array. -/
private unsafe def testRecursiveTypeNamed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestedNamed where\n" ++
    "  state bag : Array MissingType 4\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv) ← selectWithOrigins session "nested-named" source
  let draftResult := resolveProgramDraftsV1 validated
  expect (!draftResult.ok) "nested-named: not ok"
  expect (draftResult.drafts.size ≥ 1) "nested-named: ≥1 draft"
  let draft := draftResult.drafts[0]!
  expect (draft.diagnostic.message == "unknown name 'MissingType' (expected type)")
    "nested-named: message"
  let loc ← requireLocation "nested-named" draft
  expect (loc.relatedPaths.isEmpty) "nested-named: no related"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (pathInVisits visits loc.primaryPath)
    "nested-named: primary ∈ visits"
  let some visit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "nested-named: visit lookup"
  expect (visit.constructorTag == "Type.Named")
    "nested-named: primary tag Type.Named"
  let located ← locateAll "nested-named" inv draftResult.drafts
  let primaryId ← expectNodeIdSome "nested-named" located[0]!.primary
  let expectedId ← inventoryNodeId inv loc.primaryPath "nested-named"
  expect (primaryId == expectedId) "nested-named: NodeId exact"

/-- Duplicate state: later item primary, first item related.
    ValidatedSourceV1 rejects duplicate decl-sets, so this uses raw ProgramV1
    + buildTables (same pattern as BoundCheck/CheckV1 incomplete-analysis tests).
    Paths are still checked against canonicalNodeVisitsV1; inventory locate is
    covered by Loader-admitted fixtures elsewhere in this suite. -/
private unsafe def testDuplicateLaterFirst
    (_session : Language.Loader.ParserSession) : IO Unit := do
  let progName ← mkName "DupState"
  let total ← mkName "total"
  let runName ← mkName "run"
  let u64 : TypeV1 := .uint 64
  let stateA : StateDeclV1 := {
    name := total
    type_ := u64
    visibility := .public_
  }
  let stateB : StateDeclV1 := {
    name := total
    type_ := u64
    visibility := .public_
  }
  let entryDecl : EntryDeclV1 := {
    name := runName
    params := #[]
    result := u64
    body := { statements := #[.return_ (some (.literal (.integer 0)))] }
  }
  let progAst : ProgramV1 := {
    name := progName
    items := #[.state stateA, .state stateB, .entry entryDecl]
  }
  let (tables, st) := (buildTables progAst).run {}
  expect tables.state.hasDuplicateKey "dup-state: hasDuplicateKey"
  expect (st.drafts.size ≥ 1) "dup-state: ≥1 draft"
  let some draft := st.drafts.find?
      (·.diagnostic.message == "duplicate state declaration 'total'") |
    throw <| IO.userError s!"dup-state: missing duplicate draft, got {st.drafts.map (·.diagnostic.message)}"
  expectStableContext "dup-state" draft stableDuplicateDecl
  let loc ← requireLocation "dup-state" draft
  expect (loc.relatedPaths.size == 1) "dup-state: one related"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 progAst)
  expect (pathInVisits visits loc.primaryPath) "dup-state: primary ∈ visits"
  expect (pathInVisits visits loc.relatedPaths[0]!) "dup-state: related ∈ visits"
  let some primaryVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "dup-state: primary visit"
  let some relatedVisit := visits.find? (·.path == loc.relatedPaths[0]!) |
    throw <| IO.userError "dup-state: related visit"
  expect (primaryVisit.constructorTag == "StateDecl") "dup-state: primary StateDecl"
  expect (relatedVisit.constructorTag == "StateDecl") "dup-state: related StateDecl"
  let firstPath ← liftResult "first" (indexChildPathV1 #[] "Program" "items" 0)
  let laterPath ← liftResult "later" (indexChildPathV1 #[] "Program" "items" 1)
  expect (loc.primaryPath == laterPath) "dup-state: primary is later item"
  expect (loc.relatedPaths[0]! == firstPath) "dup-state: related is first item"
  eraseParity "dup-state" st.drafts st.diagnostics

/-- Wrong category function use: related points at declaration item. -/
private unsafe def testWrongCategoryRelated
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WrongCat where\n" ++
    "  state s : UInt64\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return s()\n"
  let (validated, inv) ← selectWithOrigins session "wrong-cat" source
  let draftResult := resolveProgramDraftsV1 validated
  expect (!draftResult.ok) "wrong-cat: not ok"
  let some draft := draftResult.drafts.find?
      (·.diagnostic.message == "name 's' resolved to state but expected function") |
    throw <| IO.userError s!"wrong-cat: missing draft, got {draftResult.drafts.map (·.diagnostic.message)}"
  expectStableContext "wrong-cat" draft stableWrongCategory
  let loc ← requireLocation "wrong-cat" draft
  expect (loc.relatedPaths.size == 1) "wrong-cat: one related"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (pathInVisits visits loc.primaryPath) "wrong-cat: primary ∈ visits"
  expect (pathInVisits visits loc.relatedPaths[0]!) "wrong-cat: related ∈ visits"
  let some primaryVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "wrong-cat: primary visit"
  let some relatedVisit := visits.find? (·.path == loc.relatedPaths[0]!) |
    throw <| IO.userError "wrong-cat: related visit"
  expect (primaryVisit.constructorTag == "Expr.LocalCall")
    "wrong-cat: primary LocalCall"
  expect (relatedVisit.constructorTag == "StateDecl")
    "wrong-cat: related StateDecl"
  let statePath ← liftResult "state" (indexChildPathV1 #[] "Program" "items" 0)
  expect (loc.relatedPaths[0]! == statePath) "wrong-cat: related is state item"
  let located ← locateAll "wrong-cat" inv #[draft]
  let primaryId ← expectNodeIdSome "wrong-cat" located[0]!.primary
  expect (primaryId == (← inventoryNodeId inv loc.primaryPath "wrong-cat primary"))
    "wrong-cat: primary NodeId"
  match located[0]!.related[0]!.nodeId with
  | none => throw <| IO.userError "wrong-cat: related nodeId none"
  | some rid =>
      expect (rid == (← inventoryNodeId inv statePath "wrong-cat related"))
        "wrong-cat: related NodeId"

/-- struct Foo + enum Bar | Foo: single-component constructor related must include
    Bar EnumDecl (variant owner), not EnumDecl named Foo.
    Wire/qid encoding requires 2+ components on constructor paths, so the site is
    a constructed ProgramV1; resolution walks public buildTables+resolveItem (same
    authority as resolveProgramDraftsV1). Loader WithOrigins supplies exact
    NodeIds for struct/enum items (same Program.items layout). -/
private unsafe def testStructEnumVariantConstructorRelated
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Loader inventory for declaration NodeIds (item layout: struct, enum, entry).
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program StructEnumCtor where\n" ++
    "  struct Foo where\n" ++
    "    x : UInt64\n" ++
    "  enum Bar where\n" ++
    "    | Foo\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (_validatedLoader, inv) ← selectWithOrigins session "struct-enum-ctor" source
  let progName ← mkName "StructEnumCtor"
  let foo ← mkName "Foo"
  let bar ← mkName "Bar"
  let runName ← mkName "run"
  let u64 : TypeV1 := .uint 64
  let ctorQn ←
    match parseSourceQualifiedNameV1 #["Foo"] with
    | .ok q => pure q
    | .error e => throw <| IO.userError s!"struct-enum-ctor: mkQn: {e}"
  let structDecl : StructDeclV1 := {
    name := foo
    fields := #[{ name := (← mkName "x"), type_ := u64 }]
  }
  let enumDecl : EnumDeclV1 := {
    name := bar
    variants := #[{ name := foo, payloadTypes := #[] }]
  }
  let entryDecl : EntryDeclV1 := {
    name := runName
    params := #[]
    result := u64
    body := {
      statements := #[
        .return_ (some (.constructor ctorQn #[]))
      ]
    }
  }
  let progAst : ProgramV1 := {
    name := progName
    items := #[.struct structDecl, .enum enumDecl, .entry entryDecl]
  }
  -- Path-threaded resolveConstructorName (same related construction as body walk).
  let (tables, s1) := (buildTables progAst).run {}
  expect (itemIndicesAligned tables) "struct-enum-ctor: itemIndices aligned"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 progAst)
  let some ctorVisit := visits.find? (·.constructorTag == "Expr.Constructor") |
    throw <| IO.userError "struct-enum-ctor: missing Expr.Constructor visit"
  let sitePath := ctorVisit.path
  let (_, s2) := (resolveConstructorName tables sitePath ctorQn).run s1
  expect (s2.drafts.size ≥ 1) "struct-enum-ctor: ≥1 draft"
  let some draft := s2.drafts.find?
      (·.diagnostic.message == "ambiguous name 'Foo' (expected constructor)") |
    throw <| IO.userError s!"struct-enum-ctor: missing draft, got {s2.drafts.map (·.diagnostic.message)}"
  expectStableContext "struct-enum-ctor" draft stableAmbiguousName
  let loc ← requireLocation "struct-enum-ctor" draft
  expect (loc.relatedPaths.size == 2) "struct-enum-ctor: two related (struct + enum)"
  expect (pathInVisits visits loc.primaryPath) "struct-enum-ctor: primary ∈ visits"
  for rp in loc.relatedPaths do
    expect (pathInVisits visits rp) "struct-enum-ctor: related ∈ visits"
  expect (loc.primaryPath == sitePath) "struct-enum-ctor: primary is constructor site"
  let some primaryVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "struct-enum-ctor: primary visit"
  expect (primaryVisit.constructorTag == "Expr.Constructor")
    "struct-enum-ctor: primary Expr.Constructor"
  let structPath ← liftResult "struct" (indexChildPathV1 #[] "Program" "items" 0)
  let enumPath ← liftResult "enum" (indexChildPathV1 #[] "Program" "items" 1)
  expect (loc.relatedPaths.any (· == structPath))
    "struct-enum-ctor: related includes struct Foo"
  expect (loc.relatedPaths.any (· == enumPath))
    "struct-enum-ctor: related includes enum Bar (variant owner, not EnumDecl named Foo)"
  let some structVisit := visits.find? (·.path == structPath) |
    throw <| IO.userError "struct-enum-ctor: struct visit"
  let some enumVisit := visits.find? (·.path == enumPath) |
    throw <| IO.userError "struct-enum-ctor: enum visit"
  expect (structVisit.constructorTag == "StructDecl") "struct-enum-ctor: StructDecl"
  expect (enumVisit.constructorTag == "EnumDecl") "struct-enum-ctor: EnumDecl Bar"
  -- Decl NodeIds from real Loader inventory (same items[0]/items[1] paths).
  let structId ← inventoryNodeId inv structPath "struct-enum-ctor Foo"
  let barId ← inventoryNodeId inv enumPath "struct-enum-ctor Bar"
  expect (structId != barId) "struct-enum-ctor: distinct decl NodeIds"
  for (rp, i) in loc.relatedPaths.zipIdx do
    let id ← inventoryNodeId inv rp s!"struct-enum-ctor related[{i}]"
    expect (id == structId || id == barId)
      s!"struct-enum-ctor: related[{i}] NodeId must be struct or Bar enum"
  expect (loc.relatedPaths.any fun rp =>
      match originInventoryLookupPathV1 inv rp with
      | some o => o.nodeId == barId
      | none => false)
    "struct-enum-ctor: Bar EnumDecl path materializes to inventory NodeId"

/-- Self-recursion cycle: primary fn decl; related includes self callsite. -/
private unsafe def testSelfCycleLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program SelfRecLoc where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv) ← selectWithOrigins session "self-cycle" source
  let resolution := resolveProgramDraftsV1 validated
  expect resolution.ok "self-cycle: resolution ok"
  let cg := analyzeFnCallGraphV1 validated.program resolution.tables
  expect (!cg.ok) "self-cycle: callgraph not ok"
  expect (cg.cycleDrafts.size == 1) "self-cycle: one cycle draft"
  let draft := cg.cycleDrafts[0]!
  expect (draft.diagnostic.message == "recursive call cycle: f")
    "self-cycle: message"
  expectStableContext "self-cycle" draft stableRecursiveCycle
  let loc ← requireLocation "self-cycle" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (pathInVisits visits loc.primaryPath) "self-cycle: primary ∈ visits"
  for rp in loc.relatedPaths do
    expect (pathInVisits visits rp) "self-cycle: related ∈ visits"
  let some primaryVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "self-cycle: primary visit"
  expect (primaryVisit.constructorTag == "FnDecl") "self-cycle: primary FnDecl"
  expect (loc.relatedPaths.size ≥ 1) "self-cycle: related includes callsite"
  let hasCallSite := loc.relatedPaths.any fun rp =>
    match visits.find? (·.path == rp) with
    | some v => v.constructorTag == "Expr.LocalCall"
    | none => false
  expect hasCallSite "self-cycle: missing LocalCall related"
  -- Public erase projection parity + structure order.
  let publicStructure := checkProgramStructureV1 validated
  let erasedRes := eraseArray resolution.drafts
  let erasedCg := eraseArray cg.cycleDrafts
  eraseParity "self-cycle-res" resolution.drafts erasedRes
  eraseParity "self-cycle-cg" cg.cycleDrafts erasedCg
  expect (publicStructure.map (·.message) ==
      (erasedRes ++ erasedCg).map (·.message))
    "self-cycle: structure messages = res++cg erase"
  expect (publicStructure.any (·.message == "recursive call cycle: f"))
    "self-cycle: public contains cycle"
  let located ← locateAll "self-cycle" inv cg.cycleDrafts
  let primaryId ← expectNodeIdSome "self-cycle" located[0]!.primary
  expect (primaryId == (← inventoryNodeId inv loc.primaryPath "self-cycle primary"))
    "self-cycle: primary NodeId"
  -- Order-insensitive set equality of related NodeIds (normalizeRelated may reorder).
  expectRelatedNodeIdSet "self-cycle" inv located[0]!.related loc.relatedPaths

/-- Two-fn cycle: primary min ordinal; related remaining decl + both callsites. -/
private unsafe def testTwoFnCycleLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TwoFnLoc where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return g()\n" ++
    "  fn g() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv) ← selectWithOrigins session "two-cycle" source
  let resolution := resolveProgramDraftsV1 validated
  expect resolution.ok "two-cycle: resolution ok"
  let cg := analyzeFnCallGraphV1 validated.program resolution.tables
  expect (!cg.ok) "two-cycle: not ok"
  expect (cg.cycleDrafts.size == 1) "two-cycle: one draft"
  let draft := cg.cycleDrafts[0]!
  expect (draft.diagnostic.message == "recursive call cycle: f, g")
    "two-cycle: message"
  expectStableContext "two-cycle" draft stableRecursiveCycle
  let loc ← requireLocation "two-cycle" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (pathInVisits visits loc.primaryPath) "two-cycle: primary ∈ visits"
  for rp in loc.relatedPaths do
    expect (pathInVisits visits rp) s!"two-cycle: related ∈ visits"
  let some primaryVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "two-cycle: primary visit"
  expect (primaryVisit.constructorTag == "FnDecl") "two-cycle: primary FnDecl"
  -- f is items[0], g is items[1]
  let fPath ← liftResult "f" (indexChildPathV1 #[] "Program" "items" 0)
  let gPath ← liftResult "g" (indexChildPathV1 #[] "Program" "items" 1)
  expect (loc.primaryPath == fPath) "two-cycle: primary is min-ordinal f"
  expect (loc.relatedPaths.any (· == gPath)) "two-cycle: related includes g decl"
  let callCount := loc.relatedPaths.foldl (fun acc rp =>
    match visits.find? (·.path == rp) with
    | some v => if v.constructorTag == "Expr.LocalCall" then acc + 1 else acc
    | none => acc) 0
  expect (callCount ≥ 2) "two-cycle: ≥2 LocalCall related"
  let publicCg := checkCallGraphV1 validated.program resolution.tables
  eraseParity "two-cycle" cg.cycleDrafts publicCg.diagnostics
  expect (publicCg.diagnostics.map (fun d => d.message) ==
      (eraseArray cg.cycleDrafts).map (fun d => d.message))
    "two-cycle: erase messages"
  let located ← locateAll "two-cycle" inv cg.cycleDrafts
  let primaryId ← expectNodeIdSome "two-cycle" located[0]!.primary
  expect (primaryId == (← inventoryNodeId inv fPath "two-cycle primary"))
    "two-cycle: primary NodeId"
  expectRelatedNodeIdSet "two-cycle" inv located[0]!.related loc.relatedPaths

/-- Resolution diagnostics precede call-graph in structure concatenation. -/
private unsafe def testResolutionBeforeCallGraphOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OrderMix where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return missing\n"
  let (validated, _inv) ← selectWithOrigins session "order-mix" source
  let resolution := resolveProgramDraftsV1 validated
  let cg := analyzeFnCallGraphV1 validated.program resolution.tables
  let structureDiags := checkProgramStructureV1 validated
  let expected := eraseArray resolution.drafts ++ eraseArray cg.cycleDrafts
  expect (structureDiags.size == expected.size) "order-mix: size"
  expect (structureDiags.map (fun d => d.message) == expected.map (fun d => d.message))
    "order-mix: messages order"
  expect (structureDiags.map (fun d => d.code) == expected.map (fun d => d.code))
    "order-mix: codes order"
  expect (structureDiags.map (fun d => d.phase) == expected.map (fun d => d.phase))
    "order-mix: phases order"
  -- First diagnostic is resolution (unknown), last is cycle.
  expect (structureDiags.size ≥ 2) "order-mix: ≥2"
  expect (structureDiags[0]!.message.contains "unknown name 'missing'")
    "order-mix: resolution first"
  expect (structureDiags[structureDiags.size - 1]!.message.contains "recursive call cycle")
    "order-mix: cycle last"

/-- Every draft path across a multi-error fixture is a canonical visit path. -/
private unsafe def testAllDraftPathsInVisits
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MultiPath where\n" ++
    "  state s : UInt64\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return missing + s()\n"
  let (validated, inv) ← selectWithOrigins session "multi-path" source
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let resolution := resolveProgramDraftsV1 validated
  let cg := analyzeFnCallGraphV1 validated.program resolution.tables
  let allDrafts := resolution.drafts ++ cg.cycleDrafts
  expect (allDrafts.size ≥ 3) "multi-path: ≥3 drafts"
  for (draft, i) in allDrafts.zipIdx do
    let loc ← requireLocation s!"multi-path[{i}]" draft
    expect (pathInVisits visits loc.primaryPath)
      s!"multi-path[{i}]: primary ∈ visits"
    for (rp, j) in loc.relatedPaths.zipIdx do
      expect (pathInVisits visits rp)
        s!"multi-path[{i}].related[{j}] ∈ visits"
  let located ← locateAll "multi-path" inv allDrafts
  expect (located.size == allDrafts.size) "multi-path: locate size"
  for (d, i) in located.zipIdx do
    let primaryId ← expectNodeIdSome s!"multi-path[{i}]" d.primary
    let loc ← requireLocation s!"multi-path-loc[{i}]" allDrafts[i]!
    expect (primaryId == (← inventoryNodeId inv loc.primaryPath s!"mp[{i}]"))
      s!"multi-path[{i}]: exact primary NodeId"

/-- Shared: run TypeCheck drafts on a Loader program with origins. -/
private unsafe def typeCheckDraftsWithOrigins
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × OriginInventoryV1 × TypeCheckProgramDraftResultV1 ×
        NameResolutionDraftResultV1) := do
  let (validated, inv) ← selectWithOrigins session label source
  let resolution := resolveProgramDraftsV1 validated
  let tc := typeCheckProgramDraftsV1 validated.program resolution
  pure (validated, inv, tc, resolution)

/-- Assert a draft has location, primary tag, optional related tags, visits membership,
    erase code/message/phase, and locate primary NodeId. -/
private def expectTypeCheckDraft
    (label : String) (inv : OriginInventoryV1) (prog : ProgramV1)
    (draft : TypedDiagnosticDraftV1)
    (messageNeedle : String) (primaryTag : String)
    (relatedTags : Array String) : IO DiagnosticLocationDraftV1 := do
  expect (draft.diagnostic.message.contains messageNeedle)
    s!"{label}: message contains {messageNeedle}, got {draft.diagnostic.message}"
  expect (draft.diagnostic.code == .sourceInvalid || draft.diagnostic.code == .internal)
    s!"{label}: code"
  let loc ← requireLocation label draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 prog)
  expect (pathInVisits visits loc.primaryPath) s!"{label}: primary ∈ visits"
  let some primaryVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError s!"{label}: primary visit"
  expect (primaryVisit.constructorTag == primaryTag)
    s!"{label}: primary tag want {primaryTag} got {primaryVisit.constructorTag}"
  expect (loc.relatedPaths.size == relatedTags.size)
    s!"{label}: related count want {relatedTags.size} got {loc.relatedPaths.size}"
  for (rp, i) in loc.relatedPaths.zipIdx do
    expect (pathInVisits visits rp) s!"{label}: related[{i}] ∈ visits"
    let some rv := visits.find? (·.path == rp) |
      throw <| IO.userError s!"{label}: related visit[{i}]"
    expect (rv.constructorTag == relatedTags[i]!)
      s!"{label}: related[{i}] tag want {relatedTags[i]!} got {rv.constructorTag}"
  let erased := eraseArray #[draft]
  eraseParity label #[draft] erased
  let located ← locateAll label inv #[draft]
  let primaryId ← expectNodeIdSome label located[0]!.primary
  expect (primaryId == (← inventoryNodeId inv loc.primaryPath s!"{label} primary"))
    s!"{label}: primary NodeId"
  if !loc.relatedPaths.isEmpty then
    expectRelatedNodeIdSet label inv located[0]!.related loc.relatedPaths
  pure loc

/-- Place.Field unknown field: primary Place.Field; related StructDecl. -/
private unsafe def testTypeCheckUnknownField
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcField where\n" ++
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "  entry run(p : Point) : UInt64 do\n" ++
    "    return p.missing\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-field" source
  expect resolution.ok "tc-field: resolution ok"
  expect (!tc.ok) "tc-field: typecheck not ok"
  expect (tc.drafts.size ≥ 1) "tc-field: ≥1 draft"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "field 'missing'") |
    throw <| IO.userError s!"tc-field: missing draft, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-field" inv validated.program draft
    "field 'missing'" "Place.Field" #["StructDecl"]
  -- Public erase projection
  let publicRes := typeCheckProgramV1 validated.program (resolveProgramV1 validated)
  expect (publicRes.diagnostics.map (·.message) == (eraseArray tc.drafts).map (·.message))
    "tc-field: public erase messages"

/-- Integer literal out of range (expression family): primary Expr.Literal; related result Type. -/
private unsafe def testTypeCheckIntegerLiteralRange
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcLit where\n" ++
    "  entry run() : UInt8 do\n" ++
    "    return 300\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-lit" source
  expect resolution.ok "tc-lit: resolution ok"
  expect (!tc.ok) "tc-lit: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "integer literal") |
    throw <| IO.userError s!"tc-lit: missing draft, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-lit" inv validated.program draft
    "integer literal" "Expr.Literal" #["Type.UInt"]

/-- Binary operand type mismatch: primary on rhs Expr.Place; no decl related. -/
private unsafe def testTypeCheckBinaryMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcBin where\n" ++
    "  entry run(a : UInt64, b : Bool) : UInt64 do\n" ++
    "    return a + b\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-bin" source
  expect resolution.ok "tc-bin: resolution ok"
  expect (!tc.ok) "tc-bin: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-bin: missing draft, got {tc.drafts.map (·.diagnostic.message)}"
  let loc ← expectTypeCheckDraft "tc-bin" inv validated.program draft
    "type mismatch" "Expr.Place" #[]
  -- Primary is the offending rhs place under Expr.Binary
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let some binVisit := visits.find? (·.constructorTag == "Expr.Binary") |
    throw <| IO.userError "tc-bin: missing binary"
  -- primary should be a descendant of binary (rhs place), not the binary itself
  expect (loc.primaryPath != binVisit.path) "tc-bin: primary is operand not binary root"

/-- Constructor arity mismatch: primary Expr.Constructor; related EnumDecl.
    Surface syntax requires multi-component ctor (`Choice.Some`); single-ident
    `Pair(...)` decodes as localCall. -/
private unsafe def testTypeCheckConstructorArity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcCtor where\n" ++
    "  enum Choice where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  entry run() : Choice do\n" ++
    "    return Choice.Some(1, 2)\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-ctor" source
  unless resolution.ok do
    throw <| IO.userError s!"tc-ctor: resolution failed: {resolution.drafts.map (·.diagnostic.message)}"
  expect (!tc.ok) "tc-ctor: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "constructor arguments") |
    throw <| IO.userError s!"tc-ctor: missing draft, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-ctor" inv validated.program draft
    "constructor arguments" "Expr.Constructor" #["EnumDecl"]

/-- Local-call arity: primary Expr.LocalCall; related FnDecl. -/
private unsafe def testTypeCheckLocalCallArity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcCall where\n" ++
    "  fn add(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return add(1)\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-call" source
  expect resolution.ok "tc-call: resolution ok"
  expect (!tc.ok) "tc-call: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "arguments") |
    throw <| IO.userError s!"tc-call: missing draft, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-call" inv validated.program draft
    "arguments" "Expr.LocalCall" #["FnDecl"]

/-- Local-call arg type: primary arg literal; related Param. -/
private unsafe def testTypeCheckLocalCallArgType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcCallArg where\n" ++
    "  fn id(a : UInt64) : UInt64 do\n" ++
    "    return a\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return id(true)\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-call-arg" source
  expect resolution.ok "tc-call-arg: resolution ok"
  expect (!tc.ok) "tc-call-arg: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-call-arg: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-call-arg" inv validated.program draft
    "type mismatch" "Expr.Literal" #["Param"]

/-- String pattern fail-closed: primary Pattern.Literal. -/
private unsafe def testTypeCheckStringPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcStrPat where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return\n" ++
    "      match true with\n" ++
    "      | \"hi\" => 0\n" ++
    "      | _ => 1\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-str-pat" source
  unless resolution.ok do
    throw <| IO.userError s!"tc-str-pat: resolution failed: {resolution.drafts.map (·.diagnostic.message)}"
  expect (!tc.ok) "tc-str-pat: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "string patterns") |
    throw <| IO.userError s!"tc-str-pat: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-str-pat" inv validated.program draft
    "string patterns" "Pattern.Literal" #[]

/-- Non-exhaustive enum match: primary Stmt.Match; related EnumDecl. -/
private unsafe def testTypeCheckNonExhaustive
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcExhaust where\n" ++
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Blue\n" ++
    "  entry run() : Unit do\n" ++
    "    let c : Color := Color.Red()\n" ++
    "    match c with\n" ++
    "    | Color.Red() => do\n" ++
    "      return\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-exhaust" source
  unless resolution.ok do
    throw <| IO.userError s!"tc-exhaust: resolution failed: {resolution.drafts.map (·.diagnostic.message)}"
  expect (!tc.ok) "tc-exhaust: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "not exhaustive") |
    throw <| IO.userError s!"tc-exhaust: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-exhaust" inv validated.program draft
    "not exhaustive" "Stmt.Match" #["EnumDecl"]

/-- Match arm type mismatch: primary later arm Expr.Literal. -/
private unsafe def testTypeCheckArmMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcArm where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return\n" ++
    "      match true with\n" ++
    "      | true => 1\n" ++
    "      | false => false\n" ++
    "      | _ => 0\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-arm" source
  unless resolution.ok do
    throw <| IO.userError s!"tc-arm: resolution failed: {resolution.drafts.map (·.diagnostic.message)}"
  expect (!tc.ok) "tc-arm: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "match arm") |
    throw <| IO.userError s!"tc-arm: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-arm" inv validated.program draft
    "match arm" "Expr.Literal" #[]

/-- Return type mismatch vs declared result: primary value; related result Type. -/
private unsafe def testTypeCheckReturnResult
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcRet where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-ret" source
  expect resolution.ok "tc-ret: resolution ok"
  expect (!tc.ok) "tc-ret: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-ret: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-ret" inv validated.program draft
    "type mismatch" "Expr.Literal" #["Type.UInt"]

/-- Assign state type mismatch: primary value; related StateDecl. -/
private unsafe def testTypeCheckAssignState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcAssign where\n" ++
    "  state total : UInt64\n" ++
    "  entry run() : Unit do\n" ++
    "    total := true\n" ++
    "    return\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-assign" source
  unless resolution.ok do
    throw <| IO.userError s!"tc-assign: resolution failed: {resolution.drafts.map (·.diagnostic.message)}"
  expect (!tc.ok) "tc-assign: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-assign: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-assign" inv validated.program draft
    "type mismatch" "Expr.Literal" #["StateDecl"]

/-- Assert non-Bool: primary condition expr. -/
private unsafe def testTypeCheckAssertBool
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcAssert where\n" ++
    "  entry run() : Unit do\n" ++
    "    assert 1\n" ++
    "    return\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-assert" source
  expect resolution.ok "tc-assert: resolution ok"
  expect (!tc.ok) "tc-assert: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-assert: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-assert" inv validated.program draft
    "type mismatch" "Expr.Literal" #[]

/-- Revert arity: primary Stmt.Revert; related ErrorDecl. -/
private unsafe def testTypeCheckRevertArity
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcRevert where\n" ++
    "  error Boom(code : UInt64)\n" ++
    "  entry run() : Unit do\n" ++
    "    revert Boom()\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-revert" source
  expect resolution.ok "tc-revert: resolution ok"
  expect (!tc.ok) "tc-revert: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "arguments") |
    throw <| IO.userError s!"tc-revert: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-revert" inv validated.program draft
    "arguments" "Stmt.Revert" #["ErrorDecl"]

/-- Emit arg type: primary arg; related Param of EventDecl. -/
private unsafe def testTypeCheckEmitArg
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcEmit where\n" ++
    "  event Tick(n : UInt64)\n" ++
    "  entry run() : Unit do\n" ++
    "    emit Tick(true)\n" ++
    "    return\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-emit" source
  expect resolution.ok "tc-emit: resolution ok"
  expect (!tc.ok) "tc-emit: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-emit: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-emit" inv validated.program draft
    "type mismatch" "Expr.Literal" #["Param"]

/-- Const value type mismatch: primary value; related const type Type.UInt. -/
private unsafe def testTypeCheckConstValue
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcConst where\n" ++
    "  const answer : UInt64 := true\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-const" source
  expect resolution.ok "tc-const: resolution ok"
  expect (!tc.ok) "tc-const: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-const: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-const" inv validated.program draft
    "type mismatch" "Expr.Literal" #["Type.UInt"]

/-- Invariant non-Bool predicate: primary predicate expr. -/
private unsafe def testTypeCheckInvariantPredicate
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcInv where\n" ++
    "  invariant alwaysOk : 1\n" ++
    "  entry run() : Unit do\n" ++
    "    return\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-inv" source
  unless resolution.ok do
    throw <| IO.userError s!"tc-inv: resolution failed: {resolution.drafts.map (·.diagnostic.message)}"
  expect (!tc.ok) "tc-inv: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "type mismatch") |
    throw <| IO.userError s!"tc-inv: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-inv" inv validated.program draft
    "type mismatch" "Expr.Literal" #[]

/-- Bare return with non-Unit result: primary Stmt.Return; related result type. -/
private unsafe def testTypeCheckBareReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcBareRet where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-bare-ret" source
  expect resolution.ok "tc-bare-ret: resolution ok"
  expect (!tc.ok) "tc-bare-ret: not ok"
  let some draft := tc.drafts.find?
      (·.diagnostic.message.contains "empty return") |
    throw <| IO.userError s!"tc-bare-ret: missing, got {tc.drafts.map (·.diagnostic.message)}"
  let _ ← expectTypeCheckDraft "tc-bare-ret" inv validated.program draft
    "empty return" "Stmt.Return" #["Type.UInt"]

/-- Resolution-not-ok short-circuit: drafts are resolution drafts; erase == typeCheckProgramV1. -/
private unsafe def testTypeCheckResolutionShortCircuit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcShort where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return missing\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-short" source
  expect (!resolution.ok) "tc-short: resolution not ok"
  expect (!tc.ok) "tc-short: typecheck not ok"
  expect (tc.drafts.size == resolution.drafts.size) "tc-short: draft size"
  expect (tc.drafts.map (·.diagnostic.message) ==
      resolution.drafts.map (·.diagnostic.message))
    "tc-short: same messages as resolution"
  let publicRes := typeCheckProgramV1 validated.program (resolveProgramV1 validated)
  expect (publicRes.diagnostics.map (·.message) == (eraseArray tc.drafts).map (·.message))
    "tc-short: public erase parity"
  -- Located resolution primary still materializes
  expect (tc.drafts.size ≥ 1) "tc-short: ≥1"
  let loc ← requireLocation "tc-short" tc.drafts[0]!
  let located ← locateAll "tc-short" inv tc.drafts
  let primaryId ← expectNodeIdSome "tc-short" located[0]!.primary
  expect (primaryId == (← inventoryNodeId inv loc.primaryPath "tc-short"))
    "tc-short: NodeId"

/-- Every TypeCheck draft path is a canonical visit; multi-family program. -/
private unsafe def testTypeCheckAllDraftPathsInVisits
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TcMulti where\n" ++
    "  const c : UInt64 := true\n" ++
    "  entry run() : UInt8 do\n" ++
    "    return 300\n"
  let (validated, inv, tc, resolution) ←
    typeCheckDraftsWithOrigins session "tc-multi" source
  expect resolution.ok "tc-multi: resolution ok"
  expect (!tc.ok) "tc-multi: not ok"
  expect (tc.drafts.size ≥ 2) "tc-multi: ≥2 type drafts"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  for (draft, i) in tc.drafts.zipIdx do
    let loc ← requireLocation s!"tc-multi[{i}]" draft
    expect (pathInVisits visits loc.primaryPath)
      s!"tc-multi[{i}]: primary ∈ visits"
    for (rp, j) in loc.relatedPaths.zipIdx do
      expect (pathInVisits visits rp)
        s!"tc-multi[{i}].related[{j}] ∈ visits"
  let located ← locateAll "tc-multi" inv tc.drafts
  expect (located.size == tc.drafts.size) "tc-multi: locate size"
  let publicRes := typeCheckProgramV1 validated.program (resolveProgramV1 validated)
  eraseParity "tc-multi" tc.drafts publicRes.diagnostics
  expect (publicRes.diagnostics.map (·.message) ==
      (eraseArray tc.drafts).map (·.message))
    "tc-multi: full erase messages"

/-- B7b3a: EffectCheck draft authority via Loader origins. -/
private unsafe def effectDraftsWithOrigins
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × OriginInventoryV1 × EffectCheckDraftResultV1) := do
  let (validated, inv) ← selectWithOrigins session label source
  let res := checkProgramEffectsDraftsV1 validated
  pure (validated, inv, res)

/-- Every path on every draft is a canonical visit; locate yields real NodeIds. -/
private def expectEffectDraftPaths
    (label : String) (inv : OriginInventoryV1) (prog : ProgramV1)
    (drafts : Array TypedDiagnosticDraftV1) : IO Unit := do
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 prog)
  for (draft, i) in drafts.zipIdx do
    let loc ← requireLocation s!"{label}[{i}]" draft
    expect (pathInVisits visits loc.primaryPath)
      s!"{label}[{i}]: primary ∈ visits"
    for (rp, j) in loc.relatedPaths.zipIdx do
      expect (pathInVisits visits rp)
        s!"{label}[{i}].related[{j}] ∈ visits"
  let located ← locateAll label inv drafts
  expect (located.size == drafts.size) s!"{label}: locate size"
  for (draft, i) in drafts.zipIdx do
    let loc ← requireLocation s!"{label}[{i}]" draft
    let primaryId ← expectNodeIdSome s!"{label}[{i}]" located[i]!.primary
    expect (primaryId == (← inventoryNodeId inv loc.primaryPath s!"{label}[{i}] primary"))
      s!"{label}[{i}]: primary NodeId exact"
    expectRelatedNodeIdSet s!"{label}[{i}]" inv located[i]!.related loc.relatedPaths

private def expectEffectEraseParity
    (label : String) (validated : ValidatedSourceV1)
    (draftRes : EffectCheckDraftResultV1) : IO Unit := do
  let publicArr := checkProgramEffectsV1 validated
  let publicRes := checkProgramEffectsResultV1 validated
  eraseParity label draftRes.drafts publicArr
  expect (draftRes.ok == publicRes.ok) s!"{label}: ok parity"
  expect (draftRes.analysisComplete == publicRes.analysisComplete)
    s!"{label}: analysisComplete parity"
  expect (publicRes.diagnostics.map (·.message) == publicArr.map (·.message))
    s!"{label}: result vs array messages"
  expect (publicArr.map (·.code) == (eraseArray draftRes.drafts).map (·.code))
    s!"{label}: code order parity"
  expect (publicArr.all (fun d => d.code == .effectDisallowed || d.code == .sourceInvalid
      || d.code == .internal))
    s!"{label}: public codes are effect/structural only"

/-- Direct fn state.read: primary FnDecl; related = Place.Name root. -/
private unsafe def testEffectDirectStateRead
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffRead where\n" ++
    "  state total : UInt64\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek()\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-read" source
  expect (!res.ok) "eff-read: not ok"
  expect res.analysisComplete "eff-read: complete"
  expect (res.drafts.size == 1) "eff-read: one draft"
  let draft := res.drafts[0]!
  expect (draft.diagnostic.code == .effectDisallowed) "eff-read: code"
  expect (draft.diagnostic.message == "fn 'peek' does not allow effect 'state.read'")
    "eff-read: message"
  let loc ← requireLocation "eff-read" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let some pVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "eff-read: primary visit"
  expect (pVisit.constructorTag == "FnDecl") "eff-read: primary FnDecl"
  expect (loc.relatedPaths.size == 1) "eff-read: one related"
  let some rVisit := visits.find? (·.path == loc.relatedPaths[0]!) |
    throw <| IO.userError "eff-read: related visit"
  expect (rVisit.constructorTag == "Place.Name") "eff-read: related Place.Name"
  expectEffectDraftPaths "eff-read" inv validated.program res.drafts
  expectEffectEraseParity "eff-read" validated res

/-- Direct state.write on assign target Place.Name + state.read from return. -/
private unsafe def testEffectDirectStateWrite
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffWrite where\n" ++
    "  state total : UInt64\n" ++
    "  fn bump() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return bump()\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-write" source
  expect (!res.ok) "eff-write: not ok"
  expect (res.drafts.size == 2) "eff-write: read+write drafts"
  expect (res.drafts[0]!.diagnostic.message.contains "state.read")
    "eff-write: rank state.read first"
  expect (res.drafts[1]!.diagnostic.message.contains "state.write")
    "eff-write: rank state.write second"
  let writeDraft := res.drafts[1]!
  let loc ← requireLocation "eff-write" writeDraft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let some pVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "eff-write: primary visit"
  expect (pVisit.constructorTag == "FnDecl") "eff-write: primary FnDecl"
  expect (loc.relatedPaths.any fun rp =>
      match visits.find? (·.path == rp) with
      | some v => v.constructorTag == "Place.Name"
      | none => false)
    "eff-write: related includes Place.Name write root"
  expectEffectDraftPaths "eff-write" inv validated.program res.drafts
  expectEffectEraseParity "eff-write" validated res

/-- emit / call / schedule / assert / revert at exact Stmt nodes. -/
private unsafe def testEffectDirectStmtSites
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffStmts where\n" ++
    "  event Ev()\n" ++
    "  error Boom()\n" ++
    "  fn bad(ok : Bool) : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    call External.Use()\n" ++
    "    schedule External.Later()\n" ++
    "    assert ok\n" ++
    "    if ok then\n" ++
    "      return 0\n" ++
    "    else\n" ++
    "      revert Boom()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return bad(true)\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-stmts" source
  expect (!res.ok) "eff-stmts: not ok"
  -- emit, external.call.sync, workflow.schedule in EffectKind order; assert+revert are allowed
  let msgs := res.drafts.map (·.diagnostic.message)
  expect (msgs.any (·.contains "event.emit")) "eff-stmts: emit"
  expect (msgs.any (·.contains "external.call.sync")) "eff-stmts: call"
  expect (msgs.any (·.contains "workflow.schedule")) "eff-stmts: schedule"
  -- failure.revert allowed on fn — no PF-EFFECT-001 for assert/revert
  expect (!msgs.any (·.contains "failure.revert")) "eff-stmts: no revert disallow"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  for (draft, i) in res.drafts.zipIdx do
    let loc ← requireLocation s!"eff-stmts[{i}]" draft
    let some pVisit := visits.find? (·.path == loc.primaryPath) |
      throw <| IO.userError s!"eff-stmts[{i}]: primary visit"
    expect (pVisit.constructorTag == "FnDecl") s!"eff-stmts[{i}]: primary FnDecl"
    expect (loc.relatedPaths.size ≥ 1) s!"eff-stmts[{i}]: related nonempty"
    for rp in loc.relatedPaths do
      let some rv := visits.find? (·.path == rp) |
        throw <| IO.userError s!"eff-stmts[{i}]: related visit"
      expect (rv.constructorTag == "Stmt.Emit" || rv.constructorTag == "Stmt.Call"
          || rv.constructorTag == "Stmt.Schedule")
        s!"eff-stmts[{i}]: related stmt tag {rv.constructorTag}"
  expectEffectDraftPaths "eff-stmts" inv validated.program res.drafts
  expectEffectEraseParity "eff-stmts" validated res

/-- Multi-effect one fn: declaration + EffectKind order preserved on erase. -/
private unsafe def testEffectMultiKindOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffMulti where\n" ++
    "  state total : UInt64\n" ++
    "  event Ev()\n" ++
    "  fn bad() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    total := 1\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return bad()\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-multi" source
  expect (!res.ok) "eff-multi: not ok"
  let msgs := res.drafts.map (·.diagnostic.message)
  -- rank: state.read(0), state.write(1), event.emit(2)
  expect (msgs.size ≥ 3) s!"eff-multi: ≥3 drafts, got {msgs}"
  expect (msgs[0]!.contains "state.read") s!"eff-multi: [0] read, got {msgs}"
  expect (msgs[1]!.contains "state.write") s!"eff-multi: [1] write, got {msgs}"
  expect (msgs[2]!.contains "event.emit") s!"eff-multi: [2] emit, got {msgs}"
  expectEffectDraftPaths "eff-multi" inv validated.program res.drafts
  expectEffectEraseParity "eff-multi" validated res

/-- View disallow state.write primary=ViewDecl; view-ok state.read produces no draft. -/
private unsafe def testEffectViewLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let okSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffViewOk where\n" ++
    "  state total : UInt64\n" ++
    "  view get() : UInt64 do\n" ++
    "    return total\n"
  let (vOk, _invOk, resOk) ← effectDraftsWithOrigins session "eff-view-ok" okSource
  expect resOk.ok "eff-view-ok: ok"
  expect resOk.drafts.isEmpty "eff-view-ok: no drafts"
  expectEffectEraseParity "eff-view-ok" vOk resOk

  let badSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffViewWrite where\n" ++
    "  state total : UInt64\n" ++
    "  view set() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return total\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-view-write" badSource
  expect (!res.ok) "eff-view-write: not ok"
  let some draft := res.drafts.find?
      (·.diagnostic.message.contains "view 'set' does not allow effect 'state.write'") |
    throw <| IO.userError s!"eff-view-write: missing write draft, got {res.drafts.map (·.diagnostic.message)}"
  let loc ← requireLocation "eff-view-write" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let some pVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "eff-view-write: primary visit"
  expect (pVisit.constructorTag == "ViewDecl") "eff-view-write: primary ViewDecl"
  expect (loc.relatedPaths.any fun rp =>
      match visits.find? (·.path == rp) with
      | some v => v.constructorTag == "Place.Name"
      | none => false)
    "eff-view-write: related Place.Name"
  expectEffectDraftPaths "eff-view-write" inv validated.program res.drafts
  expectEffectEraseParity "eff-view-write" validated res

/-- 1-hop transitive: caller related = LocalCall site ∪ writer direct Place.Name. -/
private unsafe def testEffectTransitiveOneHop
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffHop1 where\n" ++
    "  state total : UInt64\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return 1\n" ++
    "  fn caller() : UInt64 do\n" ++
    "    return writer()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return caller()\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-hop1" source
  expect (!res.ok) "eff-hop1: not ok"
  let some writerD := res.drafts.find?
      (·.diagnostic.message == "fn 'writer' does not allow effect 'state.write'") |
    throw <| IO.userError s!"eff-hop1: missing writer, got {res.drafts.map (·.diagnostic.message)}"
  let some callerD := res.drafts.find?
      (·.diagnostic.message == "fn 'caller' does not allow effect 'state.write'") |
    throw <| IO.userError s!"eff-hop1: missing caller, got {res.drafts.map (·.diagnostic.message)}"
  let wLoc ← requireLocation "eff-hop1-w" writerD
  let cLoc ← requireLocation "eff-hop1-c" callerD
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (wLoc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Place.Name")
    "eff-hop1: writer related Place.Name"
  expect (!wLoc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Expr.LocalCall")
    "eff-hop1: writer has no LocalCall related"
  expect (cLoc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Expr.LocalCall")
    "eff-hop1: caller related LocalCall"
  expect (cLoc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Place.Name")
    "eff-hop1: caller related includes downstream Place.Name"
  expectEffectDraftPaths "eff-hop1" inv validated.program res.drafts
  expectEffectEraseParity "eff-hop1" validated res

/-- Multi-hop chain: top related excludes pure unrelated call edges. -/
private unsafe def testEffectTransitiveMultiHop
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffHopN where\n" ++
    "  event Ev()\n" ++
    "  fn pure() : UInt64 do\n" ++
    "    return 0\n" ++
    "  fn leaf() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    return pure()\n" ++
    "  fn mid() : UInt64 do\n" ++
    "    return leaf()\n" ++
    "  fn top() : UInt64 do\n" ++
    "    return mid()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return top()\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-hopn" source
  expect (!res.ok) "eff-hopn: not ok"
  let some topD := res.drafts.find?
      (·.diagnostic.message == "fn 'top' does not allow effect 'event.emit'") |
    throw <| IO.userError s!"eff-hopn: missing top, got {res.drafts.map (·.diagnostic.message)}"
  let some leafD := res.drafts.find?
      (·.diagnostic.message == "fn 'leaf' does not allow effect 'event.emit'") |
    throw <| IO.userError s!"eff-hopn: missing leaf, got {res.drafts.map (·.diagnostic.message)}"
  let topLoc ← requireLocation "eff-hopn-top" topD
  let leafLoc ← requireLocation "eff-hopn-leaf" leafD
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  -- leaf related: Stmt.Emit only (pure() closed set has no event.emit → exclude LocalCall pure)
  expect (leafLoc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Stmt.Emit")
    "eff-hopn: leaf related Stmt.Emit"
  expect (!leafLoc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Expr.LocalCall")
    "eff-hopn: leaf excludes pure LocalCall (unrelated to emit)"
  -- top related: LocalCall mid + LocalCall leaf + Stmt.Emit (no pure)
  let topLocalCalls := topLoc.relatedPaths.filter fun rp =>
    (visits.find? (·.path == rp)).map (·.constructorTag) == some "Expr.LocalCall"
  expect (topLocalCalls.size == 2)
    s!"eff-hopn: top has 2 effect-propagating LocalCalls, got {topLocalCalls.size}"
  expect (topLoc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Stmt.Emit")
    "eff-hopn: top related includes Stmt.Emit"
  expectEffectDraftPaths "eff-hopn" inv validated.program res.drafts
  expectEffectEraseParity "eff-hopn" validated res

/-- Duplicate callsites: retain distinct LocalCall occurrences. -/
private unsafe def testEffectDuplicateCallsites
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffDupCall where\n" ++
    "  state total : UInt64\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return 1\n" ++
    "  fn caller() : UInt64 do\n" ++
    "    let _a : UInt64 := writer()\n" ++
    "    let _b : UInt64 := writer()\n" ++
    "    return _a\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return caller()\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-dup-call" source
  expect (!res.ok) "eff-dup-call: not ok"
  let some callerD := res.drafts.find?
      (·.diagnostic.message == "fn 'caller' does not allow effect 'state.write'") |
    throw <| IO.userError s!"eff-dup-call: missing caller, got {res.drafts.map (·.diagnostic.message)}"
  let loc ← requireLocation "eff-dup-call" callerD
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let localCalls := loc.relatedPaths.filter fun rp =>
    (visits.find? (·.path == rp)).map (·.constructorTag) == some "Expr.LocalCall"
  expect (localCalls.size == 2)
    s!"eff-dup-call: two distinct LocalCall related, got {localCalls.size}"
  expect (localCalls[0]! != localCalls[1]!) "eff-dup-call: distinct paths"
  expectEffectDraftPaths "eff-dup-call" inv validated.program res.drafts
  expectEffectEraseParity "eff-dup-call" validated res

/-- Cycle: finite deterministic related set (visit-bounded worklist). -/
private unsafe def testEffectCycleEvidence
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffCycle where\n" ++
    "  event Ev()\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return b()\n" ++
    "  fn b() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    return a()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-cycle" source
  expect (!res.ok) "eff-cycle: not ok"
  let some aD := res.drafts.find?
      (·.diagnostic.message == "fn 'a' does not allow effect 'event.emit'") |
    throw <| IO.userError s!"eff-cycle: missing a, got {res.drafts.map (·.diagnostic.message)}"
  let loc ← requireLocation "eff-cycle" aD
  -- Finite: at most a few related paths (LocalCall b, Stmt.Emit, LocalCall a)
  expect (loc.relatedPaths.size ≤ 8)
    s!"eff-cycle: related bounded, got {loc.relatedPaths.size}"
  expect (loc.relatedPaths.size ≥ 2)
    s!"eff-cycle: related ≥2 (call+emit), got {loc.relatedPaths.size}"
  -- Determinism: re-run same authority
  let res2 := checkProgramEffectsDraftsV1 validated
  expect (res2.drafts.size == res.drafts.size) "eff-cycle: draft count stable"
  for i in [0:res.drafts.size] do
    let l1 ← requireLocation s!"eff-cycle-d{i}" res.drafts[i]!
    let l2 ← requireLocation s!"eff-cycle-d{i}b" res2.drafts[i]!
    expect (l1.primaryPath == l2.primaryPath) s!"eff-cycle[{i}]: primary stable"
    expect (l1.relatedPaths == l2.relatedPaths) s!"eff-cycle[{i}]: related stable"
  expectEffectDraftPaths "eff-cycle" inv validated.program res.drafts
  expectEffectEraseParity "eff-cycle" validated res

/-- Shadowing: param/local shadow state or callee ⇒ no spurious sites/edges. -/
private unsafe def testEffectShadowingLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffShadow where\n" ++
    "  state total : UInt64\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    return 1\n" ++
    "  fn peek(total : UInt64) : UInt64 do\n" ++
    "    return total\n" ++
    "  fn caller(writer : UInt64) : UInt64 do\n" ++
    "    return writer\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek(0) + caller(0)\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-shadow" source
  expect (!res.ok) "eff-shadow: not ok"
  -- only writer should fail; peek/caller produce no drafts
  expect (res.drafts.all (fun d => d.diagnostic.message.contains "fn 'writer'"))
    s!"eff-shadow: only writer drafts, got {res.drafts.map (·.diagnostic.message)}"
  expect (!res.drafts.any (·.diagnostic.message.contains "fn 'peek'"))
    "eff-shadow: no peek draft"
  expect (!res.drafts.any (·.diagnostic.message.contains "fn 'caller'"))
    "eff-shadow: no caller draft"
  expectEffectDraftPaths "eff-shadow" inv validated.program res.drafts
  expectEffectEraseParity "eff-shadow" validated res

/-- Incomplete duplicate-fn: analysisComplete=false, no allowlist drafts. -/
private unsafe def testEffectIncompleteDuplicateFn
    (_session : Language.Loader.ParserSession) : IO Unit := do
  let progName ← mkName "EffDupFn"
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
  let (tables, _) := (buildTables progAst).run {}
  expect tables.fn.hasDuplicateKey "eff-dup-fn: hasDuplicateKey"
  let draftRes := checkEffectsDraftsV1 progAst tables
  expect (!draftRes.analysisComplete) "eff-dup-fn: analysisComplete=false"
  expect (!draftRes.ok) "eff-dup-fn: ok=false"
  expect draftRes.drafts.isEmpty "eff-dup-fn: no allowlist drafts"
  let erased := checkEffectsV1 progAst tables
  expect (erased.diagnostics.isEmpty) "eff-dup-fn: public empty diags"
  expect (!erased.analysisComplete) "eff-dup-fn: public incomplete"
  expect (!erased.ok) "eff-dup-fn: public not ok"

/-- All effect drafts paths ∈ visits; full public erase parity. -/
private unsafe def testEffectAllDraftPathsInVisits
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EffAllPaths where\n" ++
    "  state total : UInt64\n" ++
    "  event Ev()\n" ++
    "  fn writer() : UInt64 do\n" ++
    "    total := 1\n" ++
    "    emit Ev()\n" ++
    "    return total\n" ++
    "  fn mid() : UInt64 do\n" ++
    "    return writer()\n" ++
    "  view bad() : UInt64 do\n" ++
    "    return mid()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return mid()\n"
  let (validated, inv, res) ← effectDraftsWithOrigins session "eff-all" source
  expect (!res.ok) "eff-all: not ok"
  expect (res.drafts.size ≥ 3) s!"eff-all: ≥3 drafts, got {res.drafts.size}"
  expectEffectDraftPaths "eff-all" inv validated.program res.drafts
  expectEffectEraseParity "eff-all" validated res

/-- B7b3b: BoundCheck draft authority via Loader origins. -/
private unsafe def boundDraftsWithOrigins
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × OriginInventoryV1 × BoundCheckDraftResultV1) := do
  let (validated, inv) ← selectWithOrigins session label source
  let res := checkProgramBoundsDraftsV1 validated
  pure (validated, inv, res)

private def expectBoundDraftPaths
    (label : String) (inv : OriginInventoryV1) (prog : ProgramV1)
    (drafts : Array TypedDiagnosticDraftV1) : IO Unit := do
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 prog)
  for (draft, i) in drafts.zipIdx do
    let loc ← requireLocation s!"{label}[{i}]" draft
    expect (pathInVisits visits loc.primaryPath)
      s!"{label}[{i}]: primary ∈ visits"
    for (rp, j) in loc.relatedPaths.zipIdx do
      expect (pathInVisits visits rp)
        s!"{label}[{i}].related[{j}] ∈ visits"
  let located ← locateAll label inv drafts
  expect (located.size == drafts.size) s!"{label}: locate size"
  for (draft, i) in drafts.zipIdx do
    let loc ← requireLocation s!"{label}[{i}]" draft
    let primaryId ← expectNodeIdSome s!"{label}[{i}]" located[i]!.primary
    expect (primaryId == (← inventoryNodeId inv loc.primaryPath s!"{label}[{i}] primary"))
      s!"{label}[{i}]: primary NodeId exact"
    expectRelatedNodeIdSet s!"{label}[{i}]" inv located[i]!.related loc.relatedPaths

private def expectBoundEraseParity
    (label : String) (validated : ValidatedSourceV1)
    (draftRes : BoundCheckDraftResultV1) : IO Unit := do
  let publicArr := checkProgramBoundsV1 validated
  let publicRes := checkProgramBoundsResultV1 validated
  eraseParity label draftRes.drafts publicArr
  expect (draftRes.ok == publicRes.ok) s!"{label}: ok parity"
  expect (draftRes.analysisComplete == publicRes.analysisComplete)
    s!"{label}: analysisComplete parity"
  expect (publicRes.diagnostics.map (·.message) == publicArr.map (·.message))
    s!"{label}: result vs array messages"
  expect (publicArr.map (·.code) == (eraseArray draftRes.drafts).map (·.code))
    s!"{label}: code order parity"
  expect (publicArr.map (·.message) == (eraseArray draftRes.drafts).map (·.message))
    s!"{label}: message order parity"
  expect (publicArr.all (fun d =>
      d.code == .resourceBound || d.code == .sourceInvalid || d.code == .internal))
    s!"{label}: public codes are bound/structural only"

/-- Self-recursion: primary FnDecl f; related includes LocalCall site. -/
private unsafe def testBoundSelfCycleLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundSelfRec where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv, res) ← boundDraftsWithOrigins session "bound-self" source
  expect (!res.ok) "bound-self: not ok"
  expect res.analysisComplete "bound-self: complete"
  expect (res.drafts.size == 1) "bound-self: one draft"
  let draft := res.drafts[0]!
  expect (draft.diagnostic.code == .resourceBound) "bound-self: code"
  expect (draft.diagnostic.message == "unbounded recursion (call cycle): f")
    "bound-self: message"
  let loc ← requireLocation "bound-self" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let some pVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "bound-self: primary visit"
  expect (pVisit.constructorTag == "FnDecl") "bound-self: primary FnDecl"
  expect (loc.relatedPaths.any fun rp =>
      (visits.find? (·.path == rp)).map (·.constructorTag) == some "Expr.LocalCall")
    "bound-self: related LocalCall"
  expectBoundDraftPaths "bound-self" inv validated.program res.drafts
  expectBoundEraseParity "bound-self" validated res

/-- Two-fn cycle: primary min-ordinal f; related g + both LocalCalls. -/
private unsafe def testBoundTwoFnCycleLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundTwoFn where\n" ++
    "  fn f() : UInt64 do\n" ++
    "    return g()\n" ++
    "  fn g() : UInt64 do\n" ++
    "    return f()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv, res) ← boundDraftsWithOrigins session "bound-two" source
  expect (!res.ok) "bound-two: not ok"
  expect (res.drafts.size == 1) "bound-two: one draft"
  let draft := res.drafts[0]!
  expect (draft.diagnostic.message == "unbounded recursion (call cycle): f, g")
    "bound-two: message"
  let loc ← requireLocation "bound-two" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let fPath ← liftResult "f" (indexChildPathV1 #[] "Program" "items" 0)
  let gPath ← liftResult "g" (indexChildPathV1 #[] "Program" "items" 1)
  expect (loc.primaryPath == fPath) "bound-two: primary min-ordinal f"
  expect (loc.relatedPaths.any (· == gPath)) "bound-two: related g decl"
  let callCount := loc.relatedPaths.foldl (fun acc rp =>
    match visits.find? (·.path == rp) with
    | some v => if v.constructorTag == "Expr.LocalCall" then acc + 1 else acc
    | none => acc) 0
  expect (callCount == 2) s!"bound-two: exactly 2 LocalCall related, got {callCount}"
  expectBoundDraftPaths "bound-two" inv validated.program res.drafts
  expectBoundEraseParity "bound-two" validated res

/-- Three-fn cycle: primary a; related b,c + three LocalCalls in source order. -/
private unsafe def testBoundThreeFnCycleLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundThreeFn where\n" ++
    "  fn a() : UInt64 do\n" ++
    "    return b()\n" ++
    "  fn b() : UInt64 do\n" ++
    "    return c()\n" ++
    "  fn c() : UInt64 do\n" ++
    "    return a()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv, res) ← boundDraftsWithOrigins session "bound-three" source
  expect (!res.ok) "bound-three: not ok"
  expect (res.drafts.size == 1) "bound-three: one draft"
  let draft := res.drafts[0]!
  expect (draft.diagnostic.message == "unbounded recursion (call cycle): a, b, c")
    "bound-three: message"
  let loc ← requireLocation "bound-three" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let aPath ← liftResult "a" (indexChildPathV1 #[] "Program" "items" 0)
  let bPath ← liftResult "b" (indexChildPathV1 #[] "Program" "items" 1)
  let cPath ← liftResult "c" (indexChildPathV1 #[] "Program" "items" 2)
  expect (loc.primaryPath == aPath) "bound-three: primary a"
  expect (loc.relatedPaths.any (· == bPath)) "bound-three: related b"
  expect (loc.relatedPaths.any (· == cPath)) "bound-three: related c"
  -- related order: remaining decls (ordinal) then call sites (edge source order)
  expect (loc.relatedPaths.size ≥ 5)
    s!"bound-three: ≥2 decls + 3 calls, got {loc.relatedPaths.size}"
  expect (loc.relatedPaths[0]! == bPath) "bound-three: related[0]=b"
  expect (loc.relatedPaths[1]! == cPath) "bound-three: related[1]=c"
  let callCount := loc.relatedPaths.foldl (fun acc rp =>
    match visits.find? (·.path == rp) with
    | some v => if v.constructorTag == "Expr.LocalCall" then acc + 1 else acc
    | none => acc) 0
  expect (callCount == 3) s!"bound-three: 3 LocalCall related, got {callCount}"
  expectBoundDraftPaths "bound-three" inv validated.program res.drafts
  expectBoundEraseParity "bound-three" validated res

/-- Nested 4096³ overflow in fn: primary innermost Stmt.For; related fn + outer Fors. -/
private unsafe def testBoundLoopOverflowFnLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundNestFn where\n" ++
    "  state total : UInt64\n" ++
    "  fn work() : UInt64 do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        for k in 0 ..< 4096 bounded 4096 do\n" ++
    "          total := i\n" ++
    "    return total\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return work()\n"
  let (validated, inv, res) ← boundDraftsWithOrigins session "bound-loop-fn" source
  expect (!res.ok) "bound-loop-fn: not ok"
  expect (res.drafts.size == 1) "bound-loop-fn: one overflow"
  let draft := res.drafts[0]!
  expect (draft.diagnostic.code == .resourceBound) "bound-loop-fn: code"
  expect (draft.diagnostic.message ==
      "loop bound product overflows UInt32 in fn 'work' (bound 4096)")
    "bound-loop-fn: message"
  let loc ← requireLocation "bound-loop-fn" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let some pVisit := visits.find? (·.path == loc.primaryPath) |
    throw <| IO.userError "bound-loop-fn: primary visit"
  expect (pVisit.constructorTag == "Stmt.For") "bound-loop-fn: primary Stmt.For"
  -- related: FnDecl work + two ancestor Fors
  expect (loc.relatedPaths.size == 3)
    s!"bound-loop-fn: related size 3, got {loc.relatedPaths.size}"
  let some r0 := visits.find? (·.path == loc.relatedPaths[0]!) |
    throw <| IO.userError "bound-loop-fn: related[0]"
  expect (r0.constructorTag == "FnDecl") "bound-loop-fn: related[0] FnDecl"
  expect (loc.relatedPaths.all fun rp =>
      match visits.find? (·.path == rp) with
      | some v => v.constructorTag == "FnDecl" || v.constructorTag == "Stmt.For"
      | none => false)
    "bound-loop-fn: related only FnDecl/Stmt.For"
  let forRelated := loc.relatedPaths.filter fun rp =>
    (visits.find? (·.path == rp)).map (·.constructorTag) == some "Stmt.For"
  expect (forRelated.size == 2) "bound-loop-fn: two ancestor Fors"
  -- primary must not appear in related
  expect (!loc.relatedPaths.any (· == loc.primaryPath))
    "bound-loop-fn: primary not in related"
  expectBoundDraftPaths "bound-loop-fn" inv validated.program res.drafts
  expectBoundEraseParity "bound-loop-fn" validated res

/-- Overflow under entry + if / match; primary Stmt.For; related EntryDecl + ancestors. -/
private unsafe def testBoundLoopOverflowEntryIfMatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let ifSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundLoopIf where\n" ++
    "  state total : UInt64\n" ++
    "  state flag : Bool\n" ++
    "  entry run() : UInt64 do\n" ++
    "    if flag then\n" ++
    "      for i in 0 ..< 4096 bounded 4096 do\n" ++
    "        for j in 0 ..< 4096 bounded 4096 do\n" ++
    "          for k in 0 ..< 4096 bounded 4096 do\n" ++
    "            total := i\n" ++
    "    else\n" ++
    "      total := 0\n" ++
    "    return total\n"
  let (vIf, invIf, resIf) ← boundDraftsWithOrigins session "bound-loop-if" ifSource
  expect (!resIf.ok) "bound-loop-if: not ok"
  expect (resIf.drafts.size == 1) "bound-loop-if: one draft"
  let dIf := resIf.drafts[0]!
  expect (dIf.diagnostic.message.contains "entry 'run'") "bound-loop-if: entry label"
  let locIf ← requireLocation "bound-loop-if" dIf
  let visitsIf ← liftResult "visits" (canonicalNodeVisitsV1 vIf.program)
  expect ((visitsIf.find? (·.path == locIf.primaryPath)).map (·.constructorTag)
      == some "Stmt.For")
    "bound-loop-if: primary For"
  -- related: EntryDecl + two ancestor Fors (outer then mid); mirrors fn-nest contract
  expect (locIf.relatedPaths.size == 3)
    s!"bound-loop-if: related size 3, got {locIf.relatedPaths.size}"
  let some r0If := visitsIf.find? (·.path == locIf.relatedPaths[0]!) |
    throw <| IO.userError "bound-loop-if: related[0]"
  expect (r0If.constructorTag == "EntryDecl") "bound-loop-if: related[0] EntryDecl"
  expect (locIf.relatedPaths.all fun rp =>
      match visitsIf.find? (·.path == rp) with
      | some v => v.constructorTag == "EntryDecl" || v.constructorTag == "Stmt.For"
      | none => false)
    "bound-loop-if: related only EntryDecl/Stmt.For"
  let forRelatedIf := locIf.relatedPaths.filter fun rp =>
    (visitsIf.find? (·.path == rp)).map (·.constructorTag) == some "Stmt.For"
  expect (forRelatedIf.size == 2) "bound-loop-if: two ancestor Fors"
  expect (!locIf.relatedPaths.any (· == locIf.primaryPath))
    "bound-loop-if: primary not in related"
  expectBoundDraftPaths "bound-loop-if" invIf vIf.program resIf.drafts
  expectBoundEraseParity "bound-loop-if" vIf resIf

  let matchSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundLoopMatch where\n" ++
    "  state total : UInt64\n" ++
    "  state flag : Bool\n" ++
    "  entry run() : UInt64 do\n" ++
    "    match flag with\n" ++
    "    | true => do\n" ++
    "      for i in 0 ..< 4096 bounded 4096 do\n" ++
    "        for j in 0 ..< 4096 bounded 4096 do\n" ++
    "          for k in 0 ..< 4096 bounded 4096 do\n" ++
    "            total := i\n" ++
    "    | false => do\n" ++
    "      total := 0\n" ++
    "    return total\n"
  let (vM, invM, resM) ← boundDraftsWithOrigins session "bound-loop-match" matchSource
  expect (!resM.ok) "bound-loop-match: not ok"
  expect (resM.drafts.size == 1) "bound-loop-match: one draft"
  let locM ← requireLocation "bound-loop-match" resM.drafts[0]!
  let visitsM ← liftResult "visits" (canonicalNodeVisitsV1 vM.program)
  expect ((visitsM.find? (·.path == locM.primaryPath)).map (·.constructorTag)
      == some "Stmt.For")
    "bound-loop-match: primary For"
  -- related: EntryDecl + two ancestor Fors (outer then mid); mirrors fn-nest contract
  expect (locM.relatedPaths.size == 3)
    s!"bound-loop-match: related size 3, got {locM.relatedPaths.size}"
  let some r0M := visitsM.find? (·.path == locM.relatedPaths[0]!) |
    throw <| IO.userError "bound-loop-match: related[0]"
  expect (r0M.constructorTag == "EntryDecl") "bound-loop-match: related[0] EntryDecl"
  expect (locM.relatedPaths.all fun rp =>
      match visitsM.find? (·.path == rp) with
      | some v => v.constructorTag == "EntryDecl" || v.constructorTag == "Stmt.For"
      | none => false)
    "bound-loop-match: related only EntryDecl/Stmt.For"
  let forRelatedM := locM.relatedPaths.filter fun rp =>
    (visitsM.find? (·.path == rp)).map (·.constructorTag) == some "Stmt.For"
  expect (forRelatedM.size == 2) "bound-loop-match: two ancestor Fors"
  expect (!locM.relatedPaths.any (· == locM.primaryPath))
    "bound-loop-match: primary not in related"
  expectBoundDraftPaths "bound-loop-match" invM vM.program resM.drafts
  expectBoundEraseParity "bound-loop-match" vM resM

/-- Overflow in view and init callables. -/
private unsafe def testBoundLoopOverflowViewInit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let viewSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundLoopView where\n" ++
    "  state total : UInt64\n" ++
    "  view peek() : UInt64 do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        for k in 0 ..< 4096 bounded 4096 do\n" ++
    "          total := i\n" ++
    "    return total\n"
  let (vV, invV, resV) ← boundDraftsWithOrigins session "bound-loop-view" viewSource
  expect (!resV.ok) "bound-loop-view: not ok"
  expect (resV.drafts[0]!.diagnostic.message.contains "view 'peek'")
    "bound-loop-view: view label"
  let locV ← requireLocation "bound-loop-view" resV.drafts[0]!
  let visitsV ← liftResult "visits" (canonicalNodeVisitsV1 vV.program)
  expect ((visitsV.find? (·.path == locV.relatedPaths[0]!)).map (·.constructorTag)
      == some "ViewDecl")
    "bound-loop-view: related ViewDecl"
  expectBoundDraftPaths "bound-loop-view" invV vV.program resV.drafts
  expectBoundEraseParity "bound-loop-view" vV resV

  let initSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundLoopInit where\n" ++
    "  state total : UInt64\n" ++
    "  init(seed : UInt64) do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        for k in 0 ..< 4096 bounded 4096 do\n" ++
    "          total := seed\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return total\n"
  let (vI, invI, resI) ← boundDraftsWithOrigins session "bound-loop-init" initSource
  expect (!resI.ok) "bound-loop-init: not ok"
  expect (resI.drafts[0]!.diagnostic.message.contains "init 'init'")
    "bound-loop-init: init label"
  let locI ← requireLocation "bound-loop-init" resI.drafts[0]!
  let visitsI ← liftResult "visits" (canonicalNodeVisitsV1 vI.program)
  expect ((visitsI.find? (·.path == locI.relatedPaths[0]!)).map (·.constructorTag)
      == some "InitDecl")
    "bound-loop-init: related InitDecl"
  expectBoundDraftPaths "bound-loop-init" invI vI.program resI.drafts
  expectBoundEraseParity "bound-loop-init" vI resI

/-- Sibling multi-overflow: two independent overflowing nests → two drafts source order. -/
private unsafe def testBoundSiblingMultiOverflow
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundSiblings where\n" ++
    "  state total : UInt64\n" ++
    "  entry first() : UInt64 do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        for k in 0 ..< 4096 bounded 4096 do\n" ++
    "          total := i\n" ++
    "    return total\n" ++
    "  entry second() : UInt64 do\n" ++
    "    for i in 0 ..< 4096 bounded 4096 do\n" ++
    "      for j in 0 ..< 4096 bounded 4096 do\n" ++
    "        for k in 0 ..< 4096 bounded 4096 do\n" ++
    "          total := i\n" ++
    "    return total\n"
  let (validated, inv, res) ← boundDraftsWithOrigins session "bound-sib" source
  expect (!res.ok) "bound-sib: not ok"
  expect (res.drafts.size == 2) s!"bound-sib: two drafts, got {res.drafts.size}"
  expect (res.drafts[0]!.diagnostic.message.contains "entry 'first'")
    "bound-sib: first then second"
  expect (res.drafts[1]!.diagnostic.message.contains "entry 'second'")
    "bound-sib: second message"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  for i in [0:2] do
    let loc ← requireLocation s!"bound-sib[{i}]" res.drafts[i]!
    expect ((visits.find? (·.path == loc.primaryPath)).map (·.constructorTag)
        == some "Stmt.For")
      s!"bound-sib[{i}]: primary For"
    expect (loc.primaryPath != (← requireLocation s!"bound-sib-other" res.drafts[1-i]!).primaryPath)
      "bound-sib: distinct primaries"
  expectBoundDraftPaths "bound-sib" inv validated.program res.drafts
  expectBoundEraseParity "bound-sib" validated res

/-- Cycle-then-loop phase: cycle draft precedes loop draft; both locate. -/
private unsafe def testBoundCycleThenLoopLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundCycleLoop where\n" ++
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
  let (validated, inv, res) ← boundDraftsWithOrigins session "bound-phase" source
  expect (!res.ok) "bound-phase: not ok"
  expect (res.drafts.size ≥ 2) s!"bound-phase: ≥2, got {res.drafts.size}"
  expect (res.drafts[0]!.diagnostic.message.contains "unbounded recursion")
    "bound-phase: cycle first"
  expect (res.drafts.any (·.diagnostic.message.contains "loop bound product"))
    "bound-phase: has loop"
  expectBoundDraftPaths "bound-phase" inv validated.program res.drafts
  expectBoundEraseParity "bound-phase" validated res

/-- Incomplete duplicate-fn: analysisComplete=false, no bound drafts. -/
private unsafe def testBoundIncompleteDuplicateFn
    (_session : Language.Loader.ParserSession) : IO Unit := do
  let progName ← mkName "BoundDupFn"
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
  let (tables, _) := (buildTables progAst).run {}
  expect tables.fn.hasDuplicateKey "bound-dup-fn: hasDuplicateKey"
  let draftRes := checkBoundsDraftsV1 progAst tables
  expect (!draftRes.analysisComplete) "bound-dup-fn: analysisComplete=false"
  expect (!draftRes.ok) "bound-dup-fn: ok=false"
  expect draftRes.drafts.isEmpty "bound-dup-fn: no bound drafts"
  let erased := checkBoundsV1 progAst tables
  expect (erased.diagnostics.isEmpty) "bound-dup-fn: public empty diags"
  expect (!erased.analysisComplete) "bound-dup-fn: public incomplete"
  expect (!erased.ok) "bound-dup-fn: public not ok"

/-- B7b3c: DisclosureCheck draft authority via Loader origins. -/
private unsafe def discDraftsWithOrigins
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × OriginInventoryV1 × DisclosureCheckDraftResultV1) := do
  let (validated, inv) ← selectWithOrigins session label source
  let res := checkProgramDisclosureDraftsV1 validated
  pure (validated, inv, res)

private def expectDiscDraftPaths
    (label : String) (inv : OriginInventoryV1) (prog : ProgramV1)
    (drafts : Array TypedDiagnosticDraftV1) : IO Unit := do
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 prog)
  for (draft, i) in drafts.zipIdx do
    let loc ← requireLocation s!"{label}[{i}]" draft
    expect (pathInVisits visits loc.primaryPath)
      s!"{label}[{i}]: primary ∈ visits"
    for (rp, j) in loc.relatedPaths.zipIdx do
      expect (pathInVisits visits rp)
        s!"{label}[{i}].related[{j}] ∈ visits"
    expect (!loc.relatedPaths.any (· == loc.primaryPath))
      s!"{label}[{i}]: primary excluded from related"
  let located ← locateAll label inv drafts
  expect (located.size == drafts.size) s!"{label}: locate size"
  for (draft, i) in drafts.zipIdx do
    let loc ← requireLocation s!"{label}[{i}]" draft
    let primaryId ← expectNodeIdSome s!"{label}[{i}]" located[i]!.primary
    expect (primaryId == (← inventoryNodeId inv loc.primaryPath s!"{label}[{i}] primary"))
      s!"{label}[{i}]: primary NodeId exact"
    expectRelatedNodeIdSet s!"{label}[{i}]" inv located[i]!.related loc.relatedPaths

private def expectDiscEraseParity
    (label : String) (validated : ValidatedSourceV1)
    (draftRes : DisclosureCheckDraftResultV1) : IO Unit := do
  let publicArr := checkProgramDisclosureV1 validated
  let publicRes := checkProgramDisclosureResultV1 validated
  eraseParity label draftRes.drafts publicArr
  expect (draftRes.ok == publicRes.ok) s!"{label}: ok parity"
  expect (draftRes.analysisComplete == publicRes.analysisComplete)
    s!"{label}: analysisComplete parity"
  expect (publicArr.map (·.code) == (eraseArray draftRes.drafts).map (·.code))
    s!"{label}: code order parity"
  expect (publicArr.map (·.message) == (eraseArray draftRes.drafts).map (·.message))
    s!"{label}: message order parity"
  expect (publicArr.all (fun d =>
      d.code == .visibilityViolation || d.code == .sourceInvalid || d.code == .internal))
    s!"{label}: public codes are vis/structural only"

private def visitTag
    (visits : Array NodeVisitV1) (path : NormalizedSyntacticPathV1) : Option String :=
  (visits.find? (·.path == path)).map (·.constructorTag)

/-- True when `child` is a proper extension of `parent` (strict prefix of path edges). -/
private def pathIsProperExtensionOf
    (parent child : NormalizedSyntacticPathV1) : Bool :=
  child.size > parent.size && child.extract 0 parent.size == parent

/-- B7b3c: joinVisibilityEvidence unit — label join + cause retention/union. -/
private def testJoinVisibilityEvidenceUnit : IO Unit := do
  let p1 : NormalizedSyntacticPathV1 :=
    #[{ parentTag := "Synthetic", fieldTag := "a", index := 0 }]
  let p2 : NormalizedSyntacticPathV1 :=
    #[{ parentTag := "Synthetic", fieldTag := "b", index := 0 }]
  let priv1 : VisibilityEvidence := { label := .private_, causes := #[p1] }
  let pub1 : VisibilityEvidence := { label := .public_, causes := #[p2] }
  let jPrivPub := joinVisibilityEvidence priv1 pub1
  expect (jPrivPub.label == .private_)
    "joinEvidence priv∪pub: label private (more-secret)"
  expect (jPrivPub.causes == #[p1])
    "joinEvidence priv∪pub: keeps only private causes"
  let jPubPriv := joinVisibilityEvidence pub1 priv1
  expect (jPubPriv.label == .private_)
    "joinEvidence pub∪priv: label private"
  expect (jPubPriv.causes == #[p1])
    "joinEvidence pub∪priv: keeps only private causes"
  let priv2 : VisibilityEvidence := { label := .private_, causes := #[p2] }
  let jEq := joinVisibilityEvidence priv1 priv2
  expect (jEq.label == .private_)
    "joinEvidence priv∪priv: label private"
  expect (jEq.causes == #[p1, p2])
    "joinEvidence priv∪priv: stable-union first-seen left-then-right"
  let jEqRev := joinVisibilityEvidence priv2 priv1
  expect (jEqRev.causes == #[p2, p1])
    "joinEvidence priv∪priv reverse: first-seen order preserved"
  let comm : VisibilityEvidence := { label := .commitment, causes := #[p1] }
  let jComm := joinVisibilityEvidence pub1 comm
  expect (jComm.label == .commitment)
    "joinEvidence pub∪commitment: label commitment"
  expect (jComm.causes == #[p1])
    "joinEvidence pub∪commitment: commitment causes only"
  -- Equal public keeps empty∪nonempty union
  let pubEmpty : VisibilityEvidence := publicEvidence
  let jPub := joinVisibilityEvidence pubEmpty pub1
  expect (jPub.label == .public_) "joinEvidence public∪public: label public"
  expect (jPub.causes == #[p2]) "joinEvidence public∪public: stable-union causes"

/-- Assign private param → public state: primary RHS Expr.Place; related Param+StateDecl+target. -/
private unsafe def testDiscAssignLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscAssign where\n" ++
    "  state total : UInt64\n" ++
    "  entry set(private x : UInt64) : UInt64 do\n" ++
    "    total := x\n" ++
    "    return total\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-assign" source
  expect (!res.ok) "disc-assign: not ok"
  expect res.analysisComplete "disc-assign: complete"
  expect (res.drafts.size == 1) s!"disc-assign: one draft, got {res.drafts.size}"
  let draft := res.drafts[0]!
  expect (draft.diagnostic.code == .visibilityViolation) "disc-assign: code"
  expect (draft.diagnostic.message ==
      "disclosure violation: cannot flow 'private' into 'public'")
    "disc-assign: message"
  let loc ← requireLocation "disc-assign" draft
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Place")
    "disc-assign: primary Expr.Place (RHS)"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Param")
    "disc-assign: related Param"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "StateDecl")
    "disc-assign: related StateDecl"
  expect (loc.relatedPaths.any fun rp =>
      visitTag visits rp == some "Place.Name")
    "disc-assign: related target Place.Name"
  expectDiscDraftPaths "disc-assign" inv validated.program res.drafts
  expectDiscEraseParity "disc-assign" validated res

/-- Private return: primary value expr; related Stmt.Return + EntryDecl + Param. -/
private unsafe def testDiscReturnLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscReturn where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-return" source
  expect (!res.ok) "disc-return: not ok"
  expect (res.drafts.size == 1) "disc-return: one draft"
  let loc ← requireLocation "disc-return" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Place")
    "disc-return: primary Expr.Place"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.Return")
    "disc-return: related Stmt.Return"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "EntryDecl")
    "disc-return: related EntryDecl"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Param")
    "disc-return: related Param cause"
  expectDiscDraftPaths "disc-return" inv validated.program res.drafts
  expectDiscEraseParity "disc-return" validated res

/-- Emit + revert private arg: two drafts; primary each arg; related op stmts. -/
private unsafe def testDiscEmitRevertLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscEmitRevert where\n" ++
    "  event Ev(v : UInt64)\n" ++
    "  error Boom(v : UInt64)\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    emit Ev(x)\n" ++
    "    revert Boom(x)\n" ++
    "    return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-emit-revert" source
  expect (!res.ok) "disc-emit-revert: not ok"
  expect (res.drafts.size ≥ 2) s!"disc-emit-revert: ≥2, got {res.drafts.size}"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let loc0 ← requireLocation "disc-emit-revert[0]" res.drafts[0]!
  let loc1 ← requireLocation "disc-emit-revert[1]" res.drafts[1]!
  expect (visitTag visits loc0.primaryPath == some "Expr.Place")
    "disc-emit-revert[0]: primary arg"
  expect (loc0.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.Emit")
    "disc-emit-revert[0]: related Stmt.Emit"
  expect (visitTag visits loc1.primaryPath == some "Expr.Place")
    "disc-emit-revert[1]: primary arg"
  expect (loc1.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.Revert")
    "disc-emit-revert[1]: related Stmt.Revert"
  expectDiscDraftPaths "disc-emit-revert" inv validated.program res.drafts
  expectDiscEraseParity "disc-emit-revert" validated res

/-- Call + schedule private arg. -/
private unsafe def testDiscCallScheduleLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscCallSchedule where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    call External.Use(x)\n" ++
    "    schedule External.Later(x)\n" ++
    "    return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-call-sched" source
  expect (!res.ok) "disc-call-sched: not ok"
  expect (res.drafts.size ≥ 2) s!"disc-call-sched: ≥2, got {res.drafts.size}"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let loc0 ← requireLocation "disc-call-sched[0]" res.drafts[0]!
  let loc1 ← requireLocation "disc-call-sched[1]" res.drafts[1]!
  expect (loc0.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.Call")
    "disc-call-sched[0]: related Stmt.Call"
  expect (loc1.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.Schedule")
    "disc-call-sched[1]: related Stmt.Schedule"
  expectDiscDraftPaths "disc-call-sched" inv validated.program res.drafts
  expectDiscEraseParity "disc-call-sched" validated res

/-- Private index: primary index expr; related Place.Index. -/
private unsafe def testDiscIndexLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscIndex where\n" ++
    "  state arr : Array UInt64 2\n" ++
    "  entry run(private i : UInt64) : UInt64 do\n" ++
    "    return arr[i]\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-index" source
  expect (!res.ok) "disc-index: not ok"
  expect (res.drafts.size ≥ 1) "disc-index: ≥1 draft"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  -- First violation is index public sink (during place walk before return).
  let loc0 ← requireLocation "disc-index[0]" res.drafts[0]!
  expect (visitTag visits loc0.primaryPath == some "Expr.Place")
    "disc-index[0]: primary index Expr.Place"
  expect (loc0.relatedPaths.any fun rp => visitTag visits rp == some "Place.Index")
    "disc-index[0]: related Place.Index"
  expectDiscDraftPaths "disc-index" inv validated.program res.drafts
  expectDiscEraseParity "disc-index" validated res

/-- localCall private arg → public fn param: primary arg; related =
    entry Param secret (value cause) + drop params[0] (sink contract). -/
private unsafe def testDiscLocalCallParamLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscLocalCall where\n" ++
    "  fn drop(x : UInt64) : UInt64 do\n" ++
    "    return 0\n" ++
    "  entry run(private secret : UInt64) : UInt64 do\n" ++
    "    let y : UInt64 := drop(secret)\n" ++
    "    return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-local-call" source
  expect (!res.ok) "disc-local-call: not ok"
  expect (res.drafts.size == 1) s!"disc-local-call: one, got {res.drafts.size}"
  let loc ← requireLocation "disc-local-call" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Place")
    "disc-local-call: primary arg Expr.Place"
  let tables := (resolveProgramV1 validated).tables
  let dropName ← mkName "drop"
  let runName ← mkName "run"
  let some fnPath := itemPathForNamed? tables .fn dropName |
    throw <| IO.userError "disc-local-call: drop FnDecl path"
  let some dropParamPath := fnParamPath? tables dropName 0 |
    throw <| IO.userError "disc-local-call: drop params[0] path"
  let some entryPath := itemPathForNamed? tables .entry runName |
    throw <| IO.userError "disc-local-call: entry path"
  let entryParamPath ←
    liftResult "disc-local-call entry params[0]"
      (childPathV1 entryPath "EntryDecl" "params" 0)
  -- Exact related set under public PC: value-cause entry Param + sink drop Param.
  expect (loc.relatedPaths.size == 2)
    s!"disc-local-call: related size 2 (entry Param + drop Param), got {loc.relatedPaths.size}"
  expect (loc.relatedPaths.any (· == entryParamPath))
    "disc-local-call: related includes entry Param secret (value cause)"
  expect (loc.relatedPaths.any (· == dropParamPath))
    "disc-local-call: related includes drop params[0] (sink contract)"
  expect (pathIsProperExtensionOf fnPath dropParamPath)
    "disc-local-call: drop Param is proper child of FnDecl drop"
  expect (loc.relatedPaths.any fun rp => pathIsProperExtensionOf fnPath rp)
    "disc-local-call: some related path is child of drop FnDecl"
  expect (pathIsProperExtensionOf entryPath entryParamPath)
    "disc-local-call: entry Param is proper child of EntryDecl"
  -- Sink contract Param is under drop, not a second entry-only Param set.
  let dropRelatedParams := loc.relatedPaths.filter fun rp =>
    pathIsProperExtensionOf fnPath rp && visitTag visits rp == some "Param"
  expect (dropRelatedParams.size == 1)
    s!"disc-local-call: exactly one related Param under drop, got {dropRelatedParams.size}"
  expect (dropRelatedParams[0]! == dropParamPath)
    "disc-local-call: drop-related Param == fnParamPath? drop 0"
  expectDiscDraftPaths "disc-local-call" inv validated.program res.drafts
  expectDiscEraseParity "disc-local-call" validated res

/-- Const private state init: primary const value; related ConstDecl + StateDecl. -/
private unsafe def testDiscConstLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscConst where\n" ++
    "  state private secret : UInt64\n" ++
    "  const leak : UInt64 := secret\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-const" source
  expect (!res.ok) "disc-const: not ok"
  expect (res.drafts.size == 1) "disc-const: one draft"
  let loc ← requireLocation "disc-const" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Place")
    "disc-const: primary value Expr.Place"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "ConstDecl")
    "disc-const: related ConstDecl"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "StateDecl")
    "disc-const: related StateDecl cause"
  expectDiscDraftPaths "disc-const" inv validated.program res.drafts
  expectDiscEraseParity "disc-const" validated res

/-- Assert private condition: primary condition; related Stmt.Assert. -/
private unsafe def testDiscAssertLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscAssert where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    assert flag\n" ++
    "    return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-assert" source
  expect (!res.ok) "disc-assert: not ok"
  expect (res.drafts.size == 1) "disc-assert: one draft"
  let loc ← requireLocation "disc-assert" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Place")
    "disc-assert: primary condition"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.Assert")
    "disc-assert: related Stmt.Assert"
  expectDiscDraftPaths "disc-assert" inv validated.program res.drafts
  expectDiscEraseParity "disc-assert" validated res

/-- For private start/end: primary endpoint expr; related Stmt.For. -/
private unsafe def testDiscForEndpointLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscFor where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private priv : UInt64) : UInt64 do\n" ++
    "    for i in 0 ..< priv bounded 10 do\n" ++
    "      total := i\n" ++
    "    return total\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-for" source
  expect (!res.ok) "disc-for: not ok"
  expect (res.drafts.size ≥ 1) "disc-for: ≥1"
  let loc ← requireLocation "disc-for" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Place")
    "disc-for: primary end Expr.Place"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.For")
    "disc-for: related Stmt.For"
  expectDiscDraftPaths "disc-for" inv validated.program res.drafts
  expectDiscEraseParity "disc-for" validated res

/-- Path to entry body Block for a named entry. -/
private def entryBodyPath
    (tables : TypedDeclTablesV1) (entryName : SourceNameComponentV1) :
    IO NormalizedSyntacticPathV1 := do
  let some entryPath := itemPathForNamed? tables .entry entryName |
    throw <| IO.userError "entryBodyPath: missing entry"
  liftResult "entry body" (directChildPathV1 entryPath "EntryDecl" "body")

/-- Path to statements[idx] under a Block path. -/
private def blockStmtPath
    (blockPath : NormalizedSyntacticPathV1) (idx : Nat) :
    IO NormalizedSyntacticPathV1 :=
  liftResult s!"Block.statements[{idx}]"
    (indexChildPathV1 blockPath "Block" "statements" idx)

/-- B7b3cR: withControlRootEvidence unit — append control root after causes. -/
private def testWithControlRootEvidenceUnit : IO Unit := do
  let pDecl : NormalizedSyntacticPathV1 :=
    #[{ parentTag := "Synthetic", fieldTag := "decl", index := 0 }]
  let pCtrl : NormalizedSyntacticPathV1 :=
    #[{ parentTag := "Synthetic", fieldTag := "control", index := 0 }]
  let priv : VisibilityEvidence := { label := .private_, causes := #[pDecl] }
  let aug := withControlRootEvidence priv (some pCtrl)
  expect (aug.label == .private_) "withControlRoot: label unchanged"
  expect (aug.causes == #[pDecl, pCtrl])
    "withControlRoot: decl causes first, control root appended"
  let dup := withControlRootEvidence aug (some pDecl)
  expect (dup.causes == #[pDecl, pCtrl])
    "withControlRoot: existing cause not duplicated"
  let noneKeep := withControlRootEvidence priv none
  expect (noneKeep.causes == #[pDecl]) "withControlRoot: none leaves causes"
  -- Join still label-authoritative after augmentation
  let pubCtrl : VisibilityEvidence :=
    withControlRootEvidence publicEvidence (some pCtrl)
  let j := joinVisibilityEvidence priv pubCtrl
  expect (j.label == .private_) "withControlRoot+join: more-secret wins"
  expect (j.causes == #[pDecl])
    "withControlRoot+join: lower-secrecy control root discarded"

/-- If private condition taints public return: primary return value; related =
    Param (PC decl cause) + exact condition Expr root + sink sites. -/
private unsafe def testDiscIfPcLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscIfPc where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      return 1\n" ++
    "    else\n" ++
    "      return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-if-pc" source
  expect (!res.ok) "disc-if-pc: not ok"
  expect (res.drafts.size ≥ 2) s!"disc-if-pc: ≥2 arms, got {res.drafts.size}"
  expect (res.drafts[0]!.diagnostic.message ==
      "disclosure violation: cannot flow 'private' into 'public'")
    "disc-if-pc: message uses joined PC label private"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let bodyPath ← entryBodyPath tables runName
  let ifStmt ← blockStmtPath bodyPath 0
  let condPath ←
    liftResult "if cond" (directChildPathV1 ifStmt "Stmt.If" "condition")
  let some entryPath := itemPathForNamed? tables .entry runName |
    throw <| IO.userError "disc-if-pc: entry path"
  let paramPath ←
    liftResult "if param" (childPathV1 entryPath "EntryDecl" "params" 0)
  expect (visitTag visits condPath == some "Expr.Place")
    "disc-if-pc: condition path is Expr.Place"
  for i in [0:2] do
    let loc ← requireLocation s!"disc-if-pc[{i}]" res.drafts[i]!
    expect (visitTag visits loc.primaryPath == some "Expr.Literal")
      s!"disc-if-pc[{i}]: primary public literal"
    expect (loc.relatedPaths.any (· == paramPath))
      s!"disc-if-pc[{i}]: PC cause Param exact path"
    expect (loc.relatedPaths.any (· == condPath))
      s!"disc-if-pc[{i}]: PC control root = Stmt.If condition Expr"
    expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Stmt.Return")
      s!"disc-if-pc[{i}]: related Stmt.Return"
  expectDiscDraftPaths "disc-if-pc" inv validated.program res.drafts
  expectDiscEraseParity "disc-if-pc" validated res

/-- Private state as if condition: related includes StateDecl + condition Expr root. -/
private unsafe def testDiscIfPcStateLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscIfPcState where\n" ++
    "  state private flag : Bool\n" ++
    "  entry run() : UInt64 do\n" ++
    "    if flag then\n" ++
    "      return 1\n" ++
    "    return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-if-pc-state" source
  expect (!res.ok) "disc-if-pc-state: not ok"
  expect (res.drafts.size ≥ 1) s!"disc-if-pc-state: ≥1, got {res.drafts.size}"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let flagName ← mkName "flag"
  let bodyPath ← entryBodyPath tables runName
  let ifStmt ← blockStmtPath bodyPath 0
  let condPath ←
    liftResult "if-state cond" (directChildPathV1 ifStmt "Stmt.If" "condition")
  let some statePath := itemPathForNamed? tables .state flagName |
    throw <| IO.userError "disc-if-pc-state: StateDecl path"
  let loc ← requireLocation "disc-if-pc-state[0]" res.drafts[0]!
  expect (visitTag visits loc.primaryPath == some "Expr.Literal")
    "disc-if-pc-state: primary literal"
  expect (loc.relatedPaths.any (· == statePath))
    "disc-if-pc-state: related StateDecl"
  expect (loc.relatedPaths.any (· == condPath))
    "disc-if-pc-state: related condition Expr root"
  expectDiscDraftPaths "disc-if-pc-state" inv validated.program res.drafts
  expectDiscEraseParity "disc-if-pc-state" validated res

/-- Match statement private scrutinee: PC taint includes Param + scrutinee Expr root. -/
private unsafe def testDiscMatchStmtLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscMatchStmt where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    match flag with\n" ++
    "    | true => do\n" ++
    "      return 1\n" ++
    "    | false => do\n" ++
    "      return 0\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-match-stmt" source
  expect (!res.ok) "disc-match-stmt: not ok"
  expect (res.drafts.size ≥ 2) s!"disc-match-stmt: ≥2, got {res.drafts.size}"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let bodyPath ← entryBodyPath tables runName
  let matchStmt ← blockStmtPath bodyPath 0
  let scrutPath ←
    liftResult "match scrut" (directChildPathV1 matchStmt "Stmt.Match" "scrutinee")
  let some entryPath := itemPathForNamed? tables .entry runName |
    throw <| IO.userError "disc-match-stmt: entry path"
  let paramPath ←
    liftResult "match param" (childPathV1 entryPath "EntryDecl" "params" 0)
  let loc ← requireLocation "disc-match-stmt[0]" res.drafts[0]!
  expect (visitTag visits loc.primaryPath == some "Expr.Literal")
    "disc-match-stmt: primary literal"
  expect (loc.relatedPaths.any (· == paramPath))
    "disc-match-stmt: PC/scrut Param cause exact"
  expect (loc.relatedPaths.any (· == scrutPath))
    "disc-match-stmt: PC control root = Stmt.Match scrutinee Expr"
  expect (visitTag visits scrutPath == some "Expr.Place")
    "disc-match-stmt: scrutinee is Expr.Place"
  expectDiscDraftPaths "disc-match-stmt" inv validated.program res.drafts
  expectDiscEraseParity "disc-match-stmt" validated res

/-- Match expression private scrutinee returned: primary match expr; related =
    Param + scrutinee Expr root (not primary). -/
private unsafe def testDiscMatchExprLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscMatchExpr where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    return\n" ++
    "      match flag with\n" ++
    "      | true => 1\n" ++
    "      | false => 0\n" ++
    "      | _ => 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-match-expr" source
  expect (!res.ok) "disc-match-expr: not ok"
  expect (res.drafts.size ≥ 1) "disc-match-expr: ≥1"
  let loc ← requireLocation "disc-match-expr" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Match")
    "disc-match-expr: primary Expr.Match"
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let bodyPath ← entryBodyPath tables runName
  let retStmt ← blockStmtPath bodyPath 0
  let matchExpr ←
    liftResult "match value" (directChildPathV1 retStmt "Stmt.Return" "value")
  let scrutPath ←
    liftResult "expr scrut" (directChildPathV1 matchExpr "Expr.Match" "scrutinee")
  let some entryPath := itemPathForNamed? tables .entry runName |
    throw <| IO.userError "disc-match-expr: entry path"
  let paramPath ←
    liftResult "expr param" (childPathV1 entryPath "EntryDecl" "params" 0)
  expect (loc.primaryPath == matchExpr)
    "disc-match-expr: primary exact Expr.Match path"
  expect (loc.relatedPaths.any (· == paramPath))
    "disc-match-expr: scrut Param cause"
  expect (loc.relatedPaths.any (· == scrutPath))
    "disc-match-expr: scrutinee Expr root in related (not primary)"
  expect (!loc.relatedPaths.any (· == matchExpr))
    "disc-match-expr: primary excluded from related"
  expectDiscDraftPaths "disc-match-expr" inv validated.program res.drafts
  expectDiscEraseParity "disc-match-expr" validated res

/-- Binder inherits scrutinee: return of match expr ⇒ primary Expr.Match;
    related includes Param + scrutinee Expr root. -/
private unsafe def testDiscBinderLeakLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscBinder where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return\n" ++
    "      match x with\n" ++
    "      | y => y\n" ++
    "      | _ => 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-binder" source
  expect (!res.ok) "disc-binder: not ok"
  expect (res.drafts.size ≥ 1) "disc-binder: ≥1"
  let loc ← requireLocation "disc-binder" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  -- Primary = exact value expression submitted to return sink = the match expr.
  expect (visitTag visits loc.primaryPath == some "Expr.Match")
    "disc-binder: primary Expr.Match (return of match expr; not arm Place)"
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let bodyPath ← entryBodyPath tables runName
  let retStmt ← blockStmtPath bodyPath 0
  let matchExpr ←
    liftResult "binder match" (directChildPathV1 retStmt "Stmt.Return" "value")
  let scrutPath ←
    liftResult "binder scrut" (directChildPathV1 matchExpr "Expr.Match" "scrutinee")
  let some entryPath := itemPathForNamed? tables .entry runName |
    throw <| IO.userError "disc-binder: entry path"
  let paramPath ←
    liftResult "binder param" (childPathV1 entryPath "EntryDecl" "params" 0)
  expect (loc.primaryPath == matchExpr) "disc-binder: primary exact match path"
  expect (loc.relatedPaths.any (· == paramPath))
    "disc-binder: Param cause from scrutinee/binder evidence"
  expect (loc.relatedPaths.any (· == scrutPath))
    "disc-binder: scrutinee Expr root in related"
  expectDiscDraftPaths "disc-binder" inv validated.program res.drafts
  expectDiscEraseParity "disc-binder" validated res

/-- Multi-error source order: private then commitment assign. -/
private unsafe def testDiscMultiErrorOrderLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscMulti where\n" ++
    "  state a : UInt64\n" ++
    "  state b : UInt64\n" ++
    "  entry run(private x : UInt64, commitment y : UInt64) : UInt64 do\n" ++
    "    a := x\n" ++
    "    b := y\n" ++
    "    return 0\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-multi" source
  expect (!res.ok) "disc-multi: not ok"
  expect (res.drafts.size ≥ 2) s!"disc-multi: ≥2, got {res.drafts.size}"
  expect (res.drafts[0]!.diagnostic.message.contains "private")
    "disc-multi: first private"
  expect (res.drafts[1]!.diagnostic.message.contains "commitment")
    "disc-multi: second commitment"
  expectDiscDraftPaths "disc-multi" inv validated.program res.drafts
  expectDiscEraseParity "disc-multi" validated res

/-- Equal-label cause union: private x + private y returned → both Param causes;
    end-to-end message uses joined label `private`. -/
private unsafe def testDiscEqualLabelCauseUnion
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscJoin where\n" ++
    "  entry run(private x : UInt64, private y : UInt64) : UInt64 do\n" ++
    "    return x + y\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-join" source
  expect (!res.ok) "disc-join: not ok"
  expect (res.drafts.size == 1) s!"disc-join: one draft, got {res.drafts.size}"
  expect (res.drafts[0]!.diagnostic.message ==
      "disclosure violation: cannot flow 'private' into 'public'")
    "disc-join: message uses joined label private"
  let loc ← requireLocation "disc-join" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  expect (visitTag visits loc.primaryPath == some "Expr.Binary")
    "disc-join: primary Expr.Binary"
  let paramRelated := loc.relatedPaths.filter fun rp =>
    visitTag visits rp == some "Param"
  expect (paramRelated.size ≥ 2)
    s!"disc-join: ≥2 Param causes (equal-label union), got {paramRelated.size}"
  expectDiscDraftPaths "disc-join" inv validated.program res.drafts
  expectDiscEraseParity "disc-join" validated res

/-- Nested if PC restore: outer public after private branch still OK on public path;
    private branch still reports (draft count unchanged by control-root repair). -/
private unsafe def testDiscNestedIfPcRestore
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscNestedIf where\n" ++
    "  state total : UInt64\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      total := 1\n" ++
    "    total := 0\n" ++
    "    return total\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-nested-if" source
  expect (!res.ok) "disc-nested-if: not ok"
  -- Only the assign inside private if is a violation; later public assign/return OK.
  expect (res.drafts.size == 1)
    s!"disc-nested-if: exactly one (PC restored), got {res.drafts.size}"
  let loc ← requireLocation "disc-nested-if" res.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let bodyPath ← entryBodyPath tables runName
  let ifStmt ← blockStmtPath bodyPath 0
  let condPath ←
    liftResult "nested-if cond" (directChildPathV1 ifStmt "Stmt.If" "condition")
  expect (visitTag visits loc.primaryPath == some "Expr.Literal")
    "disc-nested-if: primary literal 1"
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Param")
    "disc-nested-if: PC Param"
  expect (loc.relatedPaths.any (· == condPath))
    "disc-nested-if: PC control root condition Expr"
  expectDiscDraftPaths "disc-nested-if" inv validated.program res.drafts
  expectDiscEraseParity "disc-nested-if" validated res

/-- Nested equal-private ifs: both condition Expr roots retained in related (stable union). -/
private unsafe def testDiscNestedEqualPrivatePcControls
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscNestedEqPriv where\n" ++
    "  entry run(private outer : Bool, private inner : Bool) : UInt64 do\n" ++
    "    if outer then\n" ++
    "      if inner then\n" ++
    "        return 1\n" ++
    "      return 0\n" ++
    "    return 0\n"
  let (validated, inv, res) ←
    discDraftsWithOrigins session "disc-nested-eq-priv" source
  expect (!res.ok) "disc-nested-eq-priv: not ok"
  -- return 1 under both private PCs + return 0 under outer only + return 0 public path OK
  expect (res.drafts.size ≥ 1)
    s!"disc-nested-eq-priv: ≥1, got {res.drafts.size}"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let bodyPath ← entryBodyPath tables runName
  let outerIf ← blockStmtPath bodyPath 0
  let outerCond ←
    liftResult "outer cond" (directChildPathV1 outerIf "Stmt.If" "condition")
  let thenBlock ←
    liftResult "outer then" (directChildPathV1 outerIf "Stmt.If" "thenBlock")
  let innerIf ← blockStmtPath thenBlock 0
  let innerCond ←
    liftResult "inner cond" (directChildPathV1 innerIf "Stmt.If" "condition")
  let some entryPath := itemPathForNamed? tables .entry runName |
    throw <| IO.userError "disc-nested-eq-priv: entry"
  let outerParam ←
    liftResult "outer param" (childPathV1 entryPath "EntryDecl" "params" 0)
  let innerParam ←
    liftResult "inner param" (childPathV1 entryPath "EntryDecl" "params" 1)
  -- First draft is return 1 under both private controls
  let loc ← requireLocation "disc-nested-eq-priv[0]" res.drafts[0]!
  expect (visitTag visits loc.primaryPath == some "Expr.Literal")
    "disc-nested-eq-priv: primary literal 1"
  expect (loc.relatedPaths.any (· == outerParam))
    "disc-nested-eq-priv: outer Param"
  expect (loc.relatedPaths.any (· == innerParam))
    "disc-nested-eq-priv: inner Param"
  expect (loc.relatedPaths.any (· == outerCond))
    "disc-nested-eq-priv: outer condition Expr root retained"
  expect (loc.relatedPaths.any (· == innerCond))
    "disc-nested-eq-priv: inner condition Expr root retained (equal-label union)"
  expectDiscDraftPaths "disc-nested-eq-priv" inv validated.program res.drafts
  expectDiscEraseParity "disc-nested-eq-priv" validated res

/-- Lower-secrecy nested control under more-secret outer PC: inner control excluded. -/
private unsafe def testDiscNestedLowerSecrecyPcExcluded
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscNestedMix where\n" ++
    "  entry run(private outer : Bool, flag : Bool) : UInt64 do\n" ++
    "    if outer then\n" ++
    "      if flag then\n" ++
    "        return 1\n" ++
    "      return 0\n" ++
    "    return 0\n"
  let (validated, inv, res) ←
    discDraftsWithOrigins session "disc-nested-mix" source
  expect (!res.ok) "disc-nested-mix: not ok"
  expect (res.drafts.size ≥ 1)
    s!"disc-nested-mix: ≥1, got {res.drafts.size}"
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 validated.program)
  let tables := (resolveProgramV1 validated).tables
  let runName ← mkName "run"
  let bodyPath ← entryBodyPath tables runName
  let outerIf ← blockStmtPath bodyPath 0
  let outerCond ←
    liftResult "mix outer cond" (directChildPathV1 outerIf "Stmt.If" "condition")
  let thenBlock ←
    liftResult "mix outer then" (directChildPathV1 outerIf "Stmt.If" "thenBlock")
  let innerIf ← blockStmtPath thenBlock 0
  let innerCond ←
    liftResult "mix inner cond" (directChildPathV1 innerIf "Stmt.If" "condition")
  let some entryPath := itemPathForNamed? tables .entry runName |
    throw <| IO.userError "disc-nested-mix: entry"
  let outerParam ←
    liftResult "mix outer param" (childPathV1 entryPath "EntryDecl" "params" 0)
  let innerParam ←
    liftResult "mix inner param" (childPathV1 entryPath "EntryDecl" "params" 1)
  let loc ← requireLocation "disc-nested-mix[0]" res.drafts[0]!
  expect (visitTag visits loc.primaryPath == some "Expr.Literal")
    "disc-nested-mix: primary literal 1"
  expect (loc.relatedPaths.any (· == outerParam))
    "disc-nested-mix: outer private Param retained"
  expect (loc.relatedPaths.any (· == outerCond))
    "disc-nested-mix: outer condition Expr root retained"
  expect (!loc.relatedPaths.any (· == innerParam))
    "disc-nested-mix: public inner Param excluded (lower-secrecy)"
  expect (!loc.relatedPaths.any (· == innerCond))
    "disc-nested-mix: public inner condition Expr root excluded"
  expectDiscDraftPaths "disc-nested-mix" inv validated.program res.drafts
  expectDiscEraseParity "disc-nested-mix" validated res

/-- Shadowing: local public shadows private state; no VIS. Negative: private param → public. -/
private unsafe def testDiscShadowingLocations
    (session : Language.Loader.ParserSession) : IO Unit := do
  let okSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscShadowOk where\n" ++
    "  state private total : UInt64\n" ++
    "  entry run(amount : UInt64) : UInt64 do\n" ++
    "    let total : UInt64 := amount\n" ++
    "    return total\n"
  let (vOk, invOk, resOk) ← discDraftsWithOrigins session "disc-shadow-ok" okSrc
  expect resOk.ok "disc-shadow-ok: ok"
  expect resOk.drafts.isEmpty "disc-shadow-ok: no drafts"
  expectDiscEraseParity "disc-shadow-ok" vOk resOk
  let _ := invOk

  let negSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscShadowNeg where\n" ++
    "  state private secret : UInt64\n" ++
    "  state public_total : UInt64\n" ++
    "  entry run(private secret : UInt64) : UInt64 do\n" ++
    "    public_total := secret\n" ++
    "    return 0\n"
  let (vNeg, invNeg, resNeg) ← discDraftsWithOrigins session "disc-shadow-neg" negSrc
  expect (!resNeg.ok) "disc-shadow-neg: not ok"
  expect (resNeg.drafts.size == 1) "disc-shadow-neg: one"
  let loc ← requireLocation "disc-shadow-neg" resNeg.drafts[0]!
  let visits ← liftResult "visits" (canonicalNodeVisitsV1 vNeg.program)
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "Param")
    "disc-shadow-neg: Param (not private state)"
  -- Sink site may include public_total StateDecl; private state must not be the value cause.
  expect (loc.relatedPaths.any fun rp => visitTag visits rp == some "StateDecl")
    "disc-shadow-neg: related public sink StateDecl"
  expectDiscDraftPaths "disc-shadow-neg" invNeg vNeg.program resNeg.drafts
  expectDiscEraseParity "disc-shadow-neg" vNeg resNeg

/-- Incomplete duplicate-fn: no invented VIS drafts. -/
private unsafe def testDiscIncompleteDuplicateFn
    (_session : Language.Loader.ParserSession) : IO Unit := do
  let progName ← mkName "DiscDupFn"
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
  let (tables, _) := (buildTables progAst).run {}
  expect tables.fn.hasDuplicateKey "disc-dup-fn: hasDuplicateKey"
  let draftRes := checkDisclosureDraftsV1 progAst tables
  expect (!draftRes.analysisComplete) "disc-dup-fn: analysisComplete=false"
  expect (!draftRes.ok) "disc-dup-fn: ok=false"
  expect draftRes.drafts.isEmpty "disc-dup-fn: no VIS drafts"
  let erased := checkDisclosureV1 progAst tables
  expect (erased.diagnostics.isEmpty) "disc-dup-fn: public empty diags"
  expect (!erased.analysisComplete) "disc-dup-fn: public incomplete"
  expect (!erased.ok) "disc-dup-fn: public not ok"

/-- All disclosure draft paths for a mixed sink program are in visits. -/
private unsafe def testDiscAllDraftPathsInVisits
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscAllPaths where\n" ++
    "  state total : UInt64\n" ++
    "  event Ev(v : UInt64)\n" ++
    "  entry run(private x : UInt64, private flag : Bool) : UInt64 do\n" ++
    "    total := x\n" ++
    "    if flag then\n" ++
    "      emit Ev(0)\n" ++
    "      return 1\n" ++
    "    return x\n"
  let (validated, inv, res) ← discDraftsWithOrigins session "disc-all" source
  expect (!res.ok) "disc-all: not ok"
  expect (res.drafts.size ≥ 3) s!"disc-all: ≥3, got {res.drafts.size}"
  expectDiscDraftPaths "disc-all" inv validated.program res.drafts
  expectDiscEraseParity "disc-all" validated res

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testUnknownPlaceName session
  testRecursiveTypeNamed session
  testDuplicateLaterFirst session
  testWrongCategoryRelated session
  testStructEnumVariantConstructorRelated session
  testSelfCycleLocations session
  testTwoFnCycleLocations session
  testResolutionBeforeCallGraphOrder session
  testAllDraftPathsInVisits session
  -- B7b2 TypeCheck locations
  testTypeCheckUnknownField session
  testTypeCheckIntegerLiteralRange session
  testTypeCheckBinaryMismatch session
  testTypeCheckConstructorArity session
  testTypeCheckLocalCallArity session
  testTypeCheckLocalCallArgType session
  testTypeCheckStringPattern session
  testTypeCheckNonExhaustive session
  testTypeCheckArmMismatch session
  testTypeCheckReturnResult session
  testTypeCheckAssignState session
  testTypeCheckAssertBool session
  testTypeCheckRevertArity session
  testTypeCheckEmitArg session
  testTypeCheckConstValue session
  testTypeCheckInvariantPredicate session
  testTypeCheckBareReturn session
  testTypeCheckResolutionShortCircuit session
  testTypeCheckAllDraftPathsInVisits session
  -- B7b3a EffectCheck locations
  testEffectDirectStateRead session
  testEffectDirectStateWrite session
  testEffectDirectStmtSites session
  testEffectMultiKindOrder session
  testEffectViewLocations session
  testEffectTransitiveOneHop session
  testEffectTransitiveMultiHop session
  testEffectDuplicateCallsites session
  testEffectCycleEvidence session
  testEffectShadowingLocations session
  testEffectIncompleteDuplicateFn session
  testEffectAllDraftPathsInVisits session
  -- B7b3b BoundCheck locations
  testBoundSelfCycleLocations session
  testBoundTwoFnCycleLocations session
  testBoundThreeFnCycleLocations session
  testBoundLoopOverflowFnLocations session
  testBoundLoopOverflowEntryIfMatch session
  testBoundLoopOverflowViewInit session
  testBoundSiblingMultiOverflow session
  testBoundCycleThenLoopLocations session
  testBoundIncompleteDuplicateFn session
  -- B7b3c DisclosureCheck locations (+ B7b3cR control-root repair)
  testJoinVisibilityEvidenceUnit
  testWithControlRootEvidenceUnit
  testDiscAssignLocations session
  testDiscReturnLocations session
  testDiscEmitRevertLocations session
  testDiscCallScheduleLocations session
  testDiscIndexLocations session
  testDiscLocalCallParamLocations session
  testDiscConstLocations session
  testDiscAssertLocations session
  testDiscForEndpointLocations session
  testDiscIfPcLocations session
  testDiscIfPcStateLocations session
  testDiscMatchStmtLocations session
  testDiscMatchExprLocations session
  testDiscBinderLeakLocations session
  testDiscMultiErrorOrderLocations session
  testDiscEqualLabelCauseUnion session
  testDiscNestedIfPcRestore session
  testDiscNestedEqualPrivatePcControls session
  testDiscNestedLowerSecrecyPcExcluded session
  testDiscShadowingLocations session
  testDiscIncompleteDuplicateFn session
  testDiscAllDraftPathsInVisits session
  IO.println "Tests.Typed.DiagnosticLocationsV1: all assertions passed"

end Tests.Typed.DiagnosticLocationsV1
