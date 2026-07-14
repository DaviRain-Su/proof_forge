import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.Plan.Surface

namespace ProofForge.Backend.WasmHost.Plan

open ProofForge.IR

def buildModulePlan (module : Module) : Except PlanError ModulePlan := do
  let surface ← surfaceFromModule module
  .ok {
    contextOps := surface.contextOps
    scalarReadTypes := surface.scalarReadTypes
    scalarWriteTypes := surface.scalarWriteTypes
    returnTypes := surface.returnTypes
    usesInputParams := module.entrypoints.any (fun entrypoint => !entrypoint.params.isEmpty)
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
    usesStorageUsage := surface.usesStorageUsage
    usesPromiseTransfer := surface.usesPromiseTransfer
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
    stringIndexedReadTypes := surface.stringIndexedReadTypes
    stringIndexedWriteTypes := surface.stringIndexedWriteTypes
    usesU64IndexedBuildKey := surface.usesU64IndexedBuildKey
    usesHashIndexedBuildKey := surface.usesHashIndexedBuildKey
    usesStringIndexedBuildKey := surface.usesStringIndexedBuildKey
    usesU64IndexedContains := surface.usesU64IndexedContains
    usesHashIndexedContains := surface.usesHashIndexedContains
    usesStringIndexedContains := surface.usesStringIndexedContains
    usesHashMake := surface.usesHashMake
    usesHashPreimage := surface.usesHashPreimage
    usesHashTwoToOne := surface.usesHashTwoToOne
    usesHashEq := surface.usesHashEq
    usesStrEq := surface.usesStrEq
    usesPowU32 := surface.usesPowU32
    usesPowU64 := surface.usesPowU64
    usesMemcpy := surface.usesMemcpy
    arrayLitShapes := surface.arrayLitShapes
    arrayEqShapes := surface.arrayEqShapes
    structLitNames := surface.structLitNames
    usesArrAlloc := surface.usesArrAlloc
    usesArrDealloc := surface.usesArrDealloc
  }

end ProofForge.Backend.WasmHost.Plan
