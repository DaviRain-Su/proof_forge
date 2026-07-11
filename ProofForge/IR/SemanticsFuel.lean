import ProofForge.IR.Semantics

/-! ## Generic total fuel-indexed IR interpreter (FV-9.0)

This is the **shared, total, proof-usable** generic IR interpreter that FV-9's
`∀ module` compiler-correctness theorem quantifies over. It is fuel-indexed
(structural recursion on the `Nat` fuel argument), so Lean's kernel can unfold
and induct on it — unlike the broader `partial def` interpreter in
`Semantics.lean`, which cannot be used in proofs.

FV-9.0 origin: the fuel-indexed evaluator was originally written in
`CounterSemantics.lean` as a "Counter-fragment" total semantics. Inspection
(2026-07-08) showed its evaluator bodies contain **zero Counter-specific
identifiers** — they operate generically on `State`/`Frame`/`Expr`/`Effect`/
`Statement`. It was generic-but-misfiled. This file lifts it to the IR layer
as the canonical shared interpreter; `CounterSemantics.lean` now re-exports it
and keeps only the Counter-specific wrappers/proofs.

Coverage is intentionally narrow at first (the constructors Counter+ValueVault
already exercise): `Expr.literal/local/add/sub/mul/effect`,
`Effect.storageScalarRead/storageScalarWrite`, `Statement.letBind/letMutBind/
effect/return`. FV-9.0 M2 widens this to the full arithmetic + scalar/map
storage + control-flow + event core the supported fragment needs. Each
unsupported constructor falls through to `unsupported*` so totality is
preserved and the fragment predicate (FV-9.4) can admit exactly the proven
constructor set.

No contract names appear in this file.
-/

namespace ProofForge.IR.SemanticsFuel

open ProofForge.IR
open ProofForge.IR.Semantics

def defaultFuel : Nat := 32

def unsupportedExpr (expr : Expr) : Except String ExprResult :=
  .error s!"IR fuel semantics does not support expression `{repr expr}`"

def unsupportedEffect (effect : Effect) : Except String ExprResult :=
  .error s!"IR fuel semantics does not support effect `{repr effect}`"

def unsupportedStatement (statement : Statement) :
    Except String (State × Frame × Option Value) :=
  .error s!"IR fuel semantics does not support statement `{repr statement}`"

/-- Total scalar-only version of `valueKey` for the fuel interpreter. Covers the
non-recursive `Value` constructors (the keys Counter/ValueVault maps use);
array/struct keys fall back to a generic `repr`-based key so totality is
preserved without depending on the `partial` `valueKey`. -/
def valueKeyScalar : Value → String
  | .unit => "unit"
  | .bool value => if value then "true" else "false"
  | .u8 value => s!"u8:{value}"
  | .u32 value => s!"u32:{value}"
  | .u128 value => s!"u128:{value}"
  | .u64 value => s!"u64:{value}"
  | .address value => s!"addr:{value}"
  | .bytes values => "bytes:" ++ String.intercalate "," (values.map toString)
  | .string value => s!"str:{value}"
  | .hash a b c d => s!"hash:{a}:{b}:{c}:{d}"
  | .array values => s!"array:{values.length}"
  | .struct typeName _ => s!"struct:{typeName}"

/-- Total scalar-only zero-like value, mirroring `zeroLike` for the
non-recursive constructors (the ones the fuel interpreter admits). Array and
struct values get `.unit` since the fuel interpreter's fragment is
scalar-centric; this preserves totality without recursion. -/
def zeroLikeScalar : Value → Value
  | .unit => .unit
  | .bool _ => .bool false
  | .u8 _ => .u8 0
  | .u32 _ => .u32 0
  | .u128 _ => .u128 0
  | .u64 _ => .u64 0
  | .address _ => .address 0
  | .bytes _ => .bytes []
  | .string _ => .string ""
  | .hash _ _ _ _ => .hash 0 0 0 0
  | .array _ => .unit
  | .struct _ _ => .unit

