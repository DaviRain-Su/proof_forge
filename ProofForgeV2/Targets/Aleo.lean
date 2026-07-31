/-
  ProofForgeV2.Targets.Aleo — capability-gated Aleo (Leo 4.0.2) target leaf.

  Port of the hackathon/aleo-2026-08 lane onto the current product spine:
  consumes retained `SemanticProgramV1` via the `ResolvedEngineeringBuildV1`
  capability exactly like EVM/Solana/NEAR/Noir. No V1-direct second semantic
  path: the target-owned Plan/IR are built from the same structure-valid
  semantic carrier the other four targets consume.

  Leo 4.0.2 execution model (verified by the hackathon spike + devnet runs):
    * mappings are the only state; mapping reads/writes are legal only in
      finalization context, so state-touching callables materialize as
      `fn ... -> Final { return final { ... } }`
    * `Final` functions cannot return a value: a non-Unit entry whose body
      touches state records `resultDropped` (explicit Plan metadata, never a
      silent omission); the value is observable post-transaction via
      `leo query`. Each dropped return expression is still evaluated inside
      the final block so its failure semantics (halt on panic = revert) are
      preserved.
    * native u64 arithmetic is checked (halt on overflow — spike-verified);
      `div`/`mod` by zero and `assert(false)` halt the transaction, which
      reverts atomically (no state change) — the DSL revert analogue.

  Honest fail-closed decisions (documented, SPEC-TARGET-ALEO-001):
    * `emit` — Leo 4.0.2 has no on-chain event log → fail closed.
    * `revert` with error args — the payload cannot be represented →
      fail closed; bare `revert` lowers to `assert(false)` (halt = revert).
    * `trap` lowers to `assert(false)` (unreachable halt).
    * views: bare public-state reads materialize as off-chain query
      descriptors (`leo query` — the EVM `eth_call` analogue); computed
      state-reading views fail closed; pure computed views are plain fns.
    * shift counts: UInt32 wire values render as u64 with an explicit
      `assert(count < 64u64)` guard (invalidShift); result overflow relies
      on Leo native checked shift semantics (the Noir precedent).
    * u32 count arithmetic is promoted to u64 (the documented four-target
      superset: a u32 overflow can only reach the count guard and reverts
      there).
    * bounded `for`: Leo loops need constant bounds, so the loop lowers to
      `for c in 0u64..N { if c < (end - start) { body } }` guarded by
      `if start < end { assert(end - start <= N) }` (boundExceeded halts
      before any body runs; observably identical to the reference's
      N-bodies-then-revert since a halt discards all provisional state).
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

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

/-- Leo 4.0.2 expressions (pure value syntax; mapping access is final-context
    only and appears as method calls on the mapping name). -/
inductive LeoExpr where
  | u64Literal (value : UInt64)
  | boolLiteral (value : Bool)
  | reference (name : String)
  | unary (op : String) (inner : LeoExpr)
  | binary (op : String) (lhs rhs : LeoExpr)
  | ternary (condition thenValue elseValue : LeoExpr)
  | mappingGetOrUse (mapping : String) (key : String) (default : LeoExpr)
  | call (name : String) (args : Array LeoExpr)
  deriving BEq, Inhabited, Repr

/-- Leo 4.0.2 statements (final/proof context). Leo `let` requires an explicit
    type annotation, so every binding carries its Leo type name. -/
inductive LeoStatement where
  | letBinding (name ty : String) (value : LeoExpr)
  | assert (condition : LeoExpr)
  | mappingSet (mapping : String) (key : String) (value : LeoExpr)
  | returnValue (value : LeoExpr)
  | returnUnit
  | ifElse (condition : LeoExpr) (thenBody elseBody : Array LeoStatement)
  | forConst (index : String) (bound : Nat) (body : Array LeoStatement)
  deriving BEq, Inhabited, Repr

structure LeoParam where
  name : String
  isBool : Bool
  deriving BEq, Inhabited, Repr

structure LeoFunction where
  name : String
  params : Array LeoParam
  resultIsBool : Bool
  /-- `some` = state-touching Final function (body runs in final context). -/
  isFinal : Bool
  body : Array LeoStatement
  deriving BEq, Inhabited, Repr

structure LeoMapping where
  name : String
  deriving BEq, Inhabited, Repr

/-- Leo 4.0.2 program AST. Rendering source happens after Plan-to-IR
    validation so source strings cannot rediscover business semantics. -/
structure LeoProgram where
  programId : String
  mappings : Array LeoMapping
  functions : Array LeoFunction
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  program : LeoProgram
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

/-- Hard bounds (same order of magnitude as the sibling targets). -/
private def maxFunctions : Nat := 256
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256
private def maxIrNodes : Nat := 110000

private def mappingKey : String := "0u8"
private def guardMappingName : String := "initialized"

/-- Leo 4.0.2 reserved words / mapping method names that a DSL identifier must
    not collide with (conservative; `leo build` is the final authority). -/
private def reservedLeoWords : Array String :=
  #[ "mapping", "transition", "finalize", "final", "function", "fn", "program",
     "constructor", "async", "record", "struct", "enum", "for", "if", "else",
     "return", "let", "assert", "true", "false", "public", "private",
     "self", "as", "cast" ]

private def isReserved (name : String) : Bool :=
  reservedLeoWords.contains name

private def isLeoProgramId (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      let isLower (c : Char) : Bool :=
        let code := c.toNat
        97 <= code && code <= 122
      let isDigit (c : Char) : Bool :=
        let code := c.toNat
        48 <= code && code <= 57
      isLower first && rest.all (fun c =>
        isLower c || isDigit c || c == '_')

private def asciiLower (value : String) : String :=
  String.ofList <| value.toList.map fun c =>
    let code := c.toNat
    if 65 <= code && code <= 90 then Char.ofNat (code + 32) else c

private def renderType (isBool : Bool) : String :=
  if isBool then "boolean" else "u64"

private def renderLit (value : UInt64) : String :=
  s!"{value.toNat}u64"

private partial def renderExpr : LeoExpr → String
  | .u64Literal value => renderLit value
  | .boolLiteral value => if value then "true" else "false"
  | .reference name => name
  | .unary op inner => s!"({op}{renderExpr inner})"
  | .binary op lhs rhs => s!"({renderExpr lhs} {op} {renderExpr rhs})"
  | .ternary condition thenValue elseValue =>
      s!"({renderExpr condition} ? {renderExpr thenValue} : {renderExpr elseValue})"
  | .mappingGetOrUse mapping key default =>
      s!"{mapping}.get_or_use({key}, {renderExpr default})"
  | .call name args =>
      let inner := args.toList.map renderExpr |> String.intercalate ", "
      s!"{name}({inner})"

private def indentStr (depth : Nat) : String :=
  String.ofList (List.replicate depth ' ')

mutual

private partial def renderStatements (depth : Nat) (stmts : Array LeoStatement) : String :=
  stmts.toList.map (renderStatement depth) |> String.intercalate ""

private partial def renderStatement (depth : Nat) : LeoStatement → String
  | .letBinding name ty value =>
      s!"{indentStr depth}let {name}: {ty} = {renderExpr value};\n"
  | .assert condition =>
      s!"{indentStr depth}assert({renderExpr condition});\n"
  | .mappingSet mapping key value =>
      s!"{indentStr depth}{mapping}.set({key}, {renderExpr value});\n"
  | .returnValue value =>
      s!"{indentStr depth}return {renderExpr value};\n"
  | .returnUnit =>
      s!"{indentStr depth}return ();\n"
  | .ifElse condition thenBody elseBody =>
      s!"{indentStr depth}if {renderExpr condition} \{\n" ++
      renderStatements (depth + 2) thenBody ++
      (if elseBody.isEmpty then
         s!"{indentStr depth}}}\n"
       else
         s!"{indentStr depth}}} else \{\n" ++
         renderStatements (depth + 2) elseBody ++
         s!"{indentStr depth}}}\n")
  | .forConst index bound body =>
      s!"{indentStr depth}for {index} in 0u64..{bound}u64 \{\n" ++
      renderStatements (depth + 2) body ++
      s!"{indentStr depth}}}\n"

end

private def renderParam (param : LeoParam) : String :=
  s!"public {param.name}: {renderType param.isBool}"

private def renderFunction : LeoFunction → String
  | fn =>
      let signature := (fn.params.toList.map renderParam) |> String.intercalate ", "
      let resultTy := if fn.isFinal then "Final" else renderType fn.resultIsBool
      let body := renderStatements 4 fn.body
      s!"    fn {fn.name}({signature}) -> {resultTy} \{\n" ++
      (if fn.isFinal then
         s!"        return final \{\n{body}        }\n"
       else
         body) ++
      s!"    }\n\n"

private def renderProgram (programId : String) (program : LeoProgram) : String :=
  let mappings := (program.mappings.toList.map fun m =>
    s!"    mapping {m.name}: u8 => u64;") |> String.intercalate "\n"
  s!"// Generated by proof-forge-next (Aleo target, Leo {leoToolchain}).\n" ++
  s!"program {programId}.aleo \{\n" ++
  s!"    @noupgrade\n" ++
  s!"    constructor() \{\n\n" ++
  (if mappings.isEmpty then "" else mappings ++ "\n\n") ++
  s!"    mapping {guardMappingName}: u8 => bool;\n\n" ++
  (program.functions.toList.map renderFunction |> String.intercalate "") ++
  s!"}\n"

-- ---------------------------------------------------------------------------
-- Plan validation
-- ---------------------------------------------------------------------------

private def validateExprNodes (expr : Expr) : Option Nat :=
  match expr with
  | .literal _ | .boolLiteral _ | .param _ | .loopVar _ | .stateLoad _ => some 1
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .logicalAnd l r | .logicalOr l r | .shl l r | .shr l r => do
      let dl ← validateExprNodes l
      let dr ← validateExprNodes r
      if dl + dr + 1 > maxExprDepth then none else some (dl + dr + 1)
  | .compare _ l r => do
      let dl ← validateExprNodes l
      let dr ← validateExprNodes r
      if dl + dr + 1 > maxExprDepth then none else some (dl + dr + 1)
  | .bitNot o | .boolNot o => do
      let do' ← validateExprNodes o
      if do' + 1 > maxExprDepth then none else some (do' + 1)
  | .callFn _ args => do
      let mut total : Nat := 1
      for arg in args do
        let da ← validateExprNodes arg
        total := total + da
      if total > maxExprDepth then none else some total

private partial def validateStatements (stmts : Array Statement) : CompileResult Unit := do
  if stmts.size > maxBodyStatements then
    planError "Aleo function body exceeds the statement limit"
  for stmt in stmts do
    match stmt with
    | .store _ value | .returnValue value => do
        match validateExprNodes value with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
    | .returnNone => pure ()
    | .assert condition => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
    | .ifThenElse condition thenBody elseBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
        validateStatements thenBody
        validateStatements elseBody
    | .switchOn condition cases defaultBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
        for (_, caseBody) in cases do
          validateStatements caseBody
        validateStatements defaultBody
    | .forLoop start endExclusive _ body => do
        match validateExprNodes start, validateExprNodes endExclusive with
        | some _, some _ => pure ()
        | _, _ => planError "Aleo plan expression exceeds the depth/node limit"
        validateStatements body
    | .emitEvent .. =>
        planError "Aleo does not support emit: Leo 4.0.2 has no on-chain event log"
    | .revertError _ args =>
        unless args.isEmpty do
          planError "Aleo does not support revert payloads: Leo 4.0.2 cannot represent error arguments"

def validatePlan (plan : Plan) : CompileResult Unit := do
  if plan.functions.size > maxFunctions then
    planError "Aleo plan exceeds the function limit"
  if plan.stateFieldNames.size > maxParams then
    planError "Aleo plan exceeds the state mapping limit"
  let names := plan.functions.map (·.name) ++ plan.views.map (·.name)
  for name in names do
    if isReserved name then
      planError s!"Aleo identifier '{name}' collides with a reserved Leo word"
  for fn in plan.functions do
    if fn.params.size > maxParams then
      planError "Aleo plan function exceeds the parameter limit"
    for param in fn.params do
      if isReserved param.name then
        planError s!"Aleo parameter '{param.name}' collides with a reserved Leo word"
    validateStatements fn.body
    if fn.resultDropped && fn.kind != .mutate then
      planError "resultDropped is only valid on state-touching entries"
    if fn.resultDropped && !fn.touchesState then
      planError "resultDropped requires a state-touching body"
  for view in plan.views do
    if view.stateFieldIndex >= plan.stateFieldNames.size then
      planError "Aleo view references a missing state field"
  pure ()

private def validateLeoProgram (program : LeoProgram) : CompileResult Unit := do
  unless isLeoProgramId program.programId do
    planError s!"'{program.programId}' is not a legal Leo program id"
  unless program.functions.size ≤ maxIrNodes do
    planError "Aleo IR exceeds the node limit"

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  validateLeoProgram ir.program

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
    | other =>
        planError "Aleo lowering: semantic op is outside the public UInt64/Bool envelope"
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
    | other =>
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
      else planError "Aleo callable parameter is outside the public UInt64/Bool envelope"
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
  -- State fields (public UInt64 only in this envelope).
  let mut stateFields : Array String := #[]
  for state in data.logicalState do
    unless isUInt64Type data state.typeId do
      planError "Aleo state must be public UInt64"
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
  validatePlan plan
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

/-- Capability-gated public Plan entry (Aleo target leaf). Support is already
    decided by the capability; the Plan body consumes only retained
    SemanticProgramV1, never residual alpha. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .aleo do
    throw <| .planInvariant .aleo "engineering capability kind is not Aleo"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Aleo source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Aleo semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

-- ---------------------------------------------------------------------------
-- Plan → Leo IR
-- ---------------------------------------------------------------------------

/-- Statement lowering context: fresh-name counter and the mapping name for
    each state field. Mapping names are generated (`pf_state_{i}`), so DSL
    state names cannot collide with Leo mapping-method vocabulary. -/
private structure EmitCtx where
  next : Nat
  mappingNames : Array String
  deriving Inhabited

private def freshName (ctx : EmitCtx) : String × EmitCtx :=
  (s!"pf_e{ctx.next}", { ctx with next := ctx.next + 1 })

/-- The Leo type of a plan expression (every plan expr is u64 or boolean). -/
private def exprLeoType : Expr → String
  | .boolLiteral _ => "boolean"
  | .compare _ _ _ => "boolean"
  | .logicalAnd _ _ | .logicalOr _ _ => "boolean"
  | .boolNot _ => "boolean"
  | _ => "u64"

/-- Lower one plan expression into typed Leo lets with failure guards at every
    checked node (the EVM statement-form discipline): operands are bound in
    order, `div`/`mod` get an explicit nonzero assert, shifts get an explicit
    `count < 64` assert. Checked add/sub/mul rely on Leo's native checked
    semantics (spike-verified halt-on-overflow). Returns (statements, value
    reference, ctx). -/
private partial def lowerExprStmt
    (ctx : EmitCtx) (expr : Expr) :
    CompileResult (Array LeoStatement × LeoExpr × EmitCtx) := do
  let leaf (leo : LeoExpr) : CompileResult (Array LeoStatement × LeoExpr × EmitCtx) :=
    pure (#[], leo, ctx)
  let bind (ty : String) (op : String) (l r : Expr) : CompileResult
      (Array LeoStatement × LeoExpr × EmitCtx) := do
    let (ls1, l', ctx1) ← lowerExprStmt ctx l
    let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
    let (name, ctx3) := freshName ctx2
    pure (ls1 ++ ls2 ++ #[.letBinding name ty (.binary op l' r')], .reference name, ctx3)
  match expr with
  | .literal value => leaf (.u64Literal value)
  | .boolLiteral value => leaf (.boolLiteral value)
  | .param inputIndex => leaf (.reference s!"p{inputIndex}")
  | .loopVar depth => leaf (.reference s!"pf_i{depth}")
  | .stateLoad fieldIndex =>
      leaf (.mappingGetOrUse s!"pf_state_{fieldIndex}" mappingKey (.u64Literal 0))
  | .checkedAdd l r => bind "u64" "+" l r
  | .checkedSub l r => bind "u64" "-" l r
  | .checkedMul l r => bind "u64" "*" l r
  | .checkedDiv l r | .checkedMod l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let op := match expr with | .checkedDiv _ _ => "/" | _ => "%"
      pure (ls1 ++ ls2 ++
        #[.assert (.binary "!=" r' (.u64Literal 0)),
          .letBinding name "u64" (.binary op l' r')],
        .reference name, ctx3)
  | .shl l r | .shr l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let op := match expr with | .shl _ _ => "<<" | _ => ">>"
      pure (ls1 ++ ls2 ++
        #[.assert (.binary "<" r' (.u64Literal 64)),
          .letBinding name "u64" (.binary op l' r')],
        .reference name, ctx3)
  | .compare op l r => do
      let yul := match op with
        | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="
      bind "boolean" yul l r
  | .bitAnd l r => bind "u64" "&" l r
  | .bitOr l r => bind "u64" "|" l r
  | .bitXor l r => bind "u64" "^" l r
  | .logicalAnd l r => bind "boolean" "&&" l r
  | .logicalOr l r => bind "boolean" "||" l r
  | .bitNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "u64" (.unary "!" o')], .reference name, ctx2)
  | .boolNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "boolean" (.unary "!" o')], .reference name, ctx2)
  | .callFn fnName args => do
      let mut stmts : Array LeoStatement := #[]
      let mut args' : Array LeoExpr := #[]
      let mut ctx' := ctx
      for arg in args do
        let (ls, a', ctx1) ← lowerExprStmt ctx' arg
        stmts := stmts ++ ls
        args' := args'.push a'
        ctx' := ctx1
      let (name, ctx2) := freshName ctx'
      let leoType := exprLeoType expr
      pure (stmts ++ #[.letBinding name leoType (.call fnName args')], .reference name, ctx2)

/-- Lower a statement list into Leo. `isFinal` selects the return encoding:
    in final context a return expression is evaluated for failure semantics
    and dropped (`let pf_return = ...`); in proof context it is returned. -/
private partial def emitStatements
    (ctx : EmitCtx) (stmts : Array Statement) (loopDepth : Nat)
    (isFinal : Bool) : CompileResult (Array LeoStatement × EmitCtx) := do
  let mut out : Array LeoStatement := #[]
  let mut ctx := ctx
  for stmt in stmts do
    match stmt with
    | .store fieldIndex value => do
        let (exprStmts, leo, ctx1) ← lowerExprStmt ctx value
        out := out ++ exprStmts
        let mapping ← match ctx1.mappingNames[fieldIndex]? with
          | some m => pure m
          | none => planError "Aleo emission: store references a missing state field"
        out := out.push (.mappingSet mapping mappingKey leo)
        ctx := ctx1
    | .assert condition => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        out := out ++ exprStmts ++ #[.assert c']
        ctx := ctx1
    | .returnValue value => do
        let (exprStmts, leo, ctx1) ← lowerExprStmt ctx value
        out := out ++ exprStmts
        if isFinal then
          out := out.push (.letBinding "pf_return" (exprLeoType value) leo)
        else
          out := out.push (.returnValue leo)
        ctx := ctx1
    | .returnNone =>
        if isFinal then
          pure ()
        else
          out := out.push .returnUnit
    | .ifThenElse condition thenBody elseBody => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        let (thenStmts, ctx2) ← emitStatements ctx1 thenBody loopDepth isFinal
        let (elseStmts, ctx3) ← emitStatements ctx2 elseBody loopDepth isFinal
        out := out ++ exprStmts ++ #[.ifElse c' thenStmts elseStmts]
        ctx := ctx3
    | .switchOn scrutinee cases defaultBody => do
        let (exprStmts, s', ctx1) ← lowerExprStmt ctx scrutinee
        out := out ++ exprStmts
        let mut caseList : List (LeoExpr × Array LeoStatement) := []
        let mut ctx' := ctx1
        for (value, caseBody) in cases do
          let (caseStmts, ctx2) ← emitStatements ctx' caseBody loopDepth isFinal
          caseList := caseList ++ [((.binary "==" s' (.u64Literal value)), caseStmts)]
          ctx' := ctx2
        let (defaultStmts, ctx2) ← emitStatements ctx' defaultBody loopDepth isFinal
        ctx := ctx2
        -- Right-nested if/else chain: first matching case wins, else default.
        let combined := caseList.foldr
          (fun (cond, caseStmts) acc => #[.ifElse cond caseStmts acc]) defaultStmts
        out := out ++ combined
    | .forLoop start endExclusive maxIter body => do
        let (startStmts, sLeo, ctx1) ← lowerExprStmt ctx start
        let (endStmts, eLeo, ctx2) ← lowerExprStmt ctx1 endExclusive
        -- Deterministic per-depth names (readable + testable).
        let startName := s!"pf_start{loopDepth}"
        let endName := s!"pf_end{loopDepth}"
        let ctx3 := ctx2
        let ctx4 := ctx3
        let guardCond : LeoExpr :=
          .binary "<" (.reference startName) (.reference endName)
        let fits : LeoExpr :=
          .binary "<=" (.binary "-" (.reference endName) (.reference startName))
            (.u64Literal maxIter.toUInt64)
        let (bodyStmts, ctx5) ← emitStatements ctx4 body (loopDepth + 1) isFinal
        let indexName := s!"pf_c{loopDepth}"
        let iName := s!"pf_i{loopDepth}"
        let innerGuard : LeoExpr :=
          .binary "<" (.reference indexName)
            (.binary "-" (.reference endName) (.reference startName))
        let bodyInner :=
          #[.letBinding iName "u64" (.binary "+" (.reference startName) (.reference indexName))]
          ++ bodyStmts
        let loopStmt : LeoStatement :=
          .forConst indexName maxIter #[.ifElse innerGuard bodyInner #[]]
        out := out ++ startStmts ++ endStmts ++
          #[.letBinding startName "u64" sLeo, .letBinding endName "u64" eLeo,
            .ifElse guardCond #[.assert fits] #[], loopStmt]
        ctx := ctx5
    | .emitEvent .. =>
        planError "Aleo does not support emit: Leo 4.0.2 has no on-chain event log"
    | .revertError _ args => do
        unless args.isEmpty do
          planError "Aleo does not support revert payloads"
        out := out.push (.assert (.boolLiteral false))
  pure (out, ctx)

/-- Does a proof-context statement list need a trailing default return (its
    last statement is control flow whose arms all returned)? -/
private def needsTrailingReturn (stmts : Array Statement) : Bool :=
  match stmts.back? with
  | none => true
  | some (.returnValue _) | some .returnNone => false
  | some _ => true

private def emitFunction (ctx : EmitCtx) (fn : PlanFunction) :
    CompileResult (LeoFunction × EmitCtx) := do
  let params := fn.params.map fun p => { name := s!"p{p.sourceIndex}", isBool := p.isBool }
  let isFinal := fn.touchesState
  let (body0, ctx1) ← emitStatements ctx fn.body 0 isFinal
  -- Proof-context functions whose last statement is control flow (all arms
  -- returned) get an unreachable trailing default return so Leo's checker
  -- accepts the function; it never executes.
  let body :=
    if isFinal then body0
    else if needsTrailingReturn fn.body then
      body0 ++ #[.returnValue (if fn.resultIsBool then .boolLiteral false else .u64Literal 0)]
    else body0
  -- Initialize: inject the one-shot guard + final set.
  let body' :=
    if fn.kind == .initialize then
      #[.letBinding "pf_seen" "boolean"
          (.mappingGetOrUse guardMappingName mappingKey (.boolLiteral false)),
        .assert (.unary "!" (.reference "pf_seen"))] ++ body ++
      #[.mappingSet guardMappingName mappingKey (.boolLiteral true)]
    else
      body
  pure ({
    name := fn.name
    params
    resultIsBool := fn.resultIsBool
    isFinal
    body := body'
  }, ctx1)

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let programId := asciiLower plan.programName
  unless isLeoProgramId programId do
    planError s!"'{plan.programName}' cannot form a legal Leo program id"
  let mappings := plan.stateFieldNames.mapIdx fun i _ => { name := s!"pf_state_{i}" }
  let ctx0 : EmitCtx := { next := 0, mappingNames := mappings.map (·.name) }
  let mut functions : Array LeoFunction := #[]
  let mut ctx := ctx0
  for fn in plan.functions do
    let (leoFn, ctx1) ← emitFunction ctx fn
    functions := functions.push leoFn
    ctx := ctx1
  let program := { programId, mappings, functions }
  validateLeoProgram program
  pure { sourcePlan := plan, program }

/-- Capability-gated public IR entry. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← planFromCapability capability
  lower plan

/-- Capability-gated public materialize entry. Sole path from the retained
    SemanticProgramV1-native Aleo Plan body to emitted files for this target. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  let programId := ir.program.programId
  let source := renderProgram programId ir.program
  pure #[{
    path := s!"{programId}.aleo"
    mediaType := "text/plain"
    contents := source
  }]

instance : Materializer .aleo where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Aleo
