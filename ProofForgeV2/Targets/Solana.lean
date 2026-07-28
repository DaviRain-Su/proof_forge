import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.solana

def discriminatorDomain : String := "proof-forge-solana-v1:"
def layoutDomain : String := "proof-forge-solana-layout-v1:"
def discriminatorBytes : Nat := 8
def stateHeaderBytes : Nat := 8
def arithmeticOverflowError : Nat := 0x1001

inductive Endianness where
  | little
  deriving BEq, Inhabited, Repr

inductive OwnerPolicy where
  | currentProgram
  deriving BEq, Inhabited, Repr

inductive InitializationPolicy where
  | mustBeUninitialized
  | mustBeInitialized
  deriving BEq, Inhabited, Repr

inductive PayloadInitializationPolicy where
  | zeroAllFields
  deriving BEq, Inhabited, Repr

inductive HandlerMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

structure StateField where
  sourceId : Nat
  name : String
  accountIndex : Nat
  byteOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

structure StateAccount where
  index : Nat
  name : String
  ownerPolicy : OwnerPolicy
  exactDataLen : Nat
  headerOffset : Nat
  headerWidth : Nat
  initializedMarker : UInt64
  payloadInitialization : PayloadInitializationPolicy
  fields : Array StateField
  deriving BEq, Inhabited, Repr

structure AccountAccess where
  accountIndex : Nat
  ownerPolicy : OwnerPolicy
  exactDataLen : Nat
  signerRequired : Bool
  writableRequired : Bool
  initialization : InitializationPolicy
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  dataOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (dataOffset : Nat)
  | stateLoad (accountIndex byteOffset : Nat)
  | checkedAdd (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  accountIndex : Nat
  byteOffset : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  deriving BEq, Inhabited, Repr

structure Handler where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  accountAccess : AccountAccess
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Every Solana-specific ABI, account, layout, and dispatch decision for the
current UInt64 planning fragment. It deliberately retains no SemanticProgram. -/
structure Plan where
  codegenProfile : String
  instructionDiscriminatorDomain : String
  instructionDiscriminatorBytes : Nat
  stateLayoutDomain : String
  arithmeticOverflowError : Nat
  programName : String
  stateAccount : StateAccount
  initializer : Handler
  entries : Array Handler
  deriving BEq, Inhabited, Repr

inductive Check where
  | instructionDataLen (bytes : Nat)
  | ownerCurrentProgram (accountIndex : Nat)
  | accountDataLen (accountIndex bytes : Nat)
  | signer (accountIndex : Nat)
  | writable (accountIndex : Nat)
  | headerEquals (accountIndex byteOffset : Nat) (value : UInt64)
  deriving BEq, Inhabited, Repr

inductive Operation where
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination dataOffset : Nat)
  | loadState (destination accountIndex byteOffset : Nat)
  | checkedAdd (destination lhs rhs errorCode : Nat)
  | zeroState (accountIndex byteOffset : Nat)
  | storeState (accountIndex byteOffset value : Nat)
  | setHeader (accountIndex byteOffset : Nat) (value : UInt64)
  | setReturnData (value : Nat)
  deriving BEq, Inhabited, Repr

