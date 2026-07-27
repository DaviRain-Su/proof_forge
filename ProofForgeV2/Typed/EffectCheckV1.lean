/-
  ProofForgeV2.Typed.EffectCheckV1 — D2-02 effect/call/view checker slice.

  Collects currently expressible AST effects from callable bodies, propagates
  pure-fn effects over the local-call graph by a finite monotonic fixed-point
  on 6-bit effect sets (works for cyclic graphs; yields a complete upper bound),
  and enforces allowlists:

    * `fn`   — only `failure.revert`
    * `view` — `state.read` and `failure.revert`
    * `entry`/`init` — all currently expressible effects (no PF-EFFECT-001)

  Duplicate `fn` keys make call-graph edges ambiguous (`find?` keeps the first
  ordinal only).  In that case analysis is incomplete: `analysisComplete =
  false`, `ok = false`, and `checkProgramEffectsV1` surfaces name-resolution
  structural diagnostics so the independent entry cannot report success.

  Product consumption: composed into `CheckV1` and fail-closed gated from
  `Typed.checkV1`.  Out of scope here: context.read.*, disclosure.*, extension.*,
  resource/termination bounds, and deleting the alpha Typed view/write rules.

  Scope and local-call resolution reuse ModelV1 / NameResolutionV1 /
  CallGraphV1 shadowing rules (locals and params shadow state and fn names).
  Diagnostics are `PF-EFFECT-001` (`DiagnosticCodeV1.effectDisallowed`),
  emitted in program source/declaration order with a stable effect-kind order
  per callable.
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
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.EffectCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

/-- Currently expressible effects collected from ProgramV1 AST.  Context,
    disclosure, and extension effects are intentionally absent. -/
inductive EffectKindV1 where
  | stateRead
  | stateWrite
  | eventEmit
  | externalCallSync
  | workflowSchedule
  | failureRevert
  deriving BEq, DecidableEq, Repr, Inhabited

namespace EffectKindV1

/-- Stable total order used for deterministic diagnostic emission. -/
def rank : EffectKindV1 → Nat
  | .stateRead => 0
  | .stateWrite => 1
  | .eventEmit => 2
  | .externalCallSync => 3
  | .workflowSchedule => 4
  | .failureRevert => 5

/-- Spec wire name used in `PF-EFFECT-001` messages. -/
def wire : EffectKindV1 → String
  | .stateRead => "state.read"
  | .stateWrite => "state.write"
  | .eventEmit => "event.emit"
  | .externalCallSync => "external.call.sync"
  | .workflowSchedule => "workflow.schedule"
  | .failureRevert => "failure.revert"

/-- All kinds in stable rank order. -/
def allInOrder : Array EffectKindV1 :=
  #[.stateRead, .stateWrite, .eventEmit, .externalCallSync, .workflowSchedule, .failureRevert]

/-- Number of distinct effect bits; bounds fixed-point iteration. -/
def bitCount : Nat := 6

end EffectKindV1

/-- Bit-set style effect accumulator (6 bits). -/
structure EffectSetV1 where
  stateRead : Bool := false
  stateWrite : Bool := false
  eventEmit : Bool := false
  externalCallSync : Bool := false
  workflowSchedule : Bool := false
  failureRevert : Bool := false
  deriving BEq, Repr, Inhabited

namespace EffectSetV1

def empty : EffectSetV1 := {}

def insert (s : EffectSetV1) : EffectKindV1 → EffectSetV1
  | .stateRead => { s with stateRead := true }
  | .stateWrite => { s with stateWrite := true }
  | .eventEmit => { s with eventEmit := true }
  | .externalCallSync => { s with externalCallSync := true }
  | .workflowSchedule => { s with workflowSchedule := true }
  | .failureRevert => { s with failureRevert := true }

def union (a b : EffectSetV1) : EffectSetV1 :=
  { stateRead := a.stateRead || b.stateRead
    stateWrite := a.stateWrite || b.stateWrite
    eventEmit := a.eventEmit || b.eventEmit
    externalCallSync := a.externalCallSync || b.externalCallSync
    workflowSchedule := a.workflowSchedule || b.workflowSchedule
    failureRevert := a.failureRevert || b.failureRevert }

def contains (s : EffectSetV1) : EffectKindV1 → Bool
  | .stateRead => s.stateRead
  | .stateWrite => s.stateWrite
  | .eventEmit => s.eventEmit
  | .externalCallSync => s.externalCallSync
  | .workflowSchedule => s.workflowSchedule
  | .failureRevert => s.failureRevert

