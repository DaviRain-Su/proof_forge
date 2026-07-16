import Init.Data.Array.Basic

namespace ProofForge.Contract

/-- How a deploy constructor parameter is written into contract storage.

Today only the EVM materializer consumes these bindings (initcode tail →
storage). The names are target-neutral so future deploy constructors on other
chains can reuse the same intent. -/
inductive ConstructorInitKind where
  | scalarU64
  /-- Store a non-zero ABI `address` word without narrowing. -/
  | addressWord
  /-- Store `keccak256` of a non-zero, zero-padded ABI `address` word. -/
  | addressKeccak
  | stringLength
  | stringKeccak
  | bytesLength
  | bytesKeccak
  | arrayLength
  | arraySumU64
  deriving Repr, BEq

/-- Bind a named constructor parameter to a storage write at deploy time. -/
structure ConstructorInitBinding where
  stateId : String
  paramName : String
  kind : ConstructorInitKind
  deriving Repr, BEq

def ConstructorInitKind.label : ConstructorInitKind → String
  | .scalarU64 => "scalar"
  | .addressWord => "address_word"
  | .addressKeccak => "address_keccak"
  | .stringLength => "length"
  | .stringKeccak => "keccak"
  | .bytesLength => "length"
  | .bytesKeccak => "keccak"
  | .arrayLength => "array_length"
  | .arraySumU64 => "array_sum"

/-- Backward-compatible aliases (historical EVM-prefixed names). -/
abbrev EvmConstructorInitKind := ConstructorInitKind
abbrev EvmConstructorInitBinding := ConstructorInitBinding

def EvmConstructorInitKind.label : EvmConstructorInitKind → String :=
  ConstructorInitKind.label

end ProofForge.Contract
