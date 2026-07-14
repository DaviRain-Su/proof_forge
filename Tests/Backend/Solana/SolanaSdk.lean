import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaSdk

open ProofForge.Target
open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def hasCapability (plan : CapabilityPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun c => c == capability)

def callByOperation? (plan : CapabilityPlan) (operation : String) : Option CapabilityCall :=
  plan.calls.find? (fun call => call.operation.render == operation)

def metadataValue? (call : CapabilityCall) (key : String) : Option String :=
  call.metadata.foldl
    (fun found metadata =>
      match found with
      | some _ => found
      | none =>
          if metadata.key == key then
            some metadata.value
          else
            none)
    none

def callByCpiName? (plan : CapabilityPlan) (name : String) : Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .crosscallCpi &&
    metadataValue? call "solana.cpi.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == none

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"metadata `{key}` mismatch for operation `{call.operation}`"

def scopedCall? (plan : CapabilityPlan) (operation entrypoint : String) : Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.operation.render == operation && metadataValue? call "proof_forge.entrypoint" == some entrypoint

def scopedCpiCall? (plan : CapabilityPlan) (name entrypoint : String) : Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .crosscallCpi &&
    metadataValue? call "solana.cpi.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def extensionSpec : ProofForge.Contract.ContractSpec :=
  build "SolanaVault" do
    pdaAccount "vault" #[literalSeed "vault", accountSeed "authority"]
      (bump? := some "vault_bump")
      (account? := some "vault_account")
      (isSigner := true)

    bumpAllocator

    systemTransfer
      "lamport_transfer"
      "payer"
      "recipient"
      "lamports"

    splTokenTransferChecked
      "token_transfer"
      "source"
      "mint"
      "destination"
      "authority"
      "amount"
      9
      (signerSeeds := #["vault", "vault_bump"])

    entry "touch" do
      derivePda "vault" #[literalSeed "vault", accountSeed "authority"]
        (bump? := some "vault_bump")
        (account? := some "vault_account")
        (isSigner := true)
      invokeSystemTransfer
        "lamport_transfer"
        "payer"
        "recipient"
        "lamports"
      invokeSplTokenTransferChecked
        "token_transfer"
        "source"
        "mint"
        "destination"
        "authority"
        "amount"
        9
        (signerSeeds := #["vault", "vault_bump"])

def requireSolanaPlan (plan : CapabilityPlan) : IO Unit := do
  require (plan.targetId == solanaSbpfAsm.id) "Solana SDK plan target id mismatch"
  require (hasCapability plan .accountExplicit) "Solana SDK plan missing account.explicit"
  require (hasCapability plan .storagePda) "Solana SDK plan missing storage.pda"
  require (hasCapability plan .runtimeAllocator) "Solana SDK plan missing runtime.allocator"
  require (hasCapability plan .crosscallCpi) "Solana SDK plan missing crosscall.cpi"

  let allocatorCall ←
    match callByOperation? plan "solana.runtime.allocator" with
    | some call => pure call
    | none => throw <| IO.userError "Solana SDK plan missing solana.runtime.allocator operation"
  requireMetadata allocatorCall "solana.extension" "allocator"
  requireMetadata allocatorCall "solana.allocator.name" "runtime"
  requireMetadata allocatorCall "solana.allocator.kind" "bump"
  requireMetadata allocatorCall "solana.allocator.heap_start" "0x300000000"
  requireMetadata allocatorCall "solana.allocator.heap_bytes" "32768"
  requireMetadata allocatorCall "solana.allocator.model" "downward-bump"

  let pdaCall ←
    match callByOperation? plan "solana.pda.derive" with
    | some call => pure call
    | none => throw <| IO.userError "Solana SDK plan missing solana.pda.derive operation"
  requireMetadata pdaCall "solana.extension" "pda"
  requireMetadata pdaCall "solana.pda.name" "vault"
  requireMetadata pdaCall "solana.pda.seeds" "vault,authority"
  requireMetadata pdaCall "solana.pda.seed_descriptors" "literal:vault,account:authority"
  requireMetadata pdaCall "solana.pda.bump" "vault_bump"
  requireMetadata pdaCall "solana.pda.account" "vault_account"
  requireMetadata pdaCall "solana.pda.signer" "true"

  let systemCpiCall ←
    match callByCpiName? plan "lamport_transfer" with
    | some call => pure call
    | none => throw <| IO.userError "Solana SDK plan missing lamport_transfer CPI"
  require (systemCpiCall.operation == .builtin "solana.cpi.invoke")
    "system transfer should use unsigned CPI operation"
  requireMetadata systemCpiCall "solana.extension" "cpi"
  requireMetadata systemCpiCall "solana.cpi.name" "lamport_transfer"
  requireMetadata systemCpiCall "solana.cpi.program" "system_program"
  requireMetadata systemCpiCall "solana.cpi.protocol" "system"
  requireMetadata systemCpiCall "solana.cpi.instruction" "transfer"
  requireMetadata systemCpiCall "solana.cpi.accounts" "payer:writable:signer,recipient:writable:none"
  requireMetadata systemCpiCall "solana.cpi.signer_seeds" ""
  requireMetadata systemCpiCall "solana.cpi.data_layout" "system.transfer"
  requireMetadata systemCpiCall "solana.cpi.lamports_source" "lamports"

  let cpiCall ←
    match callByCpiName? plan "token_transfer" with
    | some call => pure call
    | none => throw <| IO.userError "Solana SDK plan missing solana.cpi.invoke_signed operation"
  require (cpiCall.operation == .builtin "solana.cpi.invoke_signed")
    "SPL Token PDA transfer should use signed CPI operation"
  requireMetadata cpiCall "solana.extension" "cpi"
  requireMetadata cpiCall "solana.cpi.name" "token_transfer"
  requireMetadata cpiCall "solana.cpi.program" "spl_token"
  requireMetadata cpiCall "solana.cpi.protocol" "spl-token"
  requireMetadata cpiCall "solana.cpi.instruction" "transfer_checked"
  requireMetadata cpiCall "solana.cpi.accounts"
    "source:writable:none,mint:readonly:none,destination:writable:none,authority:readonly:pda-signer"
  requireMetadata cpiCall "solana.cpi.signer_seeds" "vault,vault_bump"
  requireMetadata cpiCall "solana.cpi.data_layout" "spl-token.transfer_checked"
  requireMetadata cpiCall "solana.cpi.amount_source" "amount"
  requireMetadata cpiCall "solana.cpi.decimals" "9"

  let pdaAction ←
    match scopedCall? plan "solana.pda.derive" "touch" with
    | some call => pure call
    | none => throw <| IO.userError "Solana SDK plan missing touch-scoped PDA action"
  requireMetadata pdaAction "solana.pda.name" "vault"
  requireMetadata pdaAction "proof_forge.entrypoint" "touch"

  let systemCpiAction ←
    match scopedCpiCall? plan "lamport_transfer" "touch" with
    | some call => pure call
    | none => throw <| IO.userError "Solana SDK plan missing touch-scoped System CPI action"
  requireMetadata systemCpiAction "solana.cpi.name" "lamport_transfer"
  requireMetadata systemCpiAction "proof_forge.entrypoint" "touch"

  let cpiAction ←
    match scopedCpiCall? plan "token_transfer" "touch" with
    | some call => pure call
    | none => throw <| IO.userError "Solana SDK plan missing touch-scoped CPI action"
  requireMetadata cpiAction "solana.cpi.name" "token_transfer"
  requireMetadata cpiAction "proof_forge.entrypoint" "touch"

def main : IO UInt32 := do
  let plan ←
    match resolveSpec solanaSbpfAsm extensionSpec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana SDK routing failed: {err.render}"
  requireSolanaPlan plan

  match resolveSpec evm extensionSpec with
  | .ok _ => throw <| IO.userError "EVM unexpectedly accepted Solana PDA/CPI extension"
  | .error err =>
      require (err.render == "target `evm` cannot use Solana target extension metadata on operation `solana.account.pda`")
        s!"unexpected EVM diagnostic: {err.render}"

  IO.println "solana-sdk: ok"
  return 0

end ProofForge.Tests.SolanaSdk

def main : IO UInt32 :=
  ProofForge.Tests.SolanaSdk.main
