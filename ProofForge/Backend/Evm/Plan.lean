import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Backend.Evm.Plan.Storage
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Backend.Evm.Plan

open ProofForge.IR
open ProofForge.Target

/-! ## CrosscallMode / CreateMode: planned call kinds -/

inductive CrosscallMode where
  | call
  | callValue
  | staticcall
  | delegatecall
  deriving BEq, Repr

inductive CreateMode where
  | create
  | create2
  deriving BEq, Repr

/-! ## ExprPlan: target-semantic expression plan

The `ExprPlan` layer represents EVM expressions *after* validation and helper
discovery but *before* final Yul AST construction. Each constructor names an EVM
concept (e.g. `mapSlot`, `checkedAdd`, `crosscall`) rather than a raw Yul
builtin. The `ToYul` pass decides which Yul builtins or helper calls realize
each plan node. -/

mutual
  inductive ContextExprPlan where
    | userId
    /-- Identity-width caller digest: `keccak256` of the 32-byte zero-padded
    `caller` word (`hashWord(caller)`). Product path for OwnableHash /
    `callerHash` on EVM — distinct from raw address-width `userId`. -/
    | userIdHash
    | contractId
    | checkpointId
    | timestamp
    | chainId
    | gasPrice
    | gasLeft
    | prepaidGas
    | usedGas
    | baseFee
    | prevRandao
    | origin
    | coinbase
    | blockHash (blockNumber : ExprPlan)
    deriving Repr

  inductive ExprPlan where
    | literalWord (value : Nat)
    | local (name : String)
    | calldataWord (paramIndex : Nat)
    | storageLoad (slot : StorageSlotPlan)
    | builtin (name : String) (args : Array ExprPlan)
    | helperCall (helper : Helper) (args : Array ExprPlan)
    | checkedArith (op : AssignOp) (lhs rhs : ExprPlan)
        (overflowChecked : Bool := true) (resultByteWidth? : Option Nat := none)
    | hashPack (a b c d : ExprPlan)
    | context (field : ContextExprPlan)
    | crosscall (mode : CrosscallMode) (target methodId : ExprPlan)
        (callValue? : Option ExprPlan) (args : Array CrosscallArgWordPlan) (returnType : ValueType)
    | create (mode : CreateMode) (callValue : ExprPlan) (salt? : Option ExprPlan)
        (initCodeHex : String)
    | cast (source : ExprPlan) (target : ValueType)
    | structField (base : ExprPlan) (fieldName : String)
    | arrayGet (array index : ExprPlan)
    | localArrayGet (name : String) (path : Array ExprPlan) (lengths : Array Nat)
    | arrayLit (elementType : ValueType) (values : Array ExprPlan)
    | memoryArrayNew (elementType : ValueType) (length : ExprPlan)
    | memoryArrayLength (array : ExprPlan)
    | memoryArrayGet (array index : ExprPlan)
    | structLit (typeName : String) (fields : Array (String × ExprPlan))
    | hashValue (a b c d : ExprPlan)
    | hash (preimage : ExprPlan)
    | hashTwoToOne (lhs rhs : ExprPlan)
    | ecrecover (digest v r s : ExprPlan)
    | eip712PermitDigest (owner spender value nonce deadline domainSep : ExprPlan)
    /-- ABI-packed CALL: static stores; optional runtime length + targets. -/
    | crosscallAbiPacked (target : ExprPlan) (selector : Nat)
        (stores : Array (Nat × Nat)) (argsSize : Nat) (outSize : Nat)
        (dynLenOffset? : Option Nat) (dynLen? : Option ExprPlan)
        (dynTargetOffsets : Array Nat) (dynTargets : Array ExprPlan)
    | nativeValue
    | effect (effect : EffectPlan)
    deriving Repr

  structure FixedArrayAssignmentSourcePlan where
    index : Nat
    expr : ExprPlan
    deriving Repr

  structure NestedFixedArrayAssignmentSourcePlan where
    path : Array Nat
    fieldName? : Option String
    expr : ExprPlan
    deriving Repr

  structure StructAssignmentSourcePlan where
    fieldName : String
    expr : ExprPlan
    deriving Repr

  structure StructArrayAssignmentSourcePlan where
    index : Nat
    fieldName : String
    expr : ExprPlan
    deriving Repr

  structure StorageStructWriteFieldPlan where
    slot : Nat
    fieldName : String
    value : ExprPlan
    deriving Repr

  inductive AbiValuePlan where
    | expr (value : ExprPlan)
    | local (name : String) (type : ValueType)
    | storage (stateId : String) (type : ValueType)
    | arrayLit (elementType : ValueType) (values : Array AbiValuePlan)
    | structLit (typeName : String) (fields : Array (String × AbiValuePlan))
    deriving Repr

  inductive CrosscallArgWordPlan where
    | expr (value : ExprPlan)
    | local (name : String) (type : ValueType)
    | storage (stateId : String) (type : ValueType)
    deriving Repr

  inductive StorageSlotExprPlan where
    | scalarSlot (slot : Nat)
    | fixedSlot (slotHex : String)
    | mapValueSlot (rootSlot : Nat) (keys : Array ExprPlan)
    | mapPresenceSlot (rootSlot : Nat) (keys : Array ExprPlan)
    | arraySlot (rootSlot length : Nat) (index : ExprPlan)
    | structArrayFieldSlot (rootSlot length fieldCount fieldOffset : Nat) (index : ExprPlan)
    | dynamicArraySlot (rootSlot : Nat) (index : ExprPlan)
    deriving Repr

  inductive StoragePathWriteExprTargetPlan where
    | mapWrite (rootSlot : Nat) (key : ExprPlan)
    | singleSlot (slot : StorageSlotExprPlan)
    | mapValuePresence (valueSlot presenceSlot : StorageSlotExprPlan)
    deriving Repr

  inductive EffectPlan where
    | storageScalarRead (stateId : String)
    | storageScalarReadTarget (target : ScalarStorageTargetPlan)
    | storageScalarWrite (stateId : String) (value : ExprPlan)
    | storageScalarWriteTarget (target : ScalarStorageTargetPlan) (value : ExprPlan)
    | storageScalarAssignOp (stateId : String) (op : AssignOp) (value : ExprPlan)
    | storageScalarAssignOpTarget (target : ScalarStorageTargetPlan) (op : AssignOp) (value : ExprPlan)
    | storageMapContains (stateId : String) (key : ExprPlan)
    | storageMapContainsTarget (target : MapReadTargetPlan) (key : ExprPlan)
    | storageMapGet (stateId : String) (key : ExprPlan)
    | storageMapGetTarget (target : MapReadTargetPlan) (key : ExprPlan)
    | storageMapInsert (stateId : String) (key value : ExprPlan)
    | storageMapInsertTarget (target : MapWriteTargetPlan) (key value : ExprPlan)
    | storageMapSet (stateId : String) (key value : ExprPlan)
    | storageMapSetTarget (target : MapWriteTargetPlan) (key value : ExprPlan)
    | storageMapDelete (stateId : String) (key : ExprPlan)
    | storageMapDeleteTarget (target : MapWriteTargetPlan) (key : ExprPlan)
    | storageArrayRead (stateId : String) (index : ExprPlan)
    | storageArrayReadTarget (target : ArrayReadTargetPlan) (index : ExprPlan)
    | storageArrayWrite (stateId : String) (index value : ExprPlan)
    | storageArrayWriteTarget (target : ArrayWriteTargetPlan) (index value : ExprPlan)
    | storageArrayStructFieldRead (stateId : String) (index : ExprPlan) (fieldName : String)
    | storageArrayStructFieldReadTarget (target : StructArrayFieldReadTargetPlan) (index : ExprPlan)
    | storageArrayStructFieldWrite (stateId : String) (index : ExprPlan) (fieldName : String) (value : ExprPlan)
    | storageArrayStructFieldWriteTarget (target : StructArrayFieldWriteTargetPlan) (index value : ExprPlan)
    | storageDynamicArrayPush (stateId : String) (value : ExprPlan)
    | storageDynamicArrayPushTarget (target : DynamicArrayTargetPlan) (value : ExprPlan)
    | storageDynamicArrayPop (stateId : String)
    | storageDynamicArrayPopTarget (target : DynamicArrayTargetPlan)
    | memoryArraySet (array index value : ExprPlan)
    | storageStructFieldRead (stateId fieldName : String)
    | storageStructFieldReadTarget (target : StructFieldReadTargetPlan)
    | storageStructFieldWrite (stateId fieldName : String) (value : ExprPlan)
    | storageStructFieldWriteTarget (target : StructFieldWriteTargetPlan) (value : ExprPlan)
    | storagePathRead (stateId : String) (path : Array StoragePathSegment)
    | storagePathReadTarget (slot : StorageSlotPlan)
    | storagePathReadExprTarget (slot : StorageSlotExprPlan)
    | storagePathWrite (stateId : String) (path : Array StoragePathSegment) (value : ExprPlan)
    | storagePathWriteTarget (target : StoragePathWriteTargetPlan) (value : ExprPlan)
    | storagePathWriteExprTarget (target : StoragePathWriteExprTargetPlan) (value : ExprPlan)
    | storagePathAssignOp (stateId : String) (path : Array StoragePathSegment) (op : AssignOp) (value : ExprPlan)
    | storagePathAssignOpTarget (target : StoragePathWriteTargetPlan) (op : AssignOp) (value : ExprPlan)
    | storagePathAssignOpExprTarget (target : StoragePathWriteExprTargetPlan) (op : AssignOp) (value : ExprPlan)
    | contextRead (field : ContextExprPlan)
    | eventEmit (event : EventPlan) (dataFields : Array AbiValuePlan)
    | eventEmitIndexed (event : EventPlan) (indexedFields dataFields : Array AbiValuePlan)
    | eventEmitWords (event : EventPlan) (dataFieldWords : Array (Array ExprPlan))
    | eventEmitIndexedWords (event : EventPlan) (indexedFieldWords dataFieldWords : Array (Array ExprPlan))
    | checkErc721Received (operator fromAddr toAddr tokenId : ExprPlan)
    | checkErc1155Received (operator fromAddr toAddr id amount : ExprPlan)
    | checkErc1155BatchReceived (operator fromAddr toAddr ids amounts : ExprPlan)
    deriving Repr

  inductive EventFieldPlan where
    | of (name : String) (type : ValueType) (indexed : Bool) (abiType? : Option String)
    deriving Repr

  inductive EventPlan where
    | of (name : String) (signature : String) (fields : Array EventFieldPlan)
    deriving Repr
