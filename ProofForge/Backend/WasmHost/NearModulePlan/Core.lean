import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
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

def coreTypeToValueTypeWith (materialization : MaterializationContract) :
    CoreType → ValueType
  | .fixedArray element length =>
      .fixedArray (coreTypeToValueTypeWith materialization element) length
  | .array element | .memoryRef element =>
      .array (coreTypeToValueTypeWith materialization element)
  | .structType typeId =>
      .structType ((materialization.typeLayouts.find? (·.typeId == typeId)).map (·.name)
        |>.getD (toString typeId.value))
  | type => coreTypeToValueType type

/-- Build a NearStatePlan from a Core scalar state declaration.
NEAR stores scalars as UTF-8 key strings in the host key-value store.
The key pointer is the string pool offset for the state id string. -/
def coreScalarToNearStatePlan (decl : Core.StateDecl) (name : String)
    (keyPtr : Nat) : Except PlanError NearStatePlan := do
  let vt <- match decl.shape with
    | .scalar ty => pure (coreTypeToValueType ty)
    | _ => throw { message := s!"NEAR scalar layout received non-scalar state {decl.id.value}" }
  return {
    id := name
    coreId? := some decl.id.value
    type := vt
    keyPtr := keyPtr
    keyLen := name.length }

/-- Build a NearMapPlan from a Core map/array state declaration.
NEAR stores maps as `id ++ ":"` prefixed keys. -/
def coreMapToNearMapPlan (decl : Core.StateDecl) (name : String)
    (prefixPtr : Nat) : Except PlanError NearMapPlan := do
  match decl.shape with
  | .map kty vty (some _) =>
      let keyType := coreTypeToValueType kty
      let valueType := coreTypeToValueType vty
      return {
        id := name
        coreId? := some decl.id.value
        keyType := keyType
        valueType := valueType
        prefixPtr := prefixPtr
        prefixLen := name.length + 1
        isArray := false }
  | .fixedArray elem _ =>
      let valueType := coreTypeToValueType elem
      return {
        id := name
        coreId? := some decl.id.value
        keyType := .u64
        valueType := valueType
        prefixPtr := prefixPtr
        prefixLen := name.length + 1
        isArray := true }
  | .map _ _ none => throw { message := "NEAR map state requires a finite capacity contract" }
  | .dynamicArray _ => throw { message := "NEAR dynamic array layout requires an allocator plan" }
  | _ => throw { message := s!"unsupported NEAR state shape for {decl.id.value}" }

/-- Classify a Core state shape as scalar vs map/array. -/
def isScalarShape : StateShape → Bool
  | .scalar _ => true
  | _ => false

private def dedupValueTypes (types : Array ValueType) : Array ValueType :=
  types.foldl (fun result type => if result.contains type then result else result.push type) #[]

