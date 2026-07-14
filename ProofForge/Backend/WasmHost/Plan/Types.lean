import ProofForge.IR.ValueType

namespace ProofForge.Backend.WasmHost.Plan

open ProofForge.IR

inductive ContextExprPlan where
  | userId
  | userIdHash
  | accountId
  | contractId
  | checkpointId
  | timestamp
  | epochHeight
  | randomSeed
  | origin
  | prepaidGas
  | usedGas
  deriving BEq, DecidableEq, Repr

def ContextExprPlan.resultType : ContextExprPlan → ValueType
  | .randomSeed | .userIdHash => .hash
  | .accountId => .string
  | _ => .u64

end ProofForge.Backend.WasmHost.Plan
