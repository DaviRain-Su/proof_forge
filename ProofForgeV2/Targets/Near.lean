import ProofForgeV2.Targets.Common

namespace ProofForgeV2.Targets.Near

open ProofForgeV2

def descriptor : TargetDescriptor := {
  targetId := TargetId.near
  artifactEncoding := .wasmText
  executionHost := .nearRuntime
  commitModel := .receiptLocal
  stateBinding := .hostKeyValue
  callModel := .asynchronousReceipt
  proofModel := .none
  settlementModel := .near
  codegenProfile := CodegenProfileId.nearWasmRawU64V1
  supportedRequirements := #[
    .persistentState, .checkedArithmetic, .transactionalRollback
  ]
}

def hostAbiVersion : String := "near-host-abi-v1"
def rawInputAbi : String := "packed-raw-little-endian-u64"
def stateLayoutDomain : String := "proof-forge-near-layout-v1:"
def layoutMarkerKey : String := "pf:v1:layout"

inductive Endianness where
  | little
  deriving BEq, Inhabited, Repr

inductive PayloadInitializationPolicy where
  | zeroAllFields
  deriving BEq, Inhabited, Repr

inductive FailureAction where
  | trap
  | returnStatus
  deriving BEq, Inhabited, Repr

structure FailurePolicy where
  invalidInput : FailureAction
  uninitializedLayout : FailureAction
  corruptStorage : FailureAction
  arithmeticOverflow : FailureAction
  nonzeroDeposit : FailureAction
  deriving BEq, Inhabited, Repr

inductive ReceiptCommitPolicy where
  | rollbackOnTrap
  | retainWritesOnTrap
  deriving BEq, Inhabited, Repr

inductive MethodMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

inductive DepositPolicy where
  | requireZero
  | queryOnly
  deriving BEq, Inhabited, Repr

inductive HostImport where
  | input
  | registerLen
  | readRegister
  | storageRead
  | storageWrite
  | valueReturn
  | attachedDeposit
  deriving BEq, Inhabited, Repr

structure ResourceLimits where
  maxArtifactStemBytes : Nat
  maxStateFields : Nat
  maxEntries : Nat
  maxParams : Nat
  maxBodyStatements : Nat
  maxExprDepth : Nat
  maxPlanNodes : Nat
  maxRecipeNodes : Nat
  maxMethodLocals : Nat
  wasmMemoryPages : Nat
  deriving BEq, Inhabited, Repr

structure StorageField where
  sourceId : Nat
  name : String
  key : String
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

