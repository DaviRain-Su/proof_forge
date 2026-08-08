/-
  PSY-DPN-2/3/4/5/6/7: PsyPlan → DPN package (product dual-write via EmitIRV1).

  DPN-2: UInt64 Counter-shaped templates (init store / checkedAdd store+return /
  view load) pinned to locked-dargo Counter method ids and package shape.

  DPN-3: control flow + bounded for
    * ifThenElse / switchOn → Bool ops + Select mux + conditional
      SetContractStateSlotSingle (condition wire)
    * forLoop → static unroll matching EmitIRV1 PSY-LOOP semantics
      (bound assert + N guarded steps; no while / unbounded)
    * Fail closed on unsupported Expr/Statement shapes

  DPN-4: multi-leaf + wide UInt128 (4×UInt32 limbs on dargo010Vm only)
    * storeAggregate / returnAggregate → multi SlotSingle Get/Set
    * limbAdd/limbSub + select/compare + per-limb bitwise
    * multi-field sub_slot engineering map (single-field Counter templates
      keep dargo golden; multi-leaf uses fieldIndex+4 per WideCounter dargo)
    * UInt32 param range asserts
    * default profile may lower Option/Array multi-leaf; UInt128 Plan is
      already FC before DPN when profile ≠ psy-dargo-0.1.0-vm-v1

  G5-WIDE: bindWideUintMul / DivMod / Shift → DPN defs (UInt128 4×UInt32;
    UInt256 same algorithm when limbCount=8)
    * schoolbook 8×UInt16 mul (U32And/U32ShiftRight + Target Mul/Add;
      high-digit overflow assert) matching EmitIRV1
    * restoring binary div/mod fully unrolled (4×32-step regions; limb
      range + zero-div asserts; no Felt `/`/`%` for integer result)
    * limb shift: fixed bitWidth-step one-bit walk (U32Shift*/U32Or +
      Select; shl high-bit overflow); count < bitWidth assert
    * wideUint*Limb Expr refs resolve from bind tables; residual U256
      product package may still FC on non-wide residual Plan shapes

  G5-AGG: Array / Principal / Bytes (and named Struct flatten) multi-leaf
    * Same storeAggregate / returnAggregate → multi SlotSingle path as
      Option/Map/wide (fieldIndex+4 sub_slots when multiLeaf)
    * Array UInt64 N → N Felt leaves; Bytes 1..8 → N×UInt8 leaves;
      Principal/String wire identity → len + 8×UInt32 body (9 leaves);
      named Struct preorder flatten already Plan-admitted
    * Principal/String return stays Plan FC (9 > B-RET cap 8); Nested Map /
      Map return stay Plan FC (not DPN-invented)
    * Structural + product Plan→DPN tests in PsyDpnV1; optional dargo
      package byte-equality golden still residual

  DPN-5: dense Map UInt64 UInt64 cap-8 (24 occ/key/val Felt leaves)
    * Plan already expands IndexGet→Option Select tree + IndexSet upsert
      storeAggregate + map-full assert (LowerSemantic mapLookup/mapUpsert)
    * General builder admits Select/Bool/compare/storeAggregate path — no
      text `.psy` return-in-if (dargo syntax break on Map get match)
    * Nested Map / Map return stay FC at Plan (not DPN-invented)

  DPN-6: effects honesty matrix (PARTIAL only with product evidence)
    * emitEvent → DPNEventRecord (condition + GetCheckpointId/GetUserId/
      GetContractId + data wires); matches official emit_event compile shape
    * void externalCall → InvokeExternalContractFunctionSync (num_outputs=0)
      with FNV component hashes (same as EmitIR `__invoke_sync` PARTIAL)
    * schedule / assets / ContextRead / Commit / nonempty invariant stay FC
      (Plan already FC; DPN depth-defends schedule with stable diagnostic)
    * Not a runtime/Finalize/ordered-event/response gate; deployable=false

  G5-MATRIX: §3.2 admit-row scan pins (honest DPN vs residual vs Plan FC)
    * UInt64 checkedMul/Div/Mod + add/sub → DPN (mul inverse wrap check)
    * zero-arg revertError → assertions[] "revert"; payload args FC
    * R-NARROW (G5 residual): UInt8/16/32 Felt-carried checked add/sub/mul/
      div/mod + param range asserts + unsigned compare (mirror EmitIRV1;
      result < 2^w for add/mul; not field-wrap inverse). Narrow bitwise/
      shift remain residual.
    * R-INT (G5 residual): Int64 signedCompare/checkedNeg + Int{8,16,32}
      two's-complement narrow signed add/sub/mul/div/mod/neg/compare → DPN
      (mirror EmitIRV1; Felt-carried 0..2^w-1 / bias-2^(w-1) compare; overflow
      asserts). Int64 arith reuses UInt64 checkedAdd/Sub/Mul/Div/Mod path.
    * R-SHIFT-BIT (G5 residual): UInt64 shl/shr + checkedBitNot → DPN
      (mirror EmitIR invalidShift / representability asserts; dargo U32Shift*
      + CastFelt for Felt `<<`/`>>`; checkedBitNot = Gte + Sub mask)
    * R-PURE (G5 residual): pureFn/localCall callFn → DPN by inlining the
      pureHelper body into the caller circuit (arg wires as params; nested
      callFn fuel-bounded). Package omits pureHelper top-level methods
      (free helpers match EmitIR; not contract methods). Recursive/effectful
      pure body (store/emit/externalCall/schedule/stateLoad) fail closed.
    * R-HARD (G5 residual → hard-require): narrow bitwise/shift + Goldilocks
      Field expr → DPN (mirror EmitIR); `isPsyDpnG5HardResidualAllowlistV1`
      emptied — any Plan-admitted DPN lower failure hard-fails materialize
      (`PSY-DPN-G5-HARD`); no residual `.psy`-only dual-write path.
    * Bool/compare/logic/bare assert covered by general builder + suite pins

  Method ids: official `gen_dapen_contract_function_method_id` via
  SHA-256 (RES-METHOD-ID). Counter three-method pins remain as regression
  goldens; product path always uses the algorithm (p0.. naming matches EmitIR).
-/
import ProofForgeV2.Targets.Psy.LowerSemanticV1
import ProofForgeV2.Targets.Psy.ValidatePlanV1
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Crypto

namespace ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1

open ProofForgeV2
open ProofForgeV2.Targets.Psy
open ProofForgeV2.Targets.Psy.Dpn.SchemaV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

/-- Pinned method ids from locked-dargo Counter package (psy-node-aligned).
    Regression pins only — product path uses `genDapenContractFunctionMethodIdV1`. -/
def pinnedMethodIdV1 (name : String) : Option UInt32 :=
  match name with
  | "initialize" => some 202172507
  | "increment" => some 1990357658
  | "get" => some 1459926901
  | _ => none

/-- Official `psy_crypto::hash::utils::gen_dapen_contract_function_method_id`.

    preimage = `method_name` + `(` + join(`arg_name` + `[` + `size` + `]`, `,`) + `)`
    method_id = first 4 LE bytes of SHA-256(UTF-8 preimage) as `u32`.

    Felt / Bool / U32 each contribute size `1`. Multi-limb UInt128 is expanded
    at Plan time into one PlanParam per Felt leaf; EmitIR renames those to
    `p0,p1,p2,p3` each size 1 (not a single `p0[4]`). Verified against
    EmitIRV1 `p{sourceIndex}` emission and Counter dargo golden. -/
def genDapenContractFunctionMethodIdV1
    (methodName : String) (args : Array (String × Nat)) : UInt32 :=
  let argPortion :=
    String.intercalate ","
      (args.map (fun (n, sz) => s!"{n}[{sz}]")).toList
  let preimage := s!"{methodName}({argPortion})"
  let dig := ProofForgeV2.Crypto.sha256 preimage.toUTF8
  let b0 := dig[0]!.toUInt32
  let b1 := dig[1]!.toUInt32
  let b2 := dig[2]!.toUInt32
  let b3 := dig[3]!.toUInt32
  b0 ||| UInt32.shiftLeft b1 8 ||| UInt32.shiftLeft b2 16 |||
    UInt32.shiftLeft b3 24

/-- EmitIR renames each physical PlanParam to `p{sourceIndex}` with Felt size 1
    (Bool / UInt / Field leaves are each one circuit input). -/
def methodIdArgsFromPlanParamsV1 (params : Array PlanParam) : Array (String × Nat) :=
  params.map fun p => (s!"p{p.sourceIndex}", 1)

/-- Product method_id from method name + EmitIR-shaped `(name, size)` args. -/
def requireMethodIdV1 (name : String) (args : Array (String × Nat)) :
    CompileResult UInt32 :=
  pure (genDapenContractFunctionMethodIdV1 name args)

/-- Product method_id from a PlanFunction (caller package method name + p0.. args).
    pureHelper bodies are inlined and omitted from the package; only contract
    methods reach package emission, so method_id always uses the caller name. -/
def requireMethodIdFromPlanFnV1 (fn : PlanFunction) : CompileResult UInt32 :=
  requireMethodIdV1 fn.name (methodIdArgsFromPlanParamsV1 fn.params)

private def bTrue : UInt64 := encodeIndexedId .bool 0

/-- Max static unroll steps (matches EmitIRV1 PSY-LOOP budget). -/
def maxUnrollBudgetV1 : Nat := 64

/-- Max physical state leaves admitted in DPN-4/5/G5-AGG.
    Map UInt64 cap-8 = 24; Token Map+supply = 25; Option dual-leaf = 2;
    Principal wire identity = 9; Array UInt64 N / Bytes N ≤ 8; Struct flatten
    headroom for multi-state pilots (not a formal resource profile). -/
def maxStateLeavesV1 : Nat := 64

/-- View get: Constant + GetState(sub_slot 0) → output target 1. -/
def lowerViewLoadReturnV1 (name : String) (fieldIndex : Nat) :
    CompileResult FunctionCircuitDefV1 := do
  unless fieldIndex == 0 do
    planError "PSY-DPN: only state field 0 supported in Counter/view template"
  let methodId ← requireMethodIdV1 name #[]
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
  let methodId ← requireMethodIdV1 name #[("p0", 1)]
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
  let methodId ← requireMethodIdV1 name #[("p0", 1)]
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

/-! ## DPN-3/4 general builder (if / match / for / multi-leaf / wide limbs) -/

/-- Circuit wire: target (Felt/UInt64), bool, or u32Target, per-type index. -/
inductive WireV1 where
  | target (index : Nat)
  | bool (index : Nat)
  | u32 (index : Nat)
  deriving BEq, Inhabited, Repr

def WireV1.encoded : WireV1 → UInt64
  | .target i => encodeIndexedId .target i
  | .bool i => encodeIndexedId .bool i
  | .u32 i => encodeIndexedId .u32Target i

def WireV1.rawIndex : WireV1 → Nat
  | .target i => i
  | .bool i => i
  | .u32 i => i

/-- Operand id for DPN ops (matches dargo): Target→raw index, Bool/U32→encoded. -/
def WireV1.operand : WireV1 → UInt64
  | w => w.encoded

/-- G5-WIDE bind table entry: operationId → little-endian Target result limbs. -/
structure WideMulBindV1 where
  operationId : Nat
  limbs : Array WireV1
  deriving Inhabited

structure WideDivBindV1 where
  operationId : Nat
  quotient : Array WireV1
  remainder : Array WireV1
  deriving Inhabited

structure WideShiftBindV1 where
  operationId : Nat
  kind : WideUInt128ShiftKindV1
  limbs : Array WireV1
  deriving Inhabited

structure BuilderV1 where
  nextTarget : Nat := 0
  nextBool : Nat := 0
  nextU32 : Nat := 0
  defs : Array IndexedVarDefV1 := #[]
  cmds : Array StateCmdV1 := #[]
  res : Array Nat := #[]
  asserts : Array AssertEqV1 := #[]
  /-- DPN-6: ordered `DPNEventRecord` list (product emit PARTIAL). -/
  events : Array EventRecordV1 := #[]
  /-- Shared Constant 0 target index (always allocated at start of general lower). -/
  zeroTarget : Nat := 0
  /-- Shared ConstantTrue bool index. -/
  trueBool : Nat := 0
  /-- Optional ConstantFalse. -/
  falseBool? : Option Nat := none
  /-- loopDepth → induction wire (target). -/
  loopVars : Array WireV1 := #[]
  /-- True when Plan has >1 physical state leaf (DPN-4 multi-leaf map). -/
  multiLeaf : Bool := false
  /-- G5-WIDE: bindWideUintMul results (Target limbs). -/
  wideMulBinds : Array WideMulBindV1 := #[]
  /-- G5-WIDE: bindWideUintDivMod quotient+remainder limbs. -/
  wideDivBinds : Array WideDivBindV1 := #[]
  /-- G5-WIDE: bindWideUintShift results. -/
  wideShiftBinds : Array WideShiftBindV1 := #[]
  /-- R-PURE: pureHelper table for callFn inline (name → body). -/
  helpers : Array PlanFunction := #[]
  /-- R-PURE: nested callFn inline depth (0 = top-level method body). -/
  inlineDepth : Nat := 0
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

