/-
  B7b1 + B7b2: Typed diagnostic-draft path materialization through B7a
  OriginInventoryV1.

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
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.DiagnosticDraftV1
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
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.DiagnosticDraftV1
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
  IO.println "Tests.Typed.DiagnosticLocationsV1: all assertions passed"

end Tests.Typed.DiagnosticLocationsV1
