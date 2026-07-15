import ProofForgeV2.Targets.Common

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2 Source

def descriptor : TargetDescriptor := {
  targetId := .evm
  artifactEncoding := .evmYul
  executionHost := .evm
  commitModel := .transactionAtomic
  stateBinding := .contractStorage
  callModel := .synchronous
  proofModel := .none
  settlementModel := .ethereum
  codegenProfile := "evm-yul-solc-0.8.34-v1"
  supportedRequirements := #[
    .persistentState, .checkedArithmetic, .transactionalRollback
  ]
}

structure Plan where
  source : SemanticProgram
  storageSlot : Nat
  incrementSelector : String
  getSelector : String
  deriving Inhabited, Repr

structure IR where
  objectName : String
  yul : String
  abi : String
  deriving Inhabited, Repr

def makePlan (resolved : ResolvedProgram .evm) : CompileResult Plan := do
  unless Targets.isExactCounter resolved.source do
    throw <| .planInvariant .evm "v2alpha1 only lowers the exact checked Counter semantics"
  return {
    source := resolved.source
    storageSlot := 0
    incrementSelector := "dd9a82bc"
    getSelector := "6d4ce63c"
  }

private def renderYul (plan : Plan) : String :=
  s!"object \"{plan.source.name}\" \{\n  code \{\n    if callvalue() \{ revert(0, 0) }\n    let programSize := datasize(\"{plan.source.name}\")\n    if iszero(eq(codesize(), add(programSize, 32))) \{ revert(0, 0) }\n    codecopy(0, programSize, 32)\n    let initial := mload(0)\n    if gt(initial, 0xffffffffffffffff) \{ revert(0, 0) }\n    sstore({plan.storageSlot}, initial)\n    datacopy(0, dataoffset(\"runtime\"), datasize(\"runtime\"))\n    return(0, datasize(\"runtime\"))\n  }\n  object \"runtime\" \{\n    code \{\n      if callvalue() \{ revert(0, 0) }\n      if lt(calldatasize(), 4) \{ revert(0, 0) }\n      switch shr(224, calldataload(0))\n      case 0x{plan.incrementSelector} \{\n        if lt(calldatasize(), 36) \{ revert(0, 0) }\n        let old := sload({plan.storageSlot})\n        let delta := calldataload(4)\n        if or(gt(old, 0xffffffffffffffff), gt(delta, 0xffffffffffffffff)) \{ revert(0, 0) }\n        if gt(old, sub(0xffffffffffffffff, delta)) \{ revert(0, 0) }\n        let next := add(old, delta)\n        sstore({plan.storageSlot}, next)\n        mstore(0, next)\n        return(0, 32)\n      }\n      case 0x{plan.getSelector} \{\n        mstore(0, sload({plan.storageSlot}))\n        return(0, 32)\n      }\n      default \{ revert(0, 0) }\n    }\n  }\n}\n"

private def renderAbi (_plan : Plan) : String :=
  "[\n" ++
    "  {\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[{\"name\":\"initial\",\"type\":\"uint64\"}]},\n" ++
    "  {\"type\":\"function\",\"name\":\"increment\",\"stateMutability\":\"nonpayable\",\"inputs\":[{\"name\":\"delta\",\"type\":\"uint64\"}],\"outputs\":[{\"name\":\"\",\"type\":\"uint64\"}]},\n" ++
    "  {\"type\":\"function\",\"name\":\"get\",\"stateMutability\":\"view\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint64\"}]}\n" ++
    "]\n"

def lower (plan : Plan) : CompileResult IR :=
  .ok { objectName := plan.source.name, yul := renderYul plan, abi := renderAbi plan }

def emit (ir : IR) : CompileResult (Array OutputFile) :=
  .ok #[
    { path := s!"{ir.objectName}.yul", mediaType := "text/yul", contents := ir.yul },
    { path := s!"{ir.objectName}.abi.json", mediaType := "application/json", contents := ir.abi }
  ]

instance : Materializer .evm where
  Plan := Plan
  TargetIR := IR
  makePlan := makePlan
  lower := lower
  emit := emit

def materialize (program : SemanticProgram) : CompileResult OutputSet := do
  let resolved ← Targets.resolve descriptor program
  let plan ← makePlan resolved
  let ir ← lower plan
  let files ← emit ir
  return Targets.makeOutput descriptor program false files

end ProofForgeV2.Targets.Evm
