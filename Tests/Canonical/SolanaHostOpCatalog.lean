import ProofForge.Frontend.Authored
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.Canonical.SolanaHostOpCatalog

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.Target

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
  IO.println "solana-host-op-catalog: ok"

end ProofForge.Tests.Canonical.SolanaHostOpCatalog

def main : IO Unit :=
  ProofForge.Tests.Canonical.SolanaHostOpCatalog.run
