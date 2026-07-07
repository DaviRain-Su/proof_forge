import ProofForge.Backend.WasmNear.Plan.Surface

namespace ProofForge.Backend.WasmNear.Plan

open ProofForge.IR

structure ModulePlan where
  contextOps : Array ContextExprPlan
  scalarReadTypes : Array ValueType
  scalarWriteTypes : Array ValueType
  returnTypes : Array ValueType
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
  usesU64IndexedBuildKey : Bool
  usesHashIndexedBuildKey : Bool
  usesU64IndexedContains : Bool
  usesHashIndexedContains : Bool
  usesHashMake : Bool
  usesHashPreimage : Bool
  usesHashTwoToOne : Bool
  usesHashEq : Bool
  usesPowU32 : Bool
  usesPowU64 : Bool
  usesMemcpy : Bool
  arrayLitShapes : Array (ValueType × Nat)
  arrayEqShapes : Array (ValueType × Nat)
  structLitNames : Array String
  usesArrAlloc : Bool
  usesArrDealloc : Bool
  deriving Repr

def buildModulePlan (module : Module) : Except PlanError ModulePlan := do
  let surface ← surfaceFromModule module
  .ok {
    contextOps := surface.contextOps
    scalarReadTypes := surface.scalarReadTypes
    scalarWriteTypes := surface.scalarWriteTypes
    returnTypes := surface.returnTypes
    usesNativeValue := surface.usesNativeValue
    usesStorageRead := surface.usesStorageRead
    usesStorageWrite := surface.usesStorageWrite
    usesPromiseApi := surface.usesPromiseApi
    usesPromiseCreate := surface.usesPromiseCreate
    usesPromiseThen := surface.usesPromiseThen
    usesPromiseResults := surface.usesPromiseResults
    usesPromiseResultU64 := surface.usesPromiseResultU64
    usesPromiseReturn := surface.usesPromiseReturn
    usesPromiseReceiverAccount := surface.usesPromiseReceiverAccount
    usesCrosscallArgs := surface.usesCrosscallArgs
    usesCrosscallHash := surface.usesCrosscallHash
    usesFmtU64 := surface.usesFmtU64
    usesEventApi := surface.usesEventApi
    usesEventNumeric := surface.usesEventNumeric
    usesEventBool := surface.usesEventBool
    usesEventHash := surface.usesEventHash
    u64IndexedReadTypes := surface.u64IndexedReadTypes
    u64IndexedWriteTypes := surface.u64IndexedWriteTypes
    hashIndexedReadTypes := surface.hashIndexedReadTypes
    hashIndexedWriteTypes := surface.hashIndexedWriteTypes
    usesU64IndexedBuildKey := surface.usesU64IndexedBuildKey
    usesHashIndexedBuildKey := surface.usesHashIndexedBuildKey
    usesU64IndexedContains := surface.usesU64IndexedContains
    usesHashIndexedContains := surface.usesHashIndexedContains
    usesHashMake := surface.usesHashMake
    usesHashPreimage := surface.usesHashPreimage
    usesHashTwoToOne := surface.usesHashTwoToOne
    usesHashEq := surface.usesHashEq
    usesPowU32 := surface.usesPowU32
    usesPowU64 := surface.usesPowU64
    usesMemcpy := surface.usesMemcpy
    arrayLitShapes := surface.arrayLitShapes
    arrayEqShapes := surface.arrayEqShapes
    structLitNames := surface.structLitNames
    usesArrAlloc := surface.usesArrAlloc
    usesArrDealloc := surface.usesArrDealloc
  }

end ProofForge.Backend.WasmNear.Plan
