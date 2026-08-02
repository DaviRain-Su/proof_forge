import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Aleo LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the Aleo-owned Plan surface and the retained-`SemanticProgramV1` Plan body.
Plan canonicity lives in `ValidatePlanV1`; Leo emission in `EmitIRV1`.
`FinalizeV1` remains a separate submodule.

## Coverage boundary (AleoCoverage + H3 PsyAleoAggregate)

LOWERED (product path): scalar stateLoad/stateStore (UInt64), checked
arithmetic/compare/bitwise/shift/logical, unary not/bitNot, pureCall,
bare assert, bare revert (`assert(false)`), if/switch/for, Commit identity
passthrough (label-only; no crypto commitment realization), **named Struct/Enum
and fixed Array UInt64 N** via flatten-to-mapping leaves (`name_field` /
`name_i` → consecutive `pf_state_*` mappings).

FAIL-CLOSED (explicit pins, not catch-all GAP):
  * **Field (bn254 Fr)** — research pin: Aleo native `field` is the BLS12-377
    scalar field (Edwards BLS Fr = BLS12-377 Fr), **not** catalog bn254 Fr.
    Mapping would be a silent wrong modulus. Keep `pilotFieldPolicyNone`.
  * **Map/Bytes/Option/String/Principal state** — outside Array-only container pilot.
  * **ContextRead** — no host clock ABI in Leo 4.0.2 Final model for this pilot.
  * **emit / externalCall / schedule / revert-with-args** — no Leo analogue
    (resolver also declines event/sync/async requirement keys).
  * Array IndexGet/IndexSet require compile-time UInt literal index.
-/

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Engineering codegen profile for the Leo 4.0.2 source slice. Any change to
    the supported surface or the Leo toolchain requires a new profile. -/
def codegenProfile : CodegenProfileId := CodegenProfileId.aleoLeoU64V1

/-- Locked Leo toolchain version string (source-only; no approved digest-pinned
    `leo` binary is configured, mirroring the Noir zero-tool finalization). -/
def leoToolchain : String := "4.0.2"

/-- Engineering descriptor (shared DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.aleo

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

/-- Target-owned Aleo Plan expression over the shipped public UInt64/Bool
    semantic envelope. UInt32 shift counts are promoted to UInt64 values with
    an explicit `count < 64` guard at emission. -/
inductive Expr where
  | literal (value : UInt64)
  | boolLiteral (value : Bool)
  | param (inputIndex : Nat)
  /-- The induction value of the enclosing bounded `for` at loop stack depth
      `loopDepth` (0 = outermost). -/
  | loopVar (loopDepth : Nat)
  | stateLoad (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | bitAnd (lhs rhs : Expr)
  | bitOr (lhs rhs : Expr)
  | bitXor (lhs rhs : Expr)
  /-- Strict Bool and/or: both sides are evaluated (no short circuit). -/
  | logicalAnd (lhs rhs : Expr)
  | logicalOr (lhs rhs : Expr)
  /-- UInt64 << / >> with an explicit count < 64 guard at emission. -/
  | shl (lhs rhs : Expr)
  | shr (lhs rhs : Expr)
  | bitNot (operand : Expr)
  | boolNot (operand : Expr)
  | callFn (fnName : String) (args : Array Expr)
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (fieldIndex : Nat) (value : Expr)
  | assert (condition : Expr)
  | returnValue (value : Expr)
  | returnNone
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  /-- Bounded for (see module doc for the exact Leo encoding). -/
  | forLoop (start endExclusive : Expr) (maxIterations : Nat)
      (body : Array Statement)
  | emitEvent (eventIndex : Nat) (args : Array Expr)
  | revertError (errorIndex : Nat) (args : Array Expr)
  deriving BEq, Inhabited, Repr

inductive FunctionKind where
  | initialize
  | mutate
  deriving BEq, Inhabited, Repr

structure PlanParam where
  sourceIndex : Nat
  name : String
  isBool : Bool
  deriving BEq, Inhabited, Repr

/-- One callable artifact. `resultDropped` records that a non-Unit result
    cannot be returned by Leo's `Final` model (see module doc): the value is
    observable post-transaction via `leo query`, and each return expression
    is still evaluated in the final block for failure semantics. -/
structure PlanFunction where
  index : Nat
  name : String
  kind : FunctionKind
  params : Array PlanParam
  body : Array Statement
  /-- True when the body reads or writes mappings (Final function). -/
  touchesState : Bool
  resultIsBool : Bool
  resultDropped : Bool
  deriving BEq, Inhabited, Repr

/-- Bare public-state read view: materializes as an off-chain mapping query
    (the EVM `eth_call` analogue), never as an on-chain artifact. -/
structure PlanView where
  name : String
  stateFieldIndex : Nat
  deriving BEq, Inhabited, Repr

/-- Target-owned Aleo Plan. Retains no SemanticProgram; carries the canonical
    source/semantic digests and the artifact program name. -/
structure Plan where
  programName : String
  stateFieldNames : Array String
  functions : Array PlanFunction
  views : Array PlanView
  sourceHash : String
  semanticHash : String
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

private def aleoPlanErr (message : String) : CompileError :=
  .planInvariant .aleo message

/-- Aleo type-closure wording. Field pin cites BLS12-377 Fr ≠ bn254 Fr. -/
private def aleoTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Aleo"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/UInt32 widths are supported"
  unsupportedShapeDetail :=
    "only UInt64, UInt32, Unit, Bool, named Struct/Enum, and Array UInt64 are supported (Aleo native field is BLS12-377 Fr / Edwards BLS scalar, not bn254 Fr; Map/Bytes/Option/Principal/String stay fail-closed)"

/-- Aleo pilot type-closure: UInt64 + UInt32 + Unit/Bool + named Struct/Enum +
    Array (H3 flatten-to-mapping leaves). Field stays `pilotFieldPolicyNone`
    (BLS12-377 ≠ bn254). Map/Bytes/Option/Principal/String fail closed. -/
private def validateAleoTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult PilotTypeClosureV1 :=
  validatePilotTypeClosure aleoPlanErr aleoTypeClosureWording types
    pilotUintWidthPolicyU64U32
    (intPolicy := pilotIntWidthPolicyNone)
    (fieldPolicy := pilotFieldPolicyNone)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayOnly)

-- ---------------------------------------------------------------------------
-- Wire semantic → target-owned Plan lowering
-- ---------------------------------------------------------------------------

private def maxIdentifierBytes : Nat := 240
private def maxStateLeafFields : Nat := 256

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

private abbrev AleoTypeClosureV1 := PilotTypeClosureV1

private structure LoweredVal where
  expr : Expr
  leaves? : Option (Array Expr) := none
  deriving Inhabited

private def LoweredVal.isAggregate (v : LoweredVal) : Bool :=
  v.leaves?.isSome

private def LoweredVal.leafExprs (v : LoweredVal) : Array Expr :=
  match v.leaves? with
  | some ls => ls
  | none => #[v.expr]

private def mkScalarVal (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none }

private def mkAggregateVal (leaves : Array Expr) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves }

private structure ValueEnv where
  entries : Array (ValueIdV1 × LoweredVal)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option LoweredVal :=
  env.entries.findSome? (fun (vid, v) => if vid == id then some v else none)

private def envLookupExpr (env : ValueEnv) (id : ValueIdV1) : Option Expr :=
  (envLookup env id).map (·.expr)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (e : Expr) : ValueEnv :=
  { env with entries := env.entries.push (id, mkScalarVal e) }

private def envInsertVal (env : ValueEnv) (id : ValueIdV1) (v : LoweredVal) : ValueEnv :=
  { env with entries := env.entries.push (id, v) }

private structure AleoLowerLayoutV1 where
  fieldNames : Array String
  stateLeaves : Array (Array Nat)
  typeDecls : Array TypeDeclV1
  types : AleoTypeClosureV1

private def isUInt64Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 64, .. } => true
  | _ => false

private def isBoolType (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .bool, .. } => true
  | _ => false

private def isUInt32Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 32, .. } => true
  | _ => false

private def isUnitType (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .unit, .. } => true
  | _ => false

private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array String) := do
  if typeId == types.uint64TypeId then
    pure #[namePrefix]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        planError s!"unsupported Aleo semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              planError "unsupported Aleo semantic shape: named Struct requires at least one field"
            let mut out : Array String := #[]
            for f in fields do
              let subName :=
                if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
              unless isIdentifier subName do
                planError s!"state name '{subName}' is not a safe identifier"
              let sub ← flattenTypeLeafSpecsV1 typeDecls types f.typeId subName
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              planError "unsupported Aleo semantic shape: named Enum requires at least one variant"
            let tagName :=
              if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
            unless isIdentifier tagName do
              planError s!"state name '{tagName}' is not a safe identifier"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenTypeLeafSpecsV1 typeDecls types pt "tmp"
                n := n + sub.size
              if n > maxPay then maxPay := n
            let mut out : Array String := #[tagName]
            for i in [0:maxPay] do
              let pName :=
                if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
              unless isIdentifier pName do
                planError s!"state name '{pName}' is not a safe identifier"
              out := out.push pName
            pure out
        | _ =>
            planError "unsupported Aleo semantic shape: named type must be Struct or Enum"
  else if types.isContainer typeId then
    match typeDecls[typeId.toNat]? with
    | some { shape := .array elTid len, .. } =>
        unless elTid == types.uint64TypeId do
          planError "unsupported Aleo semantic shape: Array state element must be UInt64"
        let n := len.toNat
        unless n ≥ 1 do
          planError "unsupported Aleo semantic shape: Array state length must be ≥ 1"
        let mut out : Array String := #[]
        for i in [0:n] do
          let leafName := namePrefix ++ "_" ++ toString i
          unless isIdentifier leafName do
            planError s!"state name '{leafName}' is not a safe identifier"
          out := out.push leafName
        pure out
    | some { shape := .map .., .. } =>
        planError "unsupported Aleo semantic shape: Map state is outside the Aleo Array-only container pilot"
    | some { shape := .bytes _, .. } =>
        planError "unsupported Aleo semantic shape: Bytes state is outside the Aleo Array-only container pilot"
    | _ =>
        planError "unsupported Aleo semantic shape: container TypeId is not Array/Map/Bytes"
  else
    planError "unsupported Aleo semantic shape: aggregate leaf must be UInt64, named Struct/Enum, or Array UInt64"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (fields : Array StructFieldV1) (fieldIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let mut start : Nat := 0
  for i in [0:fields.size] do
    let some f := fields[i]? |
      planError "struct field index out of range"
    let n ← leafCountOfTypeV1 typeDecls types f.typeId
    if i == fieldIndex then return (start, n)
    start := start + n
  planError "struct field index out of range"

private def enumMaxPayloadLeavesV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (variants : Array EnumVariantV1) : CompileResult Nat := do
  let mut maxPay : Nat := 0
  for v in variants do
    let mut n : Nat := 0
    for pt in v.payloadTypes do
      let c ← leafCountOfTypeV1 typeDecls types pt
      n := n + c
    if n > maxPay then maxPay := n
  pure maxPay

private def enumPayloadLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (variants : Array EnumVariantV1) (variantIndex payloadIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let some v := variants[variantIndex]? |
    planError "enum variant index out of range"
  let mut start : Nat := 0
  for i in [0:v.payloadTypes.size] do
    let some pt := v.payloadTypes[i]? |
      planError "enum payload index out of range"
    let n ← leafCountOfTypeV1 typeDecls types pt
    if i == payloadIndex then return (start, n)
    start := start + n
  planError "enum payload index out of range"

private def arrayUInt64LeafCountV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless elTid == types.uint64TypeId do
        planError "unsupported Aleo semantic shape: Array state element must be UInt64"
      let n := len.toNat
      unless n ≥ 1 do
        planError "unsupported Aleo semantic shape: Array state length must be ≥ 1"
      pure (some n)
  | some { shape := .map .., .. } =>
      planError "unsupported Aleo semantic shape: Map state is outside the Aleo Array-only container pilot"
  | some { shape := .bytes _, .. } =>
      planError "unsupported Aleo semantic shape: Bytes state is outside the Aleo Array-only container pilot"
  | _ =>
      planError "unsupported Aleo semantic shape: container TypeId is not Array/Map/Bytes"

private def makeStateLayoutV1
    (types : AleoTypeClosureV1) (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult AleoLowerLayoutV1 := do
  let mut fieldNames : Array String := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      planError "unsupported Aleo semantic shape: semantic state ids must match declaration order"
    unless isIdentifier state.name do
      planError s!"state name '{state.name}' is not a safe identifier"
    if types.isNamedAggregate state.typeId || types.isContainer state.typeId then
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
      if fieldNames.size + leafSpecs.size > maxStateLeafFields then
        planError "unsupported Aleo semantic shape: state leaf count exceeds Aleo profile limit"
      let mut leaves : Array Nat := #[]
      for name in leafSpecs do
        leaves := leaves.push fieldNames.size
        fieldNames := fieldNames.push name
      stateLeaves := stateLeaves.push leaves
    else if state.typeId == types.uint64TypeId then
      let leafIdx := fieldNames.size
      fieldNames := fieldNames.push state.name
      stateLeaves := stateLeaves.push #[leafIdx]
    else
      planError "Aleo state must be UInt64, named Struct/Enum, or Array UInt64 (Map/Bytes/Option/Field declined)"
  pure { fieldNames, stateLeaves, typeDecls, types }

private def literalIndexNatV1 (v : LoweredVal) : CompileResult Nat := do
  unless !v.isAggregate do
    planError "unsupported Aleo semantic shape: Array index must be a scalar UInt literal"
  match v.expr with
  | .literal n => pure n.toNat
  | _ =>
      planError "unsupported Aleo semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    planError "Aleo UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ => planError "Aleo UInt64 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ => planError "Aleo UInt64 literal carries trailing bytes"

/-- Canonical 1-byte Bool literal decode (0x00/0x01 only). -/
private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool := do
  unless bytes.size == 1 do
    planError "Aleo Bool literal must contain exactly 1 byte"
  let b := bytes.get! 0
  if b == 0 then pure false
  else if b == 1 then pure true
  else planError "Aleo Bool literal must be 0x00 or 0x01"

/-- Shift-count literals are 4-byte LE UInt32 on the wire; widen to UInt64 for
    the Plan expression surface (values are always < 2^32). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 4 do
    planError "Aleo UInt32 literal must contain exactly 4 bytes"
  match decodeU32le (start bytes) with
  | .error _ => planError "Aleo UInt32 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure (UInt64.ofNat value.toNat)
      | .error _ => planError "Aleo UInt32 literal carries trailing bytes"

private def lowerLiteral
    (data : SemanticProgramDataV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult Expr := do
  if isUInt64Type data typeId then
    match decodeUInt64LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error _ => planError "Aleo UInt64 literal is not canonical"
  else if isBoolType data typeId then
    match decodeBoolLiteralV1 valueBytes with
    | .ok flag => pure (.boolLiteral flag)
    | .error _ => planError "Aleo Bool literal is not canonical"
  else if isUInt32Type data typeId then
    match decodeUInt32LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error _ => planError "Aleo UInt32 literal is not canonical"
  else
    planError "Aleo literal type is outside the public UInt64/Bool/UInt32-count envelope"

private def lowerBinary
    (op : BinaryOpV1) (lhs rhs : Expr) : CompileResult Expr :=
  match op with
  | .add => pure (.checkedAdd lhs rhs)
  | .sub => pure (.checkedSub lhs rhs)
  | .mul => pure (.checkedMul lhs rhs)
  | .div => pure (.checkedDiv lhs rhs)
  | .mod => pure (.checkedMod lhs rhs)
  | .eq => pure (.compare .eq lhs rhs)
  | .ne => pure (.compare .ne lhs rhs)
  | .lt => pure (.compare .lt lhs rhs)
  | .le => pure (.compare .le lhs rhs)
  | .gt => pure (.compare .gt lhs rhs)
  | .ge => pure (.compare .ge lhs rhs)
  | .and => pure (.logicalAnd lhs rhs)
  | .or => pure (.logicalOr lhs rhs)
  | .bitAnd => pure (.bitAnd lhs rhs)
  | .bitOr => pure (.bitOr lhs rhs)
  | .bitXor => pure (.bitXor lhs rhs)
  | .shl => pure (.shl lhs rhs)
  | .shr => pure (.shr lhs rhs)

private def lowerUnary
    (op : UnaryOpV1) (operand : Expr) : CompileResult Expr :=
  match op with
  | .not => pure (.boolNot operand)
  | .bitNot => pure (.bitNot operand)
  | .neg => planError "Aleo does not support unary neg (Int/Field-only outside the envelope)"

private structure LoopCtxV1 where
  header : BlockIdV1
  deriving Inhabited

private structure LowerStateV1 where
  stmts : Array Statement
  deriving Inhabited

/-- Whether a block id is a loop header of this callable (any bound). -/
private def isLoopHeaderV1 (callable : CallableV1) (blockId : BlockIdV1) : Bool :=
  callable.loopBounds.any (fun lb => lb.header == blockId)

/-- Whether a block id is a loop header currently on the loop stack. -/
private def isActiveHeader (loops : Array LoopCtxV1) (blockId : BlockIdV1) : Bool :=
  loops.any (fun ctx => ctx.header == blockId)

private structure RegionResult where
  stmts : Array Statement
  join? : Option Nat
  deriving Inhabited

private def regionClosed : CompileResult RegionResult :=
  pure { stmts := #[], join? := none }

mutual

/-- Lower one callable body starting at `entry` (a non-loop block; loop
    headers are entered through `lowerLoop`). Blocks are forward-only except
    the loop back edges; joins are blocks reached by jumps from multiple open
    arms and are walked exactly once by the caller. -/
private partial def lowerRegion
    (data : SemanticProgramDataV1) (layout : AleoLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (entry : Nat) (loops : Array LoopCtxV1) (env : ValueEnv)
    (ls : LowerStateV1) : CompileResult RegionResult := do
  if entry >= callable.blocks.size then
    planError "Aleo lowering references a missing block"
  let block ← match callable.blocks[entry]? with
    | some b => pure b
    | none => planError "Aleo lowering references a missing block"
  unless block.params.isEmpty do
    planError "Aleo lowering: block parameters only appear on loop headers"
  let mut env := env
  let mut ls := ls
  for instr in block.instructions do
    match instr.op with
    | .literal typeId valueBytes => do
        let e ← lowerLiteral data typeId valueBytes
        match instr.result with
        | none => planError "Aleo literal instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .stateLoad stateId => do
        match instr.result with
        | none => planError "Aleo stateLoad instruction must produce a value"
        | some valueDef =>
            let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
              | some idxs => pure idxs
              | none => planError "Aleo stateLoad references unknown state id"
            if leafIdxs.size == 1 then
              let some fi := leafIdxs[0]? |
                planError "Aleo stateLoad leaf index missing"
              env := envInsert env valueDef.valueId (.stateLoad fi)
            else
              let mut leaves : Array Expr := #[]
              for fi in leafIdxs do
                leaves := leaves.push (.stateLoad fi)
              env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
    | .binary op lhs rhs => do
        let l ← match envLookupExpr env lhs with
          | some e => pure e
          | none => planError "Aleo binary references an undefined operand"
        let r ← match envLookupExpr env rhs with
          | some e => pure e
          | none => planError "Aleo binary references an undefined operand"
        let e ← lowerBinary op l r
        match instr.result with
        | none => planError "Aleo binary instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .unary op operand => do
        let o ← match envLookupExpr env operand with
          | some e => pure e
          | none => planError "Aleo unary references an undefined operand"
        let e ← lowerUnary op o
        match instr.result with
        | none => planError "Aleo unary instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .pureCall callableId args => do
        let fnName ← match fnNames.findSome? (fun (cid, n) =>
            if cid == callableId then some n else none) with
          | some n => pure n
          | none => planError "Aleo pureCall references an unknown callee"
        let mut argExprs : Array Expr := #[]
        for arg in args do
          match envLookup env arg with
          | some v =>
              if v.isAggregate then
                planError "Aleo pureCall does not accept aggregate arguments"
              argExprs := argExprs.push v.expr
          | none => planError "Aleo pureCall references an undefined argument"
        let e : Expr := .callFn fnName argExprs
        match instr.result with
        | none => planError "Aleo pureCall instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .stateStore stateId value => do
        let v ← match envLookup env value with
          | some lv => pure lv
          | none => planError "Aleo stateStore references an undefined value"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some idxs => pure idxs
          | none => planError "Aleo stateStore references unknown state id"
        let leaves := v.leafExprs
        unless leaves.size == leafIdxs.size do
          planError "Aleo stateStore leaf count mismatch"
        for i in [0:leafIdxs.size] do
          let some fi := leafIdxs[i]? |
            planError "Aleo stateStore leaf index missing"
          let some e := leaves[i]? |
            planError "Aleo stateStore leaf value missing"
          ls := { ls with stmts := ls.stmts.push (.store fi e) }
    | .assert_ condition _ args => do
        unless args.isEmpty do
          planError "Aleo assert-else is outside the envelope"
        let c ← match envLookupExpr env condition with
          | some e => pure e
          | none => planError "Aleo assert references an undefined condition"
        ls := { ls with stmts := ls.stmts.push (.assert c) }
    | .emit .. =>
        planError "Aleo does not support emit: Leo 4.0.2 has no on-chain event log"
    | .externalCall .. =>
        planError "Aleo does not support external calls"
    | .schedule .. =>
        planError "Aleo does not support scheduled workflows"
    -- N5: Op.Commit is label-only identity — reuse the operand's Plan value
    -- (no new Expr tag). Cryptographic commitment realization is deferred.
    | .commit valueId => do
        unless pilotContextPolicyCommitIdentity.admitCommitIdentity do
          planError "unsupported Aleo semantic shape: Commit is not admitted by pilot context policy"
        let operand ← match envLookup env valueId with
          | some v => pure v
          | none => planError "Aleo commit references an undefined operand"
        match instr.result with
        | none => planError "Aleo commit instruction must produce a value"
        | some valueDef =>
            env := envInsertVal env valueDef.valueId operand
    | .contextRead key => do
        unless key == unixTimeSecondsContextKeyV1 do
          planError s!"unsupported Aleo semantic shape: unknown ContextRead key '{key.value}'"
        planError
          "unsupported Aleo semantic shape: ContextRead is not admitted by pilot context policy"
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported Aleo semantic shape: construct instruction must produce a value"
        | some valueDef =>
            unless valueDef.typeId == typeId do
              planError "unsupported Aleo semantic shape: construct result typeId must match op typeId"
            if layout.types.isContainer typeId then
              let n ← match ← arrayUInt64LeafCountV1 layout.typeDecls layout.types typeId with
                | some n => pure n
                | none => planError "unsupported Aleo semantic shape: construct admits only fixed Array UInt64 on Aleo"
              unless ctorIdx == 0 do
                planError "unsupported Aleo semantic shape: Array construct ctorIdx must be 0"
              unless argIds.size == n do
                planError "unsupported Aleo semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              for argId in argIds do
                let arg ← match envLookup env argId with
                  | some v => pure v
                  | none => planError "unsupported Aleo semantic shape: construct references undefined arg"
                unless !arg.isAggregate do
                  planError "unsupported Aleo semantic shape: Array construct args must be scalar UInt64"
                leafExprs := leafExprs.push arg.expr
              env := envInsertVal env valueDef.valueId (mkAggregateVal leafExprs)
            else
              unless layout.types.isNamedAggregate typeId do
                planError "unsupported Aleo semantic shape: construct requires named Struct/Enum or Array"
              let some decl := layout.typeDecls[typeId.toNat]? |
                planError "unsupported Aleo semantic shape: construct TypeDecl missing"
              match decl.shape with
              | .struct fields => do
                  unless ctorIdx.toNat == 0 do
                    planError "unsupported Aleo semantic shape: struct construct ctorIdx must be 0"
                  unless argIds.size == fields.size do
                    planError "unsupported Aleo semantic shape: struct construct arity mismatch"
                  let mut leaves : Array Expr := #[]
                  for i in [0:argIds.size] do
                    let some argId := argIds[i]? |
                      planError "struct construct arg missing"
                    let some field := fields[i]? |
                      planError "struct construct field missing"
                    let arg ← match envLookup env argId with
                      | some v => pure v
                      | none => planError "struct construct undefined arg"
                    let expected ← leafCountOfTypeV1 layout.typeDecls layout.types field.typeId
                    let argLeaves := arg.leafExprs
                    unless argLeaves.size == expected do
                      planError "unsupported Aleo semantic shape: struct construct field leaf count mismatch"
                    leaves := leaves ++ argLeaves
                  env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
              | .enum variants => do
                  let vi := ctorIdx.toNat
                  let some variant := variants[vi]? |
                    planError "unsupported Aleo semantic shape: enum construct variant out of range"
                  unless argIds.size == variant.payloadTypes.size do
                    planError "unsupported Aleo semantic shape: enum construct arity mismatch"
                  let maxPay ← enumMaxPayloadLeavesV1 layout.typeDecls layout.types variants
                  let mut leaves : Array Expr := #[.literal (UInt64.ofNat vi)]
                  for i in [0:argIds.size] do
                    let some argId := argIds[i]? |
                      planError "enum construct arg missing"
                    let some pt := variant.payloadTypes[i]? |
                      planError "enum construct payload type missing"
                    let arg ← match envLookup env argId with
                      | some v => pure v
                      | none => planError "enum construct undefined arg"
                    let expected ← leafCountOfTypeV1 layout.typeDecls layout.types pt
                    let argLeaves := arg.leafExprs
                    unless argLeaves.size == expected do
                      planError "unsupported Aleo semantic shape: enum construct payload leaf count mismatch"
                    leaves := leaves ++ argLeaves
                  while leaves.size < 1 + maxPay do
                    leaves := leaves.push (.literal 0)
                  env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
              | _ =>
                  planError "unsupported Aleo semantic shape: construct requires Struct or Enum shape"
    | .fieldGet baseId fieldIndex => do
        match instr.result with
        | none => planError "unsupported Aleo semantic shape: fieldGet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "unsupported Aleo semantic shape: fieldGet base undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: fieldGet base must be a named aggregate"
            let baseLeaves := base.leafExprs
            let mut hit : Option (Nat × Nat) := none
            for tid in layout.types.namedTypeIds do
              match layout.typeDecls[tid.toNat]? with
              | some { shape := .struct fields, .. } => do
                  let total ← leafCountOfTypeV1 layout.typeDecls layout.types tid
                  if total == baseLeaves.size && fieldIndex.toNat < fields.size then
                    match fields[fieldIndex.toNat]? with
                    | some f =>
                        if f.typeId == valueDef.typeId then
                          let (s, l) ←
                            structFieldLeafRangeV1 layout.typeDecls layout.types fields
                              fieldIndex.toNat
                          hit := some (s, l)
                    | none => pure ()
              | _ => pure ()
            let (start, len) ← match hit with
              | some r => pure r
              | none =>
                  planError "unsupported Aleo semantic shape: fieldGet could not resolve struct field range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Aleo semantic shape: fieldGet leaf range out of bounds"
            let mut outLeaves : Array Expr := #[]
            for i in [start:start+len] do
              let some e := baseLeaves[i]? |
                planError "fieldGet leaf missing"
              outLeaves := outLeaves.push e
            if layout.types.isNamedAggregate valueDef.typeId then
              env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
            else
              let some e0 := outLeaves[0]? |
                planError "fieldGet scalar leaf missing"
              env := envInsert env valueDef.valueId e0
    | .fieldSet baseId fieldIndex valueId => do
        match instr.result with
        | none => planError "unsupported Aleo semantic shape: fieldSet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "fieldSet base undefined"
            let val ← match envLookup env valueId with
              | some v => pure v
              | none => planError "fieldSet value undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: fieldSet base must be a named aggregate"
            unless layout.types.isNamedAggregate valueDef.typeId do
              planError "unsupported Aleo semantic shape: fieldSet result must be named aggregate"
            let baseLeaves := base.leafExprs
            let valLeaves := val.leafExprs
            let mut hit : Option (Nat × Nat) := none
            for tid in layout.types.namedTypeIds do
              if tid == valueDef.typeId then
                match layout.typeDecls[tid.toNat]? with
                | some { shape := .struct fields, .. } => do
                    if fieldIndex.toNat < fields.size then
                      let (s, l) ←
                        structFieldLeafRangeV1 layout.typeDecls layout.types fields
                          fieldIndex.toNat
                      hit := some (s, l)
                | _ => pure ()
            let (start, len) ← match hit with
              | some r => pure r
              | none => planError "unsupported Aleo semantic shape: fieldSet could not resolve field range"
            unless valLeaves.size == len do
              planError "unsupported Aleo semantic shape: fieldSet value leaf count mismatch"
            unless start + len <= baseLeaves.size do
              planError "unsupported Aleo semantic shape: fieldSet leaf range out of bounds"
            let mut outLeaves : Array Expr := #[]
            for i in [0:baseLeaves.size] do
              if i >= start && i < start + len then
                let some e := valLeaves[i - start]? |
                  planError "fieldSet value leaf missing"
                outLeaves := outLeaves.push e
              else
                let some e := baseLeaves[i]? |
                  planError "fieldSet base leaf missing"
                outLeaves := outLeaves.push e
            env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
    | .variantTag baseId => do
        match instr.result with
        | none => planError "variantTag must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "variantTag base undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: variantTag base must be a named Enum aggregate"
            let some tag := base.leafExprs[0]? |
              planError "variantTag missing tag leaf"
            env := envInsert env valueDef.valueId tag
    | .variantPayload baseId variantIndex payloadIndex => do
        match instr.result with
        | none => planError "variantPayload must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "variantPayload base undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: variantPayload base must be a named Enum aggregate"
            let baseLeaves := base.leafExprs
            let mut hit : Option (Nat × Nat × Bool) := none
            for tid in layout.types.namedTypeIds do
              match layout.typeDecls[tid.toNat]? with
              | some { shape := .enum variants, .. } => do
                  let total ← leafCountOfTypeV1 layout.typeDecls layout.types tid
                  if total == baseLeaves.size && variantIndex.toNat < variants.size then
                    let (s, l) ←
                      enumPayloadLeafRangeV1 layout.typeDecls layout.types variants
                        variantIndex.toNat payloadIndex.toNat
                    -- payload region starts after tag (leaf 0)
                    hit := some (1 + s, l, layout.types.isNamedAggregate valueDef.typeId)
              | _ => pure ()
            let (start, len, asAgg) ← match hit with
              | some r => pure r
              | none => planError "unsupported Aleo semantic shape: variantPayload could not resolve range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Aleo semantic shape: variantPayload leaf range out of bounds"
            let mut outLeaves : Array Expr := #[]
            for i in [start:start+len] do
              let some e := baseLeaves[i]? |
                planError "variantPayload leaf missing"
              outLeaves := outLeaves.push e
            if asAgg then
              env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
            else
              let some e0 := outLeaves[0]? |
                planError "variantPayload scalar leaf missing"
              env := envInsert env valueDef.valueId e0
    | .indexGet baseId idxId => do
        match instr.result with
        | none => planError "indexGet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "indexGet base undefined"
            let idx ← match envLookup env idxId with
              | some v => pure v
              | none => planError "indexGet index undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: IndexGet base must be an Array UInt64 aggregate"
            let i ← literalIndexNatV1 idx
            let leaves := base.leafExprs
            unless i < leaves.size do
              planError "unsupported Aleo semantic shape: Array IndexGet index out of range"
            let some leaf := leaves[i]? |
              planError "Array IndexGet leaf missing"
            env := envInsert env valueDef.valueId leaf
    | .indexSet baseId idxId valueId => do
        match instr.result with
        | none => planError "indexSet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "indexSet base undefined"
            let idx ← match envLookup env idxId with
              | some v => pure v
              | none => planError "indexSet index undefined"
            let val ← match envLookup env valueId with
              | some v => pure v
              | none => planError "indexSet value undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: IndexSet base must be an Array UInt64 aggregate"
            unless !val.isAggregate do
              planError "unsupported Aleo semantic shape: Array IndexSet value must be scalar UInt64"
            let i ← literalIndexNatV1 idx
            let leaves := base.leafExprs
            unless i < leaves.size do
              planError "unsupported Aleo semantic shape: Array IndexSet index out of range"
            let mut outLeaves : Array Expr := #[]
            for j in [0:leaves.size] do
              if j == i then
                outLeaves := outLeaves.push val.expr
              else
                let some e := leaves[j]? |
                  planError "Array IndexSet leaf missing"
                outLeaves := outLeaves.push e
            env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
    | .constant .. =>
        planError "unsupported Aleo semantic shape: Constant load is outside the public UInt64 envelope"
    | .checkedCast .. =>
        planError "unsupported Aleo semantic shape: CheckedCast is outside the public UInt64 envelope"
  -- Terminator
  match block.terminator with
  | .jump target =>
      if isActiveHeader loops target.blockId then
        -- Back edge: the enclosing loop's latch. The latch's own statements
        -- are the induction increment, re-derived by the loop encoding.
        pure { stmts := ls.stmts, join? := none }
      else if isLoopHeaderV1 callable target.blockId then
        lowerLoop data layout callable fnNames target ls env loops
      else
        lowerRegion data layout callable fnNames target.blockId.toNat loops env ls
  | .branch condition thenTarget elseTarget => do
      let c ← match envLookupExpr env condition with
        | some e => pure e
        | none => planError "Aleo branch references an undefined condition"
      let thenRes ← lowerRegion data layout callable fnNames thenTarget.blockId.toNat loops env ls
      let elseRes ← lowerRegion data layout callable fnNames elseTarget.blockId.toNat loops env ls
      let join? ← match thenRes.join?, elseRes.join? with
        | none, none => pure none
        | some j, none => pure (some j)
        | none, some j => pure (some j)
        | some j1, some j2 =>
            if j1 == j2 then pure (some j1)
            else planError "Aleo lowering: branch arms join at different blocks"
      let stmts := ls.stmts.push (.ifThenElse c thenRes.stmts elseRes.stmts)
      pure { stmts, join? }
  | .switch scrutinee cases defaultTarget => do
      let s ← match envLookupExpr env scrutinee with
        | some e => pure e
        | none => planError "Aleo switch references an undefined scrutinee"
      let mut caseStmts : Array (UInt64 × Array Statement) := #[]
      let mut joins : Array Nat := #[]
      for case in cases do
        let value ← match decodeUInt64LiteralV1 case.valueBytes with
          | .ok v => pure v
          | .error _ => planError "Aleo switch case value is not a canonical UInt64"
        let targetRes ← lowerRegion data layout callable fnNames case.target.blockId.toNat loops env ls
        caseStmts := caseStmts.push (value, targetRes.stmts)
        match targetRes.join? with
        | some j => joins := joins.push j
        | none => pure ()
      let defaultRes ← match defaultTarget with
        | none => regionClosed
        | some t => lowerRegion data layout callable fnNames t.blockId.toNat loops env ls
      match defaultRes.join? with
      | some j => joins := joins.push j
      | none => pure ()
      let join? ← match joins.toList with
        | [] => pure none
        | j :: rest =>
            if rest.all (· == j) then pure (some j)
            else planError "Aleo lowering: switch arms join at different blocks"
      let stmts := ls.stmts.push (.switchOn s caseStmts defaultRes.stmts)
      pure { stmts, join? }
  | .return_ value => do
      let stmts ← match value with
        | none => pure (ls.stmts.push .returnNone)
        | some vid =>
            match envLookup env vid with
            | some v =>
                if v.isAggregate then
                  planError "Aleo return of aggregate is outside the scalar result envelope"
                pure (ls.stmts.push (.returnValue v.expr))
            | none => planError "Aleo return references an undefined value"
      pure { stmts, join? := none }
  | .revert errorId args => do
      unless args.isEmpty do
        planError "Aleo does not support revert payloads: Leo 4.0.2 cannot represent error arguments"
      let stmts := ls.stmts.push (.revertError errorId.toNat #[])
      pure { stmts, join? := none }
  | .trap _ => do
      let stmts := ls.stmts.push (.assert (.boolLiteral false))
      pure { stmts, join? := none }

/-- Lower a bounded loop entered by `target` (a loop header): construct the
    `forLoop` statement from the header's `i < end` condition, the body region
    (terminated by the latch back edge), and the exit continuation. -/
private partial def lowerLoop
    (data : SemanticProgramDataV1) (layout : AleoLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (target : JumpTargetV1) (ls : LowerStateV1) (env : ValueEnv)
    (loops : Array LoopCtxV1) : CompileResult RegionResult := do
  let headerIdx := target.blockId.toNat
  let lb ← match callable.loopBounds.findSome? (fun lb =>
      if lb.header == target.blockId then some lb else none) with
    | some lb => pure lb
    | none => planError "Aleo lowering: loop bound missing for header"
  if loops.any (fun ctx => ctx.header == target.blockId) then
    planError "Aleo lowering: re-entered an active loop header"
  let header ← match callable.blocks[headerIdx]? with
    | some b => pure b
    | none => planError "Aleo lowering: loop header block is missing"
  unless header.params.size == 1 do
    planError "Aleo lowering: loop header must carry exactly one block parameter"
  let some paramDef := header.params[0]? |
    planError "Aleo lowering: loop header parameter is missing"
  unless target.args.size == 1 do
    planError "Aleo lowering: loop entry must carry exactly one argument"
  let startVid ← match target.args[0]? with
    | some v => pure v
    | none => planError "Aleo lowering: loop start value is missing"
  let startExpr ← match envLookupExpr env startVid with
    | some e => pure e
    | none => planError "Aleo lowering: loop start value is not defined"
  -- The header must be exactly `cond := i < end` + branch; the end value is
  -- loop-invariant (already in env). The branch condition must be the cond
  -- instruction's result.
  let mut condVid? : Option ValueIdV1 := none
  let mut endExpr? : Option Expr := none
  for instr in header.instructions do
    match instr.op with
    | .binary .lt lhs rhs => do
        unless lhs == paramDef.valueId do
          planError "Aleo lowering: loop condition lhs must be the induction parameter"
        let r ← match envLookupExpr env rhs with
          | some e => pure e
          | none => planError "Aleo lowering: loop end value is not defined"
        match instr.result with
        | some valueDef => condVid? := some valueDef.valueId
        | none => planError "Aleo lowering: loop condition must produce a value"
        endExpr? := some r
    | _ =>
        planError "Aleo lowering: loop header carries an unexpected instruction"
  let endExpr ← match endExpr? with
    | some e => pure e
    | none => planError "Aleo lowering: loop header must compute `i < end`"
  let depth := loops.size
  let envLoop := envInsert env paramDef.valueId (.loopVar depth)
  let loops' := loops.push { header := target.blockId }
  match header.terminator with
  | .branch condVid thenTarget _ => do
      match condVid? with
      | some expected =>
          unless condVid == expected do
            planError "Aleo lowering: loop branch condition does not match the header computation"
      | none => planError "Aleo lowering: loop header branch condition is missing"
      let thenRes ← lowerRegion data layout callable fnNames thenTarget.blockId.toNat loops' envLoop ls
      unless thenRes.join?.isNone do
        planError "Aleo lowering: loop body must end at the latch back edge"
      let body := thenRes.stmts
      let maxIter := lb.maxIterations.toNat
      unless maxIter ≤ 4096 do
        planError "Aleo lowering: loop bound exceeds the wire maximum"
      let forStmt := .forLoop startExpr endExpr maxIter body
      match header.terminator with
      | .branch _ _ elseTarget =>
          lowerRegion data layout callable fnNames elseTarget.blockId.toNat loops env
            { ls with stmts := ls.stmts.push forStmt }
      | _ => planError "Aleo lowering: loop header must end in a branch"
  | _ => planError "Aleo lowering: loop header must end in a branch"

end
/-- Resolve a callable result to (isBool, isUnit). -/
private def resultShape (data : SemanticProgramDataV1) (callable : CallableV1) :
    CompileResult (Bool × Bool) := do
  if isBoolType data callable.result.typeId then pure (true, false)
  else if isUInt64Type data callable.result.typeId then pure (false, false)
  else if (match data.types[callable.result.typeId.toNat]? with
      | some { shape := .unit, .. } => true | _ => false) then pure (false, true)
  else planError "Aleo callable result is outside the public UInt64/Bool/Unit envelope"

private partial def touchesStateExpr : Expr → Bool
  | .stateLoad _ => true
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .logicalAnd l r | .logicalOr l r | .shl l r | .shr l r =>
      touchesStateExpr l || touchesStateExpr r
  | .compare _ l r => touchesStateExpr l || touchesStateExpr r
  | .bitNot o | .boolNot o => touchesStateExpr o
  | .callFn _ args => args.any touchesStateExpr
  | _ => false

/-- Does a statement list read or write mappings? -/
private partial def touchesStateStmts (stmts : Array Statement) : Bool :=
  stmts.any fun stmt =>
    match stmt with
    | .store _ _ => true
    | .returnValue e => touchesStateExpr e
    | .ifThenElse _ t e => touchesStateStmts t || touchesStateStmts e
    | .switchOn _ cases d => cases.any (fun (_, b) => touchesStateStmts b) || touchesStateStmts d
    | .forLoop _ _ _ b => touchesStateStmts b
    | _ => false

inductive CallableLowering where
  | asFunction (fn : PlanFunction)
  | asView (view : PlanView)
  deriving Inhabited

/-- Lower one callable into a plan function or a bare view descriptor. -/
private partial def lowerCallable
    (data : SemanticProgramDataV1) (layout : AleoLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String)) :
    CompileResult CallableLowering := do

  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty do
    planError "Aleo lowering: callable must have entry block 0"
  -- Pre-validate the loop pattern (single-param headers, branch + latch).
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      planError "Aleo lowering: loop header block is missing"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      planError "Aleo lowering: loop latch block is missing"
    unless header.params.size == 1 do
      planError "Aleo lowering: loop header must carry one UInt64 parameter"
    match header.terminator with
    | .branch .. => pure ()
    | _ => planError "Aleo lowering: loop header must end in a branch"

    match latch.terminator with
    | .jump t =>
        unless t.blockId == lb.header && t.args.size == 1 do
          planError "Aleo lowering: loop latch must jump back with one argument"
    | _ => planError "Aleo lowering: loop latch must jump back to the header"
  for blk in callable.blocks do
    unless blk.params.isEmpty ||
        callable.loopBounds.any (fun lb => lb.header == blk.id) do
      planError "Aleo lowering: block parameters are only supported on loop headers"
  -- Params.
  let mut params : Array PlanParam := #[]
  let mut paramIndex : Nat := 0
  for p in callable.params do
    let isBool ← if isBoolType data p.typeId then pure true
      else if isUInt64Type data p.typeId then pure false
      else planError "Aleo callable parameter is outside the UInt64/Bool envelope"
    params := params.push { sourceIndex := paramIndex, name := p.name, isBool }
    paramIndex := paramIndex + 1
  -- Seed the value env with callable params (source-indexed), then walk the
  -- body from the entry block.
  let mut env0 : ValueEnv := default
  let mut paramOrdinal : Nat := 0
  for p in callable.params do
    env0 := envInsert env0 p.valueId (.param paramOrdinal)
    paramOrdinal := paramOrdinal + 1
  let res ← lowerRegion data layout callable fnNames 0 #[] env0 { stmts := #[] }
  unless res.join?.isNone do
    planError "Aleo lowering: callable does not end in return on all paths"
  let body := res.stmts
  let (resultIsBool, resultIsUnit) ← resultShape data callable
  -- Bare view: body is exactly `return <stateLoad f>`.
  let bareView? : Option PlanView :=
    match callable.kind, body.toList with
    | .view, [.returnValue (.stateLoad f)] =>
        match callable.name with
        | some n => some { name := n, stateFieldIndex := f }
        | none => none
    | _, _ => none
  match bareView? with
  | some view => return (.asView view)
  | none => pure ()
  -- Ordinary function.
  let kind := match callable.kind with
    | .initializer => FunctionKind.initialize
    | _ => FunctionKind.mutate
  let touchesState := touchesStateStmts body
  -- Computed state-reading views fail closed (only bare reads map to the
  -- off-chain query model).
  if callable.kind == .view && touchesState then
    planError "Aleo computed views that read state fail closed: only bare public-state reads map to leo query"
  let resultDropped := !resultIsUnit && touchesState
  let name ← match callable.name with
    | some n => pure n
    | none => pure "initialize"
  pure (.asFunction {
    index := 0
    name
    kind
    params
    body
    touchesState
    resultIsBool
    resultDropped
  })

/-- Assembly entry: wire semantic data → target-owned Plan. -/
private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  -- Type-closure: Field fail closed; named + Array admitted (H3).
  let types ← validateAleoTypeClosureV1 data.types
  let layout ← makeStateLayoutV1 types data.types data.logicalState
  let fnNames := data.callables.filterMap fun c =>
    match c.kind with
    | .pureFn => some (c.id, c.name.getD "fn")
    | _ => none
  let mut functions : Array PlanFunction := #[]
  let mut views : Array PlanView := #[]
  for callable in data.callables do
    match callable.kind with
    | .invariant =>
        planError "Aleo does not support invariants in this slice"
    | .initializer | .entry | .view | .pureFn =>
        match ← lowerCallable data layout callable fnNames with
        | .asFunction fn =>
            functions := functions.push { fn with index := functions.size }
        | .asView view =>
            views := views.push view
  let plan := {
    programName
    stateFieldNames := layout.fieldNames
    functions
    views
    sourceHash
    semanticHash
  }
  pure plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) (artifactProgramName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Aleo received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash


private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"


/-- Internal Aleo family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .aleo do
    throw <| .planInvariant .aleo "engineering capability kind is not Aleo"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Aleo source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Aleo semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Aleo
