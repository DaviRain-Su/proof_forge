import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Contract.Source.Evm
import ProofForge.Contract.Spec
import ProofForge.IR.Legacy.Adapter
import ProofForge.Target.HostOps.Evm
import ProofForge.Target.HostOps.Near

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def contextSpec (name : String) (field : ProofForge.IR.ContextField)
    (resultType : ValueType) : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.ContractSpec.fromIR {
    name
    state := #[]
    entrypoints := #[{
      name := "read"
      selector? := some "01020304"
      «returns» := resultType
      mutability := .view
      body := #[.return (.effect (.contextRead field))]
    }]
  }

private def exprSpec (name : String) (expr : ProofForge.IR.Expr)
    (resultType : ValueType) : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.ContractSpec.fromIR {
    name
    state := #[]
    entrypoints := #[{
      name := "read"
      selector? := some "01020304"
      «returns» := resultType
      mutability := .view
      body := #[.return expr]
    }]
  }

private def adapt (name : String) (field : ProofForge.IR.ContextField)
    (resultType : ValueType) : IO CheckedCanonicalContract := do
  match ProofForge.IR.Legacy.Adapter.adaptLegacy (contextSpec name field resultType) with
  | .ok bundle => pure bundle.contract
  | .error error => throw (IO.userError s!"{name} adaptation failed: {repr error}")

private def adaptExpr (name : String) (expr : ProofForge.IR.Expr)
    (resultType : ValueType) : IO CheckedCanonicalContract := do
  match ProofForge.IR.Legacy.Adapter.adaptLegacy (exprSpec name expr resultType) with
  | .ok bundle => pure bundle.contract
  | .error error => throw (IO.userError s!"{name} adaptation failed: {repr error}")

private def hostCallIds (checked : CheckedCanonicalContract) : Array ProofForge.Target.HostOpId :=
  checked.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block =>
      block.instructions.filterMap fun instruction => match instruction.op with
        | .hostCall call => some call.id
        | _ => none

private def evmPlan (checked : CheckedCanonicalContract) :
    IO ProofForge.Backend.Evm.Plan.ModulePlan := do
  let capPlan : CapabilityPlan := {
    targetId := "evm"
    calls := checked.contract.requirements
  }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
  | .ok plan => pure plan
  | .error error => throw (IO.userError s!"EVM context plan failed: {error.message}")

private def nearPlan (checked : CheckedCanonicalContract) :
    IO ProofForge.Backend.WasmHost.NearModulePlan.NearModulePlan := do
  let capPlan : CapabilityPlan := {
    targetId := "wasm-near"
    calls := checked.contract.requirements
  }
  match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore checked capPlan with
  | .ok plan => pure plan
  | .error error => throw (IO.userError s!"NEAR context plan failed: {error.message}")

private def evmPlanHasContext (plan : ProofForge.Backend.Evm.Plan.ModulePlan)
    (expected : ProofForge.Backend.Evm.Plan.ContextExprPlan) : Bool :=
  plan.entrypoints.any fun entrypoint => entrypoint.body.any fun statement => match statement with
    | .letBind _ _ (.context actual) => reprStr actual == reprStr expected
    | _ => false

private def evmPlanHasBlockHashOfSeven (plan : ProofForge.Backend.Evm.Plan.ModulePlan) : Bool :=
  plan.entrypoints.any fun entrypoint => entrypoint.body.any fun statement => match statement with
    | .letBind name _ (.literalWord 7) =>
        entrypoint.body.any fun candidate => match candidate with
          | .letBind _ _ (.context (.blockHash (.local argument))) => argument == name
          | _ => false
    | _ => false

private def nearPlanHasHostContext
    (plan : ProofForge.Backend.WasmHost.NearModulePlan.NearModulePlan)
    (expected : ProofForge.Target.HostOpId) : Bool :=
  plan.functions.any fun function => function.blocks.any fun block =>
    block.ops.any fun operation => match operation with
      | .hostContext _ actual => actual == expected
      | _ => false

def main : IO Unit := do
  let origin ← adaptExpr "EvmOrigin" ProofForge.Contract.Source.Evm.origin .address
  require (hostCallIds origin == #[ProofForge.Target.HostOps.Evm.originSig.id])
    "EVM origin authoring API did not emit evm.context/origin"
  require (evmPlanHasContext (← evmPlan origin) .origin)
    "EVM origin HostOp did not materialize to the origin context plan"
  require ((ProofForge.Compiler.checkHostOpHandlers "wasm-near" origin).any
      (·.contains "evm.context/origin@1.0.0"))
    "NEAR accepted the EVM origin HostOp"

  let randomness ← adaptExpr "EvmPrevRandao" ProofForge.Contract.Source.Evm.prevRandao .hash
  require (hostCallIds randomness == #[ProofForge.Target.HostOps.Evm.prevRandaoSig.id])
    "EVM prevRandao authoring API did not emit evm.context/prevrandao"
  require (evmPlanHasContext (← evmPlan randomness) .prevRandao)
    "EVM prevRandao HostOp did not materialize to the target context plan"

  let evmCases : Array
      (String × ProofForge.IR.Expr × ValueType × ProofForge.Target.HostOpId ×
        ProofForge.Backend.Evm.Plan.ContextExprPlan) := #[
    ("EvmGasPrice", ProofForge.Contract.Source.Evm.gasPrice, .u64,
      ProofForge.Target.HostOps.Evm.gasPriceSig.id, .gasPrice),
    ("EvmBaseFee", ProofForge.Contract.Source.Evm.baseFee, .u64,
      ProofForge.Target.HostOps.Evm.baseFeeSig.id, .baseFee),
    ("EvmCoinbase", ProofForge.Contract.Source.Evm.coinbase, .hash,
      ProofForge.Target.HostOps.Evm.coinbaseSig.id, .coinbase)
  ]
  for (name, expr, resultType, expectedId, expectedPlan) in evmCases do
    let checked ← adaptExpr name expr resultType
    require (hostCallIds checked == #[expectedId])
      s!"{name} authoring API did not emit its typed EVM HostOp"
    require (evmPlanHasContext (← evmPlan checked) expectedPlan)
      s!"{name} HostOp did not materialize to the EVM target context plan"
    require ((ProofForge.Compiler.checkHostOpHandlers "wasm-near" checked).any
        (·.contains expectedId.render))
      s!"NEAR accepted EVM HostOp {expectedId.render}"

  let historical ← adaptExpr "EvmBlockHash"
    (ProofForge.Contract.Source.Evm.blockHash (.literal (.u64 7))) .hash
  require (hostCallIds historical == #[ProofForge.Target.HostOps.Evm.blockHashSig.id])
    "EVM blockHash authoring API did not emit evm.context/block_hash"
  let historicalPlan ← evmPlan historical
  require (evmPlanHasBlockHashOfSeven historicalPlan)
    "EVM blockHash HostOp did not retain its block-number argument"
  require ((ProofForge.Compiler.checkHostOpHandlers "wasm-near" historical).any
      (·.contains ProofForge.Target.HostOps.Evm.blockHashSig.id.render))
    "NEAR accepted the EVM blockHash HostOp"

  let nearCases : Array
      (String × ProofForge.IR.ContextField × ValueType × ProofForge.Target.HostOpId) := #[
    ("NearPredecessor", .accountId, .string,
      ProofForge.Target.HostOps.Near.predecessorAccountIdSig.id),
    ("NearEpoch", .epochHeight, .u64, ProofForge.Target.HostOps.Near.epochHeightSig.id),
    ("NearRandom", .randomSeed, .hash, ProofForge.Target.HostOps.Near.randomSeedSig.id),
    ("NearPrepaidGas", .prepaidGas, .u64, ProofForge.Target.HostOps.Near.prepaidGasSig.id),
    ("NearUsedGas", .usedGas, .u64, ProofForge.Target.HostOps.Near.usedGasSig.id)
  ]
  for (name, field, resultType, expectedId) in nearCases do
    let checked ← adapt name field resultType
    require (hostCallIds checked == #[expectedId])
      s!"{name} did not normalize to its typed NEAR HostOp"
    require (nearPlanHasHostContext (← nearPlan checked) expectedId)
      s!"{name} HostOp did not survive the NEAR target-plan boundary"
    require ((ProofForge.Compiler.checkHostOpHandlers "evm" checked).any
        (·.contains expectedId.render))
      s!"EVM accepted NEAR HostOp {expectedId.render}"

  IO.println "target-context-hostops: ok"
