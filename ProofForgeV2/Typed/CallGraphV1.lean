/-
  ProofForgeV2.Typed.CallGraphV1 — D2-01 pure-fn call graph + acyclicity slice.

  B7b1: single site-bearing analysis `analyzeFnCallGraphV1` is the authority.
  `buildFnCallEdges` / `buildAdjacency` / `checkCallGraphV1` are projections
  (no second AST walk for cycle reporting). Cycle drafts locate primary at the
  min-ordinal fn declaration and related at remaining SCC decls + in-SCC
  LocalCall expression paths.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.CallGraphV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

/-- Scope used while walking bodies to collect `.localCall` edges. -/
structure CollectorScope where
  locals : List SourceNameComponentV1
  params : Array SourceNameComponentV1

def emptyCollectorScope : CollectorScope :=
  { locals := [], params := #[] }

def collectorScopeFromParams (params : Array ParamV1) : CollectorScope :=
  { locals := [], params := params.map (fun p => p.name) }

def resolveCalleeFn (tables : TypedDeclTablesV1) (scope : CollectorScope)
    (callee : SourceNameComponentV1) : Option Nat :=
  if scope.locals.contains callee then none
  else if scope.params.contains callee then none
  else tables.fn.find? callee |>.map (·.1)

/-- Site-bearing function-call edge (caller/callee ordinals + LocalCall path). -/
structure FnCallEdgeV1 where
  callerOrdinal : Nat
  calleeOrdinal : Nat
  callSitePath : NormalizedSyntacticPathV1
  deriving Repr, BEq

structure CollectorState where
  callerOrdinal? : Option Nat
  edges : Array FnCallEdgeV1
  pathErrors : Array TypedDiagnosticDraftV1

abbrev CollectorM := StateM CollectorState

def emitEdge (calleeOrdinal : Nat) (callSitePath : NormalizedSyntacticPathV1) :
    CollectorM Unit :=
  modify fun s =>
    match s.callerOrdinal? with
    | some callerOrdinal =>
        { s with
          edges := s.edges.push {
            callerOrdinal
            calleeOrdinal
            callSitePath
          }
        }
    | none => s

def emitPathError (detail : String) : CollectorM Unit :=
  modify fun s =>
    { s with pathErrors := s.pathErrors.push (pathInternalDraft detail) }

def childOrFail
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    CollectorM (Option NormalizedSyntacticPathV1) :=
  match childPathV1 parent parentTag fieldTag index with
  | .ok p => pure (some p)
  | .error detail => do
      emitPathError detail
      pure none

def directOrFail
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) : CollectorM (Option NormalizedSyntacticPathV1) :=
  childOrFail parent parentTag fieldTag 0

mutual
  partial def collectExprEdges (tables : TypedDeclTablesV1) (scope : CollectorScope)
      (exprPath : NormalizedSyntacticPathV1) : ExprV1 → CollectorM Unit
    | .literal _ => pure ()
    | .place p => do
        match ← directOrFail exprPath "Expr.Place" "place" with
        | none => pure ()
        | some pp => collectPlaceEdges tables scope pp p
    | .constructor _ args => do
        for (arg, i) in args.zipIdx do
          match ← childOrFail exprPath "Expr.Constructor" "args" i with
          | none => pure ()
          | some ap => collectExprEdges tables scope ap arg
    | .unary _ e => do
        match ← directOrFail exprPath "Expr.Unary" "operand" with
        | none => pure ()
        | some op => collectExprEdges tables scope op e
    | .binary _ lhs rhs => do
        match ← directOrFail exprPath "Expr.Binary" "lhs" with
        | none => pure ()
        | some lp => collectExprEdges tables scope lp lhs
        match ← directOrFail exprPath "Expr.Binary" "rhs" with
        | none => pure ()
        | some rp => collectExprEdges tables scope rp rhs
    | .localCall callee args => do
        if let some calleeOrdinal := resolveCalleeFn tables scope callee then
          emitEdge calleeOrdinal exprPath
        for (arg, i) in args.zipIdx do
          match ← childOrFail exprPath "Expr.LocalCall" "args" i with
          | none => pure ()
          | some ap => collectExprEdges tables scope ap arg
    | .externalCall call => do
        -- N-CALL-RET: external callee is a qualified name, not a local fn:
        -- no call-graph edge, only walk args.
        match ← directOrFail exprPath "Expr.ExternalCall" "call" with
        | none => pure ()
        | some cp =>
            for (arg, i) in call.args.zipIdx do
              match ← childOrFail cp "ExternalCallExpr" "args" i with
              | none => pure ()
              | some ap => collectExprEdges tables scope ap arg
    | .match_ scrutinee arms => do
        match ← directOrFail exprPath "Expr.Match" "scrutinee" with
        | none => pure ()
        | some sp => collectExprEdges tables scope sp scrutinee
        for (arm, i) in arms.zipIdx do
          match ← childOrFail exprPath "Expr.Match" "arms" i with
          | none => pure ()
          | some armPath => do
              let binders := collectPatternBinders arm.pattern
              match ← directOrFail armPath "ExprMatchArm" "value" with
              | none => pure ()
              | some vp =>
                  collectExprEdges tables { scope with locals := binders ++ scope.locals }
                    vp arm.value

  partial def collectPlaceEdges (tables : TypedDeclTablesV1) (scope : CollectorScope)
      (placePath : NormalizedSyntacticPathV1) : PlaceV1 → CollectorM Unit
    | .name _ => pure ()
    | .field base _ => do
        match ← directOrFail placePath "Place.Field" "base" with
        | none => pure ()
        | some bp => collectPlaceEdges tables scope bp base
    | .index base idx => do
        match ← directOrFail placePath "Place.Index" "base" with
        | none => pure ()
        | some bp => collectPlaceEdges tables scope bp base
        match ← directOrFail placePath "Place.Index" "index" with
        | none => pure ()
        | some ip => collectExprEdges tables scope ip idx

  partial def collectPatternBinders : PatternV1 → List SourceNameComponentV1
    | PatternV1.wildcard | PatternV1.literal _ => []
    | PatternV1.bind name => [name]
    | PatternV1.constructor _ args =>
        args.foldl (fun acc p => acc ++ collectPatternBinders p) []

  partial def collectBlockEdges (tables : TypedDeclTablesV1) (scope : CollectorScope)
      (blockPath : NormalizedSyntacticPathV1) (block : BlockV1) : CollectorM Unit :=
    collectStmtsEdges tables scope blockPath block.statements.toList 0

  partial def collectStmtsEdges (tables : TypedDeclTablesV1) (scope : CollectorScope)
      (blockPath : NormalizedSyntacticPathV1) :
      List StmtV1 → Nat → CollectorM Unit
    | [], _ => pure ()
    | stmt :: rest, idx => do
        match ← childOrFail blockPath "Block" "statements" idx with
        | none => pure ()
        | some stmtPath => do
            let added ← collectStmtEdges tables scope stmtPath stmt
            collectStmtsEdges tables { scope with locals := added ++ scope.locals }
              blockPath rest (idx + 1)

  partial def collectStmtEdges (tables : TypedDeclTablesV1) (scope : CollectorScope)
      (stmtPath : NormalizedSyntacticPathV1) :
      StmtV1 → CollectorM (List SourceNameComponentV1)
    | .let_ name _ value => do
        match ← directOrFail stmtPath "Stmt.Let" "value" with
        | none => pure ()
        | some vp => collectExprEdges tables scope vp value
        pure [name]
    | .assign target value => do
        match ← directOrFail stmtPath "Stmt.Assign" "target" with
        | none => pure ()
        | some tp => collectPlaceEdges tables scope tp target
        match ← directOrFail stmtPath "Stmt.Assign" "value" with
        | none => pure ()
        | some vp => collectExprEdges tables scope vp value
        pure []
    | .if_ condition thenBlock elseBlock? => do
        match ← directOrFail stmtPath "Stmt.If" "condition" with
        | none => pure ()
        | some cp => collectExprEdges tables scope cp condition
        match ← directOrFail stmtPath "Stmt.If" "thenBlock" with
        | none => pure ()
        | some tp => collectBlockEdges tables scope tp thenBlock
        match elseBlock? with
        | none => pure ()
        | some eb =>
            match ← directOrFail stmtPath "Stmt.If" "elseBlock" with
            | none => pure ()
            | some ep => collectBlockEdges tables scope ep eb
        pure []
    | .match_ scrutinee arms => do
        match ← directOrFail stmtPath "Stmt.Match" "scrutinee" with
        | none => pure ()
        | some sp => collectExprEdges tables scope sp scrutinee
        for (arm, i) in arms.zipIdx do
          match ← childOrFail stmtPath "Stmt.Match" "arms" i with
          | none => pure ()
          | some armPath => do
              let binders := collectPatternBinders arm.pattern
              match ← directOrFail armPath "StmtMatchArm" "body" with
              | none => pure ()
              | some bp =>
                  collectBlockEdges tables { scope with locals := binders ++ scope.locals }
                    bp arm.body
        pure []
    | .for_ binder start endExclusive _ body => do
        match ← directOrFail stmtPath "Stmt.For" "start" with
        | none => pure ()
        | some sp => collectExprEdges tables scope sp start
        match ← directOrFail stmtPath "Stmt.For" "endExclusive" with
        | none => pure ()
        | some ep => collectExprEdges tables scope ep endExclusive
        match ← directOrFail stmtPath "Stmt.For" "body" with
        | none => pure ()
        | some bp =>
            collectBlockEdges tables { scope with locals := binder :: scope.locals } bp body
        pure []
    | .assert_ condition _ => do
        match ← directOrFail stmtPath "Stmt.Assert" "condition" with
        | none => pure ()
        | some cp => collectExprEdges tables scope cp condition
        pure []
    | .revert _ args => do
        for (arg, i) in args.zipIdx do
          match ← childOrFail stmtPath "Stmt.Revert" "args" i with
          | none => pure ()
          | some ap => collectExprEdges tables scope ap arg
        pure []
    | .emit _ args => do
        for (arg, i) in args.zipIdx do
          match ← childOrFail stmtPath "Stmt.Emit" "args" i with
          | none => pure ()
          | some ap => collectExprEdges tables scope ap arg
        pure []
    | .return_ value? => do
        match value? with
        | none => pure ()
        | some value =>
            match ← directOrFail stmtPath "Stmt.Return" "value" with
            | none => pure ()
            | some vp => collectExprEdges tables scope vp value
        pure []
    | .call externalCall => do
        match ← directOrFail stmtPath "Stmt.Call" "call" with
        | none => pure ()
        | some cp =>
            for (arg, i) in externalCall.args.zipIdx do
              match ← childOrFail cp "ExternalCallExpr" "args" i with
              | none => pure ()
              | some ap => collectExprEdges tables scope ap arg
        pure []
    | .schedule externalCall => do
        match ← directOrFail stmtPath "Stmt.Schedule" "call" with
        | none => pure ()
        | some cp =>
            for (arg, i) in externalCall.args.zipIdx do
              match ← childOrFail cp "ExternalCallExpr" "args" i with
              | none => pure ()
              | some ap => collectExprEdges tables scope ap arg
        pure []
