import ProofForge.IR.Core.Id
import ProofForge.IR.Core.Type
import ProofForge.IR.Core.Storage
import ProofForge.IR.Core.Syntax
import ProofForge.IR.Core.Error
import ProofForge.IR.Core.HostOp
import Std

namespace ProofForge.IR.Core.Validate

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp
open ProofForge.IR.Core.Error

structure CheckedModule where
  private mk ::
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

private def literalFitsConstructor : CoreLiteral → Bool
  | .u8Lit n => n < 256
  | .u32Lit n => n < 4294967296
  | .u64Lit n => n < 18446744073709551616
  | .u128Lit n => n < 340282366920938463463374607431768211456
  | .bytesLit bytes => bytes.size ≤ maxLogicalCollectionLength
  | .stringLit string => string.toUTF8.size ≤ maxLogicalCollectionLength
  | .unitLit | .boolLit _ => true
  | .addressLit value | .hashLit value => value.toUTF8.size ≤ maxLogicalCollectionLength

private def literalFitsResultType (lit : CoreLiteral) (ty : CoreType) : Bool :=
  match lit, ty with
  | .unitLit, .unit => true
  | .boolLit _, .bool => true
  | .u8Lit _, .u8 => true
  | .u32Lit _, .u32 => true
  | .u64Lit _, .u64 => true
  | .u128Lit _, .u128 => true
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

private def isArrayIndex : CoreType → Bool
  | .u32 | .u64 => true
  | .unit | .bool | .u8 | .u128 | .address | .bytes | .string | .hash |
      .fixedArray _ _ | .array _ | .memoryRef _ | .structType _ => false

private def isMemoryLike : CoreType → Bool
  | .memoryRef _ => true
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes |
      .string | .hash | .fixedArray _ _ | .array _ | .structType _ => false

private def elementType? : CoreType → Option CoreType
  | .bytes => some .u8
  | .array e => some e
  | .fixedArray e _ => some e
  | .memoryRef e => some e
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .string |
      .hash | .structType _ => none

private def isScalar : CoreType → Bool
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 => true
  | _ => false

private def isPortableIdentity : CoreType → Bool
  | .address => true
  | _ => false

private def supportsEquality : CoreType → Bool
  | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes | .string | .hash => true
  | .unit | .fixedArray _ _ | .array _ | .memoryRef _ | .structType _ => false

private def supportsCast (fromTy toTy : CoreType) : Bool :=
  (isIntegerLike fromTy && isIntegerLike toTy) ||
    (fromTy == .address && toTy == .u64) ||
    (fromTy == .u64 && toTy == .address) ||
    (fromTy == toTy && match fromTy with
      | .unit | .bool | .address | .bytes | .string | .hash => true
      | .u8 | .u32 | .u64 | .u128 | .fixedArray _ _ | .array _ |
          .memoryRef _ | .structType _ => false)

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
  | .fixedArray element _ | .array element | .memoryRef element => coreTypeReferences element
  | .structType typeId => #[typeId]
  | _ => #[]

private def coreTypeDepth : CoreType → Nat
  | .fixedArray element _ | .array element | .memoryRef element => coreTypeDepth element + 1
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes |
      .string | .hash | .structType _ => 1

private def moduleTypeFuel (m : Module) (root : CoreType) : Nat :=
  m.structs.foldl (fun total declaration =>
    declaration.fields.foldl (fun fieldTotal field =>
      fieldTotal + coreTypeDepth field.type) total)
    (coreTypeDepth root + m.structs.size + 1)

private def saturatingAdd (lhs rhs : Nat) : Nat :=
  if lhs > maxLogicalCollectionLength || rhs > maxLogicalCollectionLength - lhs then
    maxLogicalCollectionLength + 1
  else lhs + rhs

private def saturatingMul (lhs rhs : Nat) : Nat :=
  if lhs == 0 || rhs == 0 then 0
  else if lhs > maxLogicalCollectionLength / rhs then maxLogicalCollectionLength + 1
  else lhs * rhs

