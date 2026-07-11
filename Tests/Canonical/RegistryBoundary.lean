import ProofForge.Target.Registry

open ProofForge.Target

def expectedIds : Array String := #[
  "evm",
  "solana-sbpf-asm",
  "wasm-near",
  "wasm-cosmwasm",
  "wasm-cloudflare-workers",
  "wasm-stellar-soroban",
  "move-aptos",
  "move-sui",
  "psy-dpn",
  "aleo-leo"
]

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  require (knownIds == expectedIds) s!"unexpected public targets: {knownIds}"
  require (!knownIds.any (·.endsWith "-core")) "pipeline target leaked into registry"
  IO.println "canonical-registry-boundary: ok"
