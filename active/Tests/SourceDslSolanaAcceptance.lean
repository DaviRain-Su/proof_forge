import Examples.Backend.Solana.Contracts.AccountRealloc
import Examples.Backend.Solana.Contracts.SystemCpi
import Examples.Backend.Solana.Contracts.Vault

namespace ProofForge.Tests.SourceDslSolanaAcceptance

open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def metadataValue? (intent : Intent) (key : String) : Option String :=
  intent.metadata.foldl
    (fun found item =>
      match found with
      | some _ => found
      | none => if item.key == key then some item.value else none)
    none

def hasIntent (spec : ContractSpec) (label : String)
    (source? : Option String := none) (entrypoint? : Option String := none) : Bool :=
  spec.intents.any fun intent =>
    intent.label == label &&
    (source?.isNone || intent.source? == source?) &&
    (entrypoint?.isNone ||
      metadataValue? intent "proof_forge.entrypoint" == entrypoint?)

def hasEntrypoint (spec : ContractSpec) (name : String) : Bool :=
  spec.module.entrypoints.any fun entrypoint => entrypoint.name == name

def main : IO UInt32 := do
  let vault := Examples.Backend.Solana.Contracts.Vault.spec
  require (vault.name == "SolanaVault")
    "Solana Vault source did not elaborate to the expected ContractSpec"
  require (hasIntent vault "solana.runtime.allocator" (some "runtime"))
    "allocator grammar did not preserve allocator intent"
  require (hasIntent vault "solana.account.declare" (some "vault_account"))
    "account grammar did not preserve vault_account intent"
  require (hasIntent vault "solana.account.pda" (some "vault"))
    "PDA declaration grammar did not preserve PDA intent"
  require (hasIntent vault "solana.pda.derive" (some "vault") (some "touch"))
    "derive PDA statement did not preserve entrypoint-scoped intent"
  require (hasIntent vault "solana.cpi.accounts" (some "token_transfer"))
    "CPI declaration grammar did not preserve token_transfer intent"
  require (hasIntent vault "solana.cpi.accounts" (some "token_transfer") (some "touch"))
    "invoke CPI statement did not preserve entrypoint-scoped intent"
  require (hasEntrypoint vault "touch")
    "Solana Vault source lost the touch entrypoint"

  let systemCpi := Examples.Backend.Solana.Contracts.SystemCpi.spec
  require (hasIntent systemCpi "solana.cpi.accounts" (some "lamport_transfer"))
    "system_transfer declaration did not preserve CPI intent"
  require (hasIntent systemCpi "solana.cpi.accounts" (some "lamport_transfer") (some "transfer"))
    "system_transfer invocation did not preserve entrypoint-scoped CPI intent"

  let realloc := Examples.Backend.Solana.Contracts.AccountRealloc.spec
  require (hasIntent realloc "solana.account.realloc" (some "realloc_buffer") (some "grow"))
    "realloc statement did not preserve entrypoint-scoped realloc intent"
  require (hasEntrypoint realloc "grow")
    "Solana realloc source lost the grow entrypoint"

  IO.println "source-dsl-solana-acceptance: ok (account + PDA + CPI + realloc IR intents)"
  return 0

end ProofForge.Tests.SourceDslSolanaAcceptance

def main : IO UInt32 :=
  ProofForge.Tests.SourceDslSolanaAcceptance.main
