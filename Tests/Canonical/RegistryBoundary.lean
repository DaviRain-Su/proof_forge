import ProofForge.Target.Registry
import ProofForge.Cli.LegacyArgs

open ProofForge.Target
open ProofForge.Cli

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
  for arg in #[
      "--contract-source-evm-core-yul",
      "--contract-source-solana-core-sbpf",
      "--contract-source-wasm-core-wat"] do
    match parseArgs [arg, "Examples/Product/Counter.lean"] default with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError s!"internal pipeline flag leaked into CLI: {arg}"
  IO.println "canonical-registry-boundary: ok"
