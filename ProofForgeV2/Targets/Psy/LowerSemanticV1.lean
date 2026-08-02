import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Psy LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the Psy-owned Plan surface and the retained-`SemanticProgramV1` Plan body
for the public UInt64 envelope (comparisons, bare assert, Bool results,
if/match, revert/emit, fn/localCall, let, bounded for, shift/bitwise/logical,
call/schedule). Plan canonicity lives in `ValidatePlanV1`; `.psy` emission in
`EmitIRV1`. `FinalizeV1` remains a separate submodule.

Psy maps UInt64/UInt32 → `Felt`, Bool → `bool`. Checked u64 arithmetic is
enforced by explicit assert guards at emission (Felt is a field element; the
old Psy backend had no checked arith — V2 requires it). Bitwise `&`/`|`/`^`
and shifts lower to native Psy Felt operators (golden BitwiseProbe); unary
`~` (bitNot) fails closed because the Psy surface has no bitwise-not unary.

**Field (bn254 Fr) is fail-closed.** Native Psy `Felt` is plonky2 Goldilocks
(`ORDER = 0xFFFFFFFF00000001`), not catalog bn254 Fr — see
`EnvelopeV1.psyTypeClosureWording` research pin. Type-closure uses
`pilotFieldPolicyNone`.

## H3 PsyAleoAggregate (2026-08-02)

Named Struct/Enum and fixed-length `Array UInt64 N` are **LOWERED** by
flattening to consecutive Felt storage leaves (`name_field` / `name_i`).
Plan Expr remains scalar-only: construct/fieldGet/fieldSet/variantTag/
variantPayload/indexGet/indexSet operate in the lowering value env only.
Map/Bytes/Option/String/Principal stay fail-closed. Array IndexGet/IndexSet
require a compile-time UInt literal index (no dynamic select surface on Psy).
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Engineering codegen profile string for the Dargo/Psy UInt64 source slice.
    `CodegenProfileId` has no psy variant yet — P-B wires the opaque id into
    the registry; this string is the intended spelling. -/
def psyCodegenProfileIdString : String := "psy-dargo-u64-v1"

/-- Locked Dargo/Psy toolchain note (source-only; no approved digest-pinned
    `dargo` binary is configured). -/
def psyToolchain : String := "dargo-mainnet-beta"

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

/-- Target-owned Psy Plan expression over the shipped public UInt64/Bool
    envelope. UInt32 shift counts are promoted to UInt64 values with an
    explicit `count < 64` guard at emission. -/
inductive Expr where
  | literal (value : UInt64)
  | boolLiteral (value : Bool)
  | param (inputIndex : Nat)
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
  | logicalAnd (lhs rhs : Expr)
  | logicalOr (lhs rhs : Expr)
  | shl (lhs rhs : Expr)
  | shr (lhs rhs : Expr)
  | boolNot (operand : Expr)
  /-- Checked Int64 negation (intMin reverts at emission). -/
  | checkedNeg (operand : Expr)
  /-- Signed Int64 comparison (Felt signed interpretation at emission). -/
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
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
  | forLoop (start endExclusive : Expr) (maxIterations : Nat)
      (body : Array Statement)
  | emitEvent (eventIndex : Nat) (args : Array Expr)
  | revertError (errorIndex : Nat) (args : Array Expr)
  | bareRevert
  | externalCall (callee : Array String) (args : Array Expr)
  | schedule (callee : Array String) (args : Array Expr)
  deriving BEq, Inhabited, Repr

inductive FunctionKind where
  | initialize
  | mutate
  | pureHelper
  deriving BEq, Inhabited, Repr

structure PlanParam where
  sourceIndex : Nat
  name : String
  isBool : Bool
  deriving BEq, Inhabited, Repr

structure PlanFunction where
  index : Nat
  name : String
  kind : FunctionKind
  params : Array PlanParam
  body : Array Statement
  resultIsBool : Bool
  resultIsUnit : Bool
  deriving BEq, Inhabited, Repr

structure PlanEvent where
  name : String
  fieldNames : Array String
  deriving BEq, Inhabited, Repr

structure PlanErrorDecl where
  name : String
  fieldNames : Array String
  deriving BEq, Inhabited, Repr

/-- Target-owned Psy Plan. Retains no SemanticProgram; carries digests and
    artifact program name. -/
structure Plan where
  programName : String
  stateFieldNames : Array String
  functions : Array PlanFunction
  events : Array PlanEvent
  errors : Array PlanErrorDecl
  sourceHash : String
  semanticHash : String
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

/-- Psy pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Field stays on `pilotFieldPolicyNone`: Felt is Goldilocks, not bn254 Fr. -/
private abbrev PsyTypeClosureV1 := PilotTypeClosureV1

private def psyPlanErr (message : String) : CompileError :=
  .planInvariant .psy message

/-- Psy pilot accepts anonymous UInt64/UInt32/Unit/Bool/Int64 under the default
    UInt64+UInt32 + Int64 policies, plus **named Struct/Enum** and **Array**
    (H3 PsyAleoAggregate: flatten-to-Felt leaves). Field stays
    `pilotFieldPolicyNone` (Goldilocks ≠ bn254). Map/Bytes/Option/Principal
    fail closed. -/
private def validatePsyTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult PsyTypeClosureV1 :=
  validatePilotTypeClosure psyPlanErr psyTypeClosureWording types
    pilotUintWidthPolicyU64U32
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayOnly)

-- ---------------------------------------------------------------------------
-- Wire semantic → target-owned Plan lowering
-- ---------------------------------------------------------------------------

private def maxIdentifierBytes : Nat := 240
private def maxStateLeafFields : Nat := 256

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

/-- Scalar + optional multi-leaf aggregate carrier (H3). SSA ValueIds are
    defined once; `leaves? = some` means fixed-width flattened Struct/Enum/Array. -/
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

/-- Flattening layout: physical Felt leaf names + per-logical-state leaf ranges. -/
private structure PsyLowerLayoutV1 where
  fieldNames : Array String
  stateLeaves : Array (Array Nat)
  typeDecls : Array TypeDeclV1
  types : PsyTypeClosureV1

private def isUInt64Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 64, .. } => true
  | _ => false

private def isInt64Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .int 64, .. } => true
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

/-- Named Struct/Enum flatten to UInt64/Int64 leaves (preorder). Array UInt64 N
    flattens to N UInt64 leaves. Nested containers / Map / Bytes fail closed. -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array String) := do
  if typeId == types.uint64TypeId then
    pure #[namePrefix]
  else if types.int64TypeId == some typeId then
    pure #[namePrefix]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        planError s!"unsupported Psy semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              planError "unsupported Psy semantic shape: named Struct requires at least one field"
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
              planError "unsupported Psy semantic shape: named Enum requires at least one variant"
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
            planError "unsupported Psy semantic shape: named type must be Struct or Enum"
  else if types.isContainer typeId then
    match typeDecls[typeId.toNat]? with
    | some { shape := .array elTid len, .. } =>
        unless elTid == types.uint64TypeId do
          planError "unsupported Psy semantic shape: Array state element must be UInt64"
        let n := len.toNat
        unless n ≥ 1 do
          planError "unsupported Psy semantic shape: Array state length must be ≥ 1"
        let mut out : Array String := #[]
        for i in [0:n] do
          let leafName := namePrefix ++ "_" ++ toString i
          unless isIdentifier leafName do
            planError s!"state name '{leafName}' is not a safe identifier"
          out := out.push leafName
        pure out
    | some { shape := .map .., .. } =>
        planError "unsupported Psy semantic shape: Map state is outside the Psy Array-only container pilot"
    | some { shape := .bytes _, .. } =>
        planError "unsupported Psy semantic shape: Bytes state is outside the Psy Array-only container pilot"
    | _ =>
        planError "unsupported Psy semantic shape: container TypeId is not Array/Map/Bytes"
  else
    planError "unsupported Psy semantic shape: aggregate leaf must be UInt64, Int64, named Struct/Enum, or Array UInt64"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
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
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
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
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
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
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless elTid == types.uint64TypeId do
        planError "unsupported Psy semantic shape: Array state element must be UInt64"
      let n := len.toNat
      unless n ≥ 1 do
        planError "unsupported Psy semantic shape: Array state length must be ≥ 1"
      pure (some n)
  | some { shape := .map .., .. } =>
      planError "unsupported Psy semantic shape: Map state is outside the Psy Array-only container pilot"
  | some { shape := .bytes _, .. } =>
      planError "unsupported Psy semantic shape: Bytes state is outside the Psy Array-only container pilot"
  | _ =>
      planError "unsupported Psy semantic shape: container TypeId is not Array/Map/Bytes"

private def makeStateLayoutV1
    (types : PsyTypeClosureV1) (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult PsyLowerLayoutV1 := do
  let mut fieldNames : Array String := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      planError "unsupported Psy semantic shape: semantic state ids must match declaration order"
    unless isIdentifier state.name do
      planError s!"state name '{state.name}' is not a safe identifier"
    if types.isNamedAggregate state.typeId || types.isContainer state.typeId then
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
      if fieldNames.size + leafSpecs.size > maxStateLeafFields then
        planError "unsupported Psy semantic shape: state leaf count exceeds Psy profile limit"
      let mut leaves : Array Nat := #[]
      for name in leafSpecs do
        leaves := leaves.push fieldNames.size
        fieldNames := fieldNames.push name
      stateLeaves := stateLeaves.push leaves
    else if state.typeId == types.uint64TypeId || types.int64TypeId == some state.typeId then
      let leafIdx := fieldNames.size
      fieldNames := fieldNames.push state.name
      stateLeaves := stateLeaves.push #[leafIdx]
    else
      planError "unsupported Psy semantic shape: state must be UInt64, Int64, named Struct/Enum, or Array UInt64 (Map/Bytes/Option/Principal declined)"
  pure { fieldNames, stateLeaves, typeDecls, types }

private def literalIndexNatV1 (v : LoweredVal) : CompileResult Nat := do
  unless !v.isAggregate do
    planError "unsupported Psy semantic shape: Array index must be a scalar UInt literal"
  match v.expr with
  | .literal n => pure n.toNat
  | _ =>
      planError "unsupported Psy semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    planError "unsupported Psy semantic shape: UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ => planError "unsupported Psy semantic shape: UInt64 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ => planError "unsupported Psy semantic shape: UInt64 literal carries trailing bytes"

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool := do
  unless bytes.size == 1 do
    planError "unsupported Psy semantic shape: Bool literal must contain exactly 1 byte"
  let b := bytes.get! 0
  if b == 0 then pure false
  else if b == 1 then pure true
  else planError "unsupported Psy semantic shape: Bool literal must be 0x00 or 0x01"

private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 4 do
    planError "unsupported Psy semantic shape: UInt32 literal must contain exactly 4 bytes"
  match decodeU32le (start bytes) with
  | .error _ => planError "unsupported Psy semantic shape: UInt32 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure (UInt64.ofNat value.toNat)
      | .error _ => planError "unsupported Psy semantic shape: UInt32 literal carries trailing bytes"

private def lowerLiteral
    (data : SemanticProgramDataV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult Expr := do
  if isUInt64Type data typeId then
    match decodeUInt64LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error e => .error e
  else if isInt64Type data typeId then
    unless valueBytes.size == 8 do
      planError "unsupported Psy semantic shape: Int64 literal must contain exactly 8 bytes"
    match decodeU64le (start valueBytes) with
    | .error _ => planError "unsupported Psy semantic shape: Int64 literal is not canonical"
    | .ok (value, cursor) =>
        match finish cursor with
        | .ok () => pure (.literal value)
        | .error _ =>
            planError "unsupported Psy semantic shape: Int64 literal carries trailing bytes"
  else if isBoolType data typeId then
    match decodeBoolLiteralV1 valueBytes with
    | .ok flag => pure (.boolLiteral flag)
    | .error e => .error e
  else if isUInt32Type data typeId then
    match decodeUInt32LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error e => .error e
  else
    planError "unsupported Psy semantic shape: literal type is outside the public UInt64/Int64/Bool/UInt32 envelope"

private def lowerBinary
    (op : BinaryOpV1) (lhs rhs : Expr) (signed : Bool) : CompileResult Expr :=
  match op with
  | .add => pure (.checkedAdd lhs rhs)
  | .sub => pure (.checkedSub lhs rhs)
  | .mul => pure (.checkedMul lhs rhs)
  | .div => pure (.checkedDiv lhs rhs)
  | .mod => pure (.checkedMod lhs rhs)
  | .eq => pure (if signed then .signedCompare .eq lhs rhs else .compare .eq lhs rhs)
  | .ne => pure (if signed then .signedCompare .ne lhs rhs else .compare .ne lhs rhs)
  | .lt => pure (if signed then .signedCompare .lt lhs rhs else .compare .lt lhs rhs)
  | .le => pure (if signed then .signedCompare .le lhs rhs else .compare .le lhs rhs)
  | .gt => pure (if signed then .signedCompare .gt lhs rhs else .compare .gt lhs rhs)
  | .ge => pure (if signed then .signedCompare .ge lhs rhs else .compare .ge lhs rhs)
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
  | .bitNot =>
      planError "unsupported Psy semantic shape: unary bitNot (~) has no Psy surface form on Felt (no bitwise-not unary)"
  | .neg => pure (.checkedNeg operand)

private structure LoopCtxV1 where
  header : BlockIdV1
  deriving Inhabited

private structure LowerStateV1 where
  stmts : Array Statement
  deriving Inhabited

private def isLoopHeaderV1 (callable : CallableV1) (blockId : BlockIdV1) : Bool :=
  callable.loopBounds.any (fun lb => lb.header == blockId)

private def isActiveHeader (loops : Array LoopCtxV1) (blockId : BlockIdV1) : Bool :=
  loops.any (fun ctx => ctx.header == blockId)

private structure RegionResult where
  stmts : Array Statement
  join? : Option Nat
  deriving Inhabited

private def regionClosed : CompileResult RegionResult :=
  pure { stmts := #[], join? := none }

private def lookupArgs
    (env : ValueEnv) (args : Array ValueIdV1) (what : String) :
    CompileResult (Array Expr) := do
  let mut out : Array Expr := #[]
  for arg in args do
    match envLookup env arg with
    | some v =>
        if v.isAggregate then
          planError s!"unsupported Psy semantic shape: {what} does not accept aggregate arguments"
        out := out.push v.expr
    | none => planError s!"unsupported Psy semantic shape: {what} references an undefined argument"
  pure out

mutual

private partial def lowerRegion
    (data : SemanticProgramDataV1) (layout : PsyLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (entry : Nat) (loops : Array LoopCtxV1) (env : ValueEnv)
    (ls : LowerStateV1) : CompileResult RegionResult := do
  if entry >= callable.blocks.size then
    planError "unsupported Psy semantic shape: lowering references a missing block"
  let block ← match callable.blocks[entry]? with
    | some b => pure b
    | none => planError "unsupported Psy semantic shape: lowering references a missing block"
  unless block.params.isEmpty do
    planError "unsupported Psy semantic shape: block parameters only appear on loop headers"
  let mut env := env
  let mut ls := ls
  for instr in block.instructions do
    match instr.op with
    | .literal typeId valueBytes => do
        let e ← lowerLiteral data typeId valueBytes
        match instr.result with
        | none => planError "unsupported Psy semantic shape: literal instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .stateLoad stateId => do
        match instr.result with
        | none => planError "unsupported Psy semantic shape: stateLoad instruction must produce a value"
        | some valueDef =>
            let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
              | some idxs => pure idxs
              | none => planError "unsupported Psy semantic shape: stateLoad references unknown state id"
            if leafIdxs.size == 1 then
              let some fi := leafIdxs[0]? |
                planError "unsupported Psy semantic shape: stateLoad leaf index missing"
              env := envInsert env valueDef.valueId (.stateLoad fi)
            else
              let mut leaves : Array Expr := #[]
              for fi in leafIdxs do
                leaves := leaves.push (.stateLoad fi)
              env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
    | .binary op lhs rhs => do
        let l ← match envLookupExpr env lhs with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: binary references an undefined operand"
        let r ← match envLookupExpr env rhs with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: binary references an undefined operand"
        -- Signed Int64 comparisons use bias-corrected signedCompare; UInt64 uses
        -- unsigned compare. Operand types come from result TypeId of the
        -- comparison (Bool) is not helpful — inspect lhs type via state/params
        -- by scanning value defs is heavy; use instruction operand type from
        -- the semantic program's value table is not free. Heuristic: if either
        -- operand is a stateLoad of an Int64 state, treat as signed; otherwise
        -- signed when any logicalState row is Int64 and both operands are not
        -- clearly Bool. Prefer exact: look up lhs's defining instruction type.
        let signed :=
          match instr.result with
          | some _ =>
              -- Use lhs type when available via stateLoad field index types.
              match l with
              | .stateLoad idx =>
                  match data.logicalState[idx]? with
                  | some st => isInt64Type data st.typeId
                  | none => false
              | .param pidx =>
                  match callable.params[pidx]? with
                  | some p => isInt64Type data p.typeId
                  | none => false
              | _ =>
                  -- Int64 literals and intermediate results: if any Int64 type is
                  -- interned and this is a comparison, prefer signed when the
                  -- program has Int64 state/params (product Int64 Counter path).
                  data.logicalState.any (fun st => isInt64Type data st.typeId) ||
                    callable.params.any (fun p => isInt64Type data p.typeId)
          | none => false
        let e ← lowerBinary op l r signed
        match instr.result with
        | none => planError "unsupported Psy semantic shape: binary instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .unary op operand => do
        let o ← match envLookupExpr env operand with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: unary references an undefined operand"
        let e ← lowerUnary op o
        match instr.result with
        | none => planError "unsupported Psy semantic shape: unary instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .pureCall callableId args => do
        let fnName ← match fnNames.findSome? (fun (cid, n) =>
            if cid == callableId then some n else none) with
          | some n => pure n
          | none => planError "unsupported Psy semantic shape: pureCall references an unknown callee"
        let argExprs ← lookupArgs env args "pureCall"
        let e : Expr := .callFn fnName argExprs
        match instr.result with
        | none => planError "unsupported Psy semantic shape: pureCall instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .stateStore stateId value => do
        let v ← match envLookup env value with
          | some lv => pure lv
          | none => planError "unsupported Psy semantic shape: stateStore references an undefined value"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some idxs => pure idxs
          | none => planError "unsupported Psy semantic shape: stateStore references unknown state id"
        let leaves := v.leafExprs
        unless leaves.size == leafIdxs.size do
          planError "unsupported Psy semantic shape: stateStore leaf count mismatch"
        for i in [0:leafIdxs.size] do
          let some fi := leafIdxs[i]? |
            planError "unsupported Psy semantic shape: stateStore leaf index missing"
          let some e := leaves[i]? |
            planError "unsupported Psy semantic shape: stateStore leaf value missing"
          ls := { ls with stmts := ls.stmts.push (.store fi e) }
    | .assert_ condition _ args => do
        unless args.isEmpty do
          planError "unsupported Psy semantic shape: assert-else is outside the envelope"
        let c ← match envLookupExpr env condition with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: assert references an undefined condition"
        ls := { ls with stmts := ls.stmts.push (.assert c) }
    | .emit _effectId eventId args => do
        let argExprs ← lookupArgs env args "emit"
        ls := { ls with stmts := ls.stmts.push (.emitEvent eventId.toNat argExprs) }
    | .externalCall _effectId callee args => do
        let comps := callee.components.toArray
        unless comps.size ≥ 2 do
          planError "unsupported Psy semantic shape: external callee must have at least two components"
        let argExprs ← lookupArgs env args "externalCall"
        ls := { ls with stmts := ls.stmts.push (.externalCall comps argExprs) }
    | .schedule _effectId callee args => do
        let comps := callee.components.toArray
        unless comps.size ≥ 2 do
          planError "unsupported Psy semantic shape: schedule callee must have at least two components"
        let argExprs ← lookupArgs env args "schedule"
        ls := { ls with stmts := ls.stmts.push (.schedule comps argExprs) }
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported Psy semantic shape: construct instruction must produce a value"
        | some valueDef =>
            unless valueDef.typeId == typeId do
              planError "unsupported Psy semantic shape: construct result typeId must match op typeId"
            if layout.types.isContainer typeId then
              let n ← match ← arrayUInt64LeafCountV1 layout.typeDecls layout.types typeId with
                | some n => pure n
                | none => planError "unsupported Psy semantic shape: construct admits only fixed Array UInt64 on Psy"
              unless ctorIdx == 0 do
                planError "unsupported Psy semantic shape: Array construct ctorIdx must be 0"
              unless argIds.size == n do
                planError "unsupported Psy semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              for argId in argIds do
                let arg ← match envLookup env argId with
                  | some v => pure v
                  | none => planError "unsupported Psy semantic shape: construct references undefined arg"
                unless !arg.isAggregate do
                  planError "unsupported Psy semantic shape: Array construct args must be scalar UInt64"
                leafExprs := leafExprs.push arg.expr
              env := envInsertVal env valueDef.valueId (mkAggregateVal leafExprs)
            else
              unless layout.types.isNamedAggregate typeId do
                planError "unsupported Psy semantic shape: construct requires named Struct/Enum or Array"
              let some decl := layout.typeDecls[typeId.toNat]? |
                planError "unsupported Psy semantic shape: construct TypeDecl missing"
              match decl.shape with
              | .struct fields => do
                  unless ctorIdx.toNat == 0 do
                    planError "unsupported Psy semantic shape: struct construct ctorIdx must be 0"
                  unless argIds.size == fields.size do
                    planError "unsupported Psy semantic shape: struct construct arity mismatch"
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
                      planError "unsupported Psy semantic shape: struct construct field leaf count mismatch"
                    leaves := leaves ++ argLeaves
                  env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
              | .enum variants => do
                  let vi := ctorIdx.toNat
                  let some variant := variants[vi]? |
                    planError "unsupported Psy semantic shape: enum construct variant out of range"
                  unless argIds.size == variant.payloadTypes.size do
                    planError "unsupported Psy semantic shape: enum construct arity mismatch"
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
                      planError "unsupported Psy semantic shape: enum construct payload leaf count mismatch"
                    leaves := leaves ++ argLeaves
                  while leaves.size < 1 + maxPay do
                    leaves := leaves.push (.literal 0)
                  env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
              | _ =>
                  planError "unsupported Psy semantic shape: construct requires Struct or Enum shape"
    | .fieldGet baseId fieldIndex => do
        match instr.result with
        | none => planError "unsupported Psy semantic shape: fieldGet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "unsupported Psy semantic shape: fieldGet base undefined"
            unless base.isAggregate do
              planError "unsupported Psy semantic shape: fieldGet base must be a named aggregate"
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
                  planError "unsupported Psy semantic shape: fieldGet could not resolve struct field range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Psy semantic shape: fieldGet leaf range out of bounds"
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
        | none => planError "unsupported Psy semantic shape: fieldSet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "fieldSet base undefined"
            let val ← match envLookup env valueId with
              | some v => pure v
              | none => planError "fieldSet value undefined"
            unless base.isAggregate do
              planError "unsupported Psy semantic shape: fieldSet base must be a named aggregate"
            unless layout.types.isNamedAggregate valueDef.typeId do
              planError "unsupported Psy semantic shape: fieldSet result must be named aggregate"
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
              | none => planError "unsupported Psy semantic shape: fieldSet could not resolve field range"
            unless valLeaves.size == len do
              planError "unsupported Psy semantic shape: fieldSet value leaf count mismatch"
            unless start + len <= baseLeaves.size do
              planError "unsupported Psy semantic shape: fieldSet leaf range out of bounds"
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
              planError "unsupported Psy semantic shape: variantTag base must be a named Enum aggregate"
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
              planError "unsupported Psy semantic shape: variantPayload base must be a named Enum aggregate"
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
              | none => planError "unsupported Psy semantic shape: variantPayload could not resolve range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Psy semantic shape: variantPayload leaf range out of bounds"
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
              planError "unsupported Psy semantic shape: IndexGet base must be an Array UInt64 aggregate"
            let i ← literalIndexNatV1 idx
            let leaves := base.leafExprs
            unless i < leaves.size do
              planError "unsupported Psy semantic shape: Array IndexGet index out of range"
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
              planError "unsupported Psy semantic shape: IndexSet base must be an Array UInt64 aggregate"
            unless !val.isAggregate do
              planError "unsupported Psy semantic shape: Array IndexSet value must be scalar UInt64"
            let i ← literalIndexNatV1 idx
            let leaves := base.leafExprs
            unless i < leaves.size do
              planError "unsupported Psy semantic shape: Array IndexSet index out of range"
            let mut outLeaves : Array Expr := #[]
            for j in [0:leaves.size] do
              if j == i then
                outLeaves := outLeaves.push val.expr
              else
                let some e := leaves[j]? |
                  planError "Array IndexSet leaf missing"
                outLeaves := outLeaves.push e
            env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
    | .constant .. | .checkedCast .. =>
        planError "unsupported Psy semantic shape: Constant/CheckedCast is outside the Psy UInt64/aggregate envelope"
    -- N5: Psy declines both ContextRead and Commit (policy none).
    | .contextRead .. =>
        planError "unsupported Psy semantic shape: ContextRead is not admitted by pilot context policy"
    | .commit .. =>
        planError "unsupported Psy semantic shape: Commit is not admitted by pilot context policy"
  match block.terminator with
  | .jump target =>
      if isActiveHeader loops target.blockId then
        pure { stmts := ls.stmts, join? := none }
      else if isLoopHeaderV1 callable target.blockId then
        lowerLoop data layout callable fnNames target ls env loops
      else
        lowerRegion data layout callable fnNames target.blockId.toNat loops env ls
  | .branch condition thenTarget elseTarget => do
      let c ← match envLookupExpr env condition with
        | some e => pure e
        | none => planError "unsupported Psy semantic shape: branch references an undefined condition"
      let emptyLs : LowerStateV1 := { stmts := #[] }
      let thenRes ← lowerRegion data layout callable fnNames thenTarget.blockId.toNat loops env emptyLs
      let elseRes ← lowerRegion data layout callable fnNames elseTarget.blockId.toNat loops env emptyLs
      let join? ← match thenRes.join?, elseRes.join? with
        | none, none => pure none
        | some j, none => pure (some j)
        | none, some j => pure (some j)
        | some j1, some j2 =>
            if j1 == j2 then pure (some j1)
            else planError "unsupported Psy semantic shape: branch arms join at different blocks"
      let stmts := ls.stmts.push (.ifThenElse c thenRes.stmts elseRes.stmts)
      pure { stmts, join? }
  | .switch scrutinee cases defaultTarget => do
      let s ← match envLookupExpr env scrutinee with
        | some e => pure e
        | none => planError "unsupported Psy semantic shape: switch references an undefined scrutinee"
      let mut caseStmts : Array (UInt64 × Array Statement) := #[]
      let mut joins : Array Nat := #[]
      for case in cases do
        let value ← match decodeUInt64LiteralV1 case.valueBytes with
          | .ok v => pure v
          | .error e => .error e
        let emptyLs : LowerStateV1 := { stmts := #[] }
        let targetRes ← lowerRegion data layout callable fnNames case.target.blockId.toNat loops env emptyLs
        caseStmts := caseStmts.push (value, targetRes.stmts)
        match targetRes.join? with
        | some j => joins := joins.push j
        | none => pure ()
      let emptyLs : LowerStateV1 := { stmts := #[] }
      let defaultRes ← match defaultTarget with
        | none => regionClosed
        | some t => lowerRegion data layout callable fnNames t.blockId.toNat loops env emptyLs
      match defaultRes.join? with
      | some j => joins := joins.push j
      | none => pure ()
      let join? ← match joins.toList with
        | [] => pure none
        | j :: rest =>
            if rest.all (· == j) then pure (some j)
            else planError "unsupported Psy semantic shape: switch arms join at different blocks"
      let stmts := ls.stmts.push (.switchOn s caseStmts defaultRes.stmts)
      pure { stmts, join? }
  | .return_ value => do
      let stmts ← match value with
        | none => pure (ls.stmts.push .returnNone)
        | some vid =>
            match envLookup env vid with
            | some v =>
                if v.isAggregate then
                  planError "unsupported Psy semantic shape: return of aggregate is outside the Psy scalar result envelope"
                pure (ls.stmts.push (.returnValue v.expr))
            | none => planError "unsupported Psy semantic shape: return references an undefined value"
      pure { stmts, join? := none }
  | .revert errorId args => do
      unless args.isEmpty do
        planError "unsupported Psy semantic shape: revert with error arguments cannot be expressed on the Psy surface"
      let stmts := ls.stmts.push (.revertError errorId.toNat #[])
      pure { stmts, join? := none }
  | .trap _ => do
      let stmts := ls.stmts.push .bareRevert
      pure { stmts, join? := none }

private partial def lowerLoop
    (data : SemanticProgramDataV1) (layout : PsyLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (target : JumpTargetV1) (ls : LowerStateV1) (env : ValueEnv)
    (loops : Array LoopCtxV1) : CompileResult RegionResult := do
  let headerIdx := target.blockId.toNat
  let lb ← match callable.loopBounds.findSome? (fun lb =>
      if lb.header == target.blockId then some lb else none) with
    | some lb => pure lb
    | none => planError "unsupported Psy semantic shape: loop bound missing for header"
  if loops.any (fun ctx => ctx.header == target.blockId) then
    planError "unsupported Psy semantic shape: re-entered an active loop header"
  let header ← match callable.blocks[headerIdx]? with
    | some b => pure b
    | none => planError "unsupported Psy semantic shape: loop header block is missing"
  unless header.params.size == 1 do
    planError "unsupported Psy semantic shape: loop header must carry exactly one block parameter"
  let some paramDef := header.params[0]? |
    planError "unsupported Psy semantic shape: loop header parameter is missing"
  unless target.args.size == 1 do
    planError "unsupported Psy semantic shape: loop entry must carry exactly one argument"
  let startVid ← match target.args[0]? with
    | some v => pure v
    | none => planError "unsupported Psy semantic shape: loop start value is missing"
  let startExpr ← match envLookupExpr env startVid with
    | some e => pure e
    | none => planError "unsupported Psy semantic shape: loop start value is not defined"
  let mut condVid? : Option ValueIdV1 := none
  let mut endExpr? : Option Expr := none
  for instr in header.instructions do
    match instr.op with
    | .binary .lt lhs rhs => do
        unless lhs == paramDef.valueId do
          planError "unsupported Psy semantic shape: loop condition lhs must be the induction parameter"
        let r ← match envLookupExpr env rhs with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: loop end value is not defined"
        match instr.result with
        | some valueDef => condVid? := some valueDef.valueId
        | none => planError "unsupported Psy semantic shape: loop condition must produce a value"
        endExpr? := some r
    | _ =>
        planError "unsupported Psy semantic shape: loop header carries an unexpected instruction"
  let endExpr ← match endExpr? with
    | some e => pure e
    | none => planError "unsupported Psy semantic shape: loop header must compute `i < end`"
  let depth := loops.size
  let envLoop := envInsert env paramDef.valueId (.loopVar depth)
  let loops' := loops.push { header := target.blockId }
  match header.terminator with
  | .branch condVid thenTarget _ => do
      match condVid? with
      | some expected =>
          unless condVid == expected do
            planError "unsupported Psy semantic shape: loop branch condition does not match the header computation"
      | none => planError "unsupported Psy semantic shape: loop header branch condition is missing"
      let emptyBody : LowerStateV1 := { stmts := #[] }
      let thenRes ← lowerRegion data layout callable fnNames thenTarget.blockId.toNat loops' envLoop emptyBody
      unless thenRes.join?.isNone do
        planError "unsupported Psy semantic shape: loop body must end at the latch back edge"
      let body := thenRes.stmts
      let maxIter := lb.maxIterations.toNat
      unless maxIter ≤ 4096 do
        planError "unsupported Psy semantic shape: loop bound exceeds the wire maximum"
      let forStmt := .forLoop startExpr endExpr maxIter body
      match header.terminator with
      | .branch _ _ elseTarget =>
          let ls' : LowerStateV1 := { ls with stmts := ls.stmts.push forStmt }
          lowerRegion data layout callable fnNames elseTarget.blockId.toNat loops env ls'
      | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"
  | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"

end

private def resultShape (data : SemanticProgramDataV1) (callable : CallableV1) :
    CompileResult (Bool × Bool) := do
  if isBoolType data callable.result.typeId then pure (true, false)
  else if isUInt64Type data callable.result.typeId then pure (false, false)
  else if isInt64Type data callable.result.typeId then pure (false, false)
  else if isUnitType data callable.result.typeId then pure (false, true)
  else planError "unsupported Psy semantic shape: callable result is outside the public UInt64/Int64/Bool/Unit envelope"

private def lowerCallable
    (data : SemanticProgramDataV1) (layout : PsyLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String)) :
    CompileResult PlanFunction := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty do
    planError "unsupported Psy semantic shape: callable must have entry block 0"
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      planError "unsupported Psy semantic shape: loop header block is missing"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      planError "unsupported Psy semantic shape: loop latch block is missing"
    unless header.params.size == 1 do
      planError "unsupported Psy semantic shape: loop header must carry one UInt64 parameter"
    match header.terminator with
    | .branch .. => pure ()
    | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"
    match latch.terminator with
    | .jump t =>
        unless t.blockId == lb.header && t.args.size == 1 do
          planError "unsupported Psy semantic shape: loop latch must jump back with one argument"
    | _ => planError "unsupported Psy semantic shape: loop latch must jump back to the header"
  for blk in callable.blocks do
    unless blk.params.isEmpty ||
        callable.loopBounds.any (fun lb => lb.header == blk.id) do
      planError "unsupported Psy semantic shape: block parameters are only supported on loop headers"
  let mut params : Array PlanParam := #[]
  let mut paramIndex : Nat := 0
  for p in callable.params do
    let isBool ← if isBoolType data p.typeId then pure true
      else if isUInt64Type data p.typeId || isInt64Type data p.typeId then pure false
      else planError "unsupported Psy semantic shape: callable parameter is outside the UInt64/Int64/Bool envelope"
    params := params.push { sourceIndex := paramIndex, name := p.name, isBool }
    paramIndex := paramIndex + 1
  let mut env0 : ValueEnv := default
  let mut paramOrdinal : Nat := 0
  for p in callable.params do
    env0 := envInsert env0 p.valueId (.param paramOrdinal)
    paramOrdinal := paramOrdinal + 1
  let empty0 : LowerStateV1 := { stmts := #[] }
  let res ← lowerRegion data layout callable fnNames 0 #[] env0 empty0
  unless res.join?.isNone do
    planError "unsupported Psy semantic shape: callable does not end in return on all paths"
  let body := res.stmts
  let (resultIsBool, resultIsUnit) ← resultShape data callable
  let kind := match callable.kind with
    | .initializer => FunctionKind.initialize
    | .pureFn => FunctionKind.pureHelper
    | _ => FunctionKind.mutate
  let name ← match callable.name with
    | some n => pure n
    | none => pure "initialize"
  pure {
    index := 0
    name
    kind
    params
    body
    resultIsBool
    resultIsUnit
  }

private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  -- Type-closure first: Field/Principal fail closed; named + Array admitted (H3).
  let types ← validatePsyTypeClosureV1 data.types
  let layout ← makeStateLayoutV1 types data.types data.logicalState
  let mut events : Array PlanEvent := #[]
  for ev in data.events do
    let fieldNames := ev.fields.map (·.name)
    events := events.push { name := ev.name, fieldNames }
  let mut errors : Array PlanErrorDecl := #[]
  for err in data.errors do
    let fieldNames := err.fields.map (·.name)
    errors := errors.push { name := err.name, fieldNames }
  let fnNames := data.callables.filterMap fun c =>
    match c.kind with
    | .pureFn => some (c.id, c.name.getD "fn")
    | _ => none
  let mut functions : Array PlanFunction := #[]
  for callable in data.callables do
    match callable.kind with
    | .invariant =>
        planError "unsupported Psy semantic shape: invariants are outside the Psy envelope"
    | .initializer | .entry | .view | .pureFn =>
        let fn ← lowerCallable data layout callable fnNames
        functions := functions.push { fn with index := functions.size }
  pure {
    programName
    stateFieldNames := layout.fieldNames
    functions
    events
    errors
    sourceHash
    semanticHash
  }

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) (artifactProgramName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Psy received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash

private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"

/-- Internal Psy family phase entry: capability → Plan (pre-canonicity).
    Kind must be `.psy` (TargetKind already includes psy; P-B flips registry
    membership/default profile so product selection can mint a capability). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .psy do
    throw <| .planInvariant .psy "engineering capability kind is not Psy"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Psy source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Psy semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

/-- Pre-P-B / unit-test Plan entry: retained SemanticProgramV1 only. Same body
    as the capability path after the kind check. Product materialize remains
    capability-only once P-B wires registry/descriptor/support. -/
def planFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Psy source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Psy semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Psy