private def typeFootprintFuel (m : Module) : Nat → CoreType → Nat
  | 0, _ => maxLogicalCollectionLength + 1
  | fuel + 1, type => match type with
    | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes |
        .string | .hash | .memoryRef _ => 1
    | .fixedArray element length =>
        max 1 (saturatingMul length (typeFootprintFuel m fuel element))
    | .array _ => 1
    | .structType typeId =>
        match m.structs.find? (·.id == typeId) with
        | none => maxLogicalCollectionLength + 1
        | some declaration => max 1 <| declaration.fields.foldl (fun total field =>
            saturatingAdd total (typeFootprintFuel m fuel field.type)) 0

private def typeFootprint (m : Module) (type : CoreType) : Nat :=
  typeFootprintFuel m (moduleTypeFuel m type) type

private def stateShapeFootprint (m : Module) (shape : StateShape) : Nat :=
  match shape with
  | .scalar type => typeFootprint m type
  | .record typeId => typeFootprint m (.structType typeId)
  | .fixedArray element length =>
      max 1 (saturatingMul length (typeFootprint m element))
  | .dynamicArray _ => 1
  | .map key value (some capacity) =>
      max 1 (saturatingMul capacity
        (saturatingAdd (typeFootprint m key) (typeFootprint m value)))
  | .map key value none =>
      max 1 (saturatingAdd (typeFootprint m key) (typeFootprint m value))

private def containsMemoryRef : CoreType → Bool
  | .memoryRef _ => true
  | .fixedArray element _ | .array element => containsMemoryRef element
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes |
      .string | .hash | .structType _ => false

private def rejectEphemeralType (ty : CoreType) (context : String)
    (function : Option FunctionId := none) (block : Option BlockId := none)
    (instruction : Option Nat := none) : Except ValidationError Unit := do
  if containsMemoryRef ty then
    .error <| error .typeMismatch "state-shape" function block instruction
      s!"{context} cannot contain ephemeral memoryRef type {repr ty}"

private def reachesStruct (m : Module) (target : TypeId) : Nat → TypeId → Bool
  | 0, _ => false
  | fuel + 1, current =>
      match m.structs.find? (·.id == current) with
      | none => false
      | some declaration => declaration.fields.any fun field =>
          field.ownership == .value &&
            (coreTypeReferences field.type).any fun next =>
              next == target || reachesStruct m target fuel next

private def checkStructAcyclic (m : Module) : Except ValidationError Unit := do
  for declaration in m.structs do
    if reachesStruct m declaration.id (m.structs.size + 1) declaration.id then
      .error <| ValidationError.mkSimple .typeMismatch "state-shape"
        s!"recursive by-value struct cycle reaches {repr declaration.id}"

private def checkCoreTypeReferences (m : Module) (ty : CoreType)
    (context : String) (function : Option FunctionId := none)
    (block : Option BlockId := none) (instruction : Option Nat := none) :
    Except ValidationError Unit := do
  let rec checkBounds : CoreType → Except ValidationError Unit
    | .fixedArray element length => do
        if length > maxLogicalCollectionLength then
          .error <| error .typeMismatch "state-shape" function block instruction
            s!"{context} fixed-array length {length} exceeds {maxLogicalCollectionLength}"
        checkBounds element
    | .array element | .memoryRef element => checkBounds element
    | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes |
        .string | .hash | .structType _ => pure ()
  checkBounds ty
  for typeId in coreTypeReferences ty do
    unless m.structs.any (·.id == typeId) do
      .error <| error .unknownReference "state-shape" function block instruction
        s!"{context} references unknown struct type {repr typeId}"
  let checkFootprint (type : CoreType) : Except ValidationError Unit := do
      let footprint := typeFootprint m type
      if footprint > maxLogicalCollectionLength then
        .error <| error .typeMismatch "state-shape" function block instruction
          s!"{context} total footprint {footprint} exceeds {maxLogicalCollectionLength}"
  let rec checkFootprints : CoreType → Except ValidationError Unit
    | .fixedArray element length => do
        checkFootprint (.fixedArray element length)
        checkFootprints element
    | .array element => do
        checkFootprint (.array element)
        checkFootprints element
    | .memoryRef element => do
        checkFootprint (.memoryRef element)
        checkFootprints element
    | type => checkFootprint type
  checkFootprints ty