structure HandlerIR where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  accountAccess : AccountAccess
  checks : Array Check
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed, plan-level sBPF audit IR. It is intentionally not an ELF or an
assembler input until the pinned sBPF toolchain/backend exists.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`). -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  stateAccount : StateAccount
  handlers : Array HandlerIR
  deriving BEq, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .solana message

private def maxIdentifierBytes : Nat := 240
-- `.sbpf-plan` is the longest emitted suffix (10 bytes) under the CLI's
-- 240-byte relative-path ceiling.
private def maxArtifactStemBytes : Nat := 230
private def maxStateFields : Nat := 1024
private def maxEntries : Nat := 255
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256
private def maxPlanNodes : Nat := 100000

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

private def validDiscriminator (value : String) : Bool :=
  value.length == 2 * discriminatorBytes && value.toList.all (fun character =>
    "0123456789abcdef".contains character)

private def layoutFieldSignature (field : StateField) : String :=
  s!"{field.sourceId}:{field.name}:{field.accountIndex}:{field.byteOffset}:{field.byteWidth}:u64-le"

private def layoutSignature (fields : Array StateField) : String :=
  s!"{fields.size}|{String.intercalate "|" (fields.toList.map layoutFieldSignature)}"

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

def layoutMarker (fields : Array StateField) : UInt64 :=
  firstWordBE <| Crypto.sha256 (layoutDomain ++ layoutSignature fields).toUTF8

private def signature (name : String) (params : Array Param) : String :=
  s!"{name}({String.intercalate "," (params.toList.map fun _ => "u64")})"

def instructionDiscriminator (name : String) (params : Array Param) : String :=
  ((Crypto.sha256Hex (discriminatorDomain ++ signature name params).toUTF8).take
    (2 * discriminatorBytes)).copy

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
  if program.state.size > maxStateFields then
    throw <| .planInvariant .solana s!"state count exceeds profile limit {maxStateFields}"
  if program.entries.size > maxEntries then
    throw <| .planInvariant .solana s!"entry count exceeds profile limit {maxEntries}"
  let initializer ← match program.initializer with
    | some value => pure value
    | none => throw <| .planInvariant .solana "state-account programs require an initializer"
  if initializer.params.size > maxParams || initializer.body.size > maxBodyStatements then
    throw <| .planInvariant .solana "initializer exceeds the profile resource limits"
  for entry in program.entries do
    if entry.params.size > maxParams || entry.body.size > maxBodyStatements then
      throw <| .planInvariant .solana s!"entry '{entry.name}' exceeds the profile resource limits"
  let initializerNodes := 1 + initializer.params.size + initializer.body.size
  let entryNodes := program.entries.foldl (fun total entry =>
    total + 1 + entry.params.size + entry.body.size) 0
  let mut total := program.state.size + initializerNodes + entryNodes
  if total > maxPlanNodes then
    throw <| .planInvariant .solana s!"semantic program exceeds aggregate node limit {maxPlanNodes}"
  for statement in initializer.body do
    match statement with
    | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
    | .synchronousCall .. => pure ()
  for entry in program.entries do
    for statement in entry.body do
      match statement with
      | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
      | .synchronousCall .. => pure ()

private def makeStateAccount
    (states : Array Semantic.StateDecl) : CompileResult StateAccount := do
  if states.isEmpty then
    throw <| .planInvariant .solana "the current Solana profile requires persistent UInt64 state"
  let mut fields : Array StateField := #[]
  for state in states do
    unless state.type == .u64 do
      throw <| .planInvariant .solana s!"state '{state.name}' is not UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .solana s!"state name '{state.name}' is not a safe identifier"
    unless state.id.value == fields.size do
      throw <| .planInvariant .solana "semantic state ids must match declaration order"
    fields := fields.push {
      sourceId := state.id.value
      name := state.name
      accountIndex := 0
      byteOffset := stateHeaderBytes + fields.size * 8
      byteWidth := 8
      endianness := .little
    }
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .solana
      "state layout marker collides with the reserved uninitialized zero value"
  return {
    index := 0
    name := "state"
    ownerPolicy := .currentProgram
    exactDataLen := stateHeaderBytes + fields.size * 8
    headerOffset := 0
    headerWidth := stateHeaderBytes
    initializedMarker := marker
    payloadInitialization := .zeroAllFields
    fields
  }

private def makeParams (owner : String)
    (params : Array Semantic.Param) : CompileResult (Array Param) := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  for param in params do
    unless param.type == .u64 do
      throw <| .planInvariant .solana s!"parameter '{param.name}' in {owner} is not UInt64"
    unless param.visibility == .verifierVisible do
      throw <| .planInvariant .solana
        s!"parameter '{param.name}' in {owner} is not verifier-visible"
    unless isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    unless param.id.value == planned.size do
      throw <| .planInvariant .solana
        s!"semantic parameter ids in {owner} must match declaration order"
    planned := planned.push {
      sourceId := param.id.value
      name := param.name
      dataOffset := discriminatorBytes + planned.size * 8
      byteWidth := 8
      endianness := .little
    }
  return planned

private def findField (account : StateAccount)
    (id : Semantic.StateId) : CompileResult StateField :=
  match account.fields.find? (·.sourceId == id.value) with
  | some field => .ok field
  | none => planError s!"semantic expression references unknown state id {id.value}"

private def findParam (params : Array Param)
    (id : Semantic.ParamId) : CompileResult Param :=
  match params.find? (·.sourceId == id.value) with
  | some param => .ok param
  | none => planError s!"semantic expression references unknown parameter id {id.value}"

private partial def makeExprUnchecked (account : StateAccount) (params : Array Param) :
    Semantic.Expr → CompileResult Expr
  | .literal value => .ok <| .literal value
  | .param id => return .param (← findParam params id).dataOffset
  | .state id => do
      let field ← findField account id
      return .stateLoad field.accountIndex field.byteOffset
  | .checkedAdd lhs rhs => do
      let lhs ← makeExprUnchecked account params lhs
      let rhs ← makeExprUnchecked account params rhs
      return .checkedAdd lhs rhs

private def makeExpr (account : StateAccount) (params : Array Param)
    (expr : Semantic.Expr) : CompileResult Expr := do
  let _ ← addSemanticExprNodes 0 expr
  makeExprUnchecked account params expr

private def makeStore (account : StateAccount) (params : Array Param)
    (state : Semantic.StateId) (value : Semantic.Expr) : CompileResult Store := do
  let field ← findField account state
  return {
    accountIndex := field.accountIndex
    byteOffset := field.byteOffset
    value := ← makeExpr account params value
  }

private def makeBody (account : StateAccount) (params : Array Param)
    (owner : String) (isInitializer : Bool)
    (body : Array Semantic.Statement) : CompileResult (Array Statement) := do
  let mut planned : Array Statement := #[]
  for statement in body do
    match statement with
    | .store state value =>
        planned := planned.push <| .store (← makeStore account params state value)
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .solana "initializer cannot return a value"
        planned := planned.push <| .returnValue (← makeExpr account params value)
    | .synchronousCall callee =>
        throw <| .planInvariant .solana
          s!"call '{callee}' in {owner} is not in the Phase-1 Solana fragment"
  return planned

private def accessFor (account : StateAccount) (mode : HandlerMode) : AccountAccess := {
  accountIndex := account.index
  ownerPolicy := .currentProgram
  exactDataLen := account.exactDataLen
  signerRequired := mode == .initialize
  writableRequired := mode != .view
  initialization := if mode == .initialize then
    .mustBeUninitialized
  else
    .mustBeInitialized
}

private def makeInitializer (account : StateAccount)
    (initializer : Semantic.Initializer) : CompileResult Handler := do
  let params ← makeParams "initializer" initializer.params
  let body ← makeBody account params "initializer" true initializer.body
  let handler : Handler := {
    name := "initialize"
    discriminator := ""
    params
    mode := .initialize
    accountAccess := accessFor account .initialize
    body
  }
  return { handler with discriminator := instructionDiscriminator handler.name handler.params }

private def makeEntry (account : StateAccount)
    (entry : Semantic.Entry) : CompileResult Handler := do
  unless isIdentifier entry.name do
    throw <| .planInvariant .solana s!"entry name '{entry.name}' is not a safe identifier"
  unless entry.result == .u64 do
    throw <| .planInvariant .solana s!"entry '{entry.name}' does not return UInt64"
  let params ← makeParams s!"entry '{entry.name}'" entry.params
  let body ← makeBody account params s!"entry '{entry.name}'" false entry.body
  let mode := match entry.mode with
    | .mutate => HandlerMode.mutate
    | .view => HandlerMode.view
  let handler : Handler := {
    name := entry.name
    discriminator := ""
    params
    mode
    accountAccess := accessFor account mode
    body
  }
  return { handler with discriminator := instructionDiscriminator handler.name handler.params }

private partial def planExprNodes? (account : StateAccount) (params : Array Param)
    (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .param dataOffset => if params.any (·.dataOffset == dataOffset) then some 1 else none
    | .stateLoad accountIndex byteOffset =>
        if account.fields.any (fun field =>
            field.accountIndex == accountIndex && field.byteOffset == byteOffset) then
          some 1
        else
          none
    | .checkedAdd lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? account params childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (account : StateAccount) (params : Array Param)
    (total : Nat) (expr : Expr) : CompileResult Nat :=
  match planExprNodes? account params maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => .ok (total + nodes)
  | none => planError
      s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

private def validateStateAccount (account : StateAccount) : CompileResult Unit := do
  unless account.index == 0 && account.name == "state" &&
      account.ownerPolicy == .currentProgram do
    throw <| .planInvariant .solana "state account identity/owner policy is not canonical"
  unless account.headerOffset == 0 && account.headerWidth == stateHeaderBytes &&
      account.initializedMarker != 0 &&
      account.initializedMarker == layoutMarker account.fields &&
      account.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .solana "state account header is not canonical"
  if account.fields.isEmpty || account.fields.size > maxStateFields then
    throw <| .planInvariant .solana "state account field count is outside the profile limits"
  unless account.exactDataLen == stateHeaderBytes + account.fields.size * 8 do
    throw <| .planInvariant .solana "state account exact data length does not match its fields"
  let sourceIds := account.fields.map (·.sourceId)
  let names := account.fields.map (·.name)
  let offsets := account.fields.map (·.byteOffset)
  if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana "state field origins, names, and offsets must be unique"
  for index in [0:account.fields.size] do
    let field := account.fields[index]!
    unless field.sourceId == index && field.accountIndex == account.index &&
        field.byteOffset == stateHeaderBytes + index * 8 && field.byteWidth == 8 &&
        field.endianness == .little && isIdentifier field.name do
      throw <| .planInvariant .solana "state field layout is not canonical UInt64 little-endian"

private def validateParams (owner : String) (params : Array Param) : CompileResult Unit := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let sourceIds := params.map (·.sourceId)
  let names := params.map (·.name)
  let offsets := params.map (·.dataOffset)
  if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana s!"parameter bindings in {owner} must be unique"
  for index in [0:params.size] do
    let param := params[index]!
    unless param.sourceId == index && param.dataOffset == discriminatorBytes + index * 8 &&
        param.byteWidth == 8 && param.endianness == .little && isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter binding in {owner} is not canonical UInt64 little-endian"

private def expectedAccess (account : StateAccount) (mode : HandlerMode) : AccountAccess :=
  accessFor account mode

private def validateHandler (account : StateAccount) (isInitializer : Bool)
    (baseNodes : Nat) (handler : Handler) : CompileResult Nat := do
  unless isIdentifier handler.name && validDiscriminator handler.discriminator do
    throw <| .planInvariant .solana s!"handler '{handler.name}' has an invalid ABI identity"
  if isInitializer then
    unless handler.name == "initialize" && handler.mode == .initialize do
      throw <| .planInvariant .solana "initializer handler identity is not canonical"
  else
    if handler.mode == .initialize then
      throw <| .planInvariant .solana "entry handler cannot use initialize mode"
  validateParams s!"handler '{handler.name}'" handler.params
  unless handler.discriminator == instructionDiscriminator handler.name handler.params do
    throw <| .planInvariant .solana
      s!"handler '{handler.name}' discriminator is not bound to its canonical signature"
  unless handler.accountAccess == expectedAccess account handler.mode do
    throw <| .planInvariant .solana s!"handler '{handler.name}' account access is not canonical"
  if handler.body.isEmpty || handler.body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"handler '{handler.name}' has an invalid body size"
  let mut total := baseNodes
  let mut returned := false
  for statement in handler.body do
    if returned then
      throw <| .planInvariant .solana s!"handler '{handler.name}' has a statement after return"
    match statement with
    | .store store =>
        if handler.mode == .view then
          throw <| .planInvariant .solana s!"view handler '{handler.name}' writes state"
        unless account.fields.any (fun field =>
            field.accountIndex == store.accountIndex && field.byteOffset == store.byteOffset) do
          throw <| .planInvariant .solana s!"handler '{handler.name}' stores to an unknown field"
        total ← addPlanExprNodes account handler.params total store.value
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .solana "initializer cannot return a value"
        total ← addPlanExprNodes account handler.params total value
        returned := true
  if isInitializer then
    if returned then
      throw <| .planInvariant .solana "initializer cannot return a value"
  else unless returned do
    throw <| .planInvariant .solana s!"handler '{handler.name}' does not return UInt64"
  return total

/-- Validate the public target-owned Plan before typed IR lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.instructionDiscriminatorDomain == discriminatorDomain &&
      plan.instructionDiscriminatorBytes == discriminatorBytes &&
      plan.stateLayoutDomain == layoutDomain &&
      plan.arithmeticOverflowError == arithmeticOverflowError do
    throw <| .planInvariant .solana "Solana Plan profile/error policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .solana s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > maxArtifactStemBytes then
    throw <| .planInvariant .solana
      s!"program name exceeds artifact-stem limit {maxArtifactStemBytes} bytes"
  validateStateAccount plan.stateAccount
  if plan.entries.isEmpty || plan.entries.size > maxEntries then
    throw <| .planInvariant .solana "entry count is outside the profile limits"
  let handlerCount := 1 + plan.entries.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total handler => total + handler.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total handler => total + handler.body.size) 0
  let mut total := plan.stateAccount.fields.size + handlerCount + paramCount + statementCount
  if total > maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  total ← validateHandler plan.stateAccount true total plan.initializer
  for handler in plan.entries do
    total ← validateHandler plan.stateAccount false total handler
  let handlers := #[plan.initializer] ++ plan.entries
  if hasDuplicates (handlers.map (·.name)) then
    throw <| .planInvariant .solana "handler names must be unique"
  if hasDuplicates (handlers.map (·.discriminator)) then
    throw <| .planInvariant .solana "handler discriminators collide"

/-- Private residual alpha → Plan body. Support already decided by capability mint. -/
private def makePlanFromAlpha (source : SemanticProgram) : CompileResult Plan := do
  validateRequirementEnvelope source
  unless source.schemaVersion == Semantic.schemaVersion do
    throw <| .planInvariant .solana
      s!"semantic schema version {source.schemaVersion} is not supported; expected {Semantic.schemaVersion}"
  validateSemanticBudget source
  unless source.requirements == Semantic.deriveRequirements source do
    throw <| .planInvariant .solana "semantic requirements are not canonical for the program body"
  let initializerSource ← match source.initializer with
    | some value => pure value
    | none => throw <| .planInvariant .solana "state-account programs require an initializer"
  let stateAccount ← makeStateAccount source.state
  let initializer ← makeInitializer stateAccount initializerSource
  let entries ← source.entries.mapM (makeEntry stateAccount)
  let plan : Plan := {
    codegenProfile := descriptor.codegenProfile.toString
    instructionDiscriminatorDomain := discriminatorDomain
    instructionDiscriminatorBytes := discriminatorBytes
    stateLayoutDomain := layoutDomain
    arithmeticOverflowError
    programName := source.name
    stateAccount
    initializer
    entries
  }
  validatePlan plan
  return plan

/-- Capability-gated public plan entry (S6). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let source := CompiledProgramV1.alphaResidualOf
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromAlpha source

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private partial def lowerExpr (overflowError next : Nat) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param dataOffset =>
      { operations := #[.loadParam next dataOffset], value := next, next := next + 1 }
  | .stateLoad accountIndex byteOffset =>
      { operations := #[.loadState next accountIndex byteOffset], value := next, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr overflowError next lhs
      let rhs := lowerExpr overflowError lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }

private def checksFor (discriminatorWidth : Nat) (account : StateAccount)
    (handler : Handler) : Array Check := Id.run do
  let access := handler.accountAccess
  let headerValue := match access.initialization with
    | .mustBeUninitialized => 0
    | .mustBeInitialized => account.initializedMarker
  let mut checks := #[
    .instructionDataLen (discriminatorWidth + handler.params.size * 8),
    .ownerCurrentProgram access.accountIndex,
    .accountDataLen access.accountIndex access.exactDataLen
  ]
  if access.signerRequired then checks := checks.push (.signer access.accountIndex)
  if access.writableRequired then checks := checks.push (.writable access.accountIndex)
  return checks.push (.headerEquals access.accountIndex account.headerOffset headerValue)

private def lowerHandler (plan : Plan) (handler : Handler) : HandlerIR := Id.run do
  let account := plan.stateAccount
  let mut operations : Array Operation :=
    if handler.mode == .initialize then
      account.fields.map fun field => .zeroState field.accountIndex field.byteOffset
    else
      #[]
  let mut next := 0
  for statement in handler.body do
    match statement with
    | .store store =>
        let value := lowerExpr plan.arithmeticOverflowError next store.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState store.accountIndex store.byteOffset value.value)
        next := value.next
    | .returnValue value =>
        let value := lowerExpr plan.arithmeticOverflowError next value
        operations := operations ++ value.operations
        operations := operations.push (.setReturnData value.value)
        next := value.next
  if handler.mode == .initialize then
    operations := operations.push <|
      .setHeader account.index account.headerOffset account.initializedMarker
  return {
    name := handler.name
    discriminator := handler.discriminator
    params := handler.params
    mode := handler.mode
    accountAccess := handler.accountAccess
    checks := checksFor plan.instructionDiscriminatorBytes account handler
    operations
  }

private def tempDestination? : Operation → Option Nat
  | .literal destination .. | .loadParam destination .. |
      .loadState destination .. | .checkedAdd destination .. => some destination
  | _ => none

private def validateHandlerIR (plan : Plan) (handler : HandlerIR) : CompileResult Unit := do
  let account := plan.stateAccount
  unless isIdentifier handler.name && validDiscriminator handler.discriminator do
    throw <| .planInvariant .solana "typed Solana IR has an invalid handler identity"
  validateParams s!"IR handler '{handler.name}'" handler.params
  unless handler.discriminator == instructionDiscriminator handler.name handler.params do
    throw <| .planInvariant .solana "typed Solana IR discriminator does not match its ABI signature"
  unless handler.accountAccess == expectedAccess account handler.mode do
    throw <| .planInvariant .solana "typed Solana IR account access is not canonical"
  let planHandler : Handler := {
    name := handler.name
    discriminator := handler.discriminator
    params := handler.params
    mode := handler.mode
    accountAccess := handler.accountAccess
    body := #[.returnValue (.literal 0)]
  }
  unless handler.checks == checksFor plan.instructionDiscriminatorBytes account planHandler do
    throw <| .planInvariant .solana "typed Solana IR checks are incomplete or out of order"
  let fieldOffsets := account.fields.map (·.byteOffset)
  let paramOffsets := handler.params.map (·.dataOffset)
  let mut next := 0
  let mut returned := false
  let mut initialized := false
  for operation in handler.operations do
    if returned || initialized then
      throw <| .planInvariant .solana "typed Solana IR has an operation after its terminator"
    if let some destination := tempDestination? operation then
      unless destination == next do
        throw <| .planInvariant .solana "typed Solana IR temporary numbering is not canonical"
      next := next + 1
    match operation with
    | .literal .. => pure ()
    | .loadParam _ dataOffset =>
        unless paramOffsets.contains dataOffset do
          throw <| .planInvariant .solana "typed Solana IR loads an unknown parameter offset"
    | .loadState _ accountIndex byteOffset =>
        unless accountIndex == account.index && fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana "typed Solana IR loads an unknown state field"
    | .checkedAdd _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-add operands/error are invalid"
    | .zeroState accountIndex byteOffset =>
        unless handler.mode == .initialize && accountIndex == account.index &&
            fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana "typed Solana IR zeroes an unknown state field"
    | .storeState accountIndex byteOffset value =>
        unless handler.mode != .view && accountIndex == account.index &&
            fieldOffsets.contains byteOffset && value < next do
          throw <| .planInvariant .solana "typed Solana IR store is invalid"
    | .setHeader accountIndex byteOffset value =>
        unless handler.mode == .initialize && accountIndex == account.index &&
            byteOffset == account.headerOffset && value == account.initializedMarker do
          throw <| .planInvariant .solana "typed Solana IR header write is invalid"
        initialized := true
    | .setReturnData value =>
        unless handler.mode != .initialize && value < next do
          throw <| .planInvariant .solana "typed Solana IR return value is invalid"
        returned := true
  if handler.mode == .initialize then
    unless initialized do
      throw <| .planInvariant .solana "initializer IR does not set the initialized marker"
  else unless returned do
    throw <| .planInvariant .solana "entry IR does not set UInt64 return data"

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName &&
      ir.stateAccount == ir.sourcePlan.stateAccount do
    throw <| .planInvariant .solana "typed Solana IR identity/layout is not bound to its source Plan"
  unless isIdentifier ir.name && ir.name.toUTF8.size <= maxArtifactStemBytes do
    throw <| .planInvariant .solana "typed Solana IR has an unsafe artifact name"
  validateStateAccount ir.stateAccount
  if ir.handlers.size < 2 || ir.handlers.size > maxEntries + 1 then
    throw <| .planInvariant .solana "typed Solana IR handler count is outside the profile limits"
  unless ir.handlers[0]!.mode == .initialize && ir.handlers[0]!.name == "initialize" do
    throw <| .planInvariant .solana "typed Solana IR must begin with the canonical initializer"
  for index in [1:ir.handlers.size] do
    if ir.handlers[index]!.mode == .initialize then
      throw <| .planInvariant .solana "typed Solana IR may contain only one initializer"
  if hasDuplicates (ir.handlers.map (·.name)) ||
      hasDuplicates (ir.handlers.map (·.discriminator)) then
    throw <| .planInvariant .solana "typed Solana IR handler identities must be unique"
  let operationCount := ir.handlers.foldl (fun total handler =>
    total + handler.checks.size + handler.operations.size + handler.params.size) 0
  if operationCount > maxPlanNodes then
    throw <| .planInvariant .solana "typed Solana IR exceeds the aggregate node limit"
  for handler in ir.handlers do
    validateHandlerIR ir.sourcePlan handler
  let expectedHandlers := #[lowerHandler ir.sourcePlan ir.sourcePlan.initializer] ++
    ir.sourcePlan.entries.map (lowerHandler ir.sourcePlan)
  unless ir.handlers == expectedHandlers do
    throw <| .planInvariant .solana "typed Solana IR operations are not the exact lowering of its source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let handlers := #[lowerHandler plan plan.initializer] ++
    plan.entries.map (lowerHandler plan)
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    stateAccount := plan.stateAccount
    handlers
  }
  validateIR ir
  return ir

private def renderMode : HandlerMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderInitialization : InitializationPolicy → String
  | .mustBeUninitialized => "uninitialized"
  | .mustBeInitialized => "initialized"

private def natHex (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def uint64Hex (value : UInt64) : String :=
  let raw := natHex value.toNat
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderCheck : Check → String
  | .instructionDataLen bytes => s!"  check instruction_data_len == {bytes}\n"
  | .ownerCurrentProgram accountIndex =>
      s!"  check account[{accountIndex}].owner == current_program\n"
  | .accountDataLen accountIndex bytes =>
      s!"  check account[{accountIndex}].data_len == {bytes}\n"
  | .signer accountIndex => s!"  check account[{accountIndex}].is_signer\n"
  | .writable accountIndex => s!"  check account[{accountIndex}].is_writable\n"
  | .headerEquals accountIndex byteOffset value =>
      s!"  check load_u64_le(account[{accountIndex}].data + {byteOffset}) == 0x{uint64Hex value}\n"

private def renderOperation : Operation → String
  | .literal destination value => s!"  %{destination} = const_u64 {value}\n"
  | .loadParam destination dataOffset =>
      s!"  %{destination} = load_u64_le(instruction_data + {dataOffset})\n"
  | .loadState destination accountIndex byteOffset =>
      s!"  %{destination} = load_u64_le(account[{accountIndex}].data + {byteOffset})\n"
  | .checkedAdd destination lhs rhs errorCode =>
      s!"  %{destination} = checked_add_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .zeroState accountIndex byteOffset =>
      s!"  zero_u64_le account[{accountIndex}].data + {byteOffset}\n"
  | .storeState accountIndex byteOffset value =>
      s!"  store_u64_le account[{accountIndex}].data + {byteOffset}, %{value}\n"
  | .setHeader accountIndex byteOffset value =>
      s!"  store_u64_le account[{accountIndex}].data + {byteOffset}, 0x{uint64Hex value}\n"
  | .setReturnData value => s!"  set_return_data_u64_le %{value}\n"

private def renderHandlerPlan (handler : HandlerIR) : String :=
  let checks := handler.checks.foldl (fun output check => output ++ renderCheck check) ""
  let operations := handler.operations.foldl (fun output operation =>
    output ++ renderOperation operation) ""
  s!".handler {handler.discriminator} {handler.name} mode={renderMode handler.mode}\n" ++
    checks ++ operations ++ ".end-handler\n"

private def renderPlanText (ir : IR) : String :=
  let account := ir.stateAccount
  let fields := account.fields.foldl (fun output field => output ++
    s!"; field source_id={field.sourceId} name={field.name} account={field.accountIndex} offset={field.byteOffset} type=u64-le\n") ""
  let handlers := ir.handlers.foldl (fun output handler =>
    output ++ renderHandlerPlan handler) ""
  "; PROOF-FORGE-SBPF-PLAN v1\n" ++
    "; PLAN-ONLY NON-EXECUTABLE: no sBPF instructions, object, or ELF are present\n" ++
    s!"; codegen-profile: {ir.sourcePlan.codegenProfile}\n" ++
    s!"; program: {ir.name}\n" ++
    s!"; state-account index={account.index} owner=current-program exact-data-len={account.exactDataLen}\n" ++
    s!"; header offset={account.headerOffset} type=u64-le initialized-marker=0x{uint64Hex account.initializedMarker} layout-domain={ir.sourcePlan.stateLayoutDomain}\n" ++
    "; initializer-payload-policy: zero-all-fields\n" ++
    fields ++ handlers

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"u64\",\"dataOffset\":{param.dataOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StateField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"offset\":{field.byteOffset},\"type\":\"u64-le\"}"

private def renderHandlerJson (handler : HandlerIR) : String :=
  let access := handler.accountAccess
  let signer := if access.signerRequired then "true" else "false"
  let writable := if access.writableRequired then "true" else "false"
  let returns := if handler.mode == .initialize then "null" else "\"u64-le\""
  "{" ++
    s!"\"name\":\"{Targets.escapeJson handler.name}\"," ++
    s!"\"discriminator\":\"{handler.discriminator}\"," ++
    s!"\"mode\":\"{renderMode handler.mode}\"," ++
    "\"accounts\":[{" ++
    s!"\"name\":\"state\",\"index\":{access.accountIndex}," ++
    "\"owner\":\"current-program\"," ++
    s!"\"isSigner\":{signer},\"isWritable\":{writable}," ++
    s!"\"initialization\":\"{renderInitialization access.initialization}\"" ++
    "}]," ++
    s!"\"args\":[{renderParamsJson handler.params}],\"returns\":{returns}" ++
    "}"

private def renderIdl (ir : IR) : String :=
  let account := ir.stateAccount
  let fields := String.intercalate "," (account.fields.toList.map renderFieldJson)
  let handlers := String.intercalate ",\n    " (ir.handlers.toList.map renderHandlerJson)
  "{\n" ++
    "  \"version\": \"proof-forge-solana-idl/v1\",\n" ++
    s!"  \"name\": \"{Targets.escapeJson ir.name}\",\n" ++
    s!"  \"codegenProfile\": \"{ir.sourcePlan.codegenProfile}\",\n" ++
    "  \"deployable\": false,\n" ++
    "  \"instructionEncoding\": {" ++
    s!"\"discriminator\":\"sha256-prefix-{ir.sourcePlan.instructionDiscriminatorBytes}\"," ++
    s!"\"domain\":\"{ir.sourcePlan.instructionDiscriminatorDomain}\"," ++
    "\"arguments\":\"packed-u64-le\",\"trailingBytes\":\"reject\"},\n" ++
    "  \"accounts\": [{" ++
    s!"\"name\":\"state\",\"index\":{account.index}," ++
    "\"owner\":\"current-program\"," ++
    s!"\"exactDataLen\":{account.exactDataLen}," ++
    s!"\"header\":\{\"offset\":{account.headerOffset},\"type\":\"u64-le\",\"initializedMarker\":\"0x{uint64Hex account.initializedMarker}\",\"layoutDomain\":\"{ir.sourcePlan.stateLayoutDomain}\"}," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "}],\n" ++
    "  \"instructions\": [\n    " ++ handlers ++ "\n  ]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.sbpf-plan"
      mediaType := "application/vnd.proof-forge.sbpf-plan"
      contents := renderPlanText ir
    },
    {
      path := s!"{ir.name}.idl.json"
      mediaType := "application/json"
      contents := renderIdl ir
    }
  ]

/-- Replace handlers on an existing IR (private `mk`; for validateIR characterization). -/
def withHandlers (ir : IR) (handlers : Array HandlerIR) : IR :=
  { ir with handlers }

/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← planFromCapability capability
  lower plan

/-- Capability-gated public materialize entry (S6). -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

instance : Materializer .solana where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Solana
