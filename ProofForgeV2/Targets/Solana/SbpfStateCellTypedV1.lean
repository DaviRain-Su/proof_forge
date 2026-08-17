import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Typed.AuthorityCustodyCheckV1
import ProofForgeV2.Typed.BoundCheckV1
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.CheckV1
import ProofForgeV2.Typed.ContextExtensionCheckV1
import ProofForgeV2.Typed.DisclosureCheckV1
import ProofForgeV2.Typed.EffectCheckV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

/-!
# StateCell production Typed certificate

Kernel replay of the production structure and type-check phases over the exact
`program StateCell` source captured by the elaborator. The proof decomposes the
real source in declaration order and reuses the production table builder,
resolver, canonical path helpers, and bounded recursive walkers. It defines no
alternate checker and supplies no replacement program to production code.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Examples
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

private def item0 := StateCell.Source.subjectV1.program.items[0]'(by decide)
private def item1 := StateCell.Source.subjectV1.program.items[1]'(by decide)
private def item2 := StateCell.Source.subjectV1.program.items[2]'(by decide)
private def item3 := StateCell.Source.subjectV1.program.items[3]'(by decide)

private def initDeclOption :=
  match item1 with
  | .init declaration => some declaration
  | _ => none

private theorem initDeclSome : initDeclOption.isSome = true := by rfl

private def initDecl := initDeclOption.get initDeclSome

private theorem item1Init : item1 = .init initDecl := by rfl

private def stateDeclOption :=
  match item0 with
  | .state declaration => some declaration
  | _ => none

private theorem stateDeclSome : stateDeclOption.isSome = true := by rfl

private def stateDecl := stateDeclOption.get stateDeclSome

private def initialName := initDecl.params[0]'(by decide) |>.name
private def countName := stateDecl.name
private def initScope := mkBaseScope initDecl.params

private def initialParam := initDecl.params[0]'(by decide)

private theorem initDeclParams : initDecl.params = #[initialParam] := by rfl
private theorem initialParamType : initialParam.type_ = .uint 64 := by rfl
private theorem initDeclBody :
    initDecl.body.statements.toList =
      [.assign (.name countName) (.place (.name initialName))] := by rfl
private theorem initBaseScope : mkBaseScope initDecl.params = initScope := by rfl
private theorem initBaseScopeArray : mkBaseScope #[initialParam] = initScope := by
  rw [← initDeclParams]
  exact initBaseScope

private theorem initialInParams : initialName ∈ initScope.params := by
  simp [initialName, initScope, initDecl, initDeclOption, item1, mkBaseScope,
    StateCell.Source.subjectV1, StateCell.Source.quotedProgramV1]

private theorem countNotLocal : countName ∉ initScope.locals := by
  simp [countName, initScope, initDecl, initDeclOption, stateDecl,
    stateDeclOption, item0, item1, mkBaseScope, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1]

private theorem countNotParam : countName ∉ initScope.params := by
  simp [countName, initScope, initDecl, initDeclOption, stateDecl,
    stateDeclOption, item0, item1, mkBaseScope, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1]

private theorem item0State : item0 = .state stateDecl := by rfl
private theorem stateDeclType : stateDecl.type_ = .uint 64 := by rfl

private def incrementDeclOption :=
  match item2 with
  | .entry declaration => some declaration
  | _ => none

private theorem incrementDeclSome : incrementDeclOption.isSome = true := by rfl
private def incrementDecl := incrementDeclOption.get incrementDeclSome
private theorem item2Entry : item2 = .entry incrementDecl := by rfl
private def deltaParam := incrementDecl.params[0]'(by decide)
private def deltaName := deltaParam.name
private def incrementScope := mkBaseScope incrementDecl.params
private theorem incrementDeclParams : incrementDecl.params = #[deltaParam] := by rfl
private theorem deltaParamType : deltaParam.type_ = .uint 64 := by rfl
private theorem incrementDeclResult : incrementDecl.result = .uint 64 := by rfl
private theorem incrementDeclBody :
    incrementDecl.body.statements.toList =
      [.assign (.name countName)
          (.binary .add (.place (.name countName)) (.place (.name deltaName))),
        .return_ (some (.place (.name countName)))] := by rfl
private theorem incrementBaseScopeArray :
    mkBaseScope #[deltaParam] = incrementScope := by
  rw [← incrementDeclParams]
  rfl
private theorem incrementScopeNoAdded :
    ({ locals := incrementScope.locals, params := incrementScope.params } : Scope) =
      incrementScope := by
  cases incrementScope
  rfl

private theorem deltaInParams : deltaName ∈ incrementScope.params := by
  simp [deltaName, incrementScope, deltaParam, incrementDecl, incrementDeclOption,
    item2, mkBaseScope, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1]
private theorem incrementCountNotLocal : countName ∉ incrementScope.locals := by
  simp [countName, incrementScope, incrementDecl,
    incrementDeclOption, stateDecl, stateDeclOption, item0, item2, mkBaseScope,
    StateCell.Source.subjectV1, StateCell.Source.quotedProgramV1]
private theorem incrementCountNotParam : countName ∉ incrementScope.params := by
  simp [countName, incrementScope, incrementDecl,
    incrementDeclOption, stateDecl, stateDeclOption, item0, item2, mkBaseScope,
    StateCell.Source.subjectV1, StateCell.Source.quotedProgramV1]

private def getDeclOption :=
  match item3 with
  | .view declaration => some declaration
  | _ => none

private theorem getDeclSome : getDeclOption.isSome = true := by rfl
private def getDecl := getDeclOption.get getDeclSome
private theorem item3View : item3 = .view getDecl := by rfl
private def getScope := mkBaseScope getDecl.params
private theorem getDeclParams : getDecl.params = #[] := by rfl
private theorem getDeclResult : getDecl.result = .uint 64 := by rfl
private theorem getDeclBody :
    getDecl.body.statements.toList =
      [.return_ (some (.place (.name countName)))] := by rfl
private theorem getBaseScope : mkBaseScope #[] = getScope := by
  rw [← getDeclParams]
  rfl
private theorem getCountNotLocal : countName ∉ getScope.locals := by
  simp [countName, getScope, getDecl, getDeclOption, stateDecl,
    stateDeclOption, item0, item3, mkBaseScope, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1]