end

/-- Collect edges from one top-level item with its Program.items path. -/
def collectItemEdges (tables : TypedDeclTablesV1)
    (itemPath : NormalizedSyntacticPathV1) (item : ProgramItemV1) :
    CollectorM Unit := do
  let runWith (caller? : Option Nat) (params : Array ParamV1) (body : BlockV1)
      (bodyField parentTag : String) : CollectorM Unit := do
    let s ← get
    modify fun s' => { s' with callerOrdinal? := caller? }
    match ← directOrFail itemPath parentTag bodyField with
    | none => pure ()
    | some bp => collectBlockEdges tables (collectorScopeFromParams params) bp body
    modify fun s' => { s' with callerOrdinal? := s.callerOrdinal? }
  match item with
  | .fn decl =>
      runWith (tables.fn.find? decl.name |>.map (·.1)) decl.params decl.body "body" "FnDecl"
  | .init decl => runWith none decl.params decl.body "body" "InitDecl"
  | .entry decl => runWith none decl.params decl.body "body" "EntryDecl"
  | .view decl => runWith none decl.params decl.body "body" "ViewDecl"
  | _ => pure ()

/-- Single site-bearing edge walk. -/
def collectFnCallEdgesV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    CollectorState :=
  let st : CollectorState := { callerOrdinal? := none, edges := #[], pathErrors := #[] }
  let action : CollectorM Unit := do
    for (item, itemIndex) in program.items.zipIdx do
      match programItemPathV1 itemIndex with
      | .error detail => emitPathError detail
      | .ok itemPath => collectItemEdges tables itemPath item
  (action.run st).2

/-- Projection: ordinal pairs only (BoundCheck/EffectCheck consumers). -/
def buildFnCallEdges (program : ProgramV1) (tables : TypedDeclTablesV1) :
    Array (Nat × Nat) :=
  (collectFnCallEdgesV1 program tables).edges.map fun e =>
    (e.callerOrdinal, e.calleeOrdinal)

def dedupSortedArray {α : Type} [BEq α] (xs : Array α) : Array α :=
  xs.foldl (fun acc x =>
    match acc.back? with
    | some y => if y == x then acc else acc.push x
    | none => acc.push x) #[]

def buildAdjacency (fnCount : Nat) (edges : Array (Nat × Nat)) : Array (Array Nat) :=
  let base := List.replicate fnCount #[] |>.toArray
  let adj := edges.foldl (fun acc (caller, callee) =>
    if caller < fnCount && callee < fnCount then
      acc.set! caller (acc[caller]!.push callee)
    else
      acc) base
  adj.map (fun arr => dedupSortedArray (arr.qsort (· < ·)))

namespace Tarjan

structure State where
  indexCounter : Nat
  stack : List Nat
  onStack : Array Bool
  indices : Array (Option Nat)
  lowlinks : Array (Option Nat)
  sccs : Array (Array Nat)

def popSccUntil (v : Nat) : StateM State (Array Nat) := do
  let s : State ← get
  let (scc, rest) := s.stack.span (· != v)
  let scc := (v :: scc).toArray
  set { s with
    stack := rest.tailD [],
    onStack := scc.foldl (fun acc n => acc.set! n false) s.onStack,
    sccs := s.sccs.push scc
  }
  pure scc

partial def strongConnect (adj : Array (Array Nat)) (v : Nat) : StateM State Unit := do
  let s : State ← get
  let idx := s.indexCounter
  set { s with
    indexCounter := idx + 1,
    indices := s.indices.set! v (some idx),
    lowlinks := s.lowlinks.set! v (some idx),
    stack := v :: s.stack,
    onStack := s.onStack.set! v true
  }
  for w in adj[v]! do
    let s : State ← get
    match s.indices[w]? with
    | some none =>
        strongConnect adj w
        let s : State ← get
        let lv := s.lowlinks[v]!
        let lw := s.lowlinks[w]!
        set { s with lowlinks := s.lowlinks.set! v (some (min (lv.getD idx) (lw.getD idx))) }
    | some (some _) =>
        if s.onStack[w]! then
          let lv := s.lowlinks[v]!
          let wIdx := s.indices[w]!.getD idx
          set { s with lowlinks := s.lowlinks.set! v (some (min (lv.getD idx) wIdx)) }
    | none => pure ()
  let s : State ← get
  if s.lowlinks[v]! == s.indices[v]! then
    let _ ← popSccUntil v
    pure ()

def run (fnCount : Nat) (adj : Array (Array Nat)) : Array (Array Nat) :=
  let initState : State := {
    indexCounter := 0,
    stack := [],
    onStack := List.replicate fnCount false |>.toArray,
    indices := List.replicate fnCount none |>.toArray,
    lowlinks := List.replicate fnCount none |>.toArray,
    sccs := #[]
  }
  let action : StateM State Unit := do
    for v in [0:fnCount] do
      let s : State ← get
      if s.indices[v]!.isNone then
        strongConnect adj v
    pure ()
  let result := action.run initState
  let final : State := result.2
  final.sccs

end Tarjan

def cyclicSccs (adj : Array (Array Nat)) (sccs : Array (Array Nat)) : Array (Array Nat) :=
  sccs.filter fun scc =>
    match scc.toList with
    | [v] => adj[v]!.contains v
    | _ :: _ => true
    | [] => false

def fnNameAt (tables : TypedDeclTablesV1) (ordinal : Nat) : String :=
  match tables.fn.entries.find? (fun (_, o, _) => o == ordinal) with
  | some (name, _, _) => name.raw
  | none => s!"<fn:{ordinal}>"

def stableRecursiveCycle : String := "typed.callgraph.cycle"

/-- True iff ordinal is a member of the SCC array. -/
def sccContains (scc : Array Nat) (ordinal : Nat) : Bool :=
  scc.any (· == ordinal)

/-- Cycle draft: primary = min-ordinal fn decl; related = remaining SCC decls
    (ordinal order) + in-SCC LocalCall sites (edge source order). -/
def recursiveCycleDiagnosticDraft
    (tables : TypedDeclTablesV1)
    (scc : Array Nat)
    (edges : Array FnCallEdgeV1) : TypedDiagnosticDraftV1 :=
  let sorted := scc.qsort (· < ·)
  let members := sorted.map (fnNameAt tables)
  let memberText := String.intercalate ", " members.toList
  let base := make .sourceInvalid s!"recursive call cycle: {memberText}"
    (expected := some (.string "acyclic pure-fn call graph"))
    (actual := some (.string memberText))
    (context := some (.object #[
      ("members", .array (members.map PfJson.string))
    ]))
    (stableContext := some stableRecursiveCycle)
  match sorted[0]? with
  | none => base
  | some primaryOrd =>
      match itemPathForOrdinal? tables .fn primaryOrd with
      | none => base
      | some primaryPath =>
          let remainingDecls : Array NormalizedSyntacticPathV1 :=
            (sorted.extract 1 sorted.size).filterMap fun o =>
              itemPathForOrdinal? tables .fn o
          let callSites : Array NormalizedSyntacticPathV1 :=
            edges.filterMap fun e =>
              if sccContains scc e.callerOrdinal && sccContains scc e.calleeOrdinal then
                some e.callSitePath
              else none
          withPaths base primaryPath (remainingDecls ++ callSites)

