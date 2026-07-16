import ProofForge.Compiler.Leo.AST.Core

namespace ProofForge.Compiler.Leo.AST

inductive IntegerType where
  | u8 | u16 | u32 | u64 | u128 | i8 | i16 | i32 | i64
  deriving BEq, Repr, Inhabited

inductive LeoType where
  | address
  | array (element : LeoType) (length : Nat)
  | boolean
  | composite (name : Identifier)
  | field
  | future (inputs : Array LeoType) (output : LeoType)
  | group
  | integer (t : IntegerType)
  | mapping (key value : LeoType)
  | scalar
  | signature
  | string
  | tuple (ts : Array LeoType)
  | unit
  | err
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
