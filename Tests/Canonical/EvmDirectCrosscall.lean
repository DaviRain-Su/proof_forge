import ProofForge.Frontend.Authored.Normalize
import ProofForge.Contract.Spec
import ProofForge.Backend.Evm.Plan.Core

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Contract

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def callRemote : Entrypoint := {
  name := "callRemote"
  selector? := some "01020304"
  returns := .u64
  body := #[
    .return (.crosscallInvoke
      (.literal (.address 0)) (.literal (.address 1)) #[])
  ]
}

private def legacyModule : ProofForge.IR.Module := {
  name := "EvmDirectCrosscall"
  state := #[]
  entrypoints := #[callRemote]
  crosscallStrings := #[
    "0x000000000000000000000000000000000000dEaD",
    "remote_call"
  ]
}

private def hasLiteral (module : ProofForge.IR.Core.Module)
    (expected : CoreLiteral) : Bool :=
  module.functions.any fun function =>
    function.blocks.any fun block =>
      block.instructions.any fun instruction =>
        match instruction.op with
        | .pure (.literal literal) => literal == expected
        | _ => false

def main : IO Unit := do
  let adapted ← match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec
      (ContractSpec.fromIR legacyModule) with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"direct crosscall adaptation failed: {repr error}")
  require (hasLiteral adapted.contract.module (.addressLit "0"))
    "source target handle did not remain a stable Core address index"
  require (hasLiteral adapted.contract.module (.stringLit "1"))
    "source method handle did not remain a stable Core string index"

  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "evm"
    calls := adapted.contract.requirements
  }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore adapted capabilityPlan with
  | .ok _ => pure ()
  | .error error => throw (IO.userError s!"pool-backed EVM planning failed: {error.message}")

  let withoutPool : CanonicalContract := {
    adapted.contract with
    materialization := { adapted.contract.materialization with crosscallStrings := #[] }
  }
  let checked ← match validateCanonical withoutPool with
    | .ok checked => pure checked
    | .error error => throw (IO.userError s!"pool-free canonical validation failed: {repr error}")
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capabilityPlan with
  | .ok _ => throw (IO.userError "pool-free EVM planning unexpectedly succeeded")
  | .error error =>
      require (error.message.contains "target handle 0 is out of range")
        s!"pool-free EVM planning failed at the wrong boundary: {error.message}"
  IO.println "evm-direct-crosscall: ok"
