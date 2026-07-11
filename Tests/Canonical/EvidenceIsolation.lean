import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Target.Plan
open ProofForge.IR.Core
open ProofForge.IR.Canonical

def sharedContractBase : CanonicalContract := {
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
    interface := {
      contractName := "EvidenceIsolation"
      entrypoints := #[{
        functionId := ⟨0⟩, name := "get", kind := .function,
        mutability := .view, params := #[], retType := .u64
      }]
    }
    materialization := {
      constructorParams := #[{ name := "initial", abiType := "uint64" }]
      constructorBindings := #[{
        stateId := ⟨0⟩, paramName := "initial", kind := .scalarU64
      }]
      stateSymbols := #[{ stateId := ⟨0⟩, name := "count" }]
    }
    requirements := #[]
}

def sharedContract : CanonicalContract := {
  sharedContractBase with
  requirements := deriveCapabilityRequirements
    sharedContractBase.module sharedContractBase.materialization
}

def evidenceA : CanonicalEvidence :=
  emptyEvidence
    |>.withSourceMap { entries := #[⟨⟨0⟩, some ⟨0⟩, some 0, ⟨"A.lean", 1, 1⟩⟩] }
    |>.withVerification {
      quintInvariants := #[{ name := "invA", body := "count >= 0" }]
    }
    |>.withIntentSources #[{ intentIndex := 0, source := "A.lean:1" }]
    |>.withLegacyClassification #[{
      nodeTag := "state"
      decision := "preserve"
      reason := "legacy A"
    }]

def evidenceB : CanonicalEvidence :=
  emptyEvidence
    |>.withSourceMap { entries := #[⟨⟨0⟩, some ⟨0⟩, some 0, ⟨"B.lean", 99, 42⟩⟩] }
    |>.withVerification {
      quintInvariants := #[{ name := "invB", body := "count <= max" }]
      quintLiveness := #[{ name := "liveB", body := "eventually count = 0" }]
    }
    |>.withIntentSources #[{ intentIndex := 0, source := "B.lean:99" }]
    |>.withLegacyClassification #[{
      nodeTag := "state"
      decision := "preserve"
      reason := "legacy B"
    }]

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  let checked ← match validateCanonical sharedContract with
    | .ok contract => pure contract
    | .error e => throw <| IO.userError s!"shared contract failed validation: {repr e}"
  let bundleA : CanonicalBundle := { contract := checked, evidence := evidenceA }
  let bundleB : CanonicalBundle := { contract := checked, evidence := evidenceB }
  require (bundleA.contract == bundleB.contract) "contract changed"
  require (capabilityRequirements bundleA == capabilityRequirements bundleB)
    "evidence changed capabilities"
  require (bundleA.evidence != bundleB.evidence) "evidence did not differ"
  /- Evidence changes must not affect the EVM ModulePlan. Both bundles
  share the same checked contract, so building the plan from either
  must produce the same storage layout size and entrypoint count. -/
  let capPlan : ProofForge.Target.CapabilityPlan :=
    { targetId := "evm", calls := #[], metadata := #[] }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
  | .ok plan =>
      require (plan.storage.states.size == 1) "evidence isolation: storage size changed"
      require (plan.entrypoints.size == 1) "evidence isolation: entrypoint count changed"
  | .error e =>
      throw <| IO.userError s!"evidence isolation: buildFromCore failed: {e.message}"
  IO.println "canonical-evidence-isolation: ok"
