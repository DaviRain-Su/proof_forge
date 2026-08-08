import ProofForgeV2.Targets.Psy.LowerSemanticV1

/-!
# Psy ValidatePlanV1 — plan canonicity

Validates the public `Psy.Plan` value before DPN package / transitional `.psy`
artifacts are produced (PSY-DPN-7 dual-write).
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

private def maxFunctions : Nat := 256
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256

/-- Conservative Psy reserved identifiers (dargo is the final authority). -/
private def reservedPsyWords : Array String :=
  #[ "struct", "impl", "fn", "let", "mut", "if", "else", "for", "return",
     "assert", "assert_eq", "abort", "true", "false", "pub", "priv",
     "Felt", "bool", "u32", "u8", "u128", "Map", "as", "in", "contract",
     "contract_method", "test", "derive", "Storage", "ContractMetadata",
     "ref" ]

private def isReserved (name : String) : Bool :=
  reservedPsyWords.contains name

private def validateExprNodes (expr : Expr) : Option Nat :=
  match expr with
  | .literal _ | .u32Literal _ | .boolLiteral _ | .fieldLiteral _
  | .param _ | .loopVar _ | .stateLoad _ | .wideUintMulLimb _ _ _
  | .wideUintDivModLimb _ _ _ _ | .wideUintShiftLimb _ _ _ _ => some 1
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .logicalAnd l r | .logicalOr l r | .shl l r | .shr l r
  | .limbAdd l r | .limbSub l r
  | .narrowCheckedAdd _ l r | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r
  | .narrowCheckedDiv _ l r | .narrowCheckedMod _ l r
  | .narrowBitAnd _ l r | .narrowBitOr _ l r | .narrowBitXor _ l r
  | .narrowShl _ l r | .narrowShr _ l r
  | .narrowSignedCheckedAdd _ l r | .narrowSignedCheckedSub _ l r
  | .narrowSignedCheckedMul _ l r | .narrowSignedCheckedDiv _ l r
  | .narrowSignedCheckedMod _ l r
  | .fieldBinary _ l r | .fieldCompare _ l r => do
      let dl ← validateExprNodes l
      let dr ← validateExprNodes r
      if dl + dr + 1 > maxExprDepth then none else some (dl + dr + 1)
  | .compare _ l r | .signedCompare _ l r | .narrowSignedCompare _ _ l r => do
      let dl ← validateExprNodes l
      let dr ← validateExprNodes r
      if dl + dr + 1 > maxExprDepth then none else some (dl + dr + 1)
  | .boolNot o | .checkedNeg o | .narrowBitNot _ o | .checkedBitNot o
  | .narrowCheckedNeg _ o | .fieldNeg o => do
      let do' ← validateExprNodes o
      if do' + 1 > maxExprDepth then none else some (do' + 1)
  | .select condition thenValue elseValue => do
      let dc ← validateExprNodes condition
      let dt ← validateExprNodes thenValue
      let de ← validateExprNodes elseValue
      if dc + dt + de + 1 > maxExprDepth then none else some (dc + dt + de + 1)
  | .callFn _ args => do
      let mut total : Nat := 1
      for arg in args do
        let da ← validateExprNodes arg
        total := total + da
      if total > maxExprDepth then none else some total