structure StorageLayout where
  markerKey : String
  markerValue : UInt64
  payloadInitialization : PayloadInitializationPolicy
  fields : Array StorageField
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  inputOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (inputOffset : Nat)
  | stateLoad (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  fieldIndex : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  deriving BEq, Inhabited, Repr

structure Method where
  name : String
  params : Array Param
  exactInputLen : Nat
  mode : MethodMode
  depositPolicy : DepositPolicy
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- The NEAR-owned KV, raw ABI, method, and error policy for the supported
UInt64 fragment. It deliberately retains no SemanticProgram. -/
structure Plan where
  targetDescriptor : TargetDescriptor
  semanticSchemaVersion : Nat
  codegenProfile : String
  hostAbi : String
  inputAbi : String
  layoutDomain : String
  hostImports : Array HostImport
  failurePolicy : FailurePolicy
  commitPolicy : ReceiptCommitPolicy
  resourceLimits : ResourceLimits
  programName : String
  storage : StorageLayout
  initializer : Method
  entries : Array Method
  -- No Inhabited: Plan embeds TargetDescriptor (opaque TargetId/profile).
  deriving BEq, Repr

structure RegisterLayout where
  input : Nat
  storage : Nat
  evicted : Nat
  deriving BEq, Inhabited, Repr

structure KeyRegion where
  key : String
  offset : Nat
  length : Nat
  deriving BEq, Inhabited, Repr

structure MemoryLayout where
  minPages : Nat
  inputOffset : Nat
  inputCapacity : Nat
  depositOffset : Nat
  valueOffset : Nat
  deriving BEq, Inhabited, Repr

inductive Operation where
  | checkInputLen (bytes : Nat)
  | requireZeroAttachedDeposit
  | requireLayoutAbsent (marker : KeyRegion)
  | requireLayout (marker : KeyRegion) (value : UInt64)
  | zeroState (field : KeyRegion)
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination inputOffset : Nat)
  | loadState (destination : Nat) (field : KeyRegion)
  | checkedAdd (destination lhs rhs : Nat)
  | storeState (field : KeyRegion) (value : Nat)
  | setLayout (marker : KeyRegion) (value : UInt64)
  | setReturnData (value : Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  params : Array Param
  mode : MethodMode
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed NEAR host-call/Wasm recipe. Rendering WAT is deliberately later than
the exact Plan-to-recipe binding check. -/
structure IR where
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  registers : RegisterLayout
  keys : Array KeyRegion
  memory : MemoryLayout
  methods : Array MethodIR
  -- No Inhabited: IR embeds Plan → TargetDescriptor identities.
  deriving BEq, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .near message

private def maxIdentifierBytes : Nat := 240
-- `.near-abi.json` is the longest emitted suffix (14 bytes) under the CLI's
-- 240-byte relative-path ceiling.
private def maxArtifactStemBytes : Nat := 226
private def maxStateFields : Nat := 1024
private def maxEntries : Nat := 255
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256
private def maxPlanNodes : Nat := 100000
private def maxRecipeNodes : Nat := 110000
private def maxMethodLocals : Nat := 50000
private def wasmPageBytes : Nat := 65536

private def canonicalFailurePolicy : FailurePolicy := {
  invalidInput := .trap
  uninitializedLayout := .trap
  corruptStorage := .trap
  arithmeticOverflow := .trap
  nonzeroDeposit := .trap
}

private def canonicalResourceLimits : ResourceLimits := {
  maxArtifactStemBytes
  maxStateFields
  maxEntries
  maxParams
  maxBodyStatements
  maxExprDepth
  maxPlanNodes
  maxRecipeNodes
  maxMethodLocals
  wasmMemoryPages := 1
}

private def canonicalImports : Array HostImport := #[
  .input, .registerLen, .readRegister, .storageRead, .storageWrite, .valueReturn,
  .attachedDeposit
]

private def canonicalRegisters : RegisterLayout := {
  input := 0
  storage := 1
  evicted := 2
}

private def isIdentifier (value : String) : Bool :=
  value.toUTF8.size <= maxIdentifierBytes && match value.toList with
  | [] => false
  | first :: rest =>
      let isAsciiLetter (character : Char) : Bool :=
        let code := character.toNat
        (65 <= code && code <= 90) || (97 <= code && code <= 122)
      let isAsciiDigit (character : Char) : Bool :=
        let code := character.toNat
        48 <= code && code <= 57
      (isAsciiLetter first || first == '_') &&
        rest.all (fun character =>
          isAsciiLetter character || isAsciiDigit character || character == '_')

private def hasDuplicates [BEq α] (values : Array α) : Bool := Id.run do
  let mut seen : Array α := #[]
  for value in values do
    if seen.contains value then return true
    seen := seen.push value
  return false

private def stateKey (sourceId : Nat) : String :=
  s!"pf:v1:state:{sourceId}"

private def layoutFieldSignature (field : StorageField) : String :=
  s!"{field.sourceId}:{field.name}:{field.key}:{field.byteWidth}:u64-le"

private def layoutSignature (fields : Array StorageField) : String :=
  s!"{fields.size}|{String.intercalate "|" (fields.toList.map layoutFieldSignature)}"

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

def layoutMarker (fields : Array StorageField) : UInt64 :=
  firstWordBE <| Crypto.sha256 (stateLayoutDomain ++ layoutSignature fields).toUTF8

