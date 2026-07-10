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

  for id in #["move-aptos", "psy-dpn", "aleo-leo", "wasm-cloudflare-workers"] do
    let profile ← requireSome (find? id) s!"missing secondary target `{id}`"
    require (!profile.support.allowsInput .contractSource)
      s!"`{id}` must not advertise contract-source (fixture/research lane)"
    require profile.support.isFixtureOnly
      s!"`{id}` must be fixture-only in the support matrix"

  let aptos ← requireSome (find? "move-aptos") "missing move-aptos"
  require (aptos.support.maturity == .spike)
    "move-aptos must remain a spike until package/runtime validation is mandatory"
  require (!aptos.support.outputStages.contains .finalDeployable)
    "move-aptos fixture sourcegen must not advertise a final deployable artifact"
  require (aptos.support.validationLevel == .capability)
    "move-aptos check currently validates capability/sourcegen, not a built package"

  let aleo ← requireSome (find? "aleo-leo") "missing aleo-leo"
  require (aleo.support.maturity == .research)
    "aleo-leo must remain research while state-derived non-Unit returns fail closed"
  require (!aleo.support.outputStages.contains .finalDeployable)
    "aleo-leo sourcegen must not advertise final deployability"

  let cloudflare ← requireSome (find? "wasm-cloudflare-workers")
    "missing wasm-cloudflare-workers"
  require (cloudflare.artifactKind == .typescriptSource)
    "Cloudflare fixture emit produces TypeScript, not Wasm"
  require (cloudflare.support.maturity == .research)
    "Cloudflare Workers remains an off-chain research sourcegen lane"
  require (!cloudflare.support.outputStages.contains .finalDeployable)
    "Cloudflare TypeScript sourcegen is not a chain-deployable artifact"
  require (cloudflare.capabilities == #[.storageScalar])
    "Cloudflare fixture sourcegen must advertise only the implemented Counter storage-scalar fragment"
  for unsupported in #[.storageMap, .callerSender, .eventsEmit, .crosscallInvoke,
      .envBlock, .cryptoHash, .controlConditional, .controlBoundedLoop,
      .dataFixedArray, .dataStruct, .assertions] do
    require (!cloudflare.capabilities.contains unsupported)
      s!"Cloudflare sourcegen overclaims unsupported capability `{unsupported.id}`"

  let sui ← requireSome (find? "move-sui") "missing move-sui"
  require (sui.support.maturity == .counterMvp) "move-sui maturity is counter-mvp"
  require (!sui.support.allowsInput .contractSource) "move-sui Counter MVP is fixture lane"

  -- PF-P3-02: CosmWasm Counter MVP advertises contract_source (HostBridge.cosmWasm),
  -- same product surface class as Soroban EmitWat adapter (not fixture-only).
  let cosmwasm ← requireSome (find? "wasm-cosmwasm") "missing wasm-cosmwasm"
  require (cosmwasm.support.maturity == .counterMvp) "wasm-cosmwasm maturity is counter-mvp"
  require (cosmwasm.support.allowsInput .contractSource)
    "wasm-cosmwasm advertises contract_source (EmitWat host adapter)"
  require (cosmwasm.support.allowsCommand .build)
    "wasm-cosmwasm Counter MVP advertises build"
  require (!cosmwasm.support.isFixtureOnly)
    "wasm-cosmwasm is not fixture-only after PF-P3-02"

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