private partial def validateStatements (stmts : Array Statement) : CompileResult Unit := do
  if stmts.size > maxBodyStatements then
    planError "Psy function body exceeds the statement limit"
  for stmt in stmts do
    match stmt with
    | .store _ value | .returnValue value => do
        match validateExprNodes value with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
    | .storeAggregate fieldIndices values => do
        unless fieldIndices.size > 1 && fieldIndices.size == values.size do
          planError "Psy storeAggregate requires matching multi-leaf field/value arrays"
        for value in values do
          match validateExprNodes value with
          | some _ => pure ()
          | none => planError "Psy plan expression exceeds the depth/node limit"
    | .bindWideUintMul bitWidth _ lhs rhs => do
        let need := bitWidth / 32
        unless (bitWidth == 128 || bitWidth == 256) &&
            lhs.size == need && rhs.size == need do
          planError "Psy bindWideUintMul requires matching wide limb operands"
        for value in lhs ++ rhs do
          match validateExprNodes value with
          | some _ => pure ()
          | none => planError "Psy plan expression exceeds the depth/node limit"
    | .bindWideUintDivMod _ bitWidth _ lhs rhs => do
        let need := bitWidth / 32
        unless (bitWidth == 128 || bitWidth == 256) &&
            lhs.size == need && rhs.size == need do
          planError "Psy bindWideUintDivMod requires matching wide limb operands"
        for value in lhs ++ rhs do
          match validateExprNodes value with
          | some _ => pure ()
          | none => planError "Psy plan expression exceeds the depth/node limit"
    | .bindWideUintShift _ bitWidth _ value count => do
        let need := bitWidth / 32
        unless (bitWidth == 128 || bitWidth == 256) && value.size == need do
          planError "Psy bindWideUintShift requires matching wide value limbs"
        for limb in value do
          match validateExprNodes limb with
          | some _ => pure ()
          | none => planError "Psy plan expression exceeds the depth/node limit"
        match validateExprNodes count with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
    | .returnAggregate leaves leafIsInt => do
        -- B-RET-ABI: 1..8 leaves, UInt64/Int64 words only (byteWidth checked on ResultKind).
        unless leaves.size > 0 && leaves.size ≤ 8 do
          planError "Psy returnAggregate leaf count must be in 1..8 (B-RET-ABI)"
        unless leafIsInt.size == leaves.size do
          planError "Psy returnAggregate leafIsInt length must match leaves"
        for leaf in leaves do
          match validateExprNodes leaf with
          | some _ => pure ()
          | none => planError "Psy plan expression exceeds the depth/node limit"
    | .returnNone | .bareRevert => pure ()
    | .assert condition | .assertWithMessage condition _ => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
    | .ifThenElse condition thenBody elseBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
        validateStatements thenBody
        validateStatements elseBody
    | .switchOn condition cases defaultBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
        for (_, caseBody) in cases do
          validateStatements caseBody
        validateStatements defaultBody
    | .forLoop start endExclusive _ body => do
        match validateExprNodes start, validateExprNodes endExclusive with
        | some _, some _ => pure ()
        | _, _ => planError "Psy plan expression exceeds the depth/node limit"
        validateStatements body
    | .emitEvent _ args | .externalCall _ args | .schedule _ args => do
        for arg in args do
          match validateExprNodes arg with
          | some _ => pure ()
          | none => planError "Psy plan expression exceeds the depth/node limit"
    | .revertError _ args =>
        unless args.isEmpty do
          planError "unsupported Psy semantic shape: revert with error arguments cannot be expressed on the Psy surface"

private def maxWideUInt128MulBindings : Nat := 4
private def maxWideUInt128DivModBindings : Nat := 1
private def maxWideUInt128ShiftBindings : Nat := 4

private structure WideBindingEnvV1 where
  mulIds : Array Nat := #[]
  divModIds : Array (Nat × WideUInt128DivModResultV1) := #[]
  shiftIds : Array (Nat × WideUInt128ShiftKindV1) := #[]
  deriving Inhabited

private def hasAnyWideBindingId (env : WideBindingEnvV1) (operationId : Nat) : Bool :=
  env.mulIds.contains operationId ||
    env.divModIds.any (fun binding => binding.1 == operationId) ||
    env.shiftIds.any (fun binding => binding.1 == operationId)

private partial def validateWideExpr
    (defined : WideBindingEnvV1) (expr : Expr) : CompileResult Unit := do
  match expr with
  | .literal _ | .u32Literal _ | .boolLiteral _ | .fieldLiteral _
  | .param _ | .loopVar _ | .stateLoad _ => pure ()
  | .wideUintMulLimb bitWidth operationId limbIndex =>
      unless bitWidth == 128 || bitWidth == 256 do
        planError "Psy wide multiplication bitWidth must be 128 or 256"
      unless limbIndex < bitWidth / 32 do
        planError "Psy wide multiplication result limb index is out of range"
      unless defined.mulIds.contains operationId do
        planError "Psy wide multiplication result is used before its binding"
  | .wideUintDivModLimb resultKind bitWidth operationId limbIndex =>
      unless bitWidth == 128 || bitWidth == 256 do
        planError "Psy wide div/mod bitWidth must be 128 or 256"
      unless limbIndex < bitWidth / 32 do
        planError "Psy wide div/mod result limb index is out of range"
      unless defined.divModIds.contains (operationId, resultKind) do
        planError "Psy wide div/mod result kind is mismatched or used before its binding"
  | .wideUintShiftLimb kind bitWidth operationId limbIndex =>
      unless bitWidth == 128 || bitWidth == 256 do
        planError "Psy wide shift bitWidth must be 128 or 256"
      unless limbIndex < bitWidth / 32 do
        planError "Psy wide shift result limb index is out of range"
      unless defined.shiftIds.contains (operationId, kind) do
        planError "Psy wide shift result kind is mismatched or used before its binding"
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .logicalAnd l r | .logicalOr l r | .shl l r | .shr l r
  | .limbAdd l r | .limbSub l r
  | .narrowCheckedAdd _ l r | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r
  | .narrowCheckedDiv _ l r | .narrowCheckedMod _ l r
  | .narrowBitAnd _ l r | .narrowBitOr _ l r | .narrowBitXor _ l r
  | .narrowShl _ l r | .narrowShr _ l r
  | .narrowSignedCheckedAdd _ l r | .narrowSignedCheckedSub _ l r
  | .narrowSignedCheckedMul _ l r | .narrowSignedCheckedDiv _ l r
  | .narrowSignedCheckedMod _ l r
  | .compare _ l r | .signedCompare _ l r | .narrowSignedCompare _ _ l r
  | .fieldBinary _ l r | .fieldCompare _ l r => do
      validateWideExpr defined l
      validateWideExpr defined r
  | .boolNot o | .checkedNeg o | .narrowBitNot _ o | .checkedBitNot o
  | .narrowCheckedNeg _ o | .fieldNeg o =>
      validateWideExpr defined o
  | .select condition thenValue elseValue => do
      validateWideExpr defined condition
      validateWideExpr defined thenValue
      validateWideExpr defined elseValue
  | .callFn _ args =>
      for arg in args do
        validateWideExpr defined arg

private structure WideBindingInventoryV1 where
  ids : Array Nat := #[]
  mulCount : Nat := 0
  divModCount : Nat := 0
  shiftCount : Nat := 0
  deriving Inhabited

private def appendWideInventory
    (left right : WideBindingInventoryV1) : WideBindingInventoryV1 := {
  ids := left.ids ++ right.ids
  mulCount := left.mulCount + right.mulCount
  divModCount := left.divModCount + right.divModCount
  shiftCount := left.shiftCount + right.shiftCount
}

private partial def collectWideBindingInventory
    (stmts : Array Statement) : WideBindingInventoryV1 := Id.run do
  let mut out : WideBindingInventoryV1 := {}
  for stmt in stmts do
    match stmt with
    | .bindWideUintMul _ operationId _ _ =>
        out := { out with ids := out.ids.push operationId, mulCount := out.mulCount + 1 }
    | .bindWideUintDivMod _ _ operationId _ _ =>
        out := { out with ids := out.ids.push operationId, divModCount := out.divModCount + 1 }
    | .bindWideUintShift _ _ operationId _ _ =>
        out := { out with ids := out.ids.push operationId, shiftCount := out.shiftCount + 1 }
    | .ifThenElse _ thenBody elseBody =>
        out := appendWideInventory out (collectWideBindingInventory thenBody)
        out := appendWideInventory out (collectWideBindingInventory elseBody)
    | .switchOn _ cases defaultBody =>
        for (_, body) in cases do
          out := appendWideInventory out (collectWideBindingInventory body)
        out := appendWideInventory out (collectWideBindingInventory defaultBody)
    | .forLoop _ _ _ body =>
        out := appendWideInventory out (collectWideBindingInventory body)
    | _ => pure ()
  pure out

