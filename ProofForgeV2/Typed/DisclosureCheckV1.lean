/-
  ProofForgeV2.Typed.DisclosureCheckV1 — D2-04b explicit + PC-label / implicit disclosure.

  Independent Typed pass over ProgramV1 that checks information-flow of
  `VisibilityV1` labels (public | commitment | private), including control
  dependence (program-counter label), and emits stable
  `DiagnosticCodeV1.visibilityViolation` (`PF-VIS-001`).

  Lattice (secrecy order; join = max secrecy):
    public_ < commitment < private_
  mayFlow(src, sink) iff secrecy(src) ≤ secrecy(sink).

  Infer expression visibility bottom-up; enforce sinks with PC join:
    At every explicit sink, effective source = joinVisibility(valueVis, currentPc)
    before mayFlow / emitFlow.
    assign value → target place visibility
    return / emit / revert / external call / schedule args → public_
    place indices and for-loop endpoints → public_
    localCall args → corresponding fn ParamV1.visibility (resolved via tables.fn
      with NameResolution/TypeCheck shadowing; arity mismatch → walk args only)
    const defining expression → public_

  Program-counter (PC) label:
    * Entry PC for each body / const check is public_.
    * if_: evaluate condition under current PC; branch bodies run under
      pc' = joinVisibilityEvidence(pc, withControlRootEvidence(condVis, condPath)).
      Condition is not itself a public *value* sink, but raises PC for the
      branches (PC causes = decl causes of condition + condition Expr root).
    * match_ (statement): evaluate scrutinee; arm bodies under
      pc' = joinVisibilityEvidence(pc, withControlRootEvidence(scrutVis, scrutPath)).
      Pattern binders still inherit raw scrutVis for *value* flow (unchanged).
    * match_ (expression): result visibility =
      joinVisibilityEvidence(withControlRootEvidence(scrutVis, scrutPath),
        join of arm value visibilities) so the scrutinee control-taints the
      expression result (incl. scrutinee Expr root); arm expressions are walked
      under pc' for nested sinks.
    * Nested if/match compose by joining PC (monotonic max secrecy). Leaving a
      branch restores the outer PC (pc is a parameter, not a global).
    * assert_: condition is a public sink (EffectCheck maps assert → failure.revert,
      an observable public effect). Nested expr sinks under the condition use
      current PC; assert does **not** raise PC for subsequent statements
      (assert is not a branch).
    * for_: endpoints remain public sinks under current PC; loop body runs under
      current PC (no extra PC raise from endpoints beyond their public sink
      check). Binder remains public_.

  Local `let` records RHS visibility (value flow only; PC is applied at sinks).
  Successful localCall result is public_ (fn returns are public sinks).
  Params and state carry declared visibility; const names resolve as public_
  after the defining-expression check; locals/params shadow state
  (NameResolutionV1 / EffectCheckV1 scope rules).

  B7b3c: sole path-threaded draft authority. Public `checkDisclosureV1` /
  `checkProgramDisclosureV1` / `checkProgramDisclosureResultV1` /
  `checkBody` / `checkConstValue` are exact erase projections of the same walk.
  Violation drafts: primary = exact sink input expr/control node; related =
  stable-unique primary-excluding union of value causes + active PC causes +
  sink contract/site. VisibilityEvidence joins keep more-secret causes and
  stable-union equal labels; paths never alter flow decisions.
  B7b3cR: if/match PC joins and Expr.Match result taint use
  `withControlRootEvidence` so related includes the exact condition/scrutinee
  Expr root after declaration causes; nested lower-secrecy controls are still
  discarded by label-authoritative join.

  Duplicate `fn` keys make declaration tables ambiguous: analysisComplete=false,
  ok=false, no flow diagnostics; checkProgramDisclosureV1 surfaces name-resolution
  structural diagnostics.

  Product consumption: composed into `CheckV1` as the final disclosure phase;
  Normalize consumes its located result. The legacy alpha compatibility checker
  also consumes the unlocated projection.

  Out of scope for this module:
    * authority.* / state-custody.* analysis
    * deleting alpha Semantic visibility/requirement inference
    * B7b3d located CheckV1 composition

  N5/N-3 engineering: intrinsic `commit(x)` is the sole private→commitment
  declassification operator (result label = commitment; operand is not
  mayFlow-checked against commitment). Commitment still cannot flow to public_
  sinks (`return commit(x)`, public state assign) without a separate public
  path. `context.unixTimeSeconds` / `context.caller` are public_ / Principal
  identity (invocation-start snapshot; N-2).
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ContextCommitSurfaceV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.DisclosureCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.ContextCommitSurfaceV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

