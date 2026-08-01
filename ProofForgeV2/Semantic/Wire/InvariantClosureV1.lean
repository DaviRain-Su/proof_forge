import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CfgShapeV1
import ProofForgeV2.Semantic.Wire.CfgTypingV1
import Std.Data.HashMap

/-!
  ProofForgeV2.Semantic.Wire.InvariantClosureV1 — invariant root ops, pureFn
  closure membership, DAG, CFG acyclicity, exact computedInvariantSteps, 10M
  ceiling, ContextRead catalog, and validateCfgInvariantPhasesV1.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

private def validateInvariantRootDirectOpsV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant then
      for block in callable.blocks do
        for instr in block.instructions do
          match instr.op with
          | .stateStore _ _ => return ← err .badCfg
          | .contextRead _ => return ← err .badCfg
          | .commit _ => return ← err .badCfg
          | .emit _ _ _ => return ← err .badCfg
          | .externalCall _ _ _ => return ← err .badCfg
          | .schedule _ _ _ => return ← err .badCfg
          | _ => pure ()
  pure ()

/-- Compute exact transitive invariant-closure membership over `Op.PureCall`
    edges (SPEC §8). Generic CFG/op typing has already proved every edge is
    in-range and targets a pureFn; this helper rechecks those facts fail-closed.
    Each callable enters the worklist at most once, so traversal is bounded by
    callables plus PureCall instructions even when a cycle is present. The
    reachable call-graph DAG validator consumes this membership next. -/
private def computeInvariantClosureMembershipV1
    (callables : Array CallableV1) :
    Except SemanticWireErrorV1 (Array Bool) := do
  let mut members := Array.mk (List.replicate callables.size false)
  let mut worklist : Array Nat := #[]
  for index in [:callables.size] do
    match callables[index]? with
    | none => return ← err .badCfg
    | some callable =>
        if callable.kind == .invariant then
          members := members.set! index true
          worklist := worklist.push index
  let mut cursor : Nat := 0
  while cursor < worklist.size do
    let callerIndex := worklist[cursor]!
    cursor := cursor + 1
    match callables[callerIndex]? with
    | none => return ← err .badCfg
    | some caller =>
        for block in caller.blocks do
          for instr in block.instructions do
            match instr.op with
            | .pureCall calleeId _ =>
                let calleeIndex := calleeId.toNat
                match callables[calleeIndex]? with
                | none => return ← err .badCfg
                | some callee =>
                    unless callee.kind == .pureFn do
                      return ← err .badCfg
                    unless members[calleeIndex]! do
                      members := members.set! calleeIndex true
                      worklist := worklist.push calleeIndex
            | _ => pure ()
  pure members

/-- A pureFn carries invariant fuel metadata iff it is transitively reachable
    from an invariant root through `Op.PureCall` (SPEC §8). Presence is checked
    here after complete generic CFG/op validation; reachable call-graph DAG
    and closure-CFG acyclicity validation run next; op restrictions and exact
    checked step values follow in later post-CFG subphases. Other callable-kind
    presence rules remain in the earlier signature gates. -/
