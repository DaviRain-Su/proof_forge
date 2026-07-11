import ProofForge.IR.Core
import ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Canonical

def sharedContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := {
      name := "EvidenceIsolation"
      structs := #[]
      state := #[⟨⟨0⟩, .scalar .u64⟩]
      events := #[]
      functions := #[{
        id := ⟨0⟩
        params := #[]
        retType := .u64
        entry := ⟨0⟩
        blocks := #[{
          id := ⟨0⟩
          params := #[]
          instructions := #[
            ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 42))⟩
          ]
          terminator := .return #[{ id := ⟨1⟩, type := .u64 }]
        }]
      }]
    }
    interface := { entrypoints := #[⟨⟨0⟩, "view", false⟩] }
    materialization := { constructorBindings := #[⟨⟨0⟩, .u64Lit 0⟩] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"shared contract failed validation: {repr e}"

def evidenceA : CanonicalEvidence :=
  emptyEvidence
    |>.withSourceMap { entries := #[⟨⟨0⟩, some ⟨0⟩, some 0, ⟨"A.lean", 1, 1⟩⟩] }
    |>.withVerification { invariants := #["invA"], liveness := #[] }
    |>.withLegacyClassification #[{
      nodeTag := "state"
      decision := "preserve"
      reason := "legacy A"
    }]

def evidenceB : CanonicalEvidence :=
  emptyEvidence
    |>.withSourceMap { entries := #[⟨⟨0⟩, some ⟨0⟩, some 0, ⟨"B.lean", 99, 42⟩⟩] }
    |>.withVerification { invariants := #["invB"], liveness := #["liveB"] }
    |>.withLegacyClassification #[{
      nodeTag := "state"
      decision := "preserve"
      reason := "legacy B"
    }]

def bundleA : CanonicalBundle := { contract := sharedContract, evidence := evidenceA }
def bundleB : CanonicalBundle := { contract := sharedContract, evidence := evidenceB }

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  require (bundleA.contract == bundleB.contract) "contract changed"
  require (capabilityRequirements bundleA == capabilityRequirements bundleB)
    "evidence changed capabilities"
  require (bundleA.evidence != bundleB.evidence) "evidence did not differ"
  IO.println "canonical-evidence-isolation: ok"