private partial def validateWideBindings
    (profileMode : PsyProfileModeV1) (loopDepth : Nat)
    (defined0 : WideBindingEnvV1) (stmts : Array Statement) :
    CompileResult WideBindingEnvV1 := do
  let mut defined := defined0
  for stmt in stmts do
    match stmt with
    | .bindWideUintMul bitWidth operationId lhs rhs => do
        unless profileMode == .dargo010Vm do
          planError "Psy wide multiplication requires profile psy-dargo-0.1.0-vm-v1"
        unless bitWidth == 128 || bitWidth == 256 do
          planError "Psy wide multiplication bitWidth must be 128 or 256"
        let need := bitWidth / 32
        unless lhs.size == need && rhs.size == need do
          planError s!"Psy bindWideUintMul requires two {need}-limb operands"
        unless !hasAnyWideBindingId defined operationId do
          planError "Psy wide operation binding id is duplicated in one lexical region"
        for value in lhs ++ rhs do
          validateWideExpr defined value
        defined := { defined with mulIds := defined.mulIds.push operationId }
    | .bindWideUintDivMod resultKind bitWidth operationId lhs rhs => do
        unless profileMode == .dargo010Vm do
          planError "Psy wide div/mod requires profile psy-dargo-0.1.0-vm-v1"
        unless loopDepth == 0 do
          planError "Psy wide div/mod inside a bounded loop exceeds the frozen resource profile"
        unless bitWidth == 128 || bitWidth == 256 do
          planError "Psy wide div/mod bitWidth must be 128 or 256"
        let need := bitWidth / 32
        unless lhs.size == need && rhs.size == need do
          planError s!"Psy bindWideUintDivMod requires two {need}-limb operands"
        unless !hasAnyWideBindingId defined operationId do
          planError "Psy wide operation binding id is duplicated in one lexical region"
        for value in lhs ++ rhs do
          validateWideExpr defined value
        defined := { defined with
          divModIds := defined.divModIds.push (operationId, resultKind) }
    | .bindWideUintShift kind bitWidth operationId value count => do
        unless profileMode == .dargo010Vm do
          planError "Psy wide shift requires profile psy-dargo-0.1.0-vm-v1"
        unless loopDepth == 0 do
          planError "Psy wide shift inside a bounded loop exceeds the frozen resource profile"
        unless bitWidth == 128 || bitWidth == 256 do
          planError "Psy wide shift bitWidth must be 128 or 256"
        let need := bitWidth / 32
        unless value.size == need do
          planError s!"Psy bindWideUintShift requires {need} value limbs"
        unless !hasAnyWideBindingId defined operationId do
          planError "Psy wide operation binding id is duplicated in one lexical region"
        for limb in value do
          validateWideExpr defined limb
        validateWideExpr defined count
        defined := { defined with
          shiftIds := defined.shiftIds.push (operationId, kind) }
    | .store _ value | .returnValue value | .assert value
    | .assertWithMessage value _ =>
        validateWideExpr defined value
    | .storeAggregate _ values | .returnAggregate values _ =>
        for value in values do
          validateWideExpr defined value
    | .ifThenElse condition thenBody elseBody => do
        validateWideExpr defined condition
        let _ ← validateWideBindings profileMode loopDepth defined thenBody
        let _ ← validateWideBindings profileMode loopDepth defined elseBody
    | .switchOn scrutinee cases defaultBody => do
        validateWideExpr defined scrutinee
        for (_, body) in cases do
          let _ ← validateWideBindings profileMode loopDepth defined body
        let _ ← validateWideBindings profileMode loopDepth defined defaultBody
    | .forLoop start endExclusive _ body => do
        validateWideExpr defined start
        validateWideExpr defined endExclusive
        let _ ← validateWideBindings profileMode (loopDepth + 1) defined body
    | .emitEvent _ args | .revertError _ args | .externalCall _ args
    | .schedule _ args =>
        for arg in args do
          validateWideExpr defined arg
    | .returnNone | .bareRevert => pure ()
  pure defined

private def validateWideFunction
    (profileMode : PsyProfileModeV1) (stmts : Array Statement) : CompileResult Unit := do
  let inventory := collectWideBindingInventory stmts
  unless inventory.mulCount ≤ maxWideUInt128MulBindings do
    planError s!"Psy function exceeds the UInt128 multiplication binding limit ({maxWideUInt128MulBindings})"
  unless inventory.divModCount ≤ maxWideUInt128DivModBindings do
    planError s!"Psy function exceeds the UInt128 div/mod binding limit ({maxWideUInt128DivModBindings})"
  unless inventory.shiftCount ≤ maxWideUInt128ShiftBindings do
    planError s!"Psy function exceeds the UInt128 shift binding limit ({maxWideUInt128ShiftBindings})"
  let mut seen : Array Nat := #[]
  for operationId in inventory.ids do
    if seen.contains operationId then
      planError "Psy wide operation binding id must be unique within a function"
    seen := seen.push operationId
  let _ ← validateWideBindings profileMode 0 {} stmts
  pure ()

/-- B-RET-ABI depth defense: return form must match resultKind; aggregate
    leaves are 1..8 × 8-byte UInt64/Int64 words only. -/
private partial def checkReturnFormsV1
    (fnName : String) (resultKind : ResultKind)
    (stmts : Array Statement) : CompileResult Unit := do
  for s in stmts do
    match s with
    | .returnValue _ =>
        match resultKind with
        | .aggregate _ =>
            planError s!"function '{fnName}' aggregate resultKind must use returnAggregate, not returnValue"
        | _ => pure ()
    | .returnAggregate leaves leafIsInt =>
        match resultKind with
        | .aggregate expected =>
            unless leaves.size == expected.size && leafIsInt.size == expected.size do
              planError s!"function '{fnName}' returnAggregate leaf count mismatch"
            for i in [0:expected.size] do
              let some exp := expected[i]? |
                planError "returnAggregate expected leaf missing"
              let some gotInt := leafIsInt[i]? |
                planError "returnAggregate leafIsInt missing"
              unless exp.byteWidth == 1 || exp.byteWidth == 4 || exp.byteWidth == 8 do
                planError s!"function '{fnName}' aggregate leaf {i} must be a 1-byte Bytes UInt8, 4-byte UInt32 limb, or 8-byte UInt64/Int64 word"
              if exp.byteWidth == 4 && exp.isInt then
                planError s!"function '{fnName}' UInt128 ABI limb {i} must be unsigned"
              if exp.byteWidth == 1 && exp.isInt then
                planError s!"function '{fnName}' Bytes ABI leaf {i} must be unsigned UInt8"
              unless gotInt == exp.isInt do
                planError s!"function '{fnName}' returnAggregate leaf {i} isInt mismatch"
        | _ =>
            planError s!"function '{fnName}' returnAggregate requires an aggregate resultKind"
    | .ifThenElse _ t e =>
        checkReturnFormsV1 fnName resultKind t
        checkReturnFormsV1 fnName resultKind e
    | .switchOn _ cases defaultBody =>
        for (_, body) in cases do
          checkReturnFormsV1 fnName resultKind body
        checkReturnFormsV1 fnName resultKind defaultBody
    | .forLoop _ _ _ body =>
        checkReturnFormsV1 fnName resultKind body
    | _ => pure ()

private def validateResultKind
    (profileMode : PsyProfileModeV1) (fn : PlanFunction) : CompileResult Unit := do
  match fn.resultKind with
  | .felt | .bool | .unit => pure ()
  | .aggregate leaves =>
      unless leaves.size > 0 && leaves.size ≤ 8 do
        planError s!"function '{fn.name}' aggregate resultKind leaf count must be in 1..8 (B-RET-ABI)"
      let isWideUintAbi :=
        (leaves.size == 4 || leaves.size == 8) &&
          leaves.all (fun leaf => !leaf.isInt && leaf.byteWidth == 4)
      let isBytesAbi :=
        leaves.size ≥ 1 && leaves.size ≤ 8 &&
          leaves.all (fun leaf => !leaf.isInt && leaf.byteWidth == 1)
      if isWideUintAbi then
        unless profileMode == .dargo010Vm do
          planError s!"function '{fn.name}' wide UInt aggregate ABI requires profile psy-dargo-0.1.0-vm-v1"
        let expectedWidth := leaves.size * 32
        unless fn.resultUintWidth == expectedWidth do
          planError s!"function '{fn.name}' UInt{expectedWidth} aggregate ABI must carry resultUintWidth={expectedWidth}"
      else if isBytesAbi then
        pure ()
      else
        for leaf in leaves do
          unless leaf.byteWidth == 8 do
            planError s!"function '{fn.name}' non-wide aggregate leaves must be 8-byte UInt64/Int64 words or 1-byte Bytes"
      -- pureFn aggregate stays fail closed even if a hand-built plan slips through.
      if fn.kind == .pureHelper then
        planError s!"pureFn '{fn.name}' cannot carry an aggregate resultKind"
      if fn.resultIsBool || fn.resultIsUnit || isNarrowUintWidth fn.resultUintWidth then
        planError s!"function '{fn.name}' aggregate resultKind conflicts with scalar result flags"

def validatePlan (plan : Plan) : CompileResult Unit := do
  if plan.functions.size > maxFunctions then
    planError "Psy plan exceeds the function limit"
  if plan.stateFieldNames.size > maxParams then
    planError "Psy plan exceeds the state field limit"
  for name in plan.stateFieldNames do
    if isReserved name then
      planError s!"Psy state identifier '{name}' collides with a reserved Psy word"
  for fn in plan.functions do
    if isReserved fn.name then
      planError s!"Psy identifier '{fn.name}' collides with a reserved Psy word"
    if fn.params.size > maxParams then
      planError "Psy plan function exceeds the parameter limit"
    for param in fn.params do
      if isReserved param.name then
        planError s!"Psy parameter '{param.name}' collides with a reserved Psy word"
    validateResultKind plan.profileMode fn
    validateStatements fn.body
    validateWideFunction plan.profileMode fn.body
    checkReturnFormsV1 fn.name fn.resultKind fn.body
  for ev in plan.events do
    if isReserved ev.name then
      planError s!"Psy event identifier '{ev.name}' collides with a reserved Psy word"
  pure ()

end ProofForgeV2.Targets.Psy
