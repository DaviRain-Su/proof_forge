import ProofForge.IR.Allocator
import ProofForge.IR.Core.Id
import ProofForge.IR.Core.Type
import ProofForge.IR.Core.Storage
import ProofForge.IR.Core.Syntax
import ProofForge.IR.Core.Error
import ProofForge.IR.Core.Validate
import ProofForge.IR.Core.HostOp
import ProofForge.Target.Capability
import ProofForge.Target.Plan
import ProofForge.Contract.Intent

namespace ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Core.Error
open ProofForge.Target

/-- The only canonical envelope version accepted by this implementation. -/
def canonicalSchemaVersion : Nat := 1

/- Evidence owned types. These are intentionally non-semantic: removing them
cannot change capabilities, target code, or observable runtime behavior. -/

structure SourceMap where
  entries : Array (FunctionId × Option BlockId × Option Nat × SourceLocation)
  deriving Repr, BEq

structure NamedVerificationAnnotation where
  name : String
  body : String
  deriving Repr, BEq

structure VerificationAnnotations where
  quintInvariants : Array NamedVerificationAnnotation := #[]
  quintLiveness : Array NamedVerificationAnnotation := #[]
  leanInvariants : Array NamedVerificationAnnotation := #[]
  deriving Repr, BEq

structure IntentSourceEvidence where
  intentIndex : Nat
  source : String
  deriving Repr, BEq

structure LegacyClassificationEvidence where
  nodeTag : String
  decision : String
  reason : String
  deriving Repr, BEq

structure CanonicalEvidence where
  sourceMap : SourceMap
  verification : VerificationAnnotations
  intentSources : Array IntentSourceEvidence := #[]
  legacyClassification : Array LegacyClassificationEvidence
  deriving Repr, BEq

/- Interface contract: artifact-affecting host ABI and dispatch metadata. -/

inductive InterfaceEntrypointKind where
  | function
  | fallback
  | receive
  deriving Repr, BEq, DecidableEq, Inhabited

inductive InterfaceMutability where
  | call
  | view
  deriving Repr, BEq, DecidableEq, Inhabited

structure InterfaceParam where
  valueId : ValueId
  name : String
  type : CoreType
  abiWord? : Option String := none
  deriving Repr, BEq

structure InterfaceEntrypoint where
  functionId : FunctionId
  name : String
  kind : InterfaceEntrypointKind
  mutability : InterfaceMutability
  selector? : Option String := none
  params : Array InterfaceParam
  retType : CoreType
  deriving Repr, BEq

structure InterfaceEventField where
  fieldId : EventFieldId
  name : String
  type : CoreType
  indexed : Bool := false
  abiWord? : Option String := none
  deriving Repr, BEq

structure InterfaceEvent where
  eventId : EventId
  name : String
  fields : Array InterfaceEventField
  deriving Repr, BEq

/-- `coreName` is the unique Core identity. `name` is the source-facing error
name and may be shared by multiple static error sites with different words. -/
structure InterfaceError where
  errorId : ErrorId
  namespace_ : String
  coreName : String
  name : String
  userCode? : Option String
  code : Nat
  message : String
  params : Array CoreType := #[]
  deriving Repr, BEq

structure InterfaceContract where
  contractName : String
  entrypoints : Array InterfaceEntrypoint
  events : Array InterfaceEvent := #[]
  errors : Array InterfaceError := #[]
  deriving Repr, BEq

/- Materialization contract: target-neutral artifact inputs. Closed enums own
all policy choices; target adapters may refine them but cannot reinterpret free
form strings as new policy variants. -/

inductive ConstructorBindingKind where
  | scalarU64
  | addressWord
  | addressKeccak
  | stringLength
  | stringKeccak
  | bytesLength
  | bytesKeccak
  | arrayLength
  | arraySumU64
  deriving Repr, BEq, DecidableEq, Inhabited

structure ConstructorBinding where
  stateId : StateId
  paramName : String
  kind : ConstructorBindingKind
  deriving Repr, BEq

structure ConstructorParam where
  name : String
  abiType : String
  deriving Repr, BEq

inductive CanonicalUpgradePolicy where
  | immutable
  | authority (keyRef : String)
  | governance (ref : String)
  deriving Repr, BEq

inductive CanonicalProxyPattern where
  | uups
  | transparent
  deriving Repr, BEq, DecidableEq, Inhabited

structure StateDisplaySymbol where
  stateId : StateId
  name : String
  deriving Repr, BEq

structure TypeFieldMetadata where
  fieldId : FieldId
  name : String
  isPublic : Bool
  deriving Repr, BEq

structure TypeLayoutMetadata where
  typeId : TypeId
  name : String
  isPublic : Bool
  deriveStorage : Bool
  fields : Array TypeFieldMetadata
  deriving Repr, BEq

/-- Source-free semantic intent. `Intent.source?` is evidence and cannot enter
the checked contract through this type. -/
structure MaterializationIntent where
  kind : ProofForge.Contract.IntentKind
  label : String
  capability? : Option Capability := none
  metadata : Array TargetMetadata := #[]
  deriving Repr, BEq

structure EventFieldEncoding where
  fieldId : EventFieldId
  abiWord : String
  deriving Repr, BEq

structure EventEncoding where
  eventId : EventId
  fields : Array EventFieldEncoding
  deriving Repr, BEq

inductive ErrorEncodingForm where
  | assertFallback
  | revertMessage
  | proofForgeEnvelope
  | solidityCustom
  deriving Repr, BEq, DecidableEq, Inhabited

/-- Static target-specific error payload owned by one Core error site. Portable
message/catalogue data lives in `InterfaceError`; this structure only owns the
Solidity materialization encoding. -/
structure ErrorEncoding where
  errorId : ErrorId
  form : ErrorEncodingForm
  soliditySelector? : Option String := none
  solidityArgWords : Array Nat := #[]
  solidityArgTypes : Array String := #[]
  deriving Repr, BEq

structure MaterializationContract where
  constructorBindings : Array ConstructorBinding := #[]
  constructorParams : Array ConstructorParam := #[]
  allocator : ProofForge.IR.AllocatorConfig := ProofForge.IR.defaultAllocator
  upgradePolicy? : Option CanonicalUpgradePolicy := none
  proxyPattern? : Option CanonicalProxyPattern := none
  moduleProxyPattern? : Option CanonicalProxyPattern := none
  nearHostStrings : Array String := #[]
  stateSymbols : Array StateDisplaySymbol := #[]
  typeLayouts : Array TypeLayoutMetadata := #[]
  intents : Array MaterializationIntent := #[]
  eventEncodings : Array EventEncoding := #[]
  errorEncodings : Array ErrorEncoding := #[]
  deriving Repr, BEq

/- Canonical contract: the checked runtime/materialization boundary passed to
plan builders. Evidence is not part of this type. -/

structure CanonicalContract where
  schemaVersion : Nat
  module : Core.Module
  interface : InterfaceContract
  materialization : MaterializationContract
  requirements : Array CapabilityCall
  hostOpCatalog : Core.HostOp.HostOpCatalog := .empty
  deriving Repr, BEq

structure CheckedCanonicalContract where
  private mk ::
  contract : CanonicalContract
  deriving Repr, BEq

structure CanonicalBundle where
  contract : CheckedCanonicalContract
  evidence : CanonicalEvidence
  deriving Repr, BEq

def emptyEvidence : CanonicalEvidence := {
  sourceMap := { entries := #[] }
  verification := {}
  intentSources := #[]
  legacyClassification := #[]
}

namespace CanonicalEvidence

def withSourceMap (evidence : CanonicalEvidence) (sourceMap : SourceMap) :
    CanonicalEvidence := { evidence with sourceMap := sourceMap }

def withVerification (evidence : CanonicalEvidence)
    (verification : VerificationAnnotations) : CanonicalEvidence :=
  { evidence with verification := verification }

def withIntentSources (evidence : CanonicalEvidence)
    (intentSources : Array IntentSourceEvidence) : CanonicalEvidence :=
  { evidence with intentSources := intentSources }

def withLegacyClassification (evidence : CanonicalEvidence)
    (classification : Array LegacyClassificationEvidence) : CanonicalEvidence :=
  { evidence with legacyClassification := classification }

end CanonicalEvidence

/- Decorate a validation error with a source span from the evidence source map.
Decoration must not change the error tag or validation result. -/

def decorateValidationError (evidence : CanonicalEvidence)
    (e : ValidationError) : ValidationError :=
  let match? := evidence.sourceMap.entries.find? (fun entry =>
    let (fid, bid, idx, _) := entry
    fid == e.function && bid == e.block && idx == e.instruction)
  match match? with
  | none => e
  | some (_, _, _, loc) => e.withLocation loc

/- Required capabilities are determined entirely by the checked contract;
evidence plays no role. -/

def capabilityRequirements (bundle : CanonicalBundle) : Array CapabilityCall :=
  bundle.contract.contract.requirements

/- Capability requirements are derived from canonical payloads, never from the
legacy source module. Traversal and first-occurrence deduplication are stable. -/

private partial def coreTypeCapabilities : CoreType → Array Capability
  | .bytes | .string => #[.dataDynamicBytes]
  | .fixedArray element _ => #[.dataFixedArray] ++ coreTypeCapabilities element
  | .array element => #[.dataDynamicArray] ++ coreTypeCapabilities element
  | .memoryRef element => #[.runtimeMemory] ++ coreTypeCapabilities element
  | .structType _ => #[.dataStruct]
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .hash => #[]

private def stateShapeCapabilities : StateShape → Array Capability
  | .scalar value => #[.storageScalar] ++ coreTypeCapabilities value
  | .map key value _ =>
      #[.storageMap] ++ coreTypeCapabilities key ++ coreTypeCapabilities value
  | .fixedArray element _ =>
      #[.storageArray, .dataFixedArray] ++ coreTypeCapabilities element
  | .dynamicArray element =>
      #[.storageArray, .dataDynamicArray] ++ coreTypeCapabilities element
  | .record typeId => #[.storageScalar] ++ coreTypeCapabilities (.structType typeId)

private def pureOpCapabilities : PureOp → Array Capability
  | .arithmetic _ .checked _ _ => #[.checkedArithmetic]
  | .hash _ => #[.cryptoHash]
  | .literal _ | .unary _ _ | .arithmetic _ .wrapping _ _ |
      .compare _ _ _ | .cast _ _ => #[]

private def contextCapabilities : ContextField → Array Capability
  | .sender => #[.callerSender]
  | .value => #[.valueNative]
  | .blockNumber | .blockTimestamp | .gas => #[.envBlock]
  | .contractAddress => #[.accountExplicit]

private def instructionCapabilities (instruction : Instruction) : Array Capability :=
  let resultCaps := instruction.results.foldl
    (fun caps result => caps ++ coreTypeCapabilities result.type) #[]
  let opCaps := match instruction.op with
    | .pure op => pureOpCapabilities op
    | .storageLoad _ | .storageContains _ | .storageStore _ _ |
        .storageLength _ | .storageResize _ _ => #[]
    | .memoryAlloc type _ =>
        #[.runtimeMemory, .runtimeAllocator] ++ coreTypeCapabilities type
    | .memoryLoad _ _ | .memoryStore _ _ _ | .memoryRelease _ => #[.runtimeMemory]
    | .contextRead field => contextCapabilities field
    | .emit _ _ => #[.eventsEmit]
    | .assert _ _ => #[.assertions]
    | .crosscall spec _ =>
        #[.crosscallInvoke] ++ coreTypeCapabilities spec.returnType ++
          spec.paramTypes.foldl (fun caps type => caps ++ coreTypeCapabilities type) #[]
    -- HostOps do not carry a capability/effect class yet; do not infer one
    -- from target-specific names.
    | .hostCall _ => #[]
  resultCaps ++ opCaps

private def terminatorCapabilities : Terminator → Array Capability
  | .jump _ _ (some (.atMost _)) => #[.controlBoundedLoop]
  | .jump _ _ (some .requiresUnbounded) => #[.controlUnboundedLoop]
  | .jump _ _ none | .return _ => #[]
  | .branch _ _ _ => #[.controlConditional]
  | .revert _ => #[.assertions]

private def functionCapabilities (function : Function) : Array Capability :=
  let signatureCaps := function.params.foldl
    (fun caps param => caps ++ coreTypeCapabilities param.type)
    (coreTypeCapabilities function.retType)
  function.blocks.foldl (fun functionCaps block =>
    let paramCaps := block.params.foldl
      (fun caps param => caps ++ coreTypeCapabilities param.type) #[]
    let instructionCaps := block.instructions.foldl
      (fun caps instruction => caps ++ instructionCapabilities instruction) #[]
    functionCaps ++ paramCaps ++ instructionCaps ++
      terminatorCapabilities block.terminator) signatureCaps

private def stableUniqueCapabilities (capabilities : Array Capability) : Array Capability :=
  capabilities.foldl (fun unique capability =>
    if unique.contains capability then unique else unique.push capability) #[]

/-- Minimum target capabilities implied by canonical declarations, executable
instructions, and annotated loop edges. -/
def moduleCapabilities (module : Core.Module) : Array Capability :=
  let structCaps := module.structs.foldl (fun caps declaration =>
    let own := #[.dataStruct] ++
      (if declaration.semantics == .linearRecord then #[.dataLinearRecord] else #[])
    caps ++ declaration.fields.foldl
      (fun fieldCaps field => fieldCaps ++ coreTypeCapabilities field.type) own) #[]
  let stateCaps := module.state.foldl
    (fun caps declaration => caps ++ stateShapeCapabilities declaration.shape) #[]
  let eventCaps := module.events.foldl (fun caps event =>
    caps ++ event.fields.foldl
      (fun fieldCaps field => fieldCaps ++ coreTypeCapabilities field.type) #[]) #[]
  let errorCaps := module.errors.foldl (fun caps error =>
    caps ++ error.params.foldl
      (fun paramCaps type => paramCaps ++ coreTypeCapabilities type) #[]) #[]
  let functionCaps := module.functions.foldl
    (fun caps function => caps ++ functionCapabilities function) #[]
  stableUniqueCapabilities (structCaps ++ stateCaps ++ eventCaps ++ errorCaps ++ functionCaps)

def materializationCapabilityCalls
    (materialization : MaterializationContract) : Array CapabilityCall :=
  materialization.intents.filterMap (fun intent =>
    intent.capability?.map (fun capability => {
      capability := capability
      operation := .builtin intent.label
      source? := none
      metadata := intent.metadata
    }))

/-- Stable union of source-free capability intents and Core-derived defaults. -/
def deriveCapabilityRequirements (module : Core.Module)
    (materialization : MaterializationContract) : Array CapabilityCall :=
  let calls := materializationCapabilityCalls materialization ++
    (moduleCapabilities module).map CapabilityCall.fromCapability
  calls.foldl (fun unique call =>
    if unique.contains call then unique else unique.push call) #[]

private def hasDuplicate {α : Type} [BEq α] (xs : Array α) : Bool :=
  (xs.foldl (fun acc x =>
    if acc.1.contains x then (acc.1, true) else (acc.1.push x, acc.2))
    (#[], false)).2

private def interfaceError (reason : String) : ValidationError :=
  ValidationError.mkSimple .invalidInterface "interface" reason

private def materializationError (reason : String) : ValidationError :=
  ValidationError.mkSimple .invalidMaterialization "materialization" reason

private def viewInstructionAllowed : InstructionOp → Bool
  | .pure _ | .storageLoad _ | .storageContains _ | .storageLength _ |
      .memoryAlloc _ _ | .memoryLoad _ _ | .memoryStore _ _ _ |
      .memoryRelease _ | .assert _ _ => true
  | .contextRead .value => false
  | .contextRead _ => true
  | .crosscall spec _ => spec.mode == .staticInvoke
  | .storageStore _ _ | .storageResize _ _ | .emit _ _ | .hostCall _ => false

private def validateInterface (module : Core.Module)
    (interface : InterfaceContract) : Except ValidationError Unit := do
  if interface.contractName.isEmpty then
    throw <| interfaceError "contract name is empty"
  if hasDuplicate (interface.entrypoints.map (·.functionId)) then
    throw <| interfaceError "duplicate interface function id"
  if hasDuplicate (interface.entrypoints.map (·.name)) then
    throw <| interfaceError "duplicate interface entrypoint name"
  if hasDuplicate (interface.entrypoints.filterMap (·.selector?)) then
    throw <| interfaceError "duplicate interface selector"
  if (interface.entrypoints.filter (·.kind == .fallback)).size > 1 ||
      (interface.entrypoints.filter (·.kind == .receive)).size > 1 then
    throw <| interfaceError "interface has multiple fallback or receive entrypoints"
  for ep in interface.entrypoints do
    let function ← match module.functions.find? (·.id == ep.functionId) with
      | some function => pure function
      | none => throw (interfaceError
          s!"interface references unknown function {repr ep.functionId}")
    if ep.name.isEmpty then
      throw <| interfaceError s!"function {repr ep.functionId} has an empty interface name"
    match ep.kind with
    | .function => pure ()
    | .fallback =>
        unless ep.selector?.isNone do
          throw <| interfaceError "fallback entrypoint cannot declare a selector"
    | .receive =>
        unless ep.selector?.isNone && ep.params.isEmpty && ep.retType == .unit do
          throw <| interfaceError
            "receive entrypoint must have no selector, no parameters, and Unit return"
    unless ep.retType == function.retType do
      throw <| interfaceError s!"return type mismatch for function {repr ep.functionId}"
    unless ep.params.map (fun p => (p.valueId, p.type)) ==
        function.params.map (fun p => (p.id, p.type)) do
      throw <| interfaceError s!"parameter id/type mismatch for function {repr ep.functionId}"
    if ep.params.any (·.name.isEmpty) || hasDuplicate (ep.params.map (·.name)) then
      throw <| interfaceError s!"invalid or duplicate parameter name for function {repr ep.functionId}"
    if ep.mutability == .view then
      for block in function.blocks do
        for idx in [:block.instructions.size] do
          unless viewInstructionAllowed block.instructions[idx]!.op do
            throw <| interfaceError
              s!"view function {repr ep.functionId} contains a stateful instruction at block {repr block.id}, index {idx}"

  unless interface.events.size == module.events.size do
    throw <| interfaceError
      s!"interface has {interface.events.size} events for {module.events.size} Core events"
  if hasDuplicate (interface.events.map (·.eventId)) ||
      hasDuplicate (interface.events.map (·.name)) then
    throw <| interfaceError "duplicate interface event id or name"
  for event in interface.events do
    let declaration ← match module.events.find? (·.id == event.eventId) with
      | some declaration => pure declaration
      | none => throw <| interfaceError s!"unknown interface event {repr event.eventId}"
    if event.name.isEmpty || event.fields.any (·.name.isEmpty) ||
        hasDuplicate (event.fields.map (·.name)) then
      throw <| interfaceError s!"invalid event or field name for {repr event.eventId}"
    unless event.fields.map (fun field => (field.fieldId, field.type)) ==
        declaration.fields.map (fun field => (field.id, field.type)) do
      throw <| interfaceError s!"event schema mismatch for {repr event.eventId}"

  unless interface.errors.size == module.errors.size do
    throw <| interfaceError
      s!"interface has {interface.errors.size} errors for {module.errors.size} Core errors"
  if hasDuplicate (interface.errors.map (·.errorId)) then
    throw <| interfaceError "duplicate interface error id"
  for error in interface.errors do
    let declaration ← match module.errors.find? (·.id == error.errorId) with
      | some declaration => pure declaration
      | none => throw <| interfaceError s!"unknown interface error {repr error.errorId}"
    if error.namespace_.isEmpty || error.coreName.isEmpty || error.name.isEmpty then
      throw <| interfaceError s!"empty interface error identity for {repr error.errorId}"
    unless error.namespace_ == declaration.namespace_ &&
        error.coreName == declaration.name && error.code == declaration.code &&
        error.params == declaration.params do
      throw <| interfaceError s!"error schema mismatch for {repr error.errorId}"

private def isHexSelector (selector : String) : Bool :=
  selector.length == 8 && selector.toList.all (fun ch =>
    "0123456789abcdefABCDEF".toList.contains ch)

def constructorAbiTypeSupported (abiType : String) : Bool :=
  #["uint256", "uint64", "uint32", "bool", "bytes32", "address",
    "string", "bytes", "uint256[]"].contains abiType

private def constructorBindingCompatible (kind : ConstructorBindingKind)
    (abiType : String) (shape : StateShape) : Bool :=
  match kind, abiType, shape with
  | .scalarU64, "uint256", .scalar .u64
  | .scalarU64, "uint64", .scalar .u64
  | .scalarU64, "uint32", .scalar .u64
  | .addressWord, "address", .scalar .address
  | .addressWord, "address", .scalar .hash
  | .addressKeccak, "address", .scalar .hash
  | .stringLength, "string", .scalar .u64
  | .stringKeccak, "string", .scalar .hash
  | .bytesLength, "bytes", .scalar .u64
  | .bytesKeccak, "bytes", .scalar .hash
  | .arrayLength, "uint256[]", .scalar .u64
  | .arraySumU64, "uint256[]", .scalar .u64 => true
  | _, _, _ => false

/-- Static Solidity ABI words supported by canonical custom-error metadata.
This matches the current EVM materializer exactly. -/
def solidityStaticArgBitWidth? : String → Option Nat
  | "uint8" => some 8
  | "uint32" => some 32
  | "uint64" => some 64
  | "uint128" => some 128
  | "uint256" => some 256
  | "bool" => some 1
  | "address" => some 160
  | "bytes32" => some 256
  | _ => none

private def validateMaterialization (module : Core.Module)
    (interface : InterfaceContract)
    (materialization : MaterializationContract) : Except ValidationError Unit := do
  if materialization.constructorParams.any (fun p => p.name.isEmpty || p.abiType.isEmpty) ||
      hasDuplicate (materialization.constructorParams.map (·.name)) then
    throw <| materializationError "constructor parameters have empty or duplicate names"
  for param in materialization.constructorParams do
    unless constructorAbiTypeSupported param.abiType do
      throw <| materializationError
        s!"constructor parameter `{param.name}` has unsupported ABI type `{param.abiType}`"
  if hasDuplicate (materialization.constructorBindings.map (·.stateId)) then
    throw <| materializationError "multiple constructor bindings write the same state"
  for binding in materialization.constructorBindings do
    let state ← match module.state.find? (·.id == binding.stateId) with
      | some state => pure state
      | none => throw (materializationError
          s!"constructor binding references unknown state {repr binding.stateId}")
    let param ← match materialization.constructorParams.find? (·.name == binding.paramName) with
      | some param => pure param
      | none => throw (materializationError
          s!"constructor binding references unknown parameter `{binding.paramName}`")
    unless constructorBindingCompatible binding.kind param.abiType state.shape do
      throw <| materializationError
        s!"constructor binding {repr binding.kind} is incompatible with ABI `{param.abiType}` and state shape {repr state.shape}"

  unless materialization.proxyPattern? == materialization.moduleProxyPattern? do
    throw <| materializationError "spec and module proxy patterns disagree"
  match materialization.upgradePolicy? with
  | some (.authority keyRef) =>
      if keyRef.isEmpty then
        throw <| materializationError "upgrade authority keyRef is empty"
  | some (.governance ref) =>
      if ref.isEmpty then
        throw <| materializationError "upgrade governance reference is empty"
  | some .immutable | none => pure ()
  if materialization.nearHostStrings.any (·.isEmpty) then
    throw <| materializationError "NEAR host string pool contains an empty entry"

  unless materialization.stateSymbols.size == module.state.size do
    throw <| materializationError "state display symbol table is incomplete"
  if hasDuplicate (materialization.stateSymbols.map (·.stateId)) ||
      hasDuplicate (materialization.stateSymbols.map (·.name)) then
    throw <| materializationError "duplicate state display symbol"
  for symbol in materialization.stateSymbols do
    unless module.state.any (·.id == symbol.stateId) && !symbol.name.isEmpty do
      throw <| materializationError s!"invalid state display symbol {repr symbol.stateId}"

  unless materialization.typeLayouts.size == module.structs.size do
    throw <| materializationError "type layout metadata is incomplete"
  if hasDuplicate (materialization.typeLayouts.map (·.typeId)) ||
      hasDuplicate (materialization.typeLayouts.map (·.name)) then
    throw <| materializationError "duplicate type layout metadata"
  for layout in materialization.typeLayouts do
    let declaration ← match module.structs.find? (·.id == layout.typeId) with
      | some declaration => pure declaration
      | none => throw <| materializationError s!"unknown type layout {repr layout.typeId}"
    if layout.name.isEmpty || layout.fields.any (·.name.isEmpty) ||
        hasDuplicate (layout.fields.map (·.name)) then
      throw <| materializationError s!"invalid type or field display name for {repr layout.typeId}"
    unless layout.fields.map (·.fieldId) == declaration.fields.map (·.id) do
      throw <| materializationError s!"field metadata does not align with Core type {repr layout.typeId}"

  for intent in materialization.intents do
    if intent.label.isEmpty then
      throw <| materializationError "materialization intent has an empty label"
    match intent.kind, intent.capability? with
    | .capability, some _ => pure ()
    | .capability, none =>
        throw <| materializationError
          s!"capability intent `{intent.label}` has no capability"
    | _, none => pure ()
    | _, some _ =>
        throw <| materializationError
          s!"non-capability intent `{intent.label}` carries a capability"

  unless materialization.eventEncodings.size == interface.events.size do
    throw <| materializationError "event encoding mirror is incomplete"
  if hasDuplicate (materialization.eventEncodings.map (·.eventId)) then
    throw <| materializationError "duplicate event encoding"
  for encoding in materialization.eventEncodings do
    let event ← match interface.events.find? (·.eventId == encoding.eventId) with
      | some event => pure event
      | none => throw (materializationError
          s!"event encoding references unknown event {repr encoding.eventId}")
    if hasDuplicate (encoding.fields.map (·.fieldId)) then
      throw <| materializationError s!"duplicate field encoding for {repr encoding.eventId}"
    let expectedFields := event.fields.filterMap (fun field =>
      field.abiWord?.map (fun abiWord => { fieldId := field.fieldId, abiWord := abiWord }))
    unless encoding.fields == expectedFields do
      throw <| materializationError
        s!"event ABI mirror is incomplete or out of order for {repr encoding.eventId}"
    for fieldEncoding in encoding.fields do
      let field ← match event.fields.find? (·.fieldId == fieldEncoding.fieldId) with
        | some field => pure field
        | none => throw (materializationError
            s!"event encoding references unknown field {repr fieldEncoding.fieldId}")
      if fieldEncoding.abiWord.isEmpty || field.abiWord? != some fieldEncoding.abiWord then
        throw <| materializationError
          s!"event encoding disagrees with interface field {repr fieldEncoding.fieldId}"

  unless materialization.errorEncodings.size == interface.errors.size do
    throw <| materializationError "error encoding table is incomplete"
  if hasDuplicate (materialization.errorEncodings.map (·.errorId)) then
    throw <| materializationError "duplicate error encoding"
  for encoding in materialization.errorEncodings do
    let owner ← match interface.errors.find? (·.errorId == encoding.errorId) with
      | some owner => pure owner
      | none => throw (materializationError
          s!"error encoding references unknown error {repr encoding.errorId}")
    match encoding.form with
    | .assertFallback | .revertMessage | .proofForgeEnvelope =>
        unless encoding.soliditySelector?.isNone &&
            encoding.solidityArgWords.isEmpty && encoding.solidityArgTypes.isEmpty do
          throw (materializationError
            s!"non-custom error {repr encoding.errorId} carries a Solidity custom encoding")
    | .solidityCustom =>
        let selector ← match encoding.soliditySelector? with
          | some selector => pure selector
          | none => throw (materializationError s!"custom error {repr encoding.errorId} is missing its Solidity selector")
        unless isHexSelector selector do
          throw (materializationError
            s!"error {repr encoding.errorId} has invalid Solidity selector `{selector}`")
        unless encoding.solidityArgWords.size == encoding.solidityArgTypes.size do
          throw (materializationError
            s!"error {repr encoding.errorId} has mismatched Solidity argument schema")
        for ((abiType, word), index) in
            (encoding.solidityArgTypes.zip encoding.solidityArgWords).zipIdx do
          let width ← match solidityStaticArgBitWidth? abiType with
            | some width => pure width
            | none => throw (materializationError
                s!"error {repr encoding.errorId} argument {index} has unsupported static ABI type `{abiType}`")
          if word >= 2 ^ width then
            throw <| materializationError
              s!"error {repr encoding.errorId} argument {index} value `{word}` exceeds `{abiType}` range"
    let _ := owner

private def validateRequirements (module : Core.Module)
    (materialization : MaterializationContract) (requirements : Array CapabilityCall) :
    Except ValidationError Unit := do
  if hasDuplicate requirements then
    throw <| ValidationError.mkSimple .invalidMaterialization "capability"
      "duplicate capability requirement"
  for call in requirements do
    if call.operation.render.isEmpty then
      throw <| ValidationError.mkSimple .unknownReference "capability"
        s!"capability call for {call.capability} has empty operation"
    unless call.source?.isNone do
      throw <| ValidationError.mkSimple .invalidMaterialization "capability"
        s!"capability call `{call.operation.render}` leaked source evidence into the checked contract"
  let expected := deriveCapabilityRequirements module materialization
  unless requirements == expected do
    throw <| ValidationError.mkSimple .invalidMaterialization "capability"
      s!"capability requirements do not match canonical payload; expected {repr expected}, got {repr requirements}"

/- Validate a canonical contract in the required fixed order. The result is a
`CheckedCanonicalContract`; evidence is not consumed by validation. -/

def validateCanonical (c : CanonicalContract) :
    Except ValidationError CheckedCanonicalContract := do
  unless c.schemaVersion == canonicalSchemaVersion do
    throw <| ValidationError.mkSimple .unsupportedSchemaVersion "schema-version"
      s!"unsupported canonical schema version {c.schemaVersion}; expected {canonicalSchemaVersion}"
  -- Pass 1: symbol uniqueness and declaration tables.
  Validate.checkSymbolUniqueness c.module
  -- Pass 2: state-shape references.
  Validate.checkStateShapeReferences c.module
  let _ ← Validate.validateModulePhases c.module (some c.hostOpCatalog)
  -- The runtime must be sound before the artifact envelope is compared with it;
  -- otherwise stale metadata would mask the actionable Core validation error.
  validateInterface c.module c.interface
  validateMaterialization c.module c.interface c.materialization
  validateRequirements c.module c.materialization c.requirements
  return { contract := c }

/- Manual `Inhabited` instances for panic/debug contexts. These defaults are
not valid contracts and are not produced by `validateCanonical`. -/

instance : Inhabited SourceMap where default := { entries := #[] }
instance : Inhabited NamedVerificationAnnotation where default := { name := "", body := "" }
instance : Inhabited VerificationAnnotations where default := {}
instance : Inhabited IntentSourceEvidence where default := { intentIndex := 0, source := "" }
instance : Inhabited LegacyClassificationEvidence where default := { nodeTag := "", decision := "", reason := "" }
instance : Inhabited CanonicalEvidence where default := { sourceMap := default, verification := default, legacyClassification := #[] }
instance : Inhabited InterfaceParam where default := { valueId := ⟨0⟩, name := "", type := .unit }
instance : Inhabited InterfaceEntrypoint where default := {
  functionId := ⟨0⟩, name := "", kind := .function, mutability := .call,
  params := #[], retType := .unit
}
instance : Inhabited InterfaceEventField where default := { fieldId := ⟨0⟩, name := "", type := .unit }
instance : Inhabited InterfaceEvent where default := { eventId := ⟨0⟩, name := "", fields := #[] }
instance : Inhabited InterfaceError where default := {
  errorId := ⟨0⟩, namespace_ := "", coreName := "", name := "",
  userCode? := none, code := 0, message := ""
}
instance : Inhabited InterfaceContract where default := { contractName := "", entrypoints := #[] }
instance : Inhabited ConstructorBinding where default := { stateId := ⟨0⟩, paramName := "", kind := .scalarU64 }
instance : Inhabited ConstructorParam where default := { name := "", abiType := "" }
instance : Inhabited CanonicalUpgradePolicy where default := .immutable
instance : Inhabited StateDisplaySymbol where default := { stateId := ⟨0⟩, name := "" }
instance : Inhabited TypeFieldMetadata where default := { fieldId := ⟨0⟩, name := "", isPublic := false }
instance : Inhabited TypeLayoutMetadata where default := {
  typeId := ⟨0⟩, name := "", isPublic := false, deriveStorage := false, fields := #[]
}
instance : Inhabited MaterializationIntent where default := { kind := .module, label := "" }
instance : Inhabited EventFieldEncoding where default := { fieldId := ⟨0⟩, abiWord := "" }
instance : Inhabited EventEncoding where default := { eventId := ⟨0⟩, fields := #[] }
instance : Inhabited ErrorEncoding where default := { errorId := ⟨0⟩, form := .assertFallback }
instance : Inhabited MaterializationContract where default := {}
instance : Inhabited CanonicalContract where default := {
  schemaVersion := 0, module := default, interface := default,
  materialization := default, requirements := #[]
}

end ProofForge.IR.Canonical
