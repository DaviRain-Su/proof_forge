import ProofForge.Frontend.Authored.Syntax

/-! # Authored AST — Validation

Validates a `AuthoredContract` for duplicate names, unknown references,
and reserved namespace violations before normalization.
-/

namespace ProofForge.Frontend.Authored

/-- Validation error. -/
structure AuthoredValidationError where
  message : String
  deriving Repr

/-- Check that names are unique within a declaration list. -/
def checkUniqueNames (names : Array String) (context : String) :
    Except AuthoredValidationError Unit := do
  let mut seen : Std.HashSet String := {}
  for n in names do
    if seen.contains n then
      .error { message := s!"duplicate {context} name: {n}" }
    seen := seen.insert n

/-- Validate an authored contract for duplicate names and basic well-formedness. -/
def validateAuthored (contract : AuthoredContract) : Except AuthoredValidationError Unit := do
  checkUniqueNames (contract.structs.map (·.name)) "struct"
  checkUniqueNames (contract.state.map (·.name)) "state"
  checkUniqueNames (contract.events.map (·.name)) "event"
  checkUniqueNames (contract.errors.map (·.name)) "error"
  checkUniqueNames (contract.entrypoints.map (·.name)) "entrypoint"
  for s in contract.state do
    match s.kind with
    | .mapN keyTypes _ _ =>
        if keyTypes.size < 2 then
          .error { message := s!"nested map {s.name} requires at least two key types" }
    | _ => pure ()
    if s.name.startsWith "$surface." then
      unless s.generated &&
          (s.name.startsWith "$surface.set." || s.name.startsWith "$surface.queue.") do
        .error { message := s!"user state name starts with reserved prefix: {s.name}" }
    else if s.generated then
      .error { message := s!"generated state name is outside the reserved namespace: {s.name}" }
  for ep in contract.entrypoints do
    if ep.name.startsWith "$surface." then
      .error { message := s!"user entrypoint name starts with reserved prefix: {ep.name}" }
  if contract.entrypoints.isEmpty then
    .error { message := "contract has no entrypoints" }

end ProofForge.Frontend.Authored
