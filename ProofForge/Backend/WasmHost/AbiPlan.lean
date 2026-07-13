import ProofForge.IR.Contract

namespace ProofForge.Backend.WasmHost.AbiPlan

open ProofForge.IR

inductive Codec where
  | borsh
  | json
  deriving Repr, BEq

def Codec.id : Codec -> String
  | .borsh => "borsh"
  | .json => "json"

structure ValuePlan where
  name? : Option String := none
  type : ValueType
  offset : Nat
  byteWidth : Nat
  deriving Repr, BEq

structure EntrypointPlan where
  name : String
  inputCodec : Codec
  outputCodec : Codec
  params : Array ValuePlan
  inputByteWidth : Nat
  returnType : ValueType
  outputByteWidth : Nat
  deriving Repr, BEq

end ProofForge.Backend.WasmHost.AbiPlan
