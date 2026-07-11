import ProofForge.Backend.Solana.Client
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Package
import ProofForge.Contract.Builder
import ProofForge.Solana
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaComputeBudgetInstruction

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

def scopedComputeBudgetCall? (plan : CapabilityPlan) (name entrypoint : String) :
    Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .runtimeComputeUnits &&
    metadataValue? call "solana.compute_budget.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"metadata `{key}` mismatch for operation `{call.operation}`"

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Builder.build "SolanaComputeBudget" do
    ProofForge.Contract.Builder.scalarState "counter" .u64
    ProofForge.Contract.Builder.entry "increment" do
      ProofForge.Solana.requestComputeBudget "fast_increment"
        (unitLimit? := some 250000)
        (unitPriceMicroLamports? := some 5000)
      ProofForge.Contract.Builder.effect
        (ProofForge.Contract.Builder.storageScalarAssignOp "counter"
          ProofForge.IR.AssignOp.add
          (ProofForge.Contract.Builder.u64 1))

def main : IO UInt32 := do
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana compute-budget routing failed: {err.render}"

  require (hasCapability plan .runtimeComputeUnits)
    "Solana plan missing runtime.compute_units capability"

  let budgetCall ←
    match scopedComputeBudgetCall? plan "fast_increment" "increment" with
    | some call => pure call
    | none => throw <| IO.userError "Solana plan missing fast_increment compute-budget advice"
  require (budgetCall.operation == .builtin "solana.compute_budget.instruction")
    "fast_increment should lower through solana.compute_budget.instruction"
  requireMetadata budgetCall "solana.extension" "compute_budget"
  requireMetadata budgetCall "solana.compute_budget.op" "instruction"
  requireMetadata budgetCall "solana.compute_budget.unit_limit" "250000"
  requireMetadata budgetCall "solana.compute_budget.unit_price_micro_lamports" "5000"

  match resolveSpec evm spec with
  | .ok _ => throw <| IO.userError "EVM unexpectedly accepted Solana compute-budget metadata"
  | .error err =>
      require (contains err.render "cannot use Solana target extension metadata")
        s!"unexpected EVM diagnostic: {err.render}"

  let manifest := ProofForge.Backend.Solana.Manifest.renderManifestWithPlan spec.module plan
  require (contains manifest "[[solana.entrypoint_compute_budget]]")
    "manifest missing compute-budget entrypoint section"
  require (contains manifest "entrypoint = \"increment\"")
    "manifest missing compute-budget entrypoint"
  require (contains manifest "compute_budget = \"fast_increment\"")
    "manifest missing compute-budget action name"
  require (contains manifest "unit_limit = 250000")
    "manifest missing compute-unit limit"
  require (contains manifest "unit_price_micro_lamports = 5000")
    "manifest missing compute-unit price"

  let idl := ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan
  require (contains idl "\"computeBudget\": [")
    "IDL missing instruction compute-budget array"
  require (contains idl "\"name\": \"fast_increment\"")
    "IDL missing compute-budget action name"
  require (contains idl "\"unitLimit\": 250000")
    "IDL missing compute-unit limit"
  require (contains idl "\"unitPriceMicroLamports\": 5000")
    "IDL missing compute-unit price"
  require (contains idl "\"entrypointActions\"")
    "IDL missing entrypoint actions"
  require (contains idl "\"computeBudget\": [{\"entrypoint\": \"increment\"")
    "IDL missing entrypoint compute-budget action metadata"

  let client := ProofForge.Backend.Solana.Client.renderWithPlan spec.module plan
  require (contains client "ComputeBudgetProgram")
    "client missing ComputeBudgetProgram import"
  require (contains client "computeBudgetInstructions")
    "client missing compute-budget helper"
  require (contains client "setComputeUnitLimit")
    "client missing compute-unit limit instruction"
  require (contains client "setComputeUnitPrice")
    "client missing compute-unit price instruction"
  require (contains client "createTransactionInstructions")
    "client missing transaction instruction helper"
  require (contains client "fast_increment")
    "client missing embedded compute-budget advice"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-compute-budget" spec with
  | .ok pkg =>
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "compute-budget package missing manifest.toml"
      let some idlFile := pkg.files.find? (fun file => file.path == pkg.idlPath)
        | throw <| IO.userError "compute-budget package missing proof-forge-idl.json"
      let some clientFile := pkg.files.find? (fun file => file.path == pkg.clientPath)
        | throw <| IO.userError "compute-budget package missing proof-forge-client.ts"
      require (contains manifestFile.contents "[[solana.entrypoint_compute_budget]]")
        "package manifest missing compute-budget entrypoint section"
      require (contains idlFile.contents "\"computeBudget\": [")
        "package IDL missing compute-budget array"
      require (contains clientFile.contents "computeBudgetInstructions")
        "package client missing compute-budget helper"
  | .error err =>
      throw <| IO.userError s!"Solana compute-budget package render failed: {err.render}"

  IO.println "solana-compute-budget-instruction: ok"
  return 0

end ProofForge.Tests.SolanaComputeBudgetInstruction

def main : IO UInt32 :=
  ProofForge.Tests.SolanaComputeBudgetInstruction.main
