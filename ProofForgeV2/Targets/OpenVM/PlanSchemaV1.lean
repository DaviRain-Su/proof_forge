/-
  OpenVM Plan engineering canonical schema + digest (O0).

  Binds plan content fields under a dedicated engineering domain:

    planDigest = domainSeparatedSha256(
      "pf.openvm-plan.engineering.v1",
      encodeEngineeringOpenVmPlanBytesV1(plan))

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.OpenVM.ValidatePlanV1

namespace ProofForgeV2.Targets.OpenVM

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringOpenVmPlanDomainV1 : String :=
  "pf.openvm-plan.engineering.v1"

/-- Content preimage (deterministic `reprStr` fields; no semantic carrier).
    Validation runs before rendering so caller-constructed Plans cannot bypass
    the expression/resource or terminal-outcome canonicity gates. -/
def encodeEngineeringOpenVmPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  match validatePlan plan with
  | .ok _ => pure ()
  | .error e => throw e.render
  pure (("pf.openvm.plan.content.v1\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.signedNumeric ++ "\u0000" ++
    reprStr plan.profile ++ "\u0000" ++
    reprStr plan.vmConfig ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.initializer ++ "\u0000" ++
    reprStr plan.entries ++ "\u0000" ++
    reprStr plan.views).toUTF8)

def engineeringOpenVmPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringOpenVmPlanBytesV1 plan
  domainSeparatedSha256 engineeringOpenVmPlanDomainV1 bytes

end ProofForgeV2.Targets.OpenVM
