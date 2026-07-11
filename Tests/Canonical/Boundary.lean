import ProofForge.Target.Registry
open ProofForge.Target

/-- Lean-side boundary assertion: public target IDs do not include
pipeline-variant `*-core` entries. This complements
`scripts/canonical/check-boundary.sh` with a compile-time check. -/

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  require (!knownIds.any (·.endsWith "-core"))
    "pipeline target leaked into registry"
  require (knownIds.contains "evm") "evm target missing"
  require (knownIds.contains "solana-sbpf-asm") "solana-sbpf-asm target missing"
  require (knownIds.contains "wasm-near") "wasm-near target missing"
  IO.println "canonical-boundary: ok"