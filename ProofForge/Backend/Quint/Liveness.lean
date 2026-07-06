import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.InvExpr
import ProofForge.Backend.Quint.Scenario
import ProofForge.Backend.Quint.Invariants

namespace ProofForge.Backend.Quint.Liveness

open ProofForge.IR
open ProofForge.Backend.Quint

def isValidQuintIdentifier := Invariants.isValidQuintIdentifier

def scenarioLivenessEntries (scenario : Scenario.Config) : Array (String × String) :=
  scenario.contractLiveness ++ scenario.liveness

def deriveManual (_module : ProofForge.IR.Module) (scenario : Scenario.Config) (reservedNames : Array String)
    : Except String (Array Temporal) := do
  let mut temporals := #[]
  let mut seen := reservedNames
  for (name, exprStr) in scenarioLivenessEntries scenario do
    if seen.contains name then
      .error s!"duplicate liveness name `{name}` (already used by an invariant or liveness property)"
    if !isValidQuintIdentifier name then
      .error s!"liveness name `{name}` is not a valid Quint identifier"
    match InvExpr.parse exprStr with
    | .error e =>
        .error s!"liveness `{name}`: {e.message}"
    | .ok body =>
        seen := seen.push name
        temporals := temporals.push { name := name, body := body }
  .ok temporals

/-- Derive temporal (liveness) properties for a module. -/
def derive (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except String (Array Temporal) := do
  let autoVals ← Invariants.derive module scenario
  let reserved := Invariants.reservedNamesForModule module scenario ++ autoVals.map (fun v => v.name)
  deriveManual module scenario reserved

end ProofForge.Backend.Quint.Liveness