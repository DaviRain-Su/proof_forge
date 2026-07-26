/-
  ProofForgeV2.Typed.CallGraphV1 — D2-01 pure-fn call graph + acyclicity slice.

  Collects `.localCall` edges from every callable body (`fn`/`entry`/`view`/`init`)
  using the same scope-shadowing rule as `NameResolutionV1`:
    * locals and parameters shadow top-level function names, producing no edge;
    * only callees that resolve to a `fn` declaration create an edge;
    * calls that resolve to other declaration kinds or are unknown produce no edge
      (they are reported by name resolution instead).

  Builds a deterministic directed graph over function ordinals (caller → callees),
  computes strongly-connected components, and rejects every cycle.  Self-recursion
  is reported as a 1-cycle.  `entry`/`view`/`init` may call `fn` but are never
  themselves call targets, so they cannot appear on a cycle.

  `checkProgramStructureV1` runs declaration tables, full-program name resolution, and
  call-graph acyclicity in one pass and concatenates diagnostics in phase order
  (tables → resolution → acyclicity).  Later phases still run even when earlier
  phases fail so that all structural errors are reported together.

  Deliberately outside this slice: termination bounds, effects, and requirements.
  Cycles are reported as `PF-SRC-INVALID` structural diagnostics.
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.CallGraphV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

/-- Scope used while walking bodies to collect `.localCall` edges.  Mirrors
    `NameResolutionV1.Scope`: locals shadow params, and both shadow top-level
    declarations. -/
structure CollectorScope where
  locals : List SourceNameComponentV1
  params : Array SourceNameComponentV1

