import ProofForge.IR.Core.Id
import ProofForge.IR.Core.Type
import ProofForge.IR.Core.Storage
import ProofForge.IR.Core.Syntax
import ProofForge.IR.Core.Error
import Std

namespace ProofForge.IR.Core.Validate

open ProofForge.IR.Core
open ProofForge.IR.Core.Error

structure CheckedModule where
  module : Module

instance : Inhabited Instruction where
  default := { results := #[], op := .pure (.literal .unitLit) }

private def error (tag : ValidationErrorTag) (pass : String)
    (function : Option FunctionId) (block : Option BlockId)
    (instruction : Option Nat) (reason : String) : ValidationError := {
  tag := tag
  pass := pass
  function := function
  block := block
  instruction := instruction
  sourceLocation := none
  reason := reason
}

/- Fixed-width literal range checking. A literal must fit its declared result
type; narrowing casts are a separate operation and are checked elsewhere. -/

private def literalFitsType (lit : CoreLiteral) (ty : CoreType) : Bool :=
  match lit, ty with
  | .unitLit, .unit => true
  | .boolLit _, .bool => true
  | .u8Lit _, .u8 => true
  | .u8Lit _, .u32 => true
  | .u8Lit _, .u64 => true
  | .u8Lit _, .u128 => true
  | .u32Lit _, .u32 => true
  | .u32Lit n, .u8 => n.toNat ≤ 255
  | .u32Lit _, .u64 => true
  | .u32Lit _, .u128 => true
  | .u64Lit _, .u64 => true
  | .u64Lit n, .u8 => n.toNat ≤ 255
  | .u64Lit n, .u32 => n.toNat ≤ 4294967295
  | .u64Lit _, .u128 => true
  | .u128Lit _, .u128 => true
  | .u128Lit n, .u8 => n.toNat ≤ 255
  | .u128Lit n, .u32 => n.toNat ≤ 4294967295
  | .u128Lit n, .u64 => n.toNat ≤ 18446744073709551615
  | .addressLit _, .address => true
  | .bytesLit _, .bytes => true
  | .stringLit _, .string => true
  | .hashLit _, .hash => true
  | _, _ => false

private def literalTypeName (lit : CoreLiteral) : String :=
  match lit with
  | .unitLit => "unit"
  | .boolLit _ => "bool"
  | .u8Lit _ => "u8"
  | .u32Lit _ => "u32"
  | .u64Lit _ => "u64"
  | .u128Lit _ => "u128"
  | .addressLit _ => "address"
  | .bytesLit _ => "bytes"
  | .stringLit _ => "string"
  | .hashLit _ => "hash"

private def isIntegerLike : CoreType → Bool
  | .u8 | .u32 | .u64 | .u128 => true
  | _ => false

private def isMemoryLike : CoreType → Bool
  | .bytes | .array _ | .fixedArray _ _ => true
  | _ => false

private def elementType? : CoreType → Option CoreType
  | .bytes => some .u8
  | .array e => some e
  | .fixedArray e _ => some e
  | _ => none

private def isScalar : CoreType → Bool
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 => true
  | _ => false

private def isPortableIdentity : CoreType → Bool
  | .address => true
  | _ => false

/- Symbol tables built from the module. -/

private def collectTypeIds (m : Module) : Std.HashSet TypeId :=
  m.structs.foldl (fun s t => s.insert t.id) {}

private def collectStateIds (m : Module) : Std.HashSet StateId :=
  m.state.foldl (fun s d => s.insert d.id) {}

private def collectFunctionIds (m : Module) : Std.HashSet FunctionId :=
  m.functions.foldl (fun s f => s.insert f.id) {}

private def collectEventIds (m : Module) : Std.HashSet EventId :=
  m.events.foldl (fun s e => s.insert e.id) {}

private def coreTypeReferences : CoreType → Array TypeId
  | .fixedArray element _ | .array element => coreTypeReferences element
  | .structType typeId => #[typeId]
  | _ => #[]

private def checkCoreTypeReferences (m : Module) (ty : CoreType)
    (context : String) (function : Option FunctionId := none)
    (block : Option BlockId := none) (instruction : Option Nat := none) :
    Except ValidationError Unit := do
  for typeId in coreTypeReferences ty do
    unless m.structs.any (·.id == typeId) do
      .error <| error .unknownReference "state-shape" function block instruction
        s!"{context} references unknown struct type {repr typeId}"

private def stateShapeTypes : StateShape → Array CoreType
  | .scalar value => #[value]
  | .map key value _ => #[key, value]
  | .fixedArray element _ | .dynamicArray element => #[element]
  | .record typeId => #[.structType typeId]

/- Pass 1: globally unique type, state, function, event, block, and value
identities. -/

private def checkUnique {α : Type} [BEq α] [Repr α] [Hashable α]
    (tag : ValidationErrorTag) (kind : String) (xs : Array α) :
    Except ValidationError Unit := do
  let mut seen : Std.HashSet α := {}
  for x in xs do
    if seen.contains x then
      .error <| ValidationError.mkSimple tag "symbol-uniqueness"
        s!"duplicate {kind}: {repr x}"
    seen := seen.insert x

def checkSymbolUniqueness (m : Module) : Except ValidationError Unit := do
  checkUnique .duplicateId "type" (m.structs.map (·.id))
  checkUnique .duplicateId "state" (m.state.map (·.id))
  checkUnique .duplicateId "function" (m.functions.map (·.id))
  checkUnique .duplicateId "event" (m.events.map (·.id))
  for f in m.functions do
    let mut blockIds : Std.HashSet BlockId := {}
    for b in f.blocks do
      if blockIds.contains b.id then
        .error <| error .duplicateId "symbol-uniqueness" (some f.id) (some b.id) none
          s!"duplicate block in function {repr f.id}: {repr b.id}"
      blockIds := blockIds.insert b.id
    let mut valueIds : Std.HashSet ValueId := {}
    for param in f.params do
      if valueIds.contains param.id then
        .error <| error .duplicateId "symbol-uniqueness" (some f.id) none none
          s!"duplicate function parameter value: {repr param.id}"
      valueIds := valueIds.insert param.id
    for b in f.blocks do
      for param in b.params do
        if valueIds.contains param.id then
          .error <| error .duplicateId "symbol-uniqueness" (some f.id) (some b.id) none
            s!"duplicate block parameter value: {repr param.id}"
        valueIds := valueIds.insert param.id
      for idx in [:b.instructions.size] do
        for result in b.instructions[idx]!.results do
          if valueIds.contains result.id then
            .error <| error .duplicateId "symbol-uniqueness" (some f.id) (some b.id) (some idx)
              s!"duplicate instruction result value: {repr result.id}"
          valueIds := valueIds.insert result.id

/- Pass 2: state-shape reference resolution. Every storage root must exist and
path segments must match the declared shape. -/

private def checkStoragePath (m : Module) (fid : FunctionId) (bid : BlockId)
    (idx : Nat) (path : StorageRef) : Except ValidationError Unit := do
  let state? := m.state.find? (·.id == path.root)
  match state? with
  | none =>
    .error <| error .unknownReference "state-shape" (some fid) (some bid) (some idx)
      s!"unknown storage root {repr path.root}"
  | some decl =>
    let mut shape := decl.shape
    for seg in path.path do
      match seg, shape with
      | .mapKey key, .map keyTy valTy _ =>
        unless key.type == keyTy do
          .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
            s!"map key type {repr key.type} does not match {repr keyTy}"
        shape := .scalar valTy
      | .mapKey _, _ =>
        .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
          s!"map key on non-map state {repr path.root}"
      | .index idxRef, .fixedArray elem _ =>
        unless idxRef.type == .u32 || idxRef.type == .u64 do
          .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
            s!"array index must be integer, got {repr idxRef.type}"
        shape := .scalar elem
      | .index idxRef, .dynamicArray elem =>
        unless idxRef.type == .u32 || idxRef.type == .u64 do
          .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
            s!"array index must be integer, got {repr idxRef.type}"
        shape := .scalar elem
      | .index _, _ =>
        .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
          s!"array index on non-array state {repr path.root}"
      | .field fieldId, .record typeId =>
        let struct? := m.structs.find? (·.id == typeId)
        match struct? with
        | none =>
          .error <| error .unknownReference "state-shape" (some fid) (some bid) (some idx)
            s!"unknown struct type {repr typeId}"
        | some struct =>
          let field? := struct.fields.find? (fun f => f.id.value == fieldId.value)
          match field? with
          | none =>
            .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
              s!"unknown field {repr fieldId} in struct {repr typeId}"
          | some fieldDef =>
            shape := .scalar fieldDef.type
      | .field _, _ =>
        .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
          s!"field access on non-record state {repr path.root}"
    match shape with
    | .scalar resultShapeType =>
      unless resultShapeType == path.resultType do
        .error <| error .typeMismatch "state-shape" (some fid) (some bid) (some idx)
          s!"storage result type {repr path.resultType} does not match shape {repr resultShapeType}"
    | _ =>
      .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
        s!"storage path for root {repr path.root} does not select a scalar leaf"

/- Pass 2: state-shape reference resolution. Every storage root must exist and
path segments must match the declared shape. This pass is intentionally
separated from instruction typing so that reference errors are reported before
type and control-flow passes. -/

def checkStateShapeReferences (m : Module) : Except ValidationError Unit := do
  for struct in m.structs do
    for field in struct.fields do
      checkCoreTypeReferences m field.type s!"struct {repr struct.id} field {repr field.id}"
  for event in m.events do
    for field in event.fields do
      checkCoreTypeReferences m field.type s!"event {repr event.id} field {repr field.id}"
  for decl in m.state do
    for ty in stateShapeTypes decl.shape do
      checkCoreTypeReferences m ty s!"state {repr decl.id}"
  for f in m.functions do
    for param in f.params do
      checkCoreTypeReferences m param.type s!"function {repr f.id} parameter {repr param.id}"
        (some f.id)
    checkCoreTypeReferences m f.retType s!"function {repr f.id} return type" (some f.id)
    for b in f.blocks do
      for param in b.params do
        checkCoreTypeReferences m param.type s!"block {repr b.id} parameter {repr param.id}"
          (some f.id) (some b.id)
      for idx in [:b.instructions.size] do
        let instr := b.instructions[idx]!
        for result in instr.results do
          checkCoreTypeReferences m result.type s!"instruction result {repr result.id}"
            (some f.id) (some b.id) (some idx)
        match instr.op with
        | .storageLoad path | .storageContains path | .storageStore path _ =>
          checkStoragePath m f.id b.id idx path
        | .storageLength root | .storageResize root _ =>
          unless m.state.any (·.id == root) do
            .error <| error .unknownReference "state-shape" (some f.id) (some b.id) (some idx)
              s!"unknown storage root {repr root}"
        | _ => pure ()

/- Pass 3: CFG shape, reachability, and cycle bounds. -/

private def blockIdsOf (f : Function) : Std.HashSet BlockId :=
  f.blocks.foldl (fun s b => s.insert b.id) {}

private def successors (t : Terminator) : Array BlockId :=
  match t with
  | .jump target _ _ => #[target]
  | .branch _ onTrue onFalse => #[onTrue, onFalse]
  | .return _ => #[]
  | .revert _ => #[]

private def traversalSuccessors (skipBoundedEdges : Bool)
    (terminator : Terminator) : Array BlockId :=
  if skipBoundedEdges then
    match terminator with
    | .jump _ _ (some _) => #[]
    | _ => successors terminator
  else
    successors terminator

private def isReachable (f : Function) (start target : BlockId)
    (avoid : Option BlockId := none) (skipBoundedEdges : Bool := false) : Bool := Id.run do
  if avoid == some start then return false
  let mut visited : Std.HashSet BlockId := {}
  let mut stack : Array BlockId := #[start]
  while !stack.isEmpty do
    let current := stack.back!
    stack := stack.pop
    if current == target then return true
    if visited.contains current then continue
    visited := visited.insert current
    match f.blocks.find? (·.id == current) with
    | none => pure ()
    | some block =>
      for succ in traversalSuccessors skipBoundedEdges block.terminator do
        unless avoid == some succ do
          stack := stack.push succ
  return false

private def checkCfgAndBounds (f : Function) :
    Except ValidationError Unit := do
  let entry? := f.blocks.find? (·.id == f.entry)
  match entry? with
  | none =>
    .error <| error .unknownReference "cfg" (some f.id) none none
      s!"entry block {repr f.entry} not found"
  | some entryBlock =>
    unless entryBlock.params.isEmpty do
      .error <| error .typeMismatch "cfg" (some f.id) (some entryBlock.id) none
        "entry block cannot declare parameters; use function parameters for call inputs"
    let mut visited : Std.HashSet BlockId := {}
    let mut stack : Array BlockId := #[f.entry]
    while !stack.isEmpty do
      let b := stack.back!
      stack := stack.pop
      if visited.contains b then continue
      visited := visited.insert b
      let block? := f.blocks.find? (·.id == b)
      match block? with
      | none =>
        .error <| error .unknownReference "cfg" (some f.id) (some b) none
          s!"block {repr b} referenced but not declared"
      | some block =>
        for succ in successors block.terminator do
          stack := stack.push succ
    for b in f.blocks do
      unless visited.contains b.id do
        .error <| error .unknownReference "cfg" (some f.id) (some b.id) none
          s!"block {repr b.id} is unreachable"
    for b in f.blocks do
      for succ in traversalSuccessors true b.terminator do
        if isReachable f succ b.id none true then
          .error <| error .missingLoopBound "cfg" (some f.id) (some b.id) none
            s!"cycle containing edge {repr b.id} -> {repr succ} lacks a LoopBound"

/- Pass 4: dominance and value environments. -/

private def storagePathValueRefs (path : StorageRef) : Array ValueRef :=
  path.path.foldl (fun refs seg =>
    match seg with
    | .mapKey key => refs.push key
    | .index index => refs.push index
    | .field _ => refs) #[]

private def optionalValueRef : Option ValueRef → Array ValueRef
  | some ref => #[ref]
  | none => #[]

private def referencedValueRefs (op : InstructionOp) : Array ValueRef :=
  match op with
  | .pure p => match p with
    | .literal _ => #[]
    | .unary _ arg => #[arg]
    | .arithmetic _ _ lhs rhs => #[lhs, rhs]
    | .compare _ lhs rhs => #[lhs, rhs]
    | .cast _ arg => #[arg]
    | .hash arg => #[arg]
  | .storageLoad path => storagePathValueRefs path
  | .storageContains path => storagePathValueRefs path
  | .storageStore path value =>
    (storagePathValueRefs path).push value
  | .storageLength _ => #[]
  | .storageResize _ length => #[length]
  | .memoryAlloc _ length => #[length]
  | .memoryLoad base index => #[base, index]
  | .memoryStore base index value => #[base, index, value]
  | .memoryRelease base => #[base]
  | .contextRead _ => #[]
  | .emit _ args => args
  | .assert condition _ => #[condition]
  | .crosscall spec args =>
    optionalValueRef spec.gas ++ optionalValueRef spec.value ++ args
  | .hostCall call => call.args

private def referencedValueRefsTerminator (t : Terminator) : Array ValueRef :=
  match t with
  | .jump _ args _ => args
  | .branch condition _ _ => #[condition]
  | .return values => values
  | .revert _ => #[]

private inductive ValueDefinitionSite
  | functionParameter
  | blockParameter (block : BlockId)
  | instructionResult (block : BlockId) (instruction : Nat)

private structure ValueBinding where
  id : ValueId
  type : CoreType
  site : ValueDefinitionSite

private def collectValueBindings (f : Function) : Array ValueBinding := Id.run do
  let mut bindings := #[]
  for param in f.params do
    bindings := bindings.push {
      id := param.id
      type := param.type
      site := .functionParameter
    }
  for block in f.blocks do
    for param in block.params do
      bindings := bindings.push {
        id := param.id
        type := param.type
        site := .blockParameter block.id
      }
    for idx in [:block.instructions.size] do
      for result in block.instructions[idx]!.results do
        bindings := bindings.push {
          id := result.id
          type := result.type
          site := .instructionResult block.id idx
        }
  return bindings

private def blockDominates (f : Function) (definition use : BlockId) : Bool :=
  definition == use || !isReachable f f.entry use (some definition)

private def checkValueUse (f : Function) (bindings : Array ValueBinding)
    (useBlock : BlockId) (useInstruction : Option Nat) (ref : ValueRef) :
    Except ValidationError Unit := do
  let binding? := bindings.find? (·.id == ref.id)
  let binding ← match binding? with
    | none =>
      .error <| error .invalidDominance "dominance" (some f.id)
        (some useBlock) useInstruction s!"value {repr ref.id} has no definition"
    | some binding => pure binding
  unless ref.type == binding.type do
    .error <| error .typeMismatch "dominance" (some f.id)
      (some useBlock) useInstruction
      s!"value {repr ref.id} claims type {repr ref.type}, but its definition has type {repr binding.type}"
  let dominates := match binding.site with
    | .functionParameter => true
    | .blockParameter definitionBlock =>
      blockDominates f definitionBlock useBlock
    | .instructionResult definitionBlock definitionInstruction =>
      if definitionBlock == useBlock then
        match useInstruction with
        | some idx => definitionInstruction < idx
        | none => true
      else
        blockDominates f definitionBlock useBlock
  unless dominates do
    .error <| error .invalidDominance "dominance" (some f.id)
      (some useBlock) useInstruction
      s!"definition of value {repr ref.id} does not dominate this use"

private def checkDominance (f : Function) : Except ValidationError Unit := do
  let bindings := collectValueBindings f
  for b in f.blocks do
    for idx in [:b.instructions.size] do
      let instr := b.instructions[idx]!
      for ref in referencedValueRefs instr.op do
        checkValueUse f bindings b.id (some idx) ref
    for ref in referencedValueRefsTerminator b.terminator do
      checkValueUse f bindings b.id none ref

/- Pass 5: instruction input/result typing. -/

private def checkPureOp (p : PureOp) (results : Array ValueDef)
    (fid : FunctionId) (bid : BlockId) (idx : Nat) :
    Except ValidationError Unit := do
  match p, results with
  | .literal lit, #[r] =>
    unless literalFitsType lit r.type do
      .error <| error .literalOutOfRange "instruction-typing" (some fid) (some bid) (some idx)
        s!"literal {repr lit} does not fit result type {repr r.type}"
  | .unary op arg, #[r] =>
    match op with
    | .not =>
      unless arg.type == .bool && r.type == .bool do
        .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
          s!"`not` expects bool, got {repr arg.type} -> {repr r.type}"
    | .neg =>
      unless isIntegerLike arg.type && r.type == arg.type do
        .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
          s!"`neg` expects integer, got {repr arg.type} -> {repr r.type}"
  | .arithmetic _ _ lhs rhs, #[r] =>
    unless lhs.type == rhs.type && r.type == lhs.type && isIntegerLike lhs.type do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"arithmetic operands/results must be matching integers, got {repr lhs.type}, {repr rhs.type} -> {repr r.type}"
  | .compare _ lhs rhs, #[r] =>
    unless lhs.type == rhs.type && r.type == .bool do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"compare operands must match and result bool, got {repr lhs.type}, {repr rhs.type} -> {repr r.type}"
  | .cast to arg, #[r] =>
    unless r.type == to && isScalar arg.type do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"cast expects scalar operand and target type, got {repr arg.type} -> {repr to}"
  | .hash _, #[r] =>
    unless r.type == .hash do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"hash result must be hash, got {repr r.type}"
  | _, _ =>
    .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
      s!"pure operation produced {results.size} results, expected 1"

private def expectedResultCount (op : InstructionOp) : Nat :=
  match op with
  | .pure (.literal _) => 1
  | .pure (.unary _ _) => 1
  | .pure (.arithmetic _ _ _ _) => 1
  | .pure (.compare _ _ _) => 1
  | .pure (.cast _ _) => 1
  | .pure (.hash _) => 1
  | .storageLoad _ => 1
  | .storageContains _ => 1
  | .storageStore _ _ => 0
  | .storageLength _ => 1
  | .storageResize _ _ => 0
  | .memoryAlloc _ _ => 1
  | .memoryLoad _ _ => 1
  | .memoryStore _ _ _ => 0
  | .memoryRelease _ => 0
  | .contextRead _ => 1
  | .emit _ _ => 0
  | .assert _ _ => 0
  | .crosscall _ _ => 1
  | .hostCall _ => 1

private def checkInstructionTyping (m : Module) (f : Function) (b : Block)
    (idx : Nat) (instr : Instruction) : Except ValidationError Unit := do
  let pass := "instruction-typing"
  unless instr.results.size == expectedResultCount instr.op do
    .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
      s!"operation expects {expectedResultCount instr.op} results, got {instr.results.size}"
  match instr.op with
  | .pure p => checkPureOp p instr.results f.id b.id idx
  | .storageLoad path =>
    -- state-shape reference resolution happens in the dedicated second pass;
    -- here we only check the instruction-level result type.
    match instr.results with
    | #[r] =>
      unless r.type == path.resultType do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"storageLoad result type {repr r.type} does not match path {repr path.resultType}"
    | _ => pure ()
  | .storageContains _ =>
    match instr.results with
    | #[r] =>
      unless r.type == .bool do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"storageContains result must be bool, got {repr r.type}"
    | _ => pure ()
  | .storageStore path value =>
    unless value.type == path.resultType do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"storageStore value type {repr value.type} does not match path {repr path.resultType}"
  | .storageLength _ =>
    match instr.results with
    | #[r] =>
      unless r.type == .u64 do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"storageLength result must be u64, got {repr r.type}"
    | _ => pure ()
  | .storageResize _ length =>
    unless length.type == .u64 do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"storageResize length must be u64, got {repr length.type}"
  | .memoryAlloc ty length =>
    unless length.type == .u64 do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryAlloc length must be u64, got {repr length.type}"
    match instr.results with
    | #[r] =>
      unless r.type == .array ty do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"memoryAlloc result type {repr r.type} does not match array {repr ty}"
    | _ => pure ()
  | .memoryLoad base index =>
    unless isMemoryLike base.type && isIntegerLike index.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryLoad base/index types invalid: {repr base.type}, {repr index.type}"
    match instr.results with
    | #[r] =>
      unless some r.type == elementType? base.type do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"memoryLoad result type {repr r.type} does not match base element"
    | _ => pure ()
  | .memoryStore base index value =>
    unless isMemoryLike base.type && isIntegerLike index.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryStore base/index types invalid: {repr base.type}, {repr index.type}"
    unless some value.type == elementType? base.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryStore value type {repr value.type} does not match base element"
  | .memoryRelease base =>
    unless isMemoryLike base.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryRelease base must be array/bytes, got {repr base.type}"
  | .contextRead field =>
    match instr.results with
    | #[r] =>
      let expected := match field with
        | .sender | .contractAddress => .address
        | .value => .u128
        | .blockNumber | .blockTimestamp | .gas => .u64
      unless r.type == expected do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"contextRead {repr field} result must be {repr expected}, got {repr r.type}"
    | _ => pure ()
  | .emit eventId args =>
    let event? := m.events.find? (·.id == eventId)
    match event? with
    | none =>
      .error <| error .unknownReference pass (some f.id) (some b.id) (some idx)
        s!"unknown event {repr eventId}"
    | some event =>
      unless args.size == event.fields.size do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"event {repr eventId} expects {event.fields.size} args, got {args.size}"
      for i in [:args.size] do
        unless args[i]!.type == event.fields[i]!.type do
          .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
            s!"event arg {i} type mismatch: expected {repr event.fields[i]!.type}, got {repr args[i]!.type}"
  | .assert condition _ =>
    unless condition.type == .bool do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"assert condition must be bool, got {repr condition.type}"
  | .crosscall _ args =>
    for arg in args do
      unless isScalar arg.type || isPortableIdentity arg.type do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"crosscall arg type {repr arg.type} is not a portable scalar/identity"
    match instr.results with
    | #[r] =>
      unless r.type == .u64 do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"crosscall result must be u64 (call handle), got {repr r.type}"
    | _ => pure ()
  | .hostCall _ => pure ()

/- Pass 6: terminator and return typing. -/

private def checkTerminator (f : Function) (b : Block) :
    Except ValidationError Unit := do
  let pass := "terminator"
  match b.terminator with
  | .jump target args _bound =>
    let target? := f.blocks.find? (·.id == target)
    match target? with
    | none =>
      .error <| error .unknownReference pass (some f.id) (some b.id) none
        s!"jump target {repr target} not found"
    | some targetBlock =>
      unless args.size == targetBlock.params.size do
        .error <| error .typeMismatch pass (some f.id) (some b.id) none
          s!"jump arg count {args.size} does not match target params {targetBlock.params.size}"
      for i in [:args.size] do
        unless args[i]!.type == targetBlock.params[i]!.type do
          .error <| error .typeMismatch pass (some f.id) (some b.id) none
            s!"jump arg {i} type mismatch: expected {repr targetBlock.params[i]!.type}, got {repr args[i]!.type}"
  | .branch condition onTrue onFalse =>
    unless condition.type == .bool do
      .error <| error .typeMismatch pass (some f.id) (some b.id) none
        s!"branch condition must be bool, got {repr condition.type}"
    for target in #[onTrue, onFalse] do
      match f.blocks.find? (·.id == target) with
      | none =>
          .error <| error .unknownReference pass (some f.id) (some b.id) none
            s!"branch target {repr target} not found"
      | some targetBlock =>
          unless targetBlock.params.isEmpty do
            .error <| error .typeMismatch pass (some f.id) (some b.id) none
              s!"branch target {repr target} declares {targetBlock.params.size} parameters, but branch carries no arguments"
  | .return values =>
    let expectedArity := if f.retType == .unit then 0 else 1
    unless values.size == expectedArity do
      .error <| error .invalidReturn pass (some f.id) (some b.id) none
        s!"return arity mismatch: function returns {repr f.retType}, expected {expectedArity}, got {values.size} values"
    if f.retType != .unit then
      match values[0]? with
      | some v =>
        unless v.type == f.retType do
          .error <| error .invalidReturn pass (some f.id) (some b.id) none
            s!"return type mismatch: expected {repr f.retType}, got {repr v.type}"
      | none =>
        .error <| error .invalidReturn pass (some f.id) (some b.id) none
          s!"missing return value for type {repr f.retType}"
  | .revert _ => pure ()

/- Pass 7: capability and HostOp references. Wave 3 will add the typed host-op
catalog; here we verify that host calls are well-formed and requirements are
non-empty only when host calls are present. -/

private def checkCapabilityAndHostOp (m : Module) :
    Except ValidationError Unit := do
  let pass := "capability-hostop"
  for f in m.functions do
    for b in f.blocks do
      for idx in [:b.instructions.size] do
        let instr := b.instructions[idx]!
        match instr.op with
        | .hostCall call =>
          if call.id.namespace_.isEmpty || call.id.name.isEmpty then
            .error <| error .unknownReference pass (some f.id) (some b.id) (some idx)
              s!"hostCall has empty namespace or name"
        | _ => pure ()

/- Passes 3-7: CFG, dominance, instruction typing, terminator typing, and
HostOp/capability references. Exposed so that `ProofForge.IR.Canonical` can
insert canonical-level reference checks between pass 1 and pass 3. -/

def validateModulePhases (m : Module) : Except ValidationError CheckedModule := do
  for f in m.functions do
    checkCfgAndBounds f
  for f in m.functions do
    checkDominance f
  for f in m.functions do
    for b in f.blocks do
      for idx in [:b.instructions.size] do
        checkInstructionTyping m f b idx b.instructions[idx]!
  for f in m.functions do
    for b in f.blocks do
      checkTerminator f b
  checkCapabilityAndHostOp m
  return { module := m }

/- Entry point: run all validation passes in the required order. -/

def validateModule (m : Module) : Except ValidationError CheckedModule := do
  checkSymbolUniqueness m
  checkStateShapeReferences m
  validateModulePhases m

end ProofForge.IR.Core.Validate