private theorem getCountNotParam : countName ∉ getScope.params := by
  simp [countName, getScope, getDecl, getDeclOption, stateDecl,
    stateDeclOption, item0, item3, mkBaseScope, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1]

private theorem items :
    StateCell.Source.subjectV1.program.items.zipIdx.toList =
      [(item0, 0), (item1, 1), (item2, 2), (item3, 3)] := by
  decide

private def tables1 : TypedDeclTablesV1 :=
  ((buildTableItemV1 emptyTables item0 0).run {}).1
private def tables2 : TypedDeclTablesV1 :=
  ((buildTableItemV1 tables1 item1 1).run {}).1
private def tables3 : TypedDeclTablesV1 :=
  ((buildTableItemV1 tables2 item2 2).run {}).1
private def tables4 : TypedDeclTablesV1 :=
  ((buildTableItemV1 tables3 item3 3).run {}).1

private theorem countInState :
    (tables4.state.find? countName).isSome = true := by rfl

private theorem countNotConst :
    (tables4.const.find? countName).isSome = false := by rfl

private theorem resolveInitial (path) :
    resolveValueName tables4 initScope path initialName = pure () := by
  simp [resolveValueName, initialInParams]

private theorem resolveCount (path) :
    resolveValueName tables4 initScope path countName = pure () := by
  simp [resolveValueName, countNotLocal, countNotParam, countInState,
    countNotConst]

private theorem resolveDelta (path) :
    resolveValueName tables4 incrementScope path deltaName = pure () := by
  simp [resolveValueName, deltaInParams]

private theorem resolveIncrementCount (path) :
    resolveValueName tables4 incrementScope path countName = pure () := by
  simp [resolveValueName, incrementCountNotLocal, incrementCountNotParam,
    countInState, countNotConst]

private theorem resolveIncrementCountAfterNoBinding (path) :
    resolveValueName tables4
      { locals := incrementScope.locals, params := incrementScope.params }
      path countName = pure () := by
  rw [incrementScopeNoAdded]
  exact resolveIncrementCount path

private theorem resolveGetCount (path) :
    resolveValueName tables4 getScope path countName = pure () := by
  simp [resolveValueName, getCountNotLocal, getCountNotParam, countInState,
    countNotConst]

private theorem table0 :
    buildTableItemV1 emptyTables item0 0 {} = (tables1, {}) := by rfl
private theorem table1 :
    buildTableItemV1 tables1 item1 1 {} = (tables2, {}) := by rfl
private theorem table2 :
    buildTableItemV1 tables2 item2 2 {} = (tables3, {}) := by rfl
private theorem table3 :
    buildTableItemV1 tables3 item3 3 {} = (tables4, {}) := by rfl

private theorem tableAll :
    Id.run ((buildTables StateCell.Source.subjectV1.program).run {}) = (tables4, {}) := by
  unfold buildTables
  rw [items]
  simp only [foldProgramItemsV1, StateT.run, Id.run, Bind.bind, StateT.bind]
  simp only [table0, table1, table2, table3, Pure.pure, StateT.pure]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem resolve0 :
    Id.run ((resolveProgramItemV1 tables4 () item0 0).run {}) = ((), {}) := by
  rw [item0State]
  simp [resolveProgramItemV1, resolveItem, stateDeclType, resolveType,
    programItemPathV1, directOrInternal, childOrInternal, UInt32.size,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, StateT.run, StateT.bind, StateT.pure, Id.run]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem resolve1 :
    Id.run ((resolveProgramItemV1 tables4 () item1 1).run {}) = ((), {}) := by
  rw [item1Init]
  simp [resolveProgramItemV1, resolveItem, resolveBlock,
    resolveBlockFuelV1, resolveStmtsFuelV1, resolveStmtFuelV1,
    resolveExprFuelV1, resolvePlaceFuelV1, resolveType, initDeclParams,
    initialParamType, initDeclBody, initBaseScopeArray, resolveInitial,
    resolveCount, UInt32.size, programItemPathV1, directOrInternal,
    childOrInternal, ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, StateT.run, StateT.bind, StateT.pure, Id.run]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem resolve2 :
    Id.run ((resolveProgramItemV1 tables4 () item2 2).run {}) = ((), {}) := by
  rw [item2Entry]
  simp [resolveProgramItemV1, resolveItem, resolveBlock,
    resolveBlockFuelV1, resolveStmtsFuelV1, resolveStmtFuelV1,
    resolveExprFuelV1, resolvePlaceFuelV1, resolveType, incrementDeclParams,
    deltaParamType, incrementDeclResult, incrementDeclBody,
    incrementBaseScopeArray, resolveDelta, resolveIncrementCount, UInt32.size,
    programItemPathV1, directOrInternal, childOrInternal,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, StateT.run, StateT.bind, StateT.pure, Id.run]
  let returnPath : ProofForgeV2.Source.WireV1.NormalizedSyntacticPathV1 := #[
    { parentTag := "Program", fieldTag := "items", index := 2 },
    { parentTag := "EntryDecl", fieldTag := "body", index := 0 },
    { parentTag := "Block", fieldTag := "statements", index := 1 },
    { parentTag := "Stmt.Return", fieldTag := "value", index := 0 },
    { parentTag := "Expr.Place", fieldTag := "place", index := 0 }]
  change
    (match
      match resolveValueName tables4
          { locals := incrementScope.locals, params := incrementScope.params }
          returnPath countName ({} : ResolutionState) with
        | (_, s) =>
          (([] : List ProofForgeV2.Source.NameComponentV1.SourceNameComponentV1), s)
    with
    | (_, s) => ((), s)) = ((), ({} : ResolutionState))
  rw [resolveIncrementCountAfterNoBinding]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem resolve3 :
    Id.run ((resolveProgramItemV1 tables4 () item3 3).run {}) = ((), {}) := by
  rw [item3View]
  simp [resolveProgramItemV1, resolveItem, resolveBlock,
    resolveBlockFuelV1, resolveStmtsFuelV1, resolveStmtFuelV1,
    resolveExprFuelV1, resolvePlaceFuelV1, resolveType, getDeclParams,
    getDeclResult, getDeclBody, getBaseScope, resolveGetCount, UInt32.size,
    programItemPathV1, directOrInternal, childOrInternal,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind, StateT.run, StateT.bind, StateT.pure, Id.run]

private theorem resolve0Raw :
    resolveProgramItemV1 tables4 () item0 0 {} = ((), {}) := by
  exact resolve0
