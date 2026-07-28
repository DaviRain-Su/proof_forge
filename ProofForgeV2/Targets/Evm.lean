import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Evm.Keccak

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.evm

/-- Target-owned binding from a semantic state identity to an EVM storage slot. -/
structure StorageBinding where
  sourceId : Nat
  name : String
  slot : Nat
  deriving BEq, Inhabited, Repr

/-- Target-owned ABI word binding. `sourceId` is retained only for traceability;
all lowering after plan construction uses `wordIndex`. -/
structure Param where
  sourceId : Nat
  name : String
  wordIndex : Nat
  deriving BEq, Inhabited, Repr

/-- EVM scalar expression for the Phase-1 UInt64 fragment. Storage slots and
ABI word positions have already been selected by the plan builder. -/
inductive Expr where
  | literal (value : UInt64)
  | param (wordIndex : Nat)
  | storageLoad (slot : Nat)
  | checkedAdd (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  slot : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  deriving BEq, Inhabited, Repr

structure Constructor where
  params : Array Param
  stores : Array Store
  deriving BEq, Inhabited, Repr

inductive Mutability where
  | nonpayable
  | view
  deriving BEq, Inhabited, Repr

structure Entry where
  name : String
  selector : String
  params : Array Param
  mutability : Mutability
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Complete EVM decisions for the currently supported portable fragment.
The renderer consumes this value without consulting `SemanticProgram`. -/
structure Plan where
  objectName : String
  runtimeObjectName : String
  storageLayout : Array StorageBinding
  constructor : Option Constructor
  entries : Array Entry
  deriving BEq, Inhabited, Repr

structure IR where
  objectName : String
  yul : String
  abi : String
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .evm message

-- Profile-owned resource limits. They bound selector hashing and the current
-- array-based uniqueness checks before target lowering performs expensive work.
private def maxIdentifierBytes : Nat := 240
private def maxArtifactStemBytes : Nat := 231
private def maxStorageBindings : Nat := 1024
private def maxEntries : Nat := 1024
private def maxParams : Nat := 256
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
        rest.all (fun character => isAsciiLetter character || isAsciiDigit character || character == '_')

private def hasDuplicates [BEq α] (values : Array α) : Bool := Id.run do
  let mut seen : Array α := #[]
  for value in values do
    if seen.contains value then return true
    seen := seen.push value
  return false

private def validSelector (selector : String) : Bool :=
  selector.length == 8 && selector.toList.all (fun character =>
    "0123456789abcdef".contains character)

private def makeStorageLayout
    (states : Array Semantic.StateDecl) : CompileResult (Array StorageBinding) := do
  if states.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
  let mut layout : Array StorageBinding := #[]
  for state in states do
    unless state.type == .u64 do
      throw <| .planInvariant .evm s!"state '{state.name}' is not UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .evm s!"state name '{state.name}' is not an EVM ABI identifier"
    if layout.any (·.sourceId == state.id.value) then
      throw <| .planInvariant .evm s!"duplicate semantic state id {state.id.value}"
    unless state.id.value == layout.size do
      throw <| .planInvariant .evm "semantic state ids must match declaration order"
    layout := layout.push {
      sourceId := state.id.value
      name := state.name
      slot := layout.size
    }
  return layout

private def makeParams (owner : String)
    (params : Array Semantic.Param) : CompileResult (Array Param) := do
  if params.size > maxParams then
    throw <| .planInvariant .evm s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  for param in params do
    unless param.type == .u64 do
      throw <| .planInvariant .evm s!"parameter '{param.name}' in {owner} is not UInt64"
    unless param.visibility == .verifierVisible do
      throw <| .planInvariant .evm s!"parameter '{param.name}' in {owner} is not verifier-visible"
    unless isIdentifier param.name do
      throw <| .planInvariant .evm s!"parameter name '{param.name}' in {owner} is not an EVM ABI identifier"
    if planned.any (·.sourceId == param.id.value) then
      throw <| .planInvariant .evm s!"duplicate semantic parameter id {param.id.value} in {owner}"
    unless param.id.value == planned.size do
      throw <| .planInvariant .evm s!"semantic parameter ids in {owner} must match declaration order"
    planned := planned.push {
      sourceId := param.id.value
      name := param.name
      wordIndex := planned.size
    }
  return planned

private def findStorage (layout : Array StorageBinding)
    (id : Semantic.StateId) : CompileResult StorageBinding :=
  match layout.find? (·.sourceId == id.value) with
  | some binding => .ok binding
  | none => planError s!"semantic expression references unknown state id {id.value}"

private def findParam (params : Array Param)
    (id : Semantic.ParamId) : CompileResult Param :=
  match params.find? (·.sourceId == id.value) with
  | some param => .ok param
  | none => planError s!"semantic expression references unknown parameter id {id.value}"

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

private def validateSemanticExprBudget (program : Semantic.Program) : CompileResult Unit := do
  let initializerNodes := program.initializer.map (fun initializer =>
    1 + initializer.params.size + initializer.body.size) |>.getD 0
  let entryNodes := program.entries.foldl (fun total entry =>
    total + entry.params.size + entry.body.size) 0
  let mut total := program.state.size + program.entries.size + initializerNodes + entryNodes
  if total > maxPlanNodes then
    throw <| .planInvariant .evm s!"semantic program exceeds aggregate node limit {maxPlanNodes}"
  if let some initializer := program.initializer then
    for statement in initializer.body do
      match statement with
      | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
      | .synchronousCall .. => pure ()
  for entry in program.entries do
    for statement in entry.body do
      match statement with
      | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
      | .synchronousCall .. => pure ()

private def validateSemanticShapeBudget (program : Semantic.Program) : CompileResult Unit := do
  if program.state.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
  if program.entries.size > maxEntries then
    throw <| .planInvariant .evm s!"entry count exceeds profile limit {maxEntries}"
  if program.requirements.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .evm
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  if let some initializer := program.initializer then
    if initializer.params.size > maxParams || initializer.body.size > maxBodyStatements then
      throw <| .planInvariant .evm "initializer exceeds the profile resource limits"
  for entry in program.entries do
    if entry.params.size > maxParams || entry.body.size > maxBodyStatements then
      throw <| .planInvariant .evm s!"entry '{entry.name}' exceeds the profile resource limits"
  validateSemanticExprBudget program

private partial def makeExprUnchecked (layout : Array StorageBinding) (params : Array Param) :
    Semantic.Expr → CompileResult Expr
  | .literal value => .ok <| .literal value
  | .param id => return .param (← findParam params id).wordIndex
  | .state id => return .storageLoad (← findStorage layout id).slot
  | .checkedAdd lhs rhs => do
      let lhs ← makeExprUnchecked layout params lhs
      let rhs ← makeExprUnchecked layout params rhs
      return .checkedAdd lhs rhs

private def makeExpr (layout : Array StorageBinding) (params : Array Param)
    (expr : Semantic.Expr) : CompileResult Expr := do
  -- `makePlan` checks the aggregate budget first. Keep this local guard so
  -- future direct helper use cannot recurse into an unbounded expression.
  let _ ← addSemanticExprNodes 0 expr
  makeExprUnchecked layout params expr

private def makeStore (layout : Array StorageBinding) (params : Array Param)
    (state : Semantic.StateId) (value : Semantic.Expr) : CompileResult Store := do
  let binding ← findStorage layout state
  return { slot := binding.slot, value := ← makeExpr layout params value }

private def makeConstructor (layout : Array StorageBinding)
    (initializer : Semantic.Initializer) : CompileResult Constructor := do
  if initializer.body.size > maxBodyStatements then
    throw <| .planInvariant .evm s!"constructor body exceeds profile limit {maxBodyStatements}"
  let params ← makeParams "constructor" initializer.params
  let mut stores : Array Store := #[]
  for statement in initializer.body do
    match statement with
    | .store state value => stores := stores.push (← makeStore layout params state value)
    | .returnValue .. =>
        throw <| .planInvariant .evm "constructor cannot return a value"
    | .synchronousCall callee =>
        throw <| .planInvariant .evm s!"constructor call '{callee}' is not in the Phase-1 EVM fragment"
  return { params, stores }

private def makeEntry (layout : Array StorageBinding)
    (entry : Semantic.Entry) : CompileResult Entry := do
  if entry.body.size > maxBodyStatements then
    throw <| .planInvariant .evm s!"entry '{entry.name}' body exceeds profile limit {maxBodyStatements}"
  unless isIdentifier entry.name do
    throw <| .planInvariant .evm s!"entry name '{entry.name}' is not an EVM ABI identifier"
  unless entry.result == .u64 do
    throw <| .planInvariant .evm s!"entry '{entry.name}' does not return UInt64"
  let params ← makeParams s!"entry '{entry.name}'" entry.params
  let mut body : Array Statement := #[]
  for statement in entry.body do
    match statement with
    | .store state value =>
        body := body.push <| .store (← makeStore layout params state value)
    | .returnValue value =>
        body := body.push <| .returnValue (← makeExpr layout params value)
    | .synchronousCall callee =>
        throw <| .planInvariant .evm s!"call '{callee}' is not in the Phase-1 EVM fragment"
  let mutability := match entry.mode with
    | .mutate => Mutability.nonpayable
    | .view => Mutability.view
  return {
    name := entry.name
    selector := Keccak.selector entry.name (params.map fun _ => "uint64")
    params
    mutability
    body
  }

private partial def planExprNodes? (slots : Array Nat) (paramCount depthLeft nodeBudget : Nat)
    (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .param wordIndex => if wordIndex < paramCount then some 1 else none
    | .storageLoad slot => if slots.contains slot then some 1 else none
    | .checkedAdd lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (slots : Array Nat) (paramCount total : Nat)
    (expr : Expr) : CompileResult Nat :=
  match planExprNodes? slots paramCount maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => .ok (total + nodes)
  | none => planError
      s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

private def addPlanStoreNodes (slots : Array Nat) (paramCount total : Nat)
    (store : Store) : CompileResult Nat := do
  unless slots.contains store.slot do
    throw <| .planInvariant .evm "plan store references an unknown storage slot"
  addPlanExprNodes slots paramCount total store.value

/-- Validate the public `Evm.Plan` value before any Yul is produced. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless isIdentifier plan.objectName do
    throw <| .planInvariant .evm s!"object name '{plan.objectName}' is not a safe EVM identifier"
  if plan.objectName.toUTF8.size > maxArtifactStemBytes then
    throw <| .planInvariant .evm
      s!"object name exceeds artifact-stem limit {maxArtifactStemBytes} bytes"
  unless isIdentifier plan.runtimeObjectName && plan.runtimeObjectName != plan.objectName do
    throw <| .planInvariant .evm "runtime object name must be safe and distinct from the containing object"
  if plan.entries.isEmpty then
    throw <| .planInvariant .evm "plan has no entries"
  if plan.storageLayout.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"storage layout exceeds profile limit {maxStorageBindings}"
  if plan.entries.size > maxEntries then
    throw <| .planInvariant .evm s!"entry count exceeds profile limit {maxEntries}"
  for binding in plan.storageLayout do
    unless isIdentifier binding.name do
      throw <| .planInvariant .evm s!"storage name '{binding.name}' is not a safe identifier"
  let stateIds := plan.storageLayout.map (·.sourceId)
  let stateNames := plan.storageLayout.map (·.name)
  let slots := plan.storageLayout.map (·.slot)
  if hasDuplicates stateIds || hasDuplicates stateNames || hasDuplicates slots then
    throw <| .planInvariant .evm "storage ids, names, and slots must each be unique"
  for index in [0:plan.storageLayout.size] do
    unless plan.storageLayout[index]!.slot == index &&
        plan.storageLayout[index]!.sourceId == index do
      throw <| .planInvariant .evm "storage slots and semantic origins must match declaration order"
  let constructorNodes := plan.constructor.map (fun constructor =>
    1 + constructor.params.size + constructor.stores.size) |>.getD 0
  let entryNodes := plan.entries.foldl (fun total entry =>
    total + entry.params.size + entry.body.size) 0
  let mut totalPlanNodes := plan.storageLayout.size + plan.entries.size + constructorNodes + entryNodes
  if totalPlanNodes > maxPlanNodes then
    throw <| .planInvariant .evm s!"plan exceeds aggregate node limit {maxPlanNodes}"
  if let some constructor := plan.constructor then
    if constructor.params.size > maxParams || constructor.stores.size > maxBodyStatements then
      throw <| .planInvariant .evm "constructor exceeds the profile resource limits"
    for index in [0:constructor.params.size] do
      unless constructor.params[index]!.wordIndex == index &&
          constructor.params[index]!.sourceId == index do
        throw <| .planInvariant .evm "constructor ABI words and semantic origins must be canonical"
      unless isIdentifier constructor.params[index]!.name do
        throw <| .planInvariant .evm "constructor parameter name is not a safe ABI identifier"
    let sourceIds := constructor.params.map (·.sourceId)
    let names := constructor.params.map (·.name)
    let words := constructor.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm "constructor parameter bindings must be unique"
    for store in constructor.stores do
      totalPlanNodes ← addPlanStoreNodes slots constructor.params.size totalPlanNodes store
  for entry in plan.entries do
    unless isIdentifier entry.name && validSelector entry.selector do
      throw <| .planInvariant .evm s!"entry '{entry.name}' has an invalid ABI identity"
    if entry.params.size > maxParams || entry.body.size > maxBodyStatements then
      throw <| .planInvariant .evm s!"entry '{entry.name}' exceeds the profile resource limits"
    for index in [0:entry.params.size] do
      unless entry.params[index]!.wordIndex == index &&
          entry.params[index]!.sourceId == index do
        throw <| .planInvariant .evm
          s!"entry '{entry.name}' ABI words and semantic origins must be canonical"
      unless isIdentifier entry.params[index]!.name do
        throw <| .planInvariant .evm s!"entry '{entry.name}' parameter name is not a safe ABI identifier"
  let entryNames := plan.entries.map (·.name)
  let selectors := plan.entries.map (·.selector)
  if hasDuplicates entryNames then
    throw <| .planInvariant .evm "entry names must be unique"
  if hasDuplicates selectors then
    throw <| .planInvariant .evm "entry selectors collide"
  for entry in plan.entries do
    let expectedSelector := Keccak.selector entry.name (entry.params.map fun _ => "uint64")
    unless entry.selector == expectedSelector do
      throw <| .planInvariant .evm
        s!"entry '{entry.name}' selector is not bound to its canonical ABI signature"
    let sourceIds := entry.params.map (·.sourceId)
    let names := entry.params.map (·.name)
    let words := entry.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm s!"entry '{entry.name}' parameter bindings must be unique"
    if entry.body.isEmpty then
      throw <| .planInvariant .evm s!"entry '{entry.name}' has no body"
    let mut returned := false
    for statement in entry.body do
      if returned then
        throw <| .planInvariant .evm s!"entry '{entry.name}' has a statement after return"
      match statement with
      | .store store =>
          if entry.mutability == .view then
            throw <| .planInvariant .evm s!"view entry '{entry.name}' writes storage"
          totalPlanNodes ← addPlanStoreNodes slots entry.params.size totalPlanNodes store
      | .returnValue value =>
          totalPlanNodes ← addPlanExprNodes slots entry.params.size totalPlanNodes value
          returned := true
    unless returned do
      throw <| .planInvariant .evm s!"entry '{entry.name}' does not return"

/-- Private residual alpha → Plan body. Support already decided by capability mint;
    no supportedRequirements membership / residual resolve gate. Plan integrity
    (schema / canonical requirements / shape budget) still enforced. -/
private def makePlanFromAlpha (source : SemanticProgram) : CompileResult Plan := do
  validateRequirementEnvelope source
  unless source.schemaVersion == Semantic.schemaVersion do
    throw <| .planInvariant .evm
      s!"semantic schema version {source.schemaVersion} is not supported; expected {Semantic.schemaVersion}"
  validateSemanticShapeBudget source
  unless source.requirements == Semantic.deriveRequirements source do
    throw <| .planInvariant .evm "semantic requirements are not canonical for the program body"
  let storageLayout ← makeStorageLayout source.state
  let constructor ← source.initializer.mapM (makeConstructor storageLayout)
  if !storageLayout.isEmpty && constructor.isNone then
    throw <| .planInvariant .evm "stateful programs require an explicit initializer"
  let entries ← source.entries.mapM (makeEntry storageLayout)
  let runtimeObjectName :=
    if source.name == "__proof_forge_runtime" then
      "__proof_forge_runtime_1"
    else
      "__proof_forge_runtime"
  let plan : Plan := {
    objectName := source.name
    runtimeObjectName
    storageLayout
    constructor
    entries
  }
  validatePlan plan
  return plan

/-- Capability-gated public plan entry (S6). Residual alpha is temporary Plan-body
    data via `alphaResidualOf` after capability — not support authority. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .evm do
    throw <| .planInvariant .evm "engineering capability kind is not EVM"
  let source := CompiledProgramV1.alphaResidualOf
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromAlpha source

private structure RenderedExpr where
  code : String
  value : String
  next : Nat
  deriving Inhabited

private partial def renderExpr (indent paramPrefix : String) (next : Nat) : Expr → RenderedExpr
  | .literal value =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {value}\n", value := name, next := next + 1 }
  | .param wordIndex =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {paramPrefix}{wordIndex}\n", value := name, next := next + 1 }
  | .storageLoad slot =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := sload({slot})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if gt({lhs.value}, sub(0xffffffffffffffff, {rhs.value})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := add({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }

private def renderStores (indent paramPrefix : String) (stores : Array Store) : String := Id.run do
  let mut output := ""
  let mut next := 0
  for store in stores do
    let rendered := renderExpr indent paramPrefix next store.value
    output := output ++ rendered.code ++ s!"{indent}sstore({store.slot}, {rendered.value})\n"
    next := rendered.next
  return output

private def renderBody (indent paramPrefix : String) (body : Array Statement) : String := Id.run do
  let mut output := ""
  let mut next := 0
  for statement in body do
    match statement with
    | .store store =>
        let rendered := renderExpr indent paramPrefix next store.value
        output := output ++ rendered.code ++ s!"{indent}sstore({store.slot}, {rendered.value})\n"
        next := rendered.next
    | .returnValue value =>
        let rendered := renderExpr indent paramPrefix next value
        output := output ++ rendered.code ++
          s!"{indent}mstore(0, {rendered.value})\n{indent}return(0, 32)\n"
        next := rendered.next
  return output

private def renderConstructor (plan : Plan) : String := Id.run do
  let constructor := plan.constructor.getD { params := #[], stores := #[] }
  let argumentBytes := constructor.params.size * 32
  let mut output :=
    s!"    if callvalue() \{ revert(0, 0) }\n" ++
    s!"    let programSize := datasize(\"{plan.objectName}\")\n" ++
    s!"    if iszero(eq(codesize(), add(programSize, {argumentBytes}))) \{ revert(0, 0) }\n"
  if argumentBytes > 0 then
    output := output ++ s!"    codecopy(0, programSize, {argumentBytes})\n"
  for param in constructor.params do
    output := output ++
      s!"    let ctor_arg{param.wordIndex} := mload({param.wordIndex * 32})\n" ++
      s!"    if gt(ctor_arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
  output := output ++ renderStores "    " "ctor_arg" constructor.stores
  return output ++
    s!"    datacopy(0, dataoffset(\"{plan.runtimeObjectName}\"), datasize(\"{plan.runtimeObjectName}\"))\n" ++
    s!"    return(0, datasize(\"{plan.runtimeObjectName}\"))\n"

private def renderEntry (entry : Entry) : String := Id.run do
  let calldataBytes := 4 + entry.params.size * 32
  let mut output :=
    s!"      case 0x{entry.selector} \{\n" ++
    s!"        if iszero(eq(calldatasize(), {calldataBytes})) \{ revert(0, 0) }\n"
  for param in entry.params do
    let offset := 4 + param.wordIndex * 32
    output := output ++
      s!"        let arg{param.wordIndex} := calldataload({offset})\n" ++
      s!"        if gt(arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
  output := output ++ renderBody "        " "arg" entry.body
  return output ++ "      }\n"

private def renderYul (plan : Plan) : String :=
  let entries := plan.entries.foldl (fun output entry => output ++ renderEntry entry) ""
  s!"object \"{plan.objectName}\" \{\n  code \{\n" ++
    renderConstructor plan ++
    s!"  }\n  object \"{plan.runtimeObjectName}\" \{\n    code \{\n" ++
    "      if callvalue() { revert(0, 0) }\n" ++
    "      if lt(calldatasize(), 4) { revert(0, 0) }\n" ++
    "      switch shr(224, calldataload(0))\n" ++
    entries ++
    "      default { revert(0, 0) }\n" ++
    "    }\n  }\n}\n"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"uint64\"}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderConstructorAbi (constructor : Constructor) : String :=
  "{\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[" ++
    renderParamsJson constructor.params ++ "]}"

private def renderEntryAbi (entry : Entry) : String :=
  let mutability := match entry.mutability with
    | .nonpayable => "nonpayable"
    | .view => "view"
  "{\"type\":\"function\",\"name\":\"" ++ Targets.escapeJson entry.name ++
    "\",\"stateMutability\":\"" ++ mutability ++ "\",\"inputs\":[" ++
    renderParamsJson entry.params ++
    "],\"outputs\":[{\"name\":\"\",\"type\":\"uint64\"}]}"

private def renderAbi (plan : Plan) : String :=
  let constructor := plan.constructor.map (fun value => #[renderConstructorAbi value]) |>.getD #[]
  let entries := plan.entries.map renderEntryAbi
  let items := constructor ++ entries
  "[\n  " ++ String.intercalate ",\n  " items.toList ++ "\n]\n"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  return { objectName := plan.objectName, yul := renderYul plan, abi := renderAbi plan }

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) :=
  .ok #[
    { path := s!"{ir.objectName}.yul", mediaType := "text/yul", contents := ir.yul },
    { path := s!"{ir.objectName}.abi.json", mediaType := "application/json", contents := ir.abi }
  ]

/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files.
    Not a residual Plan→IR bypass. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← planFromCapability capability
  lower plan

/-- Capability-gated public materialize entry (S6). Sole path from residual alpha
    Plan body to emitted files for this target. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

instance : Materializer .evm where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Evm
