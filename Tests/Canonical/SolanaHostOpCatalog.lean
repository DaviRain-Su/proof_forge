import ProofForge.Frontend.Authored
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Solana.Extension
import ProofForge.Contract.Source.Solana.Internal.Authored

namespace ProofForge.Tests.Canonical.SolanaHostOpCatalog

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.Target
open ProofForge.Target.HostOps.Solana.Payload

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def operation :=
  CapabilityOperation.hostOp
    ProofForge.Target.HostOps.Solana.remainingComputeUnitsSig.id

def contract : AuthoredContract := {
  name := "SolanaOperationIntent"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[]
  entrypoints := #[{
    name := "run"
    kind := .function
    mutability := .view
    params := #[]
    retType := .unit
    body := #[.returnUnit]
  }]
  constructorParams := #[]
  constructorBindings := #[]
  intents := #[{
    kind := .capability
    operation := operation
    capability? := some .runtimeComputeUnits
  }]
}

def accountSpec : AccountSpec := {
  name := "vault"
  access := .writable
  signer := .signer
  owner := "program"
}

def pdaSpec : PdaSpec := {
  name := "vaultAuthority"
  seeds := #[
    { kind := .literal, value := "vault" },
    { kind := .account, value := "vault" }
  ]
  bump? := some "vaultBump"
  account? := some "vault"
  signer := true
}

def cpiSpec : CpiSpec := {
  name := "transfer"
  program := "system_program"
  instruction := "transfer"
  accounts := #[
    { name := "vault", access := .writable, signer := .signer },
    { name := "receiver", access := .writable }
  ]
  signerSeeds := #[{ kind := .bump, value := "vaultBump" }]
  protocol? := some "system"
  dataLayout? := some "system_transfer_u64"
  signed := true
}

def typedContract : AuthoredContract :=
  ProofForge.Frontend.Authored.Builder.build "SolanaTypedOperations" do
    ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount accountSpec
    ProofForge.Frontend.Authored.Builder.entry "run" do
      ProofForge.Contract.Source.Solana.Internal.Authored.derivePda pdaSpec
      ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi cpiSpec
      ProofForge.Frontend.Authored.Builder.retUnit

def duplicatePayloadContract : AuthoredContract := {
  typedContract with
  name := "DuplicatePayload"
  intents := typedContract.intents.map fun authoredIntent =>
    if authoredIntent.operation ==
        .hostOp ProofForge.Target.HostOps.Solana.accountDeclareId then
      { authoredIntent with payload := authoredIntent.payload.push {
          name := "name", value := .text "duplicate" } }
    else
      authoredIntent
}

def run : IO Unit := do
  let catalog ← match ProofForge.Target.HostOps.Solana.catalog with
    | .ok catalog => pure catalog
    | .error error => throw <| IO.userError s!"Solana HostOp catalog failed: {repr error}"
  let signature ← match catalog.lookup
      ProofForge.Target.HostOps.Solana.remainingComputeUnitsSig.id with
    | .ok signature => pure signature
    | .error error => throw <| IO.userError s!"Solana HostOp lookup failed: {repr error}"
  require (signature.results == #[ProofForge.IR.Core.CoreType.u64])
    "remaining compute units has the wrong result type"
  require (solanaSbpfAsm.hostOps.contains signature.id)
    "solana-sbpf-asm does not advertise the registered HostOp"
  require (solanaSbpfAsm.hostOps.contains ProofForge.Target.HostOps.Solana.accountDeclareId)
    "solana-sbpf-asm does not advertise typed materialization operations"
  match catalog.lookup ProofForge.Target.HostOps.Solana.accountDeclareId with
  | .ok _ => throw <| IO.userError "materialization operation leaked into the runtime HostOp catalog"
  | .error _ => pure ()

  let bundle ← match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"authored normalization failed: {repr error}"
  let calls := bundle.contract.contract.requirements
  require (calls.any fun call =>
      call.capability == .runtimeComputeUnits && call.operation == operation)
    "versioned Solana operation did not survive authored canonicalization"
  let plan : CapabilityPlan := {
    targetId := solanaSbpfAsm.id
    calls
  }
  match requireCapabilityPlan solanaSbpfAsm plan with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError s!"Solana profile rejected its own operation: {error.render}"
  match requireCapabilityPlan evm { plan with targetId := evm.id } with
  | .ok _ => throw <| IO.userError "EVM accepted a Solana operation without a handler"
  | .error error =>
      require (error.render.contains "has no handler for operation")
        "foreign-target rejection did not identify the missing operation handler"

  let typedBundle ← match normalizeAuthored typedContract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"typed Solana normalization failed: {repr error}"
  let typedCalls := typedBundle.contract.contract.requirements
  let typedPlan : CapabilityPlan := { targetId := solanaSbpfAsm.id, calls := typedCalls }
  let extensions ← match ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlanChecked typedPlan with
    | .ok extensions => pure extensions
    | .error error => throw <| IO.userError error
  require (extensions.accounts.any fun account =>
      account.name == "vault" && account.access == "writable" && account.signer == "signer")
    "typed Solana account payload did not reach the backend plan"
  require (extensions.pdas.any fun pda =>
      pda.name == "vaultAuthority" && pda.seeds == #["literal:vault", "account:vault"])
    "typed Solana PDA payload did not reach the backend plan"
  require (extensions.pdaActions.any fun action =>
      action.name == "vaultAuthority" && action.entrypoint == "run")
    "typed Solana PDA action lost its entrypoint scope"
  require (extensions.cpis.any fun cpi =>
      cpi.name == "transfer" && cpi.accounts.size == 2 && cpi.signed &&
        cpi.dataLayout? == some "system_transfer_u64")
    "typed Solana CPI payload did not reach the backend plan"
  let malformedCalls := typedCalls.map fun call =>
    if call.operation == .hostOp ProofForge.Target.HostOps.Solana.cpiInvokeId then
      { call with payload := call.payload.filter (·.name != "program") }
    else call
  match ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlanChecked
      { typedPlan with calls := malformedCalls } with
  | .ok _ => throw <| IO.userError "malformed typed Solana payload was accepted"
  | .error _ => pure ()
  match normalizeAuthored duplicatePayloadContract with
  | .ok _ => throw <| IO.userError "duplicate typed payload fields were accepted"
  | .error _ => pure ()
  IO.println "solana-host-op-catalog: ok"

end ProofForge.Tests.Canonical.SolanaHostOpCatalog

def main : IO Unit :=
  ProofForge.Tests.Canonical.SolanaHostOpCatalog.run
