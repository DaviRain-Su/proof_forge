import ProofForge.Target.Registry
import ProofForge.Cli.LegacyArgs
import ProofForge.Cli.TargetDriver

open ProofForge.Target
open ProofForge.Cli

def expectedIds : Array String := #[
  "evm",
  "solana-sbpf-asm",
  "wasm-near",
  "wasm-cosmwasm",
  "wasm-stellar-soroban",
  "wasm-arbitrum-stylus",
  "psy-dpn",
  "aleo-leo"
]

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  require (knownIds == expectedIds) s!"unexpected public targets: {knownIds}"
  require (!knownIds.any (·.endsWith "-core")) "pipeline target leaked into registry"
  let driverIds := cliDrivers.map (·.id)
  require (driverIds.size == knownIds.size + 1)
    s!"CLI drivers must be exactly public targets plus quint: {driverIds}"
  require (knownIds.all driverIds.contains)
    s!"public target is missing its CLI driver: {driverIds}"
  require (driverIds.contains "quint") "CLI-only quint driver is missing"
  require (driverIds.all fun id => id == "quint" || knownIds.contains id)
    s!"unexpected CLI-only driver: {driverIds}"
  for id in #["evm-core", "solana-sbpf-asm-core", "wasm-near-core"] do
    require ((findCliDriver? id).isNone) s!"internal pipeline target leaked into CLI drivers: {id}"
  for arg in #[
      "--contract-source-evm-core-yul",
      "--contract-source-solana-core-sbpf",
      "--contract-source-wasm-core-wat"] do
    match parseArgs [arg, "Examples/Product/Counter.lean"] default with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError s!"internal pipeline flag leaked into CLI: {arg}"
  IO.println "canonical-registry-boundary: ok"
