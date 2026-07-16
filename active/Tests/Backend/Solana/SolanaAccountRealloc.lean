import ProofForge.Backend.Solana.Package
import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy
import Examples.Backend.Solana.Contracts.AccountRealloc
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaAccountRealloc

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

def scopedReallocCall? (plan : CapabilityPlan) (name entrypoint : String) :
    Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .accountExplicit &&
    metadataValue? call "solana.account_realloc.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"metadata `{key}` mismatch for operation `{call.operation}`"

def builderSpec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Builder.build "SolanaAccountReallocBuilder" do
    ProofForge.Contract.Builder.scalarState "counter" .u64
    ProofForge.Contract.Builder.entry "grow" do
      ProofForge.Contract.Source.Solana.Legacy.reallocAccount "grow_counter" "counter" 64
      ProofForge.Contract.Builder.effect
        (ProofForge.Contract.Builder.storageScalarWrite "counter"
          (ProofForge.Contract.Builder.u64 1))

def checkPackage (label : String) (spec : ProofForge.Contract.ContractSpec)
    (reallocName accountName entrypointName : String) (newSize : Nat) : IO Unit := do
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"{label} routing failed: {err.render}"

  require (hasCapability plan .accountExplicit)
    s!"{label} plan missing account.explicit capability"

  let reallocCall ←
    match scopedReallocCall? plan reallocName entrypointName with
    | some call => pure call
    | none => throw <| IO.userError s!"{label} plan missing realloc action `{reallocName}`"
  require (reallocCall.operation == .builtin "solana.account.realloc")
    s!"{label} realloc action should use solana.account.realloc"
  requireMetadata reallocCall "solana.extension" "account_realloc"
  requireMetadata reallocCall "solana.account_realloc.account" accountName
  requireMetadata reallocCall "solana.account_realloc.new_size" (toString newSize)

  match resolveSpec evm spec with
  | .ok _ => throw <| IO.userError s!"EVM unexpectedly accepted {label} Solana realloc metadata"
  | .error err =>
      require (contains err.render "cannot use Solana target extension metadata")
        s!"unexpected EVM diagnostic for {label}: {err.render}"

  let pkg ←
    match ProofForge.Backend.Solana.Package.renderPackageForSpec label spec with
    | .ok pkg => pure pkg
    | .error err => throw <| IO.userError s!"{label} package render failed: {err.render}"

  let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
    | throw <| IO.userError s!"{label} package missing manifest.toml"
  let some idlFile := pkg.files.find? (fun file => file.path == pkg.idlPath)
    | throw <| IO.userError s!"{label} package missing IDL"
  let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
    | throw <| IO.userError s!"{label} package missing assembly"

  require (contains manifestFile.contents "[[solana.entrypoint_realloc]]")
    s!"{label} manifest missing realloc action section"
  require (contains manifestFile.contents s!"entrypoint = \"{entrypointName}\"")
    s!"{label} manifest missing realloc entrypoint"
  require (contains manifestFile.contents s!"realloc = \"{reallocName}\"")
    s!"{label} manifest missing realloc action name"
  require (contains manifestFile.contents s!"account = \"{accountName}\"")
    s!"{label} manifest missing realloc account"
  require (contains manifestFile.contents s!"new_size = {newSize}")
    s!"{label} manifest missing realloc new size"
  require (contains manifestFile.contents "max_permitted_data_increase = 10240")
    s!"{label} manifest missing realloc max-increase"

  require (contains idlFile.contents "\"accountReallocs\"")
    s!"{label} IDL missing accountReallocs actions"
  require (contains idlFile.contents s!"\"realloc\": \"{reallocName}\"")
    s!"{label} IDL missing realloc action name"
  require (contains idlFile.contents s!"\"account\": \"{accountName}\"")
    s!"{label} IDL missing realloc account"
  require (contains idlFile.contents s!"\"newSize\": {newSize}")
    s!"{label} IDL missing realloc new size"
  require (contains idlFile.contents "\"maxPermittedDataIncrease\": 10240")
    s!"{label} IDL missing realloc max-increase"

  require (contains asmFile.contents s!"account.validation[")
    s!"{label} assembly missing account validation prologue"
  require (contains asmFile.contents s!"account={accountName} new_size={newSize} max_increase=10240")
    s!"{label} assembly missing realloc helper metadata"
  require (contains asmFile.contents s!"sol_account_realloc_{reallocName}")
    s!"{label} assembly missing realloc helper label"
  require (contains asmFile.contents "error_realloc")
    s!"{label} assembly missing realloc error path"
  require (contains asmFile.contents "stxdw [r7+0], r2")
    s!"{label} assembly missing data_len store"

def main : IO UInt32 := do
  checkPackage "solana-account-realloc-builder" builderSpec "grow_counter" "counter" "grow" 64
  checkPackage
    "solana-account-realloc-source"
    Examples.Backend.Solana.Contracts.AccountRealloc.spec
    "realloc_buffer"
    "buffer"
    "grow"
    64
  IO.println "solana-account-realloc: ok"
  return 0

end ProofForge.Tests.SolanaAccountRealloc

def main : IO UInt32 :=
  ProofForge.Tests.SolanaAccountRealloc.main
