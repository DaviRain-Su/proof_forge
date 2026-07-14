import ProofForge.IR.Legacy.Adapter
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
  let adapted ← match ProofForge.IR.Legacy.Adapter.adaptLegacy
      (ContractSpec.fromIR legacyModule) with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"direct crosscall adaptation failed: {repr error}")
  require (hasLiteral adapted.contract.module
      (.addressLit "0x000000000000000000000000000000000000dEaD"))
    "legacy target pool index did not become a direct Core address literal"
  require (hasLiteral adapted.contract.module (.stringLit "remote_call"))
    "legacy method pool index did not become a direct Core string literal"

  let withoutPool : CanonicalContract := {
    adapted.contract with
    materialization := { adapted.contract.materialization with crosscallStrings := #[] }
  }
  let checked ← match validateCanonical withoutPool with
    | .ok checked => pure checked
    | .error error => throw (IO.userError s!"pool-free canonical validation failed: {repr error}")
  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "evm"
    calls := checked.contract.requirements
  }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capabilityPlan with
  | .ok _ => pure ()
  | .error error => throw (IO.userError s!"pool-free EVM planning failed: {error.message}")
  IO.println "evm-direct-crosscall: ok"
