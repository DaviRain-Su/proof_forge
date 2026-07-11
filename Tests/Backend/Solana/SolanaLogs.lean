import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Solana.Examples.LogEvent
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaLogs

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def hasCapability (plan : CapabilityPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun c => c == capability)

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

def scopedPubkeyLogCall? (plan : CapabilityPlan) (name entrypoint : String) :
    Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .eventsEmit &&
    metadataValue? call "solana.log.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def scopedDataLogCall? (plan : CapabilityPlan) (name entrypoint : String) :
    Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .eventsEmit &&
    metadataValue? call "solana.log.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"metadata `{key}` mismatch for operation `{call.operation}`"

def main : IO UInt32 := do
  let spec := ProofForge.Solana.Examples.LogEvent.spec
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana log event routing failed: {err.render}"

  require (hasCapability plan .eventsEmit)
    "Solana log event plan missing events.emit capability"
  require (hasCapability plan .storageScalar)
    "Solana log event plan missing storage.scalar capability"
  require (hasCapability plan .accountExplicit)
    "Solana pubkey log plan missing account.explicit capability"

  let pubkeyLogCall ←
    match scopedPubkeyLogCall? plan "log_state_account" "log_state_pubkey" with
    | some call => pure call
    | none => throw <| IO.userError "Solana log event plan missing log_state_account pubkey action"
  require (pubkeyLogCall.operation == .builtin "solana.log.pubkey")
    "log_state_account should lower through solana.log.pubkey"
  requireMetadata pubkeyLogCall "solana.extension" "log"
  requireMetadata pubkeyLogCall "solana.log.op" "pubkey"
  requireMetadata pubkeyLogCall "solana.log.account" "last_logged_amount"

  let dataLogCall ←
    match scopedDataLogCall? plan "log_amount_data" "log_state_data" with
    | some call => pure call
    | none => throw <| IO.userError "Solana log event plan missing log_amount_data data action"
  require (dataLogCall.operation == .builtin "solana.log.data")
    "log_amount_data should lower through solana.log.data"
  requireMetadata dataLogCall "solana.extension" "log"
  requireMetadata dataLogCall "solana.log.op" "data"
  requireMetadata dataLogCall "solana.log.source_state" "last_logged_amount"
  requireMetadata dataLogCall "solana.log.bytes" "8"

  match resolveSpec evm spec with
  | .ok _ =>
      throw <| IO.userError "EVM target should reject Solana log extension metadata"
  | .error err =>
      require (contains err.render "cannot use Solana target extension metadata")
        "EVM rejection should mention Solana target extension metadata"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-log-event" spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "log event package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "log event package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      let tag := ProofForge.Backend.Solana.SbpfAsm.stableEventTag "AmountEvent"
      require (contains manifest "name = \"emit\"")
        "log event manifest missing emit entrypoint"
      require (contains manifest "name = \"log_state_pubkey\"")
        "log event manifest missing log_state_pubkey entrypoint"
      require (contains manifest "name = \"log_state_data\"")
        "log event manifest missing log_state_data entrypoint"
      require (contains manifest "min_data_len = 9")
        "log event manifest missing parameter payload length"
      require (contains manifest "min_data_len = 1")
        "log event manifest missing pubkey log payload length"
      require (contains manifest "{ name = \"amount\", type = \"U64\", offset = 1, byte_size = 8, encoding = \"le-u64\" }")
        "log event manifest missing amount parameter schema"
      require (contains manifest "[[solana.entrypoint_log]]")
        "log event manifest missing entrypoint log action section"
      require (contains manifest "log = \"log_state_account\"")
        "log event manifest missing pubkey log action"
      require (contains manifest "op = \"pubkey\"")
        "log event manifest missing pubkey log op"
      require (contains manifest "account = \"last_logged_amount\"")
        "log event manifest missing pubkey log account"
      require (contains manifest "log = \"log_amount_data\"")
        "log event manifest missing data log action"
      require (contains manifest "op = \"data\"")
        "log event manifest missing data log op"
      require (contains manifest "source_state = \"last_logged_amount\"")
        "log event manifest missing data log source state"
      require (contains manifest "bytes = 8")
        "log event manifest missing data log byte length"
      require (contains asm "solana.event.emit AmountEvent: sol_log_64_ scalar fields")
        "assembly missing event emission marker"
      require (contains asm s!"solana.event.field AmountEvent.amount: tag={tag} index=0")
        "assembly missing event field marker"
      require (contains asm s!"mov64 r1, {tag}")
        "assembly missing event tag argument"
      require (contains asm "mov64 r2, 0")
        "assembly missing event field index argument"
      require (contains asm "mov64 r3, r2")
        "assembly missing event field value argument"
      require (contains asm "call sol_log_64_")
        "assembly missing sol_log_64_ syscall"
      require (contains asm "solana.log.pubkey_action log_state_account")
        "assembly missing pubkey log entrypoint action"
      require (contains asm "sol_log_pubkey_log_state_account:")
        "assembly missing pubkey log helper label"
      require (contains asm "solana.log.pubkey log_state_account: account=last_logged_amount")
        "assembly missing pubkey log helper marker"
      require (contains asm "solana.log.pubkey.ptr log_state_account account=last_logged_amount")
        "assembly missing pubkey log account pointer marker"
      require (contains asm "call sol_log_pubkey")
        "assembly missing sol_log_pubkey syscall"
      require (contains asm "solana.log.data_action log_amount_data")
        "assembly missing data log entrypoint action"
      require (contains asm "sol_log_data_log_amount_data:")
        "assembly missing data log helper label"
      require (contains asm "solana.log.data log_amount_data: source=last_logged_amount bytes=8")
        "assembly missing data log helper marker"
      require (contains asm "solana.log.data.ptr log_amount_data state=last_logged_amount")
        "assembly missing data log source pointer marker"
      require (contains asm "call sol_log_data")
        "assembly missing sol_log_data syscall"
  | .error err =>
      throw <| IO.userError s!"Solana log event package render failed: {err.render}"

  IO.println "solana-logs: ok"
  return 0

end ProofForge.Tests.SolanaLogs

def main : IO UInt32 :=
  ProofForge.Tests.SolanaLogs.main
