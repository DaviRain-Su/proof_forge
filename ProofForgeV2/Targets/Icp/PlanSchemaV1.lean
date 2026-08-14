/-
  ICP Plan engineering canonical schema + digest.

  Binds plan content fields under a dedicated engineering domain:

    planDigest = domainSeparatedSha256(
      "pf.icp-plan.engineering.v1",
      encodeEngineeringIcpPlanBytesV1(plan))

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Icp.ValidatePlanV1

namespace ProofForgeV2.Targets.Icp

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringIcpPlanDomainV1 : String :=
  "pf.icp-plan.engineering.v1"

/-- Content preimage (deterministic `reprStr` fields; no semantic carrier).
    Validation runs before rendering so caller-constructed Plans cannot bypass
    the expression/resource or terminal-outcome canonicity gates. -/
def encodeEngineeringIcpPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  match validatePlan plan with
  | .ok _ => pure ()
  | .error e => throw e.render
  pure (("pf.icp.plan.content.v1\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.initializer ++ "\u0000" ++
    reprStr plan.entries ++ "\u0000" ++
    reprStr plan.views).toUTF8)

def engineeringIcpPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringIcpPlanBytesV1 plan
  domainSeparatedSha256 engineeringIcpPlanDomainV1 bytes

end ProofForgeV2.Targets.Icp
