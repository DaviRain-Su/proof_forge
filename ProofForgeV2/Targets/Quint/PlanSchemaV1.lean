/-
  Quint Plan engineering canonical schema + digest (Q0).

  Binds plan content fields under a dedicated engineering domain:

    planDigest = domainSeparatedSha256(
      "pf.quint-plan.engineering.v1",
      encodeEngineeringQuintPlanBytesV1(plan))

  **Engineering only — not formal Plan identity / OutputSetV1.**
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Quint.ValidatePlanV1

namespace ProofForgeV2.Targets.Quint

open ProofForgeV2
open ProofForgeV2.Core.Common

def engineeringQuintPlanDomainV1 : String :=
  "pf.quint-plan.engineering.v1"

/-- Content preimage (deterministic `reprStr` fields; no semantic carrier).
    Validation runs before rendering so caller-constructed Plans cannot bypass
    the expression/resource or terminal-outcome canonicity gates. -/
def encodeEngineeringQuintPlanBytesV1 (plan : Plan) : Except String ByteArray := do
  match validatePlan plan with
  | .ok _ => pure ()
  | .error e => throw e.render
  pure (("pf.quint.plan.content.v1\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.initializer ++ "\u0000" ++
    reprStr plan.entries ++ "\u0000" ++
    reprStr plan.views ++ "\u0000" ++
    reprStr plan.invariants ++ "\u0000" ++
    reprStr plan.usesVaultNative).toUTF8)

def engineeringQuintPlanDigestV1 (plan : Plan) : Except String Digest := do
  let bytes ← encodeEngineeringQuintPlanBytesV1 plan
  domainSeparatedSha256 engineeringQuintPlanDomainV1 bytes

end ProofForgeV2.Targets.Quint