private def pushU32 (b : BuilderV1) (op : OpTypeV1) (inputs : Array UInt64) :
    BuilderV1 × WireV1 :=
  let idx := b.nextU32
  let defn : IndexedVarDefV1 := {
    dataType := .u32Target, index := idx, opType := op, inputs
  }
  ({ b with
      nextU32 := idx + 1
      defs := b.defs.push defn }, .u32 idx)

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

/-- Single-field Counter write path uses dargo sub_slot 1 for field 0.
    Multi-leaf uses fieldIndex+4 for both Get/Set (WideCounter locked-dargo
    evidence: total_0..3 → sub_slots 4..7). View-only Counter field 0 stays 0. -/
private def writeSubSlot (b : BuilderV1) (fieldIndex : Nat) : UInt64 :=
  if b.multiLeaf then
    UInt64.ofNat (fieldIndex + 4)
  else if fieldIndex == 0 then
    1
  else
    UInt64.ofNat fieldIndex

private def viewSubSlot (b : BuilderV1) (fieldIndex : Nat) : UInt64 :=
  if b.multiLeaf then
    UInt64.ofNat (fieldIndex + 4)
  else
    UInt64.ofNat fieldIndex

private def asTargetIndex (w : WireV1) : CompileResult Nat :=
  match w with
  | .target i => pure i
  | .bool _ => planError "PSY-DPN: expected target wire, got bool"
  | .u32 _ => planError "PSY-DPN: expected target wire, got u32 (castFelt first)"

private def asBoolIndex (w : WireV1) : CompileResult Nat :=
  match w with
  | .bool i => pure i
  | .target _ => planError "PSY-DPN: expected bool wire, got target"
  | .u32 _ => planError "PSY-DPN: expected bool wire, got u32"

/-- Cast U32Target → Target (official CastFelt; value-preserving). -/
private def emitCastFelt (b : BuilderV1) (w : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  match w with
  | .target _ => pure (b, w)
  | .u32 _ => pure (pushTarget b .castFelt #[w.operand])
  | .bool _ => planError "PSY-DPN: castFelt expects target/u32, got bool"

/-- Ensure wire is Target (CastFelt when U32). -/
private def ensureTarget (b : BuilderV1) (w : WireV1) :
    CompileResult (BuilderV1 × WireV1) :=
  emitCastFelt b w

private def compareOpType : ComparisonOp → OpTypeV1
  | .eq => .eq | .ne => .eq  -- ne lowered as not(eq)
  | .lt => .lt | .le => .lte | .gt => .gt | .ge => .gte

/-- Emit Get + GetStateCommandResultSingle; returns value wire. -/
private def emitStateLoad (b : BuilderV1) (fieldIndex : Nat) (viewPath : Bool) :
    BuilderV1 × WireV1 :=
  let slot := if viewPath then viewSubSlot b fieldIndex else writeSubSlot b fieldIndex
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
  let slot := writeSubSlot b fieldIndex
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

/-- Select mux. Official Select always yields Target (or Bool for bool arms).
    U32 arms pass encoded U32 ids into Target Select (dargo div/shift style).
    Condition uses full encoded bool id. -/
private def emitSelect (b : BuilderV1) (cond thenW elseW : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let _ ← asBoolIndex cond
  match thenW, elseW with
  | .bool _, .bool _ =>
      pure (pushBool b .select
        #[cond.operand, thenW.operand, elseW.operand])
  | .bool _, _ | _, .bool _ =>
      planError "PSY-DPN: Select bool arms must both be bool"
  | _, _ =>
      -- Target/U32/mixed → Target Select with encoded operands
      pure (pushTarget b .select
        #[cond.operand, thenW.operand, elseW.operand])

private def emitConstTarget (b : BuilderV1) (value : UInt64) : BuilderV1 × WireV1 :=
  if value == 0 then (b, zeroWire b)
  else pushTarget b .constant #[value]

private def emitLiteralU64 (b : BuilderV1) (value : UInt64) : BuilderV1 × WireV1 :=
  emitConstTarget b value

/-- Goldilocks prime (Psy Felt domain); same as EmitIRV1. -/
private def goldilocksPrimeV1 : Nat := 0xFFFFFFFF00000001

/-- Deterministic FNV-1a-ish 64-bit hash → Goldilocks Felt (matches EmitIR
    `hashComponent` for void sync call PARTIAL). -/
def hashComponentFeltV1 (s : String) : UInt64 := Id.run do
  let prime : UInt64 := 1099511628211
  let mut h : UInt64 := 14695981039346656037
  for c in s.toList do
    h := (h ^^^ c.toNat.toUInt64) * prime
  pure (UInt64.ofNat (h.toNat % goldilocksPrimeV1))

/-- Valueless context ops (GetUserId/GetContractId/GetCheckpointId): official
    dargo encodes `inputs: [0]` with Target data_type (token.json evidence). -/
private def pushValuelessTarget (b : BuilderV1) (op : OpTypeV1) :
    BuilderV1 × WireV1 :=
  pushTarget b op #[0]

/-- Gate a target wire under writeCond: select(writeCond, w, 0). When writeCond
    is the shared ConstantTrue, returns `w` unchanged (official unconditional). -/
private def gateTargetUnderCond (b : BuilderV1) (writeCond : WireV1) (w : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  if writeCond == .bool b.trueBool then
    pure (b, w)
  else
    emitSelect b writeCond w (zeroWire b)

/-- DPN-6 PARTIAL: emitEvent → `DPNEventRecord` matching official `emit_event`.
    Event name is source metadata only (not in DPNEventRecord). -/
private def emitEventRecordV1 (b : BuilderV1) (writeCond : WireV1)
    (argWires : Array WireV1) : CompileResult BuilderV1 := do
  -- Allocate identity context ops (one per emit; dargo does the same).
  let (b1, cpW) := pushValuelessTarget b .getCheckpointId
  let (b2, userW) := pushValuelessTarget b1 .getUserId
  let (b3, cidW) := pushValuelessTarget b2 .getContractId
  let (b4, cpG) ← gateTargetUnderCond b3 writeCond cpW
  let (b5, userG) ← gateTargetUnderCond b4 writeCond userW
  let (b6, cidG) ← gateTargetUnderCond b5 writeCond cidW
  let mut bCur := b6
  let mut data : Array UInt64 := #[]
  for aw in argWires do
    let (bG, gw) ← gateTargetUnderCond bCur writeCond aw
    bCur := bG
    let ti ← asTargetIndex gw
    data := data.push (UInt64.ofNat ti)
  let cpIdx ← asTargetIndex cpG
  let userIdx ← asTargetIndex userG
  let cidIdx ← asTargetIndex cidG
  let eventRec : EventRecordV1 := {
    condition := writeCond.encoded
    checkpointId := UInt64.ofNat cpIdx
    userId := UInt64.ofNat userIdx
    contractId := UInt64.ofNat cidIdx
    data
  }
  pure { bCur with events := bCur.events.push eventRec }

/-- DPN-6 PARTIAL: void externalCall → InvokeExternalContractFunctionSync.
    Hashed static QN components; num_outputs=0 (no response-binding). -/
private def emitVoidExternalCallV1 (b : BuilderV1) (writeCond : WireV1)
    (callee : Array String) (argWires : Array WireV1) :
    CompileResult BuilderV1 := do
  unless callee.size ≥ 2 do
    planError
      "PSY-DPN-6: external callee must have ≥2 QualifiedName components (PSY-CALL-EVENT)"
  let targetHash := hashComponentFeltV1 callee[0]!
  let methodHash := hashComponentFeltV1 callee[1]!
  let (b1, tidW) := emitConstTarget b targetHash
  let (b2, midW) := emitConstTarget b1 methodHash
  let ti ← asTargetIndex tidW
  let mi ← asTargetIndex midW
  let mut args : Array UInt64 := #[]
  for aw in argWires do
    let ai ← asTargetIndex aw
    args := args.push (UInt64.ofNat ai)
  pure {
    b2 with
      cmds := b2.cmds.push
        (.invokeExternalContractFunctionSync
          writeCond.encoded (UInt64.ofNat ti) (UInt64.ofNat mi) args 0)
      -- Void invoke: no consumed GetState result (official unused-result path).
      res := b2.res.push b2.nextTarget
  }

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

/-- UInt64 checked mul: `prod = l*r`; assert `l==0 || prod/l == r` (field-wrap
    inverse check matching EmitIRV1; safe divisor when l==0). -/
private def emitCheckedMul (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, prod) := pushTarget b .mul #[UInt64.ofNat li, UInt64.ofNat ri]
  let (b2, lIs0) :=
    pushBool b1 .eq #[UInt64.ofNat li, UInt64.ofNat b1.zeroTarget]
  let (b3, oneW) := emitLiteralU64 b2 1
  let oi ← asTargetIndex oneW
  -- safeL = select(l==0, 1, l) so div is never by zero
  let (b4, safeL) ← emitSelect b3 lIs0 (.target oi) l
  let si ← asTargetIndex safeL
  let (b5, quot) :=
    pushTarget b4 .div #[UInt64.ofNat prod.rawIndex, UInt64.ofNat si]
  let (b6, check) :=
    pushBool b5 .eq #[UInt64.ofNat quot.rawIndex, UInt64.ofNat ri]
  let (b7, ok) ← emitBoolOr b6 lIs0 check
  let b8 := {
    b7 with
      asserts := b7.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b7.trueBool
        message := "u64 mul overflow"
      }
  }
  pure (b8, prod)

private def emitCheckedDiv (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, nonzero) :=
    pushBool b .gt #[UInt64.ofNat ri, UInt64.ofNat b.zeroTarget]
  let b2 := {
    b1 with
      asserts := b1.asserts.push {
        left := nonzero.encoded
        right := encodeIndexedId .bool b1.trueBool
        message := "u64 div by zero"
      }
  }
  let (b3, q) := pushTarget b2 .div #[UInt64.ofNat li, UInt64.ofNat ri]
  pure (b3, q)

private def emitCheckedMod (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, nonzero) :=
    pushBool b .gt #[UInt64.ofNat ri, UInt64.ofNat b.zeroTarget]
  let b2 := {
    b1 with
      asserts := b1.asserts.push {
        left := nonzero.encoded
        right := encodeIndexedId .bool b1.trueBool
        message := "u64 mod by zero"
      }
  }
  let (b3, m) := pushTarget b2 .mod_ #[UInt64.ofNat li, UInt64.ofNat ri]
  pure (b3, m)

/-! ## R-NARROW: Felt-carried UInt{8,16,32} (mirror EmitIRV1) -/

/-- 2^bitWidth as Felt-legal Nat (only for w ∈ {8,16,32}). -/
private def narrowBoundV1 (bitWidth : Nat) : CompileResult Nat :=
  if bitWidth == 8 then pure 256
  else if bitWidth == 16 then pure 65536
  else if bitWidth == 32 then pure 4294967296
  else planError s!"PSY-DPN-G5: narrow bitWidth {bitWidth} not admitted (need 8/16/32)"

/-- Narrow checked add: `sum = l+r`; assert `sum < 2^w` (EmitIR width guard;
    field wrap cannot occur for in-range UInt32 operands under Goldilocks). -/
private def emitNarrowCheckedAdd (b : BuilderV1) (bitWidth : Nat) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, sum) := pushTarget b .add #[UInt64.ofNat li, UInt64.ofNat ri]
  let (b2, limW) := emitLiteralU64 b1 (UInt64.ofNat bound)
  let limIdx ← asTargetIndex limW
  let (b3, ok) :=
    pushBool b2 .lt #[UInt64.ofNat sum.rawIndex, UInt64.ofNat limIdx]
  let b4 := {
    b3 with
      asserts := b3.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b3.trueBool
        message := s!"u{bitWidth} add overflow"
      }
  }
  pure (b4, sum)

/-- Narrow checked sub: assert `l >= r` then `diff = l-r` (EmitIR). -/
private def emitNarrowCheckedSub (b : BuilderV1) (bitWidth : Nat) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let _ ← narrowBoundV1 bitWidth
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, ok) := pushBool b .gte #[UInt64.ofNat li, UInt64.ofNat ri]
  let b2 := {
    b1 with
      asserts := b1.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b1.trueBool
        message := s!"u{bitWidth} sub underflow"
      }
  }
  let (b3, diff) := pushTarget b2 .sub #[UInt64.ofNat li, UInt64.ofNat ri]
  pure (b3, diff)

/-- Narrow checked mul: `prod = l*r`; assert `prod < 2^w` (EmitIR; not UInt64
    field-wrap inverse — max UInt32 product is still < Goldilocks p). -/
private def emitNarrowCheckedMul (b : BuilderV1) (bitWidth : Nat) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, prod) := pushTarget b .mul #[UInt64.ofNat li, UInt64.ofNat ri]
  let (b2, limW) := emitLiteralU64 b1 (UInt64.ofNat bound)
  let limIdx ← asTargetIndex limW
  let (b3, ok) :=
    pushBool b2 .lt #[UInt64.ofNat prod.rawIndex, UInt64.ofNat limIdx]
  let b4 := {
    b3 with
      asserts := b3.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b3.trueBool
        message := s!"u{bitWidth} mul overflow"
      }
  }
  pure (b4, prod)

