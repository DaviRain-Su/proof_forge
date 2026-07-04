import Init.Data.Array.Basic

namespace ProofForge.Contract

/-- How a constructor parameter is written into contract storage during deploy. -/
inductive EvmConstructorInitKind where
  | scalarU64
  | stringLength
  | stringKeccak
  | bytesLength
  | bytesKeccak
  | arrayLength
  | arraySumU64
  deriving Repr, BEq

structure EvmConstructorInitBinding where
  stateId : String
  paramName : String
  kind : EvmConstructorInitKind
  deriving Repr, BEq

def EvmConstructorInitKind.label : EvmConstructorInitKind → String
  | .scalarU64 => "scalar"
  | .stringLength => "length"
  | .stringKeccak => "keccak"
  | .bytesLength => "length"
  | .bytesKeccak => "keccak"
  | .arrayLength => "array_length"
  | .arraySumU64 => "array_sum"

end ProofForge.Contract
