import ProofForge.IR.ValueType

namespace ProofForge.Backend.WasmHost.Plan

open ProofForge.IR

inductive ContextExprPlan where
  | userId
  | userIdHash
  | accountId
  | currentAccountId
  | contractId
  | checkpointId
  | timestamp
  | epochHeight
  | randomSeed
  | signer
  | prepaidGas
  | usedGas
  deriving BEq, DecidableEq, Repr

def ContextExprPlan.resultType : ContextExprPlan → ValueType
  | .randomSeed | .userIdHash => .hash
  | .accountId | .currentAccountId => .string
  | _ => .u64

end ProofForge.Backend.WasmHost.Plan