private partial def semanticExprNodes? (depthLeft nodeBudget : Nat)
    (expr : Semantic.Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. | .param .. | .state .. => some 1
    | .checkedAdd lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match semanticExprNodes? childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match semanticExprNodes? childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addSemanticExprNodes (total : Nat)
    (expr : Semantic.Expr) : CompileResult Nat :=
  match semanticExprNodes? maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => .ok (total + nodes)
  | none => planError
      s!"semantic expression exceeds depth {maxExprDepth} or aggregate node limit {maxPlanNodes}"

private def validateSemanticBudget (program : Semantic.Program) : CompileResult Unit := do
  if program.state.isEmpty || program.state.size > maxStateFields then
    throw <| .planInvariant .near "state count is outside the profile limits"
  if program.entries.isEmpty || program.entries.size > maxEntries then
    throw <| .planInvariant .near "entry count is outside the profile limits"
  let initializer ← match program.initializer with
    | some value => pure value
    | none => throw <| .planInvariant .near "KV-state programs require an initializer"
  if initializer.params.size > maxParams || initializer.body.size > maxBodyStatements then
    throw <| .planInvariant .near "initializer exceeds the profile resource limits"
  for entry in program.entries do
    if entry.params.size > maxParams || entry.body.size > maxBodyStatements then
      throw <| .planInvariant .near s!"entry '{entry.name}' exceeds the profile resource limits"
  let initializerNodes := 1 + initializer.params.size + initializer.body.size
  let entryNodes := program.entries.foldl (fun total entry =>
    total + 1 + entry.params.size + entry.body.size) 0
  let mut total := program.state.size + initializerNodes + entryNodes
  if total > maxPlanNodes then
    throw <| .planInvariant .near s!"semantic program exceeds aggregate node limit {maxPlanNodes}"
  for statement in initializer.body do
    match statement with
    | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
    | .synchronousCall .. => pure ()
  for entry in program.entries do
    for statement in entry.body do
      match statement with
      | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
      | .synchronousCall .. => pure ()

private def makeStorageLayout
    (states : Array Semantic.StateDecl) : CompileResult StorageLayout := do
  let mut fields : Array StorageField := #[]
  for state in states do
    unless state.type == .u64 do
      throw <| .planInvariant .near s!"state '{state.name}' is not UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .near s!"state name '{state.name}' is not a safe identifier"
    unless state.id.value == fields.size do
      throw <| .planInvariant .near "semantic state ids must match declaration order"
    fields := fields.push {
      sourceId := state.id.value
      name := state.name
      key := stateKey state.id.value
      byteWidth := 8
      endianness := .little
    }
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .near
      "state layout marker collides with the reserved uninitialized value"
  return {
    markerKey := layoutMarkerKey
    markerValue := marker
    payloadInitialization := .zeroAllFields
    fields
  }

private def makeParams (owner : String)
    (params : Array Semantic.Param) : CompileResult (Array Param) := do
  if params.size > maxParams then
    throw <| .planInvariant .near s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  for param in params do
    unless param.type == .u64 do
      throw <| .planInvariant .near s!"parameter '{param.name}' in {owner} is not UInt64"
    unless param.visibility == .verifierVisible do
      throw <| .planInvariant .near
        s!"parameter '{param.name}' in {owner} is not verifier-visible"
    unless isIdentifier param.name do
      throw <| .planInvariant .near
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    unless param.id.value == planned.size do
      throw <| .planInvariant .near
        s!"semantic parameter ids in {owner} must match declaration order"
    planned := planned.push {
      sourceId := param.id.value
      name := param.name
      inputOffset := planned.size * 8
      byteWidth := 8
      endianness := .little
    }
  return planned

private def findField (layout : StorageLayout)
    (id : Semantic.StateId) : CompileResult StorageField :=
  match layout.fields.find? (·.sourceId == id.value) with
  | some field => .ok field
  | none => planError s!"semantic expression references unknown state id {id.value}"

private def findParam (params : Array Param)
    (id : Semantic.ParamId) : CompileResult Param :=
  match params.find? (·.sourceId == id.value) with
  | some param => .ok param
  | none => planError s!"semantic expression references unknown parameter id {id.value}"

private partial def makeExprUnchecked (layout : StorageLayout) (params : Array Param) :
    Semantic.Expr → CompileResult Expr
  | .literal value => .ok <| .literal value
  | .param id => return .param (← findParam params id).inputOffset
  | .state id => return .stateLoad (← findField layout id).sourceId
  | .checkedAdd lhs rhs => do
      let lhs ← makeExprUnchecked layout params lhs
      let rhs ← makeExprUnchecked layout params rhs
      return .checkedAdd lhs rhs

private def makeExpr (layout : StorageLayout) (params : Array Param)
    (expr : Semantic.Expr) : CompileResult Expr := do
  let _ ← addSemanticExprNodes 0 expr
  makeExprUnchecked layout params expr

private def makeStore (layout : StorageLayout) (params : Array Param)
    (state : Semantic.StateId) (value : Semantic.Expr) : CompileResult Store := do
  let field ← findField layout state
  return {
    fieldIndex := field.sourceId
    value := ← makeExpr layout params value
  }

private def makeBody (layout : StorageLayout) (params : Array Param)
    (owner : String) (isInitializer : Bool)
    (body : Array Semantic.Statement) : CompileResult (Array Statement) := do
  let mut planned : Array Statement := #[]
  for statement in body do
    match statement with
    | .store state value =>
        planned := planned.push <| .store (← makeStore layout params state value)
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .near "initializer cannot return a value"
        planned := planned.push <| .returnValue (← makeExpr layout params value)
    | .synchronousCall callee =>
        throw <| .planInvariant .near
          s!"call '{callee}' in {owner} is not in the Phase-1 NEAR fragment"
  return planned

private def makeInitializer (layout : StorageLayout)
    (initializer : Semantic.Initializer) : CompileResult Method := do
  let params ← makeParams "initializer" initializer.params
  return {
    name := "init"
    params
    exactInputLen := params.size * 8
    mode := .initialize
    depositPolicy := .requireZero
    body := ← makeBody layout params "initializer" true initializer.body
  }

private def makeEntry (layout : StorageLayout)
    (entry : Semantic.Entry) : CompileResult Method := do
  unless isIdentifier entry.name do
    throw <| .planInvariant .near s!"entry name '{entry.name}' is not a safe identifier"
  unless entry.result == .u64 do
    throw <| .planInvariant .near s!"entry '{entry.name}' does not return UInt64"
  let params ← makeParams s!"entry '{entry.name}'" entry.params
  let mode := match entry.mode with
    | .mutate => MethodMode.mutate
    | .view => MethodMode.view
  return {
    name := entry.name
    params
    exactInputLen := params.size * 8
    mode
    depositPolicy := if mode == .view then .queryOnly else .requireZero
    body := ← makeBody layout params s!"entry '{entry.name}'" false entry.body
  }

private partial def planExprNodes? (layout : StorageLayout) (params : Array Param)
    (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .param inputOffset => if params.any (·.inputOffset == inputOffset) then some 1 else none
    | .stateLoad fieldIndex => if fieldIndex < layout.fields.size then some 1 else none
    | .checkedAdd lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? layout params childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? layout params childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (total : Nat) (expr : Expr) : CompileResult Nat :=
  match planExprNodes? layout params limits.maxExprDepth (limits.maxPlanNodes - total) expr with
  | some nodes => .ok (total + nodes)
  | none => planError
      s!"plan expression has a dangling reference or exceeds depth {limits.maxExprDepth}/node limit {limits.maxPlanNodes}"

private def addMethodExprTemps (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (total : Nat) (expr : Expr) : CompileResult Nat :=
  match planExprNodes? layout params limits.maxExprDepth (limits.maxMethodLocals - total) expr with
  | some nodes => .ok (total + nodes)
  | none => planError
      s!"method expression has a dangling reference or exceeds depth {limits.maxExprDepth}/local limit {limits.maxMethodLocals}"

private def validateStorageLayout (limits : ResourceLimits)
    (layout : StorageLayout) : CompileResult Unit := do
  unless layout.markerKey == layoutMarkerKey && layout.markerValue != 0 &&
      layout.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .near "NEAR storage initialization/layout policy is not canonical"
  if layout.fields.isEmpty || layout.fields.size > limits.maxStateFields then
    throw <| .planInvariant .near "state field count is outside the profile limits"
  for index in [0:layout.fields.size] do
    let field := layout.fields[index]!
    unless field.sourceId == index && isIdentifier field.name &&
        field.key == stateKey index && field.byteWidth == 8 &&
        field.endianness == .little do
      throw <| .planInvariant .near "state field KV layout is not canonical UInt64 little-endian"
  if hasDuplicates (layout.fields.map (·.name)) ||
      hasDuplicates (layout.fields.map (·.key)) ||
      layout.fields.any (·.key == layout.markerKey) then
    throw <| .planInvariant .near "state field names/keys must be unique and distinct from the marker"
  unless layout.markerValue == layoutMarker layout.fields do
    throw <| .planInvariant .near "state layout marker is not bound to the canonical KV schema"

private def validateParams (limits : ResourceLimits) (owner : String)
    (params : Array Param) : CompileResult Unit := do
  if params.size > limits.maxParams then
    throw <| .planInvariant .near
      s!"parameter count in {owner} exceeds profile limit {limits.maxParams}"
  for index in [0:params.size] do
    let param := params[index]!
    unless param.sourceId == index && isIdentifier param.name &&
        param.inputOffset == index * 8 && param.byteWidth == 8 &&
        param.endianness == .little do
      throw <| .planInvariant .near
        s!"parameter binding in {owner} is not canonical UInt64 little-endian"
  if hasDuplicates (params.map (·.name)) then
    throw <| .planInvariant .near s!"parameter names in {owner} must be unique"

private def validateMethod (limits : ResourceLimits) (layout : StorageLayout)
    (isInitializer : Bool) (baseNodes : Nat) (method : Method) : CompileResult Nat := do
  unless isIdentifier method.name && method.name != "memory" do
    throw <| .planInvariant .near s!"method '{method.name}' is not a safe export name"
  if isInitializer then
    unless method.name == "init" && method.mode == .initialize &&
        method.depositPolicy == .requireZero do
      throw <| .planInvariant .near "initializer export identity is not canonical"
  else if method.mode == .initialize then
    throw <| .planInvariant .near "entry method cannot use initialize mode"
  unless method.depositPolicy ==
      (if method.mode == .view then .queryOnly else .requireZero) do
    throw <| .planInvariant .near s!"method '{method.name}' deposit policy is not canonical"
  validateParams limits s!"method '{method.name}'" method.params
  unless method.exactInputLen == method.params.size * 8 do
    throw <| .planInvariant .near s!"method '{method.name}' raw input length is not canonical"
  if method.body.size > limits.maxBodyStatements || (!isInitializer && method.body.isEmpty) then
    throw <| .planInvariant .near s!"method '{method.name}' has an invalid body size"
  let mut total := baseNodes
  let mut methodTemps := 0
  let mut returned := false
  for statement in method.body do
    if returned then
      throw <| .planInvariant .near s!"method '{method.name}' has a statement after return"
    match statement with
    | .store store =>
        if method.mode == .view then
          throw <| .planInvariant .near s!"view method '{method.name}' writes state"
        unless store.fieldIndex < layout.fields.size do
          throw <| .planInvariant .near s!"method '{method.name}' stores to an unknown KV field"
        total ← addPlanExprNodes limits layout method.params total store.value
        methodTemps ← addMethodExprTemps limits layout method.params methodTemps store.value
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .near "initializer cannot return a value"
        total ← addPlanExprNodes limits layout method.params total value
        methodTemps ← addMethodExprTemps limits layout method.params methodTemps value
        returned := true
  if isInitializer then
    if returned then
      throw <| .planInvariant .near "initializer cannot return a value"
  else unless returned do
    throw <| .planInvariant .near s!"method '{method.name}' does not return UInt64"
  return total

/-- Validate the public target-owned NEAR Plan before recipe lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.targetDescriptor == descriptor &&
      plan.semanticSchemaVersion == Semantic.schemaVersion &&
      plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.hostAbi == hostAbiVersion && plan.inputAbi == rawInputAbi &&
      plan.layoutDomain == stateLayoutDomain &&
      plan.hostImports == canonicalImports &&
      plan.failurePolicy == canonicalFailurePolicy &&
      plan.commitPolicy == .rollbackOnTrap &&
      plan.resourceLimits == canonicalResourceLimits do
    throw <| .planInvariant .near "NEAR Plan descriptor/schema/profile policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .near s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > plan.resourceLimits.maxArtifactStemBytes then
    throw <| .planInvariant .near
      s!"program name exceeds artifact-stem limit {plan.resourceLimits.maxArtifactStemBytes} bytes"
  validateStorageLayout plan.resourceLimits plan.storage
  if plan.entries.isEmpty || plan.entries.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .near "entry count is outside the profile limits"
  let handlerCount := 1 + plan.entries.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total method => total + method.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total method => total + method.body.size) 0
  let mut total := plan.storage.fields.size + handlerCount + paramCount + statementCount
  if total > plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .near
      s!"plan exceeds aggregate node limit {plan.resourceLimits.maxPlanNodes}"
  total ← validateMethod plan.resourceLimits plan.storage true total plan.initializer
  for method in plan.entries do
    total ← validateMethod plan.resourceLimits plan.storage false total method
  let methods := #[plan.initializer] ++ plan.entries
  if hasDuplicates (methods.map (·.name)) then
    throw <| .planInvariant .near "NEAR export names must be unique"

def makePlan (resolved : ResolvedProgram .near) : CompileResult Plan := do
  unless resolved.descriptor == descriptor do
    throw <| .planInvariant .near "resolved target descriptor does not match the NEAR profile"
  validateResolved .near descriptor resolved
  let source := resolved.source
  unless source.schemaVersion == Semantic.schemaVersion do
    throw <| .planInvariant .near
      s!"semantic schema version {source.schemaVersion} is not supported; expected {Semantic.schemaVersion}"
  validateSemanticBudget source
  unless source.requirements == Semantic.deriveRequirements source do
    throw <| .planInvariant .near "semantic requirements are not canonical for the program body"
  let initializerSource ← match source.initializer with
    | some value => pure value
    | none => throw <| .planInvariant .near "KV-state programs require an initializer"
  let storage ← makeStorageLayout source.state
  let initializer ← makeInitializer storage initializerSource
  let entries ← source.entries.mapM (makeEntry storage)
  let plan : Plan := {
    targetDescriptor := descriptor
    semanticSchemaVersion := Semantic.schemaVersion
    codegenProfile := descriptor.codegenProfile.toString
    hostAbi := hostAbiVersion
    inputAbi := rawInputAbi
    layoutDomain := stateLayoutDomain
    hostImports := canonicalImports
    failurePolicy := canonicalFailurePolicy
    commitPolicy := .rollbackOnTrap
    resourceLimits := canonicalResourceLimits
    programName := source.name
    storage
    initializer
    entries
  }
  validatePlan plan
  return plan

private def align8 (value : Nat) : Nat :=
  ((value + 7) / 8) * 8

private def makeKeyRegions (plan : Plan) : Array KeyRegion := Id.run do
  let mut regions : Array KeyRegion := #[]
  let mut offset := 0
  let markerLength := plan.storage.markerKey.toUTF8.size
  regions := regions.push { key := plan.storage.markerKey, offset, length := markerLength }
  offset := offset + markerLength
  for field in plan.storage.fields do
    let length := field.key.toUTF8.size
    regions := regions.push { key := field.key, offset, length }
    offset := offset + length
  return regions

private def maxInputLen (plan : Plan) : Nat :=
  plan.entries.foldl (fun current method => max current method.exactInputLen)
    plan.initializer.exactInputLen

private def makeMemoryLayout (plan : Plan) (keys : Array KeyRegion) : MemoryLayout :=
  let keysEnd := keys.foldl (fun current key => max current (key.offset + key.length)) 0
  let inputOffset := align8 keysEnd
  let inputCapacity := maxInputLen plan
  let depositOffset := align8 (inputOffset + inputCapacity)
  {
    minPages := plan.resourceLimits.wasmMemoryPages
    inputOffset
    inputCapacity
    depositOffset
    valueOffset := depositOffset + 16
  }

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private def fieldRegion (keys : Array KeyRegion) (fieldIndex : Nat) : KeyRegion :=
  keys[fieldIndex + 1]!

private partial def lowerExpr (keys : Array KeyRegion) (next : Nat) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param inputOffset =>
      { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .stateLoad fieldIndex =>
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr keys next lhs
      let rhs := lowerExpr keys lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }

private def lowerMethod (plan : Plan) (keys : Array KeyRegion)
    (method : Method) : MethodIR := Id.run do
  let marker := keys[0]!
  let mut operations : Array Operation := #[.checkInputLen method.exactInputLen]
  if method.depositPolicy == .requireZero then
    operations := operations.push .requireZeroAttachedDeposit
  if method.mode == .initialize then
    operations := operations.push (.requireLayoutAbsent marker)
    for index in [0:plan.storage.fields.size] do
      operations := operations.push (.zeroState (fieldRegion keys index))
  else
    operations := operations.push (.requireLayout marker plan.storage.markerValue)
  let mut next := 0
  for statement in method.body do
    match statement with
    | .store store =>
        let value := lowerExpr keys next store.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState (fieldRegion keys store.fieldIndex) value.value)
        next := value.next
    | .returnValue value =>
        let value := lowerExpr keys next value
        operations := operations ++ value.operations
        operations := operations.push (.setReturnData value.value)
        next := value.next
  if method.mode == .initialize then
    operations := operations.push (.setLayout marker plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    tempCount := next
    operations
  }

private def expectedMethods (plan : Plan) (keys : Array KeyRegion) : Array MethodIR :=
  #[lowerMethod plan keys plan.initializer] ++ plan.entries.map (lowerMethod plan keys)

/-- Validate the typed host-call recipe and bind it exactly to its source Plan. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName do
    throw <| .planInvariant .near "typed NEAR IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports && ir.registers == canonicalRegisters do
    throw <| .planInvariant .near "typed NEAR IR host imports/registers are not canonical"
  let expectedKeys := makeKeyRegions ir.sourcePlan
  unless ir.keys == expectedKeys do
    throw <| .planInvariant .near "typed NEAR IR key regions are not bound to the Plan KV layout"
  let expectedMemory := makeMemoryLayout ir.sourcePlan expectedKeys
  unless ir.memory == expectedMemory &&
      ir.memory.minPages == ir.sourcePlan.resourceLimits.wasmMemoryPages &&
      ir.memory.valueOffset + 8 <= ir.memory.minPages * wasmPageBytes do
    throw <| .planInvariant .near "typed NEAR IR memory layout is not canonical or exceeds one page"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .near "typed NEAR IR export count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
  let operationCount := ir.methods.foldl (fun total method =>
    total + method.params.size + method.operations.size) 0
  if operationCount > ir.sourcePlan.resourceLimits.maxRecipeNodes then
    throw <| .planInvariant .near
      s!"typed NEAR IR exceeds recipe node limit {ir.sourcePlan.resourceLimits.maxRecipeNodes}"
  let expected := expectedMethods ir.sourcePlan expectedKeys
  unless ir.methods == expected do
    throw <| .planInvariant .near
      "typed NEAR IR methods/operations are not the exact lowering of their source Plan"

def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    registers := canonicalRegisters
    keys
    memory
    methods := expectedMethods plan keys
  }
  validateIR ir
  return ir

