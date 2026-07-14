import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Contract.Spec
import ProofForge.IR.Legacy.Adapter
import ProofForge.Target.HostOps.Evm

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def cryptoModule : ProofForge.IR.Module := {
  name := "EvmCryptoHostOps"
  state := #[]
  entrypoints := #[
    {
      name := "recover"
      selector? := some "01020304"
      params := #[
        ("digest", .hash), ("v", .u64), ("r", .hash), ("s", .hash)
      ]
      returns := .u64
      mutability := .view
      body := #[.return (.ecrecover (.local "digest") (.local "v") (.local "r") (.local "s"))]
    },
    {
      name := "permitDigest"
      selector? := some "05060708"
      params := #[
        ("owner", .address), ("spender", .address), ("value", .u64),
        ("nonce", .u64), ("deadline", .u64), ("domain", .hash)
      ]
      returns := .hash
      mutability := .view
      body := #[.return (.eip712PermitDigest
        (.local "owner") (.local "spender") (.local "value")
        (.local "nonce") (.local "deadline") (.local "domain"))]
    }
  ]
}

private def hostCallIds (checked : CheckedCanonicalContract) : Array ProofForge.Target.HostOpId :=
  checked.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block =>
      block.instructions.filterMap fun instruction => match instruction.op with
        | .hostCall call => some call.id
        | _ => none

private def planHasCrypto (plan : ProofForge.Backend.Evm.Plan.ModulePlan) : Bool :=
  let statements := plan.entrypoints.flatMap (·.body)
  let hasRecover := statements.any fun statement => match statement with
    | .letBind _ _ (.ecrecover ..) => true
    | _ => false
  let hasDigest := statements.any fun statement => match statement with
    | .letBind _ _ (.eip712PermitDigest ..) => true
    | _ => false
  hasRecover && hasDigest

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR cryptoModule
  let checked ← match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"crypto adaptation failed: {repr error}")
  require (hostCallIds checked == #[
      ProofForge.Target.HostOps.Evm.ecrecoverSig.id,
      ProofForge.Target.HostOps.Evm.eip712PermitDigestSig.id
    ]) "EVM crypto expressions did not normalize to the exact HostOp IDs"
  match ProofForge.Compiler.runStrictCanonicalTargetGate "evm" spec with
  | .ok _ => pure ()
  | .error error => throw (IO.userError s!"strict EVM crypto gate failed: {error}")
  require ((ProofForge.Compiler.checkHostOpHandlers "wasm-near" checked).size == 2)
    "NEAR accepted an EVM crypto HostOp"
  let capPlan : CapabilityPlan := {
    targetId := "evm"
    calls := checked.contract.requirements
  }
  let plan ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"EVM crypto plan failed: {error.message}")
  require (planHasCrypto plan) "EVM crypto HostOps did not reach semantic plan expressions"
  IO.println "evm-crypto-hostops: ok"
