import ProofForge.Target
import ProofForge.Target.Support
import ProofForge.Cli.TargetJson

namespace ProofForge.Tests.TargetSupport

open ProofForge.Target
open ProofForge.Cli

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireSome {α : Type} (value : Option α) (message : String) : IO α :=
  match value with
  | some x => pure x
  | none => throw <| IO.userError message

/-- PF-P1-02: registry distinguishes primary source builds, fixture-only spikes,
and research sourcegen without prose exceptions. -/
def main : IO UInt32 := do
  for id in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let profile ← requireSome (find? id) s!"missing primary target `{id}`"
    require profile.support.isPrimarySource
      s!"`{id}` must be primary source (experimental + contract-source)"
    require (profile.support.allowsCommand .build)
      s!"`{id}` must advertise build"
    require (profile.support.allowsCommand .check)
      s!"`{id}` must advertise check"
    require (profile.support.validationLevel == .package)
      s!"`{id}` validationLevel must be package"
    require (profile.support.outputStages.contains .finalDeployable)
      s!"`{id}` must advertise final-deployable output"

  for id in #["wasm-cosmwasm", "move-aptos", "psy-dpn", "aleo-leo", "wasm-cloudflare-workers"] do
    let profile ← requireSome (find? id) s!"missing secondary target `{id}`"
    require (!profile.support.allowsInput .contractSource)
      s!"`{id}` must not advertise contract-source (fixture/research lane)"
    require profile.support.isFixtureOnly
      s!"`{id}` must be fixture-only in the support matrix"

  let sui ← requireSome (find? "move-sui") "missing move-sui"
  require (sui.support.maturity == .counterMvp) "move-sui maturity is counter-mvp"
  require (!sui.support.allowsInput .contractSource) "move-sui Counter MVP is fixture lane"

  let soroban ← requireSome (find? "wasm-stellar-soroban") "missing soroban"
  require (soroban.support.allowsInput .contractSource)
    "soroban advertises contract_source (EmitWat host adapter)"
  require (!soroban.support.allowsCommand .emit)
    "soroban emit fixture path is not the product surface yet"

  -- JSON matrix is non-empty and includes every known id.
  let json := listTargetsJson
  require (json.contains "proof-forge-target-support-matrix")
    "listTargetsJson must declare schema kind"
  for id in knownIds do
    require (json.contains s!"\"id\": \"{id}\"" || json.contains s!"\"id\":\"{id}\"")
      s!"listTargetsJson missing target id `{id}`"
  require (json.contains "\"maturity\"") "listTargetsJson must include maturity"
  require (json.contains "\"inputModes\"") "listTargetsJson must include inputModes"
  require (json.contains "\"commands\"") "listTargetsJson must include commands"
  require (json.contains "\"validationLevel\"") "listTargetsJson must include validationLevel"

  IO.println "TargetSupport matrix OK"
  return 0

end ProofForge.Tests.TargetSupport

def main : IO UInt32 :=
  ProofForge.Tests.TargetSupport.main
