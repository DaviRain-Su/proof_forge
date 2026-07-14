import TestFixtures.SurfaceProducts.ERC4626Vault
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
import ProofForge.Frontend.Surface.Normalize

open ProofForge.IR.Core
open ProofForge.Backend.Evm.Plan

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def instructionIsCrosscall (instruction : Instruction) : Bool :=
  match instruction.op with
  | .crosscall _ _ => true
  | _ => false

private def instructionIsStore (instruction : Instruction) : Bool :=
  match instruction.op with
  | .storageStore _ _ | .storageResize _ _ => true
  | _ => false

private partial def countIfElse (body : Array StmtPlan) : Nat :=
  body.foldl (fun total statement => total + match statement with
    | .ifElse _ thenBody elseBody => 1 + countIfElse thenBody + countIfElse elseBody
    | .boundedFor _ _ _ loopBody => countIfElse loopBody
    | _ => 0) 0

private partial def countReturns (body : Array StmtPlan) : Nat :=
  body.foldl (fun total statement => total + match statement with
    | .return _ => 1
    | .ifElse _ thenBody elseBody => countReturns thenBody + countReturns elseBody
    | .boundedFor _ _ _ loopBody => countReturns loopBody
    | _ => 0) 0

def main : IO Unit := do
  let surface := TestFixtures.SurfaceProducts.ERC4626Vault.contract
  require (surface.entrypoints.size == 23) "direct ERC4626 ABI must keep 23 entrypoints"
  require (surface.events.size == 4) "direct ERC4626 must keep four standard events"
  let selectors := surface.entrypoints.filterMap (·.selector?)
  for selector in #["38d52e0f", "01e1d114", "c6e6f592", "6e553f65",
      "94bf804d", "b460af94", "ba087652", "a9059cbb", "095ea7b3"] do
    require (selectors.contains selector) s!"direct ERC4626 lost selector {selector}"

  let bundle ← match ProofForge.Frontend.Surface.normalizeSurface surface with
    | .ok bundle => pure bundle
    | .error error => throw (IO.userError s!"direct ERC4626 normalization failed: {repr error}")
  let core := bundle.contract.contract.module
  let interface := bundle.contract.contract.interface
  let some depositInterface := interface.entrypoints.find? (·.name == "deposit")
    | throw (IO.userError "direct ERC4626 interface lost deposit")
  require (depositInterface.params[0]!.abiWord? == some "uint256" &&
      depositInterface.returnAbiWord? == some "uint256")
    "direct ERC4626 deposit lost standard uint256 ABI carriers"
  let some depositEvent := interface.events.find? (·.name == "Deposit")
    | throw (IO.userError "direct ERC4626 interface lost Deposit event")
  require (depositEvent.fields[2]!.abiWord? == some "uint256" &&
      depositEvent.fields[3]!.abiWord? == some "uint256")
    "direct ERC4626 Deposit event lost uint256 ABI carriers"
  for entrypoint in surface.entrypoints.filter (fun entrypoint =>
      match entrypoint.mutability with | .view => true | .call => false) do
    let some index := surface.entrypoints.findIdx? (·.name == entrypoint.name)
      | throw (IO.userError s!"missing Surface entrypoint {entrypoint.name}")
    let some function := core.functions.find? (·.id == ⟨index⟩)
      | throw (IO.userError s!"missing Core function {entrypoint.name}")
    require (!function.blocks.any fun block => block.instructions.any instructionIsStore)
      s!"view entrypoint {entrypoint.name} contains a state write"
  let crosscallCount := core.functions.foldl (fun total function =>
    total + function.blocks.foldl (fun blockTotal block =>
      blockTotal + (block.instructions.filter instructionIsCrosscall).size) 0) 0
  require (crosscallCount >= 18)
    "direct ERC4626 lost IERC20 balance/transfer crosscall measurements"

  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "evm", calls := bundle.contract.contract.requirements }
  let plan ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract capabilityPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"direct ERC4626 EVM plan failed: {error.message}")
  let some previewMint := plan.entrypoints.find? (·.name == "previewMint")
    | throw (IO.userError "direct ERC4626 plan lost previewMint")
  require (countIfElse previewMint.body >= 3 && countReturns previewMint.body >= 4)
    "EVM structured CFG lowering lost nested previewMint branches/returns"
  let some maxDeposit := plan.entrypoints.find? (·.name == "maxDeposit")
    | throw (IO.userError "direct ERC4626 plan lost maxDeposit")
  require (countIfElse maxDeposit.body >= 8 && countReturns maxDeposit.body >= 6)
    "EVM structured CFG lowering lost conservative maxDeposit branches"
  let some plannedDepositEvent := plan.events.find? (·.name == "Deposit")
    | throw (IO.userError "direct ERC4626 plan lost Deposit event")
  require (plannedDepositEvent.signature == "Deposit(address,address,uint256,uint256)")
    "direct ERC4626 EVM plan emitted a non-standard Deposit signature"
  let yul ← match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan plan with
    | .ok yul => pure yul
    | .error error => throw (IO.userError s!"direct ERC4626 Yul failed: {error.message}")
  require (yul.contains "case 0x6e553f65" && yul.contains "case 0xba087652")
    "direct ERC4626 dispatch lost deposit/redeem selectors"
  require (yul.contains "call(gas()") "direct ERC4626 Yul lost IERC20 CALL materialization"
  IO.FS.createDirAll "build/evm-direct"
  IO.FS.writeFile "build/evm-direct/ERC4626.yul" yul
  IO.println "evm-direct-erc4626: ok"
