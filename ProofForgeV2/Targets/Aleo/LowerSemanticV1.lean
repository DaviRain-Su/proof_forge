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

## Coverage boundary (AleoCoverage wave, 2026-08-01)

LOWERED (product path): scalar stateLoad/stateStore (UInt64), checked
arithmetic/compare/bitwise/shift/logical, unary not/bitNot, pureCall,
bare assert, bare revert (`assert(false)`), if/switch/for, Commit identity
passthrough (label-only; no crypto commitment realization).

FAIL-CLOSED (explicit pins, not catch-all GAP):
  * **Field (bn254 Fr)** — research pin: Aleo native `field` is the BLS12-377
    scalar field (Edwards BLS Fr = BLS12-377 Fr), **not** catalog bn254 Fr.
    Mapping would be a silent wrong modulus. Keep `pilotFieldPolicyNone`.
  * **named aggregates** — Leo has native `struct`/`record`, but this Plan/IR
    envelope is scalar-only (mappings `u8 => u64`); construct/fieldGet/fieldSet/
    variantTag/variantPayload fail closed until a dedicated layout slice.
  * **Array/Map/Bytes/Option/String/Principal state** — no scalar mapping layout.
  * **ContextRead** — no host clock ABI in Leo 4.0.2 Final model for this pilot.
  * **emit / externalCall / schedule / revert-with-args** — no Leo analogue
    (resolver also declines event/sync/async requirement keys).
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
    "only UInt64, UInt32, Unit, and Bool are supported (Aleo native field is BLS12-377 Fr / Edwards BLS scalar, not bn254 Fr; named Struct/Enum, Array/Map/Bytes/Option, Principal, and String stay fail-closed on the scalar mapping envelope)"

/-- Aleo pilot type-closure: UInt64 + UInt32 (shift counts) + Unit/Bool.
    Field stays on `pilotFieldPolicyNone` (BLS12-377 ≠ bn254). Int/named/
    containers/Principal/String fail closed. -/
private def validateAleoTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult PilotTypeClosureV1 :=
  validatePilotTypeClosure aleoPlanErr aleoTypeClosureWording types
    pilotUintWidthPolicyU64U32
    (intPolicy := pilotIntWidthPolicyNone)
    (fieldPolicy := pilotFieldPolicyNone)

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

/-- Canonical 8-byte LE UInt64 literal decode (same discipline as the sibling
    targets: exact size, full consume, no trailing bytes). -/
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
    (data : SemanticProgramDataV1) (callable : CallableV1)
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
        let e : Expr := .stateLoad stateId.toNat
        match instr.result with
        | none => planError "Aleo stateLoad instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .binary op lhs rhs => do
        let l ← match envLookup env lhs with
          | some e => pure e
          | none => planError "Aleo binary references an undefined operand"
        let r ← match envLookup env rhs with
          | some e => pure e
          | none => planError "Aleo binary references an undefined operand"
        let e ← lowerBinary op l r
        match instr.result with
        | none => planError "Aleo binary instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .unary op operand => do
        let o ← match envLookup env operand with
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
          | some e => argExprs := argExprs.push e
          | none => planError "Aleo pureCall references an undefined argument"
        let e : Expr := .callFn fnName argExprs
        match instr.result with
        | none => planError "Aleo pureCall instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId e
    | .stateStore stateId value => do
        let v ← match envLookup env value with
          | some e => pure e
          | none => planError "Aleo stateStore references an undefined value"
        ls := { ls with stmts := ls.stmts.push (.store stateId.toNat v) }
    | .assert_ condition _ args => do
        unless args.isEmpty do
          planError "Aleo assert-else is outside the envelope"
        let c ← match envLookup env condition with
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
          | some e => pure e
          | none => planError "Aleo commit references an undefined operand"
        match instr.result with
        | none => planError "Aleo commit instruction must produce a value"
        | some valueDef =>
            env := envInsert env valueDef.valueId operand
    | .contextRead key => do
        unless key == unixTimeSecondsContextKeyV1 do
          planError s!"unsupported Aleo semantic shape: unknown ContextRead key '{key.value}'"
        planError
          "unsupported Aleo semantic shape: ContextRead is not admitted by pilot context policy"
    | .construct .. =>
        planError
          "unsupported Aleo semantic shape: named Struct/Enum construct is outside the scalar mapping envelope (Leo native struct/record deferred)"
    | .fieldGet .. | .fieldSet .. =>
        planError
          "unsupported Aleo semantic shape: named Struct fieldGet/fieldSet are outside the scalar mapping envelope (Leo native struct/record deferred)"
    | .variantTag .. | .variantPayload .. =>
        planError
          "unsupported Aleo semantic shape: Enum variantTag/variantPayload are outside the scalar mapping envelope"
    | .indexGet .. | .indexSet .. =>
        planError
          "unsupported Aleo semantic shape: IndexGet/IndexSet (Array/Map/Bytes) are outside the scalar mapping envelope"
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
        lowerLoop data callable fnNames target ls env loops
      else
        lowerRegion data callable fnNames target.blockId.toNat loops env ls
  | .branch condition thenTarget elseTarget => do
      let c ← match envLookup env condition with
        | some e => pure e
        | none => planError "Aleo branch references an undefined condition"
      let thenRes ← lowerRegion data callable fnNames thenTarget.blockId.toNat loops env ls
      let elseRes ← lowerRegion data callable fnNames elseTarget.blockId.toNat loops env ls
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
      let s ← match envLookup env scrutinee with
        | some e => pure e
        | none => planError "Aleo switch references an undefined scrutinee"
      let mut caseStmts : Array (UInt64 × Array Statement) := #[]
      let mut joins : Array Nat := #[]
      for case in cases do
        let value ← match decodeUInt64LiteralV1 case.valueBytes with
          | .ok v => pure v
          | .error _ => planError "Aleo switch case value is not a canonical UInt64"
        let targetRes ← lowerRegion data callable fnNames case.target.blockId.toNat loops env ls
        caseStmts := caseStmts.push (value, targetRes.stmts)
        match targetRes.join? with
        | some j => joins := joins.push j
        | none => pure ()
      let defaultRes ← match defaultTarget with
        | none => regionClosed
        | some t => lowerRegion data callable fnNames t.blockId.toNat loops env ls
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
            | some e => pure (ls.stmts.push (.returnValue e))
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
    (data : SemanticProgramDataV1) (callable : CallableV1)
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
  let startExpr ← match envLookup env startVid with
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
        let r ← match envLookup env rhs with
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
      let thenRes ← lowerRegion data callable fnNames thenTarget.blockId.toNat loops' envLoop ls
      unless thenRes.join?.isNone do
        planError "Aleo lowering: loop body must end at the latch back edge"
      let body := thenRes.stmts
      let maxIter := lb.maxIterations.toNat
      unless maxIter ≤ 4096 do
        planError "Aleo lowering: loop bound exceeds the wire maximum"
      let forStmt := .forLoop startExpr endExpr maxIter body
      match header.terminator with
      | .branch _ _ elseTarget =>
          lowerRegion data callable fnNames elseTarget.blockId.toNat loops env
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
    (data : SemanticProgramDataV1) (callable : CallableV1)
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
  let res ← lowerRegion data callable fnNames 0 #[] env0 { stmts := #[] }
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
  -- Type-closure first: Field/Principal/named aggregates/containers fail closed
  -- with `aleoTypeClosureWording` (Field cites BLS12-377 Fr ≠ bn254 Fr).
  let _types ← validateAleoTypeClosureV1 data.types
  -- State fields (UInt64 only in this envelope; any visibility — N1).
  let mut stateFields : Array String := #[]
  for state in data.logicalState do
    -- N1: Aleo mappings are naturally private; accept any visibility, UInt64 type.
    -- Field/named/containers already rejected at type-closure.
    unless isUInt64Type data state.typeId do
      planError "Aleo state must be UInt64 (Array/Map/Bytes/Option/named aggregate and Field declined)"
    stateFields := stateFields.push state.name
  -- Callable names in wire order (pureCall callee resolution).
  let fnNames := data.callables.filterMap fun c =>
    match c.kind with
    | .pureFn => some (c.id, c.name.getD "fn")
    | _ => none
  -- Callables in wire order; bare views become query descriptors.
  let mut functions : Array PlanFunction := #[]
  let mut views : Array PlanView := #[]
  for callable in data.callables do
    match callable.kind with
    | .invariant =>
        planError "Aleo does not support invariants in this slice"
    | .initializer | .entry | .view | .pureFn =>
        match ← lowerCallable data callable fnNames with
        | .asFunction fn =>
            functions := functions.push { fn with index := functions.size }
        | .asView view =>
            views := views.push view
  let plan := {
    programName
    stateFieldNames := stateFields
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
