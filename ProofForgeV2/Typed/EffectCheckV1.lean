/-
  ProofForgeV2.Typed.EffectCheckV1 — D2-02 effect/call/view checker slice.

  Collects currently expressible AST effects from callable bodies, propagates
  pure-fn effects over the local-call graph by a finite monotonic fixed-point
  on 6-bit effect sets (works for cyclic graphs; yields a complete upper bound),
  and enforces allowlists:

    * `fn`   — only `failure.revert`
    * `view` — `state.read` and `failure.revert`
    * `entry`/`init` — all currently expressible effects (no PF-EFFECT-001)

  B7b3a: sole path-threaded draft authority. Public `checkEffectsV1` /
  `checkProgramEffectsV1` / `checkProgramEffectsResultV1` are exact erase
  projections of the same draft execution. Disallowed-effect drafts use the
  offending FnDecl/ViewDecl item as primary; related paths are the finite
  causal evidence set (direct occurrence sites + effect-propagating LocalCall
  edges, visit-bounded worklist over pure-fn callees).

  Duplicate `fn` keys make call-graph edges ambiguous (`find?` keeps the first
  ordinal only).  In that case analysis is incomplete: `analysisComplete =
  false`, `ok = false`, and `checkProgramEffectsV1` surfaces name-resolution
  structural diagnostics so the independent entry cannot report success.

  Product consumption: composed into `CheckV1`, whose located result is the
  Normalize product gate. The legacy alpha compatibility checker also consumes
  the unlocated projection. Out of scope here: context.read.*, disclosure.*, extension.*,
  resource/termination bounds, Bound/Disclosure/CheckV1 locate wiring.

  Scope and local-call resolution reuse ModelV1 / NameResolutionV1 /
  CallGraphV1 shadowing rules (locals and params shadow state and fn names).
  Diagnostics are `PF-EFFECT-001` (`DiagnosticCodeV1.effectDisallowed`),
  emitted in program source/declaration order with a stable effect-kind order
  per callable.
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
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.EffectCheckV1

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
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.DiagnosticDraftV1
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

/-- Direct occurrence of an effect at a canonical ProgramV1 path. -/
structure EffectOccurrenceV1 where
  kind : EffectKindV1
  path : NormalizedSyntacticPathV1
  deriving Repr, BEq

/-- Resolved LocalCall evidence (distinct occurrences retained). -/
structure CallSiteEvidenceV1 where
  calleeOrdinal : Nat
  callSitePath : NormalizedSyntacticPathV1
  deriving Repr, BEq

/-- Direct effects plus site-bearing call/occurrence evidence from one body. -/
structure BodyEvidenceV1 where
  effects : EffectSetV1
  callees : Array Nat
  occurrences : Array EffectOccurrenceV1
  callSites : Array CallSiteEvidenceV1
  deriving Repr, Inhabited

