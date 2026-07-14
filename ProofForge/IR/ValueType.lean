import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.Capability

/-! Portable value-shape vocabulary shared by frontends and target plans. -/

namespace ProofForge.IR

inductive ValueType where
  | unit
  | bool
  | u8
  | u32
  | u64
  | u128
  | address
  | bytes
  | string
  | hash
  | fixedArray (element : ValueType) (length : Nat)
  | structType (name : String)
  | array (element : ValueType)
  deriving BEq, DecidableEq, Repr

def ValueType.name : ValueType → String
  | .unit => "Unit"
  | .bool => "Bool"
  | .u8 => "U8"
  | .u32 => "U32"
  | .u64 => "U64"
  | .u128 => "U128"
  | .address => "Address"
  | .bytes => "Bytes"
  | .string => "String"
  | .hash => "Hash"
  | .fixedArray element length => s!"Array<{element.name},{length}>"
  | .structType name => name
  | .array element => s!"Array<{element.name}>"

def ValueType.capabilities : ValueType → Array ProofForge.Target.Capability
  | .unit | .bool | .u8 | .u32 | .u128 | .u64 | .address | .hash => #[]
  | .bytes | .string => #[.dataDynamicBytes]
  | .fixedArray element _ => #[.dataFixedArray] ++ element.capabilities
  | .structType _ => #[.dataStruct]
  | .array element => #[.dataDynamicArray] ++ element.capabilities

/-- Compatibility storage width used by the EVM planner. New target-neutral
code must not treat this as a universal physical width. -/
def ValueType.byteWidth : ValueType → Nat
  | .bool | .u8 => 1
  | .u32 => 4
  | .u64 => 8
  | .u128 => 16
  | .address => 20
  | .hash => 32
  | .unit | .bytes | .string | .fixedArray _ _ | .structType _ | .array _ => 0

def ValueType.isPackedScalar : ValueType → Bool
  | .bool | .u8 | .u32 | .u64 | .u128 | .address => true
  | .unit | .hash | .bytes | .string | .fixedArray _ _ | .structType _ | .array _ => false

def ValueType.isPortableIdentity : ValueType → Bool
  | .address => true
  | _ => false

end ProofForge.IR
