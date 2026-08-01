/-
  Noir Plan engineering canonical schema + digest (T9d / M5).

  Binds the same plan content fields as `canonicalPlanHash` under a dedicated
  engineering domain (does not re-use the plan.planHash hex string):

    planDigest = domainSeparatedSha256(
      "pf.noir-plan.engineering.v1",
      encodeEngineeringNoirPlanBytesV1(plan))

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Noir.LowerSemanticV1

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringNoirPlanDomainV1 : String :=
  "pf.noir-plan.engineering.v1"

/-- Content preimage (unsigned plan fields; excludes planHash). -/
def encodeEngineeringNoirPlanBytesV1 (plan : Plan) : Except String ByteArray :=
  pure (("pf.noir.plan.content.v1\u0000" ++
    targetDescriptorEngineeringReprV1 plan.targetDescriptor ++ "\u0000" ++
    reprStr plan.semanticSchemaVersion ++ "\u0000" ++
    reprStr plan.codegenProfile ++ "\u0000" ++
    reprStr plan.sourceDialect ++ "\u0000" ++
    reprStr plan.continuity ++ "\u0000" ++
    reprStr plan.failurePolicy ++ "\u0000" ++
    reprStr plan.proofStatus ++ "\u0000" ++
    reprStr plan.resourceLimits ++ "\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.relations).toUTF8)

def engineeringNoirPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringNoirPlanBytesV1 plan
  domainSeparatedSha256 engineeringNoirPlanDomainV1 bytes

end ProofForgeV2.Targets.Noir