private def stateShapeTypes : StateShape → Array CoreType
  | .scalar value => #[value]
  | .map key value _ => #[key, value]
  | .fixedArray element length => #[.fixedArray element length]
  | .dynamicArray element => #[.array element]
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
  checkUnique .duplicateId "error" (m.errors.map (·.id))
  for struct in m.structs do
    checkUnique .duplicateId s!"field in struct {repr struct.id}" (struct.fields.map (·.id))
  for event in m.events do
    checkUnique .duplicateId s!"field in event {repr event.id}" (event.fields.map (·.id))
  let errorIdentities := m.errors.map (fun declaration =>
    (declaration.namespace_, declaration.name, declaration.code))
  checkUnique .duplicateId "error identity" errorIdentities
  for declaration in m.errors do
    if declaration.namespace_.isEmpty || declaration.name.isEmpty then
      .error <| ValidationError.mkSimple .unknownReference "symbol-uniqueness"
        s!"error {repr declaration.id} has empty namespace or name"
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

private inductive StorageCursor
  | scalar (type : CoreType)
  | fixedArray (element : CoreType) (length : Nat)
  | dynamicArray (element : CoreType)
  | record (type : TypeId)
  | map (key value : CoreType)

private def cursorOfType : CoreType → StorageCursor
  | .fixedArray element length => .fixedArray element length
  | .array element => .dynamicArray element
  | .memoryRef type => .scalar (.memoryRef type)
  | .structType type => .record type
  | .unit => .scalar .unit
  | .bool => .scalar .bool
  | .u8 => .scalar .u8
  | .u32 => .scalar .u32
  | .u64 => .scalar .u64
  | .u128 => .scalar .u128
  | .address => .scalar .address
  | .bytes => .scalar .bytes
  | .string => .scalar .string
  | .hash => .scalar .hash

private def cursorOfShape : StateShape → StorageCursor
  | .scalar type => cursorOfType type
  | .map key value _ => .map key value
  | .fixedArray element length => .fixedArray element length
  | .dynamicArray element => .dynamicArray element
  | .record type => .record type

private def cursorType? : StorageCursor → Option CoreType
  | .scalar type => some type
  | .fixedArray element length => some (.fixedArray element length)
  | .dynamicArray element => some (.array element)
  | .record type => some (.structType type)
  | .map _ _ => none

private def checkStoragePath (m : Module) (fid : FunctionId) (bid : BlockId)
    (idx : Nat) (path : StorageRef) (requirePresence : Bool := false) :
    Except ValidationError Unit := do
  let state? := m.state.find? (·.id == path.root)
  match state? with
  | none =>
    .error <| error .unknownReference "state-shape" (some fid) (some bid) (some idx)
      s!"unknown storage root {repr path.root}"
  | some decl =>
    let mut cursor := cursorOfShape decl.shape
    let mut hasPresence := false
    for seg in path.path do
      match seg, cursor with
      | .mapKey key, .map keyTy valTy =>
        unless key.type == keyTy do
          .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
            s!"map key type {repr key.type} does not match {repr keyTy}"
        cursor := cursorOfType valTy
        hasPresence := true
      | .mapKey _, _ =>
        .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
          s!"map key on non-map state {repr path.root}"
      | .index idxRef, .fixedArray elem _ =>
        unless idxRef.type == .u32 || idxRef.type == .u64 do
          .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
            s!"array index must be integer, got {repr idxRef.type}"
        cursor := cursorOfType elem
        hasPresence := true
      | .index idxRef, .dynamicArray elem =>
        unless idxRef.type == .u32 || idxRef.type == .u64 do
          .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
            s!"array index must be integer, got {repr idxRef.type}"
        cursor := cursorOfType elem
        hasPresence := true
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
          let field? := struct.fields.find? (·.id == fieldId)
          match field? with
          | none =>
            .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
              s!"unknown field {repr fieldId} in struct {repr typeId}"
          | some fieldDef =>
            cursor := cursorOfType fieldDef.type
            hasPresence := true
      | .field _, _ =>
        .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
          s!"field access on non-record state {repr path.root}"
    if requirePresence && !hasPresence then
      .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
        "storageContains requires a map key, array index, or record field"
    match cursorType? cursor with
    | some resultShapeType =>
      unless resultShapeType == path.resultType do
        .error <| error .typeMismatch "state-shape" (some fid) (some bid) (some idx)
          s!"storage result type {repr path.resultType} does not match shape {repr resultShapeType}"
    | none =>
      .error <| error .invalidStoragePath "state-shape" (some fid) (some bid) (some idx)
        s!"storage path for root {repr path.root} does not select a typed value"

/- Pass 2: state-shape reference resolution. Every storage root must exist and
path segments must match the declared shape. This pass is intentionally
separated from instruction typing so that reference errors are reported before
type and control-flow passes. -/

def checkStateShapeReferences (m : Module) : Except ValidationError Unit := do
  checkStructAcyclic m
  for struct in m.structs do
    unless struct.semantics == .value do
      .error <| ValidationError.mkSimple .typeMismatch "state-shape"
        s!"struct {repr struct.id} uses unsupported linear-record semantics"
    for field in struct.fields do
      unless field.ownership == .value do
        .error <| ValidationError.mkSimple .typeMismatch "state-shape"
          s!"struct {repr struct.id} field {repr field.id} uses unsupported reference ownership"
      rejectEphemeralType field.type s!"struct {repr struct.id} field {repr field.id}"
      checkCoreTypeReferences m field.type s!"struct {repr struct.id} field {repr field.id}"
  for event in m.events do
    for field in event.fields do
      rejectEphemeralType field.type s!"event {repr event.id} field {repr field.id}"
      checkCoreTypeReferences m field.type s!"event {repr event.id} field {repr field.id}"
  for errorDecl in m.errors do
    for param in errorDecl.params do
      rejectEphemeralType param s!"error {repr errorDecl.id} parameter"
      checkCoreTypeReferences m param s!"error {repr errorDecl.id} parameter"
  for decl in m.state do
    match decl.shape with
    | .map _ _ (some capacity) =>
        if capacity > maxLogicalCollectionLength then
          .error <| ValidationError.mkSimple .typeMismatch "state-shape"
            s!"state {repr decl.id} map capacity {capacity} exceeds {maxLogicalCollectionLength}"
    | .fixedArray _ length =>
        if length > maxLogicalCollectionLength then
          .error <| ValidationError.mkSimple .typeMismatch "state-shape"
            s!"state {repr decl.id} fixed-array length {length} exceeds {maxLogicalCollectionLength}"
    | .scalar _ | .map _ _ none | .dynamicArray _ | .record _ => pure ()
    for ty in stateShapeTypes decl.shape do
      rejectEphemeralType ty s!"state {repr decl.id}"
      checkCoreTypeReferences m ty s!"state {repr decl.id}"
    match decl.shape with
    | .map keyType valueType (some capacity) =>
        let entryFootprint := saturatingAdd (typeFootprint m keyType)
          (typeFootprint m valueType)
        let totalFootprint := saturatingMul capacity entryFootprint
        if totalFootprint > maxLogicalCollectionLength then
          .error <| ValidationError.mkSimple .typeMismatch "state-shape"
            s!"state {repr decl.id} map capacity footprint {totalFootprint} exceeds {maxLogicalCollectionLength}"
    | .scalar _ | .map _ _ none | .fixedArray _ _ | .dynamicArray _ | .record _ =>
        pure ()
    let footprint := stateShapeFootprint m decl.shape
    if footprint > maxLogicalCollectionLength then
      .error <| ValidationError.mkSimple .typeMismatch "state-shape"
        s!"state {repr decl.id} shape footprint {footprint} exceeds {maxLogicalCollectionLength}"
  for f in m.functions do
    for param in f.params do
      rejectEphemeralType param.type s!"function {repr f.id} parameter {repr param.id}"
        (some f.id)
      checkCoreTypeReferences m param.type s!"function {repr f.id} parameter {repr param.id}"
        (some f.id)
    rejectEphemeralType f.retType s!"function {repr f.id} return type" (some f.id)
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
        | .storageLoad path | .storageStore path _ =>
          checkStoragePath m f.id b.id idx path
        | .storageContains path =>
          checkStoragePath m f.id b.id idx path true
        | .storageLength root =>
          let declaration ← match m.state.find? (·.id == root) with
          | none =>
            .error <| error .unknownReference "state-shape" (some f.id) (some b.id) (some idx)
              s!"unknown storage root {repr root}"
          | some declaration => pure declaration
          match declaration.shape with
          | .fixedArray _ _ | .dynamicArray _ => pure ()
          | .scalar _ | .map _ _ _ | .record _ =>
            .error <| error .invalidStoragePath "state-shape" (some f.id) (some b.id) (some idx)
              s!"storageLength requires array root, got {repr declaration.shape}"
        | .storageResize root _ =>
          let declaration ← match m.state.find? (·.id == root) with
          | none =>
            .error <| error .unknownReference "state-shape" (some f.id) (some b.id) (some idx)
              s!"unknown storage root {repr root}"
          | some declaration => pure declaration
          match declaration.shape with
          | .dynamicArray _ => pure ()
          | .scalar _ | .map _ _ _ | .fixedArray _ _ | .record _ =>
            .error <| error .invalidStoragePath "state-shape" (some f.id) (some b.id) (some idx)
              s!"storageResize requires dynamic-array root, got {repr declaration.shape}"
        | .memoryAlloc type _ =>
          rejectEphemeralType type "memory allocation element type"
            (some f.id) (some b.id) (some idx)
          checkCoreTypeReferences m type "memory allocation element type"
            (some f.id) (some b.id) (some idx)
        | .crosscall spec _ =>
          rejectEphemeralType spec.returnType "crosscall return type"
            (some f.id) (some b.id) (some idx)
          checkCoreTypeReferences m spec.returnType "crosscall return type"
            (some f.id) (some b.id) (some idx)
          for type in spec.paramTypes do
            rejectEphemeralType type "crosscall parameter type"
              (some f.id) (some b.id) (some idx)
            checkCoreTypeReferences m type "crosscall parameter type"
              (some f.id) (some b.id) (some idx)
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
      match b.terminator with
      | .jump target _ (some _) =>
          unless isReachable f target b.id do
            .error <| error .typeMismatch "cfg" (some f.id) (some b.id) none
              s!"LoopBound is only valid on a cycle edge, got {repr b.id} -> {repr target}"
      | .jump _ _ none | .branch _ _ _ | .return _ | .revert _ => pure ()
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
    | .hashTwoToOne lhs rhs => #[lhs, rhs]
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
  | .assert condition error => #[condition] ++ error.args
  | .crosscall spec args =>
    #[spec.target, spec.method] ++ optionalValueRef spec.gas ++
      optionalValueRef spec.value ++ args
  | .hostCall call => call.args

private def referencedValueRefsTerminator (t : Terminator) : Array ValueRef :=
  match t with
  | .jump _ args _ => args
  | .branch condition _ _ => #[condition]
  | .return values => values
  | .revert error => error.args

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
    unless literalFitsConstructor lit do
      .error <| error .literalOutOfRange "instruction-typing" (some fid) (some bid) (some idx)
        s!"literal {literalTypeName lit} payload exceeds its constructor range or collection limit"
    unless literalFitsResultType lit r.type do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"literal constructor {literalTypeName lit} does not match result type {repr r.type}"
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
  | .compare op lhs rhs, #[r] =>
    unless lhs.type == rhs.type && r.type == .bool && supportsEquality lhs.type do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"compare operands must match and result bool, got {repr lhs.type}, {repr rhs.type} -> {repr r.type}"
    if !isIntegerLike lhs.type && op != .eq && op != .ne then
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"non-integer comparison {repr op} is not portable"
  | .cast to arg, #[r] =>
    unless r.type == to && supportsCast arg.type to do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"cast expects scalar operand and target type, got {repr arg.type} -> {repr to}"
  | .hash arg, #[r] =>
    unless (arg.type == .hash || arg.type == .address) && r.type == .hash do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        s!"hash input must be hash/address and result hash, got {repr arg.type} -> {repr r.type}"
  | .hashTwoToOne lhs rhs, #[r] =>
    unless lhs.type == .hash && rhs.type == .hash && r.type == .hash do
      .error <| error .typeMismatch "instruction-typing" (some fid) (some bid) (some idx)
        "hashTwoToOne expects two hash operands and a hash result"
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
  | .pure (.hashTwoToOne _ _) => 1
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
  | .crosscall spec _ => if spec.returnType == .unit then 0 else 1
  | .hostCall _ => 1

private def checkErrorRef (m : Module) (f : Function) (b : Block)
    (instruction : Option Nat) (errorRef : CoreErrorRef) :
    Except ValidationError Unit := do
  let declaration ← match m.errors.find? (·.id == errorRef.id) with
    | none =>
      .error <| error .unknownReference "error-reference" (some f.id) (some b.id)
        instruction s!"unknown error {repr errorRef.id}"
    | some declaration => pure declaration
  unless errorRef.args.size == declaration.params.size do
    .error <| error .typeMismatch "error-reference" (some f.id) (some b.id)
      instruction
      s!"error {repr errorRef.id} expects {declaration.params.size} args, got {errorRef.args.size}"
  for i in [:errorRef.args.size] do
    unless errorRef.args[i]!.type == declaration.params[i]! do
      .error <| error .typeMismatch "error-reference" (some f.id) (some b.id)
        instruction
        s!"error arg {i} type mismatch: expected {repr declaration.params[i]!}, got {repr errorRef.args[i]!.type}"

private def validCrosscallMethodType : CoreType → Bool
  | .string | .bytes | .hash => true
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address |
      .fixedArray _ _ | .array _ | .memoryRef _ | .structType _ => false

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
      unless r.type == .memoryRef ty do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"memoryAlloc result type {repr r.type} does not match memory reference {repr ty}"
    | _ => pure ()
  | .memoryLoad base index =>
    unless isMemoryLike base.type && isArrayIndex index.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryLoad base/index types invalid: {repr base.type}, {repr index.type}"
    match instr.results with
    | #[r] =>
      unless some r.type == elementType? base.type do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"memoryLoad result type {repr r.type} does not match base element"
    | _ => pure ()
  | .memoryStore base index value =>
    unless isMemoryLike base.type && isArrayIndex index.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryStore base/index types invalid: {repr base.type}, {repr index.type}"
    unless some value.type == elementType? base.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryStore value type {repr value.type} does not match base element"
  | .memoryRelease base =>
    unless isMemoryLike base.type do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"memoryRelease base must be memoryRef, got {repr base.type}"
  | .contextRead field =>
    match instr.results with
    | #[r] =>
      let expected := match field with
        | .sender | .origin | .contractAddress => .address
        | .randomSeed => .hash
        | .value => .u128
        | .blockNumber | .blockTimestamp | .epochHeight | .gas => .u64
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
  | .assert condition errorRef =>
    unless condition.type == .bool do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"assert condition must be bool, got {repr condition.type}"
    checkErrorRef m f b (some idx) errorRef
  | .crosscall spec args =>
    let targetTypeOk : Bool := match spec.mode with
      | .nearPoolInvoke | .nearPromiseThen =>
          spec.target.type == .u32 || spec.target.type == .u64
      | _ => spec.target.type == .address
    unless targetTypeOk do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"crosscall target type is invalid for {repr spec.mode}: got {repr spec.target.type}"
    let methodTypeOk : Bool := match spec.mode with
      | .nearPoolInvoke | .nearPromiseThen =>
          spec.method.type == .u32 || spec.method.type == .u64 || spec.method.type == .address
      | _ => validCrosscallMethodType spec.method.type
    unless methodTypeOk do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"crosscall method type is invalid for {repr spec.mode}: got {repr spec.method.type}"
    match spec.gas with
    | some gas => unless gas.type == .u64 do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"crosscall gas must be u64, got {repr gas.type}"
    | none => pure ()
    match spec.value with
    | some value =>
        let valueTypeOk : Bool := match spec.mode with
          | .nearPoolInvoke | .nearPromiseThen => value.type == .u64 || value.type == .u128
          | _ => value.type == .u128
        unless valueTypeOk do
          .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
            s!"crosscall value type is invalid for {repr spec.mode}: got {repr value.type}"
        if spec.mode == .staticInvoke || spec.mode == .delegateInvoke then
          .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
            "static/delegate crosscall cannot carry value"
    | none => pure ()
    unless args.size == spec.paramTypes.size do
      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
        s!"crosscall expects {spec.paramTypes.size} args, got {args.size}"
    for i in [:args.size] do
      unless args[i]!.type == spec.paramTypes[i]! do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          s!"crosscall arg {i} type mismatch: expected {repr spec.paramTypes[i]!}, got {repr args[i]!.type}"
    if spec.returnType == .unit then
      unless instr.results.isEmpty do
        .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
          "unit crosscall must not bind a result"
    else
      match instr.results with
      | #[r] =>
        unless r.type == spec.returnType do
          .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
            s!"crosscall result type {repr r.type} does not match {repr spec.returnType}"
      | _ => pure ()
  | .hostCall _ => pure ()

/- Pass 6: terminator and return typing. -/

private def checkTerminator (m : Module) (f : Function) (b : Block) :
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
  | .revert errorRef => checkErrorRef m f b none errorRef

/- Pass 7: capability and HostOp references. When a catalog is provided, verify
that each `hostCall` has a known signature, argument types match, result types
match, and the effect class is not pure. Without a catalog, fall back to the
basic empty-namespace/name check. -/

private def checkCapabilityAndHostOp (m : Module) (catalog? : Option HostOpCatalog) :
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
          match catalog? with
          | none => pure ()
          | some catalog =>
              match catalog.lookup call.id with
              | Except.error _ =>
                  .error <| error .unknownReference pass (some f.id) (some b.id) (some idx)
                    s!"hostCall references unknown host op {call.id.render}"
              | Except.ok sig =>
                  let argTypes := call.args.map (·.type)
                  match HostOpCatalog.validateCall sig argTypes with
                  | Except.error e =>
                      .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
                        s!"hostCall argument validation failed: {repr e}"
                  | Except.ok _ =>
                      let resultTypes := instr.results.map (·.type)
                      match HostOpCatalog.validateResults sig resultTypes with
                      | Except.error e =>
                          .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
                            s!"hostCall result validation failed: {repr e}"
                      | Except.ok _ =>
                          match HostOpCatalog.validateCallUsage sig with
                          | Except.error e =>
                              .error <| error .typeMismatch pass (some f.id) (some b.id) (some idx)
                                s!"hostCall effect class mismatch: {repr e}"
                          | Except.ok _ => pure ()
        | _ => pure ()

/- Passes 3-7: CFG, dominance, instruction typing, terminator typing, and
HostOp/capability references. Exposed so that `ProofForge.IR.Canonical` can
insert canonical-level reference checks between pass 1 and pass 3. -/

def validateModulePhases (m : Module) (catalog? : Option HostOpCatalog := none) : Except ValidationError Unit := do
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
      checkTerminator m f b
  checkCapabilityAndHostOp m catalog?
  return ()

/- Entry point: run all validation passes in the required order. -/

def validateModule (m : Module) (catalog? : Option HostOpCatalog := none) : Except ValidationError CheckedModule := do
  checkSymbolUniqueness m
  checkStateShapeReferences m
  validateModulePhases m catalog?
  return { module := m }

end ProofForge.IR.Core.Validate
