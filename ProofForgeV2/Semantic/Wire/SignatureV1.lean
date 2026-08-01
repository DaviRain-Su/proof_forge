import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1

/-!
  ProofForgeV2.Semantic.Wire.SignatureV1 — callable signature phases,
  initializer/invariant special signatures, and InvariantDecl exact join.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

def validateCallableKindNamePresenceV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    match callable.kind, callable.name with
    | .initializer, none => pure ()
    | .entry, some _ | .view, some _ | .pureFn, some _
    | .invariant, some _ => pure ()
    | _, _ => return ← err .badCfg
  pure ()

/-- Named callables are unique within the unified callable table (SPEC §6).
    Compare exact UTF-8 strings; identifier grammar/NFC is the later
    declaration-name structure gate. Sorting a private name array preserves
    public callable source order. -/
def validateCallableNameUniquenessV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut names : Array String := #[]
  for callable in callables do
    match callable.name with
    | some name => names := names.push name
    | none => pure ()
  -- Zero/one extracted names are unique. Keep the canonical four-name proof
  -- subject transparent with a bounded exhaustive scan; larger tables retain
  -- the existing O(n log n) private-sort path below.
  if names.size ≤ 1 then return
  if names.size ≤ 4 then
    if names[0]! == names[1]! then return ← err .badCfg
    if names.size ≥ 3 then
      if names[0]! == names[2]! then return ← err .badCfg
      if names[1]! == names[2]! then return ← err .badCfg
    if names.size == 4 then
      if names[0]! == names[3]! then return ← err .badCfg
      if names[1]! == names[3]! then return ← err .badCfg
      if names[2]! == names[3]! then return ← err .badCfg
    return
  let sorted := names.qsort fun left right =>
    compareByteArrayLex left.toUTF8 right.toUTF8 == .lt
  let mut index : Nat := 1
  while index < sorted.size do
    if sorted[index - 1]! == sorted[index]! then
      return ← err .badCfg
    index := index + 1
  pure ()

/-- Parameter names are exact-string unique within each callable (SPEC §6).
    Each callable gets a fresh private sort; identifier grammar/NFC is the
    later declaration-name structure gate. -/
def validateCallableParameterNameUniquenessV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    let names := callable.params.map (·.name)
    if names.size ≤ 1 then continue
    let sorted := names.qsort fun left right =>
      compareByteArrayLex left.toUTF8 right.toUTF8 == .lt
    let mut index : Nat := 1
    while index < sorted.size do
      if sorted[index - 1]! == sorted[index]! then
        return ← err .badCfg
      index := index + 1
  pure ()

/-- SPEC §6 aggregate callable requirement: `callables` must contain at least
    one callable of kind `.entry` or `.view`. A program with only
    initializers/pureFns/invariants (or zero callables) has no externally
    invokable surface and is structurally invalid. This bounded source-order
    scan is O(callables)/O(1) and runs after callable kind/name presence,
    callable-name uniqueness, and per-callable parameter-name uniqueness, but
    before initializer/invariant signature checks, CFG, and requirements, so
    those later gates only observe programs that already expose an entry/view.
    `decodeSemanticProgramDataV1` transport remains permissive. -/
def validateCallableEntryViewPresenceV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let mut found := false
  for callable in callables do
    match callable.kind with
    | .entry | .view => found := true
    | _ => pure ()
  unless found do
    return ← err .badCfg
  pure ()

/-- At most one initializer callable may occur in source order (SPEC §6). -/
def validateInitializerCardinalityV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut seen : Bool := false
  for callable in callables do
    if callable.kind == .initializer then
      if seen then return ← err .badCfg
      seen := true
  pure ()

/-- Every initializer result resolves to Type.Unit and has public visibility
    (SPEC §6). Shallow result TypeId range validation runs earlier; this helper
    remains total and fails closed if called with a missing type. -/
