import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets

open ProofForgeV2 Source

def maxRequirementKinds : Nat := 13

/-- Residual alpha requirement envelope shape (no duplicates / count bound).
    **Not** product support authority — does not consult
    `supportedRequirements` or mint capability. Used as a non-authority
    plan-body helper by private capability-gated `makePlanFromAlpha` only;
    it never mints capability and is not a public Semantic→Plan entry. -/
def validateRequirementEnvelope (program : SemanticProgram) : CompileResult Unit := do
  if program.requirements.size > maxRequirementKinds then
    throw <| .invalidProgram
      s!"semantic requirement count exceeds canonical limit {maxRequirementKinds}"
  let mut seen : Array ProgramRequirement := #[]
  for requirement in program.requirements do
    if seen.contains requirement then
      throw <| .invalidProgram s!"duplicate semantic requirement '{requirement}'"
    seen := seen.push requirement

/-- JSON string escape shared by CLI private legacy-engineering evidence /
    v2alpha1 on-disk renderer. S7a deleted public `makeOutput` / `manifestJson`
    / `OutputSet` / `OutputManifest` product surfaces; disk bytes are owned by
    the private CLI publisher. Formal OutputSetV1 still pending. -/
def escapeJson (input : String) : String :=
  input.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"

end ProofForgeV2.Targets