/-- Build the NEAR layout plan from Core state declarations.
Scalar states get sequential key pointers; map/array states get
sequential prefix pointers after the scalar key region. -/
def coreLayout (m : ProofForge.IR.Core.Module)
    (materialization : MaterializationContract) : Except PlanError NearLayoutPlan := do
  let mut scalars := #[]
  let mut maps := #[]
  let mut keyPtr := 0  /- Simplified: key strings at offset 0+ -/
  let mut prefixPtr := 1024  /- Prefix strings start at 1024+ -/
  for decl in m.state do
    let symbol ← match materialization.stateSymbols.find? (fun symbol => symbol.stateId == decl.id) with
      | some symbol => pure symbol
      | none => throw { message := s!"missing NEAR state symbol for Core state {decl.id.value}" }
    if isScalarShape decl.shape then
      scalars := scalars.push (<- coreScalarToNearStatePlan decl symbol.name keyPtr)
      keyPtr := keyPtr + symbol.name.length + 1
    else
      maps := maps.push (<- coreMapToNearMapPlan decl symbol.name prefixPtr)
      prefixPtr := prefixPtr + symbol.name.length + 2
  let mut crosscallStrings := #[]
  let mut crosscallPtr := ProofForge.Backend.WasmHost.Memory.CROSSCALL_STRING_BASE
  for value in materialization.crosscallStrings do
    crosscallStrings := crosscallStrings.push { str := value, ptr := crosscallPtr, len := value.length }
    crosscallPtr := crosscallPtr + value.length
  return { scalars := scalars, maps := maps, strings := #[], panics := #[], crosscallStrings, stringPoolEnd := prefixPtr }

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
  let mut usesStorageUsage := false
  let mut usesPromiseTransfer := false
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
        | .storageLoad ref =>
          usesStorageRead := true
          match instr.op with
          | .storageLoad { path := #[.mapKey _], .. }
          | .storageLoad { path := #[.index _], .. } => pure ()
          | _ => scalarReadTypes := scalarReadTypes.push (coreTypeToValueType ref.resultType)
        | .storageStore ref value =>
          usesStorageWrite := true
          match instr.op with
          | .storageStore { path := #[.mapKey _], .. } _
          | .storageStore { path := #[.index _], .. } _ => scalarWriteTypes := scalarWriteTypes
          | _ => scalarWriteTypes := scalarWriteTypes.push (coreTypeToValueType value.type)
        | .storageRemove _ => usesStorageWrite := true
        | .contextRead .value => usesNativeValue := true
        | .contextRead .sender => contextOps := contextOps.push .userId |>.push .userIdHash
        | .contextRead .contractAddress => contextOps := contextOps.push .contractId
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
          if call.id == HostOps.predecessorAccountIdId then contextOps := contextOps.push .accountId
          if call.id == HostOps.currentAccountIdId then contextOps := contextOps.push .currentAccountId
          if call.id == HostOps.epochHeightId then contextOps := contextOps.push .epochHeight
          if call.id == HostOps.randomSeedId then contextOps := contextOps.push .randomSeed
          if call.id == HostOps.prepaidGasId then contextOps := contextOps.push .prepaidGas
          if call.id == HostOps.usedGasId then contextOps := contextOps.push .usedGas
          if call.id == HostOps.promiseCreateId then usesPromiseCreate := true
          if call.id == HostOps.storageUsageId then usesStorageUsage := true
          if call.id == HostOps.promiseTransferId then usesPromiseTransfer := true
        | .crosscall spec _ =>
          if spec.mode == .continuation then pure () else usesPromiseCreate := true
        | _ => pure ()
  {
    contextOps
    scalarReadTypes
    scalarWriteTypes
    returnTypes
    usesInputParams := m.functions.any (fun function => !function.params.isEmpty)
    usesNativeValue
    usesStorageRead
    usesStorageWrite
    u64IndexedReadTypes := dedupValueTypes <| m.functions.flatMap (fun function => function.blocks.flatMap (fun block =>
      block.instructions.filterMap fun instruction => match instruction.op with
        | .storageLoad { path := #[.mapKey key], resultType, .. } =>
            if key.type == .hash then none else some (coreTypeToValueType resultType)
        | .storageLoad { path := #[.index _], resultType, .. } => some (coreTypeToValueType resultType)
        | _ => none))
    u64IndexedWriteTypes := dedupValueTypes <| m.functions.flatMap (fun function => function.blocks.flatMap (fun block =>
      block.instructions.filterMap fun instruction => match instruction.op with
        | .storageStore { path := #[.mapKey key], resultType, .. } _ =>
            if key.type == .hash then none else some (coreTypeToValueType resultType)
        | .storageStore { path := #[.index _], resultType, .. } _ => some (coreTypeToValueType resultType)
        | _ => none))
    usesU64IndexedBuildKey := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .storageLoad { path := #[.mapKey key], .. } => key.type != .hash
        | .storageLoad { path := #[.index _], .. } => true
        | .storageStore { path := #[.mapKey key], .. } _ => key.type != .hash
        | .storageStore { path := #[.index _], .. } _ => true
        | _ => false
    usesPromiseApi := usesPromiseCreate || usesPromiseTransfer
    usesPromiseCreate
    usesPromiseThen := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .crosscall { mode := .continuation, .. } _ => true | _ => false
    usesPromiseResults := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .hostCall call => call.id == HostOps.promiseResultU64Id ||
            call.id == HostOps.promiseResultU128Id ||
            call.id == HostOps.promiseResultsCountId || call.id == HostOps.promiseResultStatusId | _ => false
    usesPromiseResultU64 := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .hostCall call => call.id == HostOps.promiseResultU64Id ||
            call.id == HostOps.promiseResultU128Id | _ => false
    usesPromiseReturn := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .crosscall { mode := .invoke, .. } _ | .crosscall { mode := .continuation, .. } _ => true
        | _ => false
    usesPromiseReceiverAccount := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .crosscall { mode := .continuation, .. } _ => true | _ => false
    usesStorageUsage
    usesPromiseTransfer
    usesCrosscallArgs := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .crosscall { mode := .namedInvoke, .. } _ | .crosscall { mode := .continuation, .. } _ => true
        | _ => false
    usesCrosscallHash := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .crosscall { mode := .namedInvoke, .. } args | .crosscall { mode := .continuation, .. } args =>
            args.any (fun arg => arg.type == .hash)
        | _ => false
    usesFmtU64 := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .crosscall { mode := .namedInvoke, .. } args | .crosscall { mode := .continuation, .. } args =>
            args.any (fun arg => arg.type == .u8 || arg.type == .u32 || arg.type == .u64 || arg.type == .u128)
        | _ => false
    usesEventApi
    usesEventNumeric
    usesEventBool
    usesEventHash := m.events.any fun event => event.fields.any (fun field => field.type == .hash)
    hashIndexedReadTypes := dedupValueTypes <| m.functions.flatMap (fun function => function.blocks.flatMap (fun block =>
      block.instructions.filterMap fun instruction => match instruction.op with
        | .storageLoad { path := #[.mapKey key], resultType, .. } =>
            if key.type == .hash then some (coreTypeToValueType resultType) else none
        | _ => none))
    hashIndexedWriteTypes := dedupValueTypes <| m.functions.flatMap (fun function => function.blocks.flatMap (fun block =>
      block.instructions.filterMap fun instruction => match instruction.op with
        | .storageStore { path := #[.mapKey key], resultType, .. } _ =>
            if key.type == .hash then some (coreTypeToValueType resultType) else none
        | _ => none))
    usesHashIndexedBuildKey := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .storageLoad { path := #[.mapKey key], .. }
        | .storageStore { path := #[.mapKey key], .. } _ => key.type == .hash
        | _ => false
    usesU64IndexedContains := false
    usesHashIndexedContains := false
    stringIndexedReadTypes := dedupValueTypes <| m.functions.flatMap (fun function =>
      function.blocks.flatMap (fun block => block.instructions.filterMap fun instruction =>
        match instruction.op with
        | .storageLoad { path := #[.mapKey key], resultType, .. } =>
            if key.type == .string then some (coreTypeToValueType resultType) else none
        | _ => none))
    stringIndexedWriteTypes := dedupValueTypes <| m.functions.flatMap (fun function =>
      function.blocks.flatMap (fun block => block.instructions.filterMap fun instruction =>
        match instruction.op with
        | .storageStore { path := #[.mapKey key], resultType, .. } _ =>
            if key.type == .string then some (coreTypeToValueType resultType) else none
        | .storageRemove { path := #[.mapKey key], resultType, .. } =>
            if key.type == .string then some (coreTypeToValueType resultType) else none
        | _ => none))
    usesStringIndexedBuildKey := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
      | .storageLoad { path := #[.mapKey key], .. }
      | .storageStore { path := #[.mapKey key], .. } _ => key.type == .string
      | .storageRemove { path := #[.mapKey key], .. } => key.type == .string
      | _ => false
    usesStringIndexedContains := false
    usesHashMake := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .pure (.literal (.hashLit _)) => true
        | _ => false
    usesHashPreimage := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .pure (.hash _) => true | _ => false
    usesHashTwoToOne := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .pure (.hashTwoToOne ..) => true
        | _ => false
    usesHashEq := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .pure (.compare op lhs _) => lhs.type == .hash && (op == .eq || op == .ne)
        | _ => false
    usesStrEq := m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .pure (.compare op lhs _) => lhs.type == .string && (op == .eq || op == .ne)
        | _ => false
    usesPowU32 := false
    usesPowU64 := false
    usesMemcpy := !usesEventApi && m.functions.any fun function => function.blocks.any fun block =>
      block.instructions.any fun instruction => match instruction.op with
        | .pure (.hashTwoToOne ..) => true
        | .storageLoad { path := #[.mapKey key], .. }
        | .storageStore { path := #[.mapKey key], .. } _ => key.type == .hash
        | .crosscall { mode := .namedInvoke, .. } args
        | .crosscall { mode := .continuation, .. } args => args.any (fun arg => arg.type == .hash)
        | _ => false
    arrayLitShapes := #[]
    arrayEqShapes := #[]
    structLitNames := #[]
    usesArrAlloc := m.functions.any (fun fn =>
      fn.params.any (fun p => p.type == .string || p.type == .bytes) ||
      fn.blocks.any (fun block => block.instructions.any fun instruction =>
        match instruction.op with | .pure (.structLit _ _) => true | _ => false))
    usesArrDealloc := false
  }

/-- Build an empty lower context seed. The canonical builder does not store
Legacy `StructDecl` or `AllocatorConfig`; it stores resolved target layout. -/
def coreLowerCtxSeed (m : ProofForge.IR.Core.Module)
    (materialization : MaterializationContract) : NearLowerCtxSeed :=
  { keyBuf := 0, mapkeyBuf := 0, stringBase := 0, crosscallStringBase := 0,
    structs := materialization.typeLayouts.filterMap fun layout => do
      let declaration ← m.structs.find? (·.id == layout.typeId)
      some {
        name := layout.name
        fields := Array.zipWith (fun field metadata => {
          id := metadata.name
          type := coreTypeToValueTypeWith materialization field.type
          isPublic := metadata.isPublic
          isRef := field.ownership == .reference
        }) declaration.fields layout.fields
        deriveStorage := layout.deriveStorage
        isPublic := layout.isPublic
        isRecord := declaration.semantics == .linearRecord
      }
    }

private def nearValue (value : ValueRef) : NearValuePlan :=
  { id := value.id.value, typeName := reprStr value.type }

private def nearResult (instr : Instruction) : Except PlanError NearValuePlan :=
  match instr.results with
  | #[result] => .ok { id := result.id.value, typeName := reprStr result.type }
  | _ => .error { message := "NEAR value-producing operation requires exactly one result" }

private def literalFor (literals : Array (ValueId × CoreLiteral)) (value : ValueRef) :
    Except PlanError CoreLiteral :=
  match literals.find? (fun entry => entry.fst == value.id) with
  | some entry => .ok entry.snd
  | none => .error { message := s!"canonical NEAR HostOp argument {value.id.value} must be a literal" }

private def literalIndex (literal : CoreLiteral) : Except PlanError Nat :=
  match literal with
  | .addressLit value | .stringLit value =>
      match value.toNat? with
      | some index => .ok index
      | none => .error { message := "canonical NEAR crosscall handle must be numeric" }
  | .u8Lit value | .u32Lit value | .u64Lit value | .u128Lit value => .ok value
  | _ => .error { message := "canonical NEAR crosscall handle has an unsupported type" }

private def crosscallJsonLiteral (literal : CoreLiteral) : Except PlanError String :=
  match literal with
  | .boolLit value => .ok (if value then "true" else "false")
  | .u8Lit value | .u32Lit value | .u64Lit value | .u128Lit value => .ok (toString value)
  | _ => .error { message := "canonical NEAR crosscall arguments currently require scalar literals" }

private def nearArithmetic : ArithmeticOp -> NearArithmeticPlan
  | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .mod => .mod
  | .and => .bitAnd | .or => .bitOr | .xor => .bitXor | .shl => .shiftLeft | .shr => .shiftRight

private def nearCompare : CompareOp -> NearComparePlan
  | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge

private def unpackHashLiteral (value : String) : Except PlanError (Nat × Nat × Nat × Nat) := do
  let some word := value.toNat?
    | throw { message := s!"canonical NEAR hash literal `{value}` is not numeric" }
  let base := 18446744073709551616
  let d := word % base
  let word := word / base
  let c := word % base
  let word := word / base
  let b := word % base
  let a := word / base
  if a < base then return (a, b, c, d)
  throw { message := s!"canonical NEAR hash literal `{value}` exceeds 256 bits" }

private def lowerNearOp (iface : InterfaceContract) (materialization : MaterializationContract)
    (literals : Array (ValueId × CoreLiteral)) (instr : Instruction) :
    Except PlanError NearOpPlan := do
  match instr.op with
  | .pure (.literal (.boolLit value)) => return .boolLiteral (<- nearResult instr) value
  | .pure (.literal (.u8Lit value)) | .pure (.literal (.u32Lit value)) |
    .pure (.literal (.u64Lit value)) =>
      return .literal (<- nearResult instr) value
  | .pure (.literal (.u128Lit value)) =>
      /- Wasm locals are at most i64. The full u128 remains attached to the
      typed promise plan; this literal local is only its low word. -/
      return .literal (<- nearResult instr) (value % 18446744073709551616)
  | .pure (.literal (.addressLit value)) =>
      let some handle := value.toNat?
        | throw { message := s!"canonical NEAR address handle `{value}` is not numeric" }
      if handle < 18446744073709551616 then
        return .literal (<- nearResult instr) handle
      else
        throw { message := s!"canonical NEAR address handle `{value}` exceeds u64" }
  | .pure (.literal (.hashLit value)) =>
      let (a, b, c, d) <- unpackHashLiteral value
      return .hashLiteral (<- nearResult instr) a b c d
  | .pure (.literal (.stringLit value)) =>
      return .stringLiteral (<- nearResult instr) value
  | .pure (.literal (.bytesLit _)) =>
      /- Byte literals remain metadata-only on the canonical NEAR path. -/
      return .literal (<- nearResult instr) 0
  | .pure (.arithmetic op mode lhs rhs) =>
      return .arithmetic (<- nearResult instr) (nearArithmetic op) (mode == .checked)
        (nearValue lhs) (nearValue rhs)
  | .pure (.compare op lhs rhs) =>
      return .compare (<- nearResult instr) (nearCompare op) (nearValue lhs) (nearValue rhs)
  | .pure (.hash value) =>
      return .hash (<- nearResult instr) (nearValue value)
  | .pure (.cast _ value) =>
      return .cast (<- nearResult instr) (nearValue value)
  | .pure (.hashTwoToOne lhs rhs) =>
      return .hashTwoToOne (<- nearResult instr) (nearValue lhs) (nearValue rhs)
  | .pure (.structLit typeId fields) =>
      let typeName := (materialization.typeLayouts.find? (·.typeId == typeId)).map (·.name)
        |>.getD s!"type_{typeId.value}"
      return .structLit (<- nearResult instr) typeName (fields.map nearValue)
  | .storageLoad ref =>
      match ref.path with
      | #[] => return .loadState (<- nearResult instr) ref.root.value
      | #[.mapKey key] | #[.index key] =>
          return .loadMap (<- nearResult instr) ref.root.value (nearValue key)
      | _ => throw { message := "NEAR canonical storage supports one mapKey or index segment" }
  | .storageStore ref value =>
      match ref.path with
      | #[] => return .storeState ref.root.value (nearValue value)
      | #[.mapKey key] | #[.index key] =>
          return .storeMap ref.root.value (nearValue key) (nearValue value)
      | _ => throw { message := "NEAR canonical storage supports one mapKey or index segment" }
  | .storageRemove ref =>
      match ref.path with
      | #[.mapKey key] | #[.index key] =>
          return .removeMap ref.root.value (nearValue key)
      | _ => throw { message := "NEAR canonical storage removal supports one mapKey or index segment" }
  | .contextRead field => return .context (<- nearResult instr) (reprStr field)
  | .emit event args =>
      let decl <- match iface.events.find? (fun decl => decl.eventId == event) with
        | some decl => pure decl
        | none => throw { message := s!"missing NEAR interface event {event.value}" }
      unless decl.fields.size == args.size do
        throw { message := s!"NEAR event `{decl.name}` field arity mismatch" }
      return .log decl.name (decl.fields.zip (args.map nearValue) |>.map fun (field, value) => (field.name, value))
  | .assert condition error => return .assert (nearValue condition) error.id.value
  | .hostCall call =>
      let registry ← match HostOps.nearPromiseRegistry with
        | .ok registry => pure registry
        | .error message => throw { message }
      let handler ← match registry.lookup "wasm-near" call.id with
        | some handler => pure handler
        | none => throw { message := s!"missingHostOpHandler: {call.id.render} on target wasm-near" }
      if handler.lower == #[HostOps.NearOpPlan.contextRead] then
        unless call.args.isEmpty do
          throw { message := s!"{call.id.render} requires no arguments" }
        return .hostContext (<- nearResult instr) call.id
      else if call.id == HostOps.promiseCreateId then
        unless handler.lower == #[HostOps.NearOpPlan.promiseCreate] do
          throw { message := s!"invalid HostOp plan for {call.id.render}" }
        unless call.args.size == 5 do
          throw { message := "near.promise.create@1.0.0 requires five arguments" }
        let account ← literalFor literals call.args[0]!
        let method ← literalFor literals call.args[1]!
        let args ← literalFor literals call.args[2]!
        let deposit ← literalFor literals call.args[3]!
        let gas ← literalFor literals call.args[4]!
        match account, method, args, deposit, gas with
        | .stringLit accountId, .stringLit methodName, .bytesLit payload,
            .u128Lit deposit, .u64Lit gas =>
            return .promiseCreate (<- nearResult instr) accountId methodName payload deposit gas
        | _, _, _, _, _ =>
            throw { message := "near.promise.create@1.0.0 literal argument types do not match its signature" }
      else if call.id == HostOps.promiseResultU64Id then
        unless handler.lower == #[HostOps.NearOpPlan.promiseResultU64] do
          throw { message := s!"invalid HostOp plan for {call.id.render}" }
        unless call.args.size == 1 do
          throw { message := "near.promise.result_u64@1.0.0 requires one argument" }
        return .promiseResultU64 (<- nearResult instr) (nearValue call.args[0]!)
      else if call.id == HostOps.promiseResultU128Id then
        unless handler.lower == #[HostOps.NearOpPlan.promiseResultU128] do
          throw { message := s!"invalid HostOp plan for {call.id.render}" }
        unless call.args.size == 1 do
          throw { message := "near.promise.result_u128@1.0.0 requires one argument" }
        return .promiseResultU128 (<- nearResult instr) (nearValue call.args[0]!)
      else if call.id == HostOps.promiseResultsCountId then
        unless handler.lower == #[HostOps.NearOpPlan.promiseResultsCount] && call.args.isEmpty do
          throw { message := "near.promise.results_count@1.0.0 requires no arguments" }
        return .promiseResultsCount (<- nearResult instr)
      else if call.id == HostOps.promiseResultStatusId then
        unless handler.lower == #[HostOps.NearOpPlan.promiseResultStatus] && call.args.size == 1 do
          throw { message := "near.promise.result_status@1.0.0 requires one argument" }
        return .promiseResultStatus (<- nearResult instr) (nearValue call.args[0]!)
      else if call.id == HostOps.storageUsageId then
        unless handler.lower == #[HostOps.NearOpPlan.storageUsage] && call.args.isEmpty do
          throw { message := "near.storage.usage@1.0.0 requires no arguments" }
        return .storageUsage (<- nearResult instr)
      else if call.id == HostOps.promiseTransferId then
        unless handler.lower == #[HostOps.NearOpPlan.promiseTransfer] && call.args.size == 2 do
          throw { message := "near.promise.transfer@1.0.0 requires account and amount" }
        return .promiseTransfer (<- nearResult instr) (nearValue call.args[0]!)
          (nearValue call.args[1]!)
      else
        throw { message := s!"missingHostOpHandler: {call.id.render} on target wasm-near" }
  | .crosscall spec args =>
      match spec.mode with
      | .invoke =>
        let targetIndex ← literalFor literals spec.target >>= literalIndex
        let methodIndex ← literalFor literals spec.method >>= literalIndex
        let accountId ← match materialization.crosscallStrings[targetIndex]? with
          | some value => pure value
          | none => throw { message := s!"canonical NEAR crosscall target handle {targetIndex} is out of range" }
        let methodName ← match materialization.crosscallStrings[methodIndex]? with
          | some value => pure value
          | none => throw { message := s!"canonical NEAR crosscall method handle {methodIndex} is out of range" }
        let encodedArgs ← args.mapM fun argument =>
          literalFor literals argument >>= crosscallJsonLiteral
        let payload := ("[" ++ String.intercalate "," encodedArgs.toList ++ "]").toUTF8
        let result := { (<- nearResult instr) with typeName := "promiseReturn" }
        return .portableCrosscall result accountId methodName payload 0
          ProofForge.Backend.WasmHost.Memory.crosscallDefaultGas
      | .namedInvoke =>
        let deposit ← match spec.value with
          | some value => pure value
          | none => throw { message := "NEAR pool invoke requires a deposit" }
        return .promiseCreatePool (<- nearResult instr) (nearValue spec.target)
          (nearValue spec.method) (args.map nearValue) (nearValue deposit) spec.argNames
      | .continuation =>
        let deposit ← match spec.value with
          | some value => pure value
          | none => throw { message := "NEAR promise_then requires a deposit" }
        let result := { (<- nearResult instr) with typeName := "promiseReturn" }
        return .promiseThen result (nearValue spec.target) (nearValue spec.method)
          (args.map nearValue) (nearValue deposit) spec.argNames
      | mode => throw { message := s!"canonical NEAR crosscall mode `{repr mode}` is unsupported" }
  | op => throw { message := s!"unsupported canonical NEAR operation `{repr op}`" }

private def lowerNearTerminator (promiseReturnIds : Array ValueId) : Terminator -> NearTerminatorPlan
  | .jump target args _ => .jump target.value (args.map nearValue)
  | .branch condition onTrue onFalse => .branch (nearValue condition) onTrue.value onFalse.value
  | .return values => .return (values.map fun value =>
      if promiseReturnIds.contains value.id then
        { (nearValue value) with typeName := "promiseReturn" }
      else nearValue value)
  | .revert error => .revert error.id.value

private def lowerNearFunction (iface : InterfaceContract)
    (materialization : MaterializationContract) (fn : Function) : Except PlanError NearFunctionPlan := do
  let ep <- match iface.entrypoints.find? (fun ep => ep.functionId == fn.id) with
    | some ep => pure ep
    | none => throw { message := s!"missing NEAR interface entrypoint {fn.id.value}" }
  let literals := fn.blocks.flatMap fun block => block.instructions.filterMap fun instruction =>
    match instruction.results, instruction.op with
    | #[result], .pure (.literal literal) => some (result.id, literal)
    | _, _ => none
  let promiseReturnIds := fn.blocks.flatMap fun block => block.instructions.filterMap fun instruction =>
    match instruction.results, instruction.op with
    | #[result], .crosscall { mode := .invoke, .. } _
    | #[result], .crosscall { mode := .continuation, .. } _ => some result.id
    | _, _ => none
  let blocks <- fn.blocks.mapM fun block => do
    let ops <- block.instructions.mapM (lowerNearOp iface materialization literals)
    return {
      id := block.id.value
      params := block.params.map (fun p => { id := p.id.value, typeName := reprStr p.type })
      ops, terminator := lowerNearTerminator promiseReturnIds block.terminator
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
  let lowerCtxSeed := coreLowerCtxSeed m checked.contract.materialization
  /- Build layout from Core state declarations. -/
  let layout <- coreLayout m checked.contract.materialization
  /- Build surface from Core module and interface. -/
  let surface := coreSurface m
  let entrypointAbis ← iface.entrypoints.mapM fun entrypoint =>
    let signatureParams := entrypoint.params.map fun param =>
      (param.name, coreTypeToValueTypeWith checked.contract.materialization param.type)
    match NearAbiPlan.buildSignaturePlan lowerCtxSeed.structs entrypoint.name signatureParams
        (coreTypeToValueTypeWith checked.contract.materialization entrypoint.retType) with
    | .ok plan => pure plan
    | .error message => throw { message }
  let functions <- m.functions.mapM (lowerNearFunction iface checked.contract.materialization)
  .ok {
    moduleName := iface.contractName
    targetId := "wasm-near"
    artifactKind := "wasm-wat"
    irVersion := "canonical-core-v1"
    surface
    entrypointAbis
    layout
    functions
    lowerCtxSeed
  }

end ProofForge.Backend.WasmHost.NearModulePlan.Core
