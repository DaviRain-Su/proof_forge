import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.IR.Allocator
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Target.Plan

/-! # Build Existing NEAR Plan from Canonical Core

This module maps a `CheckedCanonicalContract` to the existing NEAR
`NearModulePlan`. It reuses `NearModulePlan`, `NearStatePlan`,
`NearMapPlan`, `NearLayoutPlan`, and the surface `WasmHost.Plan.ModulePlan`
directly — no parallel plan types.

The Core builder must not consume `IR.Expr`, `IR.Effect`, `IR.Statement`, or
`IR.Module`. All input is typed Core ANF/CFG.
-/

namespace ProofForge.Backend.WasmHost.NearModulePlan.Core

open ProofForge.IR.Core
open ProofForge.IR
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.NearModulePlan

/-- Map a Core type to the IR ValueType (same mapping as EVM/Solana). -/
def coreTypeToValueType : CoreType → ValueType
  | .unit => .unit
  | .bool => .bool
  | .u8 => .u8
  | .u32 => .u32
  | .u64 => .u64
  | .u128 => .u128
  | .address => .address
  | .bytes => .bytes
  | .string => .string
  | .hash => .hash
  | .fixedArray elem len => .fixedArray (coreTypeToValueType elem) len
  | .array elem => .array (coreTypeToValueType elem)
  | .memoryRef elem => .array (coreTypeToValueType elem)
  | .structType tid => .structType (toString tid.value)

/-- Build a NearStatePlan from a Core scalar state declaration.
NEAR stores scalars as UTF-8 key strings in the host key-value store.
The key pointer is the string pool offset for the state id string. -/
def coreScalarToNearStatePlan (decl : Core.StateDecl) (keyPtr : Nat) : NearStatePlan :=
  let idStr := toString decl.id.value
  let vt := match decl.shape with
    | .scalar ty => coreTypeToValueType ty
    | _ => .u64
  { id := idStr, type := vt, keyPtr, keyLen := idStr.length }

/-- Build a NearMapPlan from a Core map/array state declaration.
NEAR stores maps as `id ++ ":"` prefixed keys. -/
def coreMapToNearMapPlan (decl : Core.StateDecl) (prefixPtr : Nat) : NearMapPlan :=
  let idStr := toString decl.id.value
  match decl.shape with
  | .map kty vty _ =>
      { id := idStr, keyType := coreTypeToValueType kty,
        valueType := coreTypeToValueType vty,
        prefixPtr, prefixLen := idStr.length + 1, isArray := false }
  | .fixedArray elem _ =>
      { id := idStr, keyType := .u64, valueType := coreTypeToValueType elem,
        prefixPtr, prefixLen := idStr.length + 1, isArray := true }
  | .dynamicArray elem =>
      { id := idStr, keyType := .u64, valueType := coreTypeToValueType elem,
        prefixPtr, prefixLen := idStr.length + 1, isArray := true }
  | _ =>
      { id := idStr, keyType := .u64, valueType := .u64,
        prefixPtr, prefixLen := idStr.length + 1, isArray := false }

/-- Classify a Core state shape as scalar vs map/array. -/
def isScalarShape : StateShape → Bool
  | .scalar _ => true
  | _ => false

/-- Build the NEAR layout plan from Core state declarations.
Scalar states get sequential key pointers; map/array states get
sequential prefix pointers after the scalar key region. -/
def coreLayout (m : ProofForge.IR.Core.Module) : NearLayoutPlan := Id.run do
  let mut scalars := #[]
  let mut maps := #[]
  let mut keyPtr := 0  /- Simplified: key strings at offset 0+ -/
  let mut prefixPtr := 1024  /- Prefix strings start at 1024+ -/
  for decl in m.state do
    if isScalarShape decl.shape then
      scalars := scalars.push (coreScalarToNearStatePlan decl keyPtr)
      keyPtr := keyPtr + (toString decl.id.value).length + 1
    else
      maps := maps.push (coreMapToNearMapPlan decl prefixPtr)
      prefixPtr := prefixPtr + (toString decl.id.value).length + 2
  /- Build empty string/panic/crosscall pools for the initial fragment. -/
  { scalars, maps,
    strings := #[], panics := #[], crosscallStrings := #[],
    stringPoolEnd := prefixPtr }

