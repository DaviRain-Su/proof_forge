import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Noir

namespace ProofForgeV2.Targets

open ProofForgeV2

def phase1 : Array TargetId := #[.evm, .solana, .near, .noir]

def maturity : TargetId → String
  | .evm => "runtime-validated-alpha"
  | .near => "wasm-validated-alpha"
  | .solana => "plan-only"
  | .noir => "source-only"
  | _ => "research-only"

def researched : Array TargetId := #[.cosmwasm, .soroban, .icp, .openvm, .aleo, .psy]

def descriptor? : TargetId → Option TargetDescriptor
  | .evm => some Evm.descriptor
  | .solana => some Solana.descriptor
  | .near => some Near.descriptor
  | .noir => some Noir.descriptor
  | _ => none

def checkSupport (target : TargetId) (program : SemanticProgram) : CompileResult Unit := do
  let descriptor ← match descriptor? target with
    | some descriptor => .ok descriptor
    | none => .error <| .targetNotImplemented target
  for requirement in program.requirements do
    unless descriptor.supportedRequirements.contains requirement do
      throw <| CompileError.unsupportedRequirement requirement target

def materializeResult (target : TargetId) (program : SemanticProgram) : CompileResult OutputSet := do
  checkSupport target program
  match target with
  | .evm => Evm.materialize program
  | .solana => Solana.materialize program
  | .near => Near.materialize program
  | .noir => Noir.materialize program
  | other => .error <| .targetNotImplemented other

def materialize (target : TargetId) (program : SemanticProgram) : IO OutputSet :=
  match materializeResult target program with
  | .ok output => pure output
  | .error error => throw <| IO.userError error.render

end ProofForgeV2.Targets
