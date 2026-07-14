import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.Plan.ToYul
import ProofForge.IR.Examples.EvmErrorsProbe
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Target.InterfaceOps.Evm

open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.Evm.Plan

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private partial def isLegacyErrorStmt : StmtPlan → Bool
  | .assert .. | .assertEq .. | .revertWithError .. => true
  | .ifElse _ thenBody elseBody =>
      thenBody.any isLegacyErrorStmt || elseBody.any isLegacyErrorStmt
  | .boundedFor _ _ _ body => body.any isLegacyErrorStmt
  | _ => false

private def plannedError? : StmtPlan → Option EvmErrorPlan
  | .assertPlanned _ _ (some error) | .revertPlanned error => some error
  | _ => none

def main : IO Unit := do
  let errorModule : ProofForge.IR.Module := {
    name := "CanonicalEvmErrors"
    state := #[]
    entrypoints := #[
      ProofForge.IR.Examples.EvmErrorsProbe.entryRevertCustomErrorArgs,
      ProofForge.IR.Examples.EvmErrorsProbe.entryRevertCustomErrorRuntimeArgs
    ]
  }
  let spec := ProofForge.Contract.ContractSpec.fromIR
    errorModule
  let checked <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"EVM error adaptation failed: {repr error}")
  let capabilityPlan : CapabilityPlan := {
    targetId := "evm"
    calls := checked.contract.requirements
  }
  require (checked.contract.interfaceExtensions.all fun extension =>
      extension.id == ProofForge.Target.InterfaceOps.Evm.solidityCustomErrorId)
    "custom errors did not normalize to the exact EVM interface extension ID"
  require ((ProofForge.Compiler.checkInterfaceOpHandlers "wasm-near" checked).size == 2)
    "NEAR accepted EVM custom-error interface extensions"
  let invalidContract := {
    checked.contract with
    interfaceExtensions := checked.contract.interfaceExtensions.map fun extension =>
      { extension with args := #[.string "9432a7ee", .strings #["string", "string"]] }
  }
  let invalidChecked <- match validateCanonical invalidContract with
    | .ok contract => pure contract
    | .error error => throw (IO.userError s!"generic extension validation overreached: {repr error}")
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore invalidChecked capabilityPlan with
  | .error error => do
      require (error.message.contains "unsupported EVM custom-error ABI type")
        "EVM decoder returned the wrong invalid-extension diagnostic"
  | .ok _ => throw (IO.userError "EVM accepted an unsupported custom-error ABI type")
  let plan <- match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capabilityPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"EVM error planning failed: {error.message}")
  require (!plan.entrypoints.any fun entrypoint => entrypoint.body.any isLegacyErrorStmt)
    "canonical EVM error planning reconstructed a Legacy ErrorRef statement"
  let staticEntry <- match plan.entrypoints.find? (·.name == "revertCustomErrorArgs") with
    | some entrypoint => pure entrypoint
    | none => throw (IO.userError "missing static custom-error entrypoint")
  let runtimeEntry <- match plan.entrypoints.find? (·.name == "revertCustomErrorRuntimeArgs") with
    | some entrypoint => pure entrypoint
    | none => throw (IO.userError "missing runtime custom-error entrypoint")
  let staticError <- match staticEntry.body.findSome? plannedError? with
    | some error => pure error
    | none => throw (IO.userError "static custom error did not reach EvmErrorPlan")
  let runtimeError <- match runtimeEntry.body.findSome? plannedError? with
    | some error => pure error
    | none => throw (IO.userError "runtime custom error did not reach EvmErrorPlan")
  require (staticError.soliditySelector? == some "9432a7ee" &&
      staticError.solidityArgWords.isEmpty && staticError.solidityArgExprs.size == 2)
    "static custom-error words were not normalized into typed Core arguments"
  require (runtimeError.soliditySelector? == some "9432a7ee" &&
      runtimeError.solidityArgWords.isEmpty && runtimeError.solidityArgExprs.size == 2)
    "runtime custom-error expressions were not preserved in the EVM target plan"
  for entrypoint in #[staticEntry, runtimeEntry] do
    match ProofForge.Backend.Evm.Plan.ToYul.lowerEntrypoint plan.name plan.overflowChecked entrypoint with
    | .ok _ => pure ()
    | .error error => throw (IO.userError s!"EVM target-owned error ToYul failed: {error.message}")
  IO.println "evm-error-plan: ok"
