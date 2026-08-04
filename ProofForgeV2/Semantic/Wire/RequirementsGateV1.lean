import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CodecV1

/-!
  ProofForgeV2.Semantic.Wire.RequirementsGateV1 — program requirements
  structure/order and exact ContextRead/Commit requirement row binders.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

private def isKnownRequirementDomain (domain : String) : Bool :=
  domain == "value" || domain == "control" || domain == "state" ||
  domain == "effect" || domain == "context" || domain == "disclosure" ||
  domain == "authority" || domain == "state-custody" || domain == "failure" ||
  domain == "extension"

/-- Split a requirement id on ASCII `'.'` via `toList`/`List.splitOn` so the
    domain gate is kernel-reducible for closed catalog ids (proof certificates).
    Semantically matches `String.splitOn "."` for the S2 catalog surface. -/
private def requirementIdSegmentsV1 (id : String) : List String :=
  (id.toList.splitOn '.').map String.ofList

/-- Mechanical RequirementId domain gate (CAP first segment ∈ closed set).
    Requires at least two nonempty dotted segments; unknown domain →
    `.badRequirement`. Full segment grammar remains formal CAP work. -/
private def validateRequirementIdDomain (id : String) :
    Except SemanticWireErrorV1 Unit := do
  if id.isEmpty then
    return ← err .badRequirement
  let parts := requirementIdSegmentsV1 id
  unless parts.length ≥ 2 do
    return ← err .badRequirement
  for part in parts do
    if part.isEmpty then
      return ← err .badRequirement
  let domain := parts[0]!
  unless isKnownRequirementDomain domain do
    return ← err .badRequirement
  pure ()

private def predicateNameV1 : RequirementPredicateV1 → String
  | .uintAtLeast name _ | .uintAtMost name _ | .boolEquals name _
  | .enumContains name _ | .digestEquals name _ => name

private def predicateRankV1 : RequirementPredicateV1 → Nat
  | .uintAtLeast _ _ => 0
  | .uintAtMost _ _ => 1
  | .boolEquals _ _ => 2
  | .enumContains _ _ => 3
  | .digestEquals _ _ => 4

private def validateEnumContainsValues (values : Array String) :
    Except SemanticWireErrorV1 Unit := do
  if values.size = 0 then
    return ← err .badRequirement
  for i in [:values.size] do
    mapCommon (requireNfc values[i]!)
    if i > 0 then
      match compareByteArrayLex values[i - 1]!.toUTF8 values[i]!.toUTF8 with
      | .lt => pure ()
      | .eq | .gt => return ← err .badRequirement
  pure ()

private def validateRequirementPredicateStructure (p : RequirementPredicateV1) :
    Except SemanticWireErrorV1 Unit := do
  match p with
  | .enumContains _ values => validateEnumContainsValues values
  | _ => pure ()

private def comparePredicateOrder (left right : RequirementPredicateV1) :
    Except SemanticWireErrorV1 Ordering := do
  let nameCmp :=
    compareByteArrayLex (predicateNameV1 left).toUTF8 (predicateNameV1 right).toUTF8
  if nameCmp != .eq then
    return nameCmp
  let rL := predicateRankV1 left
  let rR := predicateRankV1 right
  if rL < rR then return .lt
  if rL > rR then return .gt
  let wireL ← encodeRequirementPredicateV1 left
  let wireR ← encodeRequirementPredicateV1 right
  pure (compareByteArrayLex wireL wireR)