/-- Narrow checked div: assert `r > 0` then `l / r` (EmitIR `u{w} div by zero`). -/
private def emitNarrowCheckedDiv (b : BuilderV1) (bitWidth : Nat) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let _ ← narrowBoundV1 bitWidth
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, nonzero) :=
    pushBool b .gt #[UInt64.ofNat ri, UInt64.ofNat b.zeroTarget]
  let b2 := {
    b1 with
      asserts := b1.asserts.push {
        left := nonzero.encoded
        right := encodeIndexedId .bool b1.trueBool
        message := s!"u{bitWidth} div by zero"
      }
  }
  let (b3, q) := pushTarget b2 .div #[UInt64.ofNat li, UInt64.ofNat ri]
  pure (b3, q)

/-- Narrow checked mod: assert `r > 0` then `l % r` (EmitIR `u{w} mod by zero`). -/
private def emitNarrowCheckedMod (b : BuilderV1) (bitWidth : Nat) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let _ ← narrowBoundV1 bitWidth
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, nonzero) :=
    pushBool b .gt #[UInt64.ofNat ri, UInt64.ofNat b.zeroTarget]
  let b2 := {
    b1 with
      asserts := b1.asserts.push {
        left := nonzero.encoded
        right := encodeIndexedId .bool b1.trueBool
        message := s!"u{bitWidth} mod by zero"
      }
  }
  let (b3, m) := pushTarget b2 .mod_ #[UInt64.ofNat li, UInt64.ofNat ri]
  pure (b3, m)

/-! ## R-HARD: narrow UInt{8,16,32} bitwise/shift + bitNot (mirror EmitIRV1) -/

/-- `2^w − 1` mask for narrow bitNot (always a legal Goldilocks Felt). -/
private def narrowMaskV1 (bitWidth : Nat) : CompileResult Nat :=
  if bitWidth == 8 then pure 255
  else if bitWidth == 16 then pure 65535
  else if bitWidth == 32 then pure 4294967295
  else planError s!"PSY-DPN-G5: narrow bitWidth {bitWidth} not admitted (need 8/16/32)"

/-- Narrow bitAnd/Or/Xor: U32 op + CastFelt (same limb path as UInt64 bit*).
    Operands are range-checked at entry; result stays in-range when operands do.
    Inlined (not via later `emitLimbBitwise`) so this family stays above R-SHIFT. -/
