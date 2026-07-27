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
      pc' = joinVisibility(pc, conditionVis). Condition is not itself a public
      *value* sink, but raises PC for the branches.
    * match_ (statement): evaluate scrutinee; arm bodies under
      pc' = joinVisibility(pc, scrutVis). Pattern binders still inherit scrutVis
      for *value* flow (unchanged).
    * match_ (expression): result visibility =
      joinVisibility(scrutVis, join of arm value visibilities) so the scrutinee
      control-taints the expression result; arm expressions are walked under
      pc' for nested sinks.
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

  Duplicate `fn` keys make declaration tables ambiguous: analysisComplete=false,
  ok=false, no flow diagnostics; checkProgramDisclosureV1 surfaces name-resolution
  structural diagnostics.

  Product consumption: composed into `CheckV1` (final disclosure phase) and
  fail-closed gated from `Typed.checkV1`.

  Out of scope for this module:
    * authority.* / state-custody.* analysis
    * disclosure.commit effect or commit operator (no AST surface)
    * deleting alpha Semantic visibility/requirement inference
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.DisclosureCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

/-- Local inhabited instance so partial WalkM definitions can synthesize Nonempty. -/
instance : Inhabited VisibilityV1 where
  default := .public_

def emptyOrigins : Array SourceOrigin := #[]

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

def visibilityViolationDiagnostic (src sink : VisibilityV1) : DiagnosticV1 :=
  { code := .visibilityViolation
    message :=
      s!"disclosure violation: cannot flow '{visibilityLabel src}' into '{visibilityLabel sink}'"
    origins := emptyOrigins }

/-- Effective source at a sink: value secrecy joined with the current PC label. -/
def effectiveSource (pc valueVis : VisibilityV1) : VisibilityV1 :=
  joinVisibility valueVis pc

/-- Local scope: params by declaration; locals most-recent-first shadow earlier
    locals and all params/state. -/
structure DisclosureScope where
  locals : List (SourceNameComponentV1 × VisibilityV1)
  params : Array ParamV1

def emptyDisclosureScope : DisclosureScope :=
  { locals := [], params := #[] }

def scopeFromParams (params : Array ParamV1) : DisclosureScope :=
  { locals := [], params }

def lookupLocal (scope : DisclosureScope) (name : SourceNameComponentV1) :
    Option VisibilityV1 :=
  (scope.locals.find? (fun p => p.1 == name)).map (·.2)

def lookupParam (scope : DisclosureScope) (name : SourceNameComponentV1) :
    Option VisibilityV1 :=
  (scope.params.find? (fun p => p.name == name)).map (·.visibility)

/-- Resolve a bare name to a visibility label.  Unknown names are treated as
    public_ (resolution errors are not re-emitted by this pass).  Const names
    resolve as public_ because defining expressions are requirePublic-checked. -/
def lookupName (tables : TypedDeclTablesV1) (scope : DisclosureScope)
    (name : SourceNameComponentV1) : VisibilityV1 :=
  match lookupLocal scope name with
  | some v => v
  | none =>
    match lookupParam scope name with
    | some v => v
    | none =>
      match tables.state.find? name with
      | some (_, decl) => decl.visibility
      | none =>
        -- Const defining values are checked as public sinks; names are public_.
        match tables.const.find? name with
        | some _ => .public_
        | none => .public_

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

/-- Walk state: accumulate all flow violations in source order. -/
structure WalkState where
  diagnostics : Array DiagnosticV1
  deriving Inhabited

abbrev WalkM := StateM WalkState

def emitFlow (src sink : VisibilityV1) : WalkM Unit :=
  if mayFlow src sink then pure ()
  else
    modify fun s =>
      { s with diagnostics := s.diagnostics.push (visibilityViolationDiagnostic src sink) }

/-- Require that effective source under `pc` may flow into a public_ sink. -/
def requirePublic (pc src : VisibilityV1) : WalkM Unit :=
  emitFlow (effectiveSource pc src) .public_

/-- Emit flow from effective source under `pc` into `sink`. -/
def emitFlowUnderPc (pc src sink : VisibilityV1) : WalkM Unit :=
  emitFlow (effectiveSource pc src) sink

mutual
  /-- Infer expression visibility bottom-up while emitting index/public sinks
      under the current program-counter label. -/
  partial def exprVisibility (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityV1) : ExprV1 → WalkM VisibilityV1
    | .literal _ => pure .public_
    | .place p => placeRValueVisibility tables scope pc p
    | .constructor _ args => do
        let mut acc : VisibilityV1 := .public_
        for a in args do
          let v ← exprVisibility tables scope pc a
          acc := joinVisibility acc v
        pure acc
    | .unary _ e => exprVisibility tables scope pc e
    | .binary _ lhs rhs => do
        let lv ← exprVisibility tables scope pc lhs
        let rv ← exprVisibility tables scope pc rhs
        pure (joinVisibility lv rv)
    | .localCall callee args => do
        -- Explicit sinks: each arg flows into the corresponding ParamV1.visibility
        -- when the callee resolves to a top-level `fn` (locals/params shadow).
        -- Arity mismatch is type-phase territory: walk args for nested sinks only.
        -- Successful call result is public_ (fn returns are public sinks).
        match resolveCalleeFnDecl tables scope callee with
        | some decl =>
            if decl.params.size == args.size then
              for (param, arg) in decl.params.zip args do
                let v ← exprVisibility tables scope pc arg
                emitFlowUnderPc pc v param.visibility
            else
              for a in args do
                let _ ← exprVisibility tables scope pc a
        | none =>
            for a in args do
              let _ ← exprVisibility tables scope pc a
        pure .public_
    | .match_ scrutinee arms => do
        -- Expression match: result = join(scrutVis, join of arm values) so the
        -- scrutinee control-taints the result. Arm expressions walk under
        -- pc' = join(pc, scrutVis) for nested sinks; binders inherit scrutVis
        -- for value flow.
        let scrutVis ← exprVisibility tables scope pc scrutinee
        let pc' := joinVisibility pc scrutVis
        let mut acc : VisibilityV1 := .public_
        for arm in arms do
          let binders := patternBinders arm.pattern scrutVis
          let armScope := { scope with locals := binders ++ scope.locals }
          let v ← exprVisibility tables armScope pc' arm.value
          acc := joinVisibility acc v
        pure (joinVisibility scrutVis acc)

  /-- R-value place: field keeps base; index joins base with index expr and
      treats the index expression as a public-required sink under PC. -/
  partial def placeRValueVisibility (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityV1) : PlaceV1 → WalkM VisibilityV1
    | .name n => pure (lookupName tables scope n)
    | .field base _ => placeRValueVisibility tables scope pc base
    | .index base idx => do
        let baseVis ← placeRValueVisibility tables scope pc base
        let idxVis ← exprVisibility tables scope pc idx
        requirePublic pc idxVis
        pure (joinVisibility baseVis idxVis)

  /-- Assignment-target place visibility: root name/field chain secrecy only
      (index expressions are still public-required sinks under PC, but do not
      raise the sink label of the cell being written). -/
  partial def placeTargetVisibility (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityV1) : PlaceV1 → WalkM VisibilityV1
    | .name n => pure (lookupName tables scope n)
    | .field base _ => placeTargetVisibility tables scope pc base
    | .index base idx => do
        let baseVis ← placeTargetVisibility tables scope pc base
        let idxVis ← exprVisibility tables scope pc idx
        requirePublic pc idxVis
        pure baseVis

  /-- Pattern binders inherit the scrutinee visibility (value flow). -/
  partial def patternBinders (pattern : PatternV1) (scrutVis : VisibilityV1) :
      List (SourceNameComponentV1 × VisibilityV1) :=
    match pattern with
    | PatternV1.wildcard | PatternV1.literal _ => []
    | PatternV1.bind name => [(name, scrutVis)]
    | PatternV1.constructor _ args =>
        args.foldl (fun acc p => acc ++ patternBinders p scrutVis) []

  partial def checkBlock (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityV1) (block : BlockV1) : WalkM Unit :=
    checkStmts tables scope pc block.statements.toList

  partial def checkStmts (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityV1) : List StmtV1 → WalkM Unit
    | [] => pure ()
    | stmt :: rest => do
        let added ← checkStmt tables scope pc stmt
        checkStmts tables { scope with locals := added ++ scope.locals } pc rest

  partial def checkStmt (tables : TypedDeclTablesV1) (scope : DisclosureScope)
      (pc : VisibilityV1) : StmtV1 → WalkM (List (SourceNameComponentV1 × VisibilityV1))
    | .let_ name _ value => do
        let v ← exprVisibility tables scope pc value
        pure [(name, v)]
    | .assign target value => do
        let sink ← placeTargetVisibility tables scope pc target
        let src ← exprVisibility tables scope pc value
        emitFlowUnderPc pc src sink
        pure []
    | .if_ condition thenBlock elseBlock? => do
        -- Condition is not a public *value* sink; it raises PC for branches.
        let condVis ← exprVisibility tables scope pc condition
        let pc' := joinVisibility pc condVis
        checkBlock tables scope pc' thenBlock
        elseBlock?.forM (checkBlock tables scope pc')
        pure []
    | .match_ scrutinee arms => do
        let scrutVis ← exprVisibility tables scope pc scrutinee
        let pc' := joinVisibility pc scrutVis
        for arm in arms do
          let binders := patternBinders arm.pattern scrutVis
          checkBlock tables { scope with locals := binders ++ scope.locals } pc' arm.body
        pure []
    | .for_ binder start endExclusive _ body => do
        let startVis ← exprVisibility tables scope pc start
        requirePublic pc startVis
        let endVis ← exprVisibility tables scope pc endExclusive
        requirePublic pc endVis
        -- For-loop binder is public_ (iterator identity is not secret).
        -- Body runs under current PC (no extra raise from endpoints).
        checkBlock tables { scope with locals := (binder, .public_) :: scope.locals } pc body
        pure []
    | .assert_ condition _ => do
        -- Condition is a public sink (assert ⇒ failure.revert / observable).
        -- Nested sinks use current PC; assert does not raise PC for subsequent
        -- statements (assert is not a branch).
        let condVis ← exprVisibility tables scope pc condition
        requirePublic pc condVis
        pure []
    | .revert _ args => do
        for a in args do
          let v ← exprVisibility tables scope pc a
          requirePublic pc v
        pure []
    | .emit _ args => do
        for a in args do
          let v ← exprVisibility tables scope pc a
          requirePublic pc v
        pure []
    | .return_ value? => do
        match value? with
        | none => pure ()
        | some e => do
            let v ← exprVisibility tables scope pc e
            requirePublic pc v
        pure []
    | .call externalCall => do
        for a in externalCall.args do
          let v ← exprVisibility tables scope pc a
          requirePublic pc v
        pure []
    | .schedule externalCall => do
        for a in externalCall.args do
          let v ← exprVisibility tables scope pc a
          requirePublic pc v
        pure []
end

def checkBody (tables : TypedDeclTablesV1) (params : Array ParamV1) (body : BlockV1) :
    Array DiagnosticV1 :=
  let init : WalkState := { diagnostics := #[] }
  let (_, st) := (checkBlock tables (scopeFromParams params) .public_ body).run init
  st.diagnostics

/-- Const defining expression under empty/local scope and public PC: nested sinks
    are checked via `exprVisibility`, then the value itself must flow into public_
    (const names resolve as public_ thereafter — no private→const laundering). -/
def checkConstValue (tables : TypedDeclTablesV1) (value : ExprV1) : Array DiagnosticV1 :=
  let init : WalkState := { diagnostics := #[] }
  let (_, st) := (do
    let v ← exprVisibility tables emptyDisclosureScope .public_ value
    requirePublic .public_ v).run init
  st.diagnostics

/-- Result of the disclosure / visibility-flow checker.

    `analysisComplete` is false when declaration tables are too ambiguous
    (currently: duplicate `fn` keys).  In that case `ok` is also false and no
    flow diagnostics are produced. -/
structure DisclosureCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

def incompleteDisclosureResult : DisclosureCheckResultV1 :=
  { diagnostics := #[], ok := false, analysisComplete := false }

/-- Check disclosure flow (explicit + PC-label implicit) on ProgramV1 using
    declaration tables.

    When `tables.fn` has duplicate keys, returns `analysisComplete = false` and
    does not invent flow diagnostics.  Otherwise walks const defining expressions
    and init/entry/view/fn bodies in program source order and collects all
    violations. -/
def checkDisclosureV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    DisclosureCheckResultV1 :=
  if tables.fn.hasDuplicateKey then
    incompleteDisclosureResult
  else
    let diagnostics := program.items.foldl (init := #[]) fun acc item =>
      match item with
      | .const decl => acc ++ checkConstValue tables decl.value
      | .fn decl => acc ++ checkBody tables decl.params decl.body
      | .entry decl => acc ++ checkBody tables decl.params decl.body
      | .view decl => acc ++ checkBody tables decl.params decl.body
      | .init decl => acc ++ checkBody tables decl.params decl.body
      | _ => acc
    { diagnostics := diagnostics
      ok := diagnostics.isEmpty
      analysisComplete := true }

/-- Entry point over a validated source unit.

    Builds declaration tables via name resolution.  When disclosure analysis is
    incomplete (duplicate `fn` keys), returns resolution structural diagnostics
    so the independent entry fails closed.  When complete, returns flow
    diagnostics only. -/
def checkProgramDisclosureV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  let resolution := resolveProgramV1 source
  let discRes := checkDisclosureV1 source.program resolution.tables
  if discRes.analysisComplete then
    discRes.diagnostics
  else
    resolution.diagnostics ++ discRes.diagnostics

/-- Full result entry including `analysisComplete`, for tests and future product
    wiring that need the structured outcome. -/
def checkProgramDisclosureResultV1 (source : ValidatedSourceV1) : DisclosureCheckResultV1 :=
  let resolution := resolveProgramV1 source
  let discRes := checkDisclosureV1 source.program resolution.tables
  if discRes.analysisComplete then
    discRes
  else
    { diagnostics := resolution.diagnostics ++ discRes.diagnostics
      ok := false
      analysisComplete := false }

end ProofForgeV2.Typed.DisclosureCheckV1
