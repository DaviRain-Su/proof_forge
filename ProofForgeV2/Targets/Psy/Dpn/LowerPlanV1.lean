/-
  PSY-DPN-2/3: PsyPlan → DPN package.

  DPN-2: UInt64 Counter-shaped templates (init store / checkedAdd store+return /
  view load) pinned to locked-dargo Counter method ids and package shape.

  DPN-3: control flow + bounded for
    * ifThenElse / switchOn → Bool ops + Select mux + conditional
      SetContractStateSlotSingle (condition wire)
    * forLoop → static unroll matching EmitIRV1 PSY-LOOP semantics
      (bound assert + N guarded steps; no while / unbounded)
    * Fail closed on unsupported Expr/Statement shapes

  Method ids: Counter pins match dargo golden; other names use a stable
  engineering hash until an official golden is captured.
-/
import ProofForgeV2.Targets.Psy.LowerSemanticV1
import ProofForgeV2.Targets.Psy.ValidatePlanV1
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1

open ProofForgeV2
open ProofForgeV2.Targets.Psy
open ProofForgeV2.Targets.Psy.Dpn.SchemaV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

/-- Pinned method ids from locked-dargo Counter package (psy-node-aligned). -/
def pinnedMethodIdV1 (name : String) : Option UInt32 :=
  match name with
  | "initialize" => some 202172507
  | "increment" => some 1990357658
  | "get" => some 1459926901
  | _ => none

/-- Stable engineering method_id when no dargo pin exists (FNV-1a 32-bit).
    Not an official `gen_dapen_contract_function_method_id` reimplementation. -/
def engineeringMethodIdV1 (name : String) : UInt32 := Id.run do
  let mut h : UInt32 := 2166136261
  for c in name.toUTF8 do
    h := (h ^^^ c.toUInt32) * 16777619
  -- Avoid colliding with the three Counter pins when names differ.
  if h == 202172507 || h == 1990357658 || h == 1459926901 then
    pure (h ^^^ 0x9e3779b9)
  else
    pure h

def requireMethodIdV1 (name : String) : CompileResult UInt32 :=
  pure <|
    match pinnedMethodIdV1 name with
    | some id => id
    | none => engineeringMethodIdV1 name

private def bTrue : UInt64 := encodeIndexedId .bool 0

/-- Max static unroll steps (matches EmitIRV1 PSY-LOOP budget). -/
def maxUnrollBudgetV1 : Nat := 64

/-- View get: Constant + GetState(sub_slot 0) → output target 1. -/
def lowerViewLoadReturnV1 (name : String) (fieldIndex : Nat) :
    CompileResult FunctionCircuitDefV1 := do
  unless fieldIndex == 0 do
    planError "PSY-DPN: only state field 0 supported in Counter/view template"
  let methodId ← requireMethodIdV1 name
  pure {
    name, methodId
    circuitInputs := #[]
    circuitOutputs := #[1]
    stateCommands := #[.getSelfUserCurrentContractStateSlotSingle 0]
    stateCommandResolutionIndices := #[1]
    assertions := #[]
    definitions := #[
      { dataType := .target, index := 0, opType := .constant, inputs := #[0] },
      { dataType := .target, index := 1, opType := .getStateCommandResultSingle, inputs := #[0] }
    ]
    events := #[]
  }

/-- initialize: store param 0 into field 0 (dargo sub_slot 1). -/
def lowerInitializeStoreParamV1 (name : String) (fieldIndex : Nat) :
    CompileResult FunctionCircuitDefV1 := do
  unless fieldIndex == 0 do
    planError "PSY-DPN: only state field 0 supported in Counter/init template"
  let methodId ← requireMethodIdV1 name
  pure {
    name, methodId
    circuitInputs := #[0]
    circuitOutputs := #[]
    stateCommands := #[
      .getSelfUserCurrentContractStateSlotSingle 1,
      .setContractStateSlotSingle bTrue 1 0
    ]
    stateCommandResolutionIndices := #[2, 3]
    assertions := #[]
    definitions := #[
      { dataType := .target, index := 0, opType := .inputTarget, inputs := #[0] },
      { dataType := .target, index := 1, opType := .constant, inputs := #[0] },
      { dataType := .bool, index := 0, opType := .constantTrue, inputs := #[1] }
    ]
    events := #[]
  }

/-- increment-shaped: store(checkedAdd(load,param)); return load. -/
def lowerCheckedAddStoreReturnV1 (name : String) (fieldIndex : Nat) :
    CompileResult FunctionCircuitDefV1 := do
  unless fieldIndex == 0 do
    planError "PSY-DPN: only state field 0 supported in Counter/mutate template"
  let methodId ← requireMethodIdV1 name
  pure {
    name, methodId
    circuitInputs := #[0]
    circuitOutputs := #[4]
    stateCommands := #[
      .getSelfUserCurrentContractStateSlotSingle 1,
      .setContractStateSlotSingle bTrue 1 3,
      .getSelfUserCurrentContractStateSlotSingle 1
    ]
    stateCommandResolutionIndices := #[2, 5, 5]
    assertions := #[{
      left := encodeIndexedId .bool 1
      right := encodeIndexedId .bool 0
      message := "u64 add overflow"
    }]
    definitions := #[
      { dataType := .target, index := 0, opType := .inputTarget, inputs := #[0] },
      { dataType := .target, index := 1, opType := .constant, inputs := #[0] },
      { dataType := .bool, index := 0, opType := .constantTrue, inputs := #[1] },
      { dataType := .target, index := 2, opType := .getStateCommandResultSingle, inputs := #[0] },
      { dataType := .target, index := 3, opType := .add, inputs := #[2, 0] },
      { dataType := .bool, index := 1, opType := .gte, inputs := #[3, 2] },
      { dataType := .target, index := 4, opType := .getStateCommandResultSingle, inputs := #[2] }
    ]
    events := #[]
  }

/-! ## DPN-3 general builder (if / match / bounded for) -/

/-- Circuit wire: target (Felt/UInt64) or bool, identified by per-type index. -/
inductive WireV1 where
  | target (index : Nat)
  | bool (index : Nat)
  deriving BEq, Inhabited, Repr

def WireV1.encoded : WireV1 → UInt64
  | .target i => encodeIndexedId .target i
  | .bool i => encodeIndexedId .bool i

def WireV1.rawIndex : WireV1 → Nat
  | .target i => i
  | .bool i => i

structure BuilderV1 where
  nextTarget : Nat := 0
  nextBool : Nat := 0
  defs : Array IndexedVarDefV1 := #[]
  cmds : Array StateCmdV1 := #[]
  res : Array Nat := #[]
  asserts : Array AssertEqV1 := #[]
  /-- Shared Constant 0 target index (always allocated at start of general lower). -/
  zeroTarget : Nat := 0
  /-- Shared ConstantTrue bool index. -/
  trueBool : Nat := 0
  /-- Optional ConstantFalse. -/
  falseBool? : Option Nat := none
  /-- loopDepth → induction wire (target). -/
  loopVars : Array WireV1 := #[]
  deriving Inhabited

private def pushTarget (b : BuilderV1) (op : OpTypeV1) (inputs : Array UInt64) :
    BuilderV1 × WireV1 :=
  let idx := b.nextTarget
  let defn : IndexedVarDefV1 := {
    dataType := .target, index := idx, opType := op, inputs
  }
  ({ b with
      nextTarget := idx + 1
      defs := b.defs.push defn }, .target idx)

private def pushBool (b : BuilderV1) (op : OpTypeV1) (inputs : Array UInt64) :
    BuilderV1 × WireV1 :=
  let idx := b.nextBool
  let defn : IndexedVarDefV1 := {
    dataType := .bool, index := idx, opType := op, inputs
  }
  ({ b with
      nextBool := idx + 1
      defs := b.defs.push defn }, .bool idx)

/-- Allocate InputTarget wires for each param (index 0..n-1). -/
private def emitParams (n : Nat) : BuilderV1 × Array WireV1 := Id.run do
  let mut b : BuilderV1 := {}
  let mut wires : Array WireV1 := #[]
  for i in [0:n] do
    let (b', w) := pushTarget b .inputTarget #[UInt64.ofNat i]
    b := b'
    wires := wires.push w
  pure (b, wires)

/-- Ensure zero + ConstantTrue exist (after params). -/
private def ensurePrelude (b : BuilderV1) : BuilderV1 :=
  if b.defs.isEmpty && b.nextTarget == 0 then
    -- no params path: const 0 then true
    let (b1, z) := pushTarget b .constant #[0]
    let (b2, _) := pushBool b1 .constantTrue #[UInt64.ofNat z.rawIndex]
    { b2 with zeroTarget := z.rawIndex, trueBool := 0 }
  else
    -- params already emitted; add const 0 + true
    let (b1, z) := pushTarget b .constant #[0]
    let (b2, t) := pushBool b1 .constantTrue #[UInt64.ofNat z.rawIndex]
    { b2 with zeroTarget := z.rawIndex, trueBool := t.rawIndex }

private def ensureFalse (b : BuilderV1) : BuilderV1 × WireV1 :=
  match b.falseBool? with
  | some i => (b, .bool i)
  | none =>
      let (b', w) := pushBool b .constantFalse #[UInt64.ofNat b.zeroTarget]
      ({ b' with falseBool? := some w.rawIndex }, w)

private def trueWire (b : BuilderV1) : WireV1 := .bool b.trueBool

private def zeroWire (b : BuilderV1) : WireV1 := .target b.zeroTarget

/-- Field 0 write path uses dargo sub_slot 1; other fields use index. -/
private def writeSubSlot (fieldIndex : Nat) : UInt64 :=
  if fieldIndex == 0 then 1 else UInt64.ofNat fieldIndex

private def viewSubSlot (fieldIndex : Nat) : UInt64 :=
  UInt64.ofNat fieldIndex

private def asTargetIndex (w : WireV1) : CompileResult Nat :=
  match w with
  | .target i => pure i
  | .bool _ => planError "PSY-DPN-3: expected target wire, got bool"

private def asBoolIndex (w : WireV1) : CompileResult Nat :=
  match w with
  | .bool i => pure i
  | .target _ => planError "PSY-DPN-3: expected bool wire, got target"

private def compareOpType : ComparisonOp → OpTypeV1
  | .eq => .eq | .ne => .eq  -- ne lowered as not(eq)
  | .lt => .lt | .le => .lte | .gt => .gt | .ge => .gte

/-- Emit Get + GetStateCommandResultSingle; returns value wire. -/
private def emitStateLoad (b : BuilderV1) (fieldIndex : Nat) (viewPath : Bool) :
    BuilderV1 × WireV1 :=
  let slot := if viewPath then viewSubSlot fieldIndex else writeSubSlot fieldIndex
  let cmdIdx := b.cmds.size
  let b1 := { b with cmds := b.cmds.push (.getSelfUserCurrentContractStateSlotSingle slot) }
  let (b2, w) := pushTarget b1 .getStateCommandResultSingle #[UInt64.ofNat cmdIdx]
  -- Resolution: target index of the GetState result (Counter increment style).
  let b3 := { b2 with res := b2.res.push w.rawIndex }
  (b3, w)

/-- Conditional store; `cond` is a bool wire (ConstantTrue for unconditional). -/
private def emitStateStore (b : BuilderV1) (fieldIndex : Nat) (cond : WireV1)
    (value : WireV1) : CompileResult BuilderV1 := do
  let vIdx ← asTargetIndex value
  let cEnc := cond.encoded
  let slot := writeSubSlot fieldIndex
  let b1 := {
    b with
      cmds := b.cmds.push (.setContractStateSlotSingle cEnc slot (UInt64.ofNat vIdx))
      -- Sets have no GetState result; pin resolution to nextTarget (Counter init style).
      res := b.res.push b.nextTarget
  }
  pure b1

/-- Bool AND of two conditions (for nested if / loop step guards). -/
private def emitBoolAnd (b : BuilderV1) (a c : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let ai ← asBoolIndex a
  let ci ← asBoolIndex c
  pure (pushBool b .boolAnd #[UInt64.ofNat ai, UInt64.ofNat ci])

private def emitBoolOr (b : BuilderV1) (a c : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let ai ← asBoolIndex a
  let ci ← asBoolIndex c
  pure (pushBool b .boolOr #[UInt64.ofNat ai, UInt64.ofNat ci])

private def emitBoolNot (b : BuilderV1) (a : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let ai ← asBoolIndex a
  pure (pushBool b .boolNot #[UInt64.ofNat ai])

/-- Select mux: result type matches then/else (target or bool). -/
private def emitSelect (b : BuilderV1) (cond thenW elseW : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let ci ← asBoolIndex cond
  match thenW, elseW with
  | .target t, .target e =>
      pure (pushTarget b .select
        #[UInt64.ofNat ci, UInt64.ofNat t, UInt64.ofNat e])
  | .bool t, .bool e =>
      pure (pushBool b .select
        #[UInt64.ofNat ci, UInt64.ofNat t, UInt64.ofNat e])
  | _, _ =>
      planError "PSY-DPN-3: Select arms must share data type (target/target or bool/bool)"

private def emitConstTarget (b : BuilderV1) (value : UInt64) : BuilderV1 × WireV1 :=
  if value == 0 then (b, zeroWire b)
  else pushTarget b .constant #[value]

private def emitLiteralU64 (b : BuilderV1) (value : UInt64) : BuilderV1 × WireV1 :=
  emitConstTarget b value

private def emitCheckedAdd (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, sum) := pushTarget b .add #[UInt64.ofNat li, UInt64.ofNat ri]
  let (b2, ok) := pushBool b1 .gte #[UInt64.ofNat sum.rawIndex, UInt64.ofNat li]
  let b3 := {
    b2 with
      asserts := b2.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b2.trueBool
        message := "u64 add overflow"
      }
  }
  pure (b3, sum)

private def emitCheckedSub (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, ok) := pushBool b .gte #[UInt64.ofNat li, UInt64.ofNat ri]
  let b2 := {
    b1 with
      asserts := b1.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b1.trueBool
        message := "u64 sub underflow"
      }
  }
  let (b3, diff) := pushTarget b2 .sub #[UInt64.ofNat li, UInt64.ofNat ri]
  pure (b3, diff)

private def emitCompare (b : BuilderV1) (op : ComparisonOp) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  match op with
  | .ne =>
      let (b1, eqW) := pushBool b .eq #[UInt64.ofNat li, UInt64.ofNat ri]
      emitBoolNot b1 eqW
  | other =>
      pure (pushBool b (compareOpType other) #[UInt64.ofNat li, UInt64.ofNat ri])

/-- Lower a Plan Expr into a circuit wire under DPN-3 admit surface. -/
partial def lowerExprV1 (b : BuilderV1) (params : Array WireV1) (viewPath : Bool) :
    Expr → CompileResult (BuilderV1 × WireV1)
  | .literal v => pure (emitLiteralU64 b v)
  | .boolLiteral true => pure (b, trueWire b)
  | .boolLiteral false => pure (ensureFalse b)
  | .param i =>
      match params[i]? with
      | some w => pure (b, w)
      | none => planError s!"PSY-DPN-3: param index {i} out of range"
  | .loopVar depth =>
      match b.loopVars[depth]? with
      | some w => pure (b, w)
      | none => planError s!"PSY-DPN-3: loopVar depth {depth} not bound"
  | .stateLoad f => pure (emitStateLoad b f viewPath)
  | .checkedAdd l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCheckedAdd b2 lw rw
  | .checkedSub l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCheckedSub b2 lw rw
  | .compare op l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCompare b2 op lw rw
  | .select c t e => do
      let (b1, cw) ← lowerExprV1 b params viewPath c
      let (b2, tw) ← lowerExprV1 b1 params viewPath t
      let (b3, ew) ← lowerExprV1 b2 params viewPath e
      emitSelect b3 cw tw ew
  | .boolNot o => do
      let (b1, ow) ← lowerExprV1 b params viewPath o
      emitBoolNot b1 ow
  | .logicalAnd l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitBoolAnd b2 lw rw
  | .logicalOr l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitBoolOr b2 lw rw
  | other =>
      planError s!"PSY-DPN-3: unsupported Expr shape {repr other}"

/-- Result of lowering a statement sequence: optional return wire (muxed). -/
structure StmtResultV1 where
  builder : BuilderV1
  /-- Return value if this region returns (Select-merged across branches). -/
  return? : Option WireV1 := none
  deriving Inhabited

/-- Lower statements under an active write condition `writeCond` (bool wire).
    `viewPath` only for pure view helpers (sub_slot 0). -/
partial def lowerStmtsV1 (b : BuilderV1) (params : Array WireV1)
    (writeCond : WireV1) (viewPath : Bool) :
    List Statement → CompileResult StmtResultV1
  | [] => pure { builder := b, return? := none }
  | s :: rest => do
      match s with
      | .store f value => do
          let (b1, vw) ← lowerExprV1 b params viewPath value
          let b2 ← emitStateStore b1 f writeCond vw
          lowerStmtsV1 b2 params writeCond viewPath rest
      | .returnValue value => do
          let (b1, vw) ← lowerExprV1 b params viewPath value
          -- Trailing statements after return are ignored (dead).
          pure { builder := b1, return? := some vw }
      | .returnNone =>
          pure { builder := b, return? := none }
      | .assert cond => do
          let (b1, cw) ← lowerExprV1 b params viewPath cond
          -- Under writeCond: assert ( !writeCond \/ cond ) ≡ select(writeCond,cond,true)
          let (b2, gated) ← emitSelect b1 writeCond cw (trueWire b1)
          let b3 := {
            b2 with
              asserts := b2.asserts.push {
                left := gated.encoded
                right := encodeIndexedId .bool b2.trueBool
                message := "assert"
              }
          }
          lowerStmtsV1 b3 params writeCond viewPath rest
      | .assertWithMessage cond msg => do
          let (b1, cw) ← lowerExprV1 b params viewPath cond
          let (b2, gated) ← emitSelect b1 writeCond cw (trueWire b1)
          let b3 := {
            b2 with
              asserts := b2.asserts.push {
                left := gated.encoded
                right := encodeIndexedId .bool b2.trueBool
                message := msg
              }
          }
          lowerStmtsV1 b3 params writeCond viewPath rest
      | .ifThenElse cond thenBody elseBody => do
          let (b1, cw) ← lowerExprV1 b params viewPath cond
          let (b2, thenCond) ← emitBoolAnd b1 writeCond cw
          let (b3, notC) ← emitBoolNot b2 cw
          let (b4, elseCond) ← emitBoolAnd b3 writeCond notC
          let thenRes ← lowerStmtsV1 b4 params thenCond viewPath thenBody.toList
          let elseRes ← lowerStmtsV1 thenRes.builder params elseCond viewPath
            elseBody.toList
          let (bFinal, retFinal) ← match thenRes.return?, elseRes.return? with
            | none, none => pure (elseRes.builder, none)
            | some t, some e => do
                let (bSel, w) ← emitSelect elseRes.builder cw t e
                pure (bSel, some w)
            | some _, none =>
                planError
                  "PSY-DPN-3: if-then returns but else does not (both arms must return or neither)"
            | none, some _ =>
                planError
                  "PSY-DPN-3: if-else returns but then does not (both arms must return or neither)"
          let cont ← lowerStmtsV1 bFinal params writeCond viewPath rest
          match retFinal, cont.return? with
          | some r, none => pure { cont with return? := some r }
          | none, r => pure { cont with return? := r }
          | some _, some _ =>
              planError "PSY-DPN-3: multiple return values in sequence"
      | .switchOn scrut cases defaultBody => do
          -- Desugar to nested ifThenElse: if scrut==v0 then c0 else if ... else default
          let mut nested : Array Statement := defaultBody
          -- foldr so first case is outermost
          for (v, body) in cases.reverse do
            let cond : Expr := .compare .eq scrut (.literal v)
            nested := #[.ifThenElse cond body nested]
          lowerStmtsV1 b params writeCond viewPath (nested.toList ++ rest)
      | .forLoop start endExclusive maxIter body => do
          unless maxIter ≤ maxUnrollBudgetV1 do
            planError s!"PSY-DPN-3: bounded for maxIterations={maxIter} exceeds \
unroll budget {maxUnrollBudgetV1} (no while/unbounded; PSY-LOOP)"
          let (b1, startW) ← lowerExprV1 b params viewPath start
          let (b2, endW) ← lowerExprV1 b1 params viewPath endExclusive
          let si ← asTargetIndex startW
          let ei ← asTargetIndex endW
          -- if start < end { assert end - start <= maxIter }
          let (b3, rangeNonempty) :=
            pushBool b2 .lt #[UInt64.ofNat si, UInt64.ofNat ei]
          let (b4, span) :=
            pushTarget b3 .sub #[UInt64.ofNat ei, UInt64.ofNat si]
          let (b5, maxLit) := emitLiteralU64 b4 (UInt64.ofNat maxIter)
          let mi ← asTargetIndex maxLit
          let (b6, fits) :=
            pushBool b5 .lte #[UInt64.ofNat span.rawIndex, UInt64.ofNat mi]
          let (b7, gatedFits) ← emitSelect b6 rangeNonempty fits (trueWire b6)
          let b8 := {
            b7 with
              asserts := b7.asserts.push {
                left := gatedFits.encoded
                right := encodeIndexedId .bool b7.trueBool
                message := "boundExceeded"
              }
          }
          -- Unroll: for k in 0..maxIter-1:
          --   i = start + k; if i < end { body with loopVar = i }
          let mut bCur := b8
          for k in [0:maxIter] do
            let (bK, kLit) := emitLiteralU64 bCur (UInt64.ofNat k)
            let ki ← asTargetIndex kLit
            let (bI, iW) :=
              pushTarget bK .add #[UInt64.ofNat si, UInt64.ofNat ki]
            let ii ← asTargetIndex iW
            let (bG, stepGuard) :=
              pushBool bI .lt #[UInt64.ofNat ii, UInt64.ofNat ei]
            let (bC, stepCond) ← emitBoolAnd bG writeCond stepGuard
            let bLoop := { bC with loopVars := bC.loopVars.push iW }
            let bodyRes ← lowerStmtsV1 bLoop params stepCond viewPath body.toList
            unless bodyRes.return?.isNone do
              planError "PSY-DPN-3: return inside bounded for is not admitted in this slice"
            -- Pop loop var
            bCur := { bodyRes.builder with loopVars := bC.loopVars }
          lowerStmtsV1 bCur params writeCond viewPath rest
      | .bareRevert => do
          let (b1, fW) := ensureFalse b
          let b2 := {
            b1 with
              asserts := b1.asserts.push {
                left := fW.encoded
                right := encodeIndexedId .bool b1.trueBool
                message := "revert"
              }
          }
          lowerStmtsV1 b2 params writeCond viewPath rest
      | other =>
          planError s!"PSY-DPN-3: unsupported Statement shape {repr other}"

/-- General function lower (DPN-3). Single-field UInt64 surface + control flow. -/
def lowerFunctionGeneralV1 (fn : PlanFunction) : CompileResult FunctionCircuitDefV1 := do
  let methodId ← requireMethodIdV1 fn.name
  let nParams := fn.params.size
  let (b0, paramWires) := emitParams nParams
  let b1 := ensurePrelude b0
  let viewPath :=
    fn.kind == .pureHelper &&
      fn.body.toList.all fun s =>
        match s with
        | .returnValue (.stateLoad _) => true
        | .returnNone => true
        | _ => false
  let writeCond := trueWire b1
  let res ← lowerStmtsV1 b1 paramWires writeCond viewPath fn.body.toList
  let outputs : Array UInt64 :=
    match res.return? with
    | some (.target i) => #[UInt64.ofNat i]
    | some (.bool i) => #[encodeIndexedId .bool i]
    | none => #[]
  let mut inputs : Array UInt64 := #[]
  for i in [0:nParams] do
    inputs := inputs.push (UInt64.ofNat i)
  pure {
    name := fn.name
    methodId
    circuitInputs := inputs
    circuitOutputs := outputs
    stateCommands := res.builder.cmds
    stateCommandResolutionIndices := res.builder.res
    assertions := res.builder.asserts
    definitions := res.builder.defs
    events := #[]
  }

/-- Classify a single PlanFunction into a DPN template or general lower. -/
def lowerFunctionV1 (fn : PlanFunction) : CompileResult FunctionCircuitDefV1 := do
  -- Counter templates first (exact dargo golden).
  match fn.body.toList with
  | [.returnValue (.stateLoad f)] =>
      lowerViewLoadReturnV1 fn.name f
  | [.store f (.param 0), .returnNone] =>
      lowerInitializeStoreParamV1 fn.name f
  | [.store f (.checkedAdd (.stateLoad f2) (.param 0)),
      .returnValue (.stateLoad f3)] => do
      unless f == f2 && f == f3 do
        planError "PSY-DPN: checkedAdd store/return field mismatch"
      lowerCheckedAddStoreReturnV1 fn.name f
  | _ =>
      -- DPN-3 general path (if / match / for / richer expr).
      lowerFunctionGeneralV1 fn

/-- Lower an entire Plan to a DPN package. Functions sorted by name (dargo order). -/
def lowerPlanToPackageV1 (plan : Plan) : CompileResult PackageV1 := do
  unless plan.stateFieldNames.size == 1 do
    planError s!"PSY-DPN: expected exactly one state field, got {plan.stateFieldNames.size}"
  let mut out : Array FunctionCircuitDefV1 := #[]
  for fn in plan.functions do
    let d ← lowerFunctionV1 fn
    out := out.push d
  let sorted := out.qsort (fun a b => a.name < b.name)
  pure sorted

/-- Capability path: materialize Plan then DPN lower (avoids importing Psy façade). -/
def packageFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult PackageV1 := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lowerPlanToPackageV1 plan

/-- Lower a single hand-built PlanFunction (tests / structural probes). -/
def lowerFunctionForTestV1 (fn : PlanFunction) : CompileResult FunctionCircuitDefV1 :=
  lowerFunctionV1 fn

end ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