/-- Empty collection scope. -/
def emptyCollectorScope : CollectorScope :=
  { locals := [], params := #[] }

def collectorScopeFromParams (params : Array ParamV1) : CollectorScope :=
  { locals := [], params := params.map (fun p => p.name) }

/-- If `name` resolves to a `fn` declaration through the current scope, return its
    source-order ordinal; otherwise `none`.  Locals and parameters shadow
    top-level names, matching `NameResolutionV1.resolveLocalCall`. -/
def resolveCalleeFn (tables : TypedDeclTablesV1) (scope : CollectorScope)
    (callee : SourceNameComponentV1) : Option Nat :=
  if scope.locals.contains callee then none
  else if scope.params.contains callee then none
  else tables.fn.find? callee |>.map (·.1)

/-- Mutable accumulator for edges and the current caller.
    `callerOrdinal?` is `some o` only while walking a `fn` body; it is `none`
    inside `init`/`entry`/`view` bodies so that edges are never attributed to
    non-callable callers. -/
structure CollectorState where
  callerOrdinal? : Option Nat
  edges : Array (Nat × Nat)

abbrev CollectorM := StateM CollectorState

def emitEdge (calleeOrdinal : Nat) : CollectorM Unit :=
  modify fun s =>
    match s.callerOrdinal? with
    | some callerOrdinal =>
        { s with edges := s.edges.push (callerOrdinal, calleeOrdinal) }
    | none => s

mutual
  /-- Collect `.localCall` edges reachable from an expression. -/
  partial def collectExprEdges (tables : TypedDeclTablesV1) (scope : CollectorScope) :
      ExprV1 → CollectorM Unit
    | .literal _ => pure ()
    | .place p => collectPlaceEdges tables scope p
    | .constructor _ args => args.forM (collectExprEdges tables scope)
    | .unary _ e => collectExprEdges tables scope e
    | .binary _ lhs rhs => do
        collectExprEdges tables scope lhs
        collectExprEdges tables scope rhs
    | .localCall callee args => do
        if let some calleeOrdinal := resolveCalleeFn tables scope callee then
          emitEdge calleeOrdinal
        args.forM (collectExprEdges tables scope)
    | .match_ scrutinee arms => do
        collectExprEdges tables scope scrutinee
        for arm in arms do
          let binders := collectPatternBinders arm.pattern
          collectExprEdges tables { scope with locals := binders ++ scope.locals } arm.value

  /-- Collect edges from a place expression (index expressions may contain calls). -/
  partial def collectPlaceEdges (tables : TypedDeclTablesV1) (scope : CollectorScope) :
      PlaceV1 → CollectorM Unit
    | .name _ => pure ()
    | .field base _ => collectPlaceEdges tables scope base
    | .index base idx => do
        collectPlaceEdges tables scope base
        collectExprEdges tables scope idx

  /-- Return the list of binder names introduced by a pattern. -/
  partial def collectPatternBinders : PatternV1 → List SourceNameComponentV1
    | PatternV1.wildcard | PatternV1.literal _ => []
    | PatternV1.bind name => [name]
    | PatternV1.constructor _ args =>
        args.foldl (fun acc p => acc ++ collectPatternBinders p) []

  /-- Collect edges from a block, threading locals through in source order. -/
  partial def collectBlockEdges (tables : TypedDeclTablesV1) (scope : CollectorScope)
      (block : BlockV1) : CollectorM Unit :=
    collectStmtsEdges tables scope block.statements.toList

  partial def collectStmtsEdges (tables : TypedDeclTablesV1) (scope : CollectorScope) :
      List StmtV1 → CollectorM Unit
    | [] => pure ()
    | stmt :: rest => do
        let added ← collectStmtEdges tables scope stmt
        collectStmtsEdges tables { scope with locals := added ++ scope.locals } rest

  /-- Collect edges from a single statement and return any new local binders. -/
  partial def collectStmtEdges (tables : TypedDeclTablesV1) (scope : CollectorScope) :
      StmtV1 → CollectorM (List SourceNameComponentV1)
    | .let_ name _ value => do
        collectExprEdges tables scope value
        pure [name]
    | .assign target value => do
        collectPlaceEdges tables scope target
        collectExprEdges tables scope value
        pure []
    | .if_ condition thenBlock elseBlock? => do
        collectExprEdges tables scope condition
        collectBlockEdges tables scope thenBlock
        elseBlock?.forM (collectBlockEdges tables scope)
        pure []
    | .match_ scrutinee arms => do
        collectExprEdges tables scope scrutinee
        for arm in arms do
          let binders := collectPatternBinders arm.pattern
          collectBlockEdges tables { scope with locals := binders ++ scope.locals } arm.body
        pure []
    | .for_ binder start endExclusive _ body => do
        collectExprEdges tables scope start
        collectExprEdges tables scope endExclusive
        collectBlockEdges tables { scope with locals := binder :: scope.locals } body
        pure []
    | .assert_ condition _ => do
        collectExprEdges tables scope condition
        pure []
    | .revert _ args => do
        args.forM (collectExprEdges tables scope)
        pure []
    | .emit _ args => do
        args.forM (collectExprEdges tables scope)
        pure []
    | .return_ value? => do
        value?.forM (collectExprEdges tables scope)
        pure []
    | .call externalCall | .schedule externalCall => do
        externalCall.args.forM (collectExprEdges tables scope)
        pure []
end

/-- Collect all function-call edges from a top-level callable body.  Only `fn`
    declarations are call targets, but we walk `init`/`entry`/`view` bodies too
    because they may contain `.localCall` sub-expressions. -/
def collectItemEdges (tables : TypedDeclTablesV1) (item : ProgramItemV1) :
    CollectorM Unit := do
  let runWith (caller? : Option Nat) (params : Array ParamV1) (body : BlockV1) : CollectorM Unit := do
    let s ← get
    modify fun s' => { s' with callerOrdinal? := caller? }
    collectBlockEdges tables (collectorScopeFromParams params) body
    modify fun s' => { s' with callerOrdinal? := s.callerOrdinal? }
  match item with
  | .fn decl => runWith (tables.fn.find? decl.name |>.map (·.1)) decl.params decl.body
  | .init decl => runWith none decl.params decl.body
  | .entry decl => runWith none decl.params decl.body
  | .view decl => runWith none decl.params decl.body
  | _ => pure ()

/-- Build the caller→callee edge list for a whole program.  The caller ordinal
    is the source-order ordinal of the calling `fn`; `entry`/`view`/`init` never
    contribute outgoing edges as call targets, only as additional call sites. -/
