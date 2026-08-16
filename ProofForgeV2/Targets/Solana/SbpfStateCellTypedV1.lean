import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.NameResolutionV1

/-!
# StateCell production Typed certificate

Kernel replay of the sole production name-resolution pass over the exact
`program StateCell` source captured by the elaborator. The proof decomposes the
real source in declaration order and reuses the production table builder,
resolver, canonical path helpers, and bounded recursive walkers. It defines no
alternate checker and supplies no AST to production code.
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

end ProofForgeV2.Targets.Solana
