import ProofForge.Frontend.Authored

namespace ProofForge.Tests.Canonical.AuthoredBuilder

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Builder
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def counter : AuthoredContract := build "Counter" do
  scalarState "count" .u64
  quintInvariant "countBounded" "count <= MAX_UINT"
  quintLiveness "eventuallyPositive" "eventually(count > 0)"
  leanInvariant "countNonNegative" "Example.countNonNegative"
  entry "initialize" do
    stateWrite "count" (.literal (.u64Lit 0))
    retUnit
  entry "increment" do
    bind "n" .u64 (.stateRead "count")
    stateWrite "count" (.arith .add true (.local "n") (.literal (.u64Lit 1)))
    retUnit
  queryReturns "get" .u64 do
    ret (.stateRead "count")

def run : IO Unit := do
  let bundle ← match normalizeAuthored counter with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"direct builder normalization failed: {repr error}"
  let contract := bundle.contract.contract
  require (contract.module.name == "Counter" && contract.module.state.size == 1)
    "direct builder lost the Counter module or state"
  require (contract.module.functions.size == 3 &&
      contract.interface.entrypoints.map (·.name) == #["initialize", "increment", "get"])
    "direct builder lost the Counter entrypoint surface"
  require (bundle.evidence.verification.quintInvariants.map (·.name) == #["countBounded"] &&
      bundle.evidence.verification.quintLiveness.map (·.name) == #["eventuallyPositive"] &&
      bundle.evidence.verification.leanInvariants.map (·.name) == #["countNonNegative"])
    "direct builder lost Counter verification annotations"
  let increment ← match contract.module.functions[1]? with
    | some function => pure function
    | none => throw <| IO.userError "direct builder omitted increment"
  require (increment.blocks.flatMap (·.instructions) |>.any fun instruction =>
      match instruction.op with
      | .pure (.arithmetic .add .checked _ _) => true
      | _ => false)
    "direct builder did not preserve checked increment arithmetic"
  IO.println "authored-builder: ok"

end ProofForge.Tests.Canonical.AuthoredBuilder

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredBuilder.run
