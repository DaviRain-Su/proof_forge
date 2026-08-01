import ProofForgeV2.Targets.Solana.ValidatePlanV1

/-!
# Solana EmitIRV1 — Plan → IR emission

sBPF audit IR, validateIR, lower/emitFromIR.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

inductive Check where
  | instructionDataLen (bytes : Nat)
  | ownerCurrentProgram (accountIndex : Nat)
  | accountDataLen (accountIndex bytes : Nat)
  | signer (accountIndex : Nat)
  | writable (accountIndex : Nat)
  | headerEquals (accountIndex byteOffset : Nat) (value : UInt64)
  deriving BEq, Inhabited, Repr

inductive Operation where
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination dataOffset : Nat)
  /-- Narrow ABI param load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `loadParam`. -/
  | narrowLoadParam (bitWidth destination dataOffset : Nat)
  | loadState (destination accountIndex byteOffset : Nat)
  /-- Narrow ABI state load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `loadState`. -/
  | narrowLoadState (bitWidth destination accountIndex byteOffset : Nat)
  | checkedAdd (destination lhs rhs errorCode : Nat)
  | checkedSub (destination lhs rhs errorCode : Nat)
  | signedCheckedAdd (destination lhs rhs errorCode : Nat)
  | signedCheckedSub (destination lhs rhs errorCode : Nat)
  | signedCheckedMul (destination lhs rhs errorCode : Nat)
  | signedCheckedDiv (destination lhs rhs errorCode : Nat)
  | signedCheckedMod (destination lhs rhs errorCode : Nat)
  | checkedNeg (destination source errorCode : Nat)
  | signedCompare (destination lhs rhs : Nat) (op : ComparisonOp)
  | checkedSar (destination lhs rhs shiftError : Nat)
  | zeroState (accountIndex byteOffset : Nat)
  /-- Narrow field zero on init (`bitWidth ∈ {8,16,32}`); UInt64 keeps `zeroState`. -/
  | narrowZeroState (bitWidth accountIndex byteOffset : Nat)
  | storeState (accountIndex byteOffset value : Nat)
  /-- Narrow field store (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `storeState`. -/
  | narrowStoreState (bitWidth accountIndex byteOffset value : Nat)
  | setHeader (accountIndex byteOffset : Nat) (value : UInt64)
  | setReturnData (value : Nat)
  | setReturnDataBool (value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat) (errorCode : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
  | returnNone
  | ifRegion (condition : Nat) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : Nat) (cases : Array (UInt64 × Array Operation))
      (defaultOps : Array Operation)
  /-- Structured bounded loop matching reference `noteBackEdge` semantics.
      `varTemp` is the IR induction temporary, seeded by `initial`.
      `counterTemp` is a completed-iteration counter seeded to 0 before the
      region (outer `const_u64 0`). Each iteration: evaluate `condOps`→`cond`;
      while true take `bodyOps`; then at the back edge run `boundOps` which
      assert `counter ≠ maxIterations` (else `loopBoundExceededError`) and
      rebind `counterTemp := counterNext` (`counter + 1`); then `updateOps`→
      `update` rebinds `varTemp`. Bodies 1..N pass the check; the (N+1)-th body
      runs and then errors; a return inside any body exits before the check.
      Latch `i + 1` cannot overflow under Normalize (`i < end ≤ UInt64.max`). -/
  | forRegion (varTemp initial counterTemp : Nat) (maxIterations : Nat)
      (condOps : Array Operation) (cond : Nat)
      (bodyOps : Array Operation)
      (boundOps : Array Operation) (counterNext : Nat)
      (updateOps : Array Operation) (update : Nat)
  | callFn (fnIndex : Nat) (destination : Nat) (args : Array Nat)
  | checkedMul (destination lhs rhs errorCode : Nat)
  | checkedDiv (destination lhs rhs errorCode : Nat)
  | checkedMod (destination lhs rhs errorCode : Nat)
  /-- Plain UInt64 bitwise AND (no program_error). -/
  | bitAnd (destination lhs rhs : Nat)
  /-- Plain UInt64 bitwise OR (no program_error). -/
  | bitOr (destination lhs rhs : Nat)
  /-- Plain UInt64 bitwise XOR (no program_error). -/
  | bitXor (destination lhs rhs : Nat)
  /-- UInt64 left shift: `shiftError` for count ≥ 64, `overflowError` when the
      mathematical result does not fit in UInt64. -/
  | checkedShl (destination lhs rhs shiftError overflowError : Nat)
  /-- UInt64 logical right shift: `shiftError` for count ≥ 64. -/
  | checkedShr (destination lhs rhs shiftError : Nat)
  | bitNot (destination source : Nat)
  | boolNot (destination source : Nat)
  /-- Strict Bool AND on 0/1 words (no short-circuit, no program_error). -/
  | boolAnd (destination lhs rhs : Nat)
  /-- Strict Bool OR on 0/1 words (no short-circuit, no program_error). -/
  | boolOr (destination lhs rhs : Nat)
  /-- Body multi-width checked add (`bitWidth ∈ {8,16,32}` only; w=64 uses
      historical `checkedAdd`). Field order: bitWidth, dest, lhs, rhs, error. -/
  | narrowCheckedAdd (bitWidth destination lhs rhs errorCode : Nat)
  | narrowCheckedSub (bitWidth destination lhs rhs errorCode : Nat)
  | narrowCheckedMul (bitWidth destination lhs rhs errorCode : Nat)
  | narrowCheckedDiv (bitWidth destination lhs rhs errorCode : Nat)
  | narrowCheckedMod (bitWidth destination lhs rhs errorCode : Nat)
  | narrowBitAnd (bitWidth destination lhs rhs : Nat)
  | narrowBitOr (bitWidth destination lhs rhs : Nat)
  | narrowBitXor (bitWidth destination lhs rhs : Nat)
  | narrowBitNot (bitWidth destination source : Nat)
  | narrowCheckedShl (bitWidth destination lhs rhs shiftError overflowError : Nat)
  | narrowCheckedShr (bitWidth destination lhs rhs shiftError : Nat)
  deriving BEq, Inhabited, Repr

structure HandlerIR where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  resultKind : ResultKind
  accountAccess : AccountAccess
  checks : Array Check
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Lowered pureFn body (plan-level temps; returns via setReturnData*/fn ret). -/
structure FnIR where
  name : String
  params : Array Param
  resultIsBool : Bool
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed, plan-level sBPF audit IR. It is intentionally not an ELF or an
assembler input until the pinned sBPF toolchain/backend exists.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`). -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  stateAccount : StateAccount
  fns : Array FnIR
  handlers : Array HandlerIR
  deriving BEq, Repr
private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

/-- Lookup plan-level loop induction temp → IR temp. Missing binding is a
    plan/IR construction bug (validatePlan admits `.temp` only under forLoop). -/
private def resolveTempV1 (tempMap : List (Nat × Nat)) (id : Nat) : Nat :=
  match tempMap.find? (fun p => p.1 == id) with
  | some (_, irTemp) => irTemp
  | none => id

private partial def lowerExpr (overflowError : Nat) (tempMap : List (Nat × Nat))
    (next : Nat) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param dataOffset =>
      { operations := #[.loadParam next dataOffset], value := next, next := next + 1 }
  | .narrowParam bitWidth dataOffset =>
      { operations := #[.narrowLoadParam bitWidth next dataOffset],
        value := next, next := next + 1 }
  | .stateLoad accountIndex byteOffset =>
      { operations := #[.loadState next accountIndex byteOffset], value := next, next := next + 1 }
  | .narrowStateLoad bitWidth accountIndex byteOffset =>
      { operations := #[.narrowLoadState bitWidth next accountIndex byteOffset],
        value := next, next := next + 1 }
  | .temp id =>
      let irTemp := resolveTempV1 tempMap id
      { operations := #[], value := irTemp, next }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitAnd lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitOr lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitXor lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shl lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          -- shiftError first (count ≥ 64), then overflowError (result ≥ 2^64).
          #[.checkedShl rhs.next lhs.value rhs.value invalidShiftError overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shr lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedShr rhs.next lhs.value rhs.value invalidShiftError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitNot operand =>
      let operand := lowerExpr overflowError tempMap next operand
      {
        operations := operand.operations ++ #[.bitNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .narrowBitNot bitWidth operand =>
      let operand := lowerExpr overflowError tempMap next operand
      {
        operations := operand.operations ++
          #[.narrowBitNot bitWidth operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .narrowCheckedAdd bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedAdd bitWidth rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedSub bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedSub bitWidth rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMul bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMul bitWidth rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedDiv bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedDiv bitWidth rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMod bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMod bitWidth rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowBitAnd bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitAnd bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowBitOr bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitOr bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowBitXor bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitXor bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowShl bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedShl bitWidth rhs.next lhs.value rhs.value
              invalidShiftError overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowShr bitWidth lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedShr bitWidth rhs.next lhs.value rhs.value invalidShiftError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .boolNot operand =>
      let operand := lowerExpr overflowError tempMap next operand
      {
        operations := operand.operations ++ #[.boolNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .boolAnd lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .boolOr lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedAdd lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedAdd rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedSub lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedSub rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedMul lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMul rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedDiv lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedDiv rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedMod lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMod rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCompare op lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedNeg operand =>
      let operand := lowerExpr overflowError tempMap next operand
      {
        operations := operand.operations ++
          #[.checkedNeg operand.next operand.value overflowError]
        value := operand.next
        next := operand.next + 1
      }
  | .sar lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSar rhs.next lhs.value rhs.value invalidShiftError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .callFn fnIndex args =>
      Id.run do
        let mut operations : Array Operation := #[]
        let mut next := next
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let lowered := lowerExpr overflowError tempMap next arg
          operations := operations ++ lowered.operations
          argTemps := argTemps.push lowered.value
          next := lowered.next
        {
          operations := operations ++ #[.callFn fnIndex next argTemps]
          value := next
          next := next + 1
        }
private def checksFor (discriminatorWidth : Nat) (account : StateAccount)
    (handler : Handler) : Array Check := Id.run do
  let access := handler.accountAccess
  let headerValue := match access.initialization with
    | .mustBeUninitialized => 0
    | .mustBeInitialized => account.initializedMarker
  let mut checks := #[
    .instructionDataLen (discriminatorWidth + handler.params.size * 8),
    .ownerCurrentProgram access.accountIndex,
    .accountDataLen access.accountIndex access.exactDataLen
  ]
  if access.signerRequired then checks := checks.push (.signer access.accountIndex)
  if access.writableRequired then checks := checks.push (.writable access.accountIndex)
  return checks.push (.headerEquals access.accountIndex account.headerOffset headerValue)

/-- Whether every path through a statement list ends in a return (valued or
    bare marker), matching the region emitter's closedness: a list closes iff
    its last statement is a return or a region whose arms all close. An empty
    else/default arm is a fallthrough (open). Used to append a hard `exit`
    after arms whose set_return_data would otherwise fall through into the
    region's continuation (the syscall does not halt execution). -/
private partial def statementListClosesV1 : List Statement → Bool
  | [] => false
  | [statement] =>
      match statement with
      | .returnValue _ | .returnNone | .revertError .. => true
      | .ifThenElse _ thenBody elseBody =>
          !elseBody.isEmpty && statementListClosesV1 thenBody.toList &&
            statementListClosesV1 elseBody.toList
      | .switchOn _ cases defaultBody =>
          !defaultBody.isEmpty && statementListClosesV1 defaultBody.toList &&
            cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList
      | .store _ | .assert _ | .emitEvent .. | .forLoop .. => false
  | _ :: _ :: rest => statementListClosesV1 rest

/-- Append the hard exit after a closed region arm, unless the arm already
    ends in a halting statement (the initializer's bare-return marker, or a
    declared revert, which traps by itself). -/
private def armOpsWithHardExit (arm : Array Statement)
    (operations : Array Operation) : Array Operation :=
  let alreadyHalts := match arm.back? with
    | some .returnNone | some (.revertError ..) => true
    | _ => false
  if statementListClosesV1 arm.toList && !alreadyHalts then
    operations.push .returnNone
  else
    operations

private partial def lowerBodyOps
    (overflowError : Nat) (resultKind : ResultKind) (assertErr boundErr : Nat)
    (tempMap : List (Nat × Nat))
    (next : Nat) (statements : Array Statement) : Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  for statement in statements do
    match statement with
    | .store store =>
        let value := lowerExpr overflowError tempMap next store.value
        operations := operations ++ value.operations
        let storeOp : Operation :=
          if store.byteWidth == 8 then
            .storeState store.accountIndex store.byteOffset value.value
          else
            .narrowStoreState (store.byteWidth * 8) store.accountIndex store.byteOffset value.value
        operations := operations.push storeOp
        next := value.next
    | .returnValue value =>
        let value := lowerExpr overflowError tempMap next value
        operations := operations ++ value.operations
        let returnOp : Operation := match resultKind with
          | .u64 | .i64 => .setReturnData value.value
          | .bool => .setReturnDataBool value.value
        operations := operations.push returnOp
        next := value.next
    | .returnNone =>
        -- Valid only inside region arms (validated); the initializer's own
        -- final marker is stripped by lowerHandler before lowering.
        operations := operations.push .returnNone
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr overflowError tempMap next arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr overflowError tempMap next arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .assert condition =>
        let value := lowerExpr overflowError tempMap next condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value assertErr)
        next := value.next
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr overflowError tempMap next condition
        operations := operations ++ value.operations
        let (thenOps, next1) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap value.next thenBody
        let (elseOps, next2) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap next1 elseBody
        operations := operations.push (.ifRegion value.value
          (armOpsWithHardExit thenBody thenOps) (armOpsWithHardExit elseBody elseOps))
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr overflowError tempMap next scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) :=
            lowerBodyOps overflowError resultKind assertErr boundErr tempMap nextC caseBody
          caseOps := caseOps.push (caseValue, armOpsWithHardExit caseBody ops)
          nextC := next1
        let (defaultOps, nextD) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap nextC defaultBody
        operations := operations.push (.switchRegion value.value caseOps
          (armOpsWithHardExit defaultBody defaultOps))
        next := nextD
    | .forLoop varTemp initial cond update maxIterations body =>
        -- Seed induction from `initial`, allocate completed-iteration counter
        -- at 0, then bind plan varTemp → induction IR temp.
        let initL := lowerExpr overflowError tempMap next initial
        operations := operations ++ initL.operations
        let irVar := initL.value
        let counterTemp := initL.next
        operations := operations.push (.literal counterTemp 0)
        let tempMap' := (varTemp, irVar) :: tempMap
        let afterSeed := counterTemp + 1
        let condL := lowerExpr overflowError tempMap' afterSeed cond
        let (bodyOps, nextBody) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap' condL.next body
        -- Back-edge bound check (reference noteBackEdge): after the body, if
        -- completed iterations already equal N, revert boundExceeded; else
        -- increment the counter. Counter ≤ N ≤ 4096 so +1 cannot overflow;
        -- still use checked_add to stay within the existing opcode set.
        let litN := nextBody
        let eqT := nextBody + 1
        let okT := nextBody + 2
        let lit1 := nextBody + 3
        let counterNext := nextBody + 4
        let boundOps : Array Operation := #[
          .literal litN (UInt64.ofNat maxIterations),
          .compare eqT counterTemp litN .eq,
          .boolNot okT eqT,
          .assert okT boundErr,
          .literal lit1 1,
          .checkedAdd counterNext counterTemp lit1 overflowError
        ]
        let updateL := lowerExpr overflowError tempMap' (counterNext + 1) update
        operations := operations.push (.forRegion irVar irVar counterTemp maxIterations
          condL.operations condL.value bodyOps boundOps counterNext
          updateL.operations updateL.value)
        next := updateL.next
  pure (operations, next)

private def lowerHandler (plan : Plan) (handler : Handler) : HandlerIR := Id.run do
  let account := plan.stateAccount
  let operations0 : Array Operation :=
    if handler.mode == .initialize then
      account.fields.map fun field =>
        if field.byteWidth == 8 then
          .zeroState field.accountIndex field.byteOffset
        else
          .narrowZeroState (field.byteWidth * 8) field.accountIndex field.byteOffset
    else
      #[]
  -- The initializer's final bare-return marker is the natural fall-through;
  -- in-arm markers are rejected by validatePlan and never reach this point.
  let body := if handler.body.back? == some .returnNone then
    handler.body.pop
  else
    handler.body
  let (bodyOps, _) := lowerBodyOps
    plan.arithmeticOverflowError handler.resultKind
    plan.assertionFailedError plan.loopBoundExceededError [] 0 body
  let mut operations := operations0 ++ bodyOps
  if handler.mode == .initialize then
    operations := operations.push <|
      .setHeader account.index account.headerOffset account.initializedMarker
  return {
    name := handler.name
    discriminator := handler.discriminator
    params := handler.params
    mode := handler.mode
    resultKind := handler.resultKind
    accountAccess := handler.accountAccess
    checks := checksFor plan.instructionDiscriminatorBytes account handler
    operations
  }

/-- Admitted narrow body widths for Operation constructors (UInt64 uses historical). -/
private def isNarrowBodyWidth (w : Nat) : Bool :=
  w == 8 || w == 16 || w == 32

private def tempDestination? : Operation → Option Nat
  | .literal destination .. | .loadParam destination .. |
      .narrowLoadParam _ destination .. |
      .loadState destination .. | .narrowLoadState _ destination .. |
      .checkedAdd destination .. |
      .signedCheckedAdd destination .. | .signedCheckedSub destination .. |
      .signedCheckedMul destination .. | .signedCheckedDiv destination .. |
      .signedCheckedMod destination .. | .checkedNeg destination .. |
      .signedCompare destination .. | .checkedSar destination .. |
      .checkedSub destination .. | .checkedMul destination .. |
      .checkedDiv destination .. | .checkedMod destination .. |
      .bitAnd destination .. | .bitOr destination .. | .bitXor destination .. |
      .checkedShl destination .. | .checkedShr destination .. |
      .bitNot destination _ | .boolNot destination _ |
      .boolAnd destination .. | .boolOr destination .. |
      .narrowCheckedAdd _ destination .. | .narrowCheckedSub _ destination .. |
      .narrowCheckedMul _ destination .. | .narrowCheckedDiv _ destination .. |
      .narrowCheckedMod _ destination .. |
      .narrowBitAnd _ destination .. | .narrowBitOr _ destination .. |
      .narrowBitXor _ destination .. | .narrowBitNot _ destination _ |
      .narrowCheckedShl _ destination .. | .narrowCheckedShr _ destination .. |
      .compare destination .. | .callFn _ destination _ => some destination
  | _ => none

private def lowerFn (plan : Plan) (fn : FnBinding) : FnIR := Id.run do
  let resultKind : ResultKind :=
    if fn.resultIsBool then .bool else if fn.resultIsInt then .i64 else .u64
  let (bodyOps, _) := lowerBodyOps
    plan.arithmeticOverflowError resultKind
    plan.assertionFailedError plan.loopBoundExceededError [] 0 fn.body
  {
    name := fn.name
    params := fn.params
    resultIsBool := fn.resultIsBool
    operations := bodyOps
  }
/-- Recursive operation-sequence validator: canonical temp numbering across
    nested regions, operand range checks, and per-level terminator ordering.
    Returns (next, returnedOnThisLevel, initializedOnThisLevel). -/
private partial def validateOperationSequence
    (plan : Plan) (handler : HandlerIR)
    (fieldOffsets paramOffsets : Array Nat)
    (operations : Array Operation) (next : Nat) :
    CompileResult (Nat × Bool × Bool) := do
  let account := plan.stateAccount
  let mut next := next
  let mut returned := false
  let mut initialized := false
  let mut halted := false
  for operation in operations do
    if halted then
      throw <| .planInvariant .solana "typed Solana IR has an operation after its hard exit"
    if let some destination := tempDestination? operation then
      unless destination == next do
        throw <| .planInvariant .solana "typed Solana IR temporary numbering is not canonical"
      next := next + 1
    match operation with
    | .returnNone =>
        -- The hard exit terminates an arm after set_return_data (or the
        -- initializer's bare return); it neither sets nor requires flags.
        halted := true
    | .literal ..
    | .loadParam .. | .narrowLoadParam .. | .loadState .. | .narrowLoadState ..
    | .checkedAdd .. | .checkedSub ..
    | .signedCheckedAdd .. | .signedCheckedSub .. | .signedCheckedMul ..
    | .signedCheckedDiv .. | .signedCheckedMod .. | .checkedNeg ..
    | .signedCompare .. | .checkedSar ..
    | .checkedMul .. | .checkedDiv .. | .checkedMod ..
    | .bitAnd .. | .bitOr .. | .bitXor ..
    | .checkedShl .. | .checkedShr ..
    | .bitNot .. | .boolNot ..
    | .boolAnd .. | .boolOr ..
    | .narrowCheckedAdd .. | .narrowCheckedSub .. | .narrowCheckedMul ..
    | .narrowCheckedDiv .. | .narrowCheckedMod ..
    | .narrowBitAnd .. | .narrowBitOr .. | .narrowBitXor .. | .narrowBitNot ..
    | .narrowCheckedShl .. | .narrowCheckedShr ..
    | .compare .. | .assert .. | .zeroState .. | .narrowZeroState ..
    | .storeState .. | .narrowStoreState ..
    | .setHeader .. | .setReturnData .. | .setReturnDataBool ..
    | .emitEvent .. | .revertError ..
    | .ifRegion .. | .switchRegion .. | .forRegion .. | .callFn .. =>
        if returned || initialized then
          throw <| .planInvariant .solana "typed Solana IR has an operation after its terminator"
    match operation with
    | .returnNone => pure ()
    | .literal .. => pure ()
    | .loadParam _ dataOffset =>
        unless paramOffsets.contains dataOffset do
          throw <| .planInvariant .solana "typed Solana IR loads an unknown parameter offset"
    | .narrowLoadParam bitWidth _ dataOffset =>
        unless isNarrowBodyWidth bitWidth && paramOffsets.contains dataOffset do
          throw <| .planInvariant .solana
            "typed Solana IR narrowLoadParam width/offset is invalid"
    | .loadState _ accountIndex byteOffset =>
        unless accountIndex == account.index && fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana "typed Solana IR loads an unknown state field"
    | .narrowLoadState bitWidth _ accountIndex byteOffset =>
        unless isNarrowBodyWidth bitWidth && accountIndex == account.index &&
            fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana
            "typed Solana IR narrowLoadState width/field is invalid"
    | .checkedAdd _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-add operands/error are invalid"
    | .checkedSub _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-sub operands/error are invalid"
    | .checkedMul _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-mul operands/error are invalid"
    | .checkedDiv _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-div operands/error are invalid"
    | .checkedMod _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-mod operands/error are invalid"
    | .signedCheckedAdd _ lhs rhs errorCode
    | .signedCheckedSub _ lhs rhs errorCode
    | .signedCheckedMul _ lhs rhs errorCode
    | .signedCheckedDiv _ lhs rhs errorCode
    | .signedCheckedMod _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR signed checked-arith operands/error are invalid"
    | .checkedNeg _ source errorCode =>
        unless source < next - 1 && errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checkedNeg operand/error is invalid"
    | .signedCompare _ lhs rhs _op =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR signedCompare operands are invalid"
    | .checkedSar _ lhs rhs shiftError =>
        unless lhs < next - 1 && rhs < next - 1 &&
            shiftError == plan.invalidShiftError do
          throw <| .planInvariant .solana "typed Solana IR checkedSar operands/error are invalid"
    | .bitAnd _ lhs rhs =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR bitAnd operands are invalid"
    | .bitOr _ lhs rhs =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR bitOr operands are invalid"
    | .bitXor _ lhs rhs =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR bitXor operands are invalid"
    | .checkedShl _ lhs rhs shiftError overflowError =>
        unless lhs < next - 1 && rhs < next - 1 &&
            shiftError == plan.invalidShiftError &&
            overflowError == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-shl operands/errors are invalid"
    | .checkedShr _ lhs rhs shiftError =>
        unless lhs < next - 1 && rhs < next - 1 &&
            shiftError == plan.invalidShiftError do
          throw <| .planInvariant .solana "typed Solana IR checked-shr operands/error are invalid"
    | .bitNot _ source =>
        unless source < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR bitNot operand is invalid"
    | .narrowCheckedAdd bitWidth _ lhs rhs errorCode
    | .narrowCheckedSub bitWidth _ lhs rhs errorCode
    | .narrowCheckedMul bitWidth _ lhs rhs errorCode
    | .narrowCheckedDiv bitWidth _ lhs rhs errorCode
    | .narrowCheckedMod bitWidth _ lhs rhs errorCode =>
        unless isNarrowBodyWidth bitWidth && lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana
            "typed Solana IR narrow checked-arith width/operands/error are invalid"
    | .narrowBitAnd bitWidth _ lhs rhs
    | .narrowBitOr bitWidth _ lhs rhs
    | .narrowBitXor bitWidth _ lhs rhs =>
        unless isNarrowBodyWidth bitWidth && lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana
            "typed Solana IR narrow bitwise width/operands are invalid"
    | .narrowBitNot bitWidth _ source =>
        unless isNarrowBodyWidth bitWidth && source < next - 1 do
          throw <| .planInvariant .solana
            "typed Solana IR narrow bitNot width/operand is invalid"
    | .narrowCheckedShl bitWidth _ lhs rhs shiftError overflowError =>
        unless isNarrowBodyWidth bitWidth && lhs < next - 1 && rhs < next - 1 &&
            shiftError == plan.invalidShiftError &&
            overflowError == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana
            "typed Solana IR narrow checked-shl width/operands/errors are invalid"
    | .narrowCheckedShr bitWidth _ lhs rhs shiftError =>
        unless isNarrowBodyWidth bitWidth && lhs < next - 1 && rhs < next - 1 &&
            shiftError == plan.invalidShiftError do
          throw <| .planInvariant .solana
            "typed Solana IR narrow checked-shr width/operands/error are invalid"
    | .boolNot _ source =>
        unless source < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR boolNot operand is invalid"
    | .boolAnd _ lhs rhs =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR boolAnd operands are invalid"
    | .boolOr _ lhs rhs =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR boolOr operands are invalid"
    | .compare _ lhs rhs _op =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR compare operands are invalid"
    | .callFn fnIndex _destination args =>
        unless fnIndex < plan.fns.size do
          throw <| .planInvariant .solana "typed Solana IR callFn index is out of range"
        unless args.size == plan.fns[fnIndex]!.params.size do
          throw <| .planInvariant .solana "typed Solana IR callFn arity is invalid"
        unless args.all (· < next - 1) do
          throw <| .planInvariant .solana "typed Solana IR callFn arguments are invalid"
    | .assert condition errorCode =>
        -- Bare assert uses assertionFailedError; for-loop back-edge bound
        -- checks use loopBoundExceededError (validated further in forRegion).
        unless condition < next &&
            (errorCode == plan.assertionFailedError ||
              errorCode == plan.loopBoundExceededError) do
          throw <| .planInvariant .solana "typed Solana IR assert condition/error is invalid"
    | .zeroState accountIndex byteOffset =>
        unless handler.mode == .initialize && accountIndex == account.index &&
            fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana "typed Solana IR zeroes an unknown state field"
    | .narrowZeroState bitWidth accountIndex byteOffset =>
        unless isNarrowBodyWidth bitWidth && handler.mode == .initialize &&
            accountIndex == account.index && fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana
            "typed Solana IR narrowZeroState width/field is invalid"
    | .storeState accountIndex byteOffset value =>
        unless handler.mode != .view && accountIndex == account.index &&
            fieldOffsets.contains byteOffset && value < next do
          throw <| .planInvariant .solana "typed Solana IR store is invalid"
    | .narrowStoreState bitWidth accountIndex byteOffset value =>
        unless isNarrowBodyWidth bitWidth && handler.mode != .view &&
            accountIndex == account.index && fieldOffsets.contains byteOffset &&
            value < next do
          throw <| .planInvariant .solana
            "typed Solana IR narrowStoreState width/store is invalid"
    | .setHeader accountIndex byteOffset value =>
        unless handler.mode == .initialize && accountIndex == account.index &&
            byteOffset == account.headerOffset && value == account.initializedMarker do
          throw <| .planInvariant .solana "typed Solana IR header write is invalid"
        initialized := true
    | .setReturnData value =>
        unless handler.mode != .initialize && handler.resultKind == .u64 && value < next do
          throw <| .planInvariant .solana "typed Solana IR UInt64 return value is invalid"
        returned := true
    | .setReturnDataBool value =>
        unless handler.mode != .initialize && handler.resultKind == .bool && value < next do
          throw <| .planInvariant .solana "typed Solana IR Bool return value is invalid"
        returned := true
    | .emitEvent eventIndex args =>
        unless handler.mode != .view && eventIndex < plan.events.size &&
            args.size == plan.events[eventIndex]!.fieldCount &&
            args.all (· < next) do
          throw <| .planInvariant .solana "typed Solana IR event emission is invalid"
    | .revertError errorIndex args =>
        unless errorIndex < plan.errors.size &&
            args.size == plan.errors[errorIndex]!.fieldCount &&
            args.all (· < next) do
          throw <| .planInvariant .solana "typed Solana IR declared revert is invalid"
        -- A declared revert closes this path (return or revert on all paths).
        returned := true
    | .ifRegion condition thenOps elseOps =>
        unless condition < next do
          throw <| .planInvariant .solana "typed Solana IR if-region condition is invalid"
        let (n1, r1, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets thenOps next
        let (n2, r2, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets elseOps n1
        next := n2
        returned := (r1 && r2 && !elseOps.isEmpty) || returned
    | .switchRegion scrutinee cases defaultOps =>
        unless scrutinee < next do
          throw <| .planInvariant .solana "typed Solana IR switch-region scrutinee is invalid"
        let mut nextC := next
        let mut allClosed := !defaultOps.isEmpty
        for (_, ops) in cases do
          let (n, r, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets ops nextC
          nextC := n
          allClosed := allClosed && r
        let (nd, rd, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets defaultOps nextC
        next := nd
        returned := (allClosed && rd) || returned
    | .forRegion varTemp initial counterTemp maxIterations condOps cond bodyOps
          boundOps counterNext updateOps update =>
        unless varTemp == initial && initial < next && counterTemp < next &&
            counterTemp != varTemp do
          throw <| .planInvariant .solana "typed Solana IR for-region induction/counter binding is invalid"
        unless maxIterations <= 4096 do
          throw <| .planInvariant .solana "typed Solana IR for-region maxIterations exceeds 4096"
        let (nCond, rCond, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets condOps next
        unless !rCond && cond < nCond do
          throw <| .planInvariant .solana "typed Solana IR for-region condition is invalid"
        let (nBody, rBody, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets bodyOps nCond
        unless !rBody do
          throw <| .planInvariant .solana
            "typed Solana IR for-region body must not close every path (post-loop fallthrough)"
        -- Bound-check sequence is fixed: lit N, cmp_eq counter, bool_not, assert
        -- with loopBoundExceededError, lit 1, checked_add → counterNext.
        unless boundOps.size == 6 do
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check shape is invalid"
        let (nBound, rBound, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets boundOps nBody
        unless !rBound && counterNext < nBound && counterNext + 1 == nBound do
          throw <| .planInvariant .solana "typed Solana IR for-region counter rebind is invalid"
        let some op0 := boundOps[0]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op0"
        let some op1 := boundOps[1]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op1"
        let some op2 := boundOps[2]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op2"
        let some op3 := boundOps[3]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op3"
        let some op4 := boundOps[4]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op4"
        let some op5 := boundOps[5]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op5"
        match op0, op1, op2, op3, op4, op5 with
        | Operation.literal nLit nVal,
          Operation.compare eqT cT nT ComparisonOp.eq,
          Operation.boolNot okT eqSrc,
          Operation.assert okSrc errCode,
          Operation.literal oneLit oneVal,
          Operation.checkedAdd dest lhs rhs errAdd =>
            unless nLit + 1 == eqT && eqT + 1 == okT && okT + 1 == oneLit &&
                oneLit + 1 == dest && dest == counterNext do
              throw <| .planInvariant .solana
                "typed Solana IR for-region bound-check temps are not dense"
            unless nVal.toNat == maxIterations && nT == nLit && cT == counterTemp do
              throw <| .planInvariant .solana
                "typed Solana IR for-region bound compare is not counter == maxIterations"
            unless eqSrc == eqT && okSrc == okT &&
                errCode == plan.loopBoundExceededError do
              throw <| .planInvariant .solana
                "typed Solana IR for-region bound assert/error is invalid"
            unless oneVal == 1 && lhs == counterTemp && rhs == oneLit && dest == counterNext &&
                errAdd == plan.arithmeticOverflowError do
              throw <| .planInvariant .solana
                "typed Solana IR for-region counter increment is invalid"
        | _, _, _, _, _, _ =>
            throw <| .planInvariant .solana
              "typed Solana IR for-region bound-check opcodes are invalid"
        let (nUpd, rUpd, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets updateOps nBound
        unless !rUpd && update < nUpd do
          throw <| .planInvariant .solana "typed Solana IR for-region update is invalid"
        next := nUpd
  pure (next, returned, initialized)

private def validateHandlerIR (plan : Plan) (handler : HandlerIR) : CompileResult Unit := do
  let account := plan.stateAccount
  unless isIdentifier handler.name && validDiscriminator handler.discriminator do
    throw <| .planInvariant .solana "typed Solana IR has an invalid handler identity"
  validateParams s!"IR handler '{handler.name}'" handler.params
  unless handler.discriminator == instructionDiscriminator handler.name handler.params do
    throw <| .planInvariant .solana "typed Solana IR discriminator does not match its ABI signature"
  unless handler.accountAccess == expectedAccess account handler.mode do
    throw <| .planInvariant .solana "typed Solana IR account access is not canonical"
  let planHandler : Handler := {
    name := handler.name
    discriminator := handler.discriminator
    params := handler.params
    mode := handler.mode
    resultKind := handler.resultKind
    accountAccess := handler.accountAccess
    body := #[.returnValue (.literal 0)]
  }
  unless handler.checks == checksFor plan.instructionDiscriminatorBytes account planHandler do
    throw <| .planInvariant .solana "typed Solana IR checks are incomplete or out of order"
  let fieldOffsets := account.fields.map (·.byteOffset)
  let paramOffsets := handler.params.map (·.dataOffset)
  let (_, returned, initialized) ← validateOperationSequence
    plan handler fieldOffsets paramOffsets handler.operations 0
  if handler.mode == .initialize then
    unless initialized do
      throw <| .planInvariant .solana "initializer IR does not set the initialized marker"
  else unless returned do
    throw <| .planInvariant .solana "entry IR does not set return data"

private def validateFnIR (plan : Plan) (fn : FnIR) : CompileResult Unit := do
  unless isIdentifier fn.name do
    throw <| .planInvariant .solana "typed Solana IR has an invalid fn name"
  validateParams s!"IR fn '{fn.name}'" fn.params
  -- Synthetic view-mode handler so store/emit fail and setReturnData* is accepted.
  let resultKind : ResultKind := if fn.resultIsBool then .bool else .u64
  let synthetic : HandlerIR := {
    name := fn.name
    discriminator := instructionDiscriminator fn.name fn.params
    params := fn.params
    mode := .view
    resultKind
    accountAccess := accessFor plan.stateAccount .view
    checks := #[]
    operations := fn.operations
  }
  let fieldOffsets := plan.stateAccount.fields.map (·.byteOffset)
  let paramOffsets := fn.params.map (·.dataOffset)
  let (_, returned, _) ← validateOperationSequence
    plan synthetic fieldOffsets paramOffsets fn.operations 0
  unless returned do
    throw <| .planInvariant .solana s!"fn IR '{fn.name}' does not set return data"
  -- pureFn bodies must not load state (purity defense beyond view-mode write ban).
  for op in fn.operations do
    match op with
    | .loadState .. | .narrowLoadState .. | .storeState .. | .narrowStoreState ..
    | .zeroState .. | .narrowZeroState .. | .setHeader ..
    | .emitEvent .. =>
        throw <| .planInvariant .solana
          s!"fn IR '{fn.name}' contains a non-pure operation"
    | .ifRegion _ thenOps elseOps =>
        for nested in thenOps ++ elseOps do
          match nested with
          | .loadState .. | .narrowLoadState .. | .storeState .. | .narrowStoreState ..
          | .emitEvent .. =>
              throw <| .planInvariant .solana
                s!"fn IR '{fn.name}' contains a non-pure nested operation"
          | _ => pure ()
    | .switchRegion _ cases defaultOps =>
        let nestedOps := cases.foldl (fun acc (_, ops) => acc ++ ops) defaultOps
        for nested in nestedOps do
          match nested with
          | .loadState .. | .narrowLoadState .. | .storeState .. | .narrowStoreState ..
          | .emitEvent .. =>
              throw <| .planInvariant .solana
                s!"fn IR '{fn.name}' contains a non-pure nested operation"
          | _ => pure ()
    | .forRegion _ _ _ _ condOps _ bodyOps boundOps _ updateOps _ =>
        for nested in condOps ++ bodyOps ++ boundOps ++ updateOps do
          match nested with
          | .loadState .. | .narrowLoadState .. | .storeState .. | .narrowStoreState ..
          | .emitEvent .. =>
              throw <| .planInvariant .solana
                s!"fn IR '{fn.name}' contains a non-pure nested operation"
          | _ => pure ()
    | _ => pure ()

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName &&
      ir.stateAccount == ir.sourcePlan.stateAccount do
    throw <| .planInvariant .solana "typed Solana IR identity/layout is not bound to its source Plan"
  unless isIdentifier ir.name && ir.name.toUTF8.size <= maxArtifactStemBytes do
    throw <| .planInvariant .solana "typed Solana IR has an unsafe artifact name"
  validateStateAccount ir.stateAccount
  if ir.handlers.size < 2 || ir.handlers.size > maxEntries + 1 then
    throw <| .planInvariant .solana "typed Solana IR handler count is outside the profile limits"
  unless ir.handlers[0]!.mode == .initialize && ir.handlers[0]!.name == "initialize" do
    throw <| .planInvariant .solana "typed Solana IR must begin with the canonical initializer"
  for index in [1:ir.handlers.size] do
    if ir.handlers[index]!.mode == .initialize then
      throw <| .planInvariant .solana "typed Solana IR may contain only one initializer"
  if hasDuplicates (ir.handlers.map (·.name)) ||
      hasDuplicates (ir.handlers.map (·.discriminator)) then
    throw <| .planInvariant .solana "typed Solana IR handler identities must be unique"
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .solana "typed Solana IR fn count does not match its source Plan"
  if hasDuplicates (ir.fns.map (·.name)) then
    throw <| .planInvariant .solana "typed Solana IR fn names must be unique"
  let operationCount := ir.handlers.foldl (fun total handler =>
    total + handler.checks.size + handler.operations.size + handler.params.size) 0 +
    ir.fns.foldl (fun total fn => total + fn.operations.size + fn.params.size) 0
  if operationCount > maxPlanNodes then
    throw <| .planInvariant .solana "typed Solana IR exceeds the aggregate node limit"
  for fn in ir.fns do
    validateFnIR ir.sourcePlan fn
  for handler in ir.handlers do
    validateHandlerIR ir.sourcePlan handler
  let expectedFns := ir.sourcePlan.fns.map (lowerFn ir.sourcePlan)
  unless ir.fns == expectedFns do
    throw <| .planInvariant .solana "typed Solana IR fns are not the exact lowering of its source Plan"
  let expectedHandlers := #[lowerHandler ir.sourcePlan ir.sourcePlan.initializer] ++
    ir.sourcePlan.entries.map (lowerHandler ir.sourcePlan)
  unless ir.handlers == expectedHandlers do
    throw <| .planInvariant .solana "typed Solana IR operations are not the exact lowering of its source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let fns := plan.fns.map (lowerFn plan)
  let handlers := #[lowerHandler plan plan.initializer] ++
    plan.entries.map (lowerHandler plan)
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    stateAccount := plan.stateAccount
    fns
    handlers
  }
  validateIR ir
  return ir

private def renderMode : HandlerMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderInitialization : InitializationPolicy → String
  | .mustBeUninitialized => "uninitialized"
  | .mustBeInitialized => "initialized"

private def natHex (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def uint64Hex (value : UInt64) : String :=
  let raw := natHex value.toNat
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderCheck : Check → String
  | .instructionDataLen bytes => s!"  check instruction_data_len == {bytes}\n"
  | .ownerCurrentProgram accountIndex =>
      s!"  check account[{accountIndex}].owner == current_program\n"
  | .accountDataLen accountIndex bytes =>
      s!"  check account[{accountIndex}].data_len == {bytes}\n"
  | .signer accountIndex => s!"  check account[{accountIndex}].is_signer\n"
  | .writable accountIndex => s!"  check account[{accountIndex}].is_writable\n"
  | .headerEquals accountIndex byteOffset value =>
      s!"  check load_u64_le(account[{accountIndex}].data + {byteOffset}) == 0x{uint64Hex value}\n"

private def renderComparisonOp : ComparisonOp → String
  | .eq => "eq"
  | .ne => "ne"
  | .lt => "lt"
  | .le => "le"
  | .gt => "gt"
  | .ge => "ge"

/-- Plan-level declared-error program_error code base: declared error `i`
    traps with `0x{declaredErrorBase:x} + i`, disjoint from the arithmetic and
    assertion-failure policy codes. -/
def declaredErrorBase : Nat := 8192

private partial def renderOperation (indent : String)
    (fns : Array FnBinding) (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnReturnStyle : Bool) :
    Operation → String
  | .literal destination value => s!"{indent}%{destination} = const_u64 {value}\n"
  | .loadParam destination dataOffset =>
      s!"{indent}%{destination} = load_u64_le(instruction_data + {dataOffset})\n"
  | .narrowLoadParam bitWidth destination dataOffset =>
      s!"{indent}%{destination} = load_u{bitWidth}_le(instruction_data + {dataOffset})\n"
  | .loadState destination accountIndex byteOffset =>
      s!"{indent}%{destination} = load_u64_le(account[{accountIndex}].data + {byteOffset})\n"
  | .narrowLoadState bitWidth destination accountIndex byteOffset =>
      s!"{indent}%{destination} = load_u{bitWidth}_le(account[{accountIndex}].data + {byteOffset})\n"
  | .checkedAdd destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_add_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedSub destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_sub_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedMul destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_mul_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedDiv destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_div_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedMod destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_rem_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .signedCheckedAdd destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_add_i64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .signedCheckedSub destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_sub_i64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .signedCheckedMul destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_mul_i64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .signedCheckedDiv destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_div_i64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .signedCheckedMod destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_rem_i64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedNeg destination source errorCode =>
      s!"{indent}%{destination} = checked_neg_i64 %{source} else program_error 0x{natHex errorCode}\n"
  | .signedCompare destination lhs rhs op =>
      s!"{indent}%{destination} = cmp_{renderComparisonOp op}_i64 %{lhs}, %{rhs}\n"
  | .checkedSar destination lhs rhs shiftError =>
      s!"{indent}%{destination} = sar_i64 %{lhs}, %{rhs} else program_error 0x{natHex shiftError}\n"
  | .bitAnd destination lhs rhs =>
      s!"{indent}%{destination} = bitand_u64 %{lhs}, %{rhs}\n"
  | .bitOr destination lhs rhs =>
      s!"{indent}%{destination} = bitor_u64 %{lhs}, %{rhs}\n"
  | .bitXor destination lhs rhs =>
      s!"{indent}%{destination} = bitxor_u64 %{lhs}, %{rhs}\n"
  -- Shift guards: first else is invalidShift (count ≥ 64); for shl the second
  -- else is arithmeticOverflow when the mathematical result does not fit UInt64.
  | .checkedShl destination lhs rhs shiftError overflowError =>
      s!"{indent}%{destination} = shl_u64 %{lhs}, %{rhs} else program_error 0x{natHex shiftError} else program_error 0x{natHex overflowError}\n"
  | .checkedShr destination lhs rhs shiftError =>
      s!"{indent}%{destination} = shr_u64 %{lhs}, %{rhs} else program_error 0x{natHex shiftError}\n"
  | .bitNot destination source =>
      s!"{indent}%{destination} = bitnot_u64 %{source}\n"
  | .narrowCheckedAdd bitWidth destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_add_u{bitWidth} %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .narrowCheckedSub bitWidth destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_sub_u{bitWidth} %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .narrowCheckedMul bitWidth destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_mul_u{bitWidth} %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .narrowCheckedDiv bitWidth destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_div_u{bitWidth} %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .narrowCheckedMod bitWidth destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_rem_u{bitWidth} %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .narrowBitAnd bitWidth destination lhs rhs =>
      s!"{indent}%{destination} = bitand_u{bitWidth} %{lhs}, %{rhs}\n"
  | .narrowBitOr bitWidth destination lhs rhs =>
      s!"{indent}%{destination} = bitor_u{bitWidth} %{lhs}, %{rhs}\n"
  | .narrowBitXor bitWidth destination lhs rhs =>
      s!"{indent}%{destination} = bitxor_u{bitWidth} %{lhs}, %{rhs}\n"
  | .narrowBitNot bitWidth destination source =>
      s!"{indent}%{destination} = bitnot_u{bitWidth} %{source}\n"
  | .narrowCheckedShl bitWidth destination lhs rhs shiftError overflowError =>
      s!"{indent}%{destination} = shl_u{bitWidth} %{lhs}, %{rhs} else program_error 0x{natHex shiftError} else program_error 0x{natHex overflowError}\n"
  | .narrowCheckedShr bitWidth destination lhs rhs shiftError =>
      s!"{indent}%{destination} = shr_u{bitWidth} %{lhs}, %{rhs} else program_error 0x{natHex shiftError}\n"
  | .boolNot destination source =>
      s!"{indent}%{destination} = bool_not %{source}\n"
  | .boolAnd destination lhs rhs =>
      s!"{indent}%{destination} = bool_and %{lhs}, %{rhs}\n"
  | .boolOr destination lhs rhs =>
      s!"{indent}%{destination} = bool_or %{lhs}, %{rhs}\n"
  | .zeroState accountIndex byteOffset =>
      s!"{indent}zero_u64_le account[{accountIndex}].data + {byteOffset}\n"
  | .narrowZeroState bitWidth accountIndex byteOffset =>
      s!"{indent}zero_u{bitWidth}_le account[{accountIndex}].data + {byteOffset}\n"
  | .storeState accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, %{value}\n"
  | .narrowStoreState bitWidth accountIndex byteOffset value =>
      s!"{indent}store_u{bitWidth}_le account[{accountIndex}].data + {byteOffset}, %{value}\n"
  | .setHeader accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, 0x{uint64Hex value}\n"
  | .setReturnData value =>
      if fnReturnStyle then s!"{indent}ret %{value}\n"
      else s!"{indent}set_return_data_u64_le %{value}\n"
  | .setReturnDataBool value =>
      if fnReturnStyle then s!"{indent}ret %{value}\n"
      else s!"{indent}set_return_data_bool %{value}\n"
  | .compare destination lhs rhs op =>
      s!"{indent}%{destination} = cmp_{renderComparisonOp op}_u64 %{lhs}, %{rhs}\n"
  | .assert condition errorCode =>
      s!"{indent}assert %{condition} else program_error 0x{natHex errorCode}\n"
  | .returnNone =>
      s!"{indent}exit\n"
  | .emitEvent eventIndex args =>
      let argText := String.intercalate ", " (args.toList.map (fun a => s!"%{a}"))
      s!"{indent}emit_event {events[eventIndex]!.name} {argText}\n"
  | .revertError errorIndex args =>
      let argText := String.intercalate ", " (args.toList.map (fun a => s!"%{a}"))
      s!"{indent}program_error 0x{natHex (declaredErrorBase + errorIndex)} ; {errors[errorIndex]!.name}({argText})\n"
  | .callFn fnIndex destination args =>
      let name := fns[fnIndex]!.name
      let argText := String.intercalate ", " (args.toList.map (fun a => s!"%{a}"))
      if args.isEmpty then
        s!"{indent}%{destination} = call {name}\n"
      else
        s!"{indent}%{destination} = call {name} {argText}\n"
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
      let elseText := elseOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
      s!"{indent}if %{condition} \{\n" ++ thenText ++
        s!"{indent}} else \{\n" ++ elseText ++ s!"{indent}}\n"
  | .switchRegion scrutinee cases defaultOps =>
      let caseText := cases.foldl (fun output (caseValue, ops) =>
        let body := ops.foldl (fun inner operation =>
          inner ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
        output ++ s!"{indent}case {caseValue} \{\n" ++ body ++ s!"{indent}}\n") ""
      let defaultText := defaultOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
      s!"{indent}switch %{scrutinee} \{\n" ++ caseText ++
        s!"{indent}default \{\n" ++ defaultText ++ s!"{indent}}\n"
  | .forRegion varTemp initial counterTemp maxIterations condOps cond bodyOps
        boundOps counterNext updateOps update =>
      -- Structured loop_u64 form: induction + completed-iteration counter,
      -- then cond / body / bound (back-edge check) / update sections.
      -- Bound check matches reference noteBackEdge: after body N+1,
      -- counter == N ⇒ program_error 0x1003 (loopBoundExceededError); else
      -- counter := counter + 1. Latch i+1 overflow is unreachable under
      -- Normalize (i < end ≤ UInt64.max). Counter +1 is also safe (≤4096).
      let nested := indent ++ "  "
      let condText := condOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      let bodyText := bodyOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      let boundText := boundOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      let updateText := updateOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      s!"{indent}loop_u64 %{varTemp} = %{initial} counter=%{counterTemp} max={maxIterations}\n" ++
        s!"{indent}cond \{\n" ++ condText ++
          s!"{nested}; cond_temp %{cond}\n" ++ s!"{indent}}\n" ++
        s!"{indent}body \{\n" ++ bodyText ++ s!"{indent}}\n" ++
        s!"{indent}bound \{\n" ++ boundText ++
          s!"{nested}; counter_next %{counterNext}\n" ++ s!"{indent}}\n" ++
        s!"{indent}update \{\n" ++ updateText ++
          s!"{nested}; update_temp %{update}\n" ++ s!"{indent}}\n"

private def renderFnPlan (ir : IR) (index : Nat) (fn : FnIR) : String :=
  let result := if fn.resultIsBool then "bool" else "u64"
  let operations := fn.operations.foldl (fun output operation =>
    output ++ renderOperation "  " ir.sourcePlan.fns ir.sourcePlan.events
      ir.sourcePlan.errors true operation) ""
  s!".fn {index} {fn.name} (-> {result})\n" ++ operations ++ ".end-fn\n"

private def renderHandlerPlan (ir : IR) (handler : HandlerIR) : String :=
  let checks := handler.checks.foldl (fun output check => output ++ renderCheck check) ""
  let operations := handler.operations.foldl (fun output operation =>
    output ++ renderOperation "  " ir.sourcePlan.fns ir.sourcePlan.events
      ir.sourcePlan.errors false operation) ""
  s!".handler {handler.discriminator} {handler.name} mode={renderMode handler.mode}\n" ++
    checks ++ operations ++ ".end-handler\n"

private def renderPlanText (ir : IR) : String :=
  let account := ir.stateAccount
  let fields := account.fields.foldl (fun output field => output ++
    s!"; field source_id={field.sourceId} name={field.name} account={field.accountIndex} offset={field.byteOffset} type={layoutFieldTypeSuffix field.byteWidth}\n") ""
  let fnsText := Id.run do
    let mut text := ""
    for index in [0:ir.fns.size] do
      text := text ++ renderFnPlan ir index ir.fns[index]!
    pure text
  let handlers := ir.handlers.foldl (fun output handler =>
    output ++ renderHandlerPlan ir handler) ""
  "; PROOF-FORGE-SBPF-PLAN v1\n" ++
    "; PLAN-ONLY NON-EXECUTABLE: no sBPF instructions, object, or ELF are present\n" ++
    s!"; codegen-profile: {ir.sourcePlan.codegenProfile}\n" ++
    s!"; program: {ir.name}\n" ++
    s!"; state-account index={account.index} owner=current-program exact-data-len={account.exactDataLen}\n" ++
    s!"; header offset={account.headerOffset} type=u64-le initialized-marker=0x{uint64Hex account.initializedMarker} layout-domain={ir.sourcePlan.stateLayoutDomain}\n" ++
    "; initializer-payload-policy: zero-all-fields\n" ++
    fields ++ fnsText ++ handlers

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"{abiParamTypeString param}\",\"dataOffset\":{param.dataOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StateField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"offset\":{field.byteOffset},\"type\":\"{layoutFieldTypeSuffix field.byteWidth}\"}"

private def renderHandlerJson (handler : HandlerIR) : String :=
  let access := handler.accountAccess
  let signer := if access.signerRequired then "true" else "false"
  let writable := if access.writableRequired then "true" else "false"
  let returns :=
    if handler.mode == .initialize then "null"
    else match handler.resultKind with
      | .u64 => "\"u64-le\""
      | .i64 => "\"i64-le\""
      | .bool => "\"bool\""
  "{" ++
    s!"\"name\":\"{Targets.escapeJson handler.name}\"," ++
    s!"\"discriminator\":\"{handler.discriminator}\"," ++
    s!"\"mode\":\"{renderMode handler.mode}\"," ++
    "\"accounts\":[{" ++
    s!"\"name\":\"state\",\"index\":{access.accountIndex}," ++
    "\"owner\":\"current-program\"," ++
    s!"\"isSigner\":{signer},\"isWritable\":{writable}," ++
    s!"\"initialization\":\"{renderInitialization access.initialization}\"" ++
    "}]," ++
    s!"\"args\":[{renderParamsJson handler.params}],\"returns\":{returns}" ++
    "}"

private def renderInterfaceBindingJson (binding : InterfaceBinding) : String :=
  "{\"name\":\"" ++ Targets.escapeJson binding.name ++
    "\",\"args\":[" ++
    String.intercalate "," ((List.range binding.fieldCount).map fun _ => "\"u64-le\"") ++
    "]}"

private def renderFnJson (fn : FnIR) : String :=
  let result := if fn.resultIsBool then "bool" else "u64"
  "{" ++
    s!"\"name\":\"{Targets.escapeJson fn.name}\"," ++
    s!"\"argCount\":{fn.params.size}," ++
    s!"\"result\":\"{result}\"" ++
    "}"

private def renderIdl (capability : ResolvedEngineeringBuildV1) (ir : IR) : String :=
  let account := ir.stateAccount
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  -- The IDL describes the emitted wire format; deployability follows the
  -- selected profile (elf profile finalizes a real .so, plan profile does not).
  let deployable := profile == CodegenProfileId.solanaSbpfElfV1
  let fields := String.intercalate "," (account.fields.toList.map renderFieldJson)
  let handlers := String.intercalate ",\n    " (ir.handlers.toList.map renderHandlerJson)
  let events := String.intercalate "," (ir.sourcePlan.events.toList.map renderInterfaceBindingJson)
  let errors := String.intercalate "," (ir.sourcePlan.errors.toList.map renderInterfaceBindingJson)
  let fns := String.intercalate "," (ir.fns.toList.map renderFnJson)
  "{\n" ++
    "  \"version\": \"proof-forge-solana-idl/v1\",\n" ++
    s!"  \"name\": \"{Targets.escapeJson ir.name}\",\n" ++
    s!"  \"codegenProfile\": \"{profile}\",\n" ++
    s!"  \"deployable\": {if deployable then "true" else "false"},\n" ++
    "  \"instructionEncoding\": {" ++
    s!"\"discriminator\":\"sha256-prefix-{ir.sourcePlan.instructionDiscriminatorBytes}\"," ++
    s!"\"domain\":\"{ir.sourcePlan.instructionDiscriminatorDomain}\"," ++
    "\"arguments\":\"packed-u64-le\",\"trailingBytes\":\"reject\"},\n" ++
    "  \"accounts\": [{" ++
    s!"\"name\":\"state\",\"index\":{account.index}," ++
    "\"owner\":\"current-program\"," ++
    s!"\"exactDataLen\":{account.exactDataLen}," ++
    s!"\"header\":\{\"offset\":{account.headerOffset},\"type\":\"u64-le\",\"initializedMarker\":\"0x{uint64Hex account.initializedMarker}\",\"layoutDomain\":\"{ir.sourcePlan.stateLayoutDomain}\"}," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "}],\n" ++
    "  \"instructions\": [\n    " ++ handlers ++ "\n  ],\n" ++
    s!"  \"fns\": [{fns}],\n" ++
    s!"  \"events\": [{events}],\n" ++
    s!"  \"errors\": [{errors}]\n" ++
    "}\n"

/-- Plan-profile product files: `.sbpf-plan` + IDL only (non-deployable audit).
    Capability-gated (mandatory first binder) so residual IR→files scans stay
    closed; used by `buildFromCapability` in EmitSbpfAsmV1 without a circular
    import on `emitSbpfAsmV1`. -/
def emitPlanAndIdlFromIR
    (capability : ResolvedEngineeringBuildV1) (ir : IR) :
    CompileResult (Array OutputFile) := do
  validateIR ir
  pure #[
    {
      path := s!"{ir.name}.sbpf-plan"
      mediaType := "application/vnd.proof-forge.sbpf-plan"
      contents := renderPlanText ir
    },
    {
      path := s!"{ir.name}.idl.json"
      mediaType := "application/json"
      contents := renderIdl capability ir
    }
  ]

/-- Replace handlers on an existing IR (private `mk`; for validateIR characterization). -/
def withHandlers (ir : IR) (handlers : Array HandlerIR) : IR :=
  { ir with handlers }

/-- Replace pureFn IR table (private `mk`; for validateIR characterization). -/
def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }


/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files.
    Not a residual Plan→IR bypass. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

end ProofForgeV2.Targets.Solana