/-- Local inhabited instance so partial WalkM definitions can synthesize Nonempty. -/
instance : Inhabited VisibilityV1 where
  default := .public_

/-- Secrecy rank: larger means more secret. -/
def secrecy : VisibilityV1 → Nat
  | .public_ => 0
  | .commitment => 1
  | .private_ => 2

/-- Lattice join = maximum secrecy. -/
def joinVisibility (a b : VisibilityV1) : VisibilityV1 :=
  if secrecy a ≥ secrecy b then a else b

/-- True iff `src` may legally flow into a sink labeled `sink`. -/
def mayFlow (src sink : VisibilityV1) : Bool :=
  secrecy src ≤ secrecy sink

/-- Fixed label strings used in diagnostic messages. -/
def visibilityLabel : VisibilityV1 → String
  | .public_ => "public"
  | .commitment => "commitment"
  | .private_ => "private"

def visibilityViolationMessage (src sink : VisibilityV1) : String :=
  s!"disclosure violation: cannot flow '{visibilityLabel src}' into '{visibilityLabel sink}'"

def visibilityViolationDiagnostic (src sink : VisibilityV1) : DiagnosticV1 :=
  DiagnosticV1.make .visibilityViolation (visibilityViolationMessage src sink)

/-- Finite visibility label plus stable-unique canonical cause paths.
    Causes attribute provenance; they never alter flow decisions. -/
structure VisibilityEvidence where
  label : VisibilityV1
  causes : Array NormalizedSyntacticPathV1
  deriving Repr, Inhabited

