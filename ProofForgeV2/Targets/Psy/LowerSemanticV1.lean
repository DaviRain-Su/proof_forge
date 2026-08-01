import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1

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
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

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

-- ---------------------------------------------------------------------------
-- Wire semantic → target-owned Plan lowering
-- ---------------------------------------------------------------------------

private structure ValueEnv where
  entries : Array (ValueIdV1 × Expr)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option Expr :=
  env.entries.findSome? (fun (vid, e) => if vid == id then some e else none)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (e : Expr) : ValueEnv :=
  { env with entries := env.entries.push (id, e) }

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
  else if isBoolType data typeId then
    match decodeBoolLiteralV1 valueBytes with
    | .ok flag => pure (.boolLiteral flag)
    | .error e => .error e
  else if isUInt32Type data typeId then
    match decodeUInt32LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error e => .error e
  else
    planError "unsupported Psy semantic shape: literal type is outside the public UInt64/Bool/UInt32-count envelope"

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
  | .bitNot =>
      planError "unsupported Psy semantic shape: unary bitNot (~) has no Psy surface form on Felt (no bitwise-not unary)"
  | .neg =>
      planError "unsupported Psy semantic shape: unary neg is Int/Field-only outside the envelope (desugars to 0 - x)"

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
    | some e => out := out.push e
    | none => planError s!"unsupported Psy semantic shape: {what} references an undefined argument"
  pure out

mutual

private partial def lowerRegion
    (data : SemanticProgramDataV1) (callable : CallableV1)
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
        let e : Expr := .stateLoad stateId.toNat
        match instr.result with
        | none => planError "unsupported Psy semantic shape: stateLoad instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .binary op lhs rhs => do
        let l ← match envLookup env lhs with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: binary references an undefined operand"
        let r ← match envLookup env rhs with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: binary references an undefined operand"
        let e ← lowerBinary op l r
        match instr.result with
        | none => planError "unsupported Psy semantic shape: binary instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .unary op operand => do
        let o ← match envLookup env operand with
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
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: stateStore references an undefined value"
        ls := { ls with stmts := ls.stmts.push (.store stateId.toNat v) }
    | .assert_ condition _ args => do
        unless args.isEmpty do
          planError "unsupported Psy semantic shape: assert-else is outside the envelope"
        let c ← match envLookup env condition with
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
    | .constant .. | .construct .. | .fieldGet .. | .indexGet ..
    | .fieldSet .. | .variantTag .. | .variantPayload .. | .indexSet ..
    | .checkedCast .. | .contextRead .. | .commit .. =>
        planError "unsupported Psy semantic shape: op is outside the public UInt64/Bool envelope"
  match block.terminator with
  | .jump target =>
      if isActiveHeader loops target.blockId then
        pure { stmts := ls.stmts, join? := none }
      else if isLoopHeaderV1 callable target.blockId then
        lowerLoop data callable fnNames target ls env loops
      else
        lowerRegion data callable fnNames target.blockId.toNat loops env ls
  | .branch condition thenTarget elseTarget => do
      let c ← match envLookup env condition with
        | some e => pure e
        | none => planError "unsupported Psy semantic shape: branch references an undefined condition"
      let emptyLs : LowerStateV1 := { stmts := #[] }
      let thenRes ← lowerRegion data callable fnNames thenTarget.blockId.toNat loops env emptyLs
      let elseRes ← lowerRegion data callable fnNames elseTarget.blockId.toNat loops env emptyLs
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
      let s ← match envLookup env scrutinee with
        | some e => pure e
        | none => planError "unsupported Psy semantic shape: switch references an undefined scrutinee"
      let mut caseStmts : Array (UInt64 × Array Statement) := #[]
      let mut joins : Array Nat := #[]
      for case in cases do
        let value ← match decodeUInt64LiteralV1 case.valueBytes with
          | .ok v => pure v
          | .error e => .error e
        let emptyLs : LowerStateV1 := { stmts := #[] }
        let targetRes ← lowerRegion data callable fnNames case.target.blockId.toNat loops env emptyLs
        caseStmts := caseStmts.push (value, targetRes.stmts)
        match targetRes.join? with
        | some j => joins := joins.push j
        | none => pure ()
      let emptyLs : LowerStateV1 := { stmts := #[] }
      let defaultRes ← match defaultTarget with
        | none => regionClosed
        | some t => lowerRegion data callable fnNames t.blockId.toNat loops env emptyLs
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
            | some e => pure (ls.stmts.push (.returnValue e))
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
    (data : SemanticProgramDataV1) (callable : CallableV1)
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
  let startExpr ← match envLookup env startVid with
    | some e => pure e
    | none => planError "unsupported Psy semantic shape: loop start value is not defined"
  let mut condVid? : Option ValueIdV1 := none
  let mut endExpr? : Option Expr := none
  for instr in header.instructions do
    match instr.op with
    | .binary .lt lhs rhs => do
        unless lhs == paramDef.valueId do
          planError "unsupported Psy semantic shape: loop condition lhs must be the induction parameter"
        let r ← match envLookup env rhs with
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
      let thenRes ← lowerRegion data callable fnNames thenTarget.blockId.toNat loops' envLoop emptyBody
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
          lowerRegion data callable fnNames elseTarget.blockId.toNat loops env ls'
      | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"
  | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"

end

private def resultShape (data : SemanticProgramDataV1) (callable : CallableV1) :
    CompileResult (Bool × Bool) := do
  if isBoolType data callable.result.typeId then pure (true, false)
  else if isUInt64Type data callable.result.typeId then pure (false, false)
  else if isUnitType data callable.result.typeId then pure (false, true)
  else planError "unsupported Psy semantic shape: callable result is outside the public UInt64/Bool/Unit envelope"

private def lowerCallable
    (data : SemanticProgramDataV1) (callable : CallableV1)
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
      else if isUInt64Type data p.typeId then pure false
      else planError "unsupported Psy semantic shape: callable parameter is outside the public UInt64/Bool envelope"
    params := params.push { sourceIndex := paramIndex, name := p.name, isBool }
    paramIndex := paramIndex + 1
  let mut env0 : ValueEnv := default
  let mut paramOrdinal : Nat := 0
  for p in callable.params do
    env0 := envInsert env0 p.valueId (.param paramOrdinal)
    paramOrdinal := paramOrdinal + 1
  let empty0 : LowerStateV1 := { stmts := #[] }
  let res ← lowerRegion data callable fnNames 0 #[] env0 empty0
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
  let mut stateFields : Array String := #[]
  for state in data.logicalState do
    unless isUInt64Type data state.typeId do
      planError "unsupported Psy semantic shape: state must be public UInt64"
    stateFields := stateFields.push state.name
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
        let fn ← lowerCallable data callable fnNames
        functions := functions.push { fn with index := functions.size }
  pure {
    programName
    stateFieldNames := stateFields
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
