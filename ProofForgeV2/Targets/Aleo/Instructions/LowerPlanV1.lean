/-
  ALEO-IR-2/3/4/5: AleoPlan → Aleo Instructions program.

  IR-2 (Counter MVP, golden-locked):
    * initialize: store param → Final with one-shot `initialized` guard
    * increment: store(checkedAdd(stateLoad, param)) + return stateLoad
      (resultDropped re-load after set)
    * bare views: off-chain only (not emitted; match Counter golden)
    * constructor: `assert.eq edition 0u16`

  IR-3 (control flow, structural):
    * ifThenElse → `branch.eq` / `position` (Leo 4.0.2 if shape)
    * switchOn (match) → right-nested is.eq + branch chain
    * bounded for → static unroll of `0 .. maxIterations` with runtime
      `c < (end-start)` gate + boundExceeded assert when start < end
    * expression lower: public UInt64/Bool arithmetic/compare/logic/ternary
    * fail closed: pure helpers, emit, payload revert, unbounded for

  IR-4 (multi-leaf / Map / Option / narrow widths):
    * Reuse Leo flatten-to-mapping layout: each Plan state leaf →
      `pf_state_{i}` mapping (key u8.public, value typed by leaf width)
    * Multi-leaf `storeAggregate`: evaluate all leaves on pre-store snapshot,
      then sequential `set` (matches EmitIR atomic batch)
    * Option UInt64 / Array UInt64 N / dense Map UInt64 cap-2 arrive as
      already-flattened leaves from LowerSemantic (no nested Map construct)
    * Narrow UInt{8,16,32} state/param/literal + checked arith/bit/shift
      (shift count: bound guard + cast to u8, EmitIR-portable)
    * Aggregate Final returns: eval leaves and drop (same Leo Final model)
    * Fail closed: Int64/Field leaves·params, pure helpers, emit, nested
      Map residual (Semantic/Plan already FC), bn254/Goldilocks Field

  IR-5 (effects honesty matrix — all F / no PARTIAL without evidence):
    Plan-reachable surfaces (checked here, stable `ALEO-IR-5:` diagnostics):
    * emitEvent → FC (no on-chain event log / Instructions event model)
    * callFn (pureCall residual on Instructions) → FC
    * revertError with payload args → FC (bare revert → assert.eq true false)
    Product surfaces that never reach this lower (still FC; evidence documented):
    * external call / schedule → resolver declines both S2 effect keys
    * pf.assets / record custody → zero-binding (ADR-0029 Phase D);
      no account-balance vault; record mint/consume not admitted
    * ContextRead → Semantic→Plan pilot FC (no host clock ABI)
    * Commit → Semantic identity passthrough only (no crypto commitment opcode)
    * EnvRead (balanceOfSelf) → Semantic→Plan FC
    No PARTIAL row is claimed on this path.

  Profile note (default vs compile):
    * Plan body is profile-insensitive (shared by
      `aleo-leo-4.0.2-u64-v1` and `aleo-leo-4.0.2-u64-compile-v1`).
    * Default source profile: product still emits Leo 4 source + query-contract
      (zero-tool); this lower is the engineering Instructions path for tests
      and the IR authority candidate — **not** product primary yet (IR-6).
    * Compile profile: product Leo source → locked `leo build` produces
      `*.compiled.aleo` extras; Counter Instructions from this lower must be
      structurally ≡ that golden (G1). Multi-leaf/control-flow programs are
      tested structurally (G2/G3/IR-4), not as byte-identical Leo compile goldens.

  Unsupported Plan shapes fail closed. Leo `EmitIRV1` path remains the
  transitional product printer.
-/
import ProofForgeV2.Targets.Aleo.LowerSemanticV1
import ProofForgeV2.Targets.Aleo.ValidatePlanV1
import ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.Aleo
open ProofForgeV2.Targets.Aleo.Instructions.SchemaV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

/-- Mapping key literal used by EmitIR and Leo 4.0.2 Counter golden. -/
def mappingKeyLiteralV1 : OperandV1 := .literal "0u8"

/-- One-shot init guard mapping (not a DSL state leaf). -/
def guardMappingNameV1 : String := "initialized"

/-- Physical mapping name for state leaf `fieldIndex` (matches EmitIR). -/
def mappingNameV1 (fieldIndex : Nat) : String :=
  s!"pf_state_{fieldIndex}"

/-- Intrinsic ceiling for static for-unroll (matches Semantic loopBounds max). -/
def maxForUnrollIterationsV1 : Nat := 4096

private def asciiLower (value : String) : String :=
  String.ofList <| value.toList.map fun c =>
    let code := c.toNat
    if 65 <= code && code <= 90 then Char.ofNat (code + 32) else c

/-- Leo program id spelling for Instructions header (`counter.aleo`). -/
def programNameFromPlanV1 (plan : Plan) : CompileResult String := do
  let id := asciiLower plan.programName
  unless !id.isEmpty do
    planError "ALEO-IR: program name is empty after lowercasing"
  pure s!"{id}.aleo"

/-- Admitted unsigned widths on the Instructions Final path (T8 + UInt64). -/
private def isAdmittedUintWidth (w : Nat) : Bool :=
  w == 0 || w == 8 || w == 16 || w == 32 || w == 64

private def uintWidthToBase (w : Nat) : BaseTypeV1 :=
  match w with
  | 8 => .u8
  | 16 => .u16
  | 32 => .u32
  | _ => .u64

private def isAdmittedUintParam (p : PlanParam) : Bool :=
  !p.isBool && !p.isInt && !p.isField && isAdmittedUintWidth p.uintWidth

private def isAdmittedUintLeaf
    (plan : Plan) (fieldIndex : Nat) : Bool :=
  fieldIndex < plan.stateFieldNames.size &&
    !plan.stateFieldIsInt.getD fieldIndex false &&
    !plan.stateFieldIsField.getD fieldIndex false &&
    isAdmittedUintWidth (plan.stateFieldUintWidth.getD fieldIndex 0)

private def leafUintWidth (plan : Plan) (fieldIndex : Nat) : Nat :=
  plan.stateFieldUintWidth.getD fieldIndex 0

private def defaultLiteralForWidth (w : Nat) : OperandV1 :=
  match w with
  | 8 => .literal "0u8"
  | 16 => .literal "0u16"
  | 32 => .literal "0u32"
  | _ => .literal "0u64"

private def defaultLiteralForLeaf
    (plan : Plan) (fieldIndex : Nat) : CompileResult OperandV1 := do
  unless isAdmittedUintLeaf plan fieldIndex do
    planError
      s!"ALEO-IR-4: state leaf {fieldIndex} is not public UInt8/16/32/64 (Int64/Field residual FC on Instructions path)"
  pure (defaultLiteralForWidth (leafUintWidth plan fieldIndex))

private def mappingValueTypeForLeaf
    (plan : Plan) (fieldIndex : Nat) : CompileResult TypeAnnV1 := do
  unless isAdmittedUintLeaf plan fieldIndex do
    planError
      s!"ALEO-IR-4: state leaf {fieldIndex} is not public UInt8/16/32/64"
  pure (.base (uintWidthToBase (leafUintWidth plan fieldIndex)) .public_)

private def paramInputType (p : PlanParam) : CompileResult TypeAnnV1 := do
  unless isAdmittedUintParam p do
    planError
      s!"ALEO-IR-4: param '{p.name}' must be public UInt8/16/32/64 (Bool/Int/Field residual FC)"
  pure (.base (uintWidthToBase p.uintWidth) .public_)

private def u64Literal (v : UInt64) : OperandV1 :=
  .literal s!"{v}u64"

private def uintLiteral (bitWidth : Nat) (v : UInt64) : OperandV1 :=
  match bitWidth with
  | 8 => .literal s!"{v}u8"
  | 16 => .literal s!"{v}u16"
  | 32 => .literal s!"{v}u32"
  | _ => .literal s!"{v}u64"

private def zeroLiteral (bitWidth : Nat) : OperandV1 :=
  uintLiteral bitWidth 0

/-!
  ## ALEO-IR-5 effects honesty matrix (stable diagnostics)

  Rows are **F** (fail closed). PARTIAL is forbidden without documented evidence.
  Plan-reachable rows are enforced by `checkEffectsHonestyMatrixV1` before
  shared `validatePlan` so Instructions tests pin `ALEO-IR-5:` fragments.
-/

/-- Stable diagnostic: `emit` / on-chain event log. -/
def diagEmitNotAdmittedV1 : String :=
  "ALEO-IR-5: emit is not admitted (no on-chain event log in Aleo Instructions; \
effect.event declined)"

/-- Stable diagnostic: pureCall / local `callFn` residual on Final path. -/
def diagCallFnNotAdmittedV1 : String :=
  "ALEO-IR-5: pureCall/callFn is not admitted on Instructions path \
(pure helpers residual FC; no local-call opcode lowering)"

/-- Stable diagnostic: payload `revert` (bare assert-false remains admitted). -/
def diagPayloadRevertNotAdmittedV1 : String :=
  "ALEO-IR-5: revert payloads are not admitted \
(Instructions bare revert only via assert.eq true false)"

/-- Documentation pin: external sync call fails earlier (resolver). -/
def diagExternalCallHonestyNoteV1 : String :=
  "ALEO-IR-5: effect.synchronous-call is declined at resolve on Aleo \
(no program-call Instructions surface; B-CALL-SEM open)"

/-- Documentation pin: schedule fails earlier (resolver). -/
def diagScheduleHonestyNoteV1 : String :=
  "ALEO-IR-5: effect.asynchronous-workflow is declined at resolve on Aleo \
(no Future/async Instructions surface)"

/-- Documentation pin: pf.assets / record custody zero-binding. -/
def diagAssetsRecordHonestyNoteV1 : String :=
  "ALEO-IR-5: pf.assets and record custody stay FC \
(ADR-0029 Phase D zero-binding; record mint/consume not admitted)"

/-- Documentation pin: ContextRead / EnvRead pilot FC. -/
def diagContextHonestyNoteV1 : String :=
  "ALEO-IR-5: ContextRead/EnvRead not admitted on Aleo pilot \
(no host clock / balance ABI in Final Instructions path)"

/-- Walk expressions for Plan-reachable effect residual (`callFn`). -/
private partial def checkExprEffectsHonestyV1 (e : Expr) : CompileResult Unit := do
  match e with
  | .callFn _ args => do
      for arg in args do
        checkExprEffectsHonestyV1 arg
      planError diagCallFnNotAdmittedV1
  | .literal _ | .i64Literal _ | .uintLiteral .. | .boolLiteral _
  | .param _ | .loopVar _ | .stateLoad _ | .fieldLiteral _ => pure ()
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r
  | .checkedDiv l r | .checkedMod l r
  | .bitAnd l r | .bitOr l r | .bitXor l r
  | .shl l r | .shr l r
  | .logicalAnd l r | .logicalOr l r
  | .compare _ l r
  | .signedCheckedAdd l r | .signedCheckedSub l r | .signedCheckedMul l r
  | .signedCheckedDiv l r | .signedCheckedMod l r
  | .signedBitAnd l r | .signedBitOr l r | .signedBitXor l r
  | .signedShl l r | .signedShr l r
  | .signedCompare _ l r
  | .narrowCheckedAdd _ l r | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r
  | .narrowCheckedDiv _ l r | .narrowCheckedMod _ l r
  | .narrowBitAnd _ l r | .narrowBitOr _ l r | .narrowBitXor _ l r
  | .narrowShl _ l r | .narrowShr _ l r
  | .fieldBinary _ l r | .fieldCompare _ l r => do
      checkExprEffectsHonestyV1 l
      checkExprEffectsHonestyV1 r
  | .bitNot o | .boolNot o | .checkedNeg o | .signedBitNot o
  | .narrowBitNot _ o | .fieldNeg o =>
      checkExprEffectsHonestyV1 o
  | .ternary c t e' => do
      checkExprEffectsHonestyV1 c
      checkExprEffectsHonestyV1 t
      checkExprEffectsHonestyV1 e'

/-- Walk statements for emit / payload-revert / nested effect residual. -/
private partial def checkStmtEffectsHonestyV1
    (stmts : Array Statement) : CompileResult Unit := do
  for stmt in stmts do
    match stmt with
    | .emitEvent .. => planError diagEmitNotAdmittedV1
    | .revertError _ args =>
        unless args.isEmpty do
          planError diagPayloadRevertNotAdmittedV1
    | .store _ value => checkExprEffectsHonestyV1 value
    | .storeAggregate leaves =>
        for leaf in leaves do
          checkExprEffectsHonestyV1 leaf.value
    | .assert condition => checkExprEffectsHonestyV1 condition
    | .returnValue value => checkExprEffectsHonestyV1 value
    | .returnAggregate leaves _ =>
        for leaf in leaves do
          checkExprEffectsHonestyV1 leaf
    | .returnNone => pure ()
    | .ifThenElse condition thenBody elseBody => do
        checkExprEffectsHonestyV1 condition
        checkStmtEffectsHonestyV1 thenBody
        checkStmtEffectsHonestyV1 elseBody
    | .switchOn scrutinee cases defaultBody => do
        checkExprEffectsHonestyV1 scrutinee
        for (_, body) in cases do
          checkStmtEffectsHonestyV1 body
        checkStmtEffectsHonestyV1 defaultBody
    | .forLoop start endExclusive _ body => do
        checkExprEffectsHonestyV1 start
        checkExprEffectsHonestyV1 endExclusive
        checkStmtEffectsHonestyV1 body

/-- ALEO-IR-5 sole Plan-reachable effects honesty gate (runs before validatePlan). -/
def checkEffectsHonestyMatrixV1 (plan : Plan) : CompileResult Unit := do
  for fn in plan.functions do
    checkStmtEffectsHonestyV1 fn.body

private def boolLiteral (b : Bool) : OperandV1 :=
  .literal (if b then "true" else "false")

private def compareOpcode (op : ComparisonOp) : String :=
  match op with
  | .eq => "is.eq"
  | .ne => "is.neq"
  | .lt => "lt"
  | .le => "lte"
  | .gt => "gt"
  | .ge => "gte"

/-- Transition wrapper: `input*` → `async name args into r` → `output future`.
    Matches Leo 4.0.2 compile of state-touching Final functions. -/
def lowerTransitionFunctionV1
    (programName : String) (fnName : String) (params : Array PlanParam) :
    CompileResult FunctionDeclV1 := do
  let mut body : Array InstructionV1 := #[]
  for i in [0:params.size] do
    let ty ← paramInputType params[i]!
    body := body.push (.input ⟨i⟩ ty)
  let args : Array RegisterV1 :=
    (List.range params.size).toArray.map (fun i => ⟨i⟩)
  let dest : RegisterV1 := ⟨params.size⟩
  body := body.push (.asyncCall fnName args dest)
  body := body.push (.output dest (.future programName fnName))
  pure { name := fnName, body }

/-- Edition constructor (Leo 4.0.2 Counter golden). -/
def constructorEditionV1 : ConstructorDeclV1 :=
  { body := #[.assertEq (.identifier "edition") (.literal "0u16")] }

/-- initialize finalize preamble: init-guard (before body stores). -/
def lowerInitializeGuardV1 (nextReg : Nat) :
    Array InstructionV1 × Nat :=
  let rSeen : RegisterV1 := ⟨nextReg⟩
  let rNot : RegisterV1 := ⟨nextReg + 1⟩
  (#[
      .getOrUse guardMappingNameV1 mappingKeyLiteralV1 (.literal "false") rSeen,
      .unary "not" (.register rSeen) rNot,
      .assertEq (.register rNot) (.literal "true")
    ],
    nextReg + 2)

/-- Lower-state: sequential register allocator + label counter + loop stack. -/
structure LowerCtx where
  plan : Plan
  nextReg : Nat
  labelCounter : Nat
  /-- Loop induction values, index = loopDepth. -/
  loopVars : Array OperandV1
  /-- Final-block param registers: sourceIndex → register. -/
  paramRegs : Array RegisterV1
  deriving Inhabited

private def LowerCtx.fresh (ctx : LowerCtx) : RegisterV1 × LowerCtx :=
  (⟨ctx.nextReg⟩, { ctx with nextReg := ctx.nextReg + 1 })

private def LowerCtx.freshLabel (ctx : LowerCtx) (labelPrefix : String) :
    String × LowerCtx :=
  let name := s!"{labelPrefix}_{ctx.labelCounter}"
  (name, { ctx with labelCounter := ctx.labelCounter + 1 })

/-- Emit narrow/u64 binary op with result register. -/
private def lowerBinaryOp
    (ctx0 : LowerCtx) (op : String) (lhs rhs : Expr)
    (lowerExpr : LowerCtx → Expr →
      CompileResult (Array InstructionV1 × OperandV1 × LowerCtx)) :
    CompileResult (Array InstructionV1 × OperandV1 × LowerCtx) := do
  let (il, lo, ctx1) ← lowerExpr ctx0 lhs
  let (ir, ro, ctx2) ← lowerExpr ctx1 rhs
  let (dest, ctx3) := ctx2.fresh
  pure (il ++ ir ++ #[.binary op lo ro dest], .register dest, ctx3)

/-- Div/mod with explicit nonzero guard (typed zero literal). -/
private def lowerDivMod
    (ctx0 : LowerCtx) (op : String) (bitWidth : Nat) (lhs rhs : Expr)
    (lowerExpr : LowerCtx → Expr →
      CompileResult (Array InstructionV1 × OperandV1 × LowerCtx)) :
    CompileResult (Array InstructionV1 × OperandV1 × LowerCtx) := do
  let (il, lo, ctx1) ← lowerExpr ctx0 lhs
  let (ir, ro, ctx2) ← lowerExpr ctx1 rhs
  let (nz, ctx3) := ctx2.fresh
  let (dest, ctx4) := ctx3.fresh
  pure (
    il ++ ir ++ #[
      .binary "is.neq" ro (zeroLiteral bitWidth) nz,
      .assertEq (.register nz) (.literal "true"),
      .binary op lo ro dest
    ],
    .register dest,
    ctx4)

/-- Shift with `count < bitWidth` on u64 lane + cast count to u8 (EmitIR shape). -/
private def lowerShift
    (ctx0 : LowerCtx) (op : String) (bitWidth : Nat) (lhs rhs : Expr)
    (lowerExpr : LowerCtx → Expr →
      CompileResult (Array InstructionV1 × OperandV1 × LowerCtx)) :
    CompileResult (Array InstructionV1 × OperandV1 × LowerCtx) := do
  let (il, lo, ctx1) ← lowerExpr ctx0 lhs
  let (ir, ro, ctx2) ← lowerExpr ctx1 rhs
  let (countU64, ctx3) := ctx2.fresh
  let (ok, ctx4) := ctx3.fresh
  let (countU8, ctx5) := ctx4.fresh
  let (dest, ctx6) := ctx5.fresh
  pure (
    il ++ ir ++ #[
      .typeCast ro countU64 (.base .u64 .public_),
      .binary "lt" (.register countU64) (u64Literal bitWidth.toUInt64) ok,
      .assertEq (.register ok) (.literal "true"),
      .typeCast (.register countU64) countU8 (.base .u8 .public_),
      .binary op lo (.register countU8) dest
    ],
    .register dest,
    ctx6)

/-- Lower a Plan Expr to Instructions + result operand (UInt*/Bool). -/
partial def lowerExprV1 (ctx0 : LowerCtx) (expr : Expr) :
    CompileResult (Array InstructionV1 × OperandV1 × LowerCtx) := do
  match expr with
  | .literal v => pure (#[], u64Literal v, ctx0)
  | .uintLiteral bitWidth v => do
      unless isAdmittedUintWidth bitWidth do
        planError s!"ALEO-IR-4: unsupported uintLiteral width {bitWidth}"
      pure (#[], uintLiteral bitWidth v, ctx0)
  | .boolLiteral b => pure (#[], boolLiteral b, ctx0)
  | .param idx => do
      let some reg := ctx0.paramRegs[idx]? |
        planError s!"ALEO-IR-4: param {idx} out of range for finalize inputs"
      pure (#[], .register reg, ctx0)
  | .loopVar depth => do
      let some op := ctx0.loopVars[depth]? |
        planError s!"ALEO-IR-4: loopVar depth {depth} is out of range"
      pure (#[], op, ctx0)
  | .stateLoad fieldIndex => do
      let default ← defaultLiteralForLeaf ctx0.plan fieldIndex
      let (dest, ctx1) := ctx0.fresh
      let instr : InstructionV1 :=
        .getOrUse (mappingNameV1 fieldIndex) mappingKeyLiteralV1 default dest
      pure (#[instr], .register dest, ctx1)
  | .checkedAdd lhs rhs => lowerBinaryOp ctx0 "add" lhs rhs lowerExprV1
  | .checkedSub lhs rhs => lowerBinaryOp ctx0 "sub" lhs rhs lowerExprV1
  | .checkedMul lhs rhs => lowerBinaryOp ctx0 "mul" lhs rhs lowerExprV1
  | .checkedDiv lhs rhs => lowerDivMod ctx0 "div" 64 lhs rhs lowerExprV1
  | .checkedMod lhs rhs => lowerDivMod ctx0 "rem" 64 lhs rhs lowerExprV1
  | .narrowCheckedAdd w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowCheckedAdd width {w} not admitted"
      lowerBinaryOp ctx0 "add" lhs rhs lowerExprV1
  | .narrowCheckedSub w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowCheckedSub width {w} not admitted"
      lowerBinaryOp ctx0 "sub" lhs rhs lowerExprV1
  | .narrowCheckedMul w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowCheckedMul width {w} not admitted"
      lowerBinaryOp ctx0 "mul" lhs rhs lowerExprV1
  | .narrowCheckedDiv w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowCheckedDiv width {w} not admitted"
      lowerDivMod ctx0 "div" w lhs rhs lowerExprV1
  | .narrowCheckedMod w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowCheckedMod width {w} not admitted"
      lowerDivMod ctx0 "rem" w lhs rhs lowerExprV1
  | .compare op lhs rhs =>
      lowerBinaryOp ctx0 (compareOpcode op) lhs rhs lowerExprV1
  | .boolNot operand => do
      let (io, oo, ctx1) ← lowerExprV1 ctx0 operand
      let (dest, ctx2) := ctx1.fresh
      pure (io ++ #[.unary "not" oo dest], .register dest, ctx2)
  | .logicalAnd lhs rhs => lowerBinaryOp ctx0 "and" lhs rhs lowerExprV1
  | .logicalOr lhs rhs => lowerBinaryOp ctx0 "or" lhs rhs lowerExprV1
  | .ternary condition thenValue elseValue => do
      let (ic, co, ctx1) ← lowerExprV1 ctx0 condition
      let (it, to, ctx2) ← lowerExprV1 ctx1 thenValue
      let (ie, eo, ctx3) ← lowerExprV1 ctx2 elseValue
      let (dest, ctx4) := ctx3.fresh
      pure (
        ic ++ it ++ ie ++ #[.ternary co to eo dest],
        .register dest,
        ctx4)
  | .bitAnd lhs rhs => lowerBinaryOp ctx0 "and" lhs rhs lowerExprV1
  | .bitOr lhs rhs => lowerBinaryOp ctx0 "or" lhs rhs lowerExprV1
  | .bitXor lhs rhs => lowerBinaryOp ctx0 "xor" lhs rhs lowerExprV1
  | .bitNot operand => do
      let (io, oo, ctx1) ← lowerExprV1 ctx0 operand
      let (dest, ctx2) := ctx1.fresh
      pure (io ++ #[.unary "not" oo dest], .register dest, ctx2)
  | .narrowBitAnd w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowBitAnd width {w} not admitted"
      lowerBinaryOp ctx0 "and" lhs rhs lowerExprV1
  | .narrowBitOr w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowBitOr width {w} not admitted"
      lowerBinaryOp ctx0 "or" lhs rhs lowerExprV1
  | .narrowBitXor w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowBitXor width {w} not admitted"
      lowerBinaryOp ctx0 "xor" lhs rhs lowerExprV1
  | .narrowBitNot w operand => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowBitNot width {w} not admitted"
      let (io, oo, ctx1) ← lowerExprV1 ctx0 operand
      let (dest, ctx2) := ctx1.fresh
      pure (io ++ #[.unary "not" oo dest], .register dest, ctx2)
  | .shl lhs rhs => lowerShift ctx0 "shl" 64 lhs rhs lowerExprV1
  | .shr lhs rhs => lowerShift ctx0 "shr" 64 lhs rhs lowerExprV1
  | .narrowShl w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowShl width {w} not admitted"
      lowerShift ctx0 "shl" w lhs rhs lowerExprV1
  | .narrowShr w lhs rhs => do
      unless isNarrowUintWidth w do
        planError s!"ALEO-IR-4: narrowShr width {w} not admitted"
      lowerShift ctx0 "shr" w lhs rhs lowerExprV1
  | .callFn .. =>
      planError diagCallFnNotAdmittedV1
  | .i64Literal _ | .signedCheckedAdd .. | .signedCheckedSub ..
  | .signedCheckedMul .. | .signedCheckedDiv .. | .signedCheckedMod ..
  | .signedCompare .. | .signedBitAnd .. | .signedBitOr .. | .signedBitXor ..
  | .signedShl .. | .signedShr .. | .signedBitNot .. | .checkedNeg _
  | .fieldLiteral _ | .fieldBinary .. | .fieldCompare .. | .fieldNeg _ =>
      planError
        "ALEO-IR-4: expression shape not admitted on Instructions path \
(Int64/Field residual FC; width matrix matches Leo admit minus signed/field leaf)"

mutual
  /-- Lower switch cases as a right-nested is.eq + branch chain (EmitIR shape). -/
  partial def lowerSwitchCasesV1
      (ctx0 : LowerCtx) (scrut : OperandV1)
      (remaining : List (UInt64 × Array Statement))
      (defaultBody : Array Statement) :
      CompileResult (Array InstructionV1 × LowerCtx) := do
    match remaining with
    | [] => lowerStatementsV1 ctx0 defaultBody
    | (value, caseBody) :: rest => do
        let (eqReg, ctx2) := ctx0.fresh
        let mut out : Array InstructionV1 := #[
          .binary "is.eq" scrut (u64Literal value) eqReg
        ]
        let (endThen, ctx3) := ctx2.freshLabel "end_then"
        let (endJoin, ctx4) := ctx3.freshLabel "end_otherwise"
        out := out.push
          (.branchEq (.register eqReg) (.literal "false") endThen)
        let (caseInstrs, ctx5) ← lowerStatementsV1 ctx4 caseBody
        out := out ++ caseInstrs
        out := out.push
          (.branchEq (.literal "true") (.literal "true") endJoin)
        out := out.push (.position endThen)
        let (restInstrs, ctx6) ←
          lowerSwitchCasesV1 ctx5 scrut rest defaultBody
        out := out ++ restInstrs
        out := out.push (.position endJoin)
        pure (out, ctx6)

  /-- Lower a statement list into finalize Instructions. -/
  partial def lowerStatementsV1
      (ctx0 : LowerCtx) (stmts : Array Statement) :
      CompileResult (Array InstructionV1 × LowerCtx) := do
    let mut acc : Array InstructionV1 := #[]
    let mut ctx := ctx0
    for stmt in stmts do
      match stmt with
      | .store fieldIndex value => do
          unless isAdmittedUintLeaf ctx.plan fieldIndex do
            planError
              s!"ALEO-IR-4: store leaf {fieldIndex} is not public UInt8/16/32/64"
          let (iv, vo, ctx1) ← lowerExprV1 ctx value
          acc := acc ++ iv
          acc := acc.push
            (.set vo (mappingNameV1 fieldIndex) mappingKeyLiteralV1)
          ctx := ctx1
      | .storeAggregate leaves => do
          -- IR-4: multi-leaf atomic batch — evaluate all on pre-store snapshot,
          -- then set (matches EmitIR storeAggregate / Map empty-upsert hazard fix).
          unless leaves.size ≥ 1 do
            planError "ALEO-IR-4: storeAggregate has no leaves"
          let mut prepared : Array (Nat × OperandV1) := #[]
          let mut ctxPrep := ctx
          for leaf in leaves do
            unless isAdmittedUintLeaf ctxPrep.plan leaf.fieldIndex do
              planError
                s!"ALEO-IR-4: storeAggregate leaf {leaf.fieldIndex} is not public UInt8/16/32/64"
            let (iv, vo, ctx1) ← lowerExprV1 ctxPrep leaf.value
            acc := acc ++ iv
            prepared := prepared.push (leaf.fieldIndex, vo)
            ctxPrep := ctx1
          for item in prepared do
            let (fieldIndex, vo) := item
            acc := acc.push
              (.set vo (mappingNameV1 fieldIndex) mappingKeyLiteralV1)
          ctx := ctxPrep
      | .assert condition => do
          let (ic, co, ctx1) ← lowerExprV1 ctx condition
          acc := acc ++ ic
          acc := acc.push (.assertEq co (.literal "true"))
          ctx := ctx1
      | .returnValue value => do
          -- Final model: evaluate for failure semantics; drop the value.
          let (iv, _, ctx1) ← lowerExprV1 ctx value
          acc := acc ++ iv
          ctx := ctx1
      | .returnAggregate leaves _ => do
          unless leaves.size ≤ 8 do
            planError "ALEO-IR-4: returnAggregate too large"
          for leaf in leaves do
            let (iv, _, ctx1) ← lowerExprV1 ctx leaf
            acc := acc ++ iv
            ctx := ctx1
      | .returnNone => pure ()
      | .ifThenElse condition thenBody elseBody => do
          let (ic, co, ctx1) ← lowerExprV1 ctx condition
          acc := acc ++ ic
          let (endThen, ctx2) := ctx1.freshLabel "end_then"
          let (endJoin, ctx3) := ctx2.freshLabel "end_otherwise"
          -- Skip then when condition is false (Leo 4.0.2 shape).
          acc := acc.push (.branchEq co (.literal "false") endThen)
          let (thenInstrs, ctx4) ← lowerStatementsV1 ctx3 thenBody
          acc := acc ++ thenInstrs
          acc := acc.push
            (.branchEq (.literal "true") (.literal "true") endJoin)
          acc := acc.push (.position endThen)
          let (elseInstrs, ctx5) ← lowerStatementsV1 ctx4 elseBody
          acc := acc ++ elseInstrs
          acc := acc.push (.position endJoin)
          ctx := ctx5
      | .switchOn scrutinee cases defaultBody => do
          let (is, so, ctx1) ← lowerExprV1 ctx scrutinee
          acc := acc ++ is
          let (caseInstrs, ctx2) ←
            lowerSwitchCasesV1 ctx1 so cases.toList defaultBody
          acc := acc ++ caseInstrs
          ctx := ctx2
      | .forLoop start endExclusive maxIter body => do
          unless maxIter ≤ maxForUnrollIterationsV1 do
            planError
              s!"ALEO-IR-4: bounded for maxIterations {maxIter} exceeds {maxForUnrollIterationsV1} (fail closed)"
          let (is, startOp, ctx1) ← lowerExprV1 ctx start
          let (ie, endOp, ctx2) ← lowerExprV1 ctx1 endExclusive
          acc := acc ++ is ++ ie
          -- if start < end { assert (end - start) <= maxIter }
          let (ltReg, ctx3) := ctx2.fresh
          acc := acc.push (.binary "lt" startOp endOp ltReg)
          let (skipAssert, ctx4) := ctx3.freshLabel "end_then"
          let (endAssert, ctx5) := ctx4.freshLabel "end_otherwise"
          acc := acc.push
            (.branchEq (.register ltReg) (.literal "false") skipAssert)
          let (span0, ctx6) := ctx5.fresh
          acc := acc.push (.binary "sub" endOp startOp span0)
          let (fits, ctx7) := ctx6.fresh
          acc := acc.push
            (.binary "lte" (.register span0) (u64Literal maxIter.toUInt64) fits)
          acc := acc.push (.assertEq (.register fits) (.literal "true"))
          acc := acc.push
            (.branchEq (.literal "true") (.literal "true") endAssert)
          acc := acc.push (.position skipAssert)
          acc := acc.push (.position endAssert)
          -- span = end - start for runtime iteration gate
          let (span, ctx8) := ctx7.fresh
          acc := acc.push (.binary "sub" endOp startOp span)
          let mut ctxL := ctx8
          for c in [0:maxIter] do
            let cLit := u64Literal c.toUInt64
            let (cLt, ctxA) := ctxL.fresh
            acc := acc.push (.binary "lt" cLit (.register span) cLt)
            let (skipBody, ctxB) := ctxA.freshLabel "end_then"
            let (endBody, ctxC) := ctxB.freshLabel "end_otherwise"
            acc := acc.push
              (.branchEq (.register cLt) (.literal "false") skipBody)
            -- i = start + c
            let (iReg, ctxD) := ctxC.fresh
            acc := acc.push (.binary "add" startOp cLit iReg)
            let ctxPush := {
              ctxD with
              loopVars := ctxD.loopVars.push (.register iReg)
            }
            let (bodyInstrs, ctxE) ← lowerStatementsV1 ctxPush body
            acc := acc ++ bodyInstrs
            -- pop loop var
            let ctxPop := {
              ctxE with
              loopVars := ctxE.loopVars.pop
            }
            acc := acc.push
              (.branchEq (.literal "true") (.literal "true") endBody)
            acc := acc.push (.position skipBody)
            acc := acc.push (.position endBody)
            ctxL := ctxPop
          ctx := ctxL
      | .emitEvent .. =>
          -- Defense-in-depth: IR-5 matrix gate should have rejected first.
          planError diagEmitNotAdmittedV1
      | .revertError _ args => do
          unless args.isEmpty do
            planError diagPayloadRevertNotAdmittedV1
          -- bare revert → assert false
          acc := acc.push
            (.assertEq (.literal "true") (.literal "false"))
    pure (acc, ctx)
end

/-- Build finalize input registers for public UInt* params only. -/
private def buildParamRegs (fn : PlanFunction) :
    CompileResult (Array RegisterV1) := do
  for p in fn.params do
    unless isAdmittedUintParam p do
      planError
        s!"ALEO-IR-4: function '{fn.name}' param '{p.name}' must be public UInt8/16/32/64"
  -- Dense 0..params.size-1 mapping used by Plan bodies.
  pure <| (List.range fn.params.size).toArray.map (fun i => ⟨i⟩)

/-- Finalize body for one PlanFunction (initialize gets guard + mark). -/
def lowerFinalizeBodyV1 (plan : Plan) (fn : PlanFunction) :
    CompileResult (Array InstructionV1) := do
  unless fn.touchesState do
    planError
      s!"ALEO-IR-4: function '{fn.name}' does not touch state (Final-only Instructions path)"
  unless !fn.isPureHelper do
    planError
      s!"ALEO-IR-4: pure helper '{fn.name}' is not admitted on Instructions path"
  for p in fn.params do
    unless isAdmittedUintParam p do
      planError
        s!"ALEO-IR-4: function '{fn.name}' params must be public UInt8/16/32/64"
  let arity := fn.params.size
  let mut body : Array InstructionV1 := #[]
  for i in [0:arity] do
    let ty ← paramInputType fn.params[i]!
    body := body.push (.input ⟨i⟩ ty)
  let paramRegs ← buildParamRegs fn
  let mut nextReg := arity
  -- initialize one-shot guard before body stores.
  if fn.kind == .initialize then
    let (guardInstrs, next') := lowerInitializeGuardV1 nextReg
    body := body ++ guardInstrs
    nextReg := next'
  let ctx0 : LowerCtx := {
    plan
    nextReg
    labelCounter := 0
    loopVars := #[]
    paramRegs
  }
  let (stmtInstrs, ctx1) ← lowerStatementsV1 ctx0 fn.body
  body := body ++ stmtInstrs
  -- initialize: mark initialized after body.
  if fn.kind == .initialize then
    body := body.push
      (.set (.literal "true") guardMappingNameV1 mappingKeyLiteralV1)
  -- silence unused (label counter advances via ctx1)
  let _ := ctx1.labelCounter
  pure body

/-- Classify a single PlanFunction into function + finalize pair. -/
def lowerFunctionV1
    (programName : String) (plan : Plan) (fn : PlanFunction) :
    CompileResult (FunctionDeclV1 × FinalizeDeclV1) := do
  let transition ←
    lowerTransitionFunctionV1 programName fn.name fn.params
  let finBody ← lowerFinalizeBodyV1 plan fn
  pure (transition, { name := fn.name, body := finBody })

/-- Lower an entire Plan to Instructions (multi-leaf UInt* + Final functions
    with IR-3 control flow + IR-4 narrow/multi-leaf + IR-5 effects honesty). -/
def lowerPlanToInstructionsV1 (plan : Plan) : CompileResult ProgramV1 := do
  -- IR-5 first: Plan-reachable effect residual with stable ALEO-IR-5 diagnostics
  -- (wins over shared ValidatePlan Leo-path wording for Instructions tests).
  checkEffectsHonestyMatrixV1 plan
  validatePlan plan
  unless plan.stateFieldNames.size ≥ 1 do
    planError
      s!"ALEO-IR-4: expected at least one state leaf, got {plan.stateFieldNames.size}"
  for i in [0:plan.stateFieldNames.size] do
    unless isAdmittedUintLeaf plan i do
      planError
        s!"ALEO-IR-4: state leaf {i} ('{plan.stateFieldNames[i]!}') is not public UInt8/16/32/64 (Int64/Field residual FC)"
  for view in plan.views do
    unless view.stateFieldIndex < plan.stateFieldNames.size do
      planError s!"ALEO-IR-4: view '{view.name}' references missing state"
  unless plan.functions.size ≥ 1 do
    planError "ALEO-IR-4: expected at least one function (initialize)"
  let programName ← programNameFromPlanV1 plan
  let mut items : Array ItemV1 := #[]
  for i in [0:plan.stateFieldNames.size] do
    let valueType ← mappingValueTypeForLeaf plan i
    items := items.push (.mapping {
      name := mappingNameV1 i
      keyType := .base .u8 .public_
      valueType
    })
  items := items.push (.mapping {
    name := guardMappingNameV1
    keyType := .base .u8 .public_
    valueType := .base .boolean .public_
  })
  let mut sawInitialize := false
  for fn in plan.functions do
    if fn.isPureHelper then
      planError
        s!"ALEO-IR-4: pure helper '{fn.name}' is not admitted on Instructions path"
    let (fDecl, finDecl) ← lowerFunctionV1 programName plan fn
    match fn.kind with
    | .initialize => sawInitialize := true
    | .mutate => pure ()
    items := items.push (.function fDecl)
    items := items.push (.finalize finDecl)
  unless sawInitialize do
    planError "ALEO-IR-4: requires an initialize function"
  items := items.push (.constructor constructorEditionV1)
  pure { name := programName, items }

/-- Capability path: materialize Plan then Instructions lower. -/
def programFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult ProgramV1 := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lowerPlanToInstructionsV1 plan

/-- Hand-built / test Plan → Instructions (same as product after validate). -/
def lowerPlanForTestV1 (plan : Plan) : CompileResult ProgramV1 :=
  lowerPlanToInstructionsV1 plan

/-- IR-2 template helpers retained for Counter golden documentation / tests. -/
def lowerInitializeFinalizeV1 (fieldIndex : Nat) : Array InstructionV1 :=
  let m := mappingNameV1 fieldIndex
  #[
    .input ⟨0⟩ (.base .u64 .public_),
    .getOrUse guardMappingNameV1 mappingKeyLiteralV1 (.literal "false") ⟨1⟩,
    .unary "not" (.register ⟨1⟩) ⟨2⟩,
    .assertEq (.register ⟨2⟩) (.literal "true"),
    .set (.register ⟨0⟩) m mappingKeyLiteralV1,
    .set (.literal "true") guardMappingNameV1 mappingKeyLiteralV1
  ]

def lowerCheckedAddStoreReturnFinalizeV1 (fieldIndex : Nat) :
    Array InstructionV1 :=
  let m := mappingNameV1 fieldIndex
  #[
    .input ⟨0⟩ (.base .u64 .public_),
    .getOrUse m mappingKeyLiteralV1 (.literal "0u64") ⟨1⟩,
    .binary "add" (.register ⟨1⟩) (.register ⟨0⟩) ⟨2⟩,
    .set (.register ⟨2⟩) m mappingKeyLiteralV1,
    .getOrUse m mappingKeyLiteralV1 (.literal "0u64") ⟨3⟩
  ]

end ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1
