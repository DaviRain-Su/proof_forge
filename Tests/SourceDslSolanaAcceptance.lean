import Examples.Backend.Solana.Contracts.SystemCpi
import Examples.Backend.Solana.Contracts.Vault
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Frontend.Authored
import ProofForge.Target.Registry

namespace ProofForge.Tests.SourceDslSolanaAcceptance

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def buildPlan (contract : AuthoredContract) : IO ProofForge.Backend.Solana.Plan.SolanaModulePlan := do
  let bundle <- match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"direct Solana source normalization failed: {repr error}"
  let capabilityPlan : CapabilityPlan := {
    targetId := solanaSbpfAsm.id
    calls := bundle.contract.contract.requirements
  }
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract capabilityPlan with
  | .ok plan => pure plan
  | .error error => throw <| IO.userError s!"direct Solana source planning failed: {error.message}"

def main : IO UInt32 := do
  let vaultContract := Examples.Backend.Solana.Contracts.Vault.contract
  require (vaultContract.name == "SolanaVault")
    "Solana Vault source did not elaborate to the direct Authored contract"
  require (vaultContract.entrypoints.any (fun entrypoint => entrypoint.name == "touch"))
    "Solana Vault source lost the touch entrypoint"
  let vault <- buildPlan vaultContract
  let extensions := vault.lowerCtxSeed.extensions
  require (extensions.accounts.any fun account =>
      account.name == "vault_account" && account.access == "writable")
    "account grammar did not reach the typed Solana account plan"
  require (extensions.pdas.any fun pda =>
      pda.name == "vault" && pda.seeds == #["literal:vault", "account:authority"])
    "PDA grammar did not reach the typed Solana PDA plan"
  require (extensions.pdaActions.any fun action =>
      action.name == "vault" && action.entrypoint == "touch")
    "derive PDA statement lost its direct Authored entrypoint scope"
  require (extensions.cpis.any fun cpi =>
      cpi.name == "token_transfer" && cpi.dataLayout? == some "spl-token.transfer_checked")
    "CPI grammar did not reach the typed Solana CPI plan"
  require (extensions.cpiActions.any fun action =>
      action.name == "token_transfer" && action.entrypoint == "touch")
    "invoke CPI statement lost its direct Authored entrypoint scope"

  let systemCpi <- buildPlan Examples.Backend.Solana.Contracts.SystemCpi.contract
  require (systemCpi.lowerCtxSeed.extensions.cpis.any fun cpi =>
      cpi.name == "lamport_transfer" && cpi.dataLayout? == some "system.transfer")
    "system_transfer declaration did not reach the typed Solana CPI plan"
  require (systemCpi.lowerCtxSeed.extensions.cpiActions.any fun action =>
      action.name == "lamport_transfer" && action.entrypoint == "transfer")
    "system_transfer invocation lost its direct Authored entrypoint scope"

  IO.println "source-dsl-solana-acceptance: ok (direct Authored -> Canonical -> Solana plan)"
  return 0

end ProofForge.Tests.SourceDslSolanaAcceptance

def main : IO UInt32 :=
  ProofForge.Tests.SourceDslSolanaAcceptance.main
