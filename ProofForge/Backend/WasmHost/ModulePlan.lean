import ProofForge.Backend.WasmHost.AbiPlan
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.StructPlan
import ProofForge.IR.Prelude
import ProofForge.Target.HostBridge

/-! Target-neutral data contract consumed by Wasm-host renderers. -/

namespace ProofForge.Backend.WasmHost.ModulePlan

open ProofForge.IR

structure StatePlan where
  id : String
  coreId? : Option Nat := none
  type : ValueType
  keyPtr : Nat
  keyLen : Nat
  packOffset : Nat := 0
  packed : Bool := false
  deriving Repr, BEq

structure MapPlan where
  id : String
  coreId? : Option Nat := none
  keyType : ValueType
  valueType : ValueType
  prefixPtr : Nat
  prefixLen : Nat
  isArray : Bool
  deriving Repr, BEq

structure StringPoolEntry where
  str : String
  ptr : Nat
  len : Nat
  deriving Repr, BEq

structure LayoutPlan where
  scalars : Array StatePlan
  maps : Array MapPlan
  strings : Array StringPoolEntry
  panics : Array StringPoolEntry
  crosscallStrings : Array StringPoolEntry
  stringPoolEnd : Nat
  deriving Repr, BEq

structure ValuePlan where
  id : Nat
  typeName : String
  deriving Repr, BEq, Inhabited

inductive ArithmeticPlan where
  | add | sub | mul | div | mod | bitAnd | bitOr | bitXor | shiftLeft | shiftRight
  deriving Repr, BEq, Inhabited

inductive ComparePlan where
  | eq | ne | lt | le | gt | ge
  deriving Repr, BEq, Inhabited

inductive OpPlan where
  | literal (result : ValuePlan) (value : Nat)
  | stringLiteral (result : ValuePlan) (value : String)
  | hashLiteral (result : ValuePlan) (a b c d : Nat)
  | boolLiteral (result : ValuePlan) (value : Bool)
  | loadState (result : ValuePlan) (stateId : Nat)
  | storeState (stateId : Nat) (value : ValuePlan)
  | loadMap (result : ValuePlan) (stateId : Nat) (key : ValuePlan)
  | storeMap (stateId : Nat) (key value : ValuePlan)
  | removeMap (stateId : Nat) (key : ValuePlan)
  | arithmetic (result : ValuePlan) (op : ArithmeticPlan)
      (checked : Bool) (lhs rhs : ValuePlan)
  | compare (result : ValuePlan) (op : ComparePlan) (lhs rhs : ValuePlan)
  | hashTwoToOne (result : ValuePlan) (lhs rhs : ValuePlan)
  | hash (result value : ValuePlan)
  | cast (result value : ValuePlan)
  | structLit (result : ValuePlan) (typeName : String) (fields : Array ValuePlan)
  | context (result : ValuePlan) (field : String)
  | log (eventName : String) (fields : Array (String × ValuePlan))
  | assert (condition : ValuePlan) (errorCode : Nat)
  | promiseCreate (result : ValuePlan) (accountId methodName : String)
      (args : ByteArray) (deposit gas : Nat)
  | portableCrosscall (result : ValuePlan) (accountId methodName : String)
      (args : ByteArray) (deposit gas : Nat)
  | promiseCreatePool (result : ValuePlan) (accountIndex methodIndex : ValuePlan)
      (args : Array ValuePlan) (deposit : ValuePlan) (argNames : Array String)
  | promiseThen (result : ValuePlan) (parent methodIndex : ValuePlan)
      (args : Array ValuePlan) (deposit : ValuePlan) (argNames : Array String)
  | promiseResultU64 (result index : ValuePlan)
  | promiseResultU128 (result index : ValuePlan)
  | promiseResultsCount (result : ValuePlan)
  | promiseResultStatus (result index : ValuePlan)
  | storageUsage (result : ValuePlan)
  | promiseTransfer (result account amount : ValuePlan)
  deriving Repr, BEq, Inhabited

inductive TerminatorPlan where
  | jump (target : Nat) (args : Array ValuePlan)
  | branch (condition : ValuePlan) (ifTrue ifFalse : Nat)
  | return (values : Array ValuePlan)
  | revert (errorCode : Nat)
  deriving Repr, BEq, Inhabited

structure BlockPlan where
  id : Nat
  params : Array ValuePlan
  ops : Array OpPlan
  terminator : TerminatorPlan
  deriving Repr, BEq, Inhabited

structure FunctionPlan where
  id : Nat
  name : String
  params : Array ValuePlan
  returnType : String
  blocks : Array BlockPlan
  deriving Repr, BEq, Inhabited

structure LowerCtxSeed where
  keyBuf : Nat
  mapkeyBuf : Nat
  stringBase : Nat
  crosscallStringBase : Nat
  structs : Array ProofForge.Backend.WasmHost.StructPlan.Struct
  deriving Repr

structure HostBridgePlan where
  targetId : String
  bridge : ProofForge.Target.HostBridge
  deriving Repr, BEq

structure WasmHostModulePlan where
  moduleName : String
  targetId : String
  artifactKind : String
  irVersion : String
  surface : ProofForge.Backend.WasmHost.Plan.ModulePlan
  entrypointAbis : Array ProofForge.Backend.WasmHost.AbiPlan.EntrypointPlan
  layout : LayoutPlan
  functions : Array FunctionPlan := #[]
  lowerCtxSeed : LowerCtxSeed
  hostBridge : HostBridgePlan := { targetId := "wasm-near", bridge := .near }
  deriving Repr

def bridgeForTarget (targetId : String) : Except String HostBridgePlan :=
  match targetId with
  | "wasm-near" => .ok { targetId, bridge := .near }
  | "wasm-stellar-soroban" => .ok { targetId, bridge := .soroban }
  | "wasm-cosmwasm" => .ok { targetId, bridge := .cosmWasm }
  | _ => .error s!"no Wasm-host bridge for target `{targetId}`"

end ProofForge.Backend.WasmHost.ModulePlan