private theorem resolve1Raw :
    resolveProgramItemV1 tables4 () item1 1 {} = ((), {}) := by
  exact resolve1
private theorem resolve2Raw :
    resolveProgramItemV1 tables4 () item2 2 {} = ((), {}) := by
  exact resolve2
private theorem resolve3Raw :
    resolveProgramItemV1 tables4 () item3 3 {} = ((), {}) := by
  exact resolve3

private theorem resolveAll :
    Id.run ((resolveProgramItemsV1 tables4
      StateCell.Source.subjectV1.program.items.zipIdx.toList).run {}) =
        ((), {}) := by
  rw [items]
  simp only [resolveProgramItemsV1, foldProgramItemsV1, StateT.run, Id.run,
    Bind.bind, StateT.bind, resolve0Raw, resolve1Raw, resolve2Raw, resolve3Raw,
    Pure.pure, StateT.pure]

private theorem tableAllRaw :
    StateT.run (buildTables StateCell.Source.subjectV1.program) {} =
      (tables4, {}) := by
  exact tableAll
private theorem resolveAllRaw :
    StateT.run (resolveProgramItemsV1 tables4
      StateCell.Source.subjectV1.program.items.zipIdx.toList) {} = ((), {}) := by
  exact resolveAll

private theorem stateCellResolutionExact
    (source : ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1)
    (programEq : source.program = StateCell.Source.subjectV1.program) :
    resolveProgramDraftsV1 source =
      { tables := tables4, drafts := #[], ok := true } := by
  unfold resolveProgramDraftsV1
  rw [programEq]
  rw [tableAllRaw]
  dsimp only
  rw [resolveAllRaw]
  rfl

/-- Exact, unconditional production name-resolution equation for any canonical
    binding of the real StateCell declaration. The production tables are
    retained rather than copied into this public statement. -/
theorem stateCellNameResolutionSuccessV1
    (binding : ProofForgeV2.Source.ValidatedSourceV1.CanonicalSourceBindingV1
      StateCell.Source.subjectV1 StateCell.bytes) :
    resolveProgramDraftsV1 binding.validated = {
      tables := (resolveProgramDraftsV1 binding.validated).tables
      drafts := #[]
      ok := true
    } := by
  rw [stateCellResolutionExact binding.validated binding.program_eq]

open ProofForgeV2.Typed.CallGraphV1

private theorem stateCellFnDuplicate : tables4.fn.hasDuplicateKey = false := by rfl
private theorem stateCellFnSize : tables4.fn.size = 0 := by rfl

private def emptyCollector : CollectorState :=
  { callerOrdinal? := none, edges := #[], pathErrors := #[] }

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem collectCallGraph0 :
    collectProgramItemEdgesV1 tables4 item0 0 emptyCollector =
      ((), emptyCollector) := by
  rw [item0State]
  simp [collectProgramItemEdgesV1, collectItemEdges, programItemPathV1,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind, StateT.pure]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem collectCallGraph1 :
    collectProgramItemEdgesV1 tables4 item1 1 emptyCollector =
      ((), emptyCollector) := by
  rw [item1Init]
  simp [collectProgramItemEdgesV1, collectItemEdges, collectBlockEdges,
    collectBlockEdgesFuelV1, collectStmtsEdgesFuelV1,
    collectStmtEdgesFuelV1, collectExprEdgesFuelV1, collectPlaceEdgesFuelV1,
    initDeclBody, childOrFail, directOrFail, programItemPathV1,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    collectorScopeFromParams, emptyCollector, Pure.pure, StateT.pure,
    Except.pure, Except.bind, Bind.bind, StateT.bind, get, modify, getThe,
    modifyGet, MonadStateOf.get, MonadStateOf.modifyGet, StateT.get,
    StateT.modifyGet]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem collectCallGraph2 :
    collectProgramItemEdgesV1 tables4 item2 2 emptyCollector =
      ((), emptyCollector) := by
  rw [item2Entry]
  simp [collectProgramItemEdgesV1, collectItemEdges, collectBlockEdges,
    collectBlockEdgesFuelV1, collectStmtsEdgesFuelV1,
    collectStmtEdgesFuelV1, collectExprEdgesFuelV1, collectPlaceEdgesFuelV1,
    incrementDeclBody, childOrFail, directOrFail, programItemPathV1,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    collectorScopeFromParams, emptyCollector, Pure.pure, StateT.pure,
    Except.pure, Except.bind, Bind.bind, StateT.bind, get, modify, getThe,
    modifyGet, MonadStateOf.get, MonadStateOf.modifyGet, StateT.get,
    StateT.modifyGet]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem collectCallGraph3 :
    collectProgramItemEdgesV1 tables4 item3 3 emptyCollector =
      ((), emptyCollector) := by
  rw [item3View]
  simp [collectProgramItemEdgesV1, collectItemEdges, collectBlockEdges,
    collectBlockEdgesFuelV1, collectStmtsEdgesFuelV1,
    collectStmtEdgesFuelV1, collectExprEdgesFuelV1, collectPlaceEdgesFuelV1,
    getDeclBody, childOrFail, directOrFail, programItemPathV1,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    collectorScopeFromParams, emptyCollector, Pure.pure, StateT.pure,
    Except.pure, Except.bind, Bind.bind, StateT.bind, get, modify, getThe,
    modifyGet, MonadStateOf.get, MonadStateOf.modifyGet, StateT.get,
    StateT.modifyGet]

private theorem stateCellCollected :
    collectFnCallEdgesV1 StateCell.Source.subjectV1.program tables4 =
      { callerOrdinal? := none, edges := #[], pathErrors := #[] } := by
  change
    ((collectProgramItemsEdgesV1 tables4
      StateCell.Source.subjectV1.program.items.zipIdx.toList).run emptyCollector).2 =
      emptyCollector
  rw [items]
  simp only [collectProgramItemsEdgesV1, StateT.run, collectCallGraph0,
    collectCallGraph1, collectCallGraph2, collectCallGraph3, Pure.pure,
    StateT.pure, Bind.bind, StateT.bind]

private theorem stateCellAdjacency : buildAdjacency 0 #[] = #[] := by
  simp [buildAdjacency]

private theorem stateCellPairEdges :
    Array.map (fun e : FnCallEdgeV1 => (e.callerOrdinal, e.calleeOrdinal)) #[] =
      #[] := by
  simp

private theorem stateCellTarjan : Tarjan.run 0 #[] = #[] := by
  simp [Tarjan.run, Pure.pure, StateT.run, StateT.pure, Bind.bind, StateT.bind]

private theorem stateCellCyclicEmpty : cyclicSccs #[] #[] = #[] := by
  simp [cyclicSccs]

/-- Exact production call-graph acceptance for the real StateCell source. The
    theorem replays the authoritative site-bearing collector and SCC analysis;
    it does not infer acceptance from the absence of declared `fn` items. -/
theorem stateCellCallGraphDraftsV1 :
    (analyzeFnCallGraphV1
      StateCell.Source.subjectV1.program tables4).cycleDrafts = #[] := by
  unfold analyzeFnCallGraphV1
  rw [stateCellFnDuplicate]
  simp only [Bool.false_eq_true, ↓reduceIte]
  rw [stateCellCollected, stateCellFnSize]
  dsimp only [CollectorState.edges, CollectorState.pathErrors]
  rw [stateCellPairEdges]
  rw [stateCellAdjacency, stateCellTarjan]
  rw [stateCellCyclicEmpty]
  simp [Array.qsort]

open ProofForgeV2.Typed.TypeCheckV1

private theorem initTypeCount :
    lookupBinding (scopeFromCallableParamsV1 tables4 initDecl.params) countName =
      some (.uint 64, .state) := by rfl
private theorem initTypeInitial :
    lookupBinding (scopeFromCallableParamsV1 tables4 initDecl.params) initialName =
      some (.uint 64, .param) := by rfl
private theorem incrementTypeCount :
    lookupBinding (scopeFromCallableParamsV1 tables4 incrementDecl.params) countName =
      some (.uint 64, .state) := by rfl
private theorem incrementTypeDelta :
    lookupBinding (scopeFromCallableParamsV1 tables4 incrementDecl.params) deltaName =
      some (.uint 64, .param) := by rfl
private theorem getTypeCount :
    lookupBinding (scopeFromCallableParamsV1 tables4 getDecl.params) countName =
      some (.uint 64, .state) := by rfl

private theorem checkExpectedUint64 (path related) :
    checkExpectedDraft (.uint 64) (some (.uint 64)) path related #[] =
      (.uint 64, #[]) := by
  simp [checkExpectedDraft]

private theorem uint64NumericFilter :
    Option.filter (fun t => isIntegerType t || isFieldType t)
      (some (.uint 64)) = some (.uint 64) := by rfl
private theorem uint64Numeric : isNumericType (.uint 64) = true := by rfl
private theorem uint64NotField : isFieldType (.uint 64) = false := by rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem incrementBinaryTypeCheck :
    typeCheckExprDraftsFuelV1
      (scopeFromCallableParamsV1 tables4 incrementDecl.params) tables4
      (some (.uint 64))
      (optRelatedPath (itemPathForNamed? tables4 .state countName))
      (some #[
        { parentTag := "Program", fieldTag := "items", index := 2 },
        { parentTag := "EntryDecl", fieldTag := "body", index := 0 },
        { parentTag := "Block", fieldTag := "statements", index := 0 },
        { parentTag := "Stmt.Assign", fieldTag := "value", index := 0 }])
      99998
      (.binary .add (.place (.name countName)) (.place (.name deltaName))) =
      resultDraft (.uint 64) #[] := by
  simp [typeCheckExprDraftsFuelV1, typeCheckPlaceDraftsFuelV1,
    incrementTypeCount, incrementTypeDelta, bindingOriginPath?, resultDraft,
    checkExpectedUint64, uint64NumericFilter, uint64Numeric, uint64NotField,
    resolveDirect, resolveChild, childPathOrDraft,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem incrementReturnTypeCheck :
    typeCheckExprDraftsFuelV1
      (scopeFromCallableParamsV1 tables4 incrementDecl.params) tables4
      (some (.uint 64))
      (optRelatedPath (callableResultPath? tables4 .entry incrementDecl.name))
      (some #[
        { parentTag := "Program", fieldTag := "items", index := 2 },
        { parentTag := "EntryDecl", fieldTag := "body", index := 0 },
        { parentTag := "Block", fieldTag := "statements", index := 1 },
        { parentTag := "Stmt.Return", fieldTag := "value", index := 0 }])
      99997 (.place (.name countName)) =
      resultDraft (.uint 64) #[]
        (itemPathForNamed? tables4 .state countName) := by
  simp [typeCheckExprDraftsFuelV1, typeCheckPlaceDraftsFuelV1,
    incrementTypeCount, bindingOriginPath?, resultDraft, checkExpectedUint64,
    resolveDirect, resolveChild, childPathOrDraft,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem typeCheck0 :
    typeCheckProgramItemDraftsV1 tables4 item0 0 = #[] := by
  rw [item0State]
  simp [typeCheckProgramItemDraftsV1, typeCheckItemDrafts, programItemPathV1,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem typeCheck1 :
    typeCheckProgramItemDraftsV1 tables4 item1 1 = #[] := by
  rw [item1Init]
  simp [typeCheckProgramItemDraftsV1, typeCheckItemDrafts,
    typeCheckBlockDrafts, typeCheckBlockDraftsFuelV1,
    typeCheckStatementsDraftsFuelV1, typeCheckStmtDraftsFuelV1,
    typeCheckAssignTargetDraftsFuelV1, typeCheckExprDraftsFuelV1,
    typeCheckPlaceDraftsFuelV1, initDeclBody, programItemPathV1,
    resolveDirect, resolveChild, childPathOrDraft,
    initTypeCount, initTypeInitial,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem typeCheck2 :
    typeCheckProgramItemDraftsV1 tables4 item2 2 = #[] := by
  rw [item2Entry]
  simp [typeCheckProgramItemDraftsV1, typeCheckItemDrafts,
    typeCheckBlockDrafts, typeCheckBlockDraftsFuelV1,
    typeCheckStatementsDraftsFuelV1, typeCheckStmtDraftsFuelV1,
    typeCheckAssignTargetDraftsFuelV1,
    typeCheckPlaceDraftsFuelV1, incrementDeclBody, programItemPathV1,
    resolveDirect, resolveChild, childPathOrDraft,
    incrementTypeCount,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  simp [resultDraft, bindingOriginPath?, incrementTypeCount,
    incrementBinaryTypeCheck, incrementReturnTypeCheck, incrementDeclResult]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem typeCheck3 :
    typeCheckProgramItemDraftsV1 tables4 item3 3 = #[] := by
  rw [item3View]
  simp [typeCheckProgramItemDraftsV1, typeCheckItemDrafts,
    typeCheckBlockDrafts, typeCheckBlockDraftsFuelV1,
    typeCheckStatementsDraftsFuelV1, typeCheckStmtDraftsFuelV1,
    typeCheckExprDraftsFuelV1, typeCheckPlaceDraftsFuelV1, getDeclBody,
    programItemPathV1,
    resolveDirect, resolveChild, childPathOrDraft,
    getTypeCount,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

/-- Exact production body type-check acceptance for the real StateCell source.
    The result is replayed through the sole production item driver. -/
theorem stateCellTypeCheckResultV1 :
    typeCheckProgramDraftsV1 StateCell.Source.subjectV1.program
      { tables := tables4, drafts := #[], ok := true } =
      { drafts := #[], ok := true } := by
  unfold typeCheckProgramDraftsV1 typeCheckProgramBodiesDraftsV1
  rw [items]
  simp [typeCheckProgramItemsDraftsV1, typeCheck0, typeCheck1, typeCheck2,
    typeCheck3]

open ProofForgeV2.Typed.EffectCheckV1

private def effectAcc0 : ProgramEvidenceAccumulatorV1 :=
  (#[], #[], #[none, none, none, none])

private theorem countNeInitial : countName ≠ initialName := by decide
private theorem countNeDelta : countName ≠ deltaName := by decide

private theorem initEffectCount :
    resolvesToState tables4 (effectScopeFromParams initDecl.params) countName =
      true := by
  simp [resolvesToState, effectScopeFromParams, countInState, countNeInitial,
    initialName, initDecl, initDeclOption, stateDecl, stateDeclOption, item0,
    item1, StateCell.Source.subjectV1, StateCell.Source.quotedProgramV1] <;>
    decide

private theorem initEffectInitial :
    resolvesToState tables4 (effectScopeFromParams initDecl.params) initialName =
      false := by
  simp [resolvesToState, effectScopeFromParams, initialName, initDecl,
    initDeclOption, item1, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1]

private theorem incrementEffectCount :
    resolvesToState tables4 (effectScopeFromParams incrementDecl.params) countName =
      true := by
  simp [resolvesToState, effectScopeFromParams, countInState, countNeDelta,
    deltaName, deltaParam, incrementDecl, incrementDeclOption, stateDecl,
    stateDeclOption, item0, item2, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1] <;> decide

private theorem incrementEffectDelta :
    resolvesToState tables4 (effectScopeFromParams incrementDecl.params) deltaName =
      false := by
  simp [resolvesToState, effectScopeFromParams, deltaName, deltaParam,
    incrementDecl, incrementDeclOption, item2, StateCell.Source.subjectV1,
    StateCell.Source.quotedProgramV1]

private theorem getEffectCount :
    resolvesToState tables4 (effectScopeFromParams getDecl.params) countName =
      true := by
  simp [resolvesToState, effectScopeFromParams, countInState,
    getDecl, getDeclOption, stateDecl, stateDeclOption, item0, item3,
    StateCell.Source.subjectV1, StateCell.Source.quotedProgramV1]

private theorem initEffectCountExpanded :
    resolvesToState tables4
      { locals := [], params := initDecl.params.map (fun p => p.name) }
      countName = true := initEffectCount

private theorem initEffectInitialExpanded :
    resolvesToState tables4
      { locals := [], params := initDecl.params.map (fun p => p.name) }
      initialName = false := initEffectInitial

private theorem incrementEffectCountExpanded :
    resolvesToState tables4
      { locals := [], params := incrementDecl.params.map (fun p => p.name) }
      countName = true := incrementEffectCount

private theorem incrementEffectDeltaExpanded :
    resolvesToState tables4
      { locals := [], params := incrementDecl.params.map (fun p => p.name) }
      deltaName = false := incrementEffectDelta

private theorem effectItem0 :
    collectProgramItemEvidenceV1 tables4 effectAcc0 item0 0 = effectAcc0 := by
  rw [item0State]
  simp [collectProgramItemEvidenceV1, effectAcc0, programItemPathV1,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem effectItem1 :
    collectProgramItemEvidenceV1 tables4 effectAcc0 item1 1 = effectAcc0 := by
  rw [item1Init]
  simp [collectProgramItemEvidenceV1, collectBodyEvidence, collectBlock,
    collectBlockFuelV1, collectStmtsFuelV1, collectStmtFuelV1,
    collectPlaceTargetFuelV1, collectExprFuelV1, collectPlaceFuelV1,
    initDeclBody, effectAcc0, programItemPathV1, effectScopeFromParams,
    initEffectCountExpanded, initEffectInitialExpanded,
    ProofForgeV2.Typed.EffectCheckV1.childOrFail,
    ProofForgeV2.Typed.EffectCheckV1.directOrFail, emitOccurrence, emitEffect,
    ProofForgeV2.Typed.EffectCheckV1.emitPathError, emptyCollectorState,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.directChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, StateT.pure, Except.pure, Except.bind, Bind.bind, StateT.bind,
    get, modify, getThe, modifyGet, MonadStateOf.get,
    MonadStateOf.modifyGet, StateT.get, StateT.modifyGet]
  unfold StateT.run StateT.bind StateT.pure StateT.modifyGet
  simp [Pure.pure, Bind.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem effectItem2 :
    collectProgramItemEvidenceV1 tables4 effectAcc0 item2 2 = effectAcc0 := by
  rw [item2Entry]
  simp [collectProgramItemEvidenceV1, collectBodyEvidence, collectBlock,
    collectBlockFuelV1, collectStmtsFuelV1, collectStmtFuelV1,
    collectPlaceTargetFuelV1, collectExprFuelV1, collectPlaceFuelV1,
    incrementDeclBody, effectAcc0, programItemPathV1, effectScopeFromParams,
    incrementEffectCountExpanded, incrementEffectDeltaExpanded,
    ProofForgeV2.Typed.EffectCheckV1.childOrFail,
    ProofForgeV2.Typed.EffectCheckV1.directOrFail, emitOccurrence, emitEffect,
    ProofForgeV2.Typed.EffectCheckV1.emitPathError, emptyCollectorState,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.directChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, StateT.pure, Except.pure, Except.bind, Bind.bind, StateT.bind,
    get, modify, getThe, modifyGet, MonadStateOf.get,
    MonadStateOf.modifyGet, StateT.get, StateT.pure, StateT.modifyGet]
  unfold StateT.run StateT.bind StateT.pure StateT.modifyGet
  simp [Pure.pure, Bind.bind]
  simp [incrementEffectCountExpanded]

private def getEffectEvidence : BodyEvidenceV1 :=
  (collectBodyEvidence tables4 getDecl.params
    (some #[
      { parentTag := "Program", fieldTag := "items", index := 3 },
      { parentTag := "ViewDecl", fieldTag := "body", index := 0 }])
    getDecl.body).2

private def effectAcc4 : ProgramEvidenceAccumulatorV1 :=
  (#[], #[], #[none, none, none, some getEffectEvidence])

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem getEffectPathErrors :
    (collectBodyEvidence tables4 getDecl.params
      (some #[
        { parentTag := "Program", fieldTag := "items", index := 3 },
        { parentTag := "ViewDecl", fieldTag := "body", index := 0 }])
      getDecl.body).fst.pathErrors = #[] := by
  simp [collectBodyEvidence, collectBlock, collectBlockFuelV1,
    collectStmtsFuelV1, collectStmtFuelV1, collectExprFuelV1,
    collectPlaceFuelV1, getDeclBody,
    ProofForgeV2.Typed.EffectCheckV1.childOrFail,
    ProofForgeV2.Typed.EffectCheckV1.directOrFail, emitOccurrence, emitEffect,
    ProofForgeV2.Typed.EffectCheckV1.emitPathError, emptyCollectorState,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.directChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, StateT.pure, Except.pure, Except.bind, Bind.bind, StateT.bind,
    get, modify, getThe, modifyGet, MonadStateOf.get,
    MonadStateOf.modifyGet, StateT.get, StateT.modifyGet]
  unfold StateT.run StateT.bind StateT.pure StateT.modifyGet
  simp [Pure.pure, Bind.bind]
  simp [getEffectCount]

private theorem effectItem3 :
    collectProgramItemEvidenceV1 tables4 effectAcc0 item3 3 = effectAcc4 := by
  rw [item3View]
  simp [collectProgramItemEvidenceV1, effectAcc0, effectAcc4,
    getEffectEvidence, getEffectPathErrors, programItemPathV1,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.directChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem stateCellEffectEvidence :
    collectProgramEvidence StateCell.Source.subjectV1.program tables4 =
      effectAcc4 := by
  unfold collectProgramEvidence
  rw [items]
  change collectProgramItemsEvidenceV1 tables4 effectAcc0
    [(item0, 0), (item1, 1), (item2, 2), (item3, 3)] = effectAcc4
  simp only [collectProgramItemsEvidenceV1]
  rw [effectItem0, effectItem1, effectItem2, effectItem3]

private theorem stateCellNoDuplicateFn : tables4.fn.hasDuplicateKey = false := by
  rfl

private theorem stateCellFnCount : tables4.fn.size = 0 := by rfl

/-- Exact production effect-check acceptance for the real StateCell source.
    The theorem retains the production occurrence evidence for the view body
    and proves that every bounded effect walk completed without path errors. -/
theorem stateCellEffectCheckResultV1 :
    checkEffectsDraftsV1 StateCell.Source.subjectV1.program tables4 =
      { drafts := #[], ok := true, analysisComplete := true } := by
  unfold checkEffectsDraftsV1
  rw [stateCellEffectEvidence, items]
  simp [stateCellNoDuplicateFn, stateCellFnCount,
    item0State, item1Init, item2Entry, item3View,
    effectAcc4, getEffectEvidence, collectBodyEvidence, collectBlock,
    collectBlockFuelV1, collectStmtsFuelV1, collectStmtFuelV1,
    collectExprFuelV1, collectPlaceFuelV1, getDeclBody, getEffectCount,
    ProofForgeV2.Typed.EffectCheckV1.childOrFail,
    ProofForgeV2.Typed.EffectCheckV1.directOrFail, emitOccurrence, emitEffect,
    ProofForgeV2.Typed.EffectCheckV1.emitPathError, emptyCollectorState,
    adjacencyFromEvidence, closeFnEffectsFixedPoint, fixedPointStep,
    checkEffectProgramItemsDraftsV1, checkEffectProgramItemDraftsV1,
    absorbCalleesEvidence, absorbCallees, bodyEffectsOf,
    EffectSetV1.toOrderedKinds, EffectKindV1.allInOrder,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.directChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, StateT.pure, Except.pure, Except.bind, Bind.bind, StateT.bind,
    get, modify, getThe, modifyGet, MonadStateOf.get,
    MonadStateOf.modifyGet, StateT.get, StateT.modifyGet]
  unfold StateT.run StateT.bind StateT.pure StateT.modifyGet
  simp [Pure.pure, Bind.bind, getEffectCount]
  simp [evidenceFromState, EffectSetV1.empty, EffectSetV1.insert,
    EffectSetV1.union, EffectSetV1.contains, viewAllowed, absorbCalleesEvidence,
    absorbCallees, bodyEffectsOf, closeFnEffectsFixedPoint, fixedPointStep,
    adjacencyFromEvidence, buildAdjacency, EffectSetV1.toOrderedKinds,
    EffectKindV1.allInOrder]
  cases itemPathForNamed? tables4 .view getDecl.name <;> rfl

open ProofForgeV2.Typed.BoundCheckV1

private theorem stateCellLoopItemsV1 :
    collectLoopProductItemsDraftResultV1
      StateCell.Source.subjectV1.program.items.zipIdx.toList =
      { drafts := #[], analysisComplete := true } := by
  rw [items]
  simp [collectLoopProductItemsDraftResultV1,
    collectLoopProductItemDraftResultV1, item0State, item1Init, item2Entry,
    item3View, checkLoopBoundsInBodyDraftResultV1, walkBlock,
    walkBlockFuelV1, walkStmtsFuelV1, walkStmtFuelV1,
    initDeclBody, incrementDeclBody, getDeclBody, programItemPathV1,
    ProofForgeV2.Typed.BoundCheckV1.childOrFail,
    ProofForgeV2.Typed.BoundCheckV1.directOrFail,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.directChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, StateT.pure, Except.pure, Except.bind, Bind.bind, StateT.bind,
    get, modify, getThe, modifyGet, MonadStateOf.get,
    MonadStateOf.modifyGet, StateT.get, StateT.modifyGet]
  unfold StateT.run StateT.bind StateT.pure
  simp [Pure.pure, Bind.bind]

private theorem stateCellLoopDraftResultV1 :
    collectLoopProductDraftResultV1 StateCell.Source.subjectV1.program =
      { drafts := #[], analysisComplete := true } := by
  unfold collectLoopProductDraftResultV1
  exact stateCellLoopItemsV1

private theorem stateCellCycleBoundDraftsV1 :
    collectCycleDrafts StateCell.Source.subjectV1.program tables4 = #[] := by
  unfold collectCycleDrafts
  rw [stateCellCollected, stateCellFnSize]
  dsimp only [ProofForgeV2.Typed.CallGraphV1.CollectorState.edges,
    ProofForgeV2.Typed.CallGraphV1.CollectorState.pathErrors]
  rw [stateCellPairEdges, stateCellAdjacency, stateCellTarjan,
    stateCellCyclicEmpty]
  simp [Array.qsort]

/-- Exact production recursion/loop-bound acceptance for the real StateCell
    source. Both cycle analysis and the bounded-total callable-body walk are
    replayed; no contract-specific checker or replacement AST is used. -/
theorem stateCellBoundCheckResultV1 :
    checkBoundsDraftsV1 StateCell.Source.subjectV1.program tables4 =
      { drafts := #[], ok := true, analysisComplete := true } := by
  unfold checkBoundsDraftsV1
  rw [stateCellNoDuplicateFn, stateCellCycleBoundDraftsV1,
    stateCellLoopDraftResultV1]
  rfl

open ProofForgeV2.Typed.DisclosureCheckV1

private theorem stateCellDisclosureCountLookup :
    tables4.state.find? countName = some (0, stateDecl) := by rfl
private theorem stateCellDisclosureCountPublic :
    stateDecl.visibility = .public_ := by rfl
private theorem stateCellDisclosureCountPath :
    itemPathForNamed? tables4 .state countName =
      some #[{ parentTag := "Program", fieldTag := "items", index := 0 }] := by
  rfl
private theorem stateCellDisclosureInitialPublic :
    initialParam.visibility = .public_ := by rfl
private theorem stateCellDisclosureDeltaPublic :
    deltaParam.visibility = .public_ := by rfl
private theorem stateCellDisclosureInitialName :
    initialParam.name = initialName := by rfl
private theorem stateCellDisclosureDeltaName :
    deltaParam.name = deltaName := by rfl
private theorem initialNeCount : initialName ≠ countName := Ne.symm countNeInitial
private theorem deltaNeCount : deltaName ≠ countName := Ne.symm countNeDelta

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellDisclosureItemsV1 :
    checkDisclosureProgramItemsDraftResultV1 tables4
      StateCell.Source.subjectV1.program.items.zipIdx.toList =
      { drafts := #[], analysisComplete := true } := by
  rw [items]
  simp [checkDisclosureProgramItemsDraftResultV1,
    checkDisclosureProgramItemDraftResultV1, checkBodyDraftResultV1,
    seedParamEvidence, scopeFromParamEvidence, checkBlockFuelV1,
    checkStmtsFuelV1, checkStmtFuelV1, exprVisibilityFuelV1,
    placeRValueVisibilityFuelV1, placeTargetVisibilityFuelV1,
    item0State, item1Init, item2Entry, item3View,
    initDeclParams, incrementDeclParams, getDeclParams,
    initDeclBody, incrementDeclBody, getDeclBody,
    stateCellDisclosureCountLookup, stateCellDisclosureCountPublic,
    stateCellDisclosureCountPath,
    stateCellDisclosureInitialPublic, stateCellDisclosureDeltaPublic,
    stateCellDisclosureInitialName, stateCellDisclosureDeltaName,
    initialNeCount, deltaNeCount,
    lookupName, lookupLocal, lookupParam,
    ProofForgeV2.Typed.DisclosureCheckV1.resolvesToState,
    ProofForgeV2.Typed.DisclosureCheckV1.placeRootName, countInState,
    programItemPathV1, ProofForgeV2.Typed.DisclosureCheckV1.childOrFail,
    ProofForgeV2.Typed.DisclosureCheckV1.directOrFail,
    ProofForgeV2.Source.NodeTraversalV1.indexChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.directChildPathV1,
    ProofForgeV2.Source.NodeTraversalV1.childPathV1, UInt32.size,
    Pure.pure, StateT.pure, Except.pure, Except.bind, Bind.bind, StateT.bind,
    get, modify, getThe, modifyGet, MonadStateOf.get,
    MonadStateOf.modifyGet, StateT.get, StateT.modifyGet]
  unfold StateT.run StateT.bind StateT.pure
  simp [Pure.pure, Bind.bind, lookupName, lookupLocal, lookupParam,
    ProofForgeV2.Typed.DisclosureCheckV1.resolvesToState,
    stateCellDisclosureCountLookup, stateCellDisclosureCountPublic,
    stateCellDisclosureCountPath, publicEvidence,
    stateCellDisclosureInitialPublic, stateCellDisclosureDeltaPublic,
    stateCellDisclosureInitialName, stateCellDisclosureDeltaName,
    initialNeCount, deltaNeCount, emitFlowUnderPc, requirePublic, emitFlow,
    effectiveSource, joinVisibility, joinVisibilityEvidence, evidenceWithCause,
    mayFlow, secrecy, StateT.pure]

/-- Exact production disclosure acceptance for the real, all-public StateCell
    source, replayed through every callable body of the bounded production pass. -/
theorem stateCellDisclosureCheckResultV1 :
    checkDisclosureDraftsV1 StateCell.Source.subjectV1.program tables4 =
      { drafts := #[], ok := true, analysisComplete := true } := by
  unfold checkDisclosureDraftsV1
  rw [stateCellNoDuplicateFn, items]
  exact congrArg
    (fun result : DisclosureWalkDraftResultV1 =>
      ({ drafts := result.drafts
         ok := result.analysisComplete && result.drafts.isEmpty
         analysisComplete := result.analysisComplete } :
        DisclosureCheckDraftResultV1))
    stateCellDisclosureItemsV1

open ProofForgeV2.Typed.AuthorityCustodyCheckV1

/-- Exact production authority/custody acceptance for StateCell. Its only
    state declaration is public, so the production gate has no private custody
    obligation to discharge. -/
theorem stateCellAuthorityCustodyCheckResultV1 :
    checkAuthorityCustodyDraftsV1 StateCell.Source.subjectV1.program tables4 =
      { drafts := #[], ok := true, analysisComplete := true } := by
  unfold checkAuthorityCustodyDraftsV1
  rw [stateCellNoDuplicateFn]
  rfl

open ProofForgeV2.Typed.ContextExtensionCheckV1

private theorem stateCellProgramItemsV1 :
    StateCell.Source.subjectV1.program.items.toList =
      [item0, item1, item2, item3] := by
  decide

private theorem stateCellExtensionDraftsV1 :
    collectExtensionProgramItemDraftsV1
      StateCell.Source.subjectV1.program.items.zipIdx.toList = #[] := by
  rw [items]
  simp [collectExtensionProgramItemDraftsV1,
    checkExtensionProgramItemDraftsV1, item0State, item1Init, item2Entry,
    item3View]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellInitContextScanV1 :
    blockBadContextFuelV1 100001 initDecl.body = some false := by
  simp [blockBadContextFuelV1, stmtListBadContextFuelV1,
    stmtBadContextFuelV1, exprBadContextFuelV1, initDeclBody]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellIncrementContextScanV1 :
    blockBadContextFuelV1 100001 incrementDecl.body = some false := by
  simp [blockBadContextFuelV1, stmtListBadContextFuelV1,
    stmtBadContextFuelV1, exprBadContextFuelV1, incrementDeclBody]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellGetContextScanV1 :
    blockBadContextFuelV1 100001 getDecl.body = some false := by
  simp [blockBadContextFuelV1, stmtListBadContextFuelV1,
    stmtBadContextFuelV1, exprBadContextFuelV1, getDeclBody]
  rfl

private theorem stateCellContextSurface0V1 :
    checkContextSurfaceProgramItemDraftResultV1 item0 =
      { drafts := #[], analysisComplete := true } := by
  rw [item0State]
  rfl

private theorem stateCellContextSurface1V1 :
    checkContextSurfaceProgramItemDraftResultV1 item1 =
      { drafts := #[], analysisComplete := true } := by
  rw [item1Init]
  simp [checkContextSurfaceProgramItemDraftResultV1, blockBadContextV1,
    stateCellInitContextScanV1]

private theorem stateCellContextSurface2V1 :
    checkContextSurfaceProgramItemDraftResultV1 item2 =
      { drafts := #[], analysisComplete := true } := by
  rw [item2Entry]
  simp [checkContextSurfaceProgramItemDraftResultV1, blockBadContextV1,
    stateCellIncrementContextScanV1]

private theorem stateCellContextSurface3V1 :
    checkContextSurfaceProgramItemDraftResultV1 item3 =
      { drafts := #[], analysisComplete := true } := by
  rw [item3View]
  simp [checkContextSurfaceProgramItemDraftResultV1, blockBadContextV1,
    stateCellGetContextScanV1]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellContextSurfaceDraftsV1 :
    collectContextSurfaceDraftResultV1
      StateCell.Source.subjectV1.program.items.toList =
      { drafts := #[], analysisComplete := true } := by
  rw [stateCellProgramItemsV1]
  simp [collectContextSurfaceDraftResultV1, stateCellContextSurface0V1,
    stateCellContextSurface1V1, stateCellContextSurface2V1,
    stateCellContextSurface3V1]

/-- Exact production context/extension acceptance for StateCell. The proof
    replays the extension item scan and every callable-body context walk; no
    extension requirement or context read is synthesized. -/
theorem stateCellContextExtensionCheckResultV1 :
    checkContextExtensionDraftsV1 StateCell.Source.subjectV1.program tables4 =
      { drafts := #[], ok := true, analysisComplete := true } := by
  unfold checkContextExtensionDraftsV1
  rw [stateCellNoDuplicateFn, stateCellExtensionDraftsV1,
    stateCellContextSurfaceDraftsV1]
  rfl

open ProofForgeV2.Typed.CheckV1

/-- Unconditional kernel certificate for the complete production Typed gate on
    any canonical binding of the real StateCell source. All seven production
    phases are composed by `checkProgramTypedDraftResultV1`; this theorem does
    not introduce an alternate checker. -/
theorem stateCellTypedCheckDraftSuccessV1
    (binding : ProofForgeV2.Source.ValidatedSourceV1.CanonicalSourceBindingV1
      StateCell.Source.subjectV1 StateCell.bytes) :
    checkProgramTypedDraftResultV1 binding.validated =
      { drafts := #[], ok := true, analysisComplete := true } := by
  unfold checkProgramTypedDraftResultV1
  rw [stateCellResolutionExact binding.validated binding.program_eq]
  rw [binding.program_eq]
  unfold checkProgramTypedDraftWithResolutionV1
  simp only [Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  rw [stateCellCallGraphDraftsV1, stateCellTypeCheckResultV1,
    stateCellEffectCheckResultV1, stateCellBoundCheckResultV1,
    stateCellDisclosureCheckResultV1,
    stateCellAuthorityCustodyCheckResultV1,
    stateCellContextExtensionCheckResultV1]
  rfl

/-- Exact erase projection of the full StateCell production Typed certificate. -/
theorem stateCellTypedCheckSuccessV1
    (binding : ProofForgeV2.Source.ValidatedSourceV1.CanonicalSourceBindingV1
      StateCell.Source.subjectV1 StateCell.bytes) :
    checkProgramTypedResultV1 binding.validated =
      { diagnostics := #[], ok := true, analysisComplete := true } := by
  unfold checkProgramTypedResultV1
  rw [stateCellTypedCheckDraftSuccessV1 binding]
  change
    TypedCheckResultV1.mk
      (ProofForgeV2.Typed.DiagnosticDraftV1.eraseArray
        (#[] : Array ProofForgeV2.Typed.DiagnosticDraftV1.TypedDiagnosticDraftV1))
      true true = _
  simp [ProofForgeV2.Typed.DiagnosticDraftV1.eraseArray]

end ProofForgeV2.Targets.Solana