mutual
  def evalExprFuel : Nat → State → Frame → Expr → Except String ExprResult
    | 0, _, _, _ => .error "IR fuel semantics expression fuel exhausted"
    | fuel + 1, state, frame, expr =>
      match expr with
      | .literal literal => do
          let value ← literalValue literal
          .ok (state, value)
      | .local name =>
          match frame.read name with
          | some value => .ok (state, value)
          | none => .error s!"unknown local `{name}`"
      | .add lhs rhs _ => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "add" (· + ·) lhsValue rhsValue)
      | .sub lhs rhs _ => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "sub" (· - ·) lhsValue rhsValue)
      | .mul lhs rhs _ => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "mul" (· * ·) lhsValue rhsValue)
      | .div lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "div"
            (fun lhs rhs => if rhs == 0 then 0 else lhs / rhs) lhsValue rhsValue)
      | .mod lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "mod"
            (fun lhs rhs => if rhs == 0 then 0 else lhs % rhs) lhsValue rhsValue)
      | .pow lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "pow" (· ^ ·) lhsValue rhsValue)
      | .bitAnd lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "bitAnd" Nat.land lhsValue rhsValue)
      | .bitOr lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "bitOr" Nat.lor lhsValue rhsValue)
      | .bitXor lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "bitXor" Nat.xor lhsValue rhsValue)
      | .shiftLeft lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "shiftLeft"
            (fun lhs rhs => lhs * (2 ^ rhs)) lhsValue rhsValue)
      | .shiftRight lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "shiftRight"
            (fun lhs rhs => lhs / (2 ^ rhs)) lhsValue rhsValue)
      | .cast value targetType => do
          let (nextState, rawValue) ← evalExprFuel fuel state frame value
          .ok (nextState, ← castValue rawValue targetType)
      | .eq lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalEquality lhsValue rhsValue)
      | .ne lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          match ← evalEquality lhsValue rhsValue with
          | .bool value => .ok (stateAfterRhs, .bool (!value))
          | _ => .error "equality returned a non-Bool value"
      | .lt lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericPredicate "lt" (· < ·) lhsValue rhsValue)
      | .le lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericPredicate "le" (· <= ·) lhsValue rhsValue)
      | .gt lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericPredicate "gt" (· > ·) lhsValue rhsValue)
      | .ge lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericPredicate "ge" (· >= ·) lhsValue rhsValue)
      | .boolAnd lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalBooleanBinary "boolAnd" (fun lhs rhs => lhs && rhs)
            lhsValue rhsValue)
      | .boolOr lhs rhs => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalBooleanBinary "boolOr" (fun lhs rhs => lhs || rhs)
            lhsValue rhsValue)
      | .boolNot value => do
          let (nextState, rawValue) ← evalExprFuel fuel state frame value
          match rawValue with
          | .bool value => .ok (nextState, .bool (!value))
          | _ => .error "boolNot expects Bool operand"
      | .nativeValue => .ok (state, .u64 0)
      | .effect effect =>
          evalEffectFuel fuel state frame effect
      | _ => unsupportedExpr expr

  def evalEffectFuel : Nat → State → Frame → Effect → Except String ExprResult
    | 0, _, _, _ => .error "IR fuel semantics effect fuel exhausted"
    | fuel + 1, state, frame, effect =>
      match effect with
      | .storageScalarRead name =>
          match state.read name with
          | some value => .ok (state, value)
          | none => .error s!"unknown scalar state `{name}`"
      | .storageScalarWrite name valueExpr => do
          let (nextState, value) ← evalExprFuel fuel state frame valueExpr
          .ok (nextState.write name value, .unit)
      | .storageScalarAssignOp name op valueExpr => do
          let current ←
            match state.read name with
            | some value => .ok value
            | none => .error s!"unknown scalar state `{name}`"
          let (nextState, rhs) ← evalExprFuel fuel state frame valueExpr
          let value ← evalAssignOp op current rhs
          .ok (nextState.write name value, value)
      | .storageMapGet name keyExpr => do
          let (nextState, keyValue) ← evalExprFuel fuel state frame keyExpr
          let key := valueKeyScalar keyValue
          match nextState.read (mapKey name key) with
          | some value => .ok (nextState, value)
          | none => .error s!"unknown map state `{name}` key `{key}`"
      | .storageMapInsert name keyExpr valueExpr
      | .storageMapSet name keyExpr valueExpr => do
          let (stateAfterKey, keyValue) ← evalExprFuel fuel state frame keyExpr
          let key := valueKeyScalar keyValue
          let (stateAfterValue, newValue) ← evalExprFuel fuel stateAfterKey frame valueExpr
          let oldValue := (stateAfterValue.read (mapKey name key)).getD (zeroLikeScalar newValue)
          let nextState :=
            (stateAfterValue.write (mapKey name key) newValue).write
              (mapPresentKey name key) (.bool true)
          .ok (nextState, oldValue)
      | .storageMapDelete name keyExpr => do
          let (nextState, keyValue) ← evalExprFuel fuel state frame keyExpr
          let key := valueKeyScalar keyValue
          let oldValue := (nextState.read (mapKey name key)).getD (.unit)
          let nextState := nextState.erase (mapKey name key)
          let nextState := nextState.erase (mapPresentKey name key)
          .ok (nextState, oldValue)
      | .storageMapContains name keyExpr => do
          let (nextState, keyValue) ← evalExprFuel fuel state frame keyExpr
          let key := valueKeyScalar keyValue
          .ok (nextState, .bool ((nextState.read (mapPresentKey name key)).isSome))
      | .storageStructFieldRead name fieldName =>
          match state.readStructField name fieldName with
          | some value => .ok (state, value)
          | none => .error s!"unknown struct field state `{name}.{fieldName}`"
      | .storageStructFieldWrite name fieldName valueExpr => do
          let (nextState, value) ← evalExprFuel fuel state frame valueExpr
          .ok (nextState.write (fieldKey name fieldName) value, .unit)
      | .contextRead field =>
          match field with
          | .userId | .contractId | .checkpointId | .timestamp | .epochHeight
          | .chainId | .gasPrice | .gasLeft | .prepaidGas | .usedGas | .baseFee | .prevRandao =>
              .ok (state, .u64 0)
          | .userIdHash | .randomSeed | .origin | .coinbase | .blockHash _ =>
              .ok (state, .hash 0 0 0 0)
      | .eventEmit name fields => do
          let (nextState, data) ← evalEventFieldFuel fuel state frame fields
          .ok (nextState.recordEvent name #[] data, .unit)
      | .eventEmitIndexed name indexedFields dataFields => do
          let (nextState, indexed) ← evalEventFieldFuel fuel state frame indexedFields
          let (nextState, data) ← evalEventFieldFuel fuel nextState frame dataFields
          .ok (nextState.recordEvent name indexed data, .unit)
      | .checkErc721Received operator fromAddr toAddr tokenId => do
          -- Abstract fuel model: evaluate args; host CALL is EVM-only (PF-P2-02).
          let (s1, _) ← evalExprFuel fuel state frame operator
          let (s2, _) ← evalExprFuel fuel s1 frame fromAddr
          let (s3, _) ← evalExprFuel fuel s2 frame toAddr
          let (s4, _) ← evalExprFuel fuel s3 frame tokenId
          .ok (s4, .unit)
      | .checkErc1155Received operator fromAddr toAddr id amount => do
          let (s1, _) ← evalExprFuel fuel state frame operator
          let (s2, _) ← evalExprFuel fuel s1 frame fromAddr
          let (s3, _) ← evalExprFuel fuel s2 frame toAddr
          let (s4, _) ← evalExprFuel fuel s3 frame id
          let (s5, _) ← evalExprFuel fuel s4 frame amount
          .ok (s5, .unit)
      | .checkErc1155BatchReceived operator fromAddr toAddr ids amounts => do
          let (s1, _) ← evalExprFuel fuel state frame operator
          let (s2, _) ← evalExprFuel fuel s1 frame fromAddr
          let (s3, _) ← evalExprFuel fuel s2 frame toAddr
          let (s4, _) ← evalExprFuel fuel s3 frame ids
          let (s5, _) ← evalExprFuel fuel s4 frame amounts
          .ok (s5, .unit)
      | _ => unsupportedEffect effect

  /-- Total fuel-indexed evaluation of event field arrays. -/
  def evalEventFieldFuel (fuel : Nat) (state : State) (frame : Frame)
      (fields : Array (String × Expr)) : Except String (State × Array Value) :=
    fields.foldlM (fun (accState, accValues) field =>
      match evalExprFuel fuel accState frame field.snd with
      | .error e => .error e
      | .ok (stateAfterField, value) => .ok (stateAfterField, accValues.push value))
      (state, #[])

  def execStmtFuel : Nat → State → Frame → Statement →
      Except String (State × Frame × Option Value)
    | 0, _, _, _ => .error "IR fuel semantics statement fuel exhausted"
    | fuel + 1, state, frame, statement =>
      match statement with
      | .letBind name _ value => do
          let (nextState, evaluated) ← evalExprFuel fuel state frame value
          .ok (nextState, frame.write name evaluated, none)
      | .letMutBind name _ value => do
          let (nextState, evaluated) ← evalExprFuel fuel state frame value
          .ok (nextState, frame.write name evaluated, none)
      | .assign target value =>
          match target with
          | .local name => do
              let (nextState, evaluated) ← evalExprFuel fuel state frame value
              .ok (nextState, frame.write name evaluated, none)
          | _ => unsupportedStatement statement
      | .assignOp target op value =>
          match target with
          | .local name => do
              let current ← match frame.read name with
                | some v => .ok v
                | none => .error s!"assignOp on unbound local `{name}`"
              let (nextState, rhs) ← evalExprFuel fuel state frame value
              let updated ← evalAssignOp op current rhs
              .ok (nextState, frame.write name updated, none)
          | _ => unsupportedStatement statement
      | .effect effect => do
          let (nextState, _) ← evalEffectFuel fuel state frame effect
          .ok (nextState, frame, none)
      | .assert condition message _ => do
          let (nextState, conditionValue) ← evalExprFuel fuel state frame condition
          if ← truthy conditionValue then
            .ok (nextState, frame, none)
          else
            .error s!"assertion failed: {message}"
      | .assertEq lhs rhs message _ => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          if lhsValue == rhsValue then
            .ok (stateAfterRhs, frame, none)
          else
            .error s!"assertion failed: {message}"
      | .revert message =>
          .error s!"revert: {message}"
      | .revertWithError errorRef =>
          .error s!"revert: assertion_id={errorRef.assertionId}"
      | .ifElse condition thenBody elseBody => do
          let (nextState, conditionValue) ← evalExprFuel fuel state frame condition
          let selectedBody := if ← truthy conditionValue then thenBody else elseBody
          let (branchState, returnValue?) ←
            execStatementsFuel fuel selectedBody.toList nextState frame
          .ok (branchState, frame, returnValue?)
      | .boundedFor indexName start stopExclusive body =>
          -- U5.2: total fuel-indexed bounded loop (static start/stop, like IR.Semantics).
          execBoundedForFuel fuel indexName start stopExclusive body state frame
      | .return value => do
          let (nextState, returnValue) ← evalExprFuel fuel state frame value
          .ok (nextState, frame, some returnValue)
      | _ => unsupportedStatement statement

  /-- Fuel-indexed `boundedFor`: each iteration consumes fuel; early `return` exits. -/
  def execBoundedForFuel : Nat → String → Nat → Nat → Array Statement → State → Frame →
      Except String (State × Frame × Option Value)
    | 0, _, _, _, _, _, _ => .error "IR fuel semantics boundedFor fuel exhausted"
    | fuel + 1, indexName, index, stopExclusive, body, state, frame =>
        if index < stopExclusive then
          let loopFrame := frame.write indexName (.u32 index)
          do
            let (nextState, returnValue?) ← execStatementsFuel fuel body.toList state loopFrame
            match returnValue? with
            | some value => .ok (nextState, frame, some value)
            | none =>
                execBoundedForFuel fuel indexName (index + 1) stopExclusive body nextState frame
        else
          .ok (state, frame, none)

  def execStatementsFuel : Nat → List Statement → State → Frame →
      Except String (State × Option Value)
    | 0, _, _, _ => .error "IR fuel semantics statement-list fuel exhausted"
    | _fuel + 1, [], state, _frame => .ok (state, none)
    | fuel + 1, statement :: rest, state, frame => do
        let (nextState, nextFrame, returnValue?) ← execStmtFuel fuel state frame statement
        match returnValue? with
        | some returnValue => .ok (nextState, some returnValue)
        | none => execStatementsFuel fuel rest nextState nextFrame
end

/-- Run a single entrypoint with explicit args under the fueled interpreter. -/
def runEntrypointWithArgsFuel (fuel : Nat) (state : State)
    (entrypoint : Entrypoint) (args : Array Value) :
    Except String (State × Option Value) := do
  let frame ← bindParams entrypoint.params args
  execStatementsFuel fuel entrypoint.body.toList state frame

/-- Run a single entrypoint with no args under the fueled interpreter. -/
def runEntrypointNoArgsFuel (fuel : Nat) (state : State) (entrypoint : Entrypoint) :
    Except String (State × Option Value) :=
  execStatementsFuel fuel entrypoint.body.toList state Frame.empty

/-- Run an entrypoint with the default fuel. This is the fuel-less step shape
that `runTraceListGen` / `traceSimulation_lift` consume
(`State → Call → Except (State × Obs)` after a per-contract `Call` wrapper). -/
def runEntrypointFuel (state : State) (entrypoint : Entrypoint) :
    Except String (State × Option Value) :=
  runEntrypointNoArgsFuel defaultFuel state entrypoint

end ProofForge.IR.SemanticsFuel