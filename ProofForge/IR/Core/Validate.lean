import ProofForge.IR.Core
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
    checkUnique .duplicateId s!"block in function {repr f.id}"
      (f.blocks.map (·.id))
    let mut valueIds := f.params.map (·.id)
    for b in f.blocks do
      valueIds := valueIds ++ b.params.map (·.id)
      for i in b.instructions do
        valueIds := valueIds ++ i.results.map (·.id)
    checkUnique .duplicateId s!"value in function {repr f.id}" valueIds

/- Pass 2: state-shape reference resolution. Every storage root must exist and
path segments must match the declared shape. -/

private def checkValueRefType (vr : ValueRef) (expected : CoreType)
    (pass : String) (fid : FunctionId) (bid : BlockId) (idx : Nat) :
    Except ValidationError Unit :=
  unless vr.type == expected do
    .error <| error .typeMismatch pass (some fid) (some bid) (some idx)
      s!"expected {repr expected}, got {repr vr.type}"

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
        checkValueRefType key keyTy "state-shape" fid bid idx
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
    let resultShapeType := match shape with
      | .scalar t => t
      | _ => .unit
    unless resultShapeType == path.resultType do
      .error <| error .typeMismatch "state-shape" (some fid) (some bid) (some idx)
        s!"storage result type {repr path.resultType} does not match shape {repr resultShapeType}"

/- Pass 2: state-shape reference resolution. Every storage root must exist and
path segments must match the declared shape. This pass is intentionally
separated from instruction typing so that reference errors are reported before
type and control-flow passes. -/

def checkStateShapeReferences (m : Module) : Except ValidationError Unit := do
  for f in m.functions do
    for b in f.blocks do
      for idx in [:b.instructions.size] do
        let instr := b.instructions[idx]!
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

private def isBackedge (f : Function) (src : BlockId) (dst : BlockId) :
    Bool :=
  let srcIdx? := f.blocks.findIdx? (·.id == src)
  let dstIdx? := f.blocks.findIdx? (·.id == dst)
  match srcIdx?, dstIdx? with
  | some srcIdx, some dstIdx => dstIdx ≤ srcIdx
  | _, _ => false

private def checkCfgAndBounds (f : Function) :
    Except ValidationError Unit := do
  let entry? := f.blocks.find? (·.id == f.entry)
  match entry? with
  | none =>
    .error <| error .unknownReference "cfg" (some f.id) none none
      s!"entry block {repr f.entry} not found"
  | some _ =>
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
          if isBackedge f b succ then
            match block.terminator with
            | .jump _ _ (some _) => pure ()
            | _ =>
              .error <| error .missingLoopBound "cfg" (some f.id) (some b) none
                s!"back edge from {repr b} to {repr succ} lacks a LoopBound"
          stack := stack.push succ
    for b in f.blocks do
      unless visited.contains b.id do
        .error <| error .unknownReference "cfg" (some f.id) (some b.id) none
          s!"block {repr b.id} is unreachable"

/- Pass 4: dominance and value environments. -/

private def referencedValueIds (op : InstructionOp) : Array ValueId :=
  let refs (vrs : Array ValueRef) := vrs.map (·.id)
  match op with
  | .pure p => match p with
    | .literal _ => #[]
    | .unary _ arg => #[arg.id]
    | .arithmetic _ _ lhs rhs => #[lhs.id, rhs.id]
    | .compare _ lhs rhs => #[lhs.id, rhs.id]
    | .cast _ arg => #[arg.id]
    | .hash arg => #[arg.id]
  | .storageLoad path => path.path.foldl (fun acc seg =>
      match seg with | .mapKey k => acc.push k.id | .index i => acc.push i.id | .field _ => acc) #[]
  | .storageContains path => path.path.foldl (fun acc seg =>
      match seg with | .mapKey k => acc.push k.id | .index i => acc.push i.id | .field _ => acc) #[]
  | .storageStore path value =>
    let acc := path.path.foldl (fun acc seg =>
      match seg with | .mapKey k => acc.push k.id | .index i => acc.push i.id | .field _ => acc) #[]
    acc.push value.id
  | .storageLength _ => #[]
  | .storageResize _ length => #[length.id]
  | .memoryAlloc _ length => #[length.id]
  | .memoryLoad base index => #[base.id, index.id]
  | .memoryStore base index value => #[base.id, index.id, value.id]
  | .memoryRelease base => #[base.id]
  | .contextRead _ => #[]
  | .emit _ args => refs args
  | .assert condition _ => #[condition.id]
  | .crosscall _ args => refs args
  | .hostCall call => refs call.args

private def referencedValueIdsTerminator (t : Terminator) : Array ValueId :=
  match t with
  | .jump _ args _ => args.map (·.id)
  | .branch condition _ _ => #[condition.id]
  | .return values => values.map (·.id)
  | .revert _ => #[]

private def checkDominance (f : Function) : Except ValidationError Unit := do
  let mut defined : Std.HashSet ValueId := {}
  -- function parameters are available everywhere
  for p in f.params do defined := defined.insert p.id
  for b in f.blocks do
    -- block parameters are available in the block
    for p in b.params do defined := defined.insert p.id
    for idx in [:b.instructions.size] do
      let instr := b.instructions[idx]!
      for vid in referencedValueIds instr.op do
        unless defined.contains vid do
          .error <| error .invalidDominance "dominance" (some f.id) (some b.id) (some idx)
            s!"value {repr vid} used before definition"
      for r in instr.results do
        defined := defined.insert r.id
    for vid in referencedValueIdsTerminator b.terminator do
      unless defined.contains vid do
        .error <| error .invalidDominance "dominance" (some f.id) (some b.id) none
          s!"value {repr vid} used before definition in terminator"

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
  | .hostCall call =>
    if call.id.namespace_.isEmpty || call.id.name.isEmpty then
      .error <| error .unknownReference pass (some f.id) (some b.id) (some idx)
        s!"hostCall has empty namespace or name"

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
      unless f.blocks.any (·.id == target) do
        .error <| error .unknownReference pass (some f.id) (some b.id) none
          s!"branch target {repr target} not found"
  | .return values =>
    unless values.size == 1 || (f.retType == .unit && values.isEmpty) do
      .error <| error .invalidReturn pass (some f.id) (some b.id) none
        s!"return arity mismatch: function returns {repr f.retType}, got {values.size} values"
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
