import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets

open ProofForgeV2

def maxRequirementKinds : Nat := 13

/-- JSON string escape shared by engineering OutputSet/evidence renderers
    (`renderEngineeringOutputSetManifestV1` / evidence companion). S7a deleted
    public `makeOutput` / `manifestJson` / `OutputSet` / `OutputManifest`
    product surfaces; on-disk bytes are owned by the engineering OutputSet
    renderer consumed by the CLI publisher. Not formal OutputSetV1. -/
def escapeJson (input : String) : String :=
  input.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"

end ProofForgeV2.Targets