private def uint64Hex (value : UInt64) : String :=
  let raw := String.ofList (Nat.toDigits 16 value.toNat)
  let raw := if raw.isEmpty then "0" else raw
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderImport : HostImport → String
  | .input => "  (import \"env\" \"input\" (func $pf_input (param i64)))\n"
  | .registerLen =>
      "  (import \"env\" \"register_len\" (func $pf_register_len (param i64) (result i64)))\n"
  | .readRegister =>
      "  (import \"env\" \"read_register\" (func $pf_read_register (param i64 i64)))\n"
  | .storageRead =>
      "  (import \"env\" \"storage_read\" (func $pf_storage_read (param i64 i64 i64) (result i64)))\n"
  | .storageWrite =>
      "  (import \"env\" \"storage_write\" (func $pf_storage_write (param i64 i64 i64 i64 i64) (result i64)))\n"
  | .valueReturn =>
      "  (import \"env\" \"value_return\" (func $pf_value_return (param i64 i64)))\n"
  | .attachedDeposit =>
      "  (import \"env\" \"attached_deposit\" (func $pf_attached_deposit (param i64)))\n"

private def renderReadKey (registers : RegisterLayout) (memory : MemoryLayout)
    (destination : Nat) (field : KeyRegion) : String :=
  s!"    (if (i64.ne (call $pf_storage_read (i64.const {field.length}) (i64.const {field.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
    s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
    s!"    (call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
    s!"    (local.set $t{destination} (i64.load (i32.const {memory.valueOffset})))\n"