private def emitNarrowBitwise (b : BuilderV1) (bitWidth : Nat) (op : OpTypeV1)
    (l r : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let _ ← narrowBoundV1 bitWidth
  let (b1, u) := pushU32 b op #[l.operand, r.operand]
  emitCastFelt b1 u

/-- Narrow bitNot: Felt `x ^ (2^w−1)` via U32Xor + CastFelt (EmitIR mask XOR). -/
private def emitNarrowBitNot (b : BuilderV1) (bitWidth : Nat) (o : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let mask ← narrowMaskV1 bitWidth
  let (b1, maskW) := emitLiteralU64 b (UInt64.ofNat mask)
  let (b2, u) := pushU32 b1 .u32Xor #[o.operand, maskW.operand]
  emitCastFelt b2 u

/-- Narrow shl: assert `count < w` then U32ShiftLeft + CastFelt + `result < 2^w`
    (mirror EmitIR invalidShift + post-shl width guard; dargo Felt `<<`). -/
private def emitNarrowShl (b : BuilderV1) (bitWidth : Nat) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let ri ← asTargetIndex r
  let (b1, wBound) := emitLiteralU64 b (UInt64.ofNat bitWidth)
  let wi ← asTargetIndex wBound
  let (b2, okCount) :=
    pushBool b1 .lt #[UInt64.ofNat ri, UInt64.ofNat wi]
  let b3 := {
    b2 with
      asserts := b2.asserts.push {
        left := okCount.encoded
        right := encodeIndexedId .bool b2.trueBool
        message := s!"invalidShift: count >= {bitWidth}"
      }
  }
  let (b4, u) := pushU32 b3 .u32ShiftLeft #[l.operand, r.operand]
  let (b5, res) ← emitCastFelt b4 u
  let resi ← asTargetIndex res
  let (b6, limW) := emitLiteralU64 b5 (UInt64.ofNat bound)
  let limi ← asTargetIndex limW
  let (b7, okRes) :=
    pushBool b6 .lt #[UInt64.ofNat resi, UInt64.ofNat limi]
  let b8 := {
    b7 with
      asserts := b7.asserts.push {
        left := okRes.encoded
        right := encodeIndexedId .bool b7.trueBool
        message := s!"u{bitWidth} shl overflow"
      }
  }
  pure (b8, res)

/-- Narrow shr: assert `count < w` then U32ShiftRight + CastFelt (EmitIR). -/
private def emitNarrowShr (b : BuilderV1) (bitWidth : Nat) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let _ ← narrowBoundV1 bitWidth
  let ri ← asTargetIndex r
  let (b1, wBound) := emitLiteralU64 b (UInt64.ofNat bitWidth)
  let wi ← asTargetIndex wBound
  let (b2, okCount) :=
    pushBool b1 .lt #[UInt64.ofNat ri, UInt64.ofNat wi]
  let b3 := {
    b2 with
      asserts := b2.asserts.push {
        left := okCount.encoded
        right := encodeIndexedId .bool b2.trueBool
        message := s!"invalidShift: count >= {bitWidth}"
      }
  }
  let (b4, u) := pushU32 b3 .u32ShiftRight #[l.operand, r.operand]
  emitCastFelt b4 u

/-! ## R-HARD: Goldilocks Field expr (mirror EmitIR; no checked overflow) -/

/-- Field binary: native Target add/sub/mul/div (exact mod Goldilocks; no
    UInt64 checked-arith guards). -/
private def emitFieldBinary (b : BuilderV1) (op : FieldArithOp) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let opType := match op with
    | .add => OpTypeV1.add | .sub => .sub | .mul => .mul | .div => .div
  pure (pushTarget b opType #[UInt64.ofNat li, UInt64.ofNat ri])

/-- Field negation: Target `0 - x` (Goldilocks inverse; no intMin). -/
private def emitFieldNeg (b : BuilderV1) (o : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let oi ← asTargetIndex o
  pure (pushTarget b .sub #[UInt64.ofNat b.zeroTarget, UInt64.ofNat oi])

/-! ## R-SHIFT-BIT: UInt64 shl/shr + checkedBitNot (mirror EmitIRV1 + dargo) -/

/-- UInt64 checkedBitNot: assert `x ≥ 2^32−1` then wrapping Felt sub
    `(2^32−2) − x` (exact UInt64 bitNot when representable; trap otherwise).
    Matches EmitIRV1 and locked-dargo `~` lowering. -/
private def emitCheckedBitNot (b : BuilderV1) (o : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let oi ← asTargetIndex o
  let (b1, threshold) := emitLiteralU64 b 4294967295  -- 2^32 − 1
  let ti ← asTargetIndex threshold
  let (b2, ok) :=
    pushBool b1 .gte #[UInt64.ofNat oi, UInt64.ofNat ti]
  let b3 := {
    b2 with
      asserts := b2.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b2.trueBool
        message := "u64 bitNot result not representable in Felt"
      }
  }
  let (b4, mask) := emitLiteralU64 b3 4294967294  -- 2^32 − 2 ≡ (2^64−1) (mod p)
  let mi ← asTargetIndex mask
  let (b5, res) :=
    pushTarget b4 .sub #[UInt64.ofNat mi, UInt64.ofNat oi]
  pure (b5, res)

/-- UInt64 shl: assert `count < 64` then U32ShiftLeft + CastFelt.
    Matches EmitIR invalidShift guard and locked-dargo Felt `<<` → U32ShiftLeft
    (no Target-level shift op in DPN whitelist; high bits beyond U32 truncate as
    dargo does). -/
private def emitUInt64Shl (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let _ ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, bound) := emitLiteralU64 b 64
  let bi ← asTargetIndex bound
  let (b2, ok) :=
    pushBool b1 .lt #[UInt64.ofNat ri, UInt64.ofNat bi]
  let b3 := {
    b2 with
      asserts := b2.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b2.trueBool
        message := "invalidShift: count >= 64"
      }
  }
  let (b4, u) := pushU32 b3 .u32ShiftLeft #[l.operand, r.operand]
  emitCastFelt b4 u

/-- UInt64 shr: assert `count < 64` then U32ShiftRight + CastFelt (dargo Felt `>>`). -/
private def emitUInt64Shr (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let _ ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, bound) := emitLiteralU64 b 64
  let bi ← asTargetIndex bound
  let (b2, ok) :=
    pushBool b1 .lt #[UInt64.ofNat ri, UInt64.ofNat bi]
  let b3 := {
    b2 with
      asserts := b2.asserts.push {
        left := ok.encoded
        right := encodeIndexedId .bool b2.trueBool
        message := "invalidShift: count >= 64"
      }
  }
  let (b4, u) := pushU32 b3 .u32ShiftRight #[l.operand, r.operand]
  emitCastFelt b4 u

/-! ## R-INT: Int64 + narrow Int{8,16,32} two's-complement (mirror EmitIRV1) -/

/-- Assert bool wire equals ConstantTrue (shared residual-lower style). -/
private def pushAssertTrue (b : BuilderV1) (cond : WireV1) (msg : String) :
    CompileResult BuilderV1 := do
  let _ ← asBoolIndex cond
  pure {
    b with
      asserts := b.asserts.push {
        left := cond.encoded
        right := encodeIndexedId .bool b.trueBool
        message := msg
      }
  }

/-- Target `!=` as `!(l == r)`. -/
private def emitTargetNe (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let (b1, eqW) := pushBool b .eq #[l.operand, r.operand]
  emitBoolNot b1 eqW

/-- Bool `!=` as `!(l == r)`. -/
private def emitBoolNe (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asBoolIndex l
  let ri ← asBoolIndex r
  let (b1, eqW) := pushBool b .eq #[UInt64.ofNat li, UInt64.ofNat ri]
  emitBoolNot b1 eqW

/-- Int64 checkedNeg: assert `x != 2^63` then field `0 - x` (EmitIR). -/
private def emitCheckedNegInt64 (b : BuilderV1) (o : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let oi ← asTargetIndex o
  let (b1, intMinW) := emitLiteralU64 b (UInt64.ofNat 9223372036854775808)
  let (b2, ok) ← emitTargetNe b1 o intMinW
  let b3 ← pushAssertTrue b2 ok "i64 neg overflow (intMin)"
  -- Field negation: 0 - x (zeroTarget is Constant 0).
  let (b4, neg) :=
    pushTarget b3 .sub #[UInt64.ofNat b3.zeroTarget, UInt64.ofNat oi]
  pure (b4, neg)

/-- Signed compare via bias then unsigned cmp (no `.ne` OpType — use not(eq)).
    Int64 bias 2^63; narrow bias 2^(w-1). Placed before emitCompare: inlines
    the same Target-compare rules. -/
private def emitSignedCompareBiased (b : BuilderV1) (bias : Nat)
    (op : ComparisonOp) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, biasW) := emitLiteralU64 b (UInt64.ofNat bias)
  let bi ← asTargetIndex biasW
  let (b2, nl) := pushTarget b1 .add #[UInt64.ofNat li, UInt64.ofNat bi]
  let (b3, nr) := pushTarget b2 .add #[UInt64.ofNat ri, UInt64.ofNat bi]
  match op with
  | .ne =>
      let (b4, eqW) :=
        pushBool b3 .eq #[nl.operand, nr.operand]
      emitBoolNot b4 eqW
  | other =>
      pure (pushBool b3 (compareOpType other) #[nl.operand, nr.operand])

/-- Narrow signed compare: two's-complement patterns in 0..2^w-1, bias 2^(w-1). -/
private def emitNarrowSignedCompare (b : BuilderV1) (bitWidth : Nat)
    (op : ComparisonOp) (l r : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let _ ← narrowBoundV1 bitWidth
  emitSignedCompareBiased b (Nat.pow 2 (bitWidth - 1)) op l r

/-- Int64 signed compare (bias 2^63). -/
private def emitSignedCompareInt64 (b : BuilderV1) (op : ComparisonOp)
    (l r : WireV1) : CompileResult (BuilderV1 × WireV1) :=
  emitSignedCompareBiased b 9223372036854775808 op l r

/-- Narrow checkedNeg: intMin traps; else select(x==0, 0, 2^w - x). -/
private def emitNarrowCheckedNeg (b : BuilderV1) (bitWidth : Nat) (o : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let half := Nat.pow 2 (bitWidth - 1)
  let oi ← asTargetIndex o
  let (b1, halfW) := emitLiteralU64 b (UInt64.ofNat half)
  let (b2, ok) ← emitTargetNe b1 o halfW
  let b3 ← pushAssertTrue b2 ok s!"i{bitWidth} neg overflow (intMin)"
  let (b4, is0) :=
    pushBool b3 .eq #[UInt64.ofNat oi, UInt64.ofNat b3.zeroTarget]
  let (b5, boundW) := emitLiteralU64 b4 (UInt64.ofNat bound)
  let bndi ← asTargetIndex boundW
  let (b6, subW) :=
    pushTarget b5 .sub #[UInt64.ofNat bndi, UInt64.ofNat oi]
  emitSelect b6 is0 (zeroWire b6) subW

/-- Same-sign overflow flag: `(sa&&sb || !sa&&!sb) && (sa != sr)`. -/
private def emitSameSignOverflow (b : BuilderV1) (sa sb sr : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let (b1, bothNeg) ← emitBoolAnd b sa sb
  let (b2, notSa) ← emitBoolNot b1 sa
  let (b3, notSb) ← emitBoolNot b2 sb
  let (b4, bothPos) ← emitBoolAnd b3 notSa notSb
  let (b5, sameSign) ← emitBoolOr b4 bothNeg bothPos
  let (b6, ne) ← emitBoolNe b5 sa sr
  emitBoolAnd b6 sameSign ne

/-- Opposite-sign (sub) overflow flag: `(sa&&!sb || !sa&&sb) && (sa != sr)`. -/
private def emitDiffSignOverflow (b : BuilderV1) (sa sb sr : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let (b1, notSb) ← emitBoolNot b sb
  let (b2, aNegBPos) ← emitBoolAnd b1 sa notSb
  let (b3, notSa) ← emitBoolNot b2 sa
  let (b4, aPosBNeg) ← emitBoolAnd b3 notSa sb
  let (b5, diffSign) ← emitBoolOr b4 aNegBPos aPosBNeg
  let (b6, ne) ← emitBoolNe b5 sa sr
  emitBoolAnd b6 diffSign ne

/-- Narrow signed checked add: modular wrap + same-sign overflow trap. -/
private def emitNarrowSignedCheckedAdd (b : BuilderV1) (bitWidth : Nat)
    (l r : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let half := Nat.pow 2 (bitWidth - 1)
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, sum) := pushTarget b .add #[UInt64.ofNat li, UInt64.ofNat ri]
  let (b2, boundW) := emitLiteralU64 b1 (UInt64.ofNat bound)
  let bndi ← asTargetIndex boundW
  let (b3, geBound) :=
    pushBool b2 .gte #[UInt64.ofNat sum.rawIndex, UInt64.ofNat bndi]
  let (b4, wrapped) :=
    pushTarget b3 .sub #[UInt64.ofNat sum.rawIndex, UInt64.ofNat bndi]
  let (b5, wrap) ← emitSelect b4 geBound wrapped sum
  let (b6, halfW) := emitLiteralU64 b5 (UInt64.ofNat half)
  let hi ← asTargetIndex halfW
  let (b7, sa) := pushBool b6 .gte #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b8, sb) := pushBool b7 .gte #[UInt64.ofNat ri, UInt64.ofNat hi]
  let wi ← asTargetIndex wrap
  let (b9, sr) := pushBool b8 .gte #[UInt64.ofNat wi, UInt64.ofNat hi]
  let (b10, ovf) ← emitSameSignOverflow b9 sa sb sr
  let (b11, ok) ← emitBoolNot b10 ovf
  let b12 ← pushAssertTrue b11 ok s!"i{bitWidth} add overflow"
  pure (b12, wrap)

/-- Narrow signed checked sub: modular borrow + opposite-sign overflow trap. -/
private def emitNarrowSignedCheckedSub (b : BuilderV1) (bitWidth : Nat)
    (l r : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let half := Nat.pow 2 (bitWidth - 1)
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, ge) := pushBool b .gte #[UInt64.ofNat li, UInt64.ofNat ri]
  let (b2, direct) := pushTarget b1 .sub #[UInt64.ofNat li, UInt64.ofNat ri]
  let (b3, boundW) := emitLiteralU64 b2 (UInt64.ofNat bound)
  let bndi ← asTargetIndex boundW
  let (b4, lPlus) := pushTarget b3 .add #[UInt64.ofNat li, UInt64.ofNat bndi]
  let (b5, borrowed) :=
    pushTarget b4 .sub #[UInt64.ofNat lPlus.rawIndex, UInt64.ofNat ri]
  let (b6, diff) ← emitSelect b5 ge direct borrowed
  let (b7, halfW) := emitLiteralU64 b6 (UInt64.ofNat half)
  let hi ← asTargetIndex halfW
  let (b8, sa) := pushBool b7 .gte #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b9, sb) := pushBool b8 .gte #[UInt64.ofNat ri, UInt64.ofNat hi]
  let di ← asTargetIndex diff
  let (b10, sr) := pushBool b9 .gte #[UInt64.ofNat di, UInt64.ofNat hi]
  let (b11, ovf) ← emitDiffSignOverflow b10 sa sb sr
  let (b12, ok) ← emitBoolNot b11 ovf
  let b13 ← pushAssertTrue b12 ok s!"i{bitWidth} sub overflow"
  pure (b13, diff)

/-- Narrow signed checked mul (magnitude product + re-sign; EmitIR port). -/
private def emitNarrowSignedCheckedMul (b : BuilderV1) (bitWidth : Nat)
    (l r : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let half := Nat.pow 2 (bitWidth - 1)
  let negOne := bound - 1
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, halfW) := emitLiteralU64 b (UInt64.ofNat half)
  let hi ← asTargetIndex halfW
  let zeroW := zeroWire b1
  let (b3, oneW) := emitLiteralU64 b1 1
  let oi ← asTargetIndex oneW
  let (b4, negOneW) := emitLiteralU64 b3 (UInt64.ofNat negOne)
  let ni ← asTargetIndex negOneW
  let (b5, sa) := pushBool b4 .gte #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b6, sb) := pushBool b5 .gte #[UInt64.ofNat ri, UInt64.ofNat hi]
  -- Reject intMin unless other ∈ {0,1,-1}.
  let (b7, lIsMin) :=
    pushBool b6 .eq #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b8, rIs0) :=
    pushBool b7 .eq #[UInt64.ofNat ri, UInt64.ofNat b7.zeroTarget]
  let (b9, rIs1) :=
    pushBool b8 .eq #[UInt64.ofNat ri, UInt64.ofNat oi]
  let (b10, rIsNeg1) :=
    pushBool b9 .eq #[UInt64.ofNat ri, UInt64.ofNat ni]
  let (b11, rOk) ← emitBoolOr b10 rIs0 rIs1
  let (b12, rOk2) ← emitBoolOr b11 rOk rIsNeg1
  let (b13, rBad) ← emitBoolNot b12 rOk2
  let (b14, lMinBad) ← emitBoolAnd b13 lIsMin rBad
  let (b15, lOk) ← emitBoolNot b14 lMinBad
  let b16 ← pushAssertTrue b15 lOk s!"i{bitWidth} mul overflow (intMin)"
  let (b17, rIsMin) :=
    pushBool b16 .eq #[UInt64.ofNat ri, UInt64.ofNat hi]
  let (b18, lIs0) :=
    pushBool b17 .eq #[UInt64.ofNat li, UInt64.ofNat b17.zeroTarget]
  let (b19, lIs1) :=
    pushBool b18 .eq #[UInt64.ofNat li, UInt64.ofNat oi]
  let (b20, lIsNeg1) :=
    pushBool b19 .eq #[UInt64.ofNat li, UInt64.ofNat ni]
  let (b21, lOkF) ← emitBoolOr b20 lIs0 lIs1
  let (b22, lOkF2) ← emitBoolOr b21 lOkF lIsNeg1
  let (b23, lBad) ← emitBoolNot b22 lOkF2
  let (b24, rMinBad) ← emitBoolAnd b23 rIsMin lBad
  let (b25, rOkA) ← emitBoolNot b24 rMinBad
  let b26 ← pushAssertTrue b25 rOkA s!"i{bitWidth} mul overflow (intMin)"
  -- absA = sa ? (l==half ? half : bound-l) : l
  let (b27, boundW) := emitLiteralU64 b26 (UInt64.ofNat bound)
  let bndi ← asTargetIndex boundW
  let (b28, negL) :=
    pushTarget b27 .sub #[UInt64.ofNat bndi, UInt64.ofNat li]
  let (b29, lIsMin2) :=
    pushBool b28 .eq #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b30, absANeg) ← emitSelect b29 lIsMin2 halfW negL
  let (b31, absA) ← emitSelect b30 sa absANeg l
  let (b32, negR) :=
    pushTarget b31 .sub #[UInt64.ofNat bndi, UInt64.ofNat ri]
  let (b33, rIsMin2) :=
    pushBool b32 .eq #[UInt64.ofNat ri, UInt64.ofNat hi]
  let (b34, absBNeg) ← emitSelect b33 rIsMin2 halfW negR
  let (b35, absB) ← emitSelect b34 sb absBNeg r
  let ai ← asTargetIndex absA
  let bi ← asTargetIndex absB
  let (b36, prodAbs) :=
    pushTarget b35 .mul #[UInt64.ofNat ai, UInt64.ofNat bi]
  -- prodAbs < half || (prodAbs == half && opposite signs)
  let (b37, prodLt) :=
    pushBool b36 .lt #[UInt64.ofNat prodAbs.rawIndex, UInt64.ofNat hi]
  let (b38, prodEqHalf) :=
    pushBool b37 .eq #[UInt64.ofNat prodAbs.rawIndex, UInt64.ofNat hi]
  let (b39, notSb) ← emitBoolNot b38 sb
  let (b40, aNegBPos) ← emitBoolAnd b39 sa notSb
  let (b41, notSa) ← emitBoolNot b40 sa
  let (b42, aPosBNeg) ← emitBoolAnd b41 notSa sb
  let (b43, opp) ← emitBoolOr b42 aNegBPos aPosBNeg
  let (b44, halfOk) ← emitBoolAnd b43 prodEqHalf opp
  let (b45, magOk) ← emitBoolOr b44 prodLt halfOk
  let b46 ← pushAssertTrue b45 magOk s!"i{bitWidth} mul overflow"
  -- result: 0 if prodAbs==0; else if opp: (prodAbs==half ? half : bound-prodAbs) else prodAbs
  let (b47, prodIs0) :=
    pushBool b46 .eq #[UInt64.ofNat prodAbs.rawIndex, UInt64.ofNat b46.zeroTarget]
  let (b48, negProd) :=
    pushTarget b47 .sub #[UInt64.ofNat bndi, UInt64.ofNat prodAbs.rawIndex]
  let (b49, signedNeg) ← emitSelect b48 prodEqHalf halfW negProd
  let (b50, signed) ← emitSelect b49 opp signedNeg prodAbs
  emitSelect b50 prodIs0 zeroW signed

/-- Narrow signed checked div (trunc toward zero via abs; EmitIR port). -/
private def emitNarrowSignedCheckedDiv (b : BuilderV1) (bitWidth : Nat)
    (l r : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let half := Nat.pow 2 (bitWidth - 1)
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, nz) ← emitTargetNe b r (zeroWire b)
  let b2 ← pushAssertTrue b1 nz s!"i{bitWidth} div by zero"
  let (b3, halfW) := emitLiteralU64 b2 (UInt64.ofNat half)
  let hi ← asTargetIndex halfW
  let (b4, boundW) := emitLiteralU64 b3 (UInt64.ofNat bound)
  let bndi ← asTargetIndex boundW
  let (b5, oneW) := emitLiteralU64 b4 1
  let oi ← asTargetIndex oneW
  let (b6, negOneW) :=
    pushTarget b5 .sub #[UInt64.ofNat bndi, UInt64.ofNat oi]
  -- intMin / -1 overflows
  let (b7, lIsMin) :=
    pushBool b6 .eq #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b8, rIsNeg1) :=
    pushBool b7 .eq #[UInt64.ofNat ri, UInt64.ofNat negOneW.rawIndex]
  let (b9, badDiv) ← emitBoolAnd b8 lIsMin rIsNeg1
  let (b10, okDiv) ← emitBoolNot b9 badDiv
  let b11 ← pushAssertTrue b10 okDiv s!"i{bitWidth} div overflow (intMin / -1)"
  let (b12, sa) := pushBool b11 .gte #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b13, sb) := pushBool b12 .gte #[UInt64.ofNat ri, UInt64.ofNat hi]
  let (b14, negL) :=
    pushTarget b13 .sub #[UInt64.ofNat bndi, UInt64.ofNat li]
  let (b15, absA) ← emitSelect b14 sa negL l
  let (b16, negR) :=
    pushTarget b15 .sub #[UInt64.ofNat bndi, UInt64.ofNat ri]
  let (b17, absB) ← emitSelect b16 sb negR r
  let ai ← asTargetIndex absA
  let bi ← asTargetIndex absB
  let (b18, qAbs) :=
    pushTarget b17 .div #[UInt64.ofNat ai, UInt64.ofNat bi]
  let (b19, notSb) ← emitBoolNot b18 sb
  let (b20, aNegBPos) ← emitBoolAnd b19 sa notSb
  let (b21, notSa) ← emitBoolNot b20 sa
  let (b22, aPosBNeg) ← emitBoolAnd b21 notSa sb
  let (b23, opp) ← emitBoolOr b22 aNegBPos aPosBNeg
  let (b24, qIs0) :=
    pushBool b23 .eq #[UInt64.ofNat qAbs.rawIndex, UInt64.ofNat b23.zeroTarget]
  let (b25, negQ) :=
    pushTarget b24 .sub #[UInt64.ofNat bndi, UInt64.ofNat qAbs.rawIndex]
  let (b26, signedNeg) ← emitSelect b25 qIs0 (zeroWire b25) negQ
  emitSelect b26 opp signedNeg qAbs

/-- Narrow signed checked mod: remainder has sign of dividend (EmitIR). -/
private def emitNarrowSignedCheckedMod (b : BuilderV1) (bitWidth : Nat)
    (l r : WireV1) : CompileResult (BuilderV1 × WireV1) := do
  let bound ← narrowBoundV1 bitWidth
  let half := Nat.pow 2 (bitWidth - 1)
  let li ← asTargetIndex l
  let ri ← asTargetIndex r
  let (b1, nz) ← emitTargetNe b r (zeroWire b)
  let b2 ← pushAssertTrue b1 nz s!"i{bitWidth} mod by zero"
  let (b3, halfW) := emitLiteralU64 b2 (UInt64.ofNat half)
  let hi ← asTargetIndex halfW
  let (b4, boundW) := emitLiteralU64 b3 (UInt64.ofNat bound)
  let bndi ← asTargetIndex boundW
  let (b5, sa) := pushBool b4 .gte #[UInt64.ofNat li, UInt64.ofNat hi]
  let (b6, rb) := pushBool b5 .gte #[UInt64.ofNat ri, UInt64.ofNat hi]
  let (b7, negL) :=
    pushTarget b6 .sub #[UInt64.ofNat bndi, UInt64.ofNat li]
  let (b8, absA) ← emitSelect b7 sa negL l
  let (b9, negR) :=
    pushTarget b8 .sub #[UInt64.ofNat bndi, UInt64.ofNat ri]
  let (b10, absB) ← emitSelect b9 rb negR r
  let ai ← asTargetIndex absA
  let bi ← asTargetIndex absB
  let (b11, rAbs) :=
    pushTarget b10 .mod_ #[UInt64.ofNat ai, UInt64.ofNat bi]
  let (b12, rIs0) :=
    pushBool b11 .eq #[UInt64.ofNat rAbs.rawIndex, UInt64.ofNat b11.zeroTarget]
  let (b13, negRem) :=
    pushTarget b12 .sub #[UInt64.ofNat bndi, UInt64.ofNat rAbs.rawIndex]
  let (b14, signedNeg) ← emitSelect b13 rIs0 (zeroWire b13) negRem
  emitSelect b14 sa signedNeg rAbs

/-- Target binary op accepting Target/U32 operands (encoded ids). -/
private def emitTargetBin (b : BuilderV1) (op : OpTypeV1) (l r : WireV1) :
    BuilderV1 × WireV1 :=
  pushTarget b op #[l.operand, r.operand]

/-- U32 binary op (U32And/Or/Xor/Shift*). -/
private def emitU32Bin (b : BuilderV1) (op : OpTypeV1) (l r : WireV1) :
    BuilderV1 × WireV1 :=
  pushU32 b op #[l.operand, r.operand]

private def emitLimbAdd (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) :=
  pure (emitTargetBin b .add l r)

private def emitLimbSub (b : BuilderV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) :=
  pure (emitTargetBin b .sub l r)

private def emitCompare (b : BuilderV1) (op : ComparisonOp) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  -- dargo compares accept Target and encoded U32 operands.
  match op with
  | .ne =>
      let (b1, eqW) := pushBool b .eq #[l.operand, r.operand]
      emitBoolNot b1 eqW
  | other =>
      pure (pushBool b (compareOpType other) #[l.operand, r.operand])

/-- Limb bitwise as Target: U32 op then CastFelt (Plan `.bitAnd`/`.bitOr`/`.bitXor`). -/
private def emitLimbBitwise (b : BuilderV1) (op : OpTypeV1) (l r : WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let (b1, u) := emitU32Bin b op l r
  emitCastFelt b1 u

private def lookupWideMul (b : BuilderV1) (operationId limbIndex : Nat) :
    CompileResult WireV1 := do
  let some entry := b.wideMulBinds.find? (·.operationId == operationId) |
    planError s!"PSY-DPN-G5: wideUintMulLimb unknown operationId={operationId}"
  match entry.limbs[limbIndex]? with
  | some w => pure w
  | none =>
      planError s!"PSY-DPN-G5: wideUintMulLimb limbIndex={limbIndex} OOR \
(size={entry.limbs.size})"

private def lookupWideDiv (b : BuilderV1)
    (resultKind : WideUInt128DivModResultV1) (operationId limbIndex : Nat) :
    CompileResult WireV1 := do
  let some entry := b.wideDivBinds.find? (·.operationId == operationId) |
    planError s!"PSY-DPN-G5: wideUintDivModLimb unknown operationId={operationId}"
  let limbs := match resultKind with
    | .quotient => entry.quotient
    | .remainder => entry.remainder
  match limbs[limbIndex]? with
  | some w => pure w
  | none =>
      planError s!"PSY-DPN-G5: wideUintDivModLimb limbIndex={limbIndex} OOR"

private def lookupWideShift (b : BuilderV1)
    (kind : WideUInt128ShiftKindV1) (operationId limbIndex : Nat) :
    CompileResult WireV1 := do
  let some entry :=
      b.wideShiftBinds.find? (fun e => e.operationId == operationId && e.kind == kind) |
    planError s!"PSY-DPN-G5: wideUintShiftLimb unknown operationId={operationId}"
  match entry.limbs[limbIndex]? with
  | some w => pure w
  | none =>
      planError s!"PSY-DPN-G5: wideUintShiftLimb limbIndex={limbIndex} OOR"

/-- Felt-carried narrow UInt{8,16,32} param range: assert `param < 2^w`
    (mirror EmitIRV1 entry guards; UInt32 also covers WideCounter dargo). -/
private def emitNarrowParamRangeAsserts (b : BuilderV1) (params : Array WireV1)
    (paramMeta : Array PlanParam) : CompileResult BuilderV1 := do
  let mut bCur := b
  for i in [0:params.size] do
    if let some p := paramMeta[i]? then
      if isNarrowUintWidth p.uintWidth then
        let bound ← narrowBoundV1 p.uintWidth
        let (bLit, limW) := emitLiteralU64 bCur (UInt64.ofNat bound)
        bCur := bLit
        let limIdx ← asTargetIndex limW
        match params[i]? with
        | none => planError "PSY-DPN: narrow param wire missing"
        | some w => do
            let pi ← asTargetIndex w
            let (b1, ok) :=
              pushBool bCur .lt #[UInt64.ofNat pi, UInt64.ofNat limIdx]
            bCur := {
              b1 with
                asserts := b1.asserts.push {
                  left := ok.encoded
                  right := encodeIndexedId .bool b1.trueBool
                  message := s!"u{p.uintWidth} param out of range"
                }
            }
  pure bCur

/-- Lower a Plan Expr into a circuit wire under DPN-3/4 admit surface. -/
partial def lowerExprV1 (b : BuilderV1) (params : Array WireV1) (viewPath : Bool) :
    Expr → CompileResult (BuilderV1 × WireV1)
  | .literal v => pure (emitLiteralU64 b v)
  | .boolLiteral true => pure (b, trueWire b)
  | .boolLiteral false => pure (ensureFalse b)
  | .param i =>
      match params[i]? with
      | some w => pure (b, w)
      | none => planError s!"PSY-DPN: param index {i} out of range"
  | .loopVar depth =>
      match b.loopVars[depth]? with
      | some w => pure (b, w)
      | none => planError s!"PSY-DPN: loopVar depth {depth} not bound"
  | .stateLoad f => do
      -- PureFn bodies are state-free (EffectCheck); defend inlining honesty.
      if b.inlineDepth > 0 then
        planError
          "PSY-DPN: pureFn/localCall inline cannot load state (effectful pureFn fail closed)"
      pure (emitStateLoad b f viewPath)
  | .checkedAdd l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCheckedAdd b2 lw rw
  | .checkedSub l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCheckedSub b2 lw rw
  | .checkedMul l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCheckedMul b2 lw rw
  | .checkedDiv l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCheckedDiv b2 lw rw
  | .checkedMod l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCheckedMod b2 lw rw
  | .limbAdd l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitLimbAdd b2 lw rw
  | .limbSub l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitLimbSub b2 lw rw
  | .bitAnd l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitLimbBitwise b2 .u32And lw rw
  | .bitOr l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitLimbBitwise b2 .u32Or lw rw
  | .bitXor l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitLimbBitwise b2 .u32Xor lw rw
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
  | .u32Literal v => pure (emitLiteralU64 b v)
  | .wideUintMulLimb _bitWidth operationId limbIndex => do
      let w ← lookupWideMul b operationId limbIndex
      pure (b, w)
  | .wideUintDivModLimb resultKind _bitWidth operationId limbIndex => do
      let w ← lookupWideDiv b resultKind operationId limbIndex
      pure (b, w)
  | .wideUintShiftLimb kind _bitWidth operationId limbIndex => do
      let w ← lookupWideShift b kind operationId limbIndex
      pure (b, w)
  | .callFn name args => do
      -- R-PURE: inline pureHelper body into caller definitions (preferred over
      -- separate DPN method). Expression-level pure-body walker (no mutual
      -- lowerStmts) covers return/assert/if/switch/revert; effectful stmts FC.
      let some fn := b.helpers.find? (fun h => h.name == name) |
        planError s!"PSY-DPN: pureFn/localCall callFn '{name}' is not a declared pureHelper"
      unless fn.kind == .pureHelper do
        planError s!"PSY-DPN: callFn '{name}' target is not a pureHelper"
      unless args.size == fn.params.size do
        planError s!"PSY-DPN: callFn '{name}' arity {args.size} != params {fn.params.size}"
      -- Fuel: acyclic pureFn tables have depth ≤ helpers.size; exceed ⇒ cycle.
      if b.inlineDepth > b.helpers.size then
        planError s!"PSY-DPN: pureFn/localCall callFn '{name}' recursive/cyclic \
inline depth exceeded (fail closed)"
      let mut bCur := b
      let mut argWires : Array WireV1 := #[]
      for a in args do
        let (b1, w) ← lowerExprV1 bCur params viewPath a
        bCur := b1
        argWires := argWires.push w
      let bInline := { bCur with inlineDepth := bCur.inlineDepth + 1 }
      -- Local pure-body walker: only lowerExpr recursion (same partial).
      let rec inlinePure (b : BuilderV1) (pparams : Array WireV1) :
          List Statement → CompileResult (BuilderV1 × WireV1)
        | [] =>
            planError s!"PSY-DPN: pureFn '{name}' body has no return value"
        | .returnValue e :: rest => do
            unless rest.isEmpty do
              planError s!"PSY-DPN: pureFn '{name}' has statements after return"
            lowerExprV1 b pparams false e
        | .assert c :: rest => do
            let (b1, cw) ← lowerExprV1 b pparams false c
            let b2 := {
              b1 with
                asserts := b1.asserts.push {
                  left := cw.encoded
                  right := encodeIndexedId .bool b1.trueBool
                  message := "assert"
                }
            }
            inlinePure b2 pparams rest
        | .assertWithMessage c msg :: rest => do
            let (b1, cw) ← lowerExprV1 b pparams false c
            let b2 := {
              b1 with
                asserts := b1.asserts.push {
                  left := cw.encoded
                  right := encodeIndexedId .bool b1.trueBool
                  message := msg
                }
            }
            inlinePure b2 pparams rest
        | .bareRevert :: rest => do
            unless rest.isEmpty do
              planError s!"PSY-DPN: pureFn '{name}' has statements after revert"
            let (b1, fW) := ensureFalse b
            let b2 := {
              b1 with
                asserts := b1.asserts.push {
                  left := fW.encoded
                  right := encodeIndexedId .bool b1.trueBool
                  message := "revert"
                }
            }
            -- Revert path still needs a wire for the expression context.
            pure (b2, zeroWire b2)
        | .revertError _ args' :: rest => do
            unless rest.isEmpty do
              planError s!"PSY-DPN: pureFn '{name}' has statements after revert"
            unless args'.isEmpty do
              planError
                "PSY-DPN-G5-MATRIX: payload error (nonempty revertError args) \
is fail closed (PSY-TYPED-ERROR; no structured error payload ABI)"
            let (b1, fW) := ensureFalse b
            let b2 := {
              b1 with
                asserts := b1.asserts.push {
                  left := fW.encoded
                  right := encodeIndexedId .bool b1.trueBool
                  message := "revert"
                }
            }
            pure (b2, zeroWire b2)
        | .ifThenElse cond thenBody elseBody :: rest => do
            unless rest.isEmpty do
              planError s!"PSY-DPN: pureFn '{name}' has continuation after if"
            let (b1, cw) ← lowerExprV1 b pparams false cond
            let (bThen, tw) ← inlinePure b1 pparams thenBody.toList
            let (bElse, ew) ← inlinePure bThen pparams elseBody.toList
            emitSelect bElse cw tw ew
        | .switchOn scrut cases defaultBody :: rest => do
            unless rest.isEmpty do
              planError s!"PSY-DPN: pureFn '{name}' has continuation after match"
            let mut nested : Array Statement := defaultBody
            for (v, body) in cases.reverse do
              let c : Expr := .compare .eq scrut (.literal v)
              nested := #[.ifThenElse c body nested]
            inlinePure b pparams nested.toList
        | .returnNone :: _ =>
            planError s!"PSY-DPN: pureFn '{name}' must return a value (not unit)"
        | .returnAggregate _ _ :: _ =>
            planError s!"PSY-DPN: pureFn '{name}' aggregate return is fail closed"
        | .store _ _ :: _ | .storeAggregate _ _ :: _ | .emitEvent _ _ :: _
        | .externalCall _ _ :: _ | .schedule _ _ :: _
        | .bindWideUintMul _ _ _ _ :: _ | .bindWideUintDivMod _ _ _ _ _ :: _
        | .bindWideUintShift _ _ _ _ _ :: _ | .forLoop _ _ _ _ :: _ =>
            planError
              "PSY-DPN: pureFn/localCall inline body is effectful \
(store/emit/call/schedule/wide-bind/for fail closed)"
      let (bRes, w) ← inlinePure bInline argWires fn.body.toList
      pure ({ bRes with inlineDepth := b.inlineDepth }, w)
  | .narrowCheckedAdd w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowCheckedAdd b2 w lw rw
  | .narrowCheckedSub w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowCheckedSub b2 w lw rw
  | .narrowCheckedMul w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowCheckedMul b2 w lw rw
  | .narrowCheckedDiv w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowCheckedDiv b2 w lw rw
  | .narrowCheckedMod w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowCheckedMod b2 w lw rw
  | .narrowBitAnd w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowBitwise b2 w .u32And lw rw
  | .narrowBitOr w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowBitwise b2 w .u32Or lw rw
  | .narrowBitXor w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowBitwise b2 w .u32Xor lw rw
  | .narrowShl w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowShl b2 w lw rw
  | .narrowShr w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowShr b2 w lw rw
  | .narrowBitNot w o => do
      let (b1, ow) ← lowerExprV1 b params viewPath o
      emitNarrowBitNot b1 w ow
  | .narrowSignedCheckedAdd w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowSignedCheckedAdd b2 w lw rw
  | .narrowSignedCheckedSub w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowSignedCheckedSub b2 w lw rw
  | .narrowSignedCheckedMul w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowSignedCheckedMul b2 w lw rw
  | .narrowSignedCheckedDiv w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowSignedCheckedDiv b2 w lw rw
  | .narrowSignedCheckedMod w l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowSignedCheckedMod b2 w lw rw
  | .narrowSignedCompare w op l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitNarrowSignedCompare b2 w op lw rw
  | .narrowCheckedNeg w o => do
      let (b1, ow) ← lowerExprV1 b params viewPath o
      emitNarrowCheckedNeg b1 w ow
  | .checkedNeg o => do
      let (b1, ow) ← lowerExprV1 b params viewPath o
      emitCheckedNegInt64 b1 ow
  | .signedCompare op l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitSignedCompareInt64 b2 op lw rw
  | .checkedBitNot o => do
      let (b1, ow) ← lowerExprV1 b params viewPath o
      emitCheckedBitNot b1 ow
  | .shl l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitUInt64Shl b2 lw rw
  | .shr l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitUInt64Shr b2 lw rw
  | .fieldLiteral v => pure (emitLiteralU64 b v)
  | .fieldBinary op l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitFieldBinary b2 op lw rw
  | .fieldCompare op l r => do
      let (b1, lw) ← lowerExprV1 b params viewPath l
      let (b2, rw) ← lowerExprV1 b1 params viewPath r
      emitCompare b2 op lw rw
  | .fieldNeg o => do
      let (b1, ow) ← lowerExprV1 b params viewPath o
      emitFieldNeg b1 ow

/-! ## G5-WIDE: schoolbook mul / restoring div / limb shift (EmitIRV1 port) -/

private def assertBoolEqTrue (b : BuilderV1) (cond : WireV1) (msg : String) :
    CompileResult BuilderV1 := do
  let _ ← asBoolIndex cond
  pure {
    b with
      asserts := b.asserts.push {
        left := cond.encoded
        right := encodeIndexedId .bool b.trueBool
        message := msg
      }
  }

/-- Gate assert under writeCond: select(writeCond, cond, true). -/
private def assertGated (b : BuilderV1) (writeCond cond : WireV1) (msg : String) :
    CompileResult BuilderV1 := do
  let (b1, gated) ← emitSelect b writeCond cond (trueWire b)
  assertBoolEqTrue b1 gated msg

/-- Snapshot operands + optional UInt32 range assert (`limb < 2^32`). -/
private def lowerWideOperandLimbs (b : BuilderV1) (params : Array WireV1)
    (viewPath : Bool) (writeCond : WireV1) (limbs : Array Expr)
    (rangeMsg : String) (checkRange : Bool) :
    CompileResult (BuilderV1 × Array WireV1) := do
  let mut bCur := b
  let mut out : Array WireV1 := #[]
  let (bLim, limW) := emitLiteralU64 bCur 4294967296
  bCur := bLim
  for e in limbs do
    let (b1, w0) ← lowerExprV1 bCur params viewPath e
    bCur := b1
    if checkRange then
      let (b2, ok) ← emitCompare bCur .lt w0 limW
      bCur ← assertGated b2 writeCond ok rangeMsg
      -- safe := select(ok, w0, 0) so out-of-range traps don't poison later ops
      let (b3, safe) ← emitSelect bCur ok w0 (zeroWire bCur)
      bCur := b3
      out := out.push safe
    else
      out := out.push w0
  pure (bCur, out)

/-- Schoolbook wide mul: UInt{N} limbs → 2N UInt16 digits → double-width product
    with per-product U32 normalize; high half must be zero (checked overflow).
    Ports EmitIRV1.emitWideUintMul; result limbs bound under operationId. -/
private def emitBindWideUintMulV1 (b : BuilderV1) (params : Array WireV1)
    (viewPath : Bool) (writeCond : WireV1)
    (bitWidth operationId : Nat) (lhs rhs : Array Expr) :
    CompileResult BuilderV1 := do
  unless bitWidth == 128 || bitWidth == 256 do
    planError "PSY-DPN-G5: bindWideUintMul bitWidth must be 128 or 256"
  let limbCount := bitWidth / 32
  let digitCount := limbCount * 2
  let productDigits := digitCount * 2
  unless lhs.size == limbCount && rhs.size == limbCount do
    planError s!"PSY-DPN-G5: bindWideUintMul requires two {limbCount}-limb operands"
  let (b0, left) ← lowerWideOperandLimbs b params viewPath writeCond lhs
    "u32 limb out of range" false
  let (b1, right) ← lowerWideOperandLimbs b0 params viewPath writeCond rhs
    "u32 limb out of range" false
  let (b2, mask) := emitLiteralU64 b1 65535
  let (b3, shift) := emitLiteralU64 b2 16
  let (b4, base) := emitLiteralU64 b3 65536
  let mut bCur := b4
  -- UInt32 limbs → LE UInt16 digits (U32And / U32ShiftRight), kept as U32 wires.
  let mut lhsDigits : Array WireV1 := #[]
  let mut rhsDigits : Array WireV1 := #[]
  for limb in left do
    let (bLo, lo) := emitU32Bin bCur .u32And limb mask
    let (bHi, hi) := emitU32Bin bLo .u32ShiftRight limb shift
    bCur := bHi
    lhsDigits := lhsDigits.push lo |>.push hi
  for limb in right do
    let (bLo, lo) := emitU32Bin bCur .u32And limb mask
    let (bHi, hi) := emitU32Bin bLo .u32ShiftRight limb shift
    bCur := bHi
    rhsDigits := rhsDigits.push lo |>.push hi
  -- Full double-width product, base 2^16.
  let mut digits : Array WireV1 := #[]
  let mut carry : WireV1 := zeroWire bCur
  for k in [0:productDigits] do
    let (bL, low0) := emitU32Bin bCur .u32And carry mask
    let (bH, carry0) := emitU32Bin bL .u32ShiftRight carry shift
    bCur := bH
    let mut low : WireV1 := low0
    let mut nextCarry : WireV1 := carry0
    for i in [0:digitCount] do
      if i ≤ k then
        let j := k - i
        if j < digitCount then
          let some a := lhsDigits[i]? |
            planError "PSY-DPN-G5: wide mul lhs digit missing"
          let some bb := rhsDigits[j]? |
            planError "PSY-DPN-G5: wide mul rhs digit missing"
          let (bP, product) := emitTargetBin bCur .mul a bb
          let (bPl, productLow) := emitU32Bin bP .u32And product mask
          let (bPh, productHigh) := emitU32Bin bPl .u32ShiftRight product shift
          let (bS, sum) := emitTargetBin bPh .add low productLow
          let (bCb, carryBit) := emitU32Bin bS .u32ShiftRight sum shift
          let (bNl, normalizedLow) := emitU32Bin bCb .u32And sum mask
          let (bC1, c1) := emitTargetBin bNl .add nextCarry productHigh
          let (bC2, normalizedCarry) := emitTargetBin bC1 .add c1 carryBit
          bCur := bC2
          low := normalizedLow
          nextCarry := normalizedCarry
    digits := digits.push low
    carry := nextCarry
  -- Checked overflow: upper digits + final carry == 0
  let overflowMsg := if bitWidth == 256 then "u256 mul overflow" else "u128 mul overflow"
  let (bZ, zEq) ← emitCompare bCur .eq carry (zeroWire bCur)
  bCur := bZ
  let mut noOverflow : WireV1 := zEq
  for i in [digitCount:productDigits] do
    let some digit := digits[i]? |
      planError "PSY-DPN-G5: wide product digit missing"
    let (bE, dEq) ← emitCompare bCur .eq digit (zeroWire bCur)
    let (bA, andW) ← emitBoolAnd bE noOverflow dEq
    bCur := bA
    noOverflow := andW
  bCur ← assertGated bCur writeCond noOverflow overflowMsg
  -- Repack low UInt16 digits into UInt32 Target limbs.
  let mut resultLimbs : Array WireV1 := #[]
  for limbIndex in [0:limbCount] do
    let loIndex := limbIndex * 2
    let hiIndex := loIndex + 1
    let some lo := digits[loIndex]? |
      planError "PSY-DPN-G5: wide mul low result digit missing"
    let some hi := digits[hiIndex]? |
      planError "PSY-DPN-G5: wide mul high result digit missing"
    let (bSc, scaledHigh) := emitTargetBin bCur .mul hi base
    let (bSm, limb) := emitTargetBin bSc .add lo scaledHigh
    bCur := bSm
    resultLimbs := resultLimbs.push limb
  pure {
    bCur with
      wideMulBinds := bCur.wideMulBinds.push {
        operationId, limbs := resultLimbs
      }
  }

/-- Lexicographic remainder ≥ divisor (remainder is one limb wider). -/
private def emitWideDivLexGe (b : BuilderV1)
    (remainder divisor : Array WireV1) :
    CompileResult (BuilderV1 × WireV1) := do
  let limbCount := divisor.size
  unless remainder.size == limbCount + 1 do
    planError "PSY-DPN-G5: wide div lexGe remainder width mismatch"
  let mut bCur := b
  let some r0 := remainder[0]? | planError "PSY-DPN-G5: rem0"
  let some d0 := divisor[0]? | planError "PSY-DPN-G5: div0"
  let (b0, acc0) ← emitCompare bCur .ge r0 d0
  bCur := b0
  let mut acc := acc0
  for i in [1:limbCount] do
    let some ri := remainder[i]? | planError "PSY-DPN-G5: rem i"
    let some di := divisor[i]? | planError "PSY-DPN-G5: div i"
    let (bGt, limbGt) ← emitCompare bCur .gt ri di
    let (bEq, limbEq) ← emitCompare bGt .eq ri di
    let (bAnd, eqAnd) ← emitBoolAnd bEq limbEq acc
    let (bOr, next) ← emitBoolOr bAnd limbGt eqAnd
    bCur := bOr
    acc := next
  let some rHi := remainder[limbCount]? | planError "PSY-DPN-G5: rem hi"
  let (bNe, hiNe) ← emitCompare bCur .ne rHi (zeroWire bCur)
  let (bOr2, final) ← emitBoolOr bNe hiNe acc
  pure (bOr2, final)

/-- One restoring step (single bit) of the wide divider (SSA form). -/
private def emitWideDivOneStep (b : BuilderV1)
    (limbCount : Nat) (sourceBit : WireV1)
    (remainder quotient divisor : Array WireV1)
    (divisorZero : WireV1) (writeCond : WireV1) :
    CompileResult (BuilderV1 × Array WireV1 × Array WireV1) := do
  unless remainder.size == limbCount + 1 && quotient.size == limbCount
      && divisor.size == limbCount do
    planError "PSY-DPN-G5: wide div step shape mismatch"
  let (bS1, shiftTop) := emitLiteralU64 b 31
  let (bS2, shiftOne) := emitLiteralU64 bS1 1
  let (bS3, base) := emitLiteralU64 bS2 4294967296
  let (bS4, one) := emitLiteralU64 bS3 1
  let mut bCur := bS4
  -- Shift remainder left by 1, inject source bit into limb 0.
  let mut carries : Array WireV1 := #[]
  for i in [0:limbCount] do
    let some ri := remainder[i]? | planError "PSY-DPN-G5: rem carry"
    let (bC, c) := emitU32Bin bCur .u32ShiftRight ri shiftTop
    bCur := bC
    carries := carries.push c
  let some r0 := remainder[0]? | planError "PSY-DPN-G5: r0"
  let (bL0, r0s) := emitU32Bin bCur .u32ShiftLeft r0 shiftOne
  let (bR0, r0n) := emitU32Bin bL0 .u32Or r0s sourceBit
  bCur := bR0
  let mut newRem : Array WireV1 := #[r0n]
  for i in [1:limbCount] do
    let some ri := remainder[i]? | planError "PSY-DPN-G5: rem shift"
    let some cPrev := carries[i - 1]? | planError "PSY-DPN-G5: carry prev"
    let (bLs, ris) := emitU32Bin bCur .u32ShiftLeft ri shiftOne
    let (bOr, rin) := emitU32Bin bLs .u32Or ris cPrev
    bCur := bOr
    newRem := newRem.push rin
  let some cLast := carries[limbCount - 1]? | planError "PSY-DPN-G5: carry last"
  newRem := newRem.push cLast
  -- take := rem >= divisor
  let (bTk, take) ← emitWideDivLexGe bCur newRem divisor
  bCur := bTk
  -- subtract with borrow when take
  let mut borrow : WireV1 := zeroWire bCur
  let mut diffs : Array WireV1 := #[]
  for i in [0:limbCount] do
    let some ri := newRem[i]? | planError "PSY-DPN-G5: sub rem"
    let some di := divisor[i]? | planError "PSY-DPN-G5: sub div"
    let (bSub, sub) := emitTargetBin bCur .add di borrow
    let (bUn, under) ← emitCompare bSub .lt ri sub
    let (bDir, direct) := emitTargetBin bUn .sub ri sub
    let (bW0, wrapped0) := emitTargetBin bDir .add ri base
    let (bW1, wrapped) := emitTargetBin bW0 .sub wrapped0 sub
    let (bDf, diff) ← emitSelect bW1 under wrapped direct
    let (bBr, br) ← emitSelect bDf under one (zeroWire bDf)
    bCur := bBr
    diffs := diffs.push diff
    borrow := br
  let some rHi := newRem[limbCount]? | planError "PSY-DPN-G5: rHi"
  -- high_ok := !take \/ rHi == borrow
  let (bNt, notTake) ← emitBoolNot bCur take
  let (bEq, hiEq) ← emitCompare bNt .eq rHi borrow
  let (bOk, highOk) ← emitBoolOr bEq notTake hiEq
  let (bDz, skipOrOk) ← emitBoolOr bOk divisorZero highOk
  bCur ← assertGated bDz writeCond skipOrOk "u128 div internal high borrow"
  let (bHd, highDiff) := emitTargetBin bCur .sub rHi borrow
  bCur := bHd
  let mut remOut : Array WireV1 := #[]
  for i in [0:limbCount] do
    let some ri := newRem[i]? | planError "PSY-DPN-G5: rem out"
    let some di := diffs[i]? | planError "PSY-DPN-G5: diff out"
    let (bSel, r) ← emitSelect bCur take di ri
    bCur := bSel
    remOut := remOut.push r
  let (bRh, rH) ← emitSelect bCur take highDiff rHi
  bCur := bRh
  remOut := remOut.push rH
  let (bRz, remHiOk) ← emitCompare bCur .eq rH (zeroWire bCur)
  let (bRz2, remHiGate) ← emitBoolOr bRz divisorZero remHiOk
  bCur ← assertGated bRz2 writeCond remHiGate "u128 div internal remainder high"
  -- quotient <<= 1 | take
  let (bQb, qbit) ← emitSelect bCur take one (zeroWire bCur)
  bCur := bQb
  let mut qCarries : Array WireV1 := #[]
  for i in [0:limbCount] do
    let some qi := quotient[i]? | planError "PSY-DPN-G5: q carry"
    let (bC, c) := emitU32Bin bCur .u32ShiftRight qi shiftTop
    bCur := bC
    qCarries := qCarries.push c
  let some q0 := quotient[0]? | planError "PSY-DPN-G5: q0"
  let (bQl, q0s) := emitU32Bin bCur .u32ShiftLeft q0 shiftOne
  let (bQo, q0n) := emitU32Bin bQl .u32Or q0s qbit
  bCur := bQo
  let mut quotOut : Array WireV1 := #[q0n]
  for i in [1:limbCount] do
    let some qi := quotient[i]? | planError "PSY-DPN-G5: q shift"
    let some cPrev := qCarries[i - 1]? | planError "PSY-DPN-G5: qc"
    let (bLs, qis) := emitU32Bin bCur .u32ShiftLeft qi shiftOne
    let (bOr, qin) := emitU32Bin bLs .u32Or qis cPrev
    bCur := bOr
    quotOut := quotOut.push qin
  let some qcLast := qCarries[limbCount - 1]? | planError "PSY-DPN-G5: qc last"
  let (bQe, qov) ← emitCompare bCur .eq qcLast (zeroWire bCur)
  let (bQe2, qovGate) ← emitBoolOr bQe divisorZero qov
  bCur ← assertGated bQe2 writeCond qovGate "u128 div internal quotient overflow"
  -- Cast U32 remainder/quotient limbs used as Target to Target for next step.
  -- Steps feed mixed wires; keep as-is (operand encoding handles both).
  pure (bCur, remOut, quotOut)

/-- Extract bit `31 - step` of a limb as U32 0/1 (MSB-first within limb). -/
private def emitLimbBitMSB (b : BuilderV1) (limb : WireV1) (stepInLimb : Nat) :
    CompileResult (BuilderV1 × WireV1) := do
  unless stepInLimb < 32 do
    planError "PSY-DPN-G5: limb bit step must be < 32"
  let dist := 31 - stepInLimb
  let (b1, distW) := emitLiteralU64 b (UInt64.ofNat dist)
  let (b2, shifted) := emitU32Bin b1 .u32ShiftRight limb distW
  let (b3, one) := emitLiteralU64 b2 1
  pure (emitU32Bin b3 .u32And shifted one)

/-- Restoring wide div/mod binding (EmitIRV1 port, fully unrolled). -/
private def emitBindWideUintDivModV1 (b : BuilderV1) (params : Array WireV1)
    (viewPath : Bool) (writeCond : WireV1)
    (resultKind : WideUInt128DivModResultV1)
    (bitWidth operationId : Nat) (lhs rhs : Array Expr) :
    CompileResult BuilderV1 := do
  unless bitWidth == 128 || bitWidth == 256 do
    planError "PSY-DPN-G5: bindWideUintDivMod bitWidth must be 128 or 256"
  let limbCount := bitWidth / 32
  unless lhs.size == limbCount && rhs.size == limbCount do
    planError s!"PSY-DPN-G5: bindWideUintDivMod requires two {limbCount}-limb operands"
  let rangeMsg := if bitWidth == 256 then "u256 div operand limb out of range"
    else "u128 div operand limb out of range"
  let zeroMessage := match resultKind, bitWidth with
    | .quotient, 256 => "u256 div by zero"
    | .remainder, 256 => "u256 mod by zero"
    | .quotient, _ => "u128 div by zero"
    | .remainder, _ => "u128 mod by zero"
  let (b0, left) ← lowerWideOperandLimbs b params viewPath writeCond lhs rangeMsg true
  let (b1, right) ← lowerWideOperandLimbs b0 params viewPath writeCond rhs rangeMsg true
  let mut bCur := b1
  -- divisorZero := all limbs == 0
  let some r0 := right[0]? | planError "PSY-DPN-G5: rhs0"
  let (bZ0, dz0) ← emitCompare bCur .eq r0 (zeroWire bCur)
  bCur := bZ0
  let mut divisorZero := dz0
  for i in [1:limbCount] do
    let some ri := right[i]? | planError "PSY-DPN-G5: rhs i"
    let (bE, eqW) ← emitCompare bCur .eq ri (zeroWire bCur)
    let (bA, andW) ← emitBoolAnd bE divisorZero eqW
    bCur := bA
    divisorZero := andW
  let (bNz, notZero) ← emitBoolNot bCur divisorZero
  bCur ← assertGated bNz writeCond notZero zeroMessage
  -- rem = [0..] (limbCount+1), quot = [0..] (limbCount)
  let mut rem : Array WireV1 := #[]
  for _ in [0:limbCount + 1] do
    rem := rem.push (zeroWire bCur)
  let mut quot : Array WireV1 := #[]
  for _ in [0:limbCount] do
    quot := quot.push (zeroWire bCur)
  -- MSB-first limbs: sourceIndex from limbCount-1 down to 0; 32 bits each
  for sourceIndex in List.range limbCount |>.reverse do
    let some source := left[sourceIndex]? |
      planError "PSY-DPN-G5: dividend limb missing"
    for step in [0:32] do
      let (bBit, bit) ← emitLimbBitMSB bCur source step
      let (bSt, rem', quot') ←
        emitWideDivOneStep bBit limbCount bit rem quot right divisorZero writeCond
      bCur := bSt
      rem := rem'
      quot := quot'
  -- Ensure Target limbs for binding (CastFelt any residual U32)
  let mut qOut : Array WireV1 := #[]
  for w in quot do
    let (bT, t) ← ensureTarget bCur w
    bCur := bT
    qOut := qOut.push t
  let mut rOut : Array WireV1 := #[]
  for i in [0:limbCount] do
    let some w := rem[i]? | planError "PSY-DPN-G5: rem bind"
    let (bT, t) ← ensureTarget bCur w
    bCur := bT
    rOut := rOut.push t
  pure {
    bCur with
      wideDivBinds := bCur.wideDivBinds.push {
        operationId, quotient := qOut, remainder := rOut
      }
  }

/-- Exact wide logical shift: fixed bitWidth one-bit walk (EmitIRV1 port). -/
private def emitBindWideUintShiftV1 (b : BuilderV1) (params : Array WireV1)
    (viewPath : Bool) (writeCond : WireV1)
    (kind : WideUInt128ShiftKindV1) (bitWidth operationId : Nat)
    (value : Array Expr) (count : Expr) :
    CompileResult BuilderV1 := do
  unless bitWidth == 128 || bitWidth == 256 do
    planError "PSY-DPN-G5: bindWideUintShift bitWidth must be 128 or 256"
  let limbCount := bitWidth / 32
  unless value.size == limbCount do
    planError s!"PSY-DPN-G5: bindWideUintShift requires {limbCount} value limbs"
  let rangeMsg := if bitWidth == 256 then "u256 shift operand limb out of range"
    else "u128 shift operand limb out of range"
  let overflowMsg := if bitWidth == 256 then "u256 shl overflow" else "u128 shl overflow"
  let (b0, limbs0) ← lowerWideOperandLimbs b params viewPath writeCond value rangeMsg true
  let (b1, countW) ← lowerExprV1 b0 params viewPath count
  let (b2, bwLit) := emitLiteralU64 b1 (UInt64.ofNat bitWidth)
  let (b3, countOk) ← emitCompare b2 .lt countW bwLit
  let mut bCur ← assertGated b3 writeCond countOk
    s!"invalidShift: count >= {bitWidth}"
  let (bOne, one) := emitLiteralU64 bCur 1
  let (bTop, shiftTop) := emitLiteralU64 bOne 31
  let (bSo, shiftOne) := emitLiteralU64 bTop 1
  bCur := bSo
  let mut limbs := limbs0
  -- Unroll bitWidth steps; take := step < count
  for step in [0:bitWidth] do
    let (bSt, stepLit) := emitLiteralU64 bCur (UInt64.ofNat step)
    let (bTk, take) ← emitCompare bSt .lt stepLit countW
    bCur := bTk
    match kind with
    | .shl => do
        let mut carries : Array WireV1 := #[]
        for i in [0:limbCount] do
          let some li := limbs[i]? | planError "PSY-DPN-G5: shl carry"
          let (bC, c) := emitU32Bin bCur .u32ShiftRight li shiftTop
          bCur := bC
          carries := carries.push c
        let some cLast := carries[limbCount - 1]? | planError "PSY-DPN-G5: shl ov"
        let (bNt, notTake) ← emitBoolNot bCur take
        let (bEq, cZero) ← emitCompare bNt .eq cLast (zeroWire bNt)
        let (bOk, ok) ← emitBoolOr bEq notTake cZero
        bCur ← assertGated bOk writeCond ok overflowMsg
        let some l0 := limbs[0]? | planError "PSY-DPN-G5: shl l0"
        let (bL, l0s) := emitU32Bin bCur .u32ShiftLeft l0 shiftOne
        let (bS0, l0n) ← emitSelect bL take l0s l0
        bCur := bS0
        let mut next : Array WireV1 := #[l0n]
        for i in [1:limbCount] do
          let some li := limbs[i]? | planError "PSY-DPN-G5: shl li"
          let some cPrev := carries[i - 1]? | planError "PSY-DPN-G5: shl cp"
          let (bLs, lis) := emitU32Bin bCur .u32ShiftLeft li shiftOne
          let (bOr, lior) := emitU32Bin bLs .u32Or lis cPrev
          let (bSel, lin) ← emitSelect bOr take lior li
          bCur := bSel
          next := next.push lin
        limbs := next
    | .shr => do
        let mut lowBits : Array WireV1 := #[]
        for i in [0:limbCount] do
          let some li := limbs[i]? | planError "PSY-DPN-G5: shr low"
          let (bL, lb) := emitU32Bin bCur .u32And li one
          bCur := bL
          lowBits := lowBits.push lb
        -- Build next limbs low→high: for idx in 0..limbCount-2 inject low bit
        -- of higher limb; last limb is plain >> 1.
        let mut next : Array WireV1 := #[]
        for idx in [0:limbCount - 1] do
          let some li := limbs[idx]? | planError "PSY-DPN-G5: shr idx"
          let some lbNext := lowBits[idx + 1]? | planError "PSY-DPN-G5: shr lb"
          let (bRs2, lis) := emitU32Bin bCur .u32ShiftRight li shiftOne
          let (bSh, moved) := emitU32Bin bRs2 .u32ShiftLeft lbNext shiftTop
          let (bOr, lior) := emitU32Bin bSh .u32Or lis moved
          let (bSel, lin) ← emitSelect bOr take lior li
          bCur := bSel
          next := next.push lin
        let some lLast := limbs[limbCount - 1]? | planError "PSY-DPN-G5: shr last"
        let (bRs, lastS) := emitU32Bin bCur .u32ShiftRight lLast shiftOne
        let (bSl, lastN) ← emitSelect bRs take lastS lLast
        bCur := bSl
        next := next.push lastN
        limbs := next
  let mut outLimbs : Array WireV1 := #[]
  for w in limbs do
    let (bT, t) ← ensureTarget bCur w
    bCur := bT
    outLimbs := outLimbs.push t
  pure {
    bCur with
      wideShiftBinds := bCur.wideShiftBinds.push {
        operationId, kind, limbs := outLimbs
      }
  }

/-- Result of lowering a statement sequence: return wires (empty = unit). -/
structure StmtResultV1 where
  builder : BuilderV1
  /-- Return values (Select-merged across branches). Empty = no return. -/
  returnWires : Array WireV1 := #[]
  deriving Inhabited

private def mergeReturns (b : BuilderV1) (cond : WireV1)
    (thenR elseR : Array WireV1) : CompileResult (BuilderV1 × Array WireV1) := do
  unless thenR.size == elseR.size do
    planError s!"PSY-DPN-4: if return arity mismatch then={thenR.size} else={elseR.size}"
  if thenR.isEmpty then
    pure (b, #[])
  else
    let mut bCur := b
    let mut out : Array WireV1 := #[]
    for i in [0:thenR.size] do
      let some t := thenR[i]? | planError "PSY-DPN-4: then return missing"
      let some e := elseR[i]? | planError "PSY-DPN-4: else return missing"
      let (bSel, w) ← emitSelect bCur cond t e
      bCur := bSel
      out := out.push w
    pure (bCur, out)

/-- Lower statements under an active write condition `writeCond` (bool wire).
    `viewPath` only for pure view helpers (sub_slot 0 on single-field).
    When `inlineDepth > 0` (R-PURE callFn body), state/effect statements fail closed. -/
partial def lowerStmtsV1 (b : BuilderV1) (params : Array WireV1)
    (writeCond : WireV1) (viewPath : Bool) :
    List Statement → CompileResult StmtResultV1
  | [] => pure { builder := b, returnWires := #[] }
  | s :: rest => do
      -- R-PURE: pureFn bodies are effect-free; defend inlining honesty.
      if b.inlineDepth > 0 then
        match s with
        | .store _ _ | .storeAggregate _ _ | .emitEvent _ _ | .externalCall _ _
        | .schedule _ _ | .bindWideUintMul _ _ _ _ | .bindWideUintDivMod _ _ _ _ _
        | .bindWideUintShift _ _ _ _ _ =>
            planError
              "PSY-DPN: pureFn/localCall inline body is effectful (store/emit/call/schedule/wide-bind fail closed)"
        | _ => pure ()
      match s with
      | .store f value => do
          let (b1, vw) ← lowerExprV1 b params viewPath value
          let b2 ← emitStateStore b1 f writeCond vw
          lowerStmtsV1 b2 params writeCond viewPath rest
      | .storeAggregate fieldIndices values => do
          unless fieldIndices.size == values.size do
            planError "PSY-DPN-4: storeAggregate field/value size mismatch"
          unless fieldIndices.size ≥ 1 do
            planError "PSY-DPN-4: storeAggregate requires at least one leaf"
          -- Snapshot every value before any write (atomic multi-leaf).
          let mut bCur := b
          let mut snaps : Array WireV1 := #[]
          for v in values do
            let (b1, w) ← lowerExprV1 bCur params viewPath v
            bCur := b1
            snaps := snaps.push w
          for i in [0:fieldIndices.size] do
            let some fi := fieldIndices[i]? |
              planError "PSY-DPN-4: storeAggregate field missing"
            let some vw := snaps[i]? |
              planError "PSY-DPN-4: storeAggregate snapshot missing"
            bCur ← emitStateStore bCur fi writeCond vw
          lowerStmtsV1 bCur params writeCond viewPath rest
      | .returnValue value => do
          let (b1, vw) ← lowerExprV1 b params viewPath value
          pure { builder := b1, returnWires := #[vw] }
      | .returnAggregate leaves _leafIsInt => do
          unless leaves.size ≥ 1 do
            planError "PSY-DPN-4: returnAggregate requires at least one leaf"
          let mut bCur := b
          let mut wires : Array WireV1 := #[]
          for v in leaves do
            let (b1, w) ← lowerExprV1 bCur params viewPath v
            bCur := b1
            wires := wires.push w
          pure { builder := bCur, returnWires := wires }
      | .returnNone =>
          pure { builder := b, returnWires := #[] }
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
          let (bFinal, retFinal) ←
            match thenRes.returnWires.isEmpty, elseRes.returnWires.isEmpty with
            | true, true => pure (elseRes.builder, (#[] : Array WireV1))
            | false, false =>
                mergeReturns elseRes.builder cw thenRes.returnWires elseRes.returnWires
            | false, true =>
                planError
                  "PSY-DPN: if-then returns but else does not (both arms must return or neither)"
            | true, false =>
                planError
                  "PSY-DPN: if-else returns but then does not (both arms must return or neither)"
          let cont ← lowerStmtsV1 bFinal params writeCond viewPath rest
          match retFinal.isEmpty, cont.returnWires.isEmpty with
          | false, true => pure { cont with returnWires := retFinal }
          | true, _ => pure { cont with returnWires := cont.returnWires }
          | false, false =>
              planError "PSY-DPN: multiple return values in sequence"
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
            unless bodyRes.returnWires.isEmpty do
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
      | .revertError _errorIndex args => do
          -- PSY-TYPED-ERROR: zero-arg named revert → assert(false,"revert");
          -- nonempty payload stays evidence-backed FC (no structured ABI).
          unless args.isEmpty do
            planError
              "PSY-DPN-G5-MATRIX: payload error (nonempty revertError args) \
is fail closed (PSY-TYPED-ERROR; no structured error payload ABI)"
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
      | .emitEvent _eventIndex args => do
          -- DPN-6 PARTIAL: product admits source `__emit` → DPN events[].
          -- Event name is not in DPNEventRecord (official record has no name).
          let mut bCur := b
          let mut argWires : Array WireV1 := #[]
          for a in args do
            let (b1, w) ← lowerExprV1 bCur params viewPath a
            bCur := b1
            argWires := argWires.push w
          let b2 ← emitEventRecordV1 bCur writeCond argWires
          lowerStmtsV1 b2 params writeCond viewPath rest
      | .externalCall callee args => do
          -- DPN-6 PARTIAL: void sync call only (result-bearing FC at Plan).
          let mut bCur := b
          let mut argWires : Array WireV1 := #[]
          for a in args do
            let (b1, w) ← lowerExprV1 bCur params viewPath a
            bCur := b1
            argWires := argWires.push w
          let b2 ← emitVoidExternalCallV1 bCur writeCond callee argWires
          lowerStmtsV1 b2 params writeCond viewPath rest
      | .schedule _callee _args =>
          -- DPN-6 FC: no deferred crosscall form; never alias InvokeSync.
          planError
            "PSY-DPN-6: schedule is not admitted on Psy DPN (no deferred \
InvokeExternalContractFunctionDeferred product path; effect.asynchronous-workflow \
declined; PSY-CALL-EVENT FC)"
      | .bindWideUintMul bitWidth operationId lhs rhs => do
          let b1 ← emitBindWideUintMulV1 b params viewPath writeCond
            bitWidth operationId lhs rhs
          lowerStmtsV1 b1 params writeCond viewPath rest
      | .bindWideUintDivMod resultKind bitWidth operationId lhs rhs => do
          let b1 ← emitBindWideUintDivModV1 b params viewPath writeCond
            resultKind bitWidth operationId lhs rhs
          lowerStmtsV1 b1 params writeCond viewPath rest
      | .bindWideUintShift kind bitWidth operationId value count => do
          let b1 ← emitBindWideUintShiftV1 b params viewPath writeCond
            kind bitWidth operationId value count
          lowerStmtsV1 b1 params writeCond viewPath rest

/-- Encode return wires as circuit_outputs (target raw index; bool/u32 encoded). -/
private def encodeOutputs (wires : Array WireV1) : Array UInt64 :=
  wires.map fun
    | .target i => UInt64.ofNat i
    | .bool i => encodeIndexedId .bool i
    | .u32 i => encodeIndexedId .u32Target i

/-- General function lower (DPN-3/4/5). Multi-leaf UInt64/Option/Map + limb wide.
    `helpers` is the plan pureHelper table for R-PURE callFn inlining. -/
def lowerFunctionGeneralV1 (fn : PlanFunction) (multiLeaf : Bool)
    (helpers : Array PlanFunction) :
    CompileResult FunctionCircuitDefV1 := do
  let methodId ← requireMethodIdFromPlanFnV1 fn
  let nParams := fn.params.size
  let (b0, paramWires) := emitParams nParams
  let b0 := { b0 with multiLeaf, helpers }
  let b1 := ensurePrelude b0
  let b2 ← emitNarrowParamRangeAsserts b1 paramWires fn.params
  let viewPath :=
    fn.kind == .pureHelper &&
      fn.body.toList.all fun s =>
        match s with
        | .returnValue (.stateLoad _) => true
        | .returnAggregate leaves _ =>
            leaves.all fun e => match e with | .stateLoad _ => true | _ => false
        | .returnNone => true
        | _ => false
  let writeCond := trueWire b2
  let res ← lowerStmtsV1 b2 paramWires writeCond viewPath fn.body.toList
  let outputs := encodeOutputs res.returnWires
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
    events := res.builder.events
  }

/-- Classify a single PlanFunction into a DPN template or general lower. -/
def lowerFunctionV1 (fn : PlanFunction) (multiLeaf : Bool)
    (helpers : Array PlanFunction) :
    CompileResult FunctionCircuitDefV1 := do
  -- Counter templates first (exact dargo golden) — single-leaf only.
  if !multiLeaf then
    match fn.body.toList with
    | [.returnValue (.stateLoad f)] =>
        return (← lowerViewLoadReturnV1 fn.name f)
    | [.store f (.param 0), .returnNone] =>
        return (← lowerInitializeStoreParamV1 fn.name f)
    | [.store f (.checkedAdd (.stateLoad f2) (.param 0)),
        .returnValue (.stateLoad f3)] => do
        unless f == f2 && f == f3 do
          planError "PSY-DPN: checkedAdd store/return field mismatch"
        return (← lowerCheckedAddStoreReturnV1 fn.name f)
    | _ => pure ()
  -- DPN-3/4/5 general path (if/match/for + multi-leaf Option/Map + wide limbs).
  lowerFunctionGeneralV1 fn multiLeaf helpers

/-- Lower an entire Plan to a DPN package. Functions sorted by name (dargo order).
    R-PURE: pureHelper functions are validated as lowerable but omitted from the
    package (inlined at call sites; free helpers match EmitIR, not contract methods). -/
def lowerPlanToPackageV1 (plan : Plan) : CompileResult PackageV1 := do
  let nFields := plan.stateFieldNames.size
  unless nFields ≥ 1 do
    planError "PSY-DPN: expected at least one state field"
  unless nFields ≤ maxStateLeavesV1 do
    planError s!"PSY-DPN-5: state leaf count {nFields} exceeds max {maxStateLeavesV1}"
  let multiLeaf := nFields > 1
  let helpers := plan.functions.filter (·.kind == .pureHelper)
  let mut out : Array FunctionCircuitDefV1 := #[]
  for fn in plan.functions do
    if fn.kind == .pureHelper then
      -- Validate pure helper is DPN-lowerable (no residual body); do not emit.
      let _ ← lowerFunctionV1 fn multiLeaf helpers
    else
      let d ← lowerFunctionV1 fn multiLeaf helpers
      out := out.push d
  let sorted := out.qsort (fun a b => a.name < b.name)
  pure sorted

/-- Capability path: materialize Plan then DPN lower (avoids importing Psy façade). -/
def packageFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult PackageV1 := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lowerPlanToPackageV1 plan

/-- Lower a single hand-built PlanFunction (tests / structural probes).
    Pass `multiLeaf := true` for Option/UInt128 multi-slot shapes. -/
def lowerFunctionForTestV1 (fn : PlanFunction) (multiLeaf : Bool) :
    CompileResult FunctionCircuitDefV1 :=
  lowerFunctionV1 fn multiLeaf #[]

/-- Like `lowerFunctionForTestV1` but with an explicit pureHelper table for
    R-PURE callFn inlining structural probes. -/
def lowerFunctionWithHelpersForTestV1 (fn : PlanFunction) (multiLeaf : Bool)
    (helpers : Array PlanFunction) :
    CompileResult FunctionCircuitDefV1 :=
  lowerFunctionV1 fn multiLeaf helpers

end ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