def emptyBodyEvidence : BodyEvidenceV1 :=
  { effects := EffectSetV1.empty
    callees := #[]
    occurrences := #[]
    callSites := #[] }

/-- Projection: effects + deduped callees only (legacy BodyEffects shape). -/
structure BodyEffectsV1 where
  effects : EffectSetV1
  callees : Array Nat
  deriving Repr, Inhabited

def emptyBodyEffects : BodyEffectsV1 :=
  { effects := EffectSetV1.empty, callees := #[] }

def bodyEffectsOf (ev : BodyEvidenceV1) : BodyEffectsV1 :=
  { effects := ev.effects, callees := ev.callees }

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

/-- Mutable collector for one path-threaded body walk. -/
structure CollectorState where
  effects : EffectSetV1
  callees : Array Nat
  occurrences : Array EffectOccurrenceV1
  callSites : Array CallSiteEvidenceV1
  pathErrors : Array TypedDiagnosticDraftV1

abbrev CollectorM := StateM CollectorState

def emitEffect (kind : EffectKindV1) : CollectorM Unit :=
  modify fun s => { s with effects := s.effects.insert kind }

def emitOccurrence (kind : EffectKindV1) (path : NormalizedSyntacticPathV1) :
    CollectorM Unit :=
  modify fun s =>
    { s with
      effects := s.effects.insert kind
      occurrences := s.occurrences.push { kind, path } }

def emitCallee (ordinal : Nat) : CollectorM Unit :=
  modify fun s =>
    if s.callees.contains ordinal then s
    else { s with callees := s.callees.push ordinal }

def emitCallSite (ordinal : Nat) (callSitePath : NormalizedSyntacticPathV1) :
    CollectorM Unit :=
  modify fun s =>
    let s :=
      if s.callees.contains ordinal then s
      else { s with callees := s.callees.push ordinal }
    { s with callSites := s.callSites.push { calleeOrdinal := ordinal, callSitePath } }

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
  partial def collectExpr (tables : TypedDeclTablesV1) (scope : EffectScope)
      (exprPath? : Option NormalizedSyntacticPathV1) : ExprV1 → CollectorM Unit
    | .literal _ => pure ()
    | .place p => do
        let pp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Place" "place"
        collectPlace tables scope pp? p
    | .constructor _ args => do
        for (arg, i) in args.zipIdx do
          let ap? ← match exprPath? with
            | none => pure none
            | some ep => childOrFail ep "Expr.Constructor" "args" i
          collectExpr tables scope ap? arg
    | .unary _ e => do
        let op? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Unary" "operand"
        collectExpr tables scope op? e
    | .binary _ lhs rhs => do
        let lp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Binary" "lhs"
        collectExpr tables scope lp? lhs
        let rp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Binary" "rhs"
        collectExpr tables scope rp? rhs
    | .localCall callee args => do
        if let some ordinal := resolveCalleeFn tables scope callee then
          match exprPath? with
          | some ep => emitCallSite ordinal ep
          | none => emitCallee ordinal
        for (arg, i) in args.zipIdx do
          let ap? ← match exprPath? with
            | none => pure none
            | some ep => childOrFail ep "Expr.LocalCall" "args" i
          collectExpr tables scope ap? arg
    | .match_ scrutinee arms => do
        let sp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Match" "scrutinee"
        collectExpr tables scope sp? scrutinee
        for (arm, i) in arms.zipIdx do
          let binders := collectPatternBinders arm.pattern
          let vp? ← match exprPath? with
            | none => pure none
            | some ep => do
                match ← childOrFail ep "Expr.Match" "arms" i with
                | none => pure none
                | some armPath => directOrFail armPath "ExprMatchArm" "value"
          collectExpr tables { scope with locals := binders ++ scope.locals } vp? arm.value

  partial def collectPlace (tables : TypedDeclTablesV1) (scope : EffectScope)
      (placePath? : Option NormalizedSyntacticPathV1) : PlaceV1 → CollectorM Unit
    | .name n => do
        if resolvesToState tables scope n then
          match placePath? with
          | some pp => emitOccurrence .stateRead pp
          | none => emitEffect .stateRead
    | .field base _ => do
        let bp? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Field" "base"
        collectPlace tables scope bp? base
    | .index base idx => do
        let bp? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "base"
        collectPlace tables scope bp? base
        let ip? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "index"
        collectExpr tables scope ip? idx

  partial def collectPatternBinders : PatternV1 → List SourceNameComponentV1
    | PatternV1.wildcard | PatternV1.literal _ => []
    | PatternV1.bind name => [name]
    | PatternV1.constructor _ args =>
        args.foldl (fun acc p => acc ++ collectPatternBinders p) []

  partial def collectBlock (tables : TypedDeclTablesV1) (scope : EffectScope)
      (blockPath? : Option NormalizedSyntacticPathV1) (block : BlockV1) :
      CollectorM Unit :=
    collectStmts tables scope blockPath? block.statements.toList 0

  partial def collectStmts (tables : TypedDeclTablesV1) (scope : EffectScope)
      (blockPath? : Option NormalizedSyntacticPathV1) :
      List StmtV1 → Nat → CollectorM Unit
    | [], _ => pure ()
    | stmt :: rest, idx => do
        let stmtPath? ← match blockPath? with
          | none => pure none
          | some bp => childOrFail bp "Block" "statements" idx
        let added ← collectStmt tables scope stmtPath? stmt
        collectStmts tables { scope with locals := added ++ scope.locals }
          blockPath? rest (idx + 1)

  partial def collectStmt (tables : TypedDeclTablesV1) (scope : EffectScope)
      (stmtPath? : Option NormalizedSyntacticPathV1) :
      StmtV1 → CollectorM (List SourceNameComponentV1)
    | .let_ name _ value => do
        let vp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Let" "value"
        collectExpr tables scope vp? value
        pure [name]
    | .assign target value => do
        let tp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Assign" "target"
        collectPlaceTarget tables scope tp? target
        let vp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Assign" "value"
        collectExpr tables scope vp? value
        pure []
    | .if_ condition thenBlock elseBlock? => do
        let cp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.If" "condition"
        collectExpr tables scope cp? condition
        let tp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.If" "thenBlock"
        collectBlock tables scope tp? thenBlock
        match elseBlock? with
        | none => pure ()
        | some eb => do
            let ep? ← match stmtPath? with
              | none => pure none
              | some sp => directOrFail sp "Stmt.If" "elseBlock"
            collectBlock tables scope ep? eb
        pure []
    | .match_ scrutinee arms => do
        let sp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Match" "scrutinee"
        collectExpr tables scope sp? scrutinee
        for (arm, i) in arms.zipIdx do
          let binders := collectPatternBinders arm.pattern
          let bp? ← match stmtPath? with
            | none => pure none
            | some sp => do
                match ← childOrFail sp "Stmt.Match" "arms" i with
                | none => pure none
                | some armPath => directOrFail armPath "StmtMatchArm" "body"
          collectBlock tables { scope with locals := binders ++ scope.locals } bp? arm.body
        pure []
    | .for_ binder start endExclusive _ body => do
        let sp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.For" "start"
        collectExpr tables scope sp? start
        let ep? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.For" "endExclusive"
        collectExpr tables scope ep? endExclusive
        let bp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.For" "body"
        collectBlock tables { scope with locals := binder :: scope.locals } bp? body
        pure []
    | .assert_ condition _ => do
        let cp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Assert" "condition"
        collectExpr tables scope cp? condition
        match stmtPath? with
        | some sp => emitOccurrence .failureRevert sp
        | none => emitEffect .failureRevert
        pure []
    | .revert _ args => do
        for (arg, i) in args.zipIdx do
          let ap? ← match stmtPath? with
            | none => pure none
            | some sp => childOrFail sp "Stmt.Revert" "args" i
          collectExpr tables scope ap? arg
        match stmtPath? with
        | some sp => emitOccurrence .failureRevert sp
        | none => emitEffect .failureRevert
        pure []
    | .emit _ args => do
        for (arg, i) in args.zipIdx do
          let ap? ← match stmtPath? with
            | none => pure none
            | some sp => childOrFail sp "Stmt.Emit" "args" i
          collectExpr tables scope ap? arg
        match stmtPath? with
        | some sp => emitOccurrence .eventEmit sp
        | none => emitEffect .eventEmit
        pure []
    | .return_ value? => do
        match value? with
        | none => pure ()
        | some value => do
            let vp? ← match stmtPath? with
              | none => pure none
              | some sp => directOrFail sp "Stmt.Return" "value"
            collectExpr tables scope vp? value
        pure []
    | .call externalCall => do
        match stmtPath? with
        | none =>
            externalCall.args.forM (collectExpr tables scope none)
            emitEffect .externalCallSync
        | some sp => do
            match ← directOrFail sp "Stmt.Call" "call" with
            | none =>
                externalCall.args.forM (collectExpr tables scope none)
            | some cp =>
                for (arg, i) in externalCall.args.zipIdx do
                  match ← childOrFail cp "ExternalCallExpr" "args" i with
                  | none => collectExpr tables scope none arg
                  | some ap => collectExpr tables scope (some ap) arg
            emitOccurrence .externalCallSync sp
        pure []
    | .schedule externalCall => do
        match stmtPath? with
        | none =>
            externalCall.args.forM (collectExpr tables scope none)
            emitEffect .workflowSchedule
        | some sp => do
            match ← directOrFail sp "Stmt.Schedule" "call" with
            | none =>
                externalCall.args.forM (collectExpr tables scope none)
            | some cp =>
                for (arg, i) in externalCall.args.zipIdx do
                  match ← childOrFail cp "ExternalCallExpr" "args" i with
                  | none => collectExpr tables scope none arg
                  | some ap => collectExpr tables scope (some ap) arg
            emitOccurrence .workflowSchedule sp
        pure []

  /-- Walk an assignment target: root state is a write; field/index chains on
      state are still writes; index sub-expressions are ordinary reads/calls. -/
  partial def collectPlaceTarget (tables : TypedDeclTablesV1) (scope : EffectScope)
      (placePath? : Option NormalizedSyntacticPathV1) : PlaceV1 → CollectorM Unit
    | .name n => do
        if resolvesToState tables scope n then
          match placePath? with
          | some pp => emitOccurrence .stateWrite pp
          | none => emitEffect .stateWrite
    | .field base _ => do
        let bp? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Field" "base"
        collectPlaceTarget tables scope bp? base
    | .index base idx => do
        let bp? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "base"
        collectPlaceTarget tables scope bp? base
        let ip? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "index"
        collectExpr tables scope ip? idx
end

def emptyCollectorState : CollectorState :=
  { effects := EffectSetV1.empty
    callees := #[]
    occurrences := #[]
    callSites := #[]
    pathErrors := #[] }

def evidenceFromState (st : CollectorState) : BodyEvidenceV1 :=
  { effects := st.effects
    callees := st.callees
    occurrences := st.occurrences
    callSites := st.callSites }

/-- Path-threaded body collection (sole effect AST walk). -/
def collectBodyEvidence (tables : TypedDeclTablesV1) (params : Array ParamV1)
    (bodyPath? : Option NormalizedSyntacticPathV1) (body : BlockV1) :
    CollectorState × BodyEvidenceV1 :=
  let init := emptyCollectorState
  let (_, st) :=
    (collectBlock tables (effectScopeFromParams params) bodyPath? body).run init
  (st, evidenceFromState st)

/-- Unlocated body effects projection (no path threading). -/
def collectBodyEffects (tables : TypedDeclTablesV1) (params : Array ParamV1)
    (body : BlockV1) : BodyEffectsV1 :=
  let (_, ev) := collectBodyEvidence tables params none body
  bodyEffectsOf ev

/-- Allowlist for pure `fn`: only deterministic failure. -/
def fnAllowed : EffectKindV1 → Bool
  | .failureRevert => true
  | _ => false

/-- Allowlist for `view`: state reads and deterministic failure. -/
def viewAllowed : EffectKindV1 → Bool
  | .stateRead | .failureRevert => true
  | _ => false

def effectDisallowedMessage (kindLabel name : String) (effect : EffectKindV1) : String :=
  s!"{kindLabel} '{name}' does not allow effect '{effect.wire}'"

def effectDisallowedDiagnostic (kindLabel name : String) (effect : EffectKindV1) :
    DiagnosticV1 :=
  DiagnosticV1.make .effectDisallowed (effectDisallowedMessage kindLabel name effect)

def effectDisallowedDraft
    (kindLabel name : String) (effect : EffectKindV1)
    (primaryPath : NormalizedSyntacticPathV1)
    (relatedPaths : Array NormalizedSyntacticPathV1) : TypedDiagnosticDraftV1 :=
  makeLocated .effectDisallowed (effectDisallowedMessage kindLabel name effect)
    primaryPath relatedPaths

/-- First-seen stable unique push for related path sets. -/
def pushUniquePath (acc : Array NormalizedSyntacticPathV1)
    (p : NormalizedSyntacticPathV1) : Array NormalizedSyntacticPathV1 :=
  if acc.any (· == p) then acc else acc.push p

/-- Absorb direct occurrence sites of `kind` and effect-propagating LocalCall
    edges from one body into `related`/`work`. Does not mark callees visited. -/
def absorbEvidenceSites
    (fnClosed : Array EffectSetV1)
    (kind : EffectKindV1)
    (ev : BodyEvidenceV1)
    (related : Array NormalizedSyntacticPathV1)
    (work : Array Nat)
    (visited : Array Bool) :
    Array NormalizedSyntacticPathV1 × Array Nat :=
  let related :=
    ev.occurrences.foldl (fun acc occ =>
      if occ.kind == kind then pushUniquePath acc occ.path else acc) related
  let (related, work) :=
    ev.callSites.foldl (init := (related, work)) fun (rel, w) cs =>
      if cs.calleeOrdinal < fnClosed.size
          && fnClosed[cs.calleeOrdinal]!.contains kind then
        let rel := pushUniquePath rel cs.callSitePath
        -- Enqueue only unvisited callees (first-seen); duplicates still add path.
        if cs.calleeOrdinal < visited.size && !visited[cs.calleeOrdinal]!
            && !w.contains cs.calleeOrdinal then
          (rel, w.push cs.calleeOrdinal)
        else
          (rel, w)
      else
        (rel, w)
  (related, work)

/-- Finite causal related-path set for one (callable, effect): visit-bounded
    worklist over pure-fn callees whose closed set contains `kind`. Direct
    occurrence sites and effect-propagating LocalCall sites only. -/
def relatedPathsForEffect
    (fnCount : Nat)
    (fnEvidence : Array BodyEvidenceV1)
    (fnClosed : Array EffectSetV1)
    (seed : BodyEvidenceV1)
    (seedFnOrdinal? : Option Nat)
    (kind : EffectKindV1) : Array NormalizedSyntacticPathV1 :=
  -- Mark seed fn ordinal visited so cycle re-entry cannot reprocess it.
  let visited0 : Array Bool :=
    match seedFnOrdinal? with
    | some o =>
        let v := List.replicate fnCount false |>.toArray
        if o < v.size then v.set! o true else v
    | none => List.replicate fnCount false |>.toArray
  let (related1, work1) :=
    absorbEvidenceSites fnClosed kind seed #[] #[] visited0
  let fuel := fnCount + 1
  let rec go (fuel : Nat) (related : Array NormalizedSyntacticPathV1)
      (work : Array Nat) (visited : Array Bool) (idx : Nat) :
      Array NormalizedSyntacticPathV1 :=
    if idx >= work.size then related
    else
      match fuel with
      | 0 => related
      | fuel' + 1 =>
          let o := work[idx]!
          if o < visited.size && visited[o]! then
            go fuel' related work visited (idx + 1)
          else
            let visited := if o < visited.size then visited.set! o true else visited
            let ev := if o < fnEvidence.size then fnEvidence[o]! else emptyBodyEvidence
            let (related', work') :=
              absorbEvidenceSites fnClosed kind ev related work visited
            go fuel' related' work' visited (idx + 1)
  go fuel related1 work1 visited0 0

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

def absorbCalleesEvidence (fnClosed : Array EffectSetV1) (body : BodyEvidenceV1) :
    EffectSetV1 :=
  absorbCallees fnClosed (bodyEffectsOf body)

/-- Result of the effect checker (unlocated public projection). -/
structure EffectCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Draft-bearing authority result (B7b3a). -/
structure EffectCheckDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Incomplete analysis result used for ambiguous declaration tables. -/
def incompleteEffectResult : EffectCheckResultV1 :=
  { diagnostics := #[], ok := false, analysisComplete := false }

def incompleteEffectDraftResult : EffectCheckDraftResultV1 :=
  { drafts := #[], ok := false, analysisComplete := false }

/-- Collect path-threaded evidence for every fn ordinal + all items (for views).
    Returns (fnEvidence by ordinal, pathErrors, item evidence keyed by item index). -/
def collectProgramEvidence (program : ProgramV1) (tables : TypedDeclTablesV1) :
    Array BodyEvidenceV1 × Array TypedDiagnosticDraftV1 ×
      Array (Option BodyEvidenceV1) :=
  let fnCount := tables.fn.size
  let initFn : Array BodyEvidenceV1 :=
    List.replicate fnCount emptyBodyEvidence |>.toArray
  let initItems : Array (Option BodyEvidenceV1) :=
    List.replicate program.items.size none |>.toArray
  program.items.zipIdx.foldl (init := (initFn, (#[] : Array TypedDiagnosticDraftV1), initItems))
    fun (fnEvidence, pathErrors, itemEvidence) (item, itemIndex) =>
      match programItemPathV1 itemIndex with
      | .error detail =>
          (fnEvidence, pathErrors.push (pathInternalDraft detail), itemEvidence)
      | .ok itemPath =>
          match item with
          | .fn decl =>
              let bodyPath? :=
                match directChildPathV1 itemPath "FnDecl" "body" with
                | .ok bp => some bp
                | .error _ => none
              let pathErrors :=
                match directChildPathV1 itemPath "FnDecl" "body" with
                | .error detail => pathErrors.push (pathInternalDraft detail)
                | .ok _ => pathErrors
              let (st, ev) := collectBodyEvidence tables decl.params bodyPath? decl.body
              let pathErrors := pathErrors ++ st.pathErrors
              let fnEvidence :=
                match tables.fn.find? decl.name with
                | some (o, _) =>
                    if o < fnEvidence.size then fnEvidence.set! o ev else fnEvidence
                | none => fnEvidence
              let itemEvidence := itemEvidence.set! itemIndex (some ev)
              (fnEvidence, pathErrors, itemEvidence)
          | .view decl =>
              let bodyPath? :=
                match directChildPathV1 itemPath "ViewDecl" "body" with
                | .ok bp => some bp
                | .error _ => none
              let pathErrors :=
                match directChildPathV1 itemPath "ViewDecl" "body" with
                | .error detail => pathErrors.push (pathInternalDraft detail)
                | .ok _ => pathErrors
              let (st, ev) := collectBodyEvidence tables decl.params bodyPath? decl.body
              let pathErrors := pathErrors ++ st.pathErrors
              let itemEvidence := itemEvidence.set! itemIndex (some ev)
              (fnEvidence, pathErrors, itemEvidence)
          | .entry decl =>
              let bodyPath? :=
                match directChildPathV1 itemPath "EntryDecl" "body" with
                | .ok bp => some bp
                | .error _ => none
              let pathErrors :=
                match directChildPathV1 itemPath "EntryDecl" "body" with
                | .error detail => pathErrors.push (pathInternalDraft detail)
                | .ok _ => pathErrors
              let (st, _) := collectBodyEvidence tables decl.params bodyPath? decl.body
              (fnEvidence, pathErrors ++ st.pathErrors, itemEvidence)
          | .init decl =>
              let bodyPath? :=
                match directChildPathV1 itemPath "InitDecl" "body" with
                | .ok bp => some bp
                | .error _ => none
              let pathErrors :=
                match directChildPathV1 itemPath "InitDecl" "body" with
                | .error detail => pathErrors.push (pathInternalDraft detail)
                | .ok _ => pathErrors
              let (st, _) := collectBodyEvidence tables decl.params bodyPath? decl.body
              (fnEvidence, pathErrors ++ st.pathErrors, itemEvidence)
          | _ => (fnEvidence, pathErrors, itemEvidence)

/-- Build fn-only adjacency from collected call-site evidence. -/
def adjacencyFromEvidence (fnCount : Nat) (fnEvidence : Array BodyEvidenceV1) :
    Array (Array Nat) :=
  let pairEdges : Array (Nat × Nat) :=
    (List.range fnCount).toArray.foldl (init := #[]) fun acc caller =>
      if caller < fnEvidence.size then
        fnEvidence[caller]!.callSites.foldl (fun acc2 cs =>
          acc2.push (caller, cs.calleeOrdinal)) acc
      else
        acc
  buildAdjacency fnCount pairEdges

/-- Draft authority: path-threaded effect allowlist check. -/
def checkEffectsDraftsV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    EffectCheckDraftResultV1 :=
  if tables.fn.hasDuplicateKey then
    incompleteEffectDraftResult
  else
    let fnCount := tables.fn.size
    let (fnEvidence, pathErrors, itemEvidence) := collectProgramEvidence program tables
    let directFn : Array EffectSetV1 := fnEvidence.map (·.effects)
    let adj := adjacencyFromEvidence fnCount fnEvidence
    let fnClosed := closeFnEffectsFixedPoint fnCount adj directFn
    let drafts :=
      program.items.zipIdx.foldl (init := pathErrors) fun acc (item, itemIndex) =>
        match item with
        | .fn decl =>
            let o? := tables.fn.find? decl.name |>.map (·.1)
            let total :=
              match o? with
              | some o =>
                  if o < fnClosed.size then fnClosed[o]! else EffectSetV1.empty
              | none =>
                  let ev := itemEvidence[itemIndex]!.getD emptyBodyEvidence
                  absorbCalleesEvidence fnClosed ev
            let disallowed := total.toOrderedKinds.filter (fun k => !fnAllowed k)
            let seed :=
              match o? with
              | some o =>
                  if o < fnEvidence.size then fnEvidence[o]! else emptyBodyEvidence
              | none => itemEvidence[itemIndex]!.getD emptyBodyEvidence
            let primary? :=
              match o? with
              | some o => itemPathForOrdinal? tables .fn o
              | none => itemPathForNamed? tables .fn decl.name
            match primary? with
            | none =>
                acc ++ disallowed.map fun k =>
                  make .effectDisallowed (effectDisallowedMessage "fn" decl.name.raw k)
            | some primaryPath =>
                disallowed.foldl (init := acc) fun acc k =>
                  let related := relatedPathsForEffect fnCount fnEvidence fnClosed
                    seed o? k
                  acc.push (effectDisallowedDraft "fn" decl.name.raw k primaryPath related)
        | .view decl =>
            let seed := itemEvidence[itemIndex]!.getD emptyBodyEvidence
            let total := absorbCalleesEvidence fnClosed seed
            let disallowed := total.toOrderedKinds.filter (fun k => !viewAllowed k)
            let primary? := itemPathForNamed? tables .view decl.name
            match primary? with
            | none =>
                acc ++ disallowed.map fun k =>
                  make .effectDisallowed (effectDisallowedMessage "view" decl.name.raw k)
            | some primaryPath =>
                disallowed.foldl (init := acc) fun acc k =>
                  let related := relatedPathsForEffect fnCount fnEvidence fnClosed
                    seed none k
                  acc.push
                    (effectDisallowedDraft "view" decl.name.raw k primaryPath related)
        | _ => acc
    { drafts := drafts
      ok := drafts.isEmpty
      analysisComplete := true }

/-- Public unlocated projection of `checkEffectsDraftsV1`. -/
def checkEffectsV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    EffectCheckResultV1 :=
  let r := checkEffectsDraftsV1 program tables
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

/-- Draft-bearing entry over a validated source unit. -/
def checkProgramEffectsDraftsV1 (source : ValidatedSourceV1) : EffectCheckDraftResultV1 :=
  let resolution := resolveProgramDraftsV1 source
  let effectRes := checkEffectsDraftsV1 source.program resolution.tables
  if effectRes.analysisComplete then
    effectRes
  else
    { drafts := resolution.drafts ++ effectRes.drafts
      ok := false
      analysisComplete := false }

/-- Entry point over a validated source unit.

    Builds declaration tables via name resolution.  When effect analysis is
    incomplete (duplicate `fn` keys), returns resolution structural diagnostics
    so the independent entry fails closed and cannot present as success.
    When analysis is complete, returns effect allowlist diagnostics only. -/
def checkProgramEffectsV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  eraseArray (checkProgramEffectsDraftsV1 source).drafts

/-- Full result entry including `analysisComplete`, for tests and future
    product wiring that need the structured outcome. -/
def checkProgramEffectsResultV1 (source : ValidatedSourceV1) : EffectCheckResultV1 :=
  let r := checkProgramEffectsDraftsV1 source
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

end ProofForgeV2.Typed.EffectCheckV1
