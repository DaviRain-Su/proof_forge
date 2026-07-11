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
def coreScalarToNearStatePlan (decl : Core.StateDecl) (keyPtr : Nat) : Except PlanError NearStatePlan := do
  let idStr := toString decl.id.value
  let vt <- match decl.shape with
    | .scalar ty => pure (coreTypeToValueType ty)
    | _ => throw { message := s!"NEAR scalar layout received non-scalar state {decl.id.value}" }
  return { id := idStr, type := vt, keyPtr, keyLen := idStr.length }

/-- Build a NearMapPlan from a Core map/array state declaration.
NEAR stores maps as `id ++ ":"` prefixed keys. -/
def coreMapToNearMapPlan (decl : Core.StateDecl) (prefixPtr : Nat) : Except PlanError NearMapPlan := do
  let idStr := toString decl.id.value
  match decl.shape with
  | .map kty vty (some _) =>
      let keyType := coreTypeToValueType kty
      let valueType := coreTypeToValueType vty
      return { id := idStr, keyType := keyType, valueType := valueType, prefixPtr := prefixPtr, prefixLen := idStr.length + 1, isArray := false }
  | .fixedArray elem _ =>
      let valueType := coreTypeToValueType elem
      return { id := idStr, keyType := .u64, valueType := valueType, prefixPtr := prefixPtr, prefixLen := idStr.length + 1, isArray := true }
  | .map _ _ none => throw { message := "NEAR map state requires a finite capacity contract" }
  | .dynamicArray _ => throw { message := "NEAR dynamic array layout requires an allocator plan" }
  | _ => throw { message := s!"unsupported NEAR state shape for {decl.id.value}" }

/-- Classify a Core state shape as scalar vs map/array. -/
def isScalarShape : StateShape → Bool
  | .scalar _ => true
  | _ => false

