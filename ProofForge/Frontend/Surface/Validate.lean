import ProofForge.Frontend.Surface.Syntax

/-! # Surface AST — Validation

Validates a `SurfaceContract` for duplicate names, unknown references,
and reserved namespace violations before normalization.
-/

namespace ProofForge.Frontend.Surface

/-- Validation error. -/
structure SurfaceError where
  message : String
  deriving Repr

/-- Check that names are unique within a declaration list. -/
def checkUniqueNames (names : Array String) (context : String) :
    Except SurfaceError Unit := do
  let mut seen : Std.HashSet String := {}
  for n in names do
    if seen.contains n then
      .error { message := s!"duplicate {context} name: {n}" }
    seen := seen.insert n

/-- Validate a Surface contract for duplicate names and basic well-formedness. -/
def validateSurface (contract : SurfaceContract) : Except SurfaceError Unit := do
  checkUniqueNames (contract.structs.map (·.name)) "struct"
  checkUniqueNames (contract.state.map (·.name)) "state"
  checkUniqueNames (contract.events.map (·.name)) "event"
  checkUniqueNames (contract.errors.map (·.name)) "error"
  checkUniqueNames (contract.entrypoints.map (·.name)) "entrypoint"
  /- Allow $surface.set. and $surface.queue. generated names; reject other $surface. prefixes. -/
  for s in contract.state do
    if s.name.startsWith "$surface." then
      unless s.name.startsWith "$surface.set." || s.name.startsWith "$surface.queue." do
        .error { message := s!"user state name starts with reserved prefix: {s.name}" }
  for ep in contract.entrypoints do
    if ep.name.startsWith "$surface." then
      .error { message := s!"user entrypoint name starts with reserved prefix: {ep.name}" }
  if contract.entrypoints.isEmpty then
    .error { message := "contract has no entrypoints" }

end ProofForge.Frontend.Surface