import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.solana

def discriminatorDomain : String := "proof-forge-solana-v1:"
def layoutDomain : String := "proof-forge-solana-layout-v1:"
def discriminatorBytes : Nat := 8
def stateHeaderBytes : Nat := 8
def arithmeticOverflowError : Nat := 0x1001
def assertionFailedError : Nat := 0x1002

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

/-- Entry/view return ABI kind. Init handlers ignore this field (IDL `null`).
    Bool is a single-byte 0/1 return-data payload; UInt64 remains 8-byte LE. -/
inductive ResultKind where
  | u64
  | bool
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

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (dataOffset : Nat)
  | stateLoad (accountIndex byteOffset : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  accountIndex : Nat
  byteOffset : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  | assert (condition : Expr)
  | conditional (condition : Expr) (thenBody elseBody : Array Statement)
  deriving BEq, Inhabited, Repr

structure Handler where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  resultKind : ResultKind
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
  assertionFailedError : Nat
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
  | checkedSub (destination lhs rhs errorCode : Nat)
  | zeroState (accountIndex byteOffset : Nat)
  | storeState (accountIndex byteOffset value : Nat)
  | setHeader (accountIndex byteOffset : Nat) (value : UInt64)
  | setReturnData (value : Nat)
  | setReturnDataBool (value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat) (errorCode : Nat)
  | conditional (condition : Nat) (thenOps elseOps : Array Operation)
  deriving BEq, Inhabited, Repr

structure HandlerIR where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  resultKind : ResultKind
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

private def accessFor (account : StateAccount) (mode : HandlerMode) : AccountAccess := {
  accountIndex := account.index
  ownerPolicy := account.ownerPolicy
  exactDataLen := account.exactDataLen
  signerRequired := mode == .initialize
  writableRequired := mode != .view
  initialization := if mode == .initialize then
    .mustBeUninitialized
  else
    .mustBeInitialized
}

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering -/

private structure SolanaTypeClosureV1 where
  uint64TypeId : TypeIdV1
  unitTypeId : Option TypeIdV1
  boolTypeId : Option TypeIdV1

private def validateSolanaTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult SolanaTypeClosureV1 := do
  let mut uint64TypeId : Option TypeIdV1 := none
  let mut unitTypeId : Option TypeIdV1 := none
  let mut boolTypeId : Option TypeIdV1 := none
  for decl in types do
    unless decl.name.isNone do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: named types are outside the current UInt64 pilot"
    match decl.shape with
    | .uint width =>
        unless width.toNat == 64 && uint64TypeId.isNone do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: expected one anonymous UInt64 type"
        uint64TypeId := some decl.id
    | .unit =>
        unless unitTypeId.isNone do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: duplicate Unit type"
        unitTypeId := some decl.id
    | .bool =>
        unless boolTypeId.isNone do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: duplicate Bool type"
        boolTypeId := some decl.id
    | _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: only UInt64, Unit, and Bool are supported"
  let resolvedUInt64TypeId ← match uint64TypeId with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: UInt64 type is missing")
  pure { uint64TypeId := resolvedUInt64TypeId, unitTypeId, boolTypeId }

private def makeStateAccountV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult StateAccount := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .solana "state count is outside the profile limits"
  let mut fields : Array StateField := #[]
  for state in states do
    unless state.id.toNat == fields.size do
      throw <| .planInvariant .solana "semantic state ids must match declaration order"
    unless state.typeId == uint64TypeId && state.visibility == .public_ do
      throw <| .planInvariant .solana s!"state '{state.name}' is not public UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .solana s!"state name '{state.name}' is not a safe identifier"
    fields := fields.push {
      sourceId := state.id.toNat
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
  pure {
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

private structure LoweredValueV1 where
  expr : Expr
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  isBool : Bool
  deriving Inhabited

private def makeParamsV1 (owner : String) (uint64TypeId : TypeIdV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .solana
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless param.typeId == uint64TypeId && param.visibility == .public_ do
      throw <| .planInvariant .solana
        s!"parameter '{param.name}' in {owner} is not public UInt64"
    unless isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      dataOffset := discriminatorBytes + planned.size * 8
      byteWidth := 8
      endianness := .little
    }
    planned := planned.push binding
    values := values.push {
      expr := .param binding.dataOffset
      depth := 1
      expandedNodes := 1
      dependencies := #[]
      isBool := false
    }
  pure (planned, values)

private def findFieldV1 (account : StateAccount)
    (id : StateIdV1) : CompileResult StateField :=
  match account.fields[id.toNat]? with
  | some field =>
      if field.sourceId == id.toNat then .ok field
      else planError s!"semantic expression references noncanonical state id {id.toNat}"
  | none => planError s!"semantic expression references unknown state id {id.toNat}"

private def findValueV1 (values : Array LoweredValueV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 :=
  match values[id.toNat]? with
  | some value => .ok value
  | none => planError s!"semantic expression references unknown ValueId {id.toNat}"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: invalid UInt64 literal"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: trailing UInt64 literal bytes"

private def findResultTypeV1 (callable : CallableV1)
    (id : ValueIdV1) : CompileResult TypeIdV1 := do
  for param in callable.params do if param.valueId == id then return param.typeId
  for block in callable.blocks do
    for param in block.params do if param.valueId == id then return param.typeId
    for instruction in block.instructions do
      if let some result := instruction.result then
        if result.valueId == id then return result.typeId
  throw <| .planInvariant .solana s!"unknown semantic ValueId {id.toNat}"

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool := do
  unless bytes.size == 1 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: Bool literal must contain exactly 1 byte"
  match bytes[0]!.toNat with
  | 0 => pure false
  | 1 => pure true
  | _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: Bool literal must be 0x00 or 0x01"

private def currentValueV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1)
    (isBool : Bool) : CompileResult LoweredValueV1 := do
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
    isBool
  }

private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedAdd lhsId rhsId lhs rhs false

private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedSub lhsId rhsId lhs rhs false

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (.compare op) lhsId rhsId lhs rhs true

private def consumeCurrentSegmentV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (root : ValueIdV1) : CompileResult Expr := do
  let rootValue ← currentValueV1 values paramCount segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  if root.toNat >= paramCount then
    stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: dead or reordered value instructions"
  pure rootValue.expr

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: result ValueId/type is not canonical"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .solana s!"Solana value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private def comparisonOpOfV1 : BinaryOpV1 → Option ComparisonOp
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement
  deriving Nonempty

private partial def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (callable : CallableV1)
    (nonterminal : Bool := false)
    (switchCase : Option UInt64 := none) : CompileResult LoweredCallableV1 := do
  if callable.blocks.size == 3 && switchCase.isNone then
    let entry ← match callable.blocks[0]? with | some b => pure b | none => planError "missing switch block 0"
    match entry.terminator with
    | .switch scrutinee cases (some defaultTarget) =>
      let case ← match cases with | #[c] => pure c | _ => planError "Solana switch requires exactly one case"
      unless case.typeId == types.uint64TypeId && case.target.blockId.toNat == 1 &&
          case.target.args.isEmpty && defaultTarget.blockId.toNat == 2 && defaultTarget.args.isEmpty do
        throw <| .planInvariant .solana "unsupported Solana switch case/target shape"
      unless (← findResultTypeV1 callable scrutinee) == types.uint64TypeId do
        throw <| .planInvariant .solana "Solana switch scrutinee must be UInt64"
      let value ← decodeUInt64LiteralV1 case.valueBytes
      let rewrittenEntry := { entry with terminator := .branch scrutinee case.target defaultTarget }
      let rewritten := { callable with blocks := callable.blocks.set! 0 rewrittenEntry }
      return ← lowerCallableV1 owner mode expectsBoolReturn types account rewritten nonterminal (some value)
    | .switch _ _ none => throw <| .planInvariant .solana "Solana switch requires a default target"
    | _ => pure ()
  if callable.blocks.size == 3 || callable.blocks.size == 4 then
    let hasJoin := callable.blocks.size == 4
    unless mode != .initialize && callable.params.isEmpty && callable.entryBlock.toNat == 0 &&
        callable.loopBounds.isEmpty && callable.invariantSteps.isNone do
      throw <| .planInvariant .solana
        "unsupported Solana conditional shape: entry/view must be parameterless and acyclic"
    let entry ← match callable.blocks[0]? with | some b => pure b | none => planError "missing block 0"
    let thenBlock ← match callable.blocks[1]? with | some b => pure b | none => planError "missing block 1"
    let elseBlock ← match callable.blocks[2]? with | some b => pure b | none => planError "missing block 2"
    let joinBlock? := callable.blocks[3]?
    let joinParamOk (b : BlockV1) := match b.params with
      | #[param] => param.valueId.toNat == 0 && param.typeId == types.uint64TypeId
      | _ => false
    let joinShapeOk (b : BlockV1) := b.id.toNat == 3 &&
      (b.params.isEmpty || joinParamOk b)
    unless entry.id.toNat == 0 && thenBlock.id.toNat == 1 && elseBlock.id.toNat == 2 &&
        entry.params.isEmpty && thenBlock.params.isEmpty && elseBlock.params.isEmpty &&
        (!hasJoin || joinBlock?.map joinShapeOk == some true) do
      throw <| .planInvariant .solana
        "unsupported Solana conditional shape: blocks must be parameterless [0,1,2]"
    let (condId, thenTarget, elseTarget) ← match entry.terminator with
      | .branch cond thenTarget elseTarget => pure (cond, thenTarget, elseTarget)
      | _ => throw (.planInvariant .solana
          "unsupported Solana conditional shape: block 0 must terminate in Branch")
    unless thenTarget.blockId.toNat == 1 && elseTarget.blockId.toNat == 2 &&
        thenTarget.args.isEmpty && elseTarget.args.isEmpty do
      throw <| .planInvariant .solana
        "unsupported Solana conditional shape: Branch must target blocks 1/2 with empty args"
    let valueResults (block : BlockV1) := block.instructions.foldl
      (fun n instruction => if instruction.result.isSome then n + 1 else n) 0
    let rebaseId (base : Nat) (id : ValueIdV1) : CompileResult ValueIdV1 :=
      if id.toNat < base then planError
        "unsupported Solana conditional shape: cross-arm value use"
      else pure ⟨id.toNat - base⟩
    let rebaseBlock (base : Nat) (block : BlockV1) (armNonterminal : Bool := false)
        (expectedJumpArgs : Nat := 0) : CompileResult BlockV1 := do
      let mut instructions : Array InstructionV1 := #[]
      let mut next := 0
      for instruction in block.instructions do
        let result ← match instruction.result with
          | none => pure none
          | some result =>
              unless result.valueId.toNat == base + next do
                throw <| .planInvariant .solana
                  "unsupported Solana conditional shape: arm ValueIds are not canonical"
              next := next + 1
              pure (some { result with valueId := ⟨result.valueId.toNat - base⟩ })
        let op ← match instruction.op with
          | .literal typeId bytes => pure (.literal typeId bytes)
          | .stateLoad stateId => pure (.stateLoad stateId)
          | .binary op lhs rhs => pure (.binary op (← rebaseId base lhs) (← rebaseId base rhs))
          | .stateStore stateId value => pure (.stateStore stateId (← rebaseId base value))
          | .assert_ cond errorId args =>
              let mut rebasedArgs := #[]
              for arg in args do rebasedArgs := rebasedArgs.push (← rebaseId base arg)
              pure (.assert_ (← rebaseId base cond) errorId rebasedArgs)
          | _ => throw (.planInvariant .solana
              "unsupported Solana conditional shape: arm instruction is unsupported")
        instructions := instructions.push { instruction with result, op }
      let terminator ← if armNonterminal then
          match block.terminator with
          | .jump target =>
              unless target.blockId.toNat == 3 && target.args.size == expectedJumpArgs do
                throw <| .planInvariant .solana
                  "unsupported Solana join shape: arm jump argument count is invalid"
              pure (.return_ none)
          | _ => throw (.planInvariant .solana "unsupported Solana join shape: arms must not return")
        else match block.terminator with
          | .return_ (some value) => pure (.return_ (some (← rebaseId base value)))
          | _ => throw (.planInvariant .solana
              "unsupported Solana conditional shape: each arm must Return some UInt64")
      pure { block with id := 0, instructions, terminator }
    let isPhiJoin := joinBlock?.map joinParamOk == some true
    let instructionBase := if isPhiJoin then 1 else 0
    let entryCallable := { callable with blocks := #[← rebaseBlock instructionBase
      { entry with terminator := .return_ (some condId) }] }
    let entryLowered ← lowerCallableV1 owner mode switchCase.isNone types account entryCallable
    let entryPrefix := entryLowered.body.pop
    unless entryPrefix.isEmpty do
      throw <| .planInvariant .solana
        "unsupported Solana conditional shape: block 0 may only compute the Branch condition"
    let rawCondition ← match entryLowered.body.back? with
      | some (.returnValue value) => pure value
      | _ => throw (.planInvariant .solana
          "unsupported Solana conditional shape: Branch condition did not lower to Bool")
    let condition := match switchCase with
      | some value => Expr.compare .eq rawCondition (.literal value)
      | none => rawCondition
    let thenBase := instructionBase + valueResults entry
    let elseBase := thenBase + valueResults thenBlock
    if !hasJoin then
      let rebasedThen ← rebaseBlock thenBase thenBlock
      let rebasedElse ← rebaseBlock elseBase elseBlock
      let thenLowered ← lowerCallableV1 owner mode expectsBoolReturn types account { callable with blocks := #[rebasedThen] }
      let elseLowered ← lowerCallableV1 owner mode expectsBoolReturn types account { callable with blocks := #[rebasedElse] }
      return { params := #[], body := entryPrefix.push (.conditional condition thenLowered.body elseLowered.body) }
    let joinBlock ← match joinBlock? with | some b => pure b | none => planError "missing block 3"
    let joinBase := elseBase + valueResults elseBlock
    if joinBlock.params.isEmpty then
      let rebasedThen ← rebaseBlock thenBase thenBlock true
      let rebasedElse ← rebaseBlock elseBase elseBlock true
      let thenLowered ← lowerCallableV1 owner mode expectsBoolReturn types account
        { callable with blocks := #[rebasedThen] } true
      let elseLowered ← lowerCallableV1 owner mode expectsBoolReturn types account
        { callable with blocks := #[rebasedElse] } true
      let rebasedJoin ← rebaseBlock joinBase joinBlock
      let joinLowered ← lowerCallableV1 owner mode expectsBoolReturn types account
        { callable with blocks := #[rebasedJoin] }
      return ({
        params := #[]
        body := entryPrefix.push
          (.conditional condition thenLowered.body elseLowered.body) ++ joinLowered.body
      } : LoweredCallableV1)
    let makeArm (base : Nat) (arm : BlockV1) : CompileResult (Array Statement) := do
      let jumpArg ← match arm.terminator with
        | .jump target =>
            unless target.blockId.toNat == 3 && target.args.size == 1 do
              throw <| .planInvariant .solana "unsupported Solana join shape: arms must Jump(3,[UInt64])"
            pure target.args[0]!
        | _ => throw (.planInvariant .solana "unsupported Solana join shape: arm must jump")
      let armCount := valueResults arm
      unless base <= jumpArg.toNat && jumpArg.toNat < base + armCount do
        throw <| .planInvariant .solana "unsupported Solana join shape: branch-local/cross-arm jump argument"
      let rebasedArm ← rebaseBlock base arm true 1
      let localArg : ValueIdV1 := ⟨jumpArg.toNat - base⟩
      let rewrite (id : ValueIdV1) : CompileResult ValueIdV1 :=
        if id.toNat == 0 then pure localArg
        else if joinBase <= id.toNat then pure ⟨armCount + id.toNat - joinBase⟩
        else planError "unsupported Solana join shape: continuation references cross-arm value"
      let mut instructions := rebasedArm.instructions
      for instruction in joinBlock.instructions do
        let op ← match instruction.op with
          | .literal t bytes => pure (.literal t bytes)
          | .stateLoad s => pure (.stateLoad s)
          | .binary op l r => pure (.binary op (← rewrite l) (← rewrite r))
          | .stateStore s v => pure (.stateStore s (← rewrite v))
          | .assert_ c e args =>
              let mut xs := #[]
              for x in args do xs := xs.push (← rewrite x)
              pure (.assert_ (← rewrite c) e xs)
          | _ => throw (.planInvariant .solana "unsupported Solana join continuation instruction")
        let result := instruction.result.map fun r =>
          { r with valueId := ⟨armCount + r.valueId.toNat - joinBase⟩ }
        instructions := instructions.push { instruction with op, result }
      let returnId ← match joinBlock.terminator with
        | .return_ (some id) => rewrite id
        | _ => throw (.planInvariant .solana "unsupported Solana join shape: continuation must return UInt64")
      let finalBlock : BlockV1 := {
        id := rebasedArm.id
        params := rebasedArm.params
        instructions
        terminator := .return_ (some returnId)
      }
      let lowered ← lowerCallableV1 owner mode expectsBoolReturn types account
        { callable with blocks := #[finalBlock] }
      pure lowered.body
    let thenBody ← makeArm thenBase thenBlock
    let elseBody ← makeArm elseBase elseBlock
    return { params := #[], body := entryPrefix.push (.conditional condition thenBody elseBody) }
  unless callable.entryBlock.toNat == 0 && callable.blocks.size == 1 &&
      callable.loopBounds.isEmpty && callable.invariantSteps.isNone do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: callable must be one acyclic entry block"
  let block ← match callable.blocks[0]? with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: callable entry block is missing")
  unless block.id.toNat == 0 && block.params.isEmpty do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: block parameters are not supported"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .solana
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let (params, initialValues) ← makeParamsV1 owner types.uint64TypeId callable.params
  let paramCount := params.size
  let mut values := initialValues
  let mut segmentStart := values.size
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if typeId == types.uint64TypeId then
          let value ← decodeUInt64LiteralV1 bytes
          values := ← appendResultValueV1 types.uint64TypeId values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := false
          }
        else if types.boolTypeId == some typeId then
          let bit ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal (if bit then 1 else 0)
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := true
          }
        else
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: literal is not UInt64 or Bool"
    | .stateLoad stateId, some result =>
        let field ← findFieldV1 account stateId
        values := ← appendResultValueV1 types.uint64TypeId values result {
          expr := .stateLoad field.accountIndex field.byteOffset
          depth := 1
          expandedNodes := 1
          dependencies := #[]
          isBool := false
        }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueV1 values paramCount segmentStart lhsId
        let rhs ← currentValueV1 values paramCount segmentStart rhsId
        unless !lhs.isBool && !rhs.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: binary operands must be UInt64"
        if op == .add then
          let value ← makeCheckedAddValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .sub then
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else
          match comparisonOpOfV1 op with
          | some cmpOp =>
              let boolTypeId ← match types.boolTypeId with
                | some value => pure value
                | none => throw (.planInvariant .solana
                    "unsupported Solana semantic shape: Bool type is missing for comparison")
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: comparison result must be Bool"
              let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
              values := ← appendResultValueV1 boolTypeId values result value
          | none =>
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: only checked UInt64 add/sub and comparisons are supported"
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable writes state"
        let field ← findFieldV1 account stateId
        let stored ← currentValueV1 values paramCount segmentStart valueId
        unless !stored.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: state store value must be UInt64"
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
        body := body.push (.store {
          accountIndex := field.accountIndex
          byteOffset := field.byteOffset
          value
        })
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: assert requires errorId=none and empty args"
        let cond ← currentValueV1 values paramCount segmentStart condId
        unless cond.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: assert condition must be Bool"
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart condId
        body := body.push (.assert value)
        segmentStart := values.size
    | _, _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: instruction op/result is outside the current UInt64 pilot"
  match mode, block.terminator with
  | .initialize, .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: initializer has unconsumed values"
  | .mutate, .return_ (some valueId)
  | .view, .return_ (some valueId) =>
      let returned ← currentValueV1 values paramCount segmentStart valueId
      unless returned.isBool == expectsBoolReturn do
        throw <| .planInvariant .solana
          (if expectsBoolReturn then
            "unsupported Solana semantic shape: Bool entry/view must return a Bool value"
           else
            "unsupported Solana semantic shape: UInt64 entry/view must not return a Bool value")
      let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
      body := body.push (.returnValue value)
      segmentStart := values.size
  | .initialize, .return_ (some _) =>
      throw <| .planInvariant .solana "initializer cannot return a value"
  | .mutate, .return_ none
  | .view, .return_ none =>
      unless nonterminal && segmentStart == values.size do
        throw <| .planInvariant .solana "unsupported Solana join shape: nonterminal arm has unconsumed values"
  | _, _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: callable terminator is outside the current UInt64 pilot"
  unless segmentStart == values.size do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: callable has unconsumed values"
  if body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def makeInitializerV1
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (callable : CallableV1) : CompileResult Handler := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: initializer result is not Unit"
  let lowered ← lowerCallableV1 "initializer" .initialize false types account callable
  let handler : Handler := {
    name := "initialize"
    discriminator := ""
    params := lowered.params
    mode := .initialize
    resultKind := .u64
    accountAccess := accessFor account .initialize
    body := lowered.body
  }
  pure { handler with discriminator := instructionDiscriminator handler.name handler.params }

private def makeEntryV1
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (callable : CallableV1) : CompileResult Handler := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .solana s!"entry name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .solana s!"entry '{name}' result is not public"
  let resultKind : ResultKind ←
    if callable.result.typeId == types.uint64TypeId then
      pure .u64
    else if types.boolTypeId == some callable.result.typeId then
      pure .bool
    else
      throw <| .planInvariant .solana
        s!"entry '{name}' does not return public UInt64 or Bool"
  let semanticMode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .mutate
    | .view => pure .view
    | _ => throw (.planInvariant .solana
        "unsupported Solana semantic shape: callable is not an entry or view")
  let mode : HandlerMode := match semanticMode with
    | .mutate => .mutate
    | .view => .view
    | .initialize => .initialize
  let expectsBoolReturn := resultKind == .bool
  let lowered ← lowerCallableV1 s!"entry '{name}'" semanticMode expectsBoolReturn
    types account callable
  let handler : Handler := {
    name
    discriminator := ""
    params := lowered.params
    mode
    resultKind
    accountAccess := accessFor account mode
    body := lowered.body
  }
  pure { handler with discriminator := instructionDiscriminator handler.name handler.params }

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
    | .checkedAdd lhs rhs | .checkedSub lhs rhs | .compare _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? account params childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (account : StateAccount) (params : Array Param)
    (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  match planExprNodes? account params maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .solana
        s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

private inductive ExpectedExprKind where
  | uint64 | bool
  deriving BEq

private def exprHasKind? (expected : ExpectedExprKind) (depthLeft : Nat) (expr : Expr) : Bool :=
  if depthLeft == 0 then false else match expr with
  | .literal value => expected == .uint64 || value == 0 || value == 1
  | .param .. | .stateLoad .. => expected == .uint64
  | .checkedAdd lhs rhs | .checkedSub lhs rhs =>
      expected == .uint64 && exprHasKind? .uint64 (depthLeft - 1) lhs &&
        exprHasKind? .uint64 (depthLeft - 1) rhs
  | .compare _ lhs rhs =>
      expected == .bool && exprHasKind? .uint64 (depthLeft - 1) lhs &&
        exprHasKind? .uint64 (depthLeft - 1) rhs

private def addTypedPlanExprNodes (account : StateAccount) (params : Array Param)
    (total : Nat) (expected : ExpectedExprKind) (expr : Expr) : CompileResult Nat := do
  unless exprHasKind? expected maxExprDepth expr do
    throw <| .planInvariant .solana "plan expression has the wrong contextual scalar kind"
  addPlanExprNodes account params total expr

private partial def bodyNodeCount? (depth fuel : Nat) (body : Array Statement) : Option Nat := do
  if depth == 0 || body.size > fuel then none else
  let mut total := body.size
  for statement in body do
    match statement with
    | .conditional _ thenBody elseBody =>
        let left ← bodyNodeCount? (depth - 1) (fuel - total) thenBody
        total := total + left
        let right ← bodyNodeCount? (depth - 1) (fuel - total) elseBody
        total := total + right
    | _ => pure ()
  pure total

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
  let bodyNodes ← match bodyNodeCount? maxExprDepth maxBodyStatements handler.body with
    | some n => pure n
    | none => throw (.planInvariant .solana "handler body exceeds recursive depth/node limits")
  if handler.body.isEmpty || bodyNodes > maxBodyStatements then
    throw <| .planInvariant .solana s!"handler '{handler.name}' has an invalid body size"
  if let some index := handler.body.findIdx? (fun s => match s with | .conditional .. => true | _ => false) then
    unless index == 0 && (handler.body.drop 1).all
        (fun s => match s with | .conditional .. => false | _ => true) do
      throw <| .planInvariant .solana
        "conditional handler body must begin with exactly one conditional statement"
  if handler.body.any (fun statement => match statement with
      | .conditional .. => true
      | _ => false) && !handler.params.isEmpty then
    throw <| .planInvariant .solana
      "conditional handler must be parameterless"
  let mut total := baseNodes
  let mut returned := false
  let returnKind := match handler.resultKind with
    | .u64 => ExpectedExprKind.uint64
    | .bool => ExpectedExprKind.bool
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
        total ← addTypedPlanExprNodes account handler.params total .uint64 store.value
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .solana "initializer cannot return a value"
        total ← addTypedPlanExprNodes account handler.params total returnKind value
        returned := true
    | .assert condition =>
        total ← addTypedPlanExprNodes account handler.params total .bool condition
    | .conditional condition thenBody elseBody =>
        if isInitializer || thenBody.isEmpty || elseBody.isEmpty then
          throw <| .planInvariant .solana "conditional is invalid in this handler"
        total ← addTypedPlanExprNodes account handler.params total .bool condition
        let armsReturn := thenBody.any (fun s => match s with | .returnValue .. => true | _ => false)
        unless armsReturn == elseBody.any (fun s => match s with | .returnValue .. => true | _ => false) do
          throw <| .planInvariant .solana "conditional arms disagree on terminality"
        for arm in #[thenBody, elseBody] do
          let mut armReturned := false
          for armStatement in arm do
            if armReturned then
              throw <| .planInvariant .solana "conditional arm has a statement after return"
            match armStatement with
            | .store store =>
                if handler.mode == .view then
                  throw <| .planInvariant .solana s!"view handler '{handler.name}' writes state"
                unless account.fields.any (fun field => field.accountIndex == store.accountIndex &&
                    field.byteOffset == store.byteOffset) do
                  throw <| .planInvariant .solana "conditional arm stores to an unknown field"
                total ← addTypedPlanExprNodes account handler.params total .uint64 store.value
            | .assert value =>
                total ← addTypedPlanExprNodes account handler.params total .bool value
            | .returnValue value =>
                total ← addTypedPlanExprNodes account handler.params total returnKind value
                armReturned := true
            | .conditional .. =>
                throw <| .planInvariant .solana "nested conditional is not supported"
          unless armReturned || !armsReturn do
            throw <| .planInvariant .solana "conditional arm does not return UInt64"
        returned := armsReturn
  if isInitializer then
    if returned then
      throw <| .planInvariant .solana "initializer cannot return a value"
  else unless returned do
    throw <| .planInvariant .solana s!"handler '{handler.name}' does not return a value"
  return total

/-- Validate the public target-owned Plan before typed IR lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.instructionDiscriminatorDomain == discriminatorDomain &&
      plan.instructionDiscriminatorBytes == discriminatorBytes &&
      plan.stateLayoutDomain == layoutDomain &&
      plan.arithmeticOverflowError == arithmeticOverflowError &&
      plan.assertionFailedError == assertionFailedError do
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
  let initializerNodes ← match bodyNodeCount? maxExprDepth maxPlanNodes plan.initializer.body with
    | some n => pure n | none => throw (.planInvariant .solana "initializer body exceeds recursive limits")
  let mut statementCount := initializerNodes
  for handler in plan.entries do
    let nodes ← match bodyNodeCount? maxExprDepth (maxPlanNodes - statementCount) handler.body with
      | some n => pure n | none => throw (.planInvariant .solana "entry body exceeds recursive limits")
    statementCount := statementCount + nodes
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

/-- Solana-private retained SemanticProgramV1 data → target-owned Plan pilot. -/
private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.events.isEmpty || !source.errors.isEmpty ||
      !source.invariants.isEmpty then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: constants/events/errors/invariants are outside the current UInt64 pilot"
  if source.callables.size > maxEntries + 1 then
    throw <| .planInvariant .solana s!"callable count exceeds Solana profile limit {maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .solana
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateSolanaTypeClosureV1 source.types
  let stateAccount ← makeStateAccountV1 types.uint64TypeId source.logicalState
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let mut initializer : Option Handler := none
  let mut entries : Array Handler := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .solana "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types stateAccount callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .solana s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types stateAccount callable)
    | .pureFn | .invariant =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: pure functions/invariants are outside the current UInt64 pilot"
  let resolvedInitializer ← match initializer with
    | some value => pure value
    | none => throw <| .planInvariant .solana "state-account programs require an initializer"
  let plan : Plan := {
    codegenProfile := descriptor.codegenProfile.toString
    instructionDiscriminatorDomain := discriminatorDomain
    instructionDiscriminatorBytes := discriminatorBytes
    stateLayoutDomain := layoutDomain
    arithmeticOverflowError
    assertionFailedError
    programName
    stateAccount
    initializer := resolvedInitializer
    entries
  }
  validatePlan plan
  pure plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Solana received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Capability-gated public plan entry. Plan semantics consume retained V1 only. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

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
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr overflowError next lhs
      let rhs := lowerExpr overflowError lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr overflowError next lhs
      let rhs := lowerExpr overflowError lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
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

private partial def lowerStatements (plan : Plan) (resultKind : ResultKind) (next : Nat)
    (statements : Array Statement) : Array Operation × Nat := Id.run do
  let mut operations := #[]
  let mut next := next
  for statement in statements do
    match statement with
    | .store store =>
        let value := lowerExpr plan.arithmeticOverflowError next store.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState store.accountIndex store.byteOffset value.value)
        next := value.next
    | .returnValue value =>
        let value := lowerExpr plan.arithmeticOverflowError next value
        operations := operations ++ value.operations
        let returnOp : Operation := match resultKind with
          | .u64 => .setReturnData value.value
          | .bool => .setReturnDataBool value.value
        operations := operations.push returnOp
        next := value.next
    | .assert condition =>
        let value := lowerExpr plan.arithmeticOverflowError next condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value plan.assertionFailedError)
        next := value.next
    | .conditional condition thenBody elseBody =>
        let value := lowerExpr plan.arithmeticOverflowError next condition
        let thenResult := lowerStatements plan resultKind value.next thenBody
        let elseResult := lowerStatements plan resultKind value.next elseBody
        operations := operations ++ value.operations
        operations := operations.push (.conditional value.value thenResult.1 elseResult.1)
        next := max thenResult.2 elseResult.2
  return (operations, next)

private def lowerHandler (plan : Plan) (handler : Handler) : HandlerIR := Id.run do
  let account := plan.stateAccount
  let mut operations : Array Operation :=
    if handler.mode == .initialize then
      account.fields.map fun field => .zeroState field.accountIndex field.byteOffset
    else
      #[]
  let lowered := lowerStatements plan handler.resultKind 0 handler.body
  operations := operations ++ lowered.1
  if handler.mode == .initialize then
    operations := operations.push <|
      .setHeader account.index account.headerOffset account.initializedMarker
  return {
    name := handler.name
    discriminator := handler.discriminator
    params := handler.params
    mode := handler.mode
    resultKind := handler.resultKind
    accountAccess := handler.accountAccess
    checks := checksFor plan.instructionDiscriminatorBytes account handler
    operations
  }

private def tempDestination? : Operation → Option Nat
  | .literal destination .. | .loadParam destination .. |
      .loadState destination .. | .checkedAdd destination .. |
      .checkedSub destination .. | .compare destination .. => some destination
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
    resultKind := handler.resultKind
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
  for operationIndex in [:handler.operations.size] do
    let operation := handler.operations[operationIndex]!
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
    | .checkedSub _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-sub operands/error are invalid"
    | .compare _ lhs rhs _op =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR compare operands are invalid"
    | .assert condition errorCode =>
        unless condition < next && errorCode == plan.assertionFailedError do
          throw <| .planInvariant .solana "typed Solana IR assert condition/error is invalid"
    | .conditional condition thenOps elseOps =>
        let terminalKind : Operation → Option ResultKind
          | .setReturnData _ => some .u64
          | .setReturnDataBool _ => some .bool
          | _ => none
        let thenKind := thenOps.back?.bind terminalKind
        let elseKind := elseOps.back?.bind terminalKind
        let thenReturns := thenKind.isSome
        let elseReturns := elseKind.isSome
        let hasContinuation := operationIndex + 1 < handler.operations.size
        unless condition < next && !thenOps.isEmpty && !elseOps.isEmpty &&
            thenReturns == elseReturns && (thenReturns || hasContinuation) &&
            (!thenReturns || (thenKind == some handler.resultKind && elseKind == some handler.resultKind)) do
          throw <| .planInvariant .solana "typed Solana IR conditional is invalid"
        -- Exclusive arms reuse the same static temporary range; continuation
        -- destinations begin after the larger selected-arm range.
        let armStart := next
        let mut thenNext := armStart
        for armOperation in thenOps do
          if let some destination := tempDestination? armOperation then
            unless destination == thenNext do
              throw <| .planInvariant .solana
                "typed Solana IR conditional temporary numbering is not canonical"
            thenNext := thenNext + 1
        let mut elseNext := armStart
        for armOperation in elseOps do
          if let some destination := tempDestination? armOperation then
            unless destination == elseNext do
              throw <| .planInvariant .solana
                "typed Solana IR conditional temporary numbering is not canonical"
            elseNext := elseNext + 1
        next := max thenNext elseNext
        returned := thenReturns
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
        unless handler.mode != .initialize && handler.resultKind == .u64 && value < next do
          throw <| .planInvariant .solana "typed Solana IR UInt64 return value is invalid"
        returned := true
    | .setReturnDataBool value =>
        unless handler.mode != .initialize && handler.resultKind == .bool && value < next do
          throw <| .planInvariant .solana "typed Solana IR Bool return value is invalid"
        returned := true
  if handler.mode == .initialize then
    unless initialized do
      throw <| .planInvariant .solana "initializer IR does not set the initialized marker"
  else unless returned do
    throw <| .planInvariant .solana "entry IR does not set return data"

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
  let rec operationNodes : Nat → Nat → Array Operation → Option Nat
    | 0, _, _ => none
    | _, 0, _ => none
    | depth + 1, fuel, operations =>
        if operations.size > fuel then none
        else operations.foldl (fun total operation => total.bind fun nodes =>
          if nodes >= fuel then none
          else match operation with
            | .conditional _ thenOps elseOps => do
                let left ← operationNodes depth (fuel - nodes - 1) thenOps
                let used := nodes + 1 + left
                if used >= fuel then none
                else
                  let right ← operationNodes depth (fuel - used) elseOps
                  some (used + right)
            | _ => some (nodes + 1)) (some 0)
  let mut operationCount := 0
  for handler in ir.handlers do
    let shallow := handler.checks.size + handler.params.size
    if shallow > maxPlanNodes - operationCount then
      throw <| .planInvariant .solana "typed Solana IR exceeds the aggregate node limit"
    operationCount := operationCount + shallow
    let nodes ← match operationNodes maxExprDepth (maxPlanNodes - operationCount + 1)
        handler.operations with
      | some value => pure value
      | none => throw (.planInvariant .solana
          "typed Solana IR conditional nesting or aggregate node count exceeds its limit")
    if nodes > maxPlanNodes - operationCount then
      throw <| .planInvariant .solana "typed Solana IR exceeds the aggregate node limit"
    operationCount := operationCount + nodes
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

private def renderComparisonOp : ComparisonOp → String
  | .eq => "eq"
  | .ne => "ne"
  | .lt => "lt"
  | .le => "le"
  | .gt => "gt"
  | .ge => "ge"

private partial def renderOperation (indent : String) : Operation → String
  | .literal destination value => s!"{indent}%{destination} = const_u64 {value}\n"
  | .loadParam destination dataOffset =>
      s!"{indent}%{destination} = load_u64_le(instruction_data + {dataOffset})\n"
  | .loadState destination accountIndex byteOffset =>
      s!"{indent}%{destination} = load_u64_le(account[{accountIndex}].data + {byteOffset})\n"
  | .checkedAdd destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_add_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedSub destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_sub_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .zeroState accountIndex byteOffset =>
      s!"{indent}zero_u64_le account[{accountIndex}].data + {byteOffset}\n"
  | .storeState accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, %{value}\n"
  | .setHeader accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, 0x{uint64Hex value}\n"
  | .setReturnData value => s!"{indent}set_return_data_u64_le %{value}\n"
  | .setReturnDataBool value => s!"{indent}set_return_data_bool %{value}\n"
  | .compare destination lhs rhs op =>
      s!"{indent}%{destination} = cmp_{renderComparisonOp op}_u64 %{lhs}, %{rhs}\n"
  | .assert condition errorCode =>
      s!"{indent}assert %{condition} else program_error 0x{natHex errorCode}\n"
  | .conditional condition thenOps elseOps =>
      let renderArm (ops : Array Operation) := ops.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") operation) ""
      s!"{indent}if %{condition} then\n" ++ renderArm thenOps ++
      s!"{indent}else\n" ++ renderArm elseOps ++
      s!"{indent}end-if\n"

private def renderHandlerPlan (handler : HandlerIR) : String :=
  let checks := handler.checks.foldl (fun output check => output ++ renderCheck check) ""
  let operations := handler.operations.foldl (fun output operation =>
    output ++ renderOperation "  " operation) ""
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
  let returns :=
    if handler.mode == .initialize then "null"
    else match handler.resultKind with
      | .u64 => "\"u64-le\""
      | .bool => "\"bool\""
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
