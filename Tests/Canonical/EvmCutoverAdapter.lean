import ProofForge.Contract.Spec
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Core

/-! Regression coverage for Legacy constructs admitted by the EVM canonical cutover. -/

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.Frontend.Authored.Normalize

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def hashModule : ProofForge.IR.Module := {
  name := "CutoverHash", state := #[], entrypoints := #[{
    name := "hash", returns := .hash,
    body := #[.return (.literal (.hash4 1 2 3 4))] }]
}

def mapModule : ProofForge.IR.Module := {
  name := "CutoverMap",
  state := #[{ id := "values", kind := .map .u64 4, type := .u64 }],
  entrypoints := #[{
    name := "get", params := #[("key", .u64)], returns := .u64,
    body := #[.return (.effect (.storageMapGet "values" (.local "key")))] }]
}

def userHashModule : ProofForge.IR.Module := {
  name := "CutoverUserHash", state := #[], entrypoints := #[{
    name := "caller_hash", returns := .hash,
    body := #[.return (.effect (.contextRead .userIdHash))] }]
}

def main : IO Unit := do
  let hashBundle ← match normalizeContractSpec (ProofForge.Contract.ContractSpec.fromIR hashModule) with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"hash4 adaptation failed: {repr error}"
  require (hashBundle.contract.contract.module.functions.any fun function =>
    function.blocks.any fun block => block.instructions.any fun instruction =>
      match instruction.op with | .pure (.literal (.hashLit _)) => true | _ => false)
    "hash4 did not become a Core hash literal"

  let mapBundle ← match normalizeContractSpec (ProofForge.Contract.ContractSpec.fromIR mapModule) with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"map-get adaptation failed: {repr error}"
  require (mapBundle.contract.contract.module.functions.any fun function =>
    function.blocks.any fun block => block.instructions.any fun instruction =>
      match instruction.op with | .storageLoad { path := #[.mapKey _], .. } => true | _ => false)
    "storageMapGet did not become a Core mapKey load"

  let userBundle ← match normalizeContractSpec (ProofForge.Contract.ContractSpec.fromIR userHashModule) with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"userIdHash adaptation failed: {repr error}"
  require (userBundle.contract.contract.module.functions.any fun function =>
    function.blocks.any fun block => block.instructions.any fun instruction =>
      match instruction.op with | .pure (.hash { type := .address, .. }) => true | _ => false)
    "userIdHash did not hash the Core sender address"
  IO.println "evm-cutover-adapter: ok"