def publicEvidence : VisibilityEvidence :=
  { label := .public_, causes := #[] }

def evidenceWithLabel (label : VisibilityV1) : VisibilityEvidence :=
  { label, causes := #[] }

def evidenceWithCause (label : VisibilityV1) (cause? : Option NormalizedSyntacticPathV1) :
    VisibilityEvidence :=
  match cause? with
  | some p => { label, causes := #[p] }
  | none => { label, causes := #[] }

/-- First-seen stable unique path append. -/
def pushUniquePath (acc : Array NormalizedSyntacticPathV1)
    (p : NormalizedSyntacticPathV1) : Array NormalizedSyntacticPathV1 :=
  if acc.any (· == p) then acc else acc.push p

/-- First-seen stable unique union (left then right). -/
def stableUniqueUnion (a b : Array NormalizedSyntacticPathV1) :
    Array NormalizedSyntacticPathV1 :=
  b.foldl pushUniquePath a

/-- Join evidence: keep causes of the more-secret label; on equal labels
    stable-unique union. Label decision equals `joinVisibility`. -/
def joinVisibilityEvidence (a b : VisibilityEvidence) : VisibilityEvidence :=
  let sa := secrecy a.label
  let sb := secrecy b.label
  if sa > sb then a
  else if sb > sa then b
  else { label := a.label, causes := stableUniqueUnion a.causes b.causes }

/-- Augment computed visibility evidence with the control-input expression root
    that raised PC (`Stmt.If` condition, `Stmt.Match`/`Expr.Match` scrutinee).
    Existing declaration/value causes stay first-seen; control root is appended
    if present and unique. Label and flow decisions are unchanged — callers must
    still join via `joinVisibilityEvidence` so more-secret outer PC discards a
    lower-secrecy nested control's causes (including its control root). -/
def withControlRootEvidence (ev : VisibilityEvidence)
    (controlRoot? : Option NormalizedSyntacticPathV1) : VisibilityEvidence :=
  match controlRoot? with
  | none => ev
  | some p => { ev with causes := pushUniquePath ev.causes p }

/-- Effective source label at a sink: value secrecy joined with PC. -/
def effectiveSource (pc valueVis : VisibilityV1) : VisibilityV1 :=
  joinVisibility valueVis pc

def effectiveSourceEvidence (pc value : VisibilityEvidence) : VisibilityEvidence :=
  joinVisibilityEvidence value pc

/-- Local scope: params by declaration; locals most-recent-first shadow earlier
    locals and all params/state. Entries carry VisibilityEvidence. -/
structure DisclosureScope where
  locals : List (SourceNameComponentV1 × VisibilityEvidence)
  params : Array (SourceNameComponentV1 × VisibilityEvidence)

def emptyDisclosureScope : DisclosureScope :=
  { locals := [], params := #[] }

def scopeFromParamEvidence (params : Array (SourceNameComponentV1 × VisibilityEvidence)) :
    DisclosureScope :=
  { locals := [], params }

def lookupLocal (scope : DisclosureScope) (name : SourceNameComponentV1) :
    Option VisibilityEvidence :=
  (scope.locals.find? (fun p => p.1 == name)).map (·.2)

def lookupParam (scope : DisclosureScope) (name : SourceNameComponentV1) :
    Option VisibilityEvidence :=
  (scope.params.find? (fun p => p.1 == name)).map (·.2)

/-- Resolve a bare name to visibility evidence. Unknown names are public_ with
    empty causes (resolution errors are not re-emitted by this pass). Const names
    resolve as public_ with ConstDecl cause when available. -/
def lookupName (tables : TypedDeclTablesV1) (scope : DisclosureScope)
    (name : SourceNameComponentV1) : VisibilityEvidence :=
  match lookupLocal scope name with
  | some v => v
  | none =>
    match lookupParam scope name with
    | some v => v
    | none =>
      match tables.state.find? name with
      | some (_, decl) =>
          evidenceWithCause decl.visibility (itemPathForNamed? tables .state name)
      | none =>
          match tables.const.find? name with
          | some _ =>
              evidenceWithCause .public_ (itemPathForNamed? tables .const name)
          | none => publicEvidence

/-- Same shadowing as NameResolutionV1.resolveLocalCall / TypeCheckV1:
    locals and params shadow top-level `fn` names. -/
def resolveCalleeFnDecl (tables : TypedDeclTablesV1) (scope : DisclosureScope)
    (callee : SourceNameComponentV1) : Option FnDeclV1 :=
  if (lookupLocal scope callee).isSome then none
  else if (lookupParam scope callee).isSome then none
  else
    match tables.fn.find? callee with
    | some (_, decl) => some decl
    | none => none

/-- Whether a bare name resolves to a state cell through the current scope. -/
def resolvesToState (tables : TypedDeclTablesV1) (scope : DisclosureScope)
    (name : SourceNameComponentV1) : Bool :=
  if (lookupLocal scope name).isSome then false
  else if (lookupParam scope name).isSome then false
  else tables.state.find? name |>.isSome

def placeRootName : PlaceV1 → SourceNameComponentV1
  | .name n => n
  | .field base _ => placeRootName base
  | .index base _ => placeRootName base

/-- Walk state: accumulate all flow-violation drafts in source order. -/
structure WalkState where
  drafts : Array TypedDiagnosticDraftV1
  deriving Inhabited

abbrev WalkM := StateM WalkState

def emitPathError (detail : String) : WalkM Unit :=
  modify fun s =>
    { s with drafts := s.drafts.push (pathInternalDraft detail) }

def childOrFail
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    WalkM (Option NormalizedSyntacticPathV1) :=
  match childPathV1 parent parentTag fieldTag index with
  | .ok p => pure (some p)
  | .error detail => do
      emitPathError detail
      pure none

def directOrFail
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) : WalkM (Option NormalizedSyntacticPathV1) :=
  childOrFail parent parentTag fieldTag 0

/-- Exclude `primary` then stable-unique fold. -/
def relatedWithoutPrimary
    (primary? : Option NormalizedSyntacticPathV1)
    (paths : Array NormalizedSyntacticPathV1) : Array NormalizedSyntacticPathV1 :=
  paths.foldl (init := #[]) fun acc p =>
    match primary? with
    | some prim => if p == prim then acc else pushUniquePath acc p
    | none => pushUniquePath acc p

def visibilityViolationDraft
    (src sink : VisibilityV1)
    (primary? : Option NormalizedSyntacticPathV1)
    (related : Array NormalizedSyntacticPathV1) : TypedDiagnosticDraftV1 :=
  let msg := visibilityViolationMessage src sink
  match primary? with
  | some primary =>
      makeLocated .visibilityViolation msg primary
        (relatedWithoutPrimary (some primary) related)
  | none =>
      make .visibilityViolation msg

/-- Emit flow violation draft when `src` may not flow into `sink`.
    Related = value causes ∪ pc causes ∪ sinkSites (primary excluded). -/
def emitFlow
    (srcEv pcEv : VisibilityEvidence) (sink : VisibilityV1)
    (primary? : Option NormalizedSyntacticPathV1)
    (sinkSites : Array NormalizedSyntacticPathV1) : WalkM Unit :=
  let effectiveLabel := effectiveSource pcEv.label srcEv.label
  if mayFlow effectiveLabel sink then pure ()
  else
    let related :=
      stableUniqueUnion srcEv.causes (stableUniqueUnion pcEv.causes sinkSites)
    modify fun s =>
      { s with
        drafts := s.drafts.push
          (visibilityViolationDraft effectiveLabel sink primary? related) }

def requirePublic
    (pcEv srcEv : VisibilityEvidence)
    (primary? : Option NormalizedSyntacticPathV1)
    (sinkSites : Array NormalizedSyntacticPathV1) : WalkM Unit :=
  emitFlow srcEv pcEv .public_ primary? sinkSites

def emitFlowUnderPc
    (pcEv srcEv : VisibilityEvidence) (sink : VisibilityV1)
    (primary? : Option NormalizedSyntacticPathV1)
    (sinkSites : Array NormalizedSyntacticPathV1) : WalkM Unit :=
  emitFlow srcEv pcEv sink primary? sinkSites

def optPathArray (p? : Option NormalizedSyntacticPathV1) :
    Array NormalizedSyntacticPathV1 :=
  match p? with
  | some p => #[p]
  | none => #[]

/-- Seed param evidence from declaration params + optional callable item path. -/
def seedParamEvidence
    (params : Array ParamV1)
    (itemPath? : Option NormalizedSyntacticPathV1)
    (parentTag : String) : WalkM (Array (SourceNameComponentV1 × VisibilityEvidence)) := do
  let mut out : Array (SourceNameComponentV1 × VisibilityEvidence) := #[]
  for (param, i) in params.zipIdx do
    let cause? ← match itemPath? with
      | none => pure none
      | some ip => childOrFail ip parentTag "params" i
    out := out.push (param.name, evidenceWithCause param.visibility cause?)
  pure out

mutual
  /-- Infer expression visibility bottom-up while emitting index/public sinks
      under the current program-counter evidence. -/
  partial def exprVisibility (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityEvidence) (exprPath? : Option NormalizedSyntacticPathV1) :
      ExprV1 → WalkM VisibilityEvidence
    | .literal _ => pure publicEvidence
    | .place p => do
        let pp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Place" "place"
        placeRValueVisibility tables scope pc pp? p
    | .constructor ctor args => do
        -- ADR-0030 E2: env-read catalog QNs produce a public_ result (balance
        -- read is a public observation); args are explicit public sinks (the
        -- mint Principal is a key, not a value that taints the result).
        let ctorQn := sourceQualifiedNameV1ToString ctor
        if isPfAssetsEnvReadQnV1 ctorQn then
          for (a, i) in args.zipIdx do
            let ap? ← match exprPath? with
              | none => pure none
              | some ep => childOrFail ep "Expr.Constructor" "args" i
            let v ← exprVisibility tables scope pc ap? a
            requirePublic pc v ap?
              (stableUniqueUnion (optPathArray exprPath?) (optPathArray exprPath?))
          pure publicEvidence
        else
          let mut acc : VisibilityEvidence := publicEvidence
          for (a, i) in args.zipIdx do
            let ap? ← match exprPath? with
              | none => pure none
              | some ep => childOrFail ep "Expr.Constructor" "args" i
            let v ← exprVisibility tables scope pc ap? a
            acc := joinVisibilityEvidence acc v
          pure acc
    | .unary _ e => do
        let op? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Unary" "operand"
        exprVisibility tables scope pc op? e
    | .binary _ lhs rhs => do
        let lp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Binary" "lhs"
        let lv ← exprVisibility tables scope pc lp? lhs
        let rp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Binary" "rhs"
        let rv ← exprVisibility tables scope pc rp? rhs
        pure (joinVisibilityEvidence lv rv)
    | .localCall callee args => do
        -- N5: intrinsic `commit(x)` is the sole private→commitment declassification
        -- operator. Walk the operand for nested sinks but do **not** mayFlow-check
        -- the operand into commitment; result label is always commitment (causes
        -- retained from the operand). User `fn commit` still takes the ordinary path.
        if isCommitCalleeNameV1 callee &&
            (resolveCalleeFnDecl tables scope callee).isNone &&
            args.size == 1 then
          match args[0]? with
          | none => pure (evidenceWithLabel .commitment)
          | some arg0 =>
              let ap? ← match exprPath? with
                | none => pure none
                | some ep => childOrFail ep "Expr.LocalCall" "args" 0
              let v ← exprVisibility tables scope pc ap? arg0
              pure { label := .commitment, causes := v.causes }
        else
          -- Explicit sinks: each arg flows into the corresponding ParamV1.visibility
          -- when the callee resolves to a top-level `fn` (locals/params shadow).
          -- Arity mismatch is type-phase territory: walk args for nested sinks only.
          -- Successful call result is public_ (fn returns are public sinks).
          match resolveCalleeFnDecl tables scope callee with
          | some decl =>
              if decl.params.size == args.size then
                for ((param, arg), i) in (decl.params.zip args).zipIdx do
                  let ap? ← match exprPath? with
                    | none => pure none
                    | some ep => childOrFail ep "Expr.LocalCall" "args" i
                  let v ← exprVisibility tables scope pc ap? arg
                  let paramPath? := fnParamPath? tables decl.name i
                  emitFlowUnderPc pc v param.visibility ap? (optPathArray paramPath?)
              else
                for (a, i) in args.zipIdx do
                  let ap? ← match exprPath? with
                    | none => pure none
                    | some ep => childOrFail ep "Expr.LocalCall" "args" i
                  let _ ← exprVisibility tables scope pc ap? a
          | none =>
              for (a, i) in args.zipIdx do
                let ap? ← match exprPath? with
                  | none => pure none
                  | some ep => childOrFail ep "Expr.LocalCall" "args" i
                let _ ← exprVisibility tables scope pc ap? a
          pure publicEvidence
    | .externalCall call => do
        -- N-CALL-RET: value-position sync call. Args are explicit public sinks
        -- (same as statement call); the result label is public_.
        let callPath? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.ExternalCall" "call"
        for (a, i) in call.args.zipIdx do
          let ap? ← match callPath? with
            | none => pure none
            | some cp => childOrFail cp "ExternalCallExpr" "args" i
          let v ← exprVisibility tables scope pc ap? a
          requirePublic pc v ap?
            (stableUniqueUnion (optPathArray exprPath?) (optPathArray callPath?))
        pure publicEvidence
    | .match_ scrutinee arms => do
        -- Expression match: result = join(scrutControl, join of arm values) so
        -- the scrutinee control-taints the result (decl causes + scrutinee Expr
        -- root). Arm expressions walk under pc' = join(pc, scrutControl);
        -- binders still inherit raw scrutVis for value flow (decl causes only).
        let sp? ← match exprPath? with
          | none => pure none
          | some ep => directOrFail ep "Expr.Match" "scrutinee"
        let scrutVis ← exprVisibility tables scope pc sp? scrutinee
        let scrutControl := withControlRootEvidence scrutVis sp?
        let pc' := joinVisibilityEvidence pc scrutControl
        let mut acc : VisibilityEvidence := publicEvidence
        for (arm, i) in arms.zipIdx do
          let binders := patternBinders arm.pattern scrutVis
          let armScope := { scope with locals := binders ++ scope.locals }
          let vp? ← match exprPath? with
            | none => pure none
            | some ep => do
                match ← childOrFail ep "Expr.Match" "arms" i with
                | none => pure none
                | some armPath => directOrFail armPath "ExprMatchArm" "value"
          let v ← exprVisibility tables armScope pc' vp? arm.value
          acc := joinVisibilityEvidence acc v
        pure (joinVisibilityEvidence scrutControl acc)

  /-- R-value place: field keeps base; index joins base with index expr and
      treats the index expression as a public-required sink under PC. -/
  partial def placeRValueVisibility (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityEvidence) (placePath? : Option NormalizedSyntacticPathV1) :
      PlaceV1 → WalkM VisibilityEvidence
    | .name n => pure (lookupName tables scope n)
    | .field base field => do
        -- N5: context.unixTimeSeconds is a public invocation-start snapshot.
        if isContextUnixTimeSecondsPlaceV1 (.field base field) then
          pure publicEvidence
        else do
          let bp? ← match placePath? with
            | none => pure none
            | some pp => directOrFail pp "Place.Field" "base"
          placeRValueVisibility tables scope pc bp? base
    | .index base idx => do
        let bp? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "base"
        let baseVis ← placeRValueVisibility tables scope pc bp? base
        let ip? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "index"
        let idxVis ← exprVisibility tables scope pc ip? idx
        requirePublic pc idxVis ip? (optPathArray placePath?)
        pure (joinVisibilityEvidence baseVis idxVis)

  /-- Assignment-target place visibility: root name/field chain secrecy only
      (index expressions are still public-required sinks under PC, but do not
      raise the sink label of the cell being written). -/
  partial def placeTargetVisibility (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityEvidence) (placePath? : Option NormalizedSyntacticPathV1) :
      PlaceV1 → WalkM VisibilityEvidence
    | .name n => pure (lookupName tables scope n)
    | .field base _ => do
        let bp? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Field" "base"
        placeTargetVisibility tables scope pc bp? base
    | .index base idx => do
        let bp? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "base"
        let baseVis ← placeTargetVisibility tables scope pc bp? base
        let ip? ← match placePath? with
          | none => pure none
          | some pp => directOrFail pp "Place.Index" "index"
        let idxVis ← exprVisibility tables scope pc ip? idx
        requirePublic pc idxVis ip? (optPathArray placePath?)
        pure baseVis

  /-- Pattern binders inherit the scrutinee visibility evidence (value flow). -/
  partial def patternBinders (pattern : PatternV1) (scrutVis : VisibilityEvidence) :
      List (SourceNameComponentV1 × VisibilityEvidence) :=
    match pattern with
    | PatternV1.wildcard | PatternV1.literal _ => []
    | PatternV1.bind name => [(name, scrutVis)]
    | PatternV1.constructor _ args =>
        args.foldl (fun acc p => acc ++ patternBinders p scrutVis) []

  partial def checkBlock (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityEvidence) (blockPath? : Option NormalizedSyntacticPathV1)
      (callablePath? : Option NormalizedSyntacticPathV1) (block : BlockV1) :
      WalkM Unit :=
    checkStmts tables scope pc blockPath? callablePath? block.statements.toList 0

  partial def checkStmts (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityEvidence) (blockPath? : Option NormalizedSyntacticPathV1)
      (callablePath? : Option NormalizedSyntacticPathV1) :
      List StmtV1 → Nat → WalkM Unit
    | [], _ => pure ()
    | stmt :: rest, idx => do
        let stmtPath? ← match blockPath? with
          | none => pure none
          | some bp => childOrFail bp "Block" "statements" idx
        let added ← checkStmt tables scope pc stmtPath? callablePath? stmt
        checkStmts tables { scope with locals := added ++ scope.locals } pc
          blockPath? callablePath? rest (idx + 1)

  partial def checkStmt (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityEvidence) (stmtPath? : Option NormalizedSyntacticPathV1)
      (callablePath? : Option NormalizedSyntacticPathV1) :
      StmtV1 → WalkM (List (SourceNameComponentV1 × VisibilityEvidence))
    | .let_ name _ value => do
        let vp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Let" "value"
        let v ← exprVisibility tables scope pc vp? value
        pure [(name, v)]
    | .assign target value => do
        let tp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Assign" "target"
        let sinkEv ← placeTargetVisibility tables scope pc tp? target
        let vp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Assign" "value"
        let src ← exprVisibility tables scope pc vp? value
        let mut sinkSites := optPathArray tp?
        let root := placeRootName target
        if resolvesToState tables scope root then
          sinkSites := stableUniqueUnion sinkSites
            (optPathArray (itemPathForNamed? tables .state root))
        emitFlowUnderPc pc src sinkEv.label vp? sinkSites
        pure []
    | .if_ condition thenBlock elseBlock? => do
        -- Condition is not a public *value* sink; it raises PC for branches.
        -- PC evidence = decl/value causes of condition + condition Expr root.
        let cp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.If" "condition"
        let condVis ← exprVisibility tables scope pc cp? condition
        let pc' := joinVisibilityEvidence pc (withControlRootEvidence condVis cp?)
        let tp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.If" "thenBlock"
        checkBlock tables scope pc' tp? callablePath? thenBlock
        match elseBlock? with
        | none => pure ()
        | some eb => do
            let ep? ← match stmtPath? with
              | none => pure none
              | some sp => directOrFail sp "Stmt.If" "elseBlock"
            checkBlock tables scope pc' ep? callablePath? eb
        pure []
    | .match_ scrutinee arms => do
        -- Scrutinee raises PC with decl causes + scrutinee Expr root.
        -- Binders still inherit raw scrutVis for value flow.
        let sp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Match" "scrutinee"
        let scrutVis ← exprVisibility tables scope pc sp? scrutinee
        let pc' := joinVisibilityEvidence pc (withControlRootEvidence scrutVis sp?)
        for (arm, i) in arms.zipIdx do
          let binders := patternBinders arm.pattern scrutVis
          let bp? ← match stmtPath? with
            | none => pure none
            | some sp => do
                match ← childOrFail sp "Stmt.Match" "arms" i with
                | none => pure none
                | some armPath => directOrFail armPath "StmtMatchArm" "body"
          checkBlock tables { scope with locals := binders ++ scope.locals }
            pc' bp? callablePath? arm.body
        pure []
    | .for_ binder start endExclusive _ body => do
        let sp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.For" "start"
        let startVis ← exprVisibility tables scope pc sp? start
        requirePublic pc startVis sp? (optPathArray stmtPath?)
        let ep? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.For" "endExclusive"
        let endVis ← exprVisibility tables scope pc ep? endExclusive
        requirePublic pc endVis ep? (optPathArray stmtPath?)
        -- For-loop binder is public_ (iterator identity is not secret).
        -- Body runs under current PC (no extra raise from endpoints).
        let bp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.For" "body"
        checkBlock tables
          { scope with locals := (binder, publicEvidence) :: scope.locals }
          pc bp? callablePath? body
        pure []
    | .assert_ condition _ => do
        -- Condition is a public sink (assert ⇒ failure.revert / observable).
        -- Nested sinks use current PC; assert does not raise PC for subsequent
        -- statements (assert is not a branch).
        let cp? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Assert" "condition"
        let condVis ← exprVisibility tables scope pc cp? condition
        requirePublic pc condVis cp? (optPathArray stmtPath?)
        pure []
    | .revert _ args => do
        for (a, i) in args.zipIdx do
          let ap? ← match stmtPath? with
            | none => pure none
            | some sp => childOrFail sp "Stmt.Revert" "args" i
          let v ← exprVisibility tables scope pc ap? a
          requirePublic pc v ap? (optPathArray stmtPath?)
        pure []
    | .emit _ args => do
        for (a, i) in args.zipIdx do
          let ap? ← match stmtPath? with
            | none => pure none
            | some sp => childOrFail sp "Stmt.Emit" "args" i
          let v ← exprVisibility tables scope pc ap? a
          requirePublic pc v ap? (optPathArray stmtPath?)
        pure []
    | .return_ value? => do
        match value? with
        | none => pure ()
        | some e => do
            let vp? ← match stmtPath? with
              | none => pure none
              | some sp => directOrFail sp "Stmt.Return" "value"
            let v ← exprVisibility tables scope pc vp? e
            let sinkSites :=
              stableUniqueUnion (optPathArray stmtPath?) (optPathArray callablePath?)
            requirePublic pc v vp? sinkSites
        pure []
    | .call externalCall => do
        let callPath? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Call" "call"
        for (a, i) in externalCall.args.zipIdx do
          let ap? ← match callPath? with
            | none => pure none
            | some cp => childOrFail cp "ExternalCallExpr" "args" i
          let v ← exprVisibility tables scope pc ap? a
          requirePublic pc v ap?
            (stableUniqueUnion (optPathArray stmtPath?) (optPathArray callPath?))
        pure []
    | .schedule externalCall => do
        let callPath? ← match stmtPath? with
          | none => pure none
          | some sp => directOrFail sp "Stmt.Schedule" "call"
        for (a, i) in externalCall.args.zipIdx do
          let ap? ← match callPath? with
            | none => pure none
            | some cp => childOrFail cp "ExternalCallExpr" "args" i
          let v ← exprVisibility tables scope pc ap? a
          requirePublic pc v ap?
            (stableUniqueUnion (optPathArray stmtPath?) (optPathArray callPath?))
        pure []
end

/-- Path-threaded body draft collection. When paths are `none`, drafts are
    unlocated (legacy erase projection). -/
def checkBodyDrafts
    (tables : TypedDeclTablesV1) (params : Array ParamV1) (body : BlockV1)
    (itemPath? : Option NormalizedSyntacticPathV1)
    (parentTag : String) : Array TypedDiagnosticDraftV1 :=
  let bodyPath? : Option NormalizedSyntacticPathV1 :=
    match itemPath? with
    | none => none
    | some ip =>
        match directChildPathV1 ip parentTag "body" with
        | .ok bp => some bp
        | .error _ => none
  let pathErrs : Array TypedDiagnosticDraftV1 :=
    match itemPath? with
    | none => #[]
    | some ip =>
        match directChildPathV1 ip parentTag "body" with
        | .error detail => #[pathInternalDraft detail]
        | .ok _ => #[]
  let init : WalkState := { drafts := pathErrs }
  let walk : WalkM Unit := do
    let paramEv ← seedParamEvidence params itemPath? parentTag
    checkBlock tables (scopeFromParamEvidence paramEv) publicEvidence
      bodyPath? itemPath? body
  let (_, st) := walk.run init
  st.drafts

def checkBody (tables : TypedDeclTablesV1) (params : Array ParamV1) (body : BlockV1) :
    Array DiagnosticV1 :=
  eraseArray (checkBodyDrafts tables params body none "FnDecl")

/-- Const defining expression draft walk under empty scope and public PC. -/
def checkConstValueDrafts
    (tables : TypedDeclTablesV1) (value : ExprV1)
    (itemPath? : Option NormalizedSyntacticPathV1) :
    Array TypedDiagnosticDraftV1 :=
  let valuePath? : Option NormalizedSyntacticPathV1 :=
    match itemPath? with
    | none => none
    | some ip =>
        match directChildPathV1 ip "ConstDecl" "value" with
        | .ok vp => some vp
        | .error _ => none
  let pathErrs : Array TypedDiagnosticDraftV1 :=
    match itemPath? with
    | none => #[]
    | some ip =>
        match directChildPathV1 ip "ConstDecl" "value" with
        | .error detail => #[pathInternalDraft detail]
        | .ok _ => #[]
  let init : WalkState := { drafts := pathErrs }
  let walk : WalkM Unit := do
    let v ← exprVisibility tables emptyDisclosureScope publicEvidence valuePath? value
    requirePublic publicEvidence v valuePath? (optPathArray itemPath?)
  let (_, st) := walk.run init
  st.drafts

/-- Const defining expression under empty/local scope and public PC: nested sinks
    are checked via `exprVisibility`, then the value itself must flow into public_
    (const names resolve as public_ thereafter — no private→const laundering). -/
def checkConstValue (tables : TypedDeclTablesV1) (value : ExprV1) : Array DiagnosticV1 :=
  eraseArray (checkConstValueDrafts tables value none)

/-- Result of the disclosure / visibility-flow checker.

    `analysisComplete` is false when declaration tables are too ambiguous
    (currently: duplicate `fn` keys).  In that case `ok` is also false and no
    flow diagnostics are produced. -/
structure DisclosureCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Draft-bearing authority result (B7b3c). -/
structure DisclosureCheckDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

def incompleteDisclosureResult : DisclosureCheckResultV1 :=
  { diagnostics := #[], ok := false, analysisComplete := false }

def incompleteDisclosureDraftResult : DisclosureCheckDraftResultV1 :=
  { drafts := #[], ok := false, analysisComplete := false }

/-- Draft authority: path-threaded disclosure check on ProgramV1. -/
def checkDisclosureDraftsV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    DisclosureCheckDraftResultV1 :=
  if tables.fn.hasDuplicateKey then
    incompleteDisclosureDraftResult
  else
    let drafts := program.items.zipIdx.foldl (init := #[]) fun acc (item, itemIndex) =>
      match programItemPathV1 itemIndex with
      | .error detail => acc.push (pathInternalDraft detail)
      | .ok itemPath =>
          match item with
          | .const decl =>
              acc ++ checkConstValueDrafts tables decl.value (some itemPath)
          | .fn decl =>
              acc ++
                checkBodyDrafts tables decl.params decl.body (some itemPath) "FnDecl"
          | .entry decl =>
              acc ++
                checkBodyDrafts tables decl.params decl.body (some itemPath) "EntryDecl"
          | .view decl =>
              acc ++
                checkBodyDrafts tables decl.params decl.body (some itemPath) "ViewDecl"
          | .init decl =>
              acc ++
                checkBodyDrafts tables decl.params decl.body (some itemPath) "InitDecl"
          | _ => acc
    { drafts := drafts
      ok := drafts.isEmpty
      analysisComplete := true }

/-- Check disclosure flow (explicit + PC-label implicit) on ProgramV1 using
    declaration tables.

    When `tables.fn` has duplicate keys, returns `analysisComplete = false` and
    does not invent flow diagnostics.  Otherwise walks const defining expressions
    and init/entry/view/fn bodies in program source order and collects all
    violations. Exact erase of `checkDisclosureDraftsV1`. -/
def checkDisclosureV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    DisclosureCheckResultV1 :=
  let r := checkDisclosureDraftsV1 program tables
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

/-- Draft-bearing entry over a validated source unit. -/
def checkProgramDisclosureDraftsV1 (source : ValidatedSourceV1) :
    DisclosureCheckDraftResultV1 :=
  let resolution := resolveProgramDraftsV1 source
  let discRes := checkDisclosureDraftsV1 source.program resolution.tables
  if discRes.analysisComplete then
    discRes
  else
    { drafts := resolution.drafts ++ discRes.drafts
      ok := false
      analysisComplete := false }

/-- Entry point over a validated source unit.

    Builds declaration tables via name resolution.  When disclosure analysis is
    incomplete (duplicate `fn` keys), returns resolution structural diagnostics
    so the independent entry fails closed.  When complete, returns flow
    diagnostics only. Exact erase of draft authority. -/
def checkProgramDisclosureV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  eraseArray (checkProgramDisclosureDraftsV1 source).drafts

/-- Full result entry including `analysisComplete`, for tests and future product
    wiring that need the structured outcome. -/
def checkProgramDisclosureResultV1 (source : ValidatedSourceV1) : DisclosureCheckResultV1 :=
  let r := checkProgramDisclosureDraftsV1 source
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

end ProofForgeV2.Typed.DisclosureCheckV1
