/-
  Soroban Plan engineering canonical schema + digest (S0).

  Binds plan content fields under a dedicated engineering domain:

    planDigest = domainSeparatedSha256(
      "pf.soroban-plan.engineering.v1",
      encodeEngineeringSorobanPlanBytesV1(plan))

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Soroban.ValidatePlanV1

namespace ProofForgeV2.Targets.Soroban

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringSorobanPlanDomainV1 : String :=
  "pf.soroban-plan.engineering.v1"

def encodeEngineeringSorobanPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  match validatePlan plan with
  | .ok _ => pure ()
  | .error e => throw e.render
  pure (("pf.soroban.plan.content.v1\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.initializer ++ "\u0000" ++
    reprStr plan.entries ++ "\u0000" ++
    reprStr plan.views).toUTF8)

def engineeringSorobanPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringSorobanPlanBytesV1 plan
  domainSeparatedSha256 engineeringSorobanPlanDomainV1 bytes

end ProofForgeV2.Targets.Soroban