private def validatePureFnInvariantClosureMembershipWithMembersV1
    (callables : Array CallableV1) (members : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  for index in [:callables.size] do
    match callables[index]? with
    | none => return ← err .badCfg
    | some callable =>
        if callable.kind == .pureFn then
          let hasSteps := match callable.invariantSteps with
            | some _ => true
            | none => false
          unless hasSteps == members[index]! do
            return ← err .badCfg
  pure ()

/-- Reject cycles in the reachable invariant-closure `Op.PureCall` graph
    (SPEC §8). Kahn traversal is restricted to exact closure members, counts
    duplicate static edges independently, and processes each member once.
    Generic CFG/op typing and exact membership already ran; all edge facts are
    rechecked fail-closed. Unreachable pureFn cycles are outside this gate.
    Closure-CFG back edges and exact step computation run afterward. -/
private def validateInvariantClosureCallGraphDagWithMembersV1
    (callables : Array CallableV1) (members : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  let callableCount := callables.size
  let mut indegree := Array.mk (List.replicate callableCount 0)
  let mut adjacency : Array (Array Nat) :=
    Array.mk (List.replicate callableCount #[])
  let mut memberCount : Nat := 0
  for callerIndex in [:callableCount] do
    if members[callerIndex]! then
      memberCount := memberCount + 1
      match callables[callerIndex]? with
      | none => return ← err .badCfg
      | some caller =>
          for block in caller.blocks do
            for instr in block.instructions do
              match instr.op with
              | .pureCall calleeId _ =>
                  let calleeIndex := calleeId.toNat
                  match callables[calleeIndex]? with
                  | none => return ← err .badCfg
                  | some callee =>
                      unless callee.kind == .pureFn && members[calleeIndex]! do
                        return ← err .badCfg
                      adjacency := adjacency.set! callerIndex
                        (adjacency[callerIndex]!.push calleeIndex)
                      indegree := indegree.set! calleeIndex
                        (indegree[calleeIndex]! + 1)
              | _ => pure ()
  let mut ready : Array Nat := #[]
  for index in [:callableCount] do
    if members[index]! && indegree[index]! == 0 then
      ready := ready.push index
  let mut cursor : Nat := 0
  let mut processed : Nat := 0
  while cursor < ready.size do
    let callerIndex := ready[cursor]!
    cursor := cursor + 1
    processed := processed + 1
    for calleeIndex in adjacency[callerIndex]! do
      let count := indegree[calleeIndex]!
      if count == 0 then return ← err .badCfg
      let next := count - 1
      indegree := indegree.set! calleeIndex next
      if next == 0 then ready := ready.push calleeIndex
  unless processed == memberCount do return ← err .badCfg
  pure ()

/-- Every callable in an invariant closure must have an acyclic CFG (SPEC §8).
    Generic per-callable loopBounds validation has already established exact
    back-edge metadata; this post-membership gate rejects any actual back edge
    in a closure member while leaving unreachable pureFn bounded loops under
    the generic contract. Bounded by callables plus CFG successor edges. -/
private def validateInvariantClosureCfgAcyclicWithMembersV1
    (callables : Array CallableV1) (members : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  for index in [:callables.size] do
    if members[index]! then
      match callables[index]? with
      | none => return ← err .badCfg
      | some callable =>
          unless (cfgBackEdges callable.blocks callable.blocks.size).isEmpty do
            return ← err .badCfg
  pure ()

/-- A pureFn in an invariant closure cannot access logical state or context,
    create commitments, emit events, perform synchronous external calls, or
    schedule asynchronous workflows (SPEC §8). Generic CFG/op typing and
    closure graph/CFG acyclicity have
    already run. Invariant roots remain allowed to use StateLoad directly, and
    unreachable pureFns remain outside this closure-only restriction. -/
private def validateInvariantClosurePureFnOpsWithMembersV1
    (callables : Array CallableV1) (members : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  for index in [:callables.size] do
    if members[index]! then
      match callables[index]? with
      | none => return ← err .badCfg
      | some callable =>
          if callable.kind == .pureFn then
            for block in callable.blocks do
              for instr in block.instructions do
                match instr.op with
                | .stateLoad _ => return ← err .badCfg
                | .stateStore _ _ => return ← err .badCfg
                | .contextRead _ => return ← err .badCfg
                | .commit _ => return ← err .badCfg
                | .emit _ _ _ => return ← err .badCfg
                | .externalCall _ _ _ => return ← err .badCfg
                | .schedule _ _ _ => return ← err .badCfg
                | _ => pure ()
  pure ()

/-- Add one contribution to an invariant step total without wraparound. The
    schema-fixed 10M ceiling is stricter than UInt64 overflow, so rejecting as
    soon as this bound is crossed simultaneously enforces checked UInt64
    accumulation and the intrinsic limit (SPEC §8). -/
private def addInvariantStepsCheckedV1 (lhs rhs : UInt64) :
    Except SemanticWireErrorV1 UInt64 := do
  let total := lhs.toNat + rhs.toNat
  if maxInvariantStepsV1.toNat < total then return ← err .badCfg
  pure (UInt64.ofNat total)

/-- Compute and validate exact `computedInvariantSteps` for every callable in
    the already-validated invariant-closure DAG (SPEC §8). Local cost is
    `1 + sum(block.instructions.size + 1)`; every static PureCall occurrence
    adds its callee's full computed cost, including duplicate edges. A reverse
    adjacency Kahn pass starts at leaves, so each instruction edge and closure
    member is processed once. Generic CFG/op typing, exact closure membership,
    call-graph DAG, closure-CFG acyclicity, and op restrictions have already
    run; every fact is nevertheless rechecked fail-closed. -/
private def validateInvariantStepsExactWithMembersV1
    (callables : Array CallableV1) (members : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  let callableCount := callables.size
  let mut remainingCalls := Array.mk (List.replicate callableCount 0)
  let mut callersByCallee : Array (Array Nat) :=
    Array.mk (List.replicate callableCount #[])
  let mut totals := Array.mk (List.replicate callableCount (0 : UInt64))
  let mut memberCount : Nat := 0
  for callerIndex in [:callableCount] do
    if members[callerIndex]! then
      memberCount := memberCount + 1
      match callables[callerIndex]? with
      | none => return ← err .badCfg
      | some caller =>
          let mut intrinsicTotal : UInt64 := 1
          for block in caller.blocks do
            let next ← addInvariantStepsCheckedV1 intrinsicTotal
              (UInt64.ofNat (block.instructions.size + 1))
            intrinsicTotal := next
            for instr in block.instructions do
              match instr.op with
              | .pureCall calleeId _ =>
                  let calleeIndex := calleeId.toNat
                  match callables[calleeIndex]? with
                  | none => return ← err .badCfg
                  | some callee =>
                      unless callee.kind == .pureFn && members[calleeIndex]! do
                        return ← err .badCfg
                      remainingCalls := remainingCalls.set! callerIndex
                        (remainingCalls[callerIndex]! + 1)
                      callersByCallee := callersByCallee.set! calleeIndex
                        (callersByCallee[calleeIndex]!.push callerIndex)
              | _ => pure ()
          totals := totals.set! callerIndex intrinsicTotal
  let mut ready : Array Nat := #[]
  for index in [:callableCount] do
    if members[index]! && remainingCalls[index]! == 0 then
      ready := ready.push index
  let mut cursor : Nat := 0
  let mut processed : Nat := 0
  while cursor < ready.size do
    let calleeIndex := ready[cursor]!
    cursor := cursor + 1
    processed := processed + 1
    match callables[calleeIndex]? with
    | none => return ← err .badCfg
    | some callee =>
        match callee.invariantSteps with
        | none => return ← err .badCfg
        | some carried =>
            unless carried == totals[calleeIndex]! do return ← err .badCfg
    let calleeSteps := totals[calleeIndex]!
    for callerIndex in callersByCallee[calleeIndex]! do
      let nextTotal ← addInvariantStepsCheckedV1 totals[callerIndex]! calleeSteps
      totals := totals.set! callerIndex nextTotal
      let remaining := remainingCalls[callerIndex]!
      if remaining == 0 then return ← err .badCfg
      let nextRemaining := remaining - 1
      remainingCalls := remainingCalls.set! callerIndex nextRemaining
      if nextRemaining == 0 then ready := ready.push callerIndex
  unless processed == memberCount do return ← err .badCfg
  pure ()

/-- Every present invariant fuel value is bounded by the schema-fixed 10M
    intrinsic ceiling (SPEC §8). Exact checked computation for closure members
    has already run. This residual scan keeps the scalar metadata boundary
    explicit and runs before requirements. -/
private def validateInvariantStepsIntrinsicCeilingV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    match callable.invariantSteps with
    | none => pure ()
    | some steps =>
        unless steps ≤ maxInvariantStepsV1 do return ← err .badCfg
  pure ()

/-- Run invariant-closure validation in its exact production order and return
    the exact membership array shared by all membership-consuming subphases. -/
def validateInvariantClosurePhasesV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 (Array Bool) := do
  validateInvariantRootDirectOpsV1 callables
  let members ← computeInvariantClosureMembershipV1 callables
  validatePureFnInvariantClosureMembershipWithMembersV1 callables members
  validateInvariantClosureCallGraphDagWithMembersV1 callables members
  validateInvariantClosureCfgAcyclicWithMembersV1 callables members
  validateInvariantClosurePureFnOpsWithMembersV1 callables members
  pure members

/-- Production composition phase for exact carried invariant-step validation
    followed by the intrinsic metadata ceiling. `members` must be the exact
    result returned by `validateInvariantClosurePhasesV1`; the complete
    production validator and its composition theorem pin that identity. The
    size guard keeps direct proof-seam use total and fail-closed. -/
def validateInvariantFuelPhasesV1 (callables : Array CallableV1)
    (members : Array Bool) : Except SemanticWireErrorV1 Unit := do
  unless members.size == callables.size do return ← err .badCfg
  validateInvariantStepsExactWithMembersV1 callables members
  validateInvariantStepsIntrinsicCeilingV1 callables

/-- Shallow composition rule for the closure phase, retaining the exact
    membership value returned to the fuel phase. -/
theorem validateInvariantClosurePhasesV1_eq_ok
    (callables : Array CallableV1) (members : Array Bool)
    (hRoot : validateInvariantRootDirectOpsV1 callables = .ok ())
    (hMembers : computeInvariantClosureMembershipV1 callables = .ok members)
    (hMetadata : validatePureFnInvariantClosureMembershipWithMembersV1
      callables members = .ok ())
    (hDag : validateInvariantClosureCallGraphDagWithMembersV1
      callables members = .ok ())
    (hCfg : validateInvariantClosureCfgAcyclicWithMembersV1
      callables members = .ok ())
    (hOps : validateInvariantClosurePureFnOpsWithMembersV1
      callables members = .ok ()) :
    validateInvariantClosurePhasesV1 callables = .ok members := by
  simp only [validateInvariantClosurePhasesV1, hRoot, hMembers, hMetadata,
    hDag, hCfg, hOps, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Shallow composition rule for exact fuel validation over pinned closure
    membership. -/
theorem validateInvariantFuelPhasesV1_eq_ok
    (callables : Array CallableV1) (members : Array Bool)
    (hSize : members.size = callables.size)
    (hExact : validateInvariantStepsExactWithMembersV1 callables members = .ok ())
    (hCeiling : validateInvariantStepsIntrinsicCeilingV1 callables = .ok ()) :
    validateInvariantFuelPhasesV1 callables members = .ok () := by
  simp only [validateInvariantFuelPhasesV1, hSize, beq_self_eq_true, ↓reduceIte,
    hExact, hCeiling, Pure.pure, Except.pure, Bind.bind, Except.bind]

/- SPEC-SEM-WIRE-001 §5.1 engineering subset (structure-gate-only): within one
    `SemanticProgramV1`, every `Op.ContextRead` carrying the same exact
    `SchemaId` key MUST use the same `Instruction.result` TypeId. Different
    callables/branches declaring different result types for the same key are
    invalid Core and cannot be rescued by an Invocation or target adapter.

    This is a bounded deterministic global pass that runs after every
    callable's generic CFG/op typing succeeds and before invariant-closure/
    fuel/requirements. Generic CFG already guarantees result presence and
    def-site TypeId range; this pass still defends a missing result as
    `.badCfg`. It scans callables → blocks → instructions in source order and
    performs exact-key lookup/insert only (`key.value` string equality); it
    never iterates the host map. Expected time O(number of ContextRead
    occurrences), space O(distinct keys). The wire-owned v1 catalog admits
    closed keys: unix-time-seconds → anonymous UInt64, caller → anonymous
    Principal (N-2); exact requirement binding runs after generic requirement
    validation. Commit's disclosure contract remains deferred. -/
private def validateContextReadCatalogV1
    (types : Array TypeDeclV1) (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut seen : Std.HashMap String TypeIdV1 := {}
  for callable in callables do
    for block in callable.blocks do
      for instr in block.instructions do
        match instr.op with
        | .contextRead key =>
            match instr.result with
            | none => return ← err .badCfg
            | some rdef =>
                let shapeOk :=
                  if key == unixTimeSecondsContextKeyV1 then
                    match types[rdef.typeId.toNat]? with
                    | some { name := none, shape := .uint 64, .. } => true
                    | _ => false
                  else if key == callerContextKeyV1 then
                    match types[rdef.typeId.toNat]? with
                    | some { name := none, shape := .principal, .. } => true
                    | _ => false
                  else false
                unless shapeOk do return ← err .badCfg
                match seen.get? key.value with
                | none => seen := seen.insert key.value rdef.typeId
                | some prevT =>
                    unless prevT == rdef.typeId do
                      return ← err .badCfg
        | _ => pure ()
  pure ()

/-- Stable observable subphases for the CFG/invariant segment of structure
    validation. This is not serialized and does not change the public wire
    error contract; it lets tests distinguish precedence when multiple phases
    intentionally collapse to `.badCfg`. -/
inductive CfgInvariantValidationPhaseV1
  | cfg
  | invariantClosure
  | invariantFuel
  deriving BEq, Repr

/-- Internal phase plus the unchanged public wire error. The production
    structure validator consumes this exact result and erases only `phase`. -/
structure CfgInvariantValidationFailureV1 where
  phase : CfgInvariantValidationPhaseV1
  error : SemanticWireErrorV1
  deriving BEq, Repr

private def liftCfgInvariantValidationPhaseV1 {α : Type}
    (phase : CfgInvariantValidationPhaseV1)
    (result : Except SemanticWireErrorV1 α) :
    Except CfgInvariantValidationFailureV1 α :=
  match result with
  | .ok value => .ok value
  | .error error => .error { phase, error }

/-- The exact generic `.cfg` production phase: every callable's CFG/op
    validator in source order, followed by the global ContextRead catalog.
    Invariant closure and fuel remain later phases. -/
def validateGenericCfgPhasesV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  for callable in data.callables do
    validateCallableCfgShape callable data.types.size data.types data
  validateContextReadCatalogV1 data.types data.callables

/-- Compose the exact generic `.cfg` phase for a four-callable source-order
    table while preserving the production ContextRead catalog result. -/
theorem validateGenericCfgPhasesV1_four_eq_ok
    (data : SemanticProgramDataV1) (c0 c1 c2 c3 : CallableV1)
    (hCallables : data.callables = #[c0, c1, c2, c3])
    (h0 : validateCallableCfgShape c0 data.types.size data.types data = .ok ())
    (h1 : validateCallableCfgShape c1 data.types.size data.types data = .ok ())
    (h2 : validateCallableCfgShape c2 data.types.size data.types data = .ok ())
    (h3 : validateCallableCfgShape c3 data.types.size data.types data = .ok ())
    (hContext : validateContextReadCatalogV1 data.types data.callables = .ok ()) :
    validateGenericCfgPhasesV1 data = .ok () := by
  have hContext' :
      validateContextReadCatalogV1 data.types #[c0, c1, c2, c3] = .ok () := by
    rw [← hCallables]
    exact hContext
  simp [validateGenericCfgPhasesV1, hCallables, h0, h1, h2, h3, hContext',
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Runs the exact stable §6.2 segment used by the structure gate: every
    callable's generic CFG/op validation, then the global ContextRead
    same-key result-TypeId consistency pass (SPEC §5.1, `.cfg` phase), then
    invariant closure restrictions, then intrinsic invariant fuel. Earlier
    structure phases are prerequisites. -/
def validateCfgInvariantPhasesV1 (data : SemanticProgramDataV1) :
    Except CfgInvariantValidationFailureV1 Unit := do
  liftCfgInvariantValidationPhaseV1 .cfg
    (validateGenericCfgPhasesV1 data)
  let members ← liftCfgInvariantValidationPhaseV1 .invariantClosure
    (validateInvariantClosurePhasesV1 data.callables)
  liftCfgInvariantValidationPhaseV1 .invariantFuel
    (validateInvariantFuelPhasesV1 data.callables members)

/-- Shallow composition rule for the complete CFG/invariant segment, pinning
    the closure membership passed unchanged into invariant fuel validation. -/
theorem validateCfgInvariantPhasesV1_eq_ok
    (data : SemanticProgramDataV1) (members : Array Bool)
    (hCfg : validateGenericCfgPhasesV1 data = .ok ())
    (hClosure : validateInvariantClosurePhasesV1 data.callables = .ok members)
    (hFuel : validateInvariantFuelPhasesV1 data.callables members = .ok ()) :
    validateCfgInvariantPhasesV1 data = .ok () := by
  simp only [validateCfgInvariantPhasesV1, hCfg, hClosure, hFuel,
    liftCfgInvariantValidationPhaseV1, Bind.bind, Except.bind]

end ProofForgeV2.Semantic.WireV1
