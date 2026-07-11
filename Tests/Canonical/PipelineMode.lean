import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Target.Registry

open ProofForge.Compiler
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  /- Both modes are callable from Lean. -/
  require (CompilerPipeline.legacy == .legacy) "legacy mode constructor"
  require (CompilerPipeline.canonical == .canonical) "canonical mode constructor"

  /- Target.knownIds contains neither `canonical` nor `-core`. -/
  for id in knownIds do
    require (!id.contains "canonical") s!"`canonical` leaked into knownIds: {id}"
    require (!id.endsWith "-core") s!"`-core` leaked into knownIds: {id}"

  /- The known IDs are exactly the public set. -/
  let expected := #["evm", "solana-sbpf-asm", "wasm-near", "wasm-cosmwasm",
    "wasm-cloudflare-workers", "wasm-stellar-soroban", "move-aptos", "move-sui",
    "psy-dpn", "aleo-leo"]
  require (knownIds == expected) s!"unexpected knownIds: {knownIds}"

  IO.println "pipeline-mode: ok"