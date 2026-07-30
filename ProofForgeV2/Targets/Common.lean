import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets

open ProofForgeV2

def maxRequirementKinds : Nat := 13

/-- JSON string escape shared by CLI private legacy-engineering evidence /
    v2alpha1 on-disk renderer. S7a deleted public `makeOutput` / `manifestJson`
    / `OutputSet` / `OutputManifest` product surfaces; disk bytes are owned by
    the private CLI publisher. Formal OutputSetV1 still pending. -/
def escapeJson (input : String) : String :=
  input.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"

end ProofForgeV2.Targets
