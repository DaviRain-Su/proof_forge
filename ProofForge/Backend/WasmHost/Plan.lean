import ProofForge.Backend.WasmHost.Plan.Types

namespace ProofForge.Backend.WasmHost.Plan

open ProofForge.IR

structure ModulePlan where
  contextOps : Array ContextExprPlan
  scalarReadTypes : Array ValueType
  scalarWriteTypes : Array ValueType
  returnTypes : Array ValueType
  usesInputParams : Bool
  usesNativeValue : Bool
  usesStorageRead : Bool
  usesStorageWrite : Bool
  usesPromiseApi : Bool
  usesPromiseCreate : Bool
  usesPromiseThen : Bool
  usesPromiseResults : Bool
  usesPromiseResultU64 : Bool
  usesPromiseReturn : Bool
  usesPromiseReceiverAccount : Bool
  usesStorageUsage : Bool
  usesPromiseTransfer : Bool
  usesCrosscallArgs : Bool
  usesCrosscallHash : Bool
  usesFmtU64 : Bool
  usesEventApi : Bool
  usesEventNumeric : Bool
  usesEventBool : Bool
  usesEventHash : Bool
  u64IndexedReadTypes : Array ValueType
  u64IndexedWriteTypes : Array ValueType
  hashIndexedReadTypes : Array ValueType
  hashIndexedWriteTypes : Array ValueType
  stringIndexedReadTypes : Array ValueType
  stringIndexedWriteTypes : Array ValueType
  usesU64IndexedBuildKey : Bool
  usesHashIndexedBuildKey : Bool
  usesStringIndexedBuildKey : Bool
  usesU64IndexedContains : Bool
  usesHashIndexedContains : Bool
  usesStringIndexedContains : Bool
  usesHashMake : Bool
  usesHashPreimage : Bool
  usesHashTwoToOne : Bool
  usesHashEq : Bool
  usesStrEq : Bool
  usesPowU32 : Bool
  usesPowU64 : Bool
  usesMemcpy : Bool
  arrayLitShapes : Array (ValueType × Nat)
  arrayEqShapes : Array (ValueType × Nat)
  structLitNames : Array String
  usesArrAlloc : Bool
  usesArrDealloc : Bool
  deriving Repr

end ProofForge.Backend.WasmHost.Plan
