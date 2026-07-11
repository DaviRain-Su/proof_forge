import ProofForge.Backend.Solana.Refinement
import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.Plan
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec

open ProofForge.Backend.Solana
open ProofForge.Backend.Solana.Plan
open ProofForge.Backend.Solana.Plan.Core
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.Refinement
open ProofForge.IR.Legacy.Adapter

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def canonicalNodes (module : ProofForge.IR.Module) : IO (Array Asm.AstNode) := do
  let bundle <- match adaptLegacy (ProofForge.Contract.ContractSpec.fromIR module) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"adapt failed: {repr e}"
  let capPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "solana-sbpf-asm", calls := bundle.contract.contract.requirements, metadata := #[]
  }
  let plan <- match buildFromCore bundle.contract capPlan with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"plan failed: {e.message}"
  match lowerFromPlan plan with
  | .ok nodes => pure nodes
  | .error e => throw <| IO.userError s!"lower failed: {e.message}"

def compareTrace (name : String) (module : ProofForge.IR.Module)
    (obligation : ProofForge.Backend.Refinement.TraceObligation) : IO Unit := do
  let legacy <- match SbpfAsm.lowerModule module with
    | .ok nodes => pure nodes
    | .error e => throw <| IO.userError s!"{name} legacy lower failed: {e.message}"
  let canonical <- canonicalNodes module
  for (label, nodes) in [("legacy", legacy), ("canonical", canonical)] do
    match BpfEncode.toBpfBin nodes with
    | .ok bytes => require (bytes.size > 0) s!"{name} {label} encoded no bytes"
    | .error e => throw <| IO.userError s!"{name} {label} encode failed: {e.render}"
  let legacyTrace <- match runTrace legacy obligation with
    | .ok trace => pure trace
    | .error e => throw <| IO.userError s!"{name} legacy trace failed: {e}"
  let canonicalTrace <- match runTrace canonical obligation with
    | .ok trace => pure trace
    | .error e => throw <| IO.userError s!"{name} canonical trace failed: {e}"
  require (legacyTrace == canonicalTrace)
    s!"{name} trace mismatch:\nlegacy={repr legacyTrace}\ncanonical={repr canonicalTrace}"

def main : IO UInt32 := do
  compareTrace "Counter" ProofForge.IR.Examples.Counter.module counterTraceObligation
  compareTrace "ValueVault" ProofForge.IR.Examples.ValueVault.module valueVaultTraceObligation
  IO.println "canonical-solana-runtime-parity: ok"
  return 0