def validateInitializerResultShapeV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .initializer then
      unless callable.result.visibility == .public_ do
        return ← err .badCfg
      match types[callable.result.typeId.toNat]? with
      | some decl =>
          match decl.shape with
          | .unit => pure ()
          | _ => return ← err .badCfg
      | none => return ← err .badCfg
  pure ()

/-- Every invariant callable result resolves to Type.Bool and has public
    visibility (SPEC §6). Declaration join, zero params, closure restrictions,
    and invariantSteps are separate gates. Shallow result TypeId range
    validation runs earlier; this helper stays total for missing types. -/
def validateInvariantResultShapeV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant then
      unless callable.result.visibility == .public_ do
        return ← err .badCfg
      match types[callable.result.typeId.toNat]? with
      | some decl =>
          match decl.shape with
          | .bool => pure ()
          | _ => return ← err .badCfg
      | none => return ← err .badCfg
  pure ()

/-- Invariant roots carry no parameters (SPEC §8). Declaration join, closure
    restrictions, and invariantSteps are separate gates. Parameter TypeId range
    validation runs in the earlier shallow-reference phase. -/
def validateInvariantParameterShapeV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant && !callable.params.isEmpty then
      return ← err .badCfg
  pure ()

/-- Invariant roots carry no loop bounds (SPEC §8). Their normalized closure
    must be acyclic; full closure validation and invariantSteps remain separate
    gates. Other callable kinds retain the generic bounded-loop contract. -/
def validateInvariantLoopBoundsShapeV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant && !callable.loopBounds.isEmpty then
      return ← err .badCfg
  pure ()

/-- Callables provably disjoint from every invariant closure carry no fuel
    metadata (SPEC §8). Initializer/entry/view are kind-disjoint from roots and
    `Op.PureCall` callees. When no invariant callable exists, every pureFn is
    also provably rootless and therefore outside all closures. Exact transitive
    pureFn membership, reachable call-graph DAG, and closure-CFG acyclicity are
    checked post-CFG; op restrictions and exact checked step computation follow
    those structural gates. -/
def validateNonClosureCallableInvariantStepsV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let hasInvariantRoot := callables.any (·.kind == .invariant)
  for callable in callables do
    match callable.kind with
    | .initializer | .entry | .view =>
        match callable.invariantSteps with
        | none => pure ()
        | some _ => return ← err .badCfg
    | .pureFn =>
        unless hasInvariantRoot do
          match callable.invariantSteps with
          | none => pure ()
          | some _ => return ← err .badCfg
    | .invariant => pure ()
  pure ()

/-- Every invariant root carries fuel metadata (SPEC §8). This bounded gate
    validates `some` presence only; exact pureFn membership, reachable
    call-graph DAG, closure-CFG acyclicity, op restrictions, and exact checked
    step computation are checked post-CFG. This presence
    gate runs after non-closure absence checks and before declaration join/CFG
    validation. -/
def validateInvariantRootStepsPresenceV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant then
      match callable.invariantSteps with
      | some _ => pure ()
      | none => return ← err .badCfg
  pure ()

/-- Stable non-serialized phases for the callable-signature segment. Several
    neighboring checks intentionally share the public `.badCfg` wire error;
    this seam makes their precedence observable to focused tests without
    changing serialized or CLI behavior. -/
inductive CallableSignatureValidationPhaseV1
  | kindName
  | callableName
  | parameterName
  | entryView
  | specialSignature
  deriving BEq, Repr

/-- Callable-signature phase plus the unchanged public wire error. -/
structure CallableSignatureValidationFailureV1 where
  phase : CallableSignatureValidationPhaseV1
  error : SemanticWireErrorV1
  deriving BEq, Repr

private def liftCallableSignatureValidationPhaseV1
    (phase : CallableSignatureValidationPhaseV1)
    (result : Except SemanticWireErrorV1 Unit) :
    Except CallableSignatureValidationFailureV1 Unit :=
  match result with
  | .ok () => .ok ()
  | .error wireError => .error { phase, error := wireError }

