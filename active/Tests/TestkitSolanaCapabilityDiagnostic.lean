import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.TestkitSolanaCapabilityDiagnostic

open ProofForge.Target

/-- Portable crosscall is supported on Solana; empty peer fails via PortableHonesty. -/
def isExpectedCrosscallReject (msg : String) : Bool :=
  msg.contains "PortableHonesty" || msg.contains "empty peer" || msg.contains "peer"

def main : IO UInt32 := do
  match resolveModule solanaSbpfAsm ProofForge.IR.Examples.CrosscallProbe.module with
  | .ok _ =>
      IO.eprintln "testkit-solana-diagnostic: expected Solana to reject empty-peer crosscall"
      pure 1
  | .error err =>
      let actual := err.render
      if isExpectedCrosscallReject actual then
        IO.println "testkit-solana-diagnostic: ok: empty-peer crosscall rejected"
        IO.println s!"diagnostic: {actual}"
        pure 0
      else
        IO.eprintln "testkit-solana-diagnostic: unexpected diagnostic"
        IO.eprintln s!"actual: {actual}"
        pure 1

end ProofForge.Tests.TestkitSolanaCapabilityDiagnostic

def main : IO UInt32 :=
  ProofForge.Tests.TestkitSolanaCapabilityDiagnostic.main