end

def EventFieldPlan.mk (name : String) (type : ValueType) (indexed : Bool) : EventFieldPlan :=
  .of name type indexed none

def EventFieldPlan.withAbiType (field : EventFieldPlan) (abiType : String) : EventFieldPlan :=
  match field with
  | .of name type indexed _ => .of name type indexed (some abiType)

instance : Inhabited EventFieldPlan := ⟨EventFieldPlan.mk "" .unit false⟩

def EventFieldPlan.name : EventFieldPlan → String
  | .of name _ _ _ => name

def EventFieldPlan.type : EventFieldPlan → ValueType
  | .of _ type _ _ => type

def EventFieldPlan.indexed : EventFieldPlan → Bool
  | .of _ _ indexed _ => indexed

def EventFieldPlan.abiType? : EventFieldPlan → Option String
  | .of _ _ _ abiType? => abiType?

private def splitTopLevelEventTypes (chars : List Char) : Array String := Id.run do
  let mut types : Array String := #[]
  let mut current : List Char := []
  let mut depth := 0
  for char in chars do
    if char == ',' && depth == 0 then
      types := types.push (String.ofList current.reverse)
      current := []
    else
      current := char :: current
      if char == '(' then
        depth := depth + 1
      else if char == ')' then
        depth := depth - 1
  if !current.isEmpty then
    types := types.push (String.ofList current.reverse)
  pure types