/-- Exact callable-signature phase sequence consumed by the production
    structure gate. The phase is never serialized; callers erase only it and
    retain the existing `SemanticWireErrorV1`. Invariant declaration join stays
    in its later post-signature position because it also depends on the
    dedicated invariant table. -/
def validateCallableSignaturePhasesV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) :
    Except CallableSignatureValidationFailureV1 Unit := do
  liftCallableSignatureValidationPhaseV1 .kindName
    (validateCallableKindNamePresenceV1 callables)
  liftCallableSignatureValidationPhaseV1 .callableName
    (validateCallableNameUniquenessV1 callables)
  liftCallableSignatureValidationPhaseV1 .parameterName
    (validateCallableParameterNameUniquenessV1 callables)
  liftCallableSignatureValidationPhaseV1 .entryView
    (validateCallableEntryViewPresenceV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInitializerCardinalityV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInitializerResultShapeV1 types callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantResultShapeV1 types callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantParameterShapeV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantLoopBoundsShapeV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateNonClosureCallableInvariantStepsV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantRootStepsPresenceV1 callables)

/-- Compose success of the sole production callable-signature sequence from
    the results of its production validation steps. -/
theorem validateCallableSignaturePhasesV1_eq_ok_of_phases
    (types : Array TypeDeclV1) (callables : Array CallableV1)
    (hKindName : validateCallableKindNamePresenceV1 callables = .ok ())
    (hCallableNames : validateCallableNameUniquenessV1 callables = .ok ())
    (hParameterNames : validateCallableParameterNameUniquenessV1 callables = .ok ())
    (hEntryView : validateCallableEntryViewPresenceV1 callables = .ok ())
    (hInitializerCount : validateInitializerCardinalityV1 callables = .ok ())
    (hInitializerResult : validateInitializerResultShapeV1 types callables = .ok ())
    (hInvariantResult : validateInvariantResultShapeV1 types callables = .ok ())
    (hInvariantParams : validateInvariantParameterShapeV1 callables = .ok ())
    (hInvariantLoops : validateInvariantLoopBoundsShapeV1 callables = .ok ())
    (hNonClosureSteps : validateNonClosureCallableInvariantStepsV1 callables = .ok ())
    (hRootSteps : validateInvariantRootStepsPresenceV1 callables = .ok ()) :
    validateCallableSignaturePhasesV1 types callables = .ok () := by
  simp only [validateCallableSignaturePhasesV1, hKindName, hCallableNames,
    hParameterNames, hEntryView, hInitializerCount, hInitializerResult,
    hInvariantResult, hInvariantParams, hInvariantLoops, hNonClosureSteps,
    hRootSteps, liftCallableSignatureValidationPhaseV1, Bind.bind, Except.bind]

/-- InvariantDecl rows correspond one-to-one with invariant callables in the
    latter's filtered source order (SPEC §6): exact callableId, invariant kind,
    and name. Table-id and callableId range checks run in earlier phases. -/
def validateInvariantDeclarationJoinV1 (callables : Array CallableV1)
    (invariants : Array InvariantDeclV1) : Except SemanticWireErrorV1 Unit := do
  let mut invariantCallableIds : Array CallableIdV1 := #[]
  for callable in callables do
    if callable.kind == .invariant then
      invariantCallableIds := invariantCallableIds.push callable.id
  unless invariants.size == invariantCallableIds.size do
    return ← err .badCfg
  let mut index : Nat := 0
  for invariant in invariants do
    match invariantCallableIds[index]? with
    | none => return ← err .badCfg
    | some expectedCallableId =>
        unless invariant.callableId == expectedCallableId do
          return ← err .badCfg
        match callables[expectedCallableId.toNat]? with
        | some callable =>
            match callable.kind, callable.name with
            | .invariant, some name =>
                unless invariant.name == name do
                  return ← err .badCfg
            | _, _ => return ← err .badCfg
        | none => return ← err .badCfg
    index := index + 1
  pure ()

end ProofForgeV2.Semantic.WireV1
