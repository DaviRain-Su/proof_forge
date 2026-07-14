import Examples.Product.Canonical.ArrayExample
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
import ProofForge.Frontend.Surface.Normalize

open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let bundle ← match ProofForge.Frontend.Surface.normalizeSurface
      Examples.Product.Canonical.ArrayExample.contract with
    | .ok bundle => pure bundle
    | .error error => throw (IO.userError s!"array Surface normalization failed: {repr error}")
  let instructions := bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap (·.instructions)
  require (instructions.any fun instruction => match instruction.op with
    | .memoryAlloc .u64 _ => true | _ => false) "missing Core memoryAlloc"
  require ((instructions.filter fun instruction => match instruction.op with
    | .memoryStore _ _ _ => true | _ => false).size == 6) "expected six Core memory stores"
  require ((instructions.filter fun instruction => match instruction.op with
    | .memoryLoad _ _ => true | _ => false).size == 4) "expected four Core memory loads"
  let capabilityPlan : CapabilityPlan := {
    targetId := "evm", calls := bundle.contract.contract.requirements }
  let plan ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract capabilityPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"array EVM plan failed: {error.message}")
  let yul ← match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan plan with
    | .ok yul => pure yul
    | .error error => throw (IO.userError s!"array EVM render failed: {error.message}")
  require (yul.contains "__proof_forge_memory_array_new") "missing EVM memory allocation helper"
  require (yul.contains "__proof_forge_memory_array_get") "missing EVM memory load helper"
  IO.println "surface-memory-array: ok"