/-- Effects present in stable rank order. -/
def toOrderedKinds (s : EffectSetV1) : Array EffectKindV1 :=
  EffectKindV1.allInOrder.filter (fun k => s.contains k)

end EffectSetV1

/-- Direct effects plus resolved local-call callee ordinals from one body. -/
structure BodyEffectsV1 where
  effects : EffectSetV1
  callees : Array Nat
  deriving Repr, Inhabited

def emptyBodyEffects : BodyEffectsV1 :=
  { effects := EffectSetV1.empty, callees := #[] }

/-- Scope used while walking bodies.  Mirrors CallGraphV1 / NameResolutionV1:
    locals shadow params, and both shadow top-level state and function names. -/
structure EffectScope where
  locals : List SourceNameComponentV1
  params : Array SourceNameComponentV1

def emptyEffectScope : EffectScope :=
  { locals := [], params := #[] }

def effectScopeFromParams (params : Array ParamV1) : EffectScope :=
  { locals := [], params := params.map (fun p => p.name) }

/-- Resolve a bare name to a state cell through the current scope. -/
def resolvesToState (tables : TypedDeclTablesV1) (scope : EffectScope)
    (name : SourceNameComponentV1) : Bool :=
  if scope.locals.contains name then false
  else if scope.params.contains name then false
  else tables.state.find? name |>.isSome

/-- If `name` resolves to a `fn` declaration through the current scope, return
    its source-order ordinal; otherwise `none`. -/
def resolveCalleeFn (tables : TypedDeclTablesV1) (scope : EffectScope)
    (callee : SourceNameComponentV1) : Option Nat :=
  if scope.locals.contains callee then none
  else if scope.params.contains callee then none
  else tables.fn.find? callee |>.map (·.1)

def placeRootName : PlaceV1 → SourceNameComponentV1
  | .name n => n
  | .field base _ => placeRootName base
  | .index base _ => placeRootName base

/-- Mutable collector for one body walk. -/
structure CollectorState where
  effects : EffectSetV1
  callees : Array Nat

abbrev CollectorM := StateM CollectorState

def emitEffect (kind : EffectKindV1) : CollectorM Unit :=
  modify fun s => { s with effects := s.effects.insert kind }

def emitCallee (ordinal : Nat) : CollectorM Unit :=
  modify fun s =>
    if s.callees.contains ordinal then s
    else { s with callees := s.callees.push ordinal }

mutual
  partial def collectExpr (tables : TypedDeclTablesV1) (scope : EffectScope) :
      ExprV1 → CollectorM Unit
    | .literal _ => pure ()
    | .place p => collectPlace tables scope p
    | .constructor _ args => args.forM (collectExpr tables scope)
    | .unary _ e => collectExpr tables scope e
    | .binary _ lhs rhs => do
        collectExpr tables scope lhs
        collectExpr tables scope rhs
    | .localCall callee args => do
        if let some ordinal := resolveCalleeFn tables scope callee then
          emitCallee ordinal
        args.forM (collectExpr tables scope)
    | .match_ scrutinee arms => do
        collectExpr tables scope scrutinee
        for arm in arms do
          let binders := collectPatternBinders arm.pattern
          collectExpr tables { scope with locals := binders ++ scope.locals } arm.value

  partial def collectPlace (tables : TypedDeclTablesV1) (scope : EffectScope) :
      PlaceV1 → CollectorM Unit
    | .name n => do
        if resolvesToState tables scope n then
          emitEffect .stateRead
    | .field base _ => collectPlace tables scope base
    | .index base idx => do
        collectPlace tables scope base
        collectExpr tables scope idx

  partial def collectPatternBinders : PatternV1 → List SourceNameComponentV1
    | PatternV1.wildcard | PatternV1.literal _ => []
    | PatternV1.bind name => [name]
    | PatternV1.constructor _ args =>
        args.foldl (fun acc p => acc ++ collectPatternBinders p) []

  partial def collectBlock (tables : TypedDeclTablesV1) (scope : EffectScope)
      (block : BlockV1) : CollectorM Unit :=
    collectStmts tables scope block.statements.toList

  partial def collectStmts (tables : TypedDeclTablesV1) (scope : EffectScope) :
      List StmtV1 → CollectorM Unit
    | [] => pure ()
    | stmt :: rest => do
        let added ← collectStmt tables scope stmt
        collectStmts tables { scope with locals := added ++ scope.locals } rest

  partial def collectStmt (tables : TypedDeclTablesV1) (scope : EffectScope) :
      StmtV1 → CollectorM (List SourceNameComponentV1)
    | .let_ name _ value => do
        collectExpr tables scope value
        pure [name]
    | .assign target value => do
        -- Index expressions on the target may themselves read state / call fns.
        collectPlaceTarget tables scope target
        collectExpr tables scope value
        pure []
    | .if_ condition thenBlock elseBlock? => do
        collectExpr tables scope condition
        collectBlock tables scope thenBlock
        elseBlock?.forM (collectBlock tables scope)
        pure []
    | .match_ scrutinee arms => do
        collectExpr tables scope scrutinee
        for arm in arms do
          let binders := collectPatternBinders arm.pattern
          collectBlock tables { scope with locals := binders ++ scope.locals } arm.body
        pure []
    | .for_ binder start endExclusive _ body => do
        collectExpr tables scope start
        collectExpr tables scope endExclusive
        collectBlock tables { scope with locals := binder :: scope.locals } body
        pure []
    | .assert_ condition _ => do
        collectExpr tables scope condition
        emitEffect .failureRevert
        pure []
    | .revert _ args => do
        args.forM (collectExpr tables scope)
        emitEffect .failureRevert
        pure []
    | .emit _ args => do
        args.forM (collectExpr tables scope)
        emitEffect .eventEmit
        pure []
    | .return_ value? => do
        value?.forM (collectExpr tables scope)
        pure []
    | .call externalCall => do
        externalCall.args.forM (collectExpr tables scope)
        emitEffect .externalCallSync
        pure []
    | .schedule externalCall => do
        externalCall.args.forM (collectExpr tables scope)
        emitEffect .workflowSchedule
        pure []

  /-- Walk an assignment target: root state is a write; field/index chains on
      state are still writes; index sub-expressions are ordinary reads/calls. -/
  partial def collectPlaceTarget (tables : TypedDeclTablesV1) (scope : EffectScope) :
      PlaceV1 → CollectorM Unit
    | .name n => do
        if resolvesToState tables scope n then
          emitEffect .stateWrite
    | .field base _ => collectPlaceTarget tables scope base
    | .index base idx => do
        collectPlaceTarget tables scope base
        collectExpr tables scope idx
end

def collectBodyEffects (tables : TypedDeclTablesV1) (params : Array ParamV1)
    (body : BlockV1) : BodyEffectsV1 :=
  let init : CollectorState := { effects := EffectSetV1.empty, callees := #[] }
  let (_, st) := (collectBlock tables (effectScopeFromParams params) body).run init
  { effects := st.effects, callees := st.callees }

/-- Allowlist for pure `fn`: only deterministic failure. -/
def fnAllowed : EffectKindV1 → Bool
  | .failureRevert => true
  | _ => false

/-- Allowlist for `view`: state reads and deterministic failure. -/
def viewAllowed : EffectKindV1 → Bool
  | .stateRead | .failureRevert => true
  | _ => false

def emptyOrigins : Array SourceOrigin := #[]

def effectDisallowedDiagnostic (kindLabel name : String) (effect : EffectKindV1) :
    DiagnosticV1 :=
  { code := .effectDisallowed
    message := s!"{kindLabel} '{name}' does not allow effect '{effect.wire}'"
    origins := emptyOrigins }

/-- One fixed-point step: `next[v] = direct[v] ∪ ⋃_{w ∈ adj[v]} current[w]`. -/
def fixedPointStep (fnCount : Nat) (adj : Array (Array Nat))
    (direct current : Array EffectSetV1) : Array EffectSetV1 :=
  (List.range fnCount).toArray.map fun v =>
    let fromCallees :=
      if v < adj.size then
        adj[v]!.foldl (fun acc w =>
          if w < current.size then EffectSetV1.union acc current[w]! else acc)
          EffectSetV1.empty
      else
        EffectSetV1.empty
    let base := if v < direct.size then direct[v]! else EffectSetV1.empty
    EffectSetV1.union base fromCallees

/-- Monotonic fixed-point propagation of effect sets over an arbitrary call
    graph (including cycles).  Each node is a 6-bit set; each step can only
    add bits, so the loop terminates after at most `fnCount * bitCount`
    changing iterations. -/
def closeFnEffectsFixedPoint (fnCount : Nat) (adj : Array (Array Nat))
    (direct : Array EffectSetV1) : Array EffectSetV1 :=
  let fuel := fnCount * EffectKindV1.bitCount + 1
  let rec go (fuel : Nat) (current : Array EffectSetV1) : Array EffectSetV1 :=
    match fuel with
    | 0 => current
    | fuel' + 1 =>
        let next := fixedPointStep fnCount adj direct current
        if next == current then current else go fuel' next
  go fuel direct

/-- Union callee closed effects into a body's direct set. -/
def absorbCallees (fnClosed : Array EffectSetV1) (body : BodyEffectsV1) : EffectSetV1 :=
  body.callees.foldl
    (fun acc o =>
      if o < fnClosed.size then EffectSetV1.union acc fnClosed[o]!
      else acc)
    body.effects

/-- Result of the effect checker.

    `analysisComplete` is false when declaration tables are too ambiguous to
    attribute local-call edges (currently: duplicate `fn` keys).  In that case
    `ok` is also false and allowlist diagnostics are not produced; callers must
    surface structural diagnostics from name resolution instead. -/
structure EffectCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Incomplete analysis result used for ambiguous declaration tables. -/
def incompleteEffectResult : EffectCheckResultV1 :=
  { diagnostics := #[], ok := false, analysisComplete := false }

/-- Check ProgramV1 effects against fn/view allowlists using declaration tables.

    When `tables.fn` has duplicate keys, returns `analysisComplete = false` and
    does not emit allowlist diagnostics (edges would mis-attribute callees).
    Otherwise always runs fixed-point closure, including over cycles. -/
def checkEffectsV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    EffectCheckResultV1 :=
  if tables.fn.hasDuplicateKey then
    incompleteEffectResult
  else
    let fnCount := tables.fn.size
    let directFn : Array EffectSetV1 :=
      (List.range fnCount).toArray.map fun o =>
        match tables.fn.entries.find? (fun (_, ord, _) => ord == o) with
        | some (_, _, decl) =>
            (collectBodyEffects tables decl.params decl.body).effects
        | none => EffectSetV1.empty
    let adj := buildAdjacency fnCount (buildFnCallEdges program tables)
    let fnClosed := closeFnEffectsFixedPoint fnCount adj directFn
    let diagnostics := program.items.foldl (init := #[]) fun acc item =>
      match item with
      | .fn decl =>
          -- Unique names: `find?` ordinal matches the closed vector entry.
          let total :=
            match tables.fn.find? decl.name with
            | some (o, _) =>
                if o < fnClosed.size then fnClosed[o]! else EffectSetV1.empty
            | none =>
                let body := collectBodyEffects tables decl.params decl.body
                absorbCallees fnClosed body
          let disallowed := total.toOrderedKinds.filter (fun k => !fnAllowed k)
          acc ++ disallowed.map (fun k => effectDisallowedDiagnostic "fn" decl.name.raw k)
      | .view decl =>
          let body := collectBodyEffects tables decl.params decl.body
          let total := absorbCallees fnClosed body
          let disallowed := total.toOrderedKinds.filter (fun k => !viewAllowed k)
          acc ++ disallowed.map (fun k => effectDisallowedDiagnostic "view" decl.name.raw k)
      | .entry _ | .init _ =>
          -- Currently expressible effects are allowed for entry/init.
          acc
      | _ => acc
    { diagnostics := diagnostics
      ok := diagnostics.isEmpty
      analysisComplete := true }

/-- Entry point over a validated source unit.

    Builds declaration tables via name resolution.  When effect analysis is
    incomplete (duplicate `fn` keys), returns resolution structural diagnostics
    so the independent entry fails closed and cannot present as success.
    When analysis is complete, returns effect allowlist diagnostics only. -/
def checkProgramEffectsV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  let resolution := resolveProgramV1 source
  let effectRes := checkEffectsV1 source.program resolution.tables
  if effectRes.analysisComplete then
    effectRes.diagnostics
  else
    resolution.diagnostics ++ effectRes.diagnostics

/-- Full result entry including `analysisComplete`, for tests and future
    product wiring that need the structured outcome. -/
def checkProgramEffectsResultV1 (source : ValidatedSourceV1) : EffectCheckResultV1 :=
  let resolution := resolveProgramV1 source
  let effectRes := checkEffectsV1 source.program resolution.tables
  if effectRes.analysisComplete then
    effectRes
  else
    { diagnostics := resolution.diagnostics ++ effectRes.diagnostics
      ok := false
      analysisComplete := false }

end ProofForgeV2.Typed.EffectCheckV1
