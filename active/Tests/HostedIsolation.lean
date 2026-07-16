import ProofForge.Cli.ContractLoader

/-! ## PF-P3-03 hosted isolation honesty

Pins the fail-closed gate: hosted isolation requests must be recognized, and
the refusal message must stay stable for smoke scripts.
-/

namespace ProofForge.Tests.HostedIsolation

open ProofForge.Cli.ContractLoader

theorem hosted_isolation_truthy :
    isHostedIsolationRequested "1" = true ∧
      isHostedIsolationRequested "true" = true ∧
      isHostedIsolationRequested "YES" = true ∧
      isHostedIsolationRequested "on" = true := by
  native_decide

theorem hosted_isolation_falsy :
    isHostedIsolationRequested "" = false ∧
      isHostedIsolationRequested "0" = false ∧
      isHostedIsolationRequested "false" = false ∧
      isHostedIsolationRequested "no" = false := by
  native_decide

theorem hosted_isolation_message_mentions_p3_03 :
    (hostedIsolationRefusedMessage.splitOn "PF-P3-03").length ≥ 2 ∧
      (hostedIsolationRefusedMessage.splitOn "hosted isolation is not ready").length ≥ 2 := by
  native_decide

end ProofForge.Tests.HostedIsolation

def main : IO UInt32 := do
  IO.println "hosted-isolation: truthy/falsy gate + refusal message pins ok"
  return 0