private def renderOperation (registers : RegisterLayout) (memory : MemoryLayout) :
    Operation → String
  | .checkInputLen bytes =>
      s!"    (call $pf_input (i64.const {registers.input}))\n" ++
        s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.input})) (i64.const {bytes})) (then unreachable))\n" ++
        (if bytes == 0 then "" else
          s!"    (call $pf_read_register (i64.const {registers.input}) (i64.const {memory.inputOffset}))\n")
  | .requireZeroAttachedDeposit =>
      s!"    (call $pf_attached_deposit (i64.const {memory.depositOffset}))\n" ++
        s!"    (if (i64.ne (i64.load (i32.const {memory.depositOffset})) (i64.const 0)) (then unreachable))\n" ++
        s!"    (if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n"
  | .requireLayoutAbsent marker =>
      s!"    (if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 0)) (then unreachable))\n"
  | .requireLayout marker value =>
      s!"    (if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
        s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
        s!"    (call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
        s!"    (if (i64.ne (i64.load (i32.const {memory.valueOffset})) (i64.const {value.toNat})) (then unreachable))\n"
  | .zeroState field =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (i64.const 0))\n" ++
        s!"    (if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .literal destination value =>
      s!"    (local.set $t{destination} (i64.const {value.toNat}))\n"
  | .loadParam destination inputOffset =>
      s!"    (local.set $t{destination} (i64.load (i32.const {memory.inputOffset + inputOffset})))\n"
  | .loadState destination field =>
      renderReadKey registers memory destination field
  | .checkedAdd destination lhs rhs =>
      s!"    (local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"    (if (i64.lt_u (local.get $t{destination}) (local.get $t{lhs})) (then unreachable))\n"
  | .storeState field value =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"    (if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))\n" ++
        s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const 8)) (then unreachable))\n"
  | .setLayout marker value =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (i64.const {value.toNat}))\n" ++
        s!"    (if (i64.ne (call $pf_storage_write (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .setReturnData value =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"    (call $pf_value_return (i64.const 8) (i64.const {memory.valueOffset}))\n"