def recursiveCycleDiagnostic (tables : TypedDeclTablesV1) (scc : Array Nat) :
    DiagnosticV1 :=
  let members := (scc.qsort (· < ·)).map (fnNameAt tables)
  let memberText := String.intercalate ", " members.toList
  erase (make .sourceInvalid s!"recursive call cycle: {memberText}"
    (stableContext := some stableRecursiveCycle)
    (expected := some (.string "acyclic pure-fn call graph"))
    (actual := some (.string memberText)))

structure CallGraphResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  deriving Repr, Inhabited

/-- Full site-bearing analysis result. -/
structure FnCallGraphAnalysisV1 where
  edges : Array FnCallEdgeV1
  cycleDrafts : Array TypedDiagnosticDraftV1
  ok : Bool
  deriving Repr

/-- Authority: single site-bearing walk + SCC cycle drafts. -/
def analyzeFnCallGraphV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    FnCallGraphAnalysisV1 :=
  if tables.fn.hasDuplicateKey then
    { edges := #[], cycleDrafts := #[], ok := true }
  else
    let collected := collectFnCallEdgesV1 program tables
    let edges := collected.edges
    let fnCount := tables.fn.size
    let pairEdges := edges.map fun e => (e.callerOrdinal, e.calleeOrdinal)
    let adj := buildAdjacency fnCount pairEdges
    let sccs := Tarjan.run fnCount adj
    let cycles := cyclicSccs adj sccs
    let sortedCycles := cycles.qsort (fun a b =>
      let minA := a.foldl (init := fnCount) (fun acc n => min acc n)
      let minB := b.foldl (init := fnCount) (fun acc n => min acc n)
      minA < minB)
    let cycleDrafts :=
      collected.pathErrors ++
      sortedCycles.map (fun scc => recursiveCycleDiagnosticDraft tables scc edges)
    { edges := edges
      cycleDrafts := cycleDrafts
      ok := cycleDrafts.isEmpty }

/-- Public unlocated projection of analyzeFnCallGraphV1. -/
def checkCallGraphV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    CallGraphResultV1 :=
  let analysis := analyzeFnCallGraphV1 program tables
  { diagnostics := eraseArray analysis.cycleDrafts
    ok := analysis.ok }

/-- Tables → resolution → acyclicity; unlocated diagnostics in phase order. -/
def checkProgramStructureV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  let resolution := resolveProgramV1 source
  let cg := checkCallGraphV1 source.program resolution.tables
  resolution.diagnostics ++ cg.diagnostics

end ProofForgeV2.Typed.CallGraphV1
