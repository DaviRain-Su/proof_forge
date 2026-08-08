/-
  ALEO-IR-2/3: AleoPlan → Aleo Instructions program.

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
    * fail closed: pure helpers, multi-leaf/aggregate, emit, payload revert,
      unbounded (maxIterations > 4096), unsupported expr shapes

  Profile note (default vs compile):
    * Plan body is profile-insensitive (shared by
      `aleo-leo-4.0.2-u64-v1` and `aleo-leo-4.0.2-u64-compile-v1`).
    * Default source profile: product still emits Leo 4 source + query-contract
      (zero-tool); this lower is the engineering Instructions path for tests
      and the IR authority candidate — **not** product primary yet (IR-6).
    * Compile profile: product Leo source → locked `leo build` produces
      `*.compiled.aleo` extras; Counter Instructions from this lower must be
      structurally ≡ that golden (G1). Control-flow programs are tested
      structurally (G3), not as byte-identical Leo compile goldens yet.

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

private def isPublicUInt64Param (p : PlanParam) : Bool :=
  !p.isBool && !p.isInt && !p.isField &&
    (p.uintWidth == 0 || p.uintWidth == 64)

private def isPublicUInt64Leaf
    (plan : Plan) (fieldIndex : Nat) : Bool :=
  fieldIndex < plan.stateFieldNames.size &&
    !plan.stateFieldIsInt.getD fieldIndex false &&
    !plan.stateFieldIsField.getD fieldIndex false &&
    let w := plan.stateFieldUintWidth.getD fieldIndex 0
    w == 0 || w == 64

private def defaultLiteralForLeaf
    (plan : Plan) (fieldIndex : Nat) : CompileResult OperandV1 := do
  unless isPublicUInt64Leaf plan fieldIndex do
    planError
      s!"ALEO-IR-3: state leaf {fieldIndex} is not public UInt64 (multi-leaf/narrow/int/field deferred to IR-4)"
  pure (.literal "0u64")

private def u64Literal (v : UInt64) : OperandV1 :=
  .literal s!"{v}u64"

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
    (programName : String) (fnName : String) (arity : Nat) :
    CompileResult FunctionDeclV1 := do
  let mut body : Array InstructionV1 := #[]
  for i in [0:arity] do
    body := body.push (.input ⟨i⟩ (.base .u64 .public_))
  let args : Array RegisterV1 :=
    (List.range arity).toArray.map (fun i => ⟨i⟩)
  let dest : RegisterV1 := ⟨arity⟩
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

/-- Lower a Plan Expr to Instructions + result operand (public UInt64/Bool). -/
partial def lowerExprV1 (ctx0 : LowerCtx) (expr : Expr) :
    CompileResult (Array InstructionV1 × OperandV1 × LowerCtx) := do
  match expr with
  | .literal v => pure (#[], u64Literal v, ctx0)
  | .boolLiteral b => pure (#[], boolLiteral b, ctx0)
  | .param idx => do
      let some reg := ctx0.paramRegs[idx]? |
        planError s!"ALEO-IR-3: param {idx} out of range for finalize inputs"
      pure (#[], .register reg, ctx0)
  | .loopVar depth => do
      let some op := ctx0.loopVars[depth]? |
        planError s!"ALEO-IR-3: loopVar depth {depth} is out of range"
      pure (#[], op, ctx0)
  | .stateLoad fieldIndex => do
      unless isPublicUInt64Leaf ctx0.plan fieldIndex do
        planError
          s!"ALEO-IR-3: stateLoad leaf {fieldIndex} is not public UInt64"
      let default ← defaultLiteralForLeaf ctx0.plan fieldIndex
      let (dest, ctx1) := ctx0.fresh
      let instr : InstructionV1 :=
        .getOrUse (mappingNameV1 fieldIndex) mappingKeyLiteralV1 default dest
      pure (#[instr], .register dest, ctx1)
  | .checkedAdd lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "add" lo ro dest], .register dest, ctx3)
  | .checkedSub lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "sub" lo ro dest], .register dest, ctx3)
  | .checkedMul lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "mul" lo ro dest], .register dest, ctx3)
  | .checkedDiv lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      -- Explicit nonzero guard (matches EmitIR portable shape).
      let (nz, ctx3) := ctx2.fresh
      let (dest, ctx4) := ctx3.fresh
      pure (
        il ++ ir ++ #[
          .binary "is.neq" ro (.literal "0u64") nz,
          .assertEq (.register nz) (.literal "true"),
          .binary "div" lo ro dest
        ],
        .register dest,
        ctx4)
  | .checkedMod lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (nz, ctx3) := ctx2.fresh
      let (dest, ctx4) := ctx3.fresh
      pure (
        il ++ ir ++ #[
          .binary "is.neq" ro (.literal "0u64") nz,
          .assertEq (.register nz) (.literal "true"),
          .binary "rem" lo ro dest
        ],
        .register dest,
        ctx4)
  | .compare op lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (
        il ++ ir ++ #[.binary (compareOpcode op) lo ro dest],
        .register dest,
        ctx3)
  | .boolNot operand => do
      let (io, oo, ctx1) ← lowerExprV1 ctx0 operand
      let (dest, ctx2) := ctx1.fresh
      pure (io ++ #[.unary "not" oo dest], .register dest, ctx2)
  | .logicalAnd lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "and" lo ro dest], .register dest, ctx3)
  | .logicalOr lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "or" lo ro dest], .register dest, ctx3)
  | .ternary condition thenValue elseValue => do
      let (ic, co, ctx1) ← lowerExprV1 ctx0 condition
      let (it, to, ctx2) ← lowerExprV1 ctx1 thenValue
      let (ie, eo, ctx3) ← lowerExprV1 ctx2 elseValue
      let (dest, ctx4) := ctx3.fresh
      pure (
        ic ++ it ++ ie ++ #[.ternary co to eo dest],
        .register dest,
        ctx4)
  | .bitAnd lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "and" lo ro dest], .register dest, ctx3)
  | .bitOr lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "or" lo ro dest], .register dest, ctx3)
  | .bitXor lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (dest, ctx3) := ctx2.fresh
      pure (il ++ ir ++ #[.binary "xor" lo ro dest], .register dest, ctx3)
  | .bitNot operand => do
      let (io, oo, ctx1) ← lowerExprV1 ctx0 operand
      let (dest, ctx2) := ctx1.fresh
      pure (io ++ #[.unary "not" oo dest], .register dest, ctx2)
  | .shl lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      -- count < 64 guard (EmitIR portable).
      let (ok, ctx3) := ctx2.fresh
      let (dest, ctx4) := ctx3.fresh
      pure (
        il ++ ir ++ #[
          .binary "lt" ro (.literal "64u64") ok,
          .assertEq (.register ok) (.literal "true"),
          .binary "shl" lo ro dest
        ],
        .register dest,
        ctx4)
  | .shr lhs rhs => do
      let (il, lo, ctx1) ← lowerExprV1 ctx0 lhs
      let (ir, ro, ctx2) ← lowerExprV1 ctx1 rhs
      let (ok, ctx3) := ctx2.fresh
      let (dest, ctx4) := ctx3.fresh
      pure (
        il ++ ir ++ #[
          .binary "lt" ro (.literal "64u64") ok,
          .assertEq (.register ok) (.literal "true"),
          .binary "shr" lo ro dest
        ],
        .register dest,
        ctx4)
  | .i64Literal _ | .uintLiteral .. | .narrowCheckedAdd ..
  | .narrowCheckedSub .. | .narrowCheckedMul .. | .narrowCheckedDiv ..
  | .narrowCheckedMod .. | .signedCheckedAdd .. | .signedCheckedSub ..
  | .signedCheckedMul .. | .signedCheckedDiv .. | .signedCheckedMod ..
  | .signedCompare .. | .narrowBitAnd .. | .narrowBitOr .. | .narrowBitXor ..
  | .signedBitAnd .. | .signedBitOr .. | .signedBitXor .. | .narrowShl ..
  | .narrowShr .. | .signedShl .. | .signedShr .. | .signedBitNot ..
  | .narrowBitNot .. | .checkedNeg _ | .fieldLiteral _ | .fieldBinary ..
  | .fieldCompare .. | .fieldNeg _ | .callFn .. =>
      planError
        "ALEO-IR-3: expression shape not admitted on public-UInt64 Final Instructions path (narrow/signed/field/pureCall deferred)"

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
          unless isPublicUInt64Leaf ctx.plan fieldIndex do
            planError
              s!"ALEO-IR-3: store leaf {fieldIndex} is not public UInt64"
          let (iv, vo, ctx1) ← lowerExprV1 ctx value
          acc := acc ++ iv
          acc := acc.push
            (.set vo (mappingNameV1 fieldIndex) mappingKeyLiteralV1)
          ctx := ctx1
      | .storeAggregate leaves => do
          -- IR-3 admits only single public-UInt64 aggregate leaf (scalar store).
          unless leaves.size == 1 do
            planError
              "ALEO-IR-3: multi-leaf storeAggregate deferred to IR-4"
          let leaf := leaves[0]!
          let (iv, vo, ctx1) ← lowerExprV1 ctx leaf.value
          unless isPublicUInt64Leaf ctx.plan leaf.fieldIndex do
            planError
              s!"ALEO-IR-3: storeAggregate leaf {leaf.fieldIndex} is not public UInt64"
          acc := acc ++ iv
          acc := acc.push
            (.set vo (mappingNameV1 leaf.fieldIndex) mappingKeyLiteralV1)
          ctx := ctx1
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
            planError "ALEO-IR-3: returnAggregate too large"
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
              s!"ALEO-IR-3: bounded for maxIterations {maxIter} exceeds {maxForUnrollIterationsV1} (fail closed)"
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
          planError
            "ALEO-IR-3: emit is not admitted (no on-chain event log in Aleo Instructions)"
      | .revertError _ args => do
          unless args.isEmpty do
            planError "ALEO-IR-3: revert payloads are not admitted"
          -- bare revert → assert false
          acc := acc.push
            (.assertEq (.literal "true") (.literal "false"))
    pure (acc, ctx)
end

/-- Build finalize input registers for public UInt64 params only. -/
private def buildParamRegs (fn : PlanFunction) :
    CompileResult (Array RegisterV1) := do
  for p in fn.params do
    unless isPublicUInt64Param p do
      planError
        s!"ALEO-IR-3: function '{fn.name}' param '{p.name}' must be public UInt64"
  -- Dense 0..params.size-1 mapping used by Plan bodies.
  pure <| (List.range fn.params.size).toArray.map (fun i => ⟨i⟩)

/-- Finalize body for one PlanFunction (initialize gets guard + mark). -/
def lowerFinalizeBodyV1 (plan : Plan) (fn : PlanFunction) :
    CompileResult (Array InstructionV1) := do
  unless fn.touchesState do
    planError
      s!"ALEO-IR-3: function '{fn.name}' does not touch state (Final-only Instructions path)"
  unless !fn.isPureHelper do
    planError
      s!"ALEO-IR-3: pure helper '{fn.name}' is not admitted on Instructions path"
  unless fn.resultAggregateLeaves.isNone do
    planError
      s!"ALEO-IR-3: function '{fn.name}' aggregate results deferred (IR-4)"
  for p in fn.params do
    unless isPublicUInt64Param p do
      planError
        s!"ALEO-IR-3: function '{fn.name}' params must be public UInt64"
  let arity := fn.params.size
  let mut body : Array InstructionV1 := #[]
  for i in [0:arity] do
    body := body.push (.input ⟨i⟩ (.base .u64 .public_))
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
    lowerTransitionFunctionV1 programName fn.name fn.params.size
  let finBody ← lowerFinalizeBodyV1 plan fn
  pure (transition, { name := fn.name, body := finBody })

/-- Lower an entire Plan to Instructions (single public UInt64 leaf + Final
    functions with IR-3 control flow). -/
def lowerPlanToInstructionsV1 (plan : Plan) : CompileResult ProgramV1 := do
  validatePlan plan
  -- Single public UInt64 state leaf (IR-4 multi-leaf).
  unless plan.stateFieldNames.size == 1 do
    planError
      s!"ALEO-IR-3: expected exactly one state leaf, got {plan.stateFieldNames.size} (multi-leaf deferred to IR-4)"
  unless isPublicUInt64Leaf plan 0 do
    planError "ALEO-IR-3: sole state leaf must be public UInt64"
  for view in plan.views do
    unless view.stateFieldIndex < plan.stateFieldNames.size do
      planError s!"ALEO-IR-3: view '{view.name}' references missing state"
  unless plan.functions.size ≥ 1 do
    planError "ALEO-IR-3: expected at least one function (initialize)"
  let programName ← programNameFromPlanV1 plan
  let mut items : Array ItemV1 := #[]
  for i in [0:plan.stateFieldNames.size] do
    items := items.push (.mapping {
      name := mappingNameV1 i
      keyType := .base .u8 .public_
      valueType := .base .u64 .public_
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
        s!"ALEO-IR-3: pure helper '{fn.name}' is not admitted on Instructions path"
    let (fDecl, finDecl) ← lowerFunctionV1 programName plan fn
    match fn.kind with
    | .initialize => sawInitialize := true
    | .mutate => pure ()
    items := items.push (.function fDecl)
    items := items.push (.finalize finDecl)
  unless sawInitialize do
    planError "ALEO-IR-3: requires an initialize function"
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
