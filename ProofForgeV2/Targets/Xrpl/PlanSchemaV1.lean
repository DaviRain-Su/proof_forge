/-
  XRPL Plan engineering canonical schema + digest (Q0).

  Binds plan content fields under a dedicated engineering domain:

    planDigest = domainSeparatedSha256(
      "pf.xrpl-plan.engineering.v1",
      encodeEngineeringXrplPlanBytesV1(plan))

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Xrpl.ValidatePlanV1

namespace ProofForgeV2.Targets.Xrpl

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringXrplPlanDomainV1 : String :=
  "pf.xrpl-plan.engineering.v1"

def encodeEngineeringXrplPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  match validatePlan plan with
  | .ok _ => pure ()
  | .error e => throw e.render
  pure (("pf.xrpl.plan.content.v1\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.signedNumeric ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.initializer ++ "\u0000" ++
    reprStr plan.entries ++ "\u0000" ++
    reprStr plan.views).toUTF8)

def engineeringXrplPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringXrplPlanBytesV1 plan
  domainSeparatedSha256 engineeringXrplPlanDomainV1 bytes

end ProofForgeV2.Targets.Xrpl
