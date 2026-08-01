import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Compiler.Pipeline

/-!
# Noir LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the Noir-owned relation Plan surface and Semantic→Plan body.
-/

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

def codegenProfileString : String := "noir-source-u64-relations-v1"
def codegenProfile : CodegenProfileId := CodegenProfileId.noirSourceU64RelationsV1
def sourceDialect : String := "noir-native-u64-relations-v1"

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.noir

inductive StateContinuity where
  | none
  | externalPublicPrePost
  deriving BEq, Inhabited, Repr

inductive ConstraintFailurePolicy where
  | unsatisfied
  deriving BEq, Inhabited, Repr

inductive ProofStatus where
  | notProduced
  deriving BEq, Inhabited, Repr

inductive RelationMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

inductive InputVisibility where
  | verifier
  | witness
  deriving BEq, Inhabited, Repr

inductive InputType where
  | u64
  | bool
  /-- Sole catalog bn254 Fr Field (Noir native Field; exact modulus match). -/
  | field
  /-- T8b: ABI multi-width public inputs (native Noir u8/u16/u32). Body temps
      still zero-extend into the UInt64 pilot until T8d. -/
  | u8
  | u16
  | u32
  deriving BEq, Inhabited, Repr

inductive InputRole where
  | preInitialized
  | preState (sourceId : Nat)
  | parameter (sourceId : Nat)
  | postState (sourceId : Nat)
  | postInitialized
  | result
  | eventSlot (emitIndex argIndex : Nat)
  /-- Verifier witness of one static external call's outcome: true when the
      executing path's response disposition is returned (a reverted claim is
      inadmissible, mirroring externalCallReverted). -/
  | callStatus (callIndex : Nat)
  | callArgSlot (callIndex argIndex : Nat)
  | scheduleArgSlot (scheduleIndex argIndex : Nat)
  deriving BEq, Inhabited, Repr

structure ResourceLimits where
  maxArtifactStemBytes : Nat
  maxStateFields : Nat
  maxRelations : Nat
  maxParams : Nat
  maxBodyStatements : Nat
  maxExprDepth : Nat
  maxPlanNodes : Nat
  maxIrOperations : Nat
  deriving BEq, Inhabited, Repr

structure StateField where
  sourceId : Nat
  name : String
  /-- UInt64 / Int64 share the u64 plan word; UInt{8,16,32} map to native Noir
      widths (T8b); Field is native Noir Field. -/
  inputType : InputType := .u64
  /-- Relation-slot disclosure: public state is a verifier-visible pre/post
      public input; private state is a private-witness pre/post slot (the
      proof carries the values as witnesses while Reference still treats them
      as logical state). Commitment is not representable in this pilot. -/
  visibility : InputVisibility := .verifier
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  inputIndex : Nat
  visibility : InputVisibility
  /-- Plan input type for this parameter (u64 / u8 / u16 / u32 / field). -/
  inputType : InputType := .u64
  deriving BEq, Inhabited, Repr

structure InputBinding where
  name : String
  sourceName : String
  type : InputType
  visibility : InputVisibility
  role : InputRole
  deriving BEq, Inhabited, Repr

/-- Native UInt64 comparison operators for Noir relation expressions. -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (inputIndex : Nat)
  | stateLoad (fieldIndex : Nat)
  /-- Reference to a loop header's induction-variable block param. The slot
  is the param's index in the callable's seeded block-param order; the
  relation walker resolves it through the current unrolling's substitution
  environment (it never reaches rendering). -/
  | loopParam (slot : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  /-- Exact mod-p Field arithmetic (Noir native Field = bn254 Fr). No overflow
      assert; div still asserts non-zero. -/
  | fieldAdd (lhs rhs : Expr)
  | fieldSub (lhs rhs : Expr)
  | fieldMul (lhs rhs : Expr)
  | fieldDiv (lhs rhs : Expr)
  | bitNot (operand : Expr)
  /-- Narrow body checked arithmetic (`bitWidth ∈ {8,16,32}`); UInt64 keeps historical.
      Field never uses these — field* constructors stay separate. -/
  | narrowCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitAnd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitOr (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitXor (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitNot (bitWidth : Nat) (operand : Expr)
  | narrowShl (bitWidth : Nat) (lhs rhs : Expr)
  | narrowShr (bitWidth : Nat) (lhs rhs : Expr)
  | boolNot (operand : Expr)
  | checkedNeg (operand : Expr)
  /-- Field unary neg: native `-x` on Field (p - v). -/
  | fieldNeg (operand : Expr)
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
  | bitAnd (lhs rhs : Expr)
  | bitOr (lhs rhs : Expr)
  | bitXor (lhs rhs : Expr)
  /-- Shift by a count that must be a compile-time constant in this pilot
      (UInt32 values arise only from literal arithmetic); the relation layer
      constant-folds it into the guard-and-multiply/divide form. -/
  | shl (lhs rhs : Expr)
  | shr (lhs rhs : Expr)
  | boolAnd (lhs rhs : Expr)
  | boolOr (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | callFn (fnIndex : Nat) (args : Array Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  fieldIndex : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  | returnNone
  | assert (condition : Expr)
  | emitEvent (effectId : Nat) (eventIndex : Nat) (args : Array Expr)
  | revertError (errorIndex : Nat) (args : Array Expr)
  /-- Sync external call (v1: statement effect, no result value). Each static
      site binds one status witness and one public arg slot per argument;
      the executing path asserts the status returned and binds the computed
      arg values, other paths zero everything. -/
  | externalCall (effectId : Nat) (callee : Array String) (args : Array Expr)
  /-- Async workflow schedule (fire-and-forget, no response channel): each
      static site binds one public arg slot per argument, bound on the
      executing path and zeroed elsewhere. -/
  | schedule (effectId : Nat) (callee : Array String) (args : Array Expr)
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  /-- Bounded counting loop: the induction variable (a `.loopParam slot`
  block param) starts at `initial`, the body runs while `cond` holds, and
  `update` computes the next value. The static `bound` caps unrolling at the
  relation layer; the (bound+1)-th iteration is inadmissible, mirroring the
  reference machine's boundExceeded revert. Bodies may contain nested
  regions and loops, returns, and reverts, but no emits (one static event
  slot cannot bind multiple dynamic occurrences). -/
  | forLoop (slot : Nat) (bound : UInt32) (initial cond update : Expr)
      (body : Array Statement)
  deriving BEq, Inhabited, Repr

/-- One independently provable relation. Initializer, mutate, and view methods
are never folded into an inactive-selector circuit. -/
structure Relation where
  index : Nat
  name : String
  artifactStem : String
  mode : RelationMode
  params : Array Param
  inputs : Array InputBinding
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- One declared event/error binding: its name and UInt64 argument count. -/
structure InterfaceBinding where
  name : String
  fieldCount : Nat
  deriving BEq, Inhabited, Repr

/-- One validated pure-fn signature keyed by GLOBAL callable id (the id
    Op.PureCall references). Bodies lower against this complete table; the
    IR inline walker consumes the full FnBinding bodies from the Plan. -/
private structure FnSigV1 where
  callableId : Nat
  name : String
  paramCount : Nat
  resultIsBool : Bool
  deriving Inhabited

/-- One lowered pure function: its global callable id, name, lowered params,
    result kind, and the path-tree statement body (region-last form, same as
    relations). Pure fn bodies contain no state/effect statements by
    construction. -/
structure FnBinding where
  callableId : Nat
  name : String
  params : Array Param
  resultIsBool : Bool
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Target-owned source-relation plan. It deliberately retains no
SemanticProgram and records that proof production/settlement are external. -/
structure Plan where
  targetDescriptor : TargetDescriptor
  semanticSchemaVersion : Nat
  codegenProfile : String
  sourceDialect : String
  continuity : StateContinuity
  failurePolicy : ConstraintFailurePolicy
  proofStatus : ProofStatus
  resourceLimits : ResourceLimits
  programName : String
  sourceHash : String
  semanticHash : String
  /-- Deterministic digest of the complete canonical Plan. This detects
  unchecked in-process mutation; it is not an authenticity certificate for an
  untrusted serialized Plan. -/
  planHash : String
  states : Array StateField
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  fns : Array FnBinding
  relations : Array Relation
  -- No Inhabited: Plan embeds TargetDescriptor (opaque TargetId/profile).
  deriving BEq, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .noir message

private def maxIdentifierBytes : Nat := 120
def maxArtifactStemBytes : Nat := 220
def maxStateFields : Nat := 256
def maxRelations : Nat := 256
def maxParams : Nat := 64
def maxBodyStatements : Nat := 4096
def maxExprDepth : Nat := 256
def maxPlanNodes : Nat := 100000
def maxIrOperations : Nat := 110000

def canonicalLimits : ResourceLimits := {
  maxArtifactStemBytes
  maxStateFields
  maxRelations
  maxParams
  maxBodyStatements
  maxExprDepth
  maxPlanNodes
  maxIrOperations
}

/-- Thin adapter: binds Noir's `maxIdentifierBytes` (120 — documented divergence
    from EVM/Solana/NEAR's 240) to the shared ASCII grammar. -/
def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

def validDigest (value : String) : Bool :=
  value.length == 64 && value.toList.all (fun character =>
    "0123456789abcdef".contains character)

/-- Transitional deterministic descriptor preimage for the engineering Noir
plan hash. It serializes only target/profile/axis identity and deliberately
excludes requirement support; the exact resolver index is the sole current
support authority. This is not the formal D3 TargetSemantics/Profile digest. -/
def targetDescriptorEngineeringReprV1 (d : TargetDescriptor) : String :=
  let targetIdWire (id : TargetId) : String :=
    s!"ProofForgeV2.TargetId.{id.toString}"
  let codegenProfileWire (profile : CodegenProfileId) : String :=
    -- Profile grammar forbids escapes, so quoted UTF-8 is unambiguous here.
    s!"\"{profile.toString}\""
  "{ targetId := " ++ targetIdWire d.targetId ++ ",\n" ++
  "  artifactEncoding := " ++ reprStr d.artifactEncoding ++ ",\n" ++
  "  executionHost := " ++ reprStr d.executionHost ++ ",\n" ++
  "  commitModel := " ++ reprStr d.commitModel ++ ",\n" ++
  "  stateBinding := " ++ reprStr d.stateBinding ++ ",\n" ++
  "  callModel := " ++ reprStr d.callModel ++ ",\n" ++
  "  proofModel := " ++ reprStr d.proofModel ++ ",\n" ++
  "  settlementModel := " ++ reprStr d.settlementModel ++ ",\n" ++
  "  codegenProfile := " ++ codegenProfileWire d.codegenProfile ++ " }"

def canonicalPlanHash (plan : Plan) : String :=
  Crypto.sha256Hex <| ("pf.noir.plan.v1\u0000" ++
    targetDescriptorEngineeringReprV1 plan.targetDescriptor ++ "\u0000" ++
    reprStr plan.semanticSchemaVersion ++ "\u0000" ++
    reprStr plan.codegenProfile ++ "\u0000" ++
    reprStr plan.sourceDialect ++ "\u0000" ++
    reprStr plan.continuity ++ "\u0000" ++
    reprStr plan.failurePolicy ++ "\u0000" ++
    reprStr plan.proofStatus ++ "\u0000" ++
    reprStr plan.resourceLimits ++ "\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.relations).toUTF8

def artifactStem (index : Nat) (mode : RelationMode) (name : String) : String :=
  let suffix := if mode == .initialize then "init" else name
  s!"r{index}-{suffix}"

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering -/

/-- Value kinds admitted in the Noir pilot value table. Bool may be intermediate
(comparison/literal results feeding assert) or an entry/view result binding;
state and params admit UInt{8,16,32,64} / Int64 / Field (bn254). Body multi-width
(T8d) tracks UInt{8,16,32,64} temps; Field stays on field* Plan ops only.
Named Struct/Enum values are carried as `.aggregate` (flattened UInt64/Int64
leaf public inputs — circuit-native field access via leaf constraints). -/
private inductive NoirValueKindV1 where
  | uint64
  | uint32
  | uint16
  | uint8
  | bool
  | int64
  | field
  | aggregate
  deriving BEq, Inhabited, Repr

private def uintKindOfWidthV1 (w : Nat) : Option NoirValueKindV1 :=
  match w with
  | 8 => some .uint8
  | 16 => some .uint16
  | 32 => some .uint32
  | 64 => some .uint64
  | _ => none

private def widthOfUintKindV1 (k : NoirValueKindV1) : Option Nat :=
  match k with
  | .uint8 => some 8
  | .uint16 => some 16
  | .uint32 => some 32
  | .uint64 => some 64
  | .bool | .int64 | .field | .aggregate => none

/-- Noir pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Bool optional; state/params admit UInt{8,16,32,64}/Int64/Field (T8b) and
    named Struct/Enum (NoirAggregate: flattened to leaf public inputs).
    Shift counts decode to plain u64 literals in the Plan. -/
private abbrev NoirTypeClosureV1 := PilotTypeClosureV1

private def noirPlanErr (m : String) : CompileError :=
  .planInvariant .noir m

/-- Map an admitted scalar TypeId to a Noir public-input type.
    Field → `.field`; ABI UInt{8,16,32,64} → matching width; Int64 → `.u64`
    (bit-pattern carrier). Fail closed on anything else. -/
private def inputTypeOfScalarV1
    (types : NoirTypeClosureV1) (typeId : TypeIdV1) : CompileResult InputType := do
  if types.isField typeId then
    pure .field
  else if types.int64TypeId == some typeId then
    pure .u64
  else
    match types.uintWidthOf typeId with
    | some 8 => pure .u8
    | some 16 => pure .u16
    | some 32 => pure .u32
    | some 64 => pure .u64
    | some w =>
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: ABI UInt{w} is not admitted"
    | none =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: scalar type is not UInt{8,16,32,64}, Int64, or Field"

/-- Noir pilot accepts UInt{8,16,32,64}/Unit/Bool/Int64 plus sole catalog Field
    (bn254 Fr = Noir native Field) under `pilotUintWidthPolicyNoirBody` (T8d body
    multi-width + T8b ABI multi-width), plus **named Struct/Enum**
    (`pilotNamedAggregateStatePolicyAdmit`, NoirAggregate) flattened to
    UInt64/Int64 relation-slot leaves. Anonymous Array/Map/Bytes stay fail
    closed (`pilotContainerStatePolicyNone`). Valid but richer SemanticProgramV1
    programs fail at the target Plan seam rather than being silently erased.
    N2c: Principal remains fail-closed (variable-length identity is not a
    Field element; default `pilotPrincipalPolicyNone`). -/
private def validateNoirTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult NoirTypeClosureV1 :=
  -- Named aggregates admitted (flatten-to-leaf public inputs). Containers
  -- (anonymous Array/Map/Bytes) and Option stay fail closed at type-closure.
  validatePilotTypeClosure noirPlanErr noirTypeClosureWording types
    pilotUintWidthPolicyNoirBody
    (fieldPolicy := pilotFieldPolicyBn254)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)

/-- Map Semantic visibility to Noir relation-slot disclosure. Commitment is
    rejected by the caller before this helper is applied. -/
private def inputVisibilityOfSemanticV1 : VisibilityV1 → InputVisibility
  | .public_ => .verifier
  | .private_ => .witness
  | .commitment => .verifier

/-- Lowering-time state layout: flattened leaf StateFields (sourceId == dense
    leaf index) + per-logical-state leaf ranges. Named Struct/Enum flatten to
    UInt64/Int64 leaves (preorder); scalars remain one leaf. -/
private structure NoirLowerLayoutV1 where
  fields : Array StateField
  stateLeaves : Array (Array Nat)
  typeDecls : Array TypeDeclV1
  deriving Inhabited

private structure LoweredValueV1 where
  expr : Expr
  kind : NoirValueKindV1
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  /-- Named-aggregate leaf words (UInt64/Int64) in preorder flatten order.
      `none` = scalar. When `some`, `expr` mirrors `leaves[0]!` (or literal 0)
      and `kind = .aggregate`. -/
  aggregateLeaves : Option (Array Expr) := none
  /-- Parallel Int64 flag per aggregate leaf (same length as `aggregateLeaves`). -/
  aggregateLeafIsInt : Option (Array Bool) := none
  deriving Inhabited

private def LoweredValueV1.isAggregate (v : LoweredValueV1) : Bool :=
  v.kind == .aggregate || v.aggregateLeaves.isSome

private def LoweredValueV1.leafExprs (v : LoweredValueV1) : Array Expr :=
  match v.aggregateLeaves with
  | some ls => ls
  | none => #[v.expr]

private def LoweredValueV1.leafIsInts (v : LoweredValueV1) : Array Bool :=
  match v.aggregateLeafIsInt with
  | some flags => flags
  | none => #[v.kind == .int64]

private def mkAggregateValueV1 (leaves : Array Expr) (leafIsInt : Array Bool)
    (deps : Array ValueIdV1) (depth expandedNodes : Nat) : LoweredValueV1 :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head
    kind := .aggregate
    depth
    expandedNodes
    dependencies := deps
    aggregateLeaves := some leaves
    aggregateLeafIsInt := some leafIsInt }

/-- Flatten a type into ordered leaf (name, isInt) pairs under Noir aggregate
    policy. Scalars: UInt64 / Int64 only inside named aggregates (matching EVM
    N3 leaf policy). Named Struct: field preorder. Named Enum: tag (UInt64) +
    max-payload leaf slots (`_tag`, `_p0`…). Field/narrow UInt/Bool/containers
    as nested aggregate leaves fail closed. -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : NoirTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array (String × Bool)) := do
  if typeId == types.uint64TypeId then
    pure #[(namePrefix, false)]
  else if types.int64TypeId == some typeId then
    pure #[(namePrefix, true)]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: named Struct requires at least one field"
            let mut out : Array (String × Bool) := #[]
            for f in fields do
              let subName :=
                if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
              unless isIdentifier subName do
                throw <| .planInvariant .noir
                  s!"state name '{subName}' is not a safe identifier"
              let sub ← flattenTypeLeafSpecsV1 typeDecls types f.typeId subName
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: named Enum requires at least one variant"
            let tagName :=
              if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
            unless isIdentifier tagName do
              throw <| .planInvariant .noir
                s!"state name '{tagName}' is not a safe identifier"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenTypeLeafSpecsV1 typeDecls types pt "tmp"
                n := n + sub.size
              if n > maxPay then maxPay := n
            let mut out : Array (String × Bool) := #[(tagName, false)]
            for i in [0:maxPay] do
              let pName :=
                if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
              unless isIdentifier pName do
                throw <| .planInvariant .noir
                  s!"state name '{pName}' is not a safe identifier"
              out := out.push (pName, false)
            pure out
        | _ =>
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: named type must be Struct or Enum"
  else
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: aggregate leaf must be UInt64, Int64, or named Struct/Enum"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : NoirTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

/-- Struct field leaf range (start, length) within the flattened leaf vector. -/
private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : NoirTypeClosureV1)
    (fields : Array StructFieldV1) (fieldIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let mut start : Nat := 0
  for i in [0:fields.size] do
    let some f := fields[i]? |
      throw <| .planInvariant .noir "struct field index out of range"
    let n ← leafCountOfTypeV1 typeDecls types f.typeId
    if i == fieldIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .noir "struct field index out of range"

/-- Enum max payload leaf count (excluding tag). -/
private def enumMaxPayloadLeavesV1
    (typeDecls : Array TypeDeclV1) (types : NoirTypeClosureV1)
    (variants : Array EnumVariantV1) : CompileResult Nat := do
  let mut maxPay : Nat := 0
  for v in variants do
    let mut n : Nat := 0
    for pt in v.payloadTypes do
      let c ← leafCountOfTypeV1 typeDecls types pt
      n := n + c
    if n > maxPay then maxPay := n
  pure maxPay

/-- Payload leaf offset of `payloadIndex` within variant `variantIndex`
    (0-based within the payload region after the tag). -/
private def enumPayloadLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : NoirTypeClosureV1)
    (variants : Array EnumVariantV1) (variantIndex payloadIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let some v := variants[variantIndex]? |
    throw <| .planInvariant .noir "enum variant index out of range"
  let mut start : Nat := 0
  for i in [0:v.payloadTypes.size] do
    let some pt := v.payloadTypes[i]? |
      throw <| .planInvariant .noir "enum payload index out of range"
    let n ← leafCountOfTypeV1 typeDecls types pt
    if i == payloadIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .noir "enum payload index out of range"

private def makeStateLayoutV1
    (types : NoirTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult NoirLowerLayoutV1 := do
  if states.size > maxStateFields then
    throw <| .planInvariant .noir s!"state count exceeds profile limit {maxStateFields}"
  let mut planned : Array StateField := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      throw <| .planInvariant .noir "semantic state ids must match declaration order"
    -- Witness redesign: private state → private-witness pre/post slots.
    -- Commitment remains fail-closed (no public commitment binding).
    if state.visibility == .commitment then
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: commitment state is not representable (relation pilot has no public commitment binding; private-witness redesign admits private only)"
    unless isIdentifier state.name do
      throw <| .planInvariant .noir s!"state name '{state.name}' is not a safe identifier"
    let visibility := inputVisibilityOfSemanticV1 state.visibility
    if types.isNamedAggregate state.typeId then
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState noirPlanErr types state
        (allowNonPublic := true)
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
      if leafSpecs.isEmpty then
        throw <| .planInvariant .noir s!"state '{state.name}' produced zero relation leaves"
      if planned.size + leafSpecs.size > maxStateFields then
        throw <| .planInvariant .noir s!"state count exceeds profile limit {maxStateFields}"
      let mut leaves : Array Nat := #[]
      for (leafName, _) in leafSpecs do
        let sourceId := planned.size
        planned := planned.push {
          sourceId
          name := leafName
          inputType := .u64
          visibility
        }
        leaves := leaves.push sourceId
      stateLeaves := stateLeaves.push leaves
    else
      requirePublicUintAbiOrInt64OrFieldState noirPlanErr types state
        (allowNonPublic := true)
      let inputType ← inputTypeOfScalarV1 types state.typeId
      let sourceId := planned.size
      planned := planned.push {
        sourceId
        name := state.name
        inputType
        visibility
      }
      stateLeaves := stateLeaves.push #[sourceId]
  if hasDuplicates (planned.map (·.name)) then
    throw <| .planInvariant .noir "state names must be unique"
  pure { fields := planned, stateLeaves, typeDecls }

private def findStateLeavesV1 (layout : NoirLowerLayoutV1)
    (id : StateIdV1) : CompileResult (Array Nat) :=
  match layout.stateLeaves[id.toNat]? with
  | some leaves => .ok leaves
  | none => planError s!"semantic expression references unknown state id {id.toNat}"

private def makeParamsV1 (owner : String) (inputOffset : Nat)
    (types : NoirTypeClosureV1) (typeDecls : Array TypeDeclV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .noir s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  for param in params do
    unless param.valueId.toNat == values.size do
      throw <| .planInvariant .noir
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    -- Witness redesign: private params → private-witness inputs (no verifier
    -- leak). Commitment params remain fail-closed (no commitment realization).
    if param.visibility == .commitment then
      throw <| .planInvariant .noir
        s!"unsupported Noir semantic shape: commitment parameter '{param.name}' in {owner} is not representable (relation pilot has no public commitment binding; private-witness redesign admits private only)"
    unless isIdentifier param.name do
      throw <| .planInvariant .noir
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    if types.isNamedAggregate param.typeId then
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedParam
        noirPlanErr types owner param (allowNonPublic := true)
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types param.typeId param.name
      if planned.size + leafSpecs.size > maxParams then
        throw <| .planInvariant .noir
          s!"parameter count in {owner} exceeds profile limit {maxParams}"
      let mut leafExprs : Array Expr := #[]
      let mut leafIsInt : Array Bool := #[]
      for (leafName, isInt) in leafSpecs do
        unless isIdentifier leafName do
          throw <| .planInvariant .noir
            s!"parameter name '{leafName}' in {owner} is not a safe identifier"
        let inputIndex := inputOffset + planned.size
        planned := planned.push {
          sourceId := planned.size
          name := leafName
          inputIndex
          visibility := inputVisibilityOfSemanticV1 param.visibility
          inputType := .u64
        }
        leafExprs := leafExprs.push (.param inputIndex)
        leafIsInt := leafIsInt.push isInt
      values := values.push (mkAggregateValueV1 leafExprs leafIsInt #[] 1 leafExprs.size)
    else
      requirePublicUintAbiOrInt64OrFieldParam noirPlanErr types owner param
        (allowNonPublic := true)
      let isField := types.isField param.typeId
      let isInt := types.int64TypeId == some param.typeId
      let inputType ← inputTypeOfScalarV1 types param.typeId
      let binding : Param := {
        sourceId := planned.size
        name := param.name
        inputIndex := inputOffset + planned.size
        visibility := inputVisibilityOfSemanticV1 param.visibility
        inputType
      }
      planned := planned.push binding
      let kind ←
        if isField then pure NoirValueKindV1.field
        else if isInt then pure NoirValueKindV1.int64
        else match types.uintWidthOf param.typeId with
          | some w =>
              match uintKindOfWidthV1 w with
              | some k => pure k
              | none =>
                  throw <| .planInvariant .noir
                    s!"unsupported Noir semantic shape: ABI UInt{w} is not admitted"
          | none =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: param type is not UInt/Int64/Field"
      values := values.push {
        -- T8d: narrow ABI params retain semantic width for body arithmetic.
        expr := .param binding.inputIndex
        kind
        depth := 1
        expandedNodes := 1
        dependencies := #[]
      }
  if hasDuplicates (planned.map (·.name)) then
    throw <| .planInvariant .noir s!"parameter names in {owner} must be unique"
  pure (planned, values)

/-- Pre-order emit scan of a relation body: (eventIndex, argCount) keyed by
    the canonical EffectId each static emit statement carries. Event slots
    are keyed by that EffectId. -/
partial def collectEmitSlots (statements : Array Statement) :
    Array (Nat × Nat × Nat) :=
  statements.foldl (fun slots statement =>
    match statement with
    | .emitEvent effectId eventIndex args => slots.push (effectId, eventIndex, args.size)
    | .ifThenElse _ thenBody elseBody =>
        slots ++ collectEmitSlots thenBody ++ collectEmitSlots elseBody
    | .switchOn _ cases defaultBody =>
        let caseSlots := cases.foldl (fun acc (_, body) =>
          acc ++ collectEmitSlots body) #[]
        slots ++ caseSlots ++ collectEmitSlots defaultBody
    | .forLoop _ _ _ _ _ body => slots ++ collectEmitSlots body
    | _ => slots) #[]

/-- Pre-order external-call scan of a relation body: (argCount) keyed by the
    canonical EffectId each static call statement carries. Call arg slots
    and the status witness are keyed by that EffectId. -/
partial def collectCallSlots (statements : Array Statement) :
    Array (Nat × Nat) :=
  statements.foldl (fun slots statement =>
    match statement with
    | .externalCall effectId _ args => slots.push (effectId, args.size)
    | .ifThenElse _ thenBody elseBody =>
        slots ++ collectCallSlots thenBody ++ collectCallSlots elseBody
    | .switchOn _ cases defaultBody =>
        let caseSlots := cases.foldl (fun acc (_, body) =>
          acc ++ collectCallSlots body) #[]
        slots ++ caseSlots ++ collectCallSlots defaultBody
    | .forLoop _ _ _ _ _ body => slots ++ collectCallSlots body
    | _ => slots) #[]

/-- Pre-order schedule scan of a relation body: (argCount) keyed by the
    canonical EffectId each static schedule statement carries. -/
partial def collectScheduleSlots (statements : Array Statement) :
    Array (Nat × Nat) :=
  statements.foldl (fun slots statement =>
    match statement with
    | .schedule effectId _ args => slots.push (effectId, args.size)
    | .ifThenElse _ thenBody elseBody =>
        slots ++ collectScheduleSlots thenBody ++ collectScheduleSlots elseBody
    | .switchOn _ cases defaultBody =>
        let caseSlots := cases.foldl (fun acc (_, body) =>
          acc ++ collectScheduleSlots body) #[]
        slots ++ caseSlots ++ collectScheduleSlots defaultBody
    | .forLoop _ _ _ _ _ body => slots ++ collectScheduleSlots body
    | _ => slots) #[]

/-- Build the canonical input envelope. Public state/params are verifier-visible;
    private state/params are private-witness slots (proof carries them; Reference
    still treats private state as state). Lifecycle flags (`pre_initialized` /
    `post_initialized`) and entry/view results stay verifier-visible.
    `resultType` is used only for non-initializer relations (entry/view).
    Event/call/schedule slots trail the result: verifier-visible u64 per static
    effect argument in pre-order. -/
def makeInputsV1 (states : Array StateField) (mode : RelationMode)
    (params : Array Param) (resultType : InputType)
    (emitSlots : Array (Nat × Nat × Nat)) (callSlots : Array (Nat × Nat))
    (scheduleSlots : Array (Nat × Nat)) : Array InputBinding := Id.run do
  let mut inputs : Array InputBinding := #[]
  if !states.isEmpty then
    inputs := inputs.push {
      name := "pre_initialized"
      sourceName := "initialized"
      type := .bool
      visibility := .verifier
      role := .preInitialized
    }
  if mode != .initialize then
    for field in states do
      inputs := inputs.push {
        name := s!"pre_s{field.sourceId}"
        sourceName := field.name
        type := field.inputType
        visibility := field.visibility
        role := .preState field.sourceId
      }
  for param in params do
    inputs := inputs.push {
      name := s!"arg_p{param.sourceId}"
      sourceName := param.name
      type := param.inputType
      visibility := param.visibility
      role := .parameter param.sourceId
    }
  for field in states do
    inputs := inputs.push {
      name := s!"post_s{field.sourceId}"
      sourceName := field.name
      type := field.inputType
      visibility := field.visibility
      role := .postState field.sourceId
    }
  if !states.isEmpty then
    inputs := inputs.push {
      name := "post_initialized"
      sourceName := "initialized"
      type := .bool
      visibility := .verifier
      role := .postInitialized
    }
  if mode != .initialize then
    inputs := inputs.push {
      name := "result"
      sourceName := "result"
      type := resultType
      visibility := .verifier
      role := .result
    }
  for (effectId, _, argCount) in emitSlots do
    for argIndex in [0:argCount] do
      inputs := inputs.push {
        name := s!"ev_e{effectId}_a{argIndex}"
        sourceName := s!"event_slot_{effectId}_{argIndex}"
        type := .u64
        visibility := .verifier
        role := .eventSlot effectId argIndex
      }
  for (effectId, argCount) in callSlots do
    inputs := inputs.push {
      name := s!"call_e{effectId}_status"
      sourceName := s!"call_status_{effectId}"
      type := .bool
      visibility := .verifier
      role := .callStatus effectId
    }
    for argIndex in [0:argCount] do
      inputs := inputs.push {
        name := s!"call_e{effectId}_a{argIndex}"
        sourceName := s!"call_slot_{effectId}_{argIndex}"
        type := .u64
        visibility := .verifier
        role := .callArgSlot effectId argIndex
      }
  for (effectId, argCount) in scheduleSlots do
    for argIndex in [0:argCount] do
      inputs := inputs.push {
        name := s!"sched_e{effectId}_a{argIndex}"
        sourceName := s!"schedule_slot_{effectId}_{argIndex}"
        type := .u64
        visibility := .verifier
        role := .scheduleArgSlot effectId argIndex
      }
  pure inputs

def resultInputTypeOf (relation : Relation) : InputType :=
  match relation.inputs.find? (fun binding => binding.role == .result) with
  | some binding => binding.type
  | none => .u64

private def findValueV1 (values : Array LoweredValueV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 :=
  match values[id.toNat]? with
  | some value => .ok value
  | none => planError s!"semantic expression references unknown ValueId {id.toNat}"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt64LiteralLe noirPlanErr "Noir" bytes

/-- Decode a SemanticProgramV1 Bool literal (exactly one byte `0x00`/`0x01`).
    Represented as UInt64 0/1 inside the plan Expr surface.
    Invalid-byte wording is Noir's historical divergence (extra "byte "). -/
private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  let bit ← decodeBoolLiteralBit noirPlanErr "Noir" bytes
    (invalidDetail := "Bool literal byte must be 0x00 or 0x01")
  pure (if bit then 1 else 0)

private def currentValueV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart then
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Match-bind arm readability: the scrutinee of an enclosing switch may be
    referenced by its arm bodies across the (dominating) scrut-block boundary.
    All other cross-block reads still fail at the effect boundary. -/
private def currentValueWithArmsV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart && !armReadables.contains id then
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Width-dispatch for UInt body ops. Field never routes here. -/
private def mkCheckedAdd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedAdd l r else .narrowCheckedAdd w l r
private def mkCheckedSub (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedSub l r else .narrowCheckedSub w l r
private def mkCheckedMul (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedMul l r else .narrowCheckedMul w l r
private def mkCheckedDiv (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedDiv l r else .narrowCheckedDiv w l r
private def mkCheckedMod (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedMod l r else .narrowCheckedMod w l r
private def mkBitAnd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitAnd l r else .narrowBitAnd w l r
private def mkBitOr (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitOr l r else .narrowBitOr w l r
private def mkBitXor (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitXor l r else .narrowBitXor w l r
private def mkBitNot (w : Nat) (o : Expr) : Expr :=
  if w == 64 then .bitNot o else .narrowBitNot w o
private def mkShl (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .shl l r else .narrowShl w l r
private def mkShr (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .shr l r else .narrowShr w l r

private def makeTreeValueV1
    (expr : Expr) (kind : NoirValueKindV1)
    (lhsId rhsId : ValueIdV1) (lhs rhs : LoweredValueV1) :
    CompileResult LoweredValueV1 := do
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr
    kind
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  if lhs.kind == .field && rhs.kind == .field then
    makeTreeValueV1 (.fieldAdd lhs.expr rhs.expr) .field lhsId rhsId lhs rhs
  else if lhs.kind == .int64 && rhs.kind == .int64 then
    makeTreeValueV1 (.checkedAdd lhs.expr rhs.expr) .int64 lhsId rhsId lhs rhs
  else
    match widthOfUintKindV1 lhs.kind, widthOfUintKindV1 rhs.kind with
    | some w, some w2 =>
        unless w == w2 do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: checked add UInt widths must match"
        makeTreeValueV1 (mkCheckedAdd w lhs.expr rhs.expr) lhs.kind lhsId rhsId lhs rhs
    | _, _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: checked add operands must be admitted UInt, Int64, or Field"

private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  if lhs.kind == .field && rhs.kind == .field then
    makeTreeValueV1 (.fieldSub lhs.expr rhs.expr) .field lhsId rhsId lhs rhs
  else if lhs.kind == .int64 && rhs.kind == .int64 then
    makeTreeValueV1 (.checkedSub lhs.expr rhs.expr) .int64 lhsId rhsId lhs rhs
  else
    match widthOfUintKindV1 lhs.kind, widthOfUintKindV1 rhs.kind with
    | some w, some w2 =>
        unless w == w2 do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: checked sub UInt widths must match"
        makeTreeValueV1 (mkCheckedSub w lhs.expr rhs.expr) lhs.kind lhsId rhsId lhs rhs
    | _, _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: checked sub operands must be admitted UInt, Int64, or Field"

private def binaryOpToComparisonV1 : BinaryOpV1 → Option ComparisonOp
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

/-- Generic checked-arithmetic value constructor for mul/div/mod (add/sub
    keep their historical constructors above). UInt64/Int64/Field (Field only
    for mul/div — Field mod is rejected by the caller). -/
private def makeArithValueV1 (label : String)
    (mkUint : Nat → Expr → Expr → Expr)
    (mkField : Option (Expr → Expr → Expr))
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  if lhs.kind == .field && rhs.kind == .field then
    match mkField with
    | some mk => makeTreeValueV1 (mk lhs.expr rhs.expr) .field lhsId rhsId lhs rhs
    | none =>
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: Field does not support {label}"
  else if lhs.kind == .int64 && rhs.kind == .int64 then
    -- Int64 uses historical w=64 constructors (mkUint 64 → checked*).
    makeTreeValueV1 (mkUint 64 lhs.expr rhs.expr) .int64 lhsId rhsId lhs rhs
  else
    match widthOfUintKindV1 lhs.kind, widthOfUintKindV1 rhs.kind with
    | some w, some w2 =>
        unless w == w2 do
          throw <| .planInvariant .noir
            s!"unsupported Noir semantic shape: {label} UInt widths must match"
        makeTreeValueV1 (mkUint w lhs.expr rhs.expr) lhs.kind lhsId rhsId lhs rhs
    | _, _ =>
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: {label} operands must be admitted UInt, Int64, or Field"

/-- bitNot value: UInt64 in/out, pure (no failure constraint). -/
private def makeBitNotValueV1 (operandId : ValueIdV1) (operand : LoweredValueV1) :
    CompileResult LoweredValueV1 := do
  let some w := widthOfUintKindV1 operand.kind |
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: bit-not operand must be admitted UInt"
  if 1 + operand.depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mkBitNot w operand.expr
    kind := operand.kind
    depth := 1 + operand.depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
  }

/-- boolNot value: Bool in/out, pure (no failure constraint). -/
private def makeBoolNotValueV1 (operandId : ValueIdV1) (operand : LoweredValueV1) :
    CompileResult LoweredValueV1 := do
  unless operand.kind == .bool do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: bool-not operand must be Bool"
  if 1 + operand.depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := .boolNot operand.expr
    kind := .bool
    depth := 1 + operand.depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
  }

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  -- Ordering: UInt64/Int64 only. Equality: also Field (canonical typed equality).
  let isEq := op == .eq || op == .ne
  let sameUint :=
    match widthOfUintKindV1 lhs.kind, widthOfUintKindV1 rhs.kind with
    | some w, some w2 => w == w2
    | _, _ => false
  let ok :=
    sameUint ||
    (lhs.kind == .int64 && rhs.kind == .int64) ||
    (isEq && lhs.kind == .field && rhs.kind == .field)
  unless ok do
    throw <| .planInvariant .noir
      (if isEq then
        "unsupported Noir semantic shape: equality operands must be admitted UInt, Int64, or Field"
      else
        "unsupported Noir semantic shape: ordering operands must be admitted UInt or Int64")
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := if lhs.kind == .int64 then .signedCompare op lhs.expr rhs.expr
      else .compare op lhs.expr rhs.expr
    kind := .bool
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def consumeCurrentSegmentV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (armReadables : Array ValueIdV1)
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
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        -- Block params and arm/loop-whitelisted values are external roots
        -- (like callable params), not segment-local instructions.
        if dependencyIndex >= paramCount && !armReadables.contains dependency then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: dead or reordered value instructions"
  pure rootValue.expr

/-- Multi-root effect-boundary consumption (event/revert argument lists):
    every value produced in the current segment must be reachable from at
    least one sink root, mirroring the single-root discipline. -/
private def consumeSegmentRootsV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (roots : Array ValueIdV1) : CompileResult Unit := do
  for root in roots do
    let _ ← currentValueV1 values paramCount segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  for root in roots do
    if root.toNat >= paramCount then
      stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount && !armReadables.contains dependency then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: dead or reordered value instructions"
  pure ()

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: result ValueId/type is not canonical for the instruction"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .noir s!"Noir value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

/-- Bitwise binary value: UInt64 in/out, pure (no failure constraint). -/
private def makeBitwiseValueV1 (label : String)
    (mkUint : Nat → Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  match widthOfUintKindV1 lhs.kind, widthOfUintKindV1 rhs.kind with
  | some w, some w2 =>
      unless w == w2 do
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: {label} UInt widths must match"
      makeTreeValueV1 (mkUint w lhs.expr rhs.expr) lhs.kind lhsId rhsId lhs rhs
  | _, _ =>
      throw <| .planInvariant .noir
        s!"unsupported Noir semantic shape: {label} operands must be admitted UInt"

/-- Strict Bool binary value: Bool in/out, pure (no failure constraint). -/
private def makeBoolBinaryValueV1 (label : String)
    (mkExpr : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == .bool && rhs.kind == .bool do
    throw <| .planInvariant .noir
      s!"unsupported Noir semantic shape: {label} operands must be Bool"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mkExpr lhs.expr rhs.expr
    kind := .bool
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

/-- Shift value: UInt64 operand; the count must already be a literal in this
    pilot (UInt32 values arise only from literal arithmetic, which the
    relation layer constant-folds into the guard-and-multiply/divide form). -/
private def makeShiftValueV1 (label : String)
    (mkUint : Nat → Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  let some w := widthOfUintKindV1 lhs.kind |
    throw <| .planInvariant .noir
      s!"unsupported Noir semantic shape: {label} operand must be admitted UInt"
  -- Count may be any admitted UInt width (literal / UInt32 composition).
  unless (widthOfUintKindV1 rhs.kind).isSome do
    throw <| .planInvariant .noir
      s!"unsupported Noir semantic shape: {label} count must be admitted UInt"
  makeTreeValueV1 (mkUint w lhs.expr rhs.expr) lhs.kind lhsId rhsId lhs rhs

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement

/-- `returnKind = none` for initializer (no return value). For entry/view it is
    the admitted result kind (UInt64 or Bool) and must match the returned value. -/
private structure LoweredBlockV1 where
  statements : Array Statement
  values : Array LoweredValueV1
  segmentStart : Nat

/-- Lower one block's instruction sequence (terminator handled by the region
    walker). Each block starts a fresh effect segment; values from dominating
    blocks stay referenceable only via params or match-arm scrutinees. -/
private def lowerBlockInstructionsV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : NoirTypeClosureV1)
    (layout : NoirLowerLayoutV1)
    (fnSigs : Array FnSigV1)
    (paramCount : Nat)
    (armReadables : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  -- Block params (loop induction variables) are pre-seeded by lowerCallableV1
  -- and read through the values array like callable params.
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .noir
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let mut segmentStart := values0.size
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if types.int64TypeId == some typeId then
          let value ← decodeInt64LiteralLe noirPlanErr "Noir" bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            kind := .int64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else if types.boolTypeId == some typeId then
          let value ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            kind := .bool
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else
          match types.uintWidthOf typeId with
          | some w =>
              -- T8d: admitted body UInt{8,16,32,64} literals retain semantic width.
              unless isNoirBodyUintWidth w do
                throw <| .planInvariant .noir
                  s!"unsupported Noir semantic shape: UInt{w} literal is not admitted"
              let some kind := uintKindOfWidthV1 w |
                throw <| .planInvariant .noir
                  s!"unsupported Noir semantic shape: UInt{w} literal is not admitted"
              let value ← decodeUIntWidthLiteralLe noirPlanErr "Noir" w bytes
              values := ← appendResultValueV1 typeId values result {
                expr := .literal value
                kind
                depth := 1
                expandedNodes := 1
                dependencies := #[]
              }
          | none =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: literal is not UInt{8,16,32,64}, Int64, or Bool"
    | .stateLoad stateId, some result =>
        let leaves ← findStateLeavesV1 layout stateId
        if types.isNamedAggregate result.typeId then
          let specs ← flattenTypeLeafSpecsV1 layout.typeDecls types result.typeId "state"
          unless specs.size == leaves.size do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: aggregate state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          let mut leafIsInt : Array Bool := #[]
          for i in [0:leaves.size] do
            let some fieldIndex := leaves[i]? |
              throw <| .planInvariant .noir "aggregate state load leaf missing"
            let some (_, isInt) := specs[i]? |
              throw <| .planInvariant .noir "aggregate state load spec missing"
            leafExprs := leafExprs.push (.stateLoad fieldIndex)
            leafIsInt := leafIsInt.push isInt
          let value := mkAggregateValueV1 leafExprs leafIsInt #[] 1 leaves.size
          values := ← appendResultValueV1 result.typeId values result value
        else
          unless leaves.size == 1 do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: scalar state load targets multi-leaf state"
          let some fieldIndex := leaves[0]? |
            throw <| .planInvariant .noir "scalar state load leaf missing"
          let isInt := types.int64TypeId == some result.typeId
          let isField := types.isField result.typeId
          let kind ←
            if isField then pure NoirValueKindV1.field
            else if isInt then pure NoirValueKindV1.int64
            else match types.uintWidthOf result.typeId with
              | some w =>
                  unless isNoirBodyUintWidth w do
                    throw <| .planInvariant .noir
                      s!"unsupported Noir semantic shape: state load UInt{w} is not admitted"
                  match uintKindOfWidthV1 w with
                  | some k => pure k
                  | none =>
                      throw <| .planInvariant .noir
                        s!"unsupported Noir semantic shape: state load UInt{w} is not admitted"
              | none =>
                  throw <| .planInvariant .noir
                    "unsupported Noir semantic shape: state load must be UInt{8,16,32,64}, Int64, Field, or named Struct/Enum"
          values := ← appendResultValueV1 result.typeId values result {
            expr := .stateLoad fieldIndex
            kind
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables rhsId
        if op == .add then
          let value ← makeCheckedAddValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .sub then
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .mul then
          let value ← makeArithValueV1 "checked mul" mkCheckedMul (some Expr.fieldMul)
            lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .div then
          let value ← makeArithValueV1 "checked div" mkCheckedDiv (some Expr.fieldDiv)
            lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .mod then
          let value ← makeArithValueV1 "checked mod" mkCheckedMod none
            lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .bitAnd then
          let value ← makeBitwiseValueV1 "bitwise and" mkBitAnd lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .bitOr then
          let value ← makeBitwiseValueV1 "bitwise or" mkBitOr lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .bitXor then
          let value ← makeBitwiseValueV1 "bitwise xor" mkBitXor lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .shl then
          let value ← makeShiftValueV1 "shift left" mkShl lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .shr then
          let value ← makeShiftValueV1 "shift right" mkShr lhsId rhsId lhs rhs
          values := ← appendResultValueV1 result.typeId values result value
        else if op == .and || op == .or then
          let boolTypeId ← match types.boolTypeId with
            | some value => pure value
            | none => throw (.planInvariant .noir
                "unsupported Noir semantic shape: logical operator requires interned Bool type")
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: logical operator result must be Bool"
          let value ←
            if op == .and then
              makeBoolBinaryValueV1 "logical and" Expr.boolAnd lhsId rhsId lhs rhs
            else
              makeBoolBinaryValueV1 "logical or" Expr.boolOr lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        else
          match binaryOpToComparisonV1 op with
          | some comparison =>
              let boolTypeId ← match types.boolTypeId with
                | some value => pure value
                | none => throw (.planInvariant .noir
                    "unsupported Noir semantic shape: comparison requires interned Bool type")
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: comparison result must be Bool"
              let value ← makeCompareValueV1 comparison lhsId rhsId lhs rhs
              values := ← appendResultValueV1 boolTypeId values result value
          | none =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: only checked UInt{8,16,32,64}/Int64/Field arithmetic, bitwise, shift, comparison, and logical operators are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values paramCount segmentStart armReadables operandId
        match op with
        | .neg =>
            if operand.kind == .int64 then
              let tid ← match types.int64TypeId with
                | some t => pure t
                | none => throw (.planInvariant .noir
                    "unsupported Noir semantic shape: Int64 type is missing for neg")
              unless result.typeId == tid do
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: checkedNeg result must be Int64"
              if 1 + operand.depth > maxExprDepth then
                throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
              if operand.expandedNodes > maxPlanNodes - 1 then
                throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
              let value : LoweredValueV1 := {
                expr := .checkedNeg operand.expr
                kind := .int64
                depth := 1 + operand.depth
                expandedNodes := 1 + operand.expandedNodes
                dependencies := #[operandId]
              }
              values := ← appendResultValueV1 tid values result value
            else if operand.kind == .field then
              let tid ← match types.fieldTypeId with
                | some t => pure t
                | none => throw (.planInvariant .noir
                    "unsupported Noir semantic shape: Field type is missing for neg")
              unless result.typeId == tid do
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: fieldNeg result must be Field"
              if 1 + operand.depth > maxExprDepth then
                throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
              if operand.expandedNodes > maxPlanNodes - 1 then
                throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
              let value : LoweredValueV1 := {
                expr := .fieldNeg operand.expr
                kind := .field
                depth := 1 + operand.depth
                expandedNodes := 1 + operand.expandedNodes
                dependencies := #[operandId]
              }
              values := ← appendResultValueV1 tid values result value
            else
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: Op.Unary.neg requires Int64 or Field"
        | .bitNot =>
            let value ← makeBitNotValueV1 operandId operand
            values := ← appendResultValueV1 types.uint64TypeId values result value
        | .not =>
            let boolTypeId ← match types.boolTypeId with
              | some value => pure value
              | none => throw (.planInvariant .noir
                  "unsupported Noir semantic shape: bool-not requires interned Bool type")
            unless result.typeId == boolTypeId do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: bool-not result must be Bool"
            let value ← makeBoolNotValueV1 operandId operand
            values := ← appendResultValueV1 boolTypeId values result value
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: view callable writes state"
        let leaves ← findStateLeavesV1 layout stateId
        let stored ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
        -- Consume the whole segment via the stored value's dependency closure
        -- (works for both scalar and aggregate roots).
        let _ ← consumeCurrentSegmentV1 values paramCount segmentStart armReadables valueId
        if stored.isAggregate then
          let leafExprs := stored.leafExprs
          unless leafExprs.size == leaves.size do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: aggregate state store leaf count mismatch"
          for i in [0:leaves.size] do
            let some fieldIndex := leaves[i]? |
              throw <| .planInvariant .noir "aggregate store leaf missing"
            let some expr := leafExprs[i]? |
              throw <| .planInvariant .noir "aggregate store leaf expr missing"
            body := body.push (.store { fieldIndex, value := expr })
        else
          unless leaves.size == 1 do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: scalar store targets multi-leaf state"
          -- T8d: store accepts matching UInt width / Int64 / Field.
          unless (widthOfUintKindV1 stored.kind).isSome ||
              stored.kind == .int64 || stored.kind == .field do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: state store value must be admitted UInt, Int64, Field, or named Struct/Enum"
          let some fieldIndex := leaves[0]? |
            throw <| .planInvariant .noir "scalar store leaf missing"
          body := body.push (.store { fieldIndex, value := stored.expr })
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: assert must use errorId=none and empty args"
        let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables condId
        unless root.kind == .bool do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: assert condition must be Bool"
        let condition ← consumeCurrentSegmentV1 values paramCount segmentStart armReadables condId
        body := body.push (.assert condition)
        segmentStart := values.size
    | .emit effectId eventId argIds, none =>
        if mode == .view then
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: view callable emits an event"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values paramCount segmentStart armReadables argIds
        body := body.push (.emitEvent effectId.toNat eventId.toNat argExprs)
        segmentStart := values.size
    | .externalCall effectId qname argIds, none =>
        if mode == .view then
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: view callable makes an external call"
        unless qname.components.toArray.size ≥ 2 do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: external call callee must have at least two components"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: external call arguments must be UInt64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values paramCount segmentStart armReadables argIds
        body := body.push (.externalCall effectId.toNat qname.components.toArray argExprs)
        segmentStart := values.size
    | .schedule effectId qname argIds, none =>
        if mode == .view then
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: view callable schedules a workflow"
        unless qname.components.toArray.size ≥ 2 do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: schedule callee must have at least two components"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: schedule arguments must be UInt64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values paramCount segmentStart armReadables argIds
        body := body.push (.schedule effectId.toNat qname.components.toArray argExprs)
        segmentStart := values.size
    | .pureCall callableId argIds, some result =>
        let some fnSig := fnSigs.find? (fun sig => sig.callableId == callableId.toNat) |
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: pure call target is not a declared fn"
        unless argIds.size == fnSig.paramCount do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: pure call argument count mismatch"
        let mut argExprs : Array Expr := #[]
        let mut maxDepth := 0
        let mut expanded := 1
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless root.kind == .uint64 || root.kind == .int64 || root.kind == .field do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: pure call arguments must be UInt64, Int64, or Field"
          argExprs := argExprs.push root.expr
          maxDepth := max maxDepth root.depth
          if expanded > maxPlanNodes - 1 - root.expandedNodes then
            throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
          expanded := expanded + root.expandedNodes
        -- Pure expression: the segment continues (no effect boundary).
        let resultKind : NoirValueKindV1 :=
          if fnSig.resultIsBool then .bool
          else if types.isField result.typeId then .field
          else if types.int64TypeId == some result.typeId then .int64
          else .uint64
        let resultTypeId ← match resultKind with
          | .uint64 => pure types.uint64TypeId
          | .uint8 | .uint16 | .uint32 =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: pureCall result cannot be narrow UInt"
          | .int64 =>
              match types.int64TypeId with
              | some tid => pure tid
              | none => throw (.planInvariant .noir
                  "unsupported Noir semantic shape: Int64 type is missing for pureCall")
          | .field =>
              match types.fieldTypeId with
              | some tid => pure tid
              | none => throw (.planInvariant .noir
                  "unsupported Noir semantic shape: Field type is missing for pureCall")
          | .bool =>
              match types.boolTypeId with
              | some boolTid => pure boolTid
              | none =>
                  throw <| .planInvariant .noir
                    "unsupported Noir semantic shape: Bool fn result requires interned Bool type"
          | .aggregate =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: pureCall result cannot be a named aggregate"
        values := ← appendResultValueV1 resultTypeId values result {
          expr := .callFn callableId.toNat argExprs
          kind := resultKind
          depth := 1 + maxDepth
          expandedNodes := expanded
          dependencies := argIds
        }
    -- NoirAggregate: named Struct/Enum construct + field/variant ops as
    -- circuit-native leaf assembly (public-input flatten; no container ops).
    | .construct typeId ctorIdx argIds, some result => do
        unless result.typeId == typeId do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: construct result typeId must match op typeId"
        unless types.isNamedAggregate typeId do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: construct requires named Struct/Enum (Array/Map/Bytes/Option containers are outside the Noir pilot)"
        let some decl := layout.typeDecls[typeId.toNat]? |
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: construct TypeDecl missing"
        match decl.shape with
        | .struct fields => do
            unless ctorIdx.toNat == 0 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: struct construct ctorIdx must be 0"
            unless argIds.size == fields.size do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: struct construct arity mismatch"
            let mut leaves : Array Expr := #[]
            let mut leafIsInt : Array Bool := #[]
            let mut deps : Array ValueIdV1 := #[]
            let mut depth : Nat := 1
            let mut nodes : Nat := 1
            for i in [0:argIds.size] do
              let some argId := argIds[i]? |
                throw <| .planInvariant .noir "struct construct arg missing"
              let some field := fields[i]? |
                throw <| .planInvariant .noir "struct construct field missing"
              let arg ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
              let expectedLeaves ← leafCountOfTypeV1 layout.typeDecls types field.typeId
              let argLeaves := arg.leafExprs
              let argIsInt := arg.leafIsInts
              unless argLeaves.size == expectedLeaves do
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: struct construct field leaf count mismatch"
              leaves := leaves ++ argLeaves
              leafIsInt := leafIsInt ++ argIsInt
              deps := deps.push argId
              depth := Nat.max depth (arg.depth + 1)
              nodes := nodes + arg.expandedNodes
            let value := mkAggregateValueV1 leaves leafIsInt deps depth nodes
            values := ← appendResultValueV1 typeId values result value
        | .enum variants => do
            let vi := ctorIdx.toNat
            let some variant := variants[vi]? |
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: enum construct variant out of range"
            unless argIds.size == variant.payloadTypes.size do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: enum construct arity mismatch"
            let maxPay ← enumMaxPayloadLeavesV1 layout.typeDecls types variants
            let mut leaves : Array Expr := #[.literal (UInt64.ofNat vi)]
            let mut leafIsInt : Array Bool := #[false]
            let mut deps : Array ValueIdV1 := #[]
            let mut depth : Nat := 1
            let mut nodes : Nat := 1
            for i in [0:argIds.size] do
              let some argId := argIds[i]? |
                throw <| .planInvariant .noir "enum construct arg missing"
              let some pt := variant.payloadTypes[i]? |
                throw <| .planInvariant .noir "enum construct payload type missing"
              let arg ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
              let expectedLeaves ← leafCountOfTypeV1 layout.typeDecls types pt
              let argLeaves := arg.leafExprs
              let argIsInt := arg.leafIsInts
              unless argLeaves.size == expectedLeaves do
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: enum construct payload leaf count mismatch"
              leaves := leaves ++ argLeaves
              leafIsInt := leafIsInt ++ argIsInt
              deps := deps.push argId
              depth := Nat.max depth (arg.depth + 1)
              nodes := nodes + arg.expandedNodes
            while leaves.size < 1 + maxPay do
              leaves := leaves.push (.literal 0)
              leafIsInt := leafIsInt.push false
            let value := mkAggregateValueV1 leaves leafIsInt deps depth nodes
            values := ← appendResultValueV1 typeId values result value
        | _ =>
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: construct requires Struct or Enum shape"
    | .fieldGet baseId fieldIndex, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fieldGet base must be a named aggregate"
        let baseLeaves := base.leafExprs
        let baseIsInt := base.leafIsInts
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          match layout.typeDecls[tid.toNat]? with
          | some { shape := .struct fields, .. } => do
              let total ← leafCountOfTypeV1 layout.typeDecls types tid
              if total == baseLeaves.size && fieldIndex.toNat < fields.size then
                match fields[fieldIndex.toNat]? with
                | some f =>
                    if f.typeId == result.typeId then
                      let (s, l) ←
                        structFieldLeafRangeV1 layout.typeDecls types fields
                          fieldIndex.toNat
                      hit := some (s, l)
                | none => pure ()
          | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: fieldGet could not resolve struct field range"
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fieldGet leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        let mut outIsInt : Array Bool := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .noir "fieldGet leaf missing"
          let some b := baseIsInt[i]? |
            throw <| .planInvariant .noir "fieldGet leaf isInt missing"
          outLeaves := outLeaves.push e
          outIsInt := outIsInt.push b
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves outIsInt #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .noir "fieldGet scalar leaf missing"
            let isInt := match outIsInt[0]? with | some b => b | none => false
            pure {
              expr := e0
              kind := if isInt then NoirValueKindV1.int64 else .uint64
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId]
            }
        values := ← appendResultValueV1 result.typeId values result value
    | .fieldSet baseId fieldIndex valueId, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        let val ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
        unless base.isAggregate do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fieldSet base must be a named aggregate"
        unless types.isNamedAggregate result.typeId do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fieldSet result must be named aggregate"
        let baseLeaves := base.leafExprs
        let baseIsInt := base.leafIsInts
        let valLeaves := val.leafExprs
        let valIsInt := val.leafIsInts
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          if tid == result.typeId then
            match layout.typeDecls[tid.toNat]? with
            | some { shape := .struct fields, .. } => do
                if fieldIndex.toNat < fields.size then
                  let (s, l) ←
                    structFieldLeafRangeV1 layout.typeDecls types fields fieldIndex.toNat
                  hit := some (s, l)
            | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: fieldSet could not resolve struct field range"
        unless start + len <= baseLeaves.size && valLeaves.size == len do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: fieldSet leaf range/value size mismatch"
        let mut outLeaves : Array Expr := #[]
        let mut outIsInt : Array Bool := #[]
        for i in [0:baseLeaves.size] do
          if i >= start && i < start + len then
            let j := i - start
            let some e := valLeaves[j]? |
              throw <| .planInvariant .noir "fieldSet value leaf missing"
            let some b := valIsInt[j]? |
              throw <| .planInvariant .noir "fieldSet value isInt missing"
            outLeaves := outLeaves.push e
            outIsInt := outIsInt.push b
          else
            let some e := baseLeaves[i]? |
              throw <| .planInvariant .noir "fieldSet base leaf missing"
            let some b := baseIsInt[i]? |
              throw <| .planInvariant .noir "fieldSet base isInt missing"
            outLeaves := outLeaves.push e
            outIsInt := outIsInt.push b
        let value := mkAggregateValueV1 outLeaves outIsInt #[baseId, valueId]
          (Nat.max base.depth val.depth + 1)
          (base.expandedNodes + val.expandedNodes + 1)
        values := ← appendResultValueV1 result.typeId values result value
    | .variantTag baseId, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: variantTag base must be a named Enum aggregate"
        let kind ← match types.uintWidthOf result.typeId with
          | some 32 => pure NoirValueKindV1.uint32
          | some 64 => pure NoirValueKindV1.uint64
          | _ =>
              if result.typeId == types.uint64TypeId then pure NoirValueKindV1.uint64
              else
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: variantTag result must be UInt32"
        let some tagExpr := base.leafExprs[0]? |
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: variantTag enum has no tag leaf"
        values := ← appendResultValueV1 result.typeId values result {
          expr := tagExpr
          kind
          depth := base.depth + 1
          expandedNodes := base.expandedNodes + 1
          dependencies := #[baseId]
        }
    | .variantPayload baseId variantIndex payloadIndex, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: variantPayload base must be a named Enum"
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          match layout.typeDecls[tid.toNat]? with
          | some { shape := .enum variants, .. } => do
              let total ← leafCountOfTypeV1 layout.typeDecls types tid
              if total == base.leafExprs.size then
                let (s, l) ← enumPayloadLeafRangeV1 layout.typeDecls types variants
                  variantIndex.toNat payloadIndex.toNat
                hit := some (s + 1, l)
          | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: variantPayload could not resolve range"
        let baseLeaves := base.leafExprs
        let baseIsInt := base.leafIsInts
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: variantPayload leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        let mut outIsInt : Array Bool := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .noir "variantPayload leaf missing"
          let some b := baseIsInt[i]? |
            throw <| .planInvariant .noir "variantPayload isInt missing"
          outLeaves := outLeaves.push e
          outIsInt := outIsInt.push b
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves outIsInt #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .noir "variantPayload scalar missing"
            let isInt := match outIsInt[0]? with | some b => b | none => false
            pure {
              expr := e0
              kind := if isInt then NoirValueKindV1.int64 else .uint64
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId]
            }
        values := ← appendResultValueV1 result.typeId values result value
    | .indexGet .., some _ | .indexSet .., some _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: IndexGet/IndexSet are outside the Noir pilot (anonymous Array/Map/Bytes containers fail closed)"
    -- N5: Noir declines Commit (commitment labels have no relation-slot
    -- representation under N1 public-input policy) and ContextRead (no clock).
    | .commit .., some _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: Commit is not admitted by pilot context policy (commitment labels are not representable as public relation slots)"
    | .contextRead key, some _ =>
        unless key == unixTimeSecondsContextKeyV1 do
          throw <| .planInvariant .noir
            s!"unsupported Noir semantic shape: unknown ContextRead key '{key.value}'"
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: ContextRead is not admitted by pilot context policy"
    | _, _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: instruction op/result is outside the current UInt64 pilot"
  pure { statements := body, values, segmentStart }

/-- Decode a switch case constant against the scrutinee kind. -/
private def decodeSwitchCaseValueV1 (scrutIsBool : Bool) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if scrutIsBool then
    decodeBoolLiteralV1 bytes
  else
    decodeUInt64LiteralV1 bytes

/-- Structured emission of the forward-only multi-block CFG. Diamonds
    (branch/switch) are recovered by following each arm to its exit jump or
    return; convergent joins continue the region. The fuel bounds recursion
    to the block count. Returns (statements, values, nextJoin). -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : NoirTypeClosureV1)
    (layout : NoirLowerLayoutV1)
    (fnSigs : Array FnSigV1)
    (returnKind : Option NoirValueKindV1)
    (blocks : Array BlockV1)
    (loops : Array LoopBoundV1)
    (paramCount : Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × Option Nat × Option (Array Expr)) := do
  if fuel == 0 then
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: CFG region exceeds block bound"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .noir
        "unsupported Noir semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: block ids are not dense"
  let lowered ← lowerBlockInstructionsV1
    owner mode types layout fnSigs paramCount armReadables block values0
  let instrs := lowered.statements
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  match block.terminator with
  | .return_ (some valueId) =>
      match mode with
      | .initialize =>
          throw <| .planInvariant .noir "initializer relation cannot return a value"
      | .mutate | .view =>
          let expectedKind ← match returnKind with
            | some kind => pure kind
            | none =>
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: entry/view return kind is missing"
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
          unless root.kind == expectedKind do
            throw <| .planInvariant .noir
              s!"unsupported Noir semantic shape: return value kind is not consistent with the {owner} result type"
          let value ← consumeCurrentSegmentV1 values paramCount segmentStart armReadables valueId
          pure (instrs.push (.returnValue value), values, none, none)
  | .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, none, none)
  | .jump target =>
      match loops.find? (fun lb => lb.header == target.blockId) with
      | none =>
          unless segmentStart == values.size do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: block has unconsumed values"
          pure (instrs, values, some target.blockId.toNat, none)
      | some lb =>
          if target.blockId.toNat == start then
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: loop header cannot be its own latch"
          else if target.blockId.toNat < start then
            -- Back edge: the latch jumps back to the header. The update
            -- expression travels on the back-edge channel to the enclosing
            -- loop-entry; it never fires inside a region arm.
            unless target.args.size == 1 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: loop latch must carry exactly one argument"
            let updateId := target.args[0]!
            let updateRoot ← currentValueWithArmsV1 values paramCount segmentStart armReadables updateId
            unless updateRoot.kind == .uint64 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: loop update must be UInt64"
            let _ ← consumeSegmentRootsV1 values paramCount segmentStart armReadables target.args
            pure (instrs, values, none, some #[updateRoot.expr])
          else do
            -- Loop entry: the forward jump into the header carries the
            -- initial induction value. Everything the loop reads from the
            -- pre-header (initial value, end expression, enclosing lets)
            -- stays readable through the loop whitelist.
            let some header := blocks[target.blockId.toNat]? |
              throw (.planInvariant .noir
                "unsupported Noir semantic shape: loop header block is missing")
            unless header.params.size == 1 && target.args.size == 1 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: loop header must carry exactly one parameter"
            let some headerParam := header.params[0]? |
              throw (.planInvariant .noir
                "unsupported Noir semantic shape: loop header parameter is missing")
            unless headerParam.typeId == types.uint64TypeId do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: loop induction variable must be UInt64"
            let initId := target.args[0]!
            let initRoot ← currentValueWithArmsV1 values paramCount segmentStart armReadables initId
            unless initRoot.kind == .uint64 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: loop initial value must be UInt64"
            let segmentIds : Array ValueIdV1 :=
              (List.range (values.size - segmentStart)).toArray.map
                (fun i => UInt32.ofNat (segmentStart + i))
            let loopReadables := armReadables ++ segmentIds
            let _ ← consumeSegmentRootsV1 values paramCount segmentStart armReadables segmentIds
            -- The induction placeholder's slot is this header's ordinal
            -- among all loop headers (BlockId order).
            let mut slot := 0
            for blk in blocks do
              if blk.id < header.id then
                slot := slot + blk.params.size
            let headerLowered ← lowerBlockInstructionsV1
              owner mode types layout fnSigs paramCount loopReadables header values
            unless headerLowered.statements.isEmpty do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: loop header has side effects"
            let valuesH := headerLowered.values
            let hSegment := headerLowered.segmentStart
            match header.terminator with
            | .branch condId thenT elseT => do
                let condRoot ← currentValueWithArmsV1 valuesH paramCount hSegment loopReadables condId
                unless condRoot.kind == .bool do
                  throw <| .planInvariant .noir
                    "unsupported Noir semantic shape: loop condition must be Bool"
                let cond ← consumeCurrentSegmentV1 valuesH paramCount hSegment loopReadables condId
                let (bodyStmts, valuesB, bodyNext, backEdge) ←
                  emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
                    loopReadables (fuel - 1) thenT.blockId.toNat valuesH
                unless bodyNext.isNone do
                  throw <| .planInvariant .noir
                    "unsupported Noir semantic shape: loop body escapes past its latch"
                let some updateExprs := backEdge |
                  throw (.planInvariant .noir
                    "unsupported Noir semantic shape: loop body does not reach its latch")
                unless updateExprs.size == 1 do
                  throw <| .planInvariant .noir
                    "unsupported Noir semantic shape: loop latch must carry exactly one update"
                let loopStmt := Statement.forLoop slot lb.maxIterations
                  initRoot.expr cond updateExprs[0]! bodyStmts
                -- Continue the enclosing walk at the loop exit; the loop
                -- whitelist stays in scope for post-loop reads of pre-loop
                -- values, and an enclosing latch may still follow (nesting).
                let (rest, valuesX, nextX, backX) ←
                  emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
                    loopReadables (fuel - 1) elseT.blockId.toNat valuesB
                pure (instrs ++ #[loopStmt] ++ rest, valuesX, nextX, backX)
            | _ =>
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: loop header must end in a branch"
  | .branch condId thenT elseT =>
      let condRoot ← currentValueWithArmsV1 values paramCount segmentStart armReadables condId
      unless condRoot.kind == .bool do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values paramCount segmentStart armReadables condId
      let (thenBody, values1, thenNext, thenBack) ←
        emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
          armReadables (fuel - 1) thenT.blockId.toNat values
      unless thenBack.isNone do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: loop back edge escapes a branch arm"
      match thenNext with
      | some j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, next, back2) ←
              emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
                armReadables (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest, values2, next, back2)
          else
            let (elseBody, values2, elseNext, elseBack) ←
              emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
                armReadables (fuel - 1) elseT.blockId.toNat values1
            unless elseBack.isNone do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: loop back edge escapes a branch arm"
            match elseNext with
            | some j2 =>
                unless j == j2 do
                  throw <| .planInvariant .noir
                    "unsupported Noir semantic shape: branch arms converge on divergent joins"
                let (rest, values3, next, back3) ←
                  emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
                    armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, next, back3)
            | none =>
                let (rest, values3, next, back3) ←
                  emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
                    armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, next, back3)
      | none =>
          let (elseBody, values2, elseNext, elseBack) ←
            emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
              armReadables (fuel - 1) elseT.blockId.toNat values1
          pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, elseNext, elseBack)
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables scrutId
      let scrut ← consumeCurrentSegmentV1 values paramCount segmentStart armReadables scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .noir
          "unsupported Noir semantic shape: switch must carry a default target")
      let scrutIsBool := scrutVal.kind == .bool
      let mut caseBodies : Array (UInt64 × Array Statement) := #[]
      let mut joinAcc : Option Nat := none
      let mut valuesA := values
      for switchCase in cases do
        let caseValue ← decodeSwitchCaseValueV1 scrutIsBool switchCase.valueBytes
        let (body, values1, armNext, armBack) ←
          emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
            (armReadables.push scrutId) (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        unless armBack.isNone do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: loop back edge escapes a switch arm"
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        match armNext, joinAcc with
        | none, _ => pure ()
        | some j, none => joinAcc := some j
        | some j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: switch arms converge on divergent joins"
      let (defaultBody, values2, defaultNext, defaultBack) ←
        emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
          (armReadables.push scrutId) (fuel - 1)
          defaultT.blockId.toNat valuesA
      unless defaultBack.isNone do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: loop back edge escapes a switch arm"
      match defaultNext, joinAcc with
      | none, _ => pure ()
      | some j, none => joinAcc := some j
      | some j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: switch arms converge on divergent joins"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody], values2, none, none)
      | some j =>
          let (rest, values3, next, back3) ←
            emitRegionV1 owner mode types layout fnSigs returnKind blocks loops paramCount
              armReadables (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest, values3, next, back3)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
        unless root.kind == .uint64 do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values paramCount segmentStart armReadables argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, none, none)
  | .trap _ =>
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: trap terminators are outside the current pilot"

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (inputOffset : Nat)
    (types : NoirTypeClosureV1)
    (layout : NoirLowerLayoutV1)
    (fnSigs : Array FnSigV1)
    (returnKind : Option NoirValueKindV1)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.invariantSteps.isNone do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: callable must have an entry block 0"
  -- Loop pattern: every loopBounds entry must pair a single-param UInt64
  -- header ending in a branch with a latch jumping back with one argument;
  -- block parameters may appear only on such headers.
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      throw (.planInvariant .noir
        "unsupported Noir semantic shape: loop header block is missing")
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      throw (.planInvariant .noir
        "unsupported Noir semantic shape: loop latch block is missing")
    unless header.params.size == 1 do
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: loop header must carry one UInt64 parameter"
    let some headerParam := header.params[0]? |
      throw (.planInvariant .noir
        "unsupported Noir semantic shape: loop header parameter is missing")
    unless headerParam.typeId == types.uint64TypeId do
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: loop header must carry one UInt64 parameter"
    match header.terminator with
    | .branch .. => pure ()
    | _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: loop header must end in a branch"
    match latch.terminator with
    | .jump target =>
        unless target.blockId == lb.header && target.args.size == 1 do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: loop latch must jump back with one argument"
    | _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: loop latch must jump back to the header"
  for blk in callable.blocks do
    unless blk.params.isEmpty ||
        callable.loopBounds.any (fun lb => lb.header == blk.id) do
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: block parameters are only supported on loop headers"
  let (params, paramValues) ← makeParamsV1 owner inputOffset types layout.typeDecls callable.params
  -- Pre-seed the loop-induction placeholder slots in canonical ValueId
  -- order (callable params, then every block param in BlockId order), so
  -- instruction results keep appending at their canonical positions.
  let mut seedValues : Array LoweredValueV1 := #[]
  for blk in callable.blocks do
    for paramDef in blk.params do
      unless paramDef.valueId.toNat == paramValues.size + seedValues.size do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: block parameter ValueIds are not canonical"
      seedValues := seedValues.push {
        expr := .loopParam seedValues.size
        kind := .uint64
        depth := 1
        expandedNodes := 1
        dependencies := #[]
      }
  let initialValues := paramValues ++ seedValues
  let paramCount := initialValues.size
  let (body0, values0, nextJoin0, back0) ←
    emitRegionV1 owner mode types layout fnSigs returnKind callable.blocks
      callable.loopBounds paramCount #[] callable.blocks.size 0 initialValues
  unless back0.isNone do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: loop back edge escapes the callable entry"
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly
  -- increase outside loop bodies, so this terminates within blocks.size folds.
  let mut body := body0
  let mut values := values0
  let mut nextJoin := nextJoin0
  for _ in [0:callable.blocks.size] do
    match nextJoin with
    | none => break
    | some j =>
        let (rest, values1, next1, back1) ←
          emitRegionV1 owner mode types layout fnSigs returnKind callable.blocks
            callable.loopBounds paramCount #[] callable.blocks.size j values
        unless back1.isNone do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: loop back edge escapes the callable entry"
        body := body ++ rest
        values := values1
        nextJoin := next1
  match nextJoin with
  | some _ =>
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: callable does not end in return on all paths"
  | none => pure ()
  if body.size > maxBodyStatements then
    throw <| .planInvariant .noir s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def resolveEntryViewResultV1
    (types : NoirTypeClosureV1)
    (name : String)
    (callable : CallableV1) : CompileResult (NoirValueKindV1 × InputType) := do
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .noir
      s!"entry '{name}' does not return a public UInt8/16/32/64, Int64, Bool, or Field"
  if types.isField callable.result.typeId then
    pure (.field, .field)
  else
    match types.uintWidthOf callable.result.typeId with
    | some 8 => pure (.uint8, .u8)
    | some 16 => pure (.uint16, .u16)
    | some 32 => pure (.uint32, .u32)
    | some 64 => pure (.uint64, .u64)
    | some _ =>
        throw <| .planInvariant .noir
          s!"entry '{name}' does not return public UInt8/16/32/64, Int64, Bool, or Field"
    | none =>
        if types.int64TypeId == some callable.result.typeId then
          pure (.int64, .u64)
        else if types.boolTypeId == some callable.result.typeId then
          pure (.bool, .bool)
        else
          throw <| .planInvariant .noir
            s!"entry '{name}' does not return public UInt8/16/32/64, Int64, Bool, or Field"

private def makeRelationV1
    (index : Nat)
    (types : NoirTypeClosureV1)
    (layout : NoirLowerLayoutV1)
    (fnSigs : Array FnSigV1)
    (name : String)
    (mode : RelationMode)
    (callable : CallableV1) : CompileResult Relation := do
  unless isIdentifier name do
    throw <| .planInvariant .noir s!"relation name '{name}' is not a safe identifier"
  let states := layout.fields
  let (returnKind, resultType) : Option NoirValueKindV1 × InputType ←
    if mode == .initialize then
      unless callable.name.isNone && callable.result.visibility == .public_ do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: initializer signature is invalid"
      let unitTypeId ← match types.unitTypeId with
        | some value => pure value
        | none => throw (.planInvariant .noir
            "unsupported Noir semantic shape: initializer Unit type is missing")
      unless callable.result.typeId == unitTypeId do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: initializer result is not Unit"
      pure (none, .u64)
    else
      let (kind, inputTy) ← resolveEntryViewResultV1 types name callable
      pure (some kind, inputTy)
  let inputOffset := if states.isEmpty then 0 else
    1 + (if mode == .initialize then 0 else states.size)
  let semanticMode : SemanticCallableModeV1 := match mode with
    | .initialize => .initialize
    | .mutate => .mutate
    | .view => .view
  let lowered ← lowerCallableV1 s!"relation '{name}'" semanticMode inputOffset
    types layout fnSigs returnKind callable
  pure {
    index
    name
    artifactStem := artifactStem index mode name
    mode
    params := lowered.params
    inputs := makeInputsV1 states mode lowered.params resultType
      (collectEmitSlots lowered.body) (collectCallSlots lowered.body)
      (collectScheduleSlots lowered.body)
    body := lowered.body
  }
private def makeInterfaceBindingV1 (label : String) (name : String)
    (fields : Array InterfaceFieldV1) (uint64TypeId : TypeIdV1) :
    CompileResult InterfaceBinding := do
  unless isIdentifier name do
    throw <| .planInvariant .noir
      s!"unsupported Noir semantic shape: {label} name '{name}' is not a safe identifier"
  for field in fields do
    unless field.typeId == uint64TypeId && field.visibility == .public_ do
      throw <| .planInvariant .noir
        s!"unsupported Noir semantic shape: {label} '{name}' fields must be public UInt64"
  pure { name, fieldCount := fields.size }

/-- Noir-private retained SemanticProgramV1 data → target-owned Plan pilot.
    Name/source/semantic identity comes from the same non-alpha compiled carrier;
    hash strings are derived from sourceHashV1/semanticHashV1 digests. -/

private def makePlanFromSemanticDataV1
    (artifactProgramName sourceHash semanticHash : String)
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.invariants.isEmpty then
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: constants/invariants are outside the current UInt64 pilot"
  if source.callables.size > maxRelations then
    throw <| .planInvariant .noir s!"callable count exceeds Noir profile limit {maxRelations}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .noir
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateNoirTypeClosureV1 source.types
  let layout ← makeStateLayoutV1 types source.types source.logicalState
  let states := layout.fields
  let events ← source.events.mapM (fun d =>
    makeInterfaceBindingV1 "event" d.name d.fields types.uint64TypeId)
  let errors ← source.errors.mapM (fun d =>
    makeInterfaceBindingV1 "error" d.name d.fields types.uint64TypeId)
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  unless programName == artifactProgramName do
    throw <| .planInvariant .noir
      "retained SemanticProgramV1 name diverges from compiled artifact identity"
  let mut initializer : Option CallableV1 := none
  let mut entries : Array CallableV1 := #[]
  -- Pass 1: collect validated fn signatures keyed by GLOBAL callable id, so
  -- bodies lowered in pass 2 can resolve pure calls to any declared fn
  -- (including later-declared ones) with exact arity/result kinds.
  let mut fnSigs : Array FnSigV1 := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .noir "semantic program has multiple initializers"
        initializer := some callable
    | .entry | .view => entries := entries.push callable
    | .pureFn =>
        let fnName ← match callable.name with
          | some value => pure value
          | none => throw (.planInvariant .noir
              "unsupported Noir semantic shape: pure fn is missing its name")
        unless isIdentifier fnName do
          throw <| .planInvariant .noir
            s!"unsupported Noir semantic shape: fn name '{fnName}' is not a safe identifier"
        let resultIsBool ←
          if callable.result.typeId == types.uint64TypeId ||
              types.int64TypeId == some callable.result.typeId ||
              types.isField callable.result.typeId then
            pure false
          else if types.boolTypeId == some callable.result.typeId then
            pure true
          else
            throw <| .planInvariant .noir
              s!"unsupported Noir semantic shape: fn '{fnName}' result is not UInt64, Int64, Bool, or Field"
        unless callable.result.visibility == .public_ do
          throw <| .planInvariant .noir
            s!"unsupported Noir semantic shape: fn '{fnName}' result is not public"
        fnSigs := fnSigs.push {
          callableId := callable.id.toNat
          name := fnName
          paramCount := callable.params.size
          resultIsBool
        }
    | .invariant =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: invariants are outside the current UInt64 pilot"
  -- Empty layout for pure-fn bodies (no state; typeDecls still needed for
  -- named-aggregate construct/field ops if they appear in pure expressions).
  let emptyLayout : NoirLowerLayoutV1 := {
    fields := #[]
    stateLeaves := #[]
    typeDecls := source.types
  }
  -- Pass 2: lower fn bodies against the complete signature table and an
  -- empty state table (fn purity).
  let mut fns : Array FnBinding := #[]
  for callable in source.callables do
    match callable.kind with
    | .pureFn =>
        let some fnSig := fnSigs.find? (fun sig => sig.callableId == callable.id.toNat) |
          throw (.planInvariant .noir
            "unsupported Noir semantic shape: pure fn signature is missing")
        let resultKind : NoirValueKindV1 := if fnSig.resultIsBool then .bool else .uint64
        let lowered ← lowerCallableV1 s!"fn '{fnSig.name}'" .mutate 0
          types emptyLayout fnSigs (some resultKind) callable
        fns := fns.push {
          callableId := callable.id.toNat
          name := fnSig.name
          params := lowered.params
          resultIsBool := fnSig.resultIsBool
          body := lowered.body
        }
    | _ => pure ()
  if states.isEmpty && initializer.isSome then
    throw <| .planInvariant .noir "stateless circuit programs cannot declare an initializer"
  if !states.isEmpty && initializer.isNone then
    throw <| .planInvariant .noir "stateful circuit programs require an initializer relation"
  let mut relations : Array Relation := #[]
  if let some initCallable := initializer then
    relations := relations.push (← makeRelationV1 0 types layout fnSigs "init" .initialize initCallable)
  for callable in entries do
    let name ← match callable.name with
      | some value => pure value
      | none => throw (.planInvariant .noir
          "unsupported Noir semantic shape: named entry is missing its name")
    let mode : RelationMode := match callable.kind with
      | .entry => .mutate
      | .view => .view
      | _ => .mutate
    relations := relations.push (← makeRelationV1 relations.size types layout fnSigs name mode callable)
  let unsignedPlan : Plan := {
    targetDescriptor := descriptor
    semanticSchemaVersion := semanticProgramSchemaVersionV1
    codegenProfile := codegenProfileString
    sourceDialect
    continuity := if states.isEmpty then .none else .externalPublicPrePost
    failurePolicy := .unsatisfied
    proofStatus := .notProduced
    resourceLimits := canonicalLimits
    programName
    sourceHash
    semanticHash
    planHash := String.ofList (List.replicate 64 '0')
    states
    events
    errors
    fns
    relations
  }
  let plan := { unsignedPlan with planHash := canonicalPlanHash unsignedPlan }
  pure plan

private def makePlanFromSemanticV1
    (artifactProgramName sourceHash semanticHash : String)
    (source : SemanticProgramV1) : CompileResult Plan := do
  -- Semantic structure was validated once at the capability mint
  -- (resolveEngineeringRequirementsV1 → validateSemanticProgramV1); the
  -- carrier is private-ctor so re-validation here is redundant. Transport
  -- decode still yields SemanticProgramDataV1 for the Plan body.
  let data ← match decodeSemanticProgramDataV1 source.canonicalBytes with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Noir received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 artifactProgramName sourceHash semanticHash data

/-- Internal Noir family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .noir do
    throw <| .planInvariant .noir "engineering capability kind is not Noir"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let sourceHash ← CompiledSemanticV1.artifactSourceHashHexOf compiled
  let semanticHash ← CompiledSemanticV1.artifactSemanticHashHexOf compiled
  makePlanFromSemanticV1
    (CompiledSemanticV1.artifactProgramNameOf compiled)
    sourceHash
    semanticHash
    source

end ProofForgeV2.Targets.Noir