private def renderMethod (ir : IR) (method : MethodIR) : String :=
  let locals := String.intercalate "" <| (Array.range method.tempCount).toList.map fun index =>
    s!" (local $t{index} i64)"
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.registers ir.memory)
  s!"  (func (export \"{method.name}\"){locals}\n" ++ operations ++ "  )\n"

private def renderWat (ir : IR) : String :=
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let data := String.intercalate "" <| ir.keys.toList.map fun key =>
    s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  let methods := String.intercalate "" <| ir.methods.toList.map (renderMethod ir)
  "(module\n" ++ imports ++
    s!"  (memory (export \"memory\") {ir.memory.minPages})\n" ++ data ++ methods ++ ")\n"

private def renderMode : MethodMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderDepositPolicy : DepositPolicy → String
  | .requireZero => "zero-required"
  | .queryOnly => "query-only"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"u64-le\",\"inputOffset\":{param.inputOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StorageField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"key\":\"{Targets.escapeJson field.key}\",\"type\":\"u64-le\"}"

private def renderMethodJson (method : Method) : String :=
  let returns := if method.mode == .initialize then "null" else "\"u64-le\""
  "{" ++
    s!"\"name\":\"{Targets.escapeJson method.name}\"," ++
    s!"\"mode\":\"{renderMode method.mode}\"," ++
    s!"\"depositPolicy\":\"{renderDepositPolicy method.depositPolicy}\"," ++
    s!"\"exactInputLen\":{method.exactInputLen}," ++
    s!"\"args\":[{renderParamsJson method.params}],\"returns\":{returns}" ++
    "}"

private def renderAbi (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map renderFieldJson)
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  "{\n" ++
    "  \"schema\": \"proof-forge-near-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"storage\": {" ++
    s!"\"markerKey\":\"{plan.storage.markerKey}\"," ++
    s!"\"layoutMarker\":\"0x{uint64Hex plan.storage.markerValue}\"," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "},\n" ++
    "  \"exports\": [\n    " ++ exports ++ "\n  ]\n" ++
    "}\n"

def emit (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.wat"
      mediaType := "application/wasm-text"
      contents := renderWat ir
    },
    {
      path := s!"{ir.name}.near-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
    }
  ]

instance : Materializer .near where
  Plan := Plan
  TargetIR := IR
  makePlan := makePlan
  lower := lower
  emit := emit

end ProofForgeV2.Targets.Near