/-- Build the NEAR layout plan from Core state declarations.
Scalar states get sequential key pointers; map/array states get
sequential prefix pointers after the scalar key region. -/
def coreLayout (m : ProofForge.IR.Core.Module) : Except PlanError NearLayoutPlan := do
  let mut scalars := #[]
  let mut maps := #[]
  let mut keyPtr := 0  /- Simplified: key strings at offset 0+ -/
  let mut prefixPtr := 1024  /- Prefix strings start at 1024+ -/
  for decl in m.state do
    if isScalarShape decl.shape then
      scalars := scalars.push (<- coreScalarToNearStatePlan decl keyPtr)
      keyPtr := keyPtr + (toString decl.id.value).length + 1
    else
      maps := maps.push (<- coreMapToNearMapPlan decl prefixPtr)
      prefixPtr := prefixPtr + (toString decl.id.value).length + 2
  /- Build empty string/panic/crosscall pools for the initial fragment. -/
  return { scalars := scalars, maps := maps, strings := #[], panics := #[], crosscallStrings := #[], stringPoolEnd := prefixPtr }

/-- Build the WasmHost.Plan.ModulePlan surface from Core.
Maps Core interface and module features to the existing surface flags. -/
def coreSurface (m : ProofForge.IR.Core.Module) : WasmHost.Plan.ModulePlan := Id.run do
  let mut scalarReadTypes := #[]
  let mut scalarWriteTypes := #[]
  let mut returnTypes := #[]
  let mut usesStorageRead := false
  let mut usesStorageWrite := false
  let mut usesNativeValue := false
  let mut usesPromiseCreate := false
  let mut usesEventApi := false
  let mut usesEventNumeric := false
  let mut usesEventBool := false
  let mut contextOps : Array ContextExprPlan := #[]
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
        | .contextRead .blockNumber => contextOps := contextOps.push .checkpointId
        | .contextRead .blockTimestamp => contextOps := contextOps.push .timestamp
        | .emit event _ =>
          usesEventApi := true
          match m.events.find? (fun decl => decl.id == event) with
          | some decl =>
              if decl.fields.any (fun field => field.type == .bool) then usesEventBool := true
              if decl.fields.any (fun field => field.type == .u8 || field.type == .u32 || field.type == .u64 || field.type == .u128) then
                usesEventNumeric := true
          | none => pure ()
        | .hostCall call =>
          if call.id.namespace_ == "near.promise" && call.id.name == "create" then
            usesPromiseCreate := true
        | _ => pure ()
  {
    contextOps
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
    usesEventApi
    usesEventNumeric
    usesEventBool
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

private def nearValue (value : ValueRef) : NearValuePlan :=
  { id := value.id.value, typeName := reprStr value.type }

private def nearResult (instr : Instruction) : Except PlanError NearValuePlan :=
  match instr.results with
  | #[result] => .ok { id := result.id.value, typeName := reprStr result.type }
  | _ => .error { message := "NEAR value-producing operation requires exactly one result" }

private def nearArithmetic : ArithmeticOp -> NearArithmeticPlan
  | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .mod => .mod
  | .and => .bitAnd | .or => .bitOr | .xor => .bitXor | .shl => .shiftLeft | .shr => .shiftRight

private def nearCompare : CompareOp -> NearComparePlan
  | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge

private def lowerNearOp (iface : InterfaceContract) (instr : Instruction) : Except PlanError NearOpPlan := do
  match instr.op with
  | .pure (.literal (.boolLit value)) => return .boolLiteral (<- nearResult instr) value
  | .pure (.literal (.u8Lit value)) | .pure (.literal (.u32Lit value)) |
    .pure (.literal (.u64Lit value)) | .pure (.literal (.u128Lit value)) =>
      return .literal (<- nearResult instr) value
  | .pure (.arithmetic op mode lhs rhs) =>
      return .arithmetic (<- nearResult instr) (nearArithmetic op) (mode == .checked)
        (nearValue lhs) (nearValue rhs)
  | .pure (.compare op lhs rhs) =>
      return .compare (<- nearResult instr) (nearCompare op) (nearValue lhs) (nearValue rhs)
  | .storageLoad ref =>
      if !ref.path.isEmpty then throw { message := "nested NEAR storage path is not materialized" }
      return .loadState (<- nearResult instr) ref.root.value
  | .storageStore ref value =>
      if !ref.path.isEmpty then throw { message := "nested NEAR storage path is not materialized" }
      return .storeState ref.root.value (nearValue value)
  | .contextRead field => return .context (<- nearResult instr) (reprStr field)
  | .emit event args =>
      let decl <- match iface.events.find? (fun decl => decl.eventId == event) with
        | some decl => pure decl
        | none => throw { message := s!"missing NEAR interface event {event.value}" }
      unless decl.fields.size == args.size do
        throw { message := s!"NEAR event `{decl.name}` field arity mismatch" }
      return .log decl.name (decl.fields.zip (args.map nearValue) |>.map fun (field, value) => (field.name, value))
  | .assert condition error => return .assert (nearValue condition) error.id.value
  | op => throw { message := s!"unsupported canonical NEAR operation `{repr op}`" }

private def lowerNearTerminator : Terminator -> NearTerminatorPlan
  | .jump target args _ => .jump target.value (args.map nearValue)
  | .branch condition onTrue onFalse => .branch (nearValue condition) onTrue.value onFalse.value
  | .return values => .return (values.map nearValue)
  | .revert error => .revert error.id.value

private def lowerNearFunction (iface : InterfaceContract) (fn : Function) : Except PlanError NearFunctionPlan := do
  let ep <- match iface.entrypoints.find? (fun ep => ep.functionId == fn.id) with
    | some ep => pure ep
    | none => throw { message := s!"missing NEAR interface entrypoint {fn.id.value}" }
  let blocks <- fn.blocks.mapM fun block => do
    let ops <- block.instructions.mapM (lowerNearOp iface)
    return {
      id := block.id.value
      params := block.params.map (fun p => { id := p.id.value, typeName := reprStr p.type })
      ops, terminator := lowerNearTerminator block.terminator
    }
  return {
    id := fn.id.value, name := ep.name
    params := fn.params.map (fun p => { id := p.id.value, typeName := reprStr p.type })
    returnType := reprStr fn.retType, blocks
  }

/-- Build a NEAR ModulePlan from a checked canonical contract.
This reuses the existing NearModulePlan structure — no parallel plan types. -/
def buildFromCore (checked : CheckedCanonicalContract)
    (capPlan : CapabilityPlan) :
    Except PlanError NearModulePlan := do
  if capPlan.targetId != "wasm-near" then
    .error { message := s!"NEAR buildFromCore requires target `wasm-near`, got `{capPlan.targetId}`" }
  for requirement in checked.contract.requirements do
    unless capPlan.calls.any (fun call => call.capability == requirement.capability) do
      throw { message := s!"NEAR capability plan is missing `{requirement.capability.id}`" }
  let m := checked.contract.module
  let iface := checked.contract.interface
  /- Build layout from Core state declarations. -/
  let layout <- coreLayout m
  /- Build surface from Core module and interface. -/
  let surface := coreSurface m
  let functions <- m.functions.mapM (lowerNearFunction iface)
  .ok {
    moduleName := iface.contractName
    targetId := "wasm-near"
    artifactKind := "wasm-wat"
    irVersion := "canonical-core-v1"
    surface
    layout
    functions
    lowerCtxSeed := coreLowerCtxSeed
  }

end ProofForge.Backend.WasmHost.NearModulePlan.Core