def eventSignatureAbiTypes (signature : String) : Array String :=
  match signature.splitOn "(" with
  | _ :: tail =>
      let argsWithClose := String.intercalate "(" tail
      if argsWithClose.endsWith ")" then
        splitTopLevelEventTypes (argsWithClose.dropEnd 1 |>.toString.toList)
      else
        #[]
  | [] => #[]

def EventPlan.mk (name signature : String) (fields : Array EventFieldPlan) : EventPlan :=
  let abiTypes := eventSignatureAbiTypes signature
  let fields := fields.mapIdx fun index field =>
    match abiTypes[index]? with
    | some abiType => field.withAbiType abiType
    | none => field
  .of name signature fields

instance : Inhabited EventPlan := ⟨EventPlan.mk "" "" #[]⟩

def EventPlan.name : EventPlan → String
  | .of name _ _ => name

def EventPlan.signature : EventPlan → String
  | .of _ signature _ => signature

def EventPlan.fields : EventPlan → Array EventFieldPlan
  | .of _ _ fields => fields

def EventPlan.indexedFields (event : EventPlan) : Array EventFieldPlan :=
  event.fields.foldl
    (fun acc field => if field.indexed then acc.push field else acc)
    #[]

def EventPlan.dataFields (event : EventPlan) : Array EventFieldPlan :=
  event.fields.foldl
    (fun acc field => if field.indexed then acc else acc.push field)
    #[]

inductive StoragePathPlanSegment where
  | mapKey (key : ExprPlan)
  | index (index : ExprPlan)
  | field (fieldName : String)
  deriving Repr

def StorageSlotExprPlan.keyCount : StorageSlotExprPlan → Nat
  | .scalarSlot _ => 0
  | .fixedSlot _ => 0
  | .mapValueSlot _ keys => keys.size
  | .mapPresenceSlot _ keys => keys.size
  | .arraySlot .. => 0
  | .structArrayFieldSlot .. => 0
  | .dynamicArraySlot .. => 0

def StorageSlotExprPlan.requiredHelpers : StorageSlotExprPlan → HelperSet
  | .scalarSlot _ => #[]
  | .fixedSlot _ => #[]
  | .mapValueSlot _ _ => #[Helper.mapSlot]
  | .mapPresenceSlot _ keys =>
      let helpers : HelperSet := #[Helper.mapPresenceSlot]
      if keys.size > 1 then
        HelperSet.insert helpers Helper.mapSlot
      else
        helpers
  | .arraySlot .. => #[Helper.arraySlot]
  | .structArrayFieldSlot .. => #[Helper.structArraySlot]
  | .dynamicArraySlot .. => #[Helper.dynamicArraySlot]

def storagePathPlanMapKeys? (path : Array StoragePathPlanSegment) : Option (Array ExprPlan) :=
  go 0 #[]
where
  go (idx : Nat) (acc : Array ExprPlan) : Option (Array ExprPlan) :=
    if h : idx < path.size then
      match path[idx] with
      | .mapKey key => go (idx + 1) (acc.push key)
      | .field _ | .index _ => none
    else if acc.isEmpty then
      none
    else
      some acc

def mapValueSlotExprPlan
    (module : Module)
    (stateId : String)
    (keys : Array ExprPlan) : Except PlanError StorageSlotExprPlan := do
  let mapState ← requireMapState module stateId
  if keys.isEmpty then
    .error { message := s!"EVM map storage path for '{stateId}' must contain at least one mapKey segment" }
  else
    .ok (.mapValueSlot mapState.rootSlot keys)

def mapPresenceSlotExprPlan
    (module : Module)
    (stateId : String)
    (keys : Array ExprPlan) : Except PlanError StorageSlotExprPlan := do
  let mapState ← requireMapState module stateId
  if keys.isEmpty then
    .error { message := s!"EVM map storage path for '{stateId}' must contain at least one mapKey segment" }
  else
    .ok (.mapPresenceSlot mapState.rootSlot keys)

def storagePathMapValueSlotExprPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathPlanSegment) : Except PlanError StorageSlotExprPlan :=
  match storagePathPlanMapKeys? path with
  | some keys => mapValueSlotExprPlan module stateId keys
  | none =>
      .error { message := "EVM plan supports map storage paths only as one or more mapKey segments" }

def storagePathMapPresenceSlotExprPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathPlanSegment) : Except PlanError StorageSlotExprPlan :=
  match storagePathPlanMapKeys? path with
  | some keys => mapPresenceSlotExprPlan module stateId keys
  | none =>
      .error { message := "EVM plan supports map storage paths only as one or more mapKey segments" }

def arraySlotExprPlan (module : Module) (stateId : String) (index : ExprPlan) :
    Except PlanError StorageSlotExprPlan := do
  let (slot, length, _) ← requireArrayState module stateId
  .ok (.arraySlot slot length index)

def dynamicArraySlotExprPlan (module : Module) (stateId : String) (index : ExprPlan) :
    Except PlanError StorageSlotExprPlan := do
  let (slot, _) ← requireDynamicArrayState module stateId
  .ok (.dynamicArraySlot slot index)

def structArrayFieldSlotExprPlan
    (module : Module)
    (stateId : String)
    (index : ExprPlan)
    (fieldName : String) : Except PlanError StorageSlotExprPlan := do
  let (slot, length, fieldCount, fieldOffset, _) ← requireStructArrayStateField module stateId fieldName
  .ok (.structArrayFieldSlot slot length fieldCount fieldOffset index)

def structFieldSlotExprPlan
    (module : Module)
    (stateId fieldName : String) : Except PlanError StorageSlotExprPlan := do
  let (slot, _) ← requireStructStateField module stateId fieldName
  .ok (.scalarSlot slot)

def storagePathWriteExprTargetPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathPlanSegment) : Except PlanError StoragePathWriteExprTargetPlan :=
  match path.toList with
  | [StoragePathPlanSegment.mapKey key] => do
      let mapState ← requireMapState module stateId
      .ok (.mapWrite mapState.rootSlot key)
  | [StoragePathPlanSegment.index index] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .array _ => .ok (.singleSlot (← arraySlotExprPlan module stateId index))
      | .dynamicArray => .ok (.singleSlot (← dynamicArraySlotExprPlan module stateId index))
      | .scalar | .map _ _ => .error { message := s!"storage path state `{stateId}` does not support index access" }
  | [StoragePathPlanSegment.field fieldName] => do
      .ok (.singleSlot (← structFieldSlotExprPlan module stateId fieldName))
  | [StoragePathPlanSegment.index index, StoragePathPlanSegment.field fieldName] => do
      .ok (.singleSlot (← structArrayFieldSlotExprPlan module stateId index fieldName))
  | [] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .map _ _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | .array _ => .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
      | .dynamicArray => .error { message := s!"storage path state `{stateId}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage paths" }
      | .scalar => .error { message := "scalar storage paths are not supported by IR EVM v0; use storage.scalar.write" }
  | _ =>
      match storagePathPlanMapKeys? path with
      | some _ => do
          .ok (.mapValuePresence
            (← storagePathMapValueSlotExprPlan module stateId path)
            (← storagePathMapPresenceSlotExprPlan module stateId path))
      | none =>
          .error { message := "EVM IR v0 supports storage paths as one or more mapKey segments, index, field, or index followed by field" }

def storagePathReadExprSlotPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathPlanSegment) : Except PlanError StorageSlotExprPlan :=
  match path.toList with
  | [StoragePathPlanSegment.mapKey key] =>
      mapValueSlotExprPlan module stateId #[key]
  | [StoragePathPlanSegment.index index] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .array _ => arraySlotExprPlan module stateId index
      | .dynamicArray => dynamicArraySlotExprPlan module stateId index
      | .scalar | .map _ _ => .error { message := s!"storage path state `{stateId}` does not support index access" }
  | [StoragePathPlanSegment.field fieldName] =>
      structFieldSlotExprPlan module stateId fieldName
  | [StoragePathPlanSegment.index index, StoragePathPlanSegment.field fieldName] =>
      structArrayFieldSlotExprPlan module stateId index fieldName
  | [] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .map _ _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | .array _ => .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
      | .dynamicArray => .error { message := s!"storage path state `{stateId}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage paths" }
      | .scalar => .error { message := "scalar storage paths are not supported by IR EVM v0; use storage.scalar.read" }
  | _ =>
      match storagePathPlanMapKeys? path with
      | some _ =>
          storagePathMapValueSlotExprPlan module stateId path
      | none =>
          .error { message := "EVM IR v0 supports storage paths as one or more mapKey segments, index, field, or index followed by field" }

/-! ## CrosscallHelperSpec / CreateHelperSpec: helper function specs (no ExprPlan) -/

structure CrosscallHelperSpec where
  arity : Nat
  returnType : ValueType
  wordTypes : Array ValueType
  mode : CrosscallMode := .call
  plainTransfer : Bool := false
  deriving BEq, Repr

structure CreateHelperSpec where
  mode : CreateMode
  initCodeHex : String
  deriving BEq, Repr

instance : BEq CreateHelperSpec := ⟨fun a b => a.mode == b.mode && a.initCodeHex == b.initCodeHex⟩

/-- ABI-packed CALL helper (static args; optional runtime length + targets). -/
structure AbiPackedHelperSpec where
  selector : Nat
  stores : Array (Nat × Nat)
  argsSize : Nat
  outSize : Nat
  /-- Args-region offset of the Call[] length word (e.g. `0x20` for aggregate). -/
  dynLenOffset? : Option Nat := none
  /-- Args-region offsets of each Call.address word to overwrite at runtime. -/
  dynTargetOffsets : Array Nat := #[]
  deriving BEq, Repr

instance : BEq AbiPackedHelperSpec :=
  ⟨fun a b =>
    a.selector == b.selector && a.stores == b.stores &&
      a.argsSize == b.argsSize && a.outSize == b.outSize &&
      a.dynLenOffset? == b.dynLenOffset? &&
      a.dynTargetOffsets == b.dynTargetOffsets⟩

/-! ## StmtPlan: target-semantic statement plan -/

inductive StmtPlan where
  | letBind (name : String) (type : ValueType) (value : ExprPlan)
  | letMutBind (name : String) (type : ValueType) (value : ExprPlan)
  | assign (target : ExprPlan) (value : ExprPlan)
  | assignOp (target : ExprPlan) (op : AssignOp) (value : ExprPlan)
  | effect (effect : EffectPlan)
  | assert (condition : ExprPlan) (message : String) (errorRef? : Option ProofForge.IR.ErrorRef)
  | assertEq (lhs rhs : ExprPlan) (message : String) (errorRef? : Option ProofForge.IR.ErrorRef)
  | release (name : String)
  | revert (message : String)
  | revertWithError (errorRef : ProofForge.IR.ErrorRef)
  | ifElse (condition : ExprPlan) (thenBody elseBody : Array StmtPlan)
  | boundedFor (indexName : String) (start stopExclusive : Nat) (body : Array StmtPlan)
  | return (value : ExprPlan)
  deriving Repr

/-! ## EntrypointPlan: planned EVM entrypoint with selector and ABI -/

structure AbiParamPlan where
  name : String
  type : ValueType
  /-- Host ABI scalar override carried from `Entrypoint.paramAbiWords`.
  This must survive planning because fixed bytes and addresses have canonical
  calldata encodings that differ from their portable IR carrier type. -/
  abiWord? : Option String := none
  wordTypes : Array ValueType
  headWordIndex : Nat
  localNames : Array String
  deriving Repr

instance : Inhabited AbiParamPlan := ⟨{
  name := "",
  type := .unit,
  abiWord? := none,
  wordTypes := #[],
  headWordIndex := 0,
  localNames := #[]
}⟩

def abiTypeIsDynamic : ValueType → Bool
  | .bytes | .string | .array _ => true
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .unit | .fixedArray _ _ | .structType _ => false

def dynamicParamLengthName (name : String) : String :=
  s!"__pf_param_{name}_length"

def dynamicParamDataPtrName (name : String) : String :=
  s!"__pf_param_{name}_data_ptr"

def AbiParamPlan.isDynamic (param : AbiParamPlan) : Bool :=
  abiTypeIsDynamic param.type

def AbiParamPlan.headWordCount (param : AbiParamPlan) : Nat :=
  if param.isDynamic then 1 else param.wordTypes.size

structure ReturnPlan where
  returnType : ValueType
  wordTypes : Array ValueType
  localNames : Array String
  deriving Repr

structure CrosscallReturnAssignmentPlan where
  returns : ReturnPlan
  mode : CrosscallMode
  target : ExprPlan
  methodId : ExprPlan
  callValue? : Option ExprPlan
  args : Array CrosscallArgWordPlan
  deriving Repr

structure ReturnValueWordPlan where
  returns : ReturnPlan
  source : AbiValuePlan
  deriving Repr

instance : Inhabited ReturnPlan := ⟨{ returnType := .unit, wordTypes := #[], localNames := #[] }⟩

def abiReturnName (index : Nat) : String :=
  s!"__pf_return_{index}"

def returnLocalNames (returnType : ValueType) (wordTypes : Array ValueType) : Array String :=
  match returnType with
  | .unit => #[]
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string | .array _ => #["__pf_result"]
  | .fixedArray _ _ | .structType _ =>
      Id.run do
        let mut names : Array String := #[]
        for _h : idx in [0:wordTypes.size] do
          names := names.push (abiReturnName idx)
        names

structure EntrypointPlan where
  name : String
  selector : String
  params : Array AbiParamPlan
  returns : ReturnPlan
  body : Array StmtPlan
  deriving Repr

instance : Inhabited EntrypointPlan := ⟨{ name := "", selector := "", params := #[], returns := default, body := #[] }⟩

inductive DispatchDefaultPlan where
  | revert
  | uupsProxy
  /-- User-defined fallback: runs on unknown selector with non-empty calldata. -/
  | fallback
  /-- User-defined receive: runs on empty calldata with ETH. -/
  | receive
  deriving BEq, Repr

structure DispatchPlan where
  entrypoints : Array EntrypointPlan
  default : DispatchDefaultPlan
  deriving Repr

instance : Inhabited DispatchPlan := ⟨{ entrypoints := #[], default := .revert }⟩

def moduleDispatchDefaultPlan (module : Module) : DispatchDefaultPlan :=
  -- Check for user-defined fallback/receive entrypoints first
  let hasFallback := module.entrypoints.any (fun ep => ep.kind == .fallback)
  let hasReceive := module.entrypoints.any (fun ep => ep.kind == .receive)
  match module.proxyPattern? with
  | some "uups" => .uupsProxy
  | _ =>
    if hasReceive then .receive
    else if hasFallback then .fallback
    else .revert

def moduleDispatchPlan (module : Module) (entrypoints : Array EntrypointPlan) : DispatchPlan := {
  entrypoints
  default := moduleDispatchDefaultPlan module
}

/-! ## MetadataPlan: planned artifact/deploy metadata inputs -/

structure MetadataPlan where
  moduleName : String
  entrypoints : Array EntrypointPlan
  events : Array EventPlan
  capabilities : Array Capability
  deriving Repr

/-! ## ContextPlan: EVM context operation summary -/

structure ContextPlan where
  field : ContextField
  deriving Repr

def ContextPlan.beq (a b : ContextPlan) : Bool :=
  a.field.name == b.field.name

instance : BEq ContextPlan := ⟨ContextPlan.beq⟩

/-! ## ModulePlan: the complete EVM semantic plan -/

structure ModulePlan where
  name : String
  targetPlan : CapabilityPlan
  storage : StorageLayout
  helpers : HelperSet
  mapAssignOps : Array AssignOp
  entrypoints : Array EntrypointPlan
  dispatch : DispatchPlan
  events : Array EventPlan
  crosscalls : Array CrosscallHelperSpec
  creates : Array CreateHelperSpec
  localArrayGetLengths : Array Nat
  nestedLocalArrayGetShapes : Array (Array Nat)
  usesCheckedArithmetic : Bool
  /-- Mirror of `Module.overflowChecked`: when false, add/sub/mul lower to
      wrapping Yul builtins (Solana/NEAR semantics); when true, to checked-revert
      helpers (Solidity 0.8 semantics). `usesCheckedArithmetic` reports whether
      any entrypoint actually contains such an op; this field drives the
      lowering mode. See Track 0.1 in `docs/zh/execution-plan-2026-07.md`. -/
  overflowChecked : Bool := false
  metadata : MetadataPlan
  contextOps : Array ContextPlan
  deriving Repr

def ModulePlan.capabilities (plan : ModulePlan) : Array Capability :=
  plan.targetPlan.capabilities

def ModulePlan.hasHelper (plan : ModulePlan) (helper : Helper) : Bool :=
  HelperSet.contains plan.helpers helper

mutual
  partial def contextOpsFromExpr (expr : Expr) : Array ContextPlan :=
    match expr with
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc v => acc ++ contextOpsFromExpr v
    | .arrayGet array index =>
        contextOpsFromExpr array ++ contextOpsFromExpr index
    | .memoryArrayNew _ length =>
        contextOpsFromExpr length
    | .memoryArrayLength array =>
        contextOpsFromExpr array
    | .memoryArrayGet array index =>
        contextOpsFromExpr array ++ contextOpsFromExpr index
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field => acc ++ contextOpsFromExpr field.snd
    | .field base _ => contextOpsFromExpr base
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        contextOpsFromExpr lhs ++ contextOpsFromExpr rhs
    | .ecrecover a b c d =>
        contextOpsFromExpr a ++ contextOpsFromExpr b ++ contextOpsFromExpr c ++ contextOpsFromExpr d
    | .eip712PermitDigest a b c d e f =>
        contextOpsFromExpr a ++ contextOpsFromExpr b ++ contextOpsFromExpr c ++
          contextOpsFromExpr d ++ contextOpsFromExpr e ++ contextOpsFromExpr f
    | .crosscallAbiPacked target _ _ _ _ _ dynLen? _dynOffs dynTargets =>
        let base :=
          match dynLen? with
          | none => contextOpsFromExpr target
          | some len => contextOpsFromExpr target ++ contextOpsFromExpr len
        dynTargets.foldl (init := base) fun acc t => acc ++ contextOpsFromExpr t
    | .cast value _ | .boolNot value | .hash value => contextOpsFromExpr value
    | .hashValue a b c d =>
        contextOpsFromExpr a ++ contextOpsFromExpr b ++ contextOpsFromExpr c ++ contextOpsFromExpr d
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        contextOpsFromExpr target ++ contextOpsFromExpr methodId ++
          args.foldl (init := #[]) fun acc arg => acc ++ contextOpsFromExpr arg
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        contextOpsFromExpr target ++ contextOpsFromExpr methodId ++ contextOpsFromExpr callValue ++
          args.foldl (init := #[]) fun acc arg => acc ++ contextOpsFromExpr arg
    | .crosscallCreate callValue _ => contextOpsFromExpr callValue
    | .crosscallCreate2 callValue salt _ =>
        contextOpsFromExpr callValue ++ contextOpsFromExpr salt
    | .crosscallNamed _ _ args _ =>
        args.foldl (init := #[]) fun acc arg => acc ++ contextOpsFromExpr arg
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
        contextOpsFromExpr parentPromise ++ contextOpsFromExpr callbackMethod ++ contextOpsFromExpr deposit ++
          args.foldl (init := #[]) fun acc arg => acc ++ contextOpsFromExpr arg
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        contextOpsFromExpr accountIndex ++ contextOpsFromExpr methodId ++ contextOpsFromExpr deposit ++
          args.foldl (init := #[]) fun acc arg => acc ++ contextOpsFromExpr arg
    | .nearPromiseResultsCount => #[]
    | .nearPromiseResultStatus index => contextOpsFromExpr index
    | .nearPromiseResultU64 index => contextOpsFromExpr index
    | .effect e => contextOpsFromEffect e

  partial def contextOpsFromEffect (effect : Effect) : Array ContextPlan :=
    match effect with
    | .storageScalarRead _ => #[]
    | .storageScalarWrite _ value => contextOpsFromExpr value
    | .storageScalarAssignOp _ _ value => contextOpsFromExpr value
    | .storageMapContains _ key => contextOpsFromExpr key
    | .storageMapGet _ key => contextOpsFromExpr key
    | .storageMapInsert _ key value | .storageMapSet _ key value =>
        contextOpsFromExpr key ++ contextOpsFromExpr value
    | .storageMapDelete _ key => contextOpsFromExpr key
    | .storageArrayRead _ index => contextOpsFromExpr index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value =>
        contextOpsFromExpr index ++ contextOpsFromExpr value
    | .storageArrayStructFieldRead _ index _ => contextOpsFromExpr index
    | .storageDynamicArrayPush _ value => contextOpsFromExpr value
    | .storageDynamicArrayPop _ => #[]
    | .memoryArraySet array index value =>
        contextOpsFromExpr array ++ contextOpsFromExpr index ++ contextOpsFromExpr value
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ value => contextOpsFromExpr value
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          match segment with
          | .mapKey key | .index key => acc ++ contextOpsFromExpr key
          | .field _ => acc
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        path.foldl (init := #[]) fun acc segment =>
          match segment with
          | .mapKey key | .index key => acc ++ contextOpsFromExpr key
          | .field _ => acc
        ++ contextOpsFromExpr value
    | .contextRead field => #[{ field }]
    | .eventEmit _ fields | .eventEmitIndexed _ fields _ =>
        fields.foldl (init := #[]) fun acc field => acc ++ contextOpsFromExpr field.snd
    | .checkErc721Received a b c d =>
        contextOpsFromExpr a ++ contextOpsFromExpr b ++ contextOpsFromExpr c ++ contextOpsFromExpr d
    | .checkErc1155Received a b c d e =>
        contextOpsFromExpr a ++ contextOpsFromExpr b ++ contextOpsFromExpr c ++
          contextOpsFromExpr d ++ contextOpsFromExpr e

    | .checkErc1155BatchReceived a b c d e =>
        #[a, b, c, d, e].foldl (init := #[]) fun acc expr =>
          acc ++ contextOpsFromExpr expr

  partial def contextOpsFromStatement (statement : Statement) : Array ContextPlan :=
    match statement with
    | .letBind _ _ value | .letMutBind _ _ value => contextOpsFromExpr value
    | .assign target value | .assignOp target _ value =>
        contextOpsFromExpr target ++ contextOpsFromExpr value
    | .effect e => contextOpsFromEffect e
    | .assert condition _ _ => contextOpsFromExpr condition
    | .assertEq lhs rhs _ _ => contextOpsFromExpr lhs ++ contextOpsFromExpr rhs
    | .release _ | .revert _ | .revertWithError _ => #[]
    | .ifElse condition thenBody elseBody =>
        contextOpsFromExpr condition ++ contextOpsFromStatements thenBody ++ contextOpsFromStatements elseBody
    | .boundedFor _ _ _ body => contextOpsFromStatements body
    | .whileLoop condition body => contextOpsFromExpr condition ++ contextOpsFromStatements body
    | .return value => contextOpsFromExpr value

  partial def contextOpsFromStatements (statements : Array Statement) : Array ContextPlan :=
    statements.foldl (init := #[]) fun acc stmt => acc ++ contextOpsFromStatement stmt
end

def contextOpsFromModule (module : Module) : Array ContextPlan :=
  let all := module.entrypoints.foldl (init := #[]) fun acc ep => acc ++ contextOpsFromStatements ep.body
  all.foldl (init := #[]) fun acc plan =>
    if acc.any (fun existing => existing.field.name == plan.field.name) then acc else acc.push plan

def buildModulePlanWithTargetPlan (module : Module) (targetPlan : CapabilityPlan) :
    Except PlanError ModulePlan := do
  if targetPlan.targetId != Target.evm.id then
    .error {
      message := s!"EVM module plan requires target `{Target.evm.id}`, got `{targetPlan.targetId}`"
    }
  else
    let helpers := moduleHelpers module
    .ok {
      name := module.name
      targetPlan
      storage := storageLayout module
      helpers
      mapAssignOps := helperMapAssignOps helpers
      entrypoints := #[]
      dispatch := moduleDispatchPlan module #[]
      events := #[]
      crosscalls := #[]
      creates := #[]
      localArrayGetLengths := #[]
      nestedLocalArrayGetShapes := #[]
      usesCheckedArithmetic := false
      metadata := {
        moduleName := module.name
        entrypoints := #[]
        events := #[]
        capabilities := targetPlan.capabilities
      }
      contextOps := contextOpsFromModule module
    }

def buildModulePlan (module : Module) : Except PlanError ModulePlan :=
  match resolveModule Target.evm module with
  | .ok targetPlan => buildModulePlanWithTargetPlan module targetPlan
  | .error err => .error (PlanError.fromDiagnostic err)

def buildSpecPlan (spec : ProofForge.Contract.ContractSpec) : Except PlanError ModulePlan :=
  match resolveSpec Target.evm spec with
  | .ok targetPlan => buildModulePlanWithTargetPlan spec.module targetPlan
  | .error err => .error (PlanError.fromDiagnostic err)

end ProofForge.Backend.Evm.Plan