def buildFnCallEdges (program : ProgramV1) (tables : TypedDeclTablesV1) :
    Array (Nat × Nat) :=
  let st := { callerOrdinal? := none, edges := #[] }
  let (_, st') := (program.items.forM (collectItemEdges tables)).run st
  st'.edges

/-- Remove adjacent duplicates from a sorted array. -/
def dedupSortedArray {α : Type} [BEq α] (xs : Array α) : Array α :=
  xs.foldl (fun acc x =>
    match acc.back? with
    | some y => if y == x then acc else acc.push x
    | none => acc.push x) #[]

/-- Adjacency list representation: for each caller ordinal, the sorted,
    deduplicated list of callee ordinals it calls. -/
def buildAdjacency (fnCount : Nat) (edges : Array (Nat × Nat)) : Array (Array Nat) :=
  let base := List.replicate fnCount #[] |>.toArray
  let adj := edges.foldl (fun acc (caller, callee) =>
    if caller < fnCount && callee < fnCount then
      acc.set! caller (acc[caller]!.push callee)
    else
      acc) base
  adj.map (fun arr => dedupSortedArray (arr.qsort (· < ·)))

namespace Tarjan

/-- Mutable state for Tarjan's strongly-connected-components algorithm. -/
structure State where
  indexCounter : Nat
  stack : List Nat
  onStack : Array Bool
  indices : Array (Option Nat)
  lowlinks : Array (Option Nat)
  sccs : Array (Array Nat)

/-- Pop vertices from the stack until `v` is removed, forming one SCC. -/
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

/-- One step of Tarjan's algorithm starting from vertex `v`. -/
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

/-- Run Tarjan on all function vertices and return SCCs. -/
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

/-- All functions participating in a cycle.  A 1-element SCC is a cycle only
    when the function calls itself; larger SCCs are always cycles. -/
def cyclicSccs (adj : Array (Array Nat)) (sccs : Array (Array Nat)) : Array (Array Nat) :=
  sccs.filter fun scc =>
    match scc.toList with
    | [v] => adj[v]!.contains v
    | _ :: _ => true
    | [] => false

/-- Build the canonical function name for an ordinal. -/
def fnNameAt (tables : TypedDeclTablesV1) (ordinal : Nat) : String :=
  match tables.fn.entries.find? (fun (_, o, _) => o == ordinal) with
  | some (name, _, _) => name.raw
  | none => s!"<fn:{ordinal}>"

/-- Diagnostic emitted for a recursive cycle.  Members are named in ascending
    source-order ordinal (declaration order) so reporting is deterministic. -/
def recursiveCycleDiagnostic (tables : TypedDeclTablesV1) (scc : Array Nat) :
    DiagnosticV1 :=
  let members := (scc.qsort (· < ·)).map (fnNameAt tables)
  let memberText := String.intercalate ", " members.toList
  { code := .sourceInvalid,
    message := s!"recursive call cycle: {memberText}",
    origins := emptyOrigins }

/-- Result of call-graph acyclicity checking. -/
structure CallGraphResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  deriving Repr, Inhabited

/-- Check a validated ProgramV1 for recursive call cycles.

    Only `.localCall` occurrences that resolve to a `fn` declaration through
    the current scope create edges.  Cycles are reported as `PF-SRC-INVALID`
    diagnostics sorted by the earliest member's declaration ordinal. -/
def checkCallGraphV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    CallGraphResultV1 :=
  -- When duplicate function names exist, the table maps a single name to
  -- multiple ordinals.  Resolution already reports the duplicate; running the
  -- cycle check on that malformed table would mis-attribute edges.  Skip it.
  if tables.fn.hasDuplicateKey then
    { diagnostics := #[], ok := true }
  else
    let fnCount := tables.fn.size
    let edges := buildFnCallEdges program tables
    let adj := buildAdjacency fnCount edges
    let sccs := Tarjan.run fnCount adj
    let cycles := cyclicSccs adj sccs
    let sortedCycles := cycles.qsort (fun a b =>
      let minA := a.foldl (init := fnCount) (fun acc n => min acc n)
      let minB := b.foldl (init := fnCount) (fun acc n => min acc n)
      minA < minB)
    let diagnostics := sortedCycles.map (recursiveCycleDiagnostic tables)
    { diagnostics := diagnostics, ok := diagnostics.isEmpty }

/-- Run table construction, name resolution, and call-graph acyclicity in one
    pass.  Diagnostics are returned in phase order (tables → resolution →
    acyclicity).  Later phases always run so that every structural error is
    reported together. -/
def checkProgramStructureV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  let resolution := resolveProgramV1 source
  let cg := checkCallGraphV1 source.program resolution.tables
  resolution.diagnostics ++ cg.diagnostics

end ProofForgeV2.Typed.CallGraphV1