private def validatePredicatesSorted (predicates : Array RequirementPredicateV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut prev? : Option RequirementPredicateV1 := none
  for p in predicates do
    validateRequirementPredicateStructure p
    match prev? with
    | none => pure ()
    | some prev =>
      let cmp ← comparePredicateOrder prev p
      match cmp with
      | .lt => pure ()
      | .eq | .gt => return ← err .badRequirement
    prev? := some p
  pure ()

private def compareRequirementKey (left right : RequirementRequestV1) :
    Except SemanticWireErrorV1 Ordering := do
  let idCmp := compareByteArrayLex left.id.toUTF8 right.id.toUTF8
  if idCmp != .eq then
    return idCmp
  let verL ← mapCommon (renderSemVer left.version)
  let verR ← mapCommon (renderSemVer right.version)
  let verCmp := compareByteArrayLex verL.toUTF8 verR.toUTF8
  if verCmp != .eq then
    return verCmp
  mapCommon (validateDigest left.digest)
  mapCommon (validateDigest right.digest)
  pure (compareByteArrayLex left.digest.bytes right.digest.bytes)

/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def validateProgramRequirementsStructure (reqs : ProgramRequirementsV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut prev? : Option RequirementRequestV1 := none
  for item in reqs.items do
    validateRequirementIdDomain item.id
    validatePredicatesSorted item.predicates
    match prev? with
    | none => pure ()
    | some prev =>
      let cmp ← compareRequirementKey prev item
      match cmp with
      | .lt => pure ()
      | .eq | .gt => return ← err .badRequirement
    prev? := some item
  pure ()

/-- Empty requirements table is accepted by the production structure gate. -/
theorem validateProgramRequirementsStructure_empty_eq_ok :
    validateProgramRequirementsStructure { items := #[] } = .ok () := rfl

private theorem requirementIdSegments_value_bool :
    requirementIdSegmentsV1 "value.bool" = ["value", "bool"] := by
  simp [requirementIdSegmentsV1]
  decide

private theorem validateRequirementIdDomain_value_bool :
    validateRequirementIdDomain "value.bool" = .ok () := by
  simp [validateRequirementIdDomain, requirementIdSegments_value_bool,
    isKnownRequirementDomain, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem validatePredicatesSorted_empty :
    validatePredicatesSorted #[] = .ok () := rfl

/-- A singleton row with closed id `value.bool` and empty predicates passes the
    production requirements structure gate (domain + empty predicate order;
    no peer-order comparison). Digest/version are ignored when alone. -/
theorem validateProgramRequirementsStructure_singleton_value_bool_eq_ok
    (version : SemVer) (digest : Digest) :
    validateProgramRequirementsStructure {
      items := #[{
        id := "value.bool"
        version := version
        digest := digest
        predicates := #[]
      }]
    } = .ok () := by
  simp only [validateProgramRequirementsStructure]
  have hDom := validateRequirementIdDomain_value_bool
  have hPred := validatePredicatesSorted_empty
  simp [hDom, hPred, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Apply `f` to every instruction in callables → blocks → instructions
    source order. Full scan; no early exit. -/
private def forEachInstruction {m : Type → Type} [Monad m]
    (data : SemanticProgramDataV1) (f : InstructionV1 → m Unit) : m Unit := do
  for callable in data.callables do
    for block in callable.blocks do
      for instr in block.instructions do
        f instr

/-- True if any instruction's op satisfies `used`. Full source-order scan
    (callables → blocks → instructions); no early exit. Bool-accumulating
    wrapper over `forEachInstruction`. -/
private def anyUsedOpV1 (data : SemanticProgramDataV1)
    (used : SemanticOpV1 → Bool) : Bool :=
  (StateT.run
    (forEachInstruction (m := StateM Bool) data fun instr => do
      if used instr.op then set true)
    false).2

/-- Bind a used op family to exactly one requirement row.
    Order is preserved exactly from the prior twin gates: scan ops first; if
    unused return early *before* matching `expectedRow`; then mint the row
    (`.error` → `.badRequirement`); then require a single exact id match in
    `data.requirements`. A malformed mint with unused ops therefore still
    returns early without observing the mint failure. -/
private def bindUsedOpToExactRequirementRow
    (data : SemanticProgramDataV1)
    (used : SemanticOpV1 → Bool)
    (expectedId : String)
    (expectedRow : Except String RequirementRequestV1) :
    Except SemanticWireErrorV1 Unit := do
  unless anyUsedOpV1 data used do return
  let expected ← match expectedRow with
    | .ok row => pure row
    | .error _ => return ← err .badRequirement
  let mut found := false
  for item in data.requirements.items do
    if item.id == expectedId then
      unless item == expected do return ← err .badRequirement
      if found then return ← err .badRequirement
      found := true
  unless found do return ← err .badRequirement

/-- Bind every used wire-owned ContextRead key to its exact requirement row.
    Closed v1 catalog: unix-time-seconds and caller (N-2). Generic requirement
    structure/order is validated first. -/
def validateContextReadRequirementsV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut usedUnix := false
  let mut usedCaller := false
  for callable in data.callables do
    for block in callable.blocks do
      for instr in block.instructions do
        match instr.op with
        | .contextRead key =>
            if key == unixTimeSecondsContextKeyV1 then usedUnix := true
            else if key == callerContextKeyV1 then usedCaller := true
            else pure ()
        | _ => pure ()
  if usedUnix then
    bindUsedOpToExactRequirementRow data
      (fun
        | .contextRead k => k == unixTimeSecondsContextKeyV1
        | _ => false)
      unixTimeSecondsContextRequirementIdV1
      unixTimeSecondsContextRequirementV1
  if usedCaller then
    bindUsedOpToExactRequirementRow data
      (fun
        | .contextRead k => k == callerContextKeyV1
        | _ => false)
      callerContextRequirementIdV1
      callerContextRequirementV1
  pure ()

/-- Bind every used Commit operation to the one exact disclosure.commitment
    requirement row. Generic requirement structure/order is validated first. -/
def validateCommitRequirementsV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit :=
  bindUsedOpToExactRequirementRow data
    (fun
      | .commit _ => true
      | _ => false)
    commitmentDisclosureRequirementIdV1
    commitmentDisclosureRequirementV1

end ProofForgeV2.Semantic.WireV1