/-- Build the WasmHost.Plan.ModulePlan surface from Core.
Maps Core interface and module features to the existing surface flags. -/
def coreSurface (m : ProofForge.IR.Core.Module) (iface : InterfaceContract) : WasmHost.Plan.ModulePlan := Id.run do
  let mut scalarReadTypes := #[]
  let mut scalarWriteTypes := #[]
  let mut returnTypes := #[]
  let mut usesStorageRead := false
  let mut usesStorageWrite := false
  let mut usesNativeValue := false
  let mut usesPromiseCreate := false
  /- Scan all function instructions for storage, context, and host-call usage. -/
  for func in m.functions do
    match func.retType with
    | .unit => returnTypes := returnTypes
    | ty => returnTypes := returnTypes.push (coreTypeToValueType ty)
    for block in func.blocks do
      for instr in block.instructions do
        match instr.op with
        | .storageLoad _ =>
          usesStorageRead := true
          scalarReadTypes := scalarReadTypes.push .u64
        | .storageStore _ _ =>
          usesStorageWrite := true
          scalarWriteTypes := scalarWriteTypes.push .u64
        | .contextRead .value => usesNativeValue := true
        | .hostCall call =>
          if call.id.namespace_ == "near.promise" && call.id.name == "create" then
            usesPromiseCreate := true
        | _ => pure ()
  {
    contextOps := #[]
    scalarReadTypes
    scalarWriteTypes
    returnTypes
    usesNativeValue
    usesStorageRead
    usesStorageWrite
    usesPromiseApi := usesPromiseCreate
    usesPromiseCreate
    usesPromiseThen := false
    usesPromiseResults := false
    usesPromiseResultU64 := false
    usesPromiseReturn := false
    usesPromiseReceiverAccount := false
    usesCrosscallArgs := false
    usesCrosscallHash := false
    usesFmtU64 := false
    usesEventApi := false
    usesEventNumeric := false
    usesEventBool := false
    usesEventHash := false
    u64IndexedReadTypes := #[]
    u64IndexedWriteTypes := #[]
    hashIndexedReadTypes := #[]
    hashIndexedWriteTypes := #[]
    usesU64IndexedBuildKey := false
    usesHashIndexedBuildKey := false
    usesU64IndexedContains := false
    usesHashIndexedContains := false
    usesHashMake := false
    usesHashPreimage := false
    usesHashTwoToOne := false
    usesHashEq := false
    usesPowU32 := false
    usesPowU64 := false
    usesMemcpy := false
    arrayLitShapes := #[]
    arrayEqShapes := #[]
    structLitNames := #[]
    usesArrAlloc := false
    usesArrDealloc := false
  }

/-- Build an empty lower context seed. The canonical builder does not store
Legacy `StructDecl` or `AllocatorConfig`; it stores resolved target layout. -/
def coreLowerCtxSeed : NearLowerCtxSeed :=
  { keyBuf := 0, mapkeyBuf := 0, stringBase := 0, crosscallStringBase := 0,
    structs := #[], allocator := defaultAllocator }

/-- Build a NEAR ModulePlan from a checked canonical contract.
This reuses the existing NearModulePlan structure — no parallel plan types. -/
def buildFromCore (checked : CheckedCanonicalContract)
    (capPlan : CapabilityPlan) :
    Except PlanError NearModulePlan := do
  if capPlan.targetId != "wasm-near" then
    .error { message := s!"NEAR buildFromCore requires target `wasm-near`, got `{capPlan.targetId}`" }
  let m := checked.contract.module
  let iface := checked.contract.interface
  /- Build layout from Core state declarations. -/
  let layout := coreLayout m
  /- Build surface from Core module and interface. -/
  let surface := coreSurface m iface
  .ok {
    moduleName := iface.contractName
    targetId := "wasm-near"
    artifactKind := "wasm-wat"
    irVersion := "canonical-core-v1"
    surface
    layout
    lowerCtxSeed := coreLowerCtxSeed
  }

end ProofForge.Backend.WasmHost.NearModulePlan.Core