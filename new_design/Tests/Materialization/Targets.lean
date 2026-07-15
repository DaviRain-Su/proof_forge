import ProofForgeV2.Examples.Counter
import ProofForgeV2.Examples.PrivateSum4
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Registry

namespace Tests.Materialization

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let counter ← match Compiler.compile Examples.counter with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let counterWithCall ← match Compiler.compile Examples.counterWithSynchronousCall with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let differentLogic ← match Compiler.compile Examples.counterWithDifferentBusinessLogic with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let privateSum ← match Compiler.compile Examples.privateSum4 with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  for target in [TargetId.evm, .solana, .near, .noir] do
    let output ← Targets.materialize target counter
    expect (!output.files.isEmpty) s!"{target} must emit at least one artifact"
    expect (output.manifest.sourceHash == Examples.counter.sourceHash)
      "manifest must bind the decoded source"
    expect (output.manifest.semanticHash == counter.semanticHash)
      "manifest must bind the canonical semantics"
  let unsupported := Targets.checkSupport .noir counterWithCall
  match unsupported with
  | .error (.unsupportedRequirement .synchronousCall .noir) => pure ()
  | _ => throw <| IO.userError "Noir must reject synchronous chain calls"
  let privateCircuit ← Targets.materialize .noir privateSum
  expect (privateCircuit.files.any (fun file => file.path == "src/main.nr"))
    "Noir must materialize the private circuit in the same DSL"
  match Targets.checkSupport .evm privateSum with
  | .error (.unsupportedRequirement .privateWitness .evm) => pure ()
  | _ => throw <| IO.userError "EVM must reject private witness semantics instead of exposing it"
  for target in [TargetId.evm, .solana, .near, .noir] do
    match Targets.materializeResult target differentLogic with
    | .error (.planInvariant rejectedTarget _) =>
        expect (rejectedTarget == target) "shape rejection must identify its target"
    | _ => throw <| IO.userError s!"{target} must reject lookalike programs with different business logic"

end Tests.Materialization
