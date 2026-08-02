import ProofForgeV2.Targets.Evm.LowerSemanticV1

/-!
# Evm ValidatePlanV1 — plan canonicity

Validates the public `Evm.Plan` value before any Yul is produced.
-/

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

private partial def planExprNodes? (slots : Array Nat) (paramCount depthLeft nodeBudget : Nat)
    (fns : Array FnBinding) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. | .bigLiteral .. => some 1
    | .param wordIndex => if wordIndex < paramCount then some 1 else none
    | .narrowParam bitWidth wordIndex =>
        if isEvmAbiUintWidth bitWidth && bitWidth != 64 && wordIndex < paramCount then
          some 1
        else none
    | .temp _ => some 1
    | .storageLoad slot | .fieldStorageLoad slot =>
        if slots.contains slot then some 1 else none
    | .narrowStorageLoad bitWidth slot =>
        if isEvmAbiUintWidth bitWidth && bitWidth != 64 && slots.contains slot then
          some 1
        else none
    | .indexedStorageLoad baseSlot length index byteWidth =>
        -- Contiguous range baseSlot .. baseSlot+length-1 must all be planned
        -- slots; length ≥ 1; byteWidth ∈ {1,2,4,8,16,32}.
        if length == 0 then none
        else if !(byteWidth == 1 || byteWidth == 2 || byteWidth == 4 || byteWidth == 8 ||
            byteWidth == 16 || byteWidth == 32) then
          none
        else
          let rangeOk := Id.run do
            let mut ok := true
            for i in [0:length] do
              unless slots.contains (baseSlot + i) do ok := false
            pure ok
          if !rangeOk then none
          else
            let childDepth := depthLeft - 1
            let available := nodeBudget - 1
            match planExprNodes? slots paramCount childDepth available fns index with
            | none => none
            | some nodes => some (1 + nodes)
    | .boundsCheckedIndex index length =>
        if length == 0 then none
        else
          let childDepth := depthLeft - 1
          let available := nodeBudget - 1
          match planExprNodes? slots paramCount childDepth available fns index with
          | none => none
          | some nodes => some (1 + nodes)
    | .arrayIndexGet index leaves =>
        if leaves.isEmpty then none
        else
          let childDepth := depthLeft - 1
          Id.run do
            let mut available := nodeBudget - 1
            let mut total : Nat := 1
            let mut ok := true
            match planExprNodes? slots paramCount childDepth available fns index with
            | none => ok := false
            | some nodes =>
                total := total + nodes
                available := available - nodes
            if ok then
              for leaf in leaves do
                match planExprNodes? slots paramCount childDepth available fns leaf with
                | none => ok := false
                | some nodes =>
                    total := total + nodes
                    available := available - nodes
            if ok then some total else none
    | .checkedAdd lhs rhs | .narrowCheckedAdd _ lhs rhs
    | .add lhs rhs
    | .checkedSub lhs rhs | .narrowCheckedSub _ lhs rhs
    | .compare _ lhs rhs
    | .signedCompare _ lhs rhs
    | .narrowSignedCompare _ _ lhs rhs
    | .checkedMul lhs rhs | .narrowCheckedMul _ lhs rhs
    | .checkedDiv lhs rhs | .narrowCheckedDiv _ lhs rhs
    | .checkedMod lhs rhs | .narrowCheckedMod _ lhs rhs
    | .signedCheckedAdd lhs rhs | .signedCheckedSub lhs rhs
    | .signedCheckedMul lhs rhs | .signedCheckedDiv lhs rhs
    | .signedCheckedMod lhs rhs
    | .narrowSignedCheckedAdd _ lhs rhs | .narrowSignedCheckedSub _ lhs rhs
    | .narrowSignedCheckedMul _ lhs rhs | .narrowSignedCheckedDiv _ lhs rhs
    | .narrowSignedCheckedMod _ lhs rhs
    | .bitAnd lhs rhs | .narrowBitAnd _ lhs rhs
    | .bitOr lhs rhs | .narrowBitOr _ lhs rhs
    | .bitXor lhs rhs | .narrowBitXor _ lhs rhs
    | .shl lhs rhs | .narrowShl _ lhs rhs
    | .shr lhs rhs | .narrowShr _ lhs rhs
    | .sar lhs rhs | .narrowSar _ lhs rhs
    | .logicalAnd lhs rhs | .logicalOr lhs rhs
    | .fieldAdd lhs rhs | .fieldSub lhs rhs
    | .fieldMul lhs rhs | .fieldDiv lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available fns lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) fns rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .bitNot operand | .narrowBitNot _ operand | .boolNot operand
    | .checkedNeg operand | .narrowCheckedNeg _ operand | .fieldNeg operand =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available fns operand with
        | none => none
        | some nodes => some (1 + nodes)
    | .callFn fnIndex args =>
        match fns[fnIndex]? with
        | none => none
        | some binding =>
            if args.size != binding.params.size then
              none
            else
              -- Args must be UInt64-compatible (no compare / boolNot / logical /
              -- Bool-returning callFn).
              let argsOk := args.all fun arg =>
                match arg with
                | .compare .. => false
                | .boolNot .. => false
                | .logicalAnd .. => false
                | .logicalOr .. => false
                | .callFn nestedIdx _ =>
                    match fns[nestedIdx]? with
                    | some nested => !nested.resultIsBool
                    | none => false
                | _ => true
              if !argsOk then
                none
              else
                let childDepth := depthLeft - 1
                Id.run do
                  let mut available := nodeBudget - 1
                  let mut total : Nat := 1
                  let mut ok := true
                  for arg in args do
                    match planExprNodes? slots paramCount childDepth available fns arg with
                    | none => ok := false
                    | some nodes =>
                        total := total + nodes
                        available := available - nodes
                  if ok then some total else none

private def addPlanExprNodes (slots : Array Nat) (paramCount total : Nat)
    (fns : Array FnBinding) (expr : Expr) : CompileResult Nat := do
  if total >= maxPlanNodes then
    throw <| .planInvariant .evm s!"plan exceeds aggregate node limit {maxPlanNodes}"
  match planExprNodes? slots paramCount maxExprDepth (maxPlanNodes - total) fns expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .evm
        s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

private def validAbiByteWidth (byteWidth : Nat) : Bool :=
  byteWidth == 1 || byteWidth == 2 || byteWidth == 4 || byteWidth == 8 ||
    byteWidth == 16 || byteWidth == 32

private def addPlanStoreNodes (slots : Array Nat) (paramCount total : Nat)
    (fns : Array FnBinding) (store : Store) : CompileResult Nat := do
  unless slots.contains store.slot do
    throw <| .planInvariant .evm "plan store references an unknown storage slot"
  unless validAbiByteWidth store.byteWidth do
    throw <| .planInvariant .evm
      s!"plan store byteWidth {store.byteWidth} is not an admitted ABI width"
  addPlanExprNodes slots paramCount total fns store.value

/-- Structural Bool-producer: comparison and strict logical ops are always Bool.
    Bool literals are surface-encoded as `.literal 0`/`.literal 1` and are
    accepted only where a Bool kind is required (return/assert). callFn uses
    the callee result flag. -/
private def exprIsCompareV1 : Expr → Bool
  | .compare .. => true
  | .signedCompare .. => true
  | .narrowSignedCompare .. => true
  | _ => false

private def exprIsBoolLiteralV1 : Expr → Bool
  | .literal value => value == 0 || value == 1
  | _ => false

private def exprIsBoolCompatibleV1 (fns : Array FnBinding) (expr : Expr) : Bool :=
  match expr with
  | .compare .. => true
  | .signedCompare .. => true
  | .narrowSignedCompare .. => true
  | .boolNot .. => true
  | .logicalAnd .. => true
  | .logicalOr .. => true
  | .literal value => value == 0 || value == 1
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some binding => binding.resultIsBool
      | none => false
  | _ => false

/-- Word-compatible (UInt/Int/Field): everything except comparison, boolNot,
    logical binaries, and Bool-returning callFn. Signed arith/neg/sar and Field
    arith/neg count as word-compatible for store/return/event args. -/
private def exprIsUInt64CompatibleV1 (fns : Array FnBinding) (expr : Expr) : Bool :=
  match expr with
  | .compare .. => false
  | .signedCompare .. => false
  | .narrowSignedCompare .. => false
  | .boolNot .. => false
  | .logicalAnd .. => false
  | .logicalOr .. => false
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some binding => !binding.resultIsBool
      | none => false
  | _ => true

/-- Recursive statement-tree validator: kind gates, view-write ban (including
    inside branches), node accounting, and per-level return ordering. Returns
    the updated node total and whether execution of this statement list always
    ends in a return on every path. A bare-return marker is accepted only at
    the top level of a constructor body (`allowReturnNone`); early bare returns
    inside branch arms fail closed (the constructor deployment epilogue must
    run on every path, which a mid-arm halt would skip). -/
private partial def checkPlanStatementsV1
    (owner : String) (isConstructor : Bool) (isView : Bool)
    (resultKind : ResultKind) (slots : Array Nat) (paramCount : Nat)
    (allowReturnNone : Bool)
    (eventCount : Nat) (eventFieldCounts : Array Nat)
    (errorCount : Nat) (errorFieldCounts : Array Nat)
    (fns : Array FnBinding)
    (statements : Array Statement) (total : Nat) :
    CompileResult (Nat × Bool) := do
  let mut total := total
  let mut closed := false
  for statement in statements do
    if closed then
      throw <| .planInvariant .evm s!"{owner} has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .evm s!"{owner} writes storage in a view context"
        unless exprIsUInt64CompatibleV1 fns store.value do
          throw <| .planInvariant .evm
            s!"{owner} cannot store a Bool-typed expression into a UInt64 slot"
        total ← addPlanStoreNodes slots paramCount total fns store
    | .storeAtomic operations =>
        if isView then
          throw <| .planInvariant .evm s!"{owner} writes storage in a view context"
        unless operations.size ≥ 2 do
          throw <| .planInvariant .evm
            s!"{owner} storeAtomic requires at least two leaf stores (use store for scalar)"
        -- Slot uniqueness within the batch (one StateStore leaf set).
        let mut seenSlots : Array Nat := #[]
        for store in operations do
          if seenSlots.contains store.slot then
            throw <| .planInvariant .evm
              s!"{owner} storeAtomic has duplicate slot {store.slot}"
          seenSlots := seenSlots.push store.slot
          unless exprIsUInt64CompatibleV1 fns store.value do
            throw <| .planInvariant .evm
              s!"{owner} cannot store a Bool-typed expression into a UInt64 slot"
          total ← addPlanStoreNodes slots paramCount total fns store
        total := total + 1
    | .assert condition =>
        unless exprIsBoolCompatibleV1 fns condition do
          throw <| .planInvariant .evm
            s!"{owner} assert condition must be a Bool-typed expression"
        total ← addPlanExprNodes slots paramCount total fns condition
    | .returnValue value =>
        if isConstructor then
          throw <| .planInvariant .evm "constructor cannot return a value"
        match resultKind with
        | .uint64 | .uint32 | .uint16 | .uint8 | .uint128 | .uint256
        | .int64 | .int32 | .int16 | .int8 | .field =>
            unless exprIsUInt64CompatibleV1 fns value do
              throw <| .planInvariant .evm
                s!"{owner} resultKind integer/Field is inconsistent with Bool return expression"
        | .bool =>
            unless exprIsBoolCompatibleV1 fns value do
              throw <| .planInvariant .evm
                s!"{owner} resultKind bool is inconsistent with integer return expression"
        | .aggregate _ =>
            throw <| .planInvariant .evm
              s!"{owner} aggregate resultKind must use returnAggregate, not returnValue"
        total ← addPlanExprNodes slots paramCount total fns value
        closed := true
    | .returnAggregate leaves leafIsInt =>
        if isConstructor then
          throw <| .planInvariant .evm "constructor cannot return a value"
        match resultKind with
        | .aggregate expectedLeaves =>
            unless leaves.size == expectedLeaves.size do
              throw <| .planInvariant .evm
                s!"{owner} returnAggregate leaf count mismatch (expected {expectedLeaves.size}, got {leaves.size})"
            unless leafIsInt.size == leaves.size do
              throw <| .planInvariant .evm
                s!"{owner} returnAggregate leafIsInt length mismatch"
            for i in [0:expectedLeaves.size] do
              let some exp := expectedLeaves[i]? | throw <| .planInvariant .evm "returnAggregate expected leaf missing"
              let some gotInt := leafIsInt[i]? | throw <| .planInvariant .evm "returnAggregate leafIsInt missing"
              unless gotInt == exp.isInt do
                throw <| .planInvariant .evm
                  s!"{owner} returnAggregate leaf {i} ABI kind mismatch (expected isInt={exp.isInt}, got {gotInt})"
              let some leaf := leaves[i]? | throw <| .planInvariant .evm "returnAggregate leaf missing"
              unless exprIsUInt64CompatibleV1 fns leaf do
                throw <| .planInvariant .evm
                  s!"{owner} returnAggregate leaf {i} must be an integer/Field expression"
        | _ =>
            throw <| .planInvariant .evm
              s!"{owner} returnAggregate requires an aggregate resultKind"
        for leaf in leaves do
          total ← addPlanExprNodes slots paramCount total fns leaf
        total := total + 1
        closed := true
    | .returnNone =>
        unless allowReturnNone do
          throw <| .planInvariant .evm
            s!"{owner} has an early bare return inside a branch arm"
        total := total + 1
        closed := true
    | .emitEvent eventIndex args =>
        if isView then
          throw <| .planInvariant .evm s!"{owner} emits an event in a view context"
        unless eventIndex < eventCount do
          throw <| .planInvariant .evm s!"{owner} emits an unknown event"
        unless args.size == eventFieldCounts[eventIndex]! do
          throw <| .planInvariant .evm s!"{owner} event argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .evm
              s!"{owner} event arguments must be UInt64 expressions"
          total ← addPlanExprNodes slots paramCount total fns arg
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .evm s!"{owner} reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .evm s!"{owner} error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .evm
              s!"{owner} error arguments must be UInt64 expressions"
          total ← addPlanExprNodes slots paramCount total fns arg
        total := total + 1
        closed := true
    | .externalCall callee args =>
        if isView then
          throw <| .planInvariant .evm s!"{owner} makes an external call in a view context"
        unless callee.size ≥ 2 do
          throw <| .planInvariant .evm
            s!"{owner} external call callee must have at least two components"
        for c in callee do
          unless isIdentifier c do
            throw <| .planInvariant .evm
              s!"{owner} external call callee component '{c}' is not a safe identifier"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .evm
              s!"{owner} external call arguments must be UInt64 expressions"
          total ← addPlanExprNodes slots paramCount total fns arg
        total := total + 1
    | .schedule callee args =>
        if isView then
          throw <| .planInvariant .evm s!"{owner} schedules a workflow in a view context"
        unless callee.size ≥ 2 do
          throw <| .planInvariant .evm
            s!"{owner} schedule callee must have at least two components"
        for c in callee do
          unless isIdentifier c do
            throw <| .planInvariant .evm
              s!"{owner} schedule callee component '{c}' is not a safe identifier"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .evm
              s!"{owner} schedule arguments must be UInt64 expressions"
          total ← addPlanExprNodes slots paramCount total fns arg
        total := total + 1
    | .ifThenElse condition thenBody elseBody =>
        unless exprIsBoolCompatibleV1 fns condition do
          throw <| .planInvariant .evm
            s!"{owner} if condition must be a Bool-typed expression"
        total ← addPlanExprNodes slots paramCount total fns condition
        total := total + 1
        let (t1, c1) ← checkPlanStatementsV1
          owner isConstructor isView resultKind slots paramCount false
          eventCount eventFieldCounts errorCount errorFieldCounts fns thenBody total
        let (t2, c2) ← checkPlanStatementsV1
          owner isConstructor isView resultKind slots paramCount false
          eventCount eventFieldCounts errorCount errorFieldCounts fns elseBody t1
        total := t2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes slots paramCount total fns scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, c) ← checkPlanStatementsV1
            owner isConstructor isView resultKind slots paramCount false
            eventCount eventFieldCounts errorCount errorFieldCounts fns caseBody total
          total := t
          allClosed := allClosed && c
        let (td, cd) ← checkPlanStatementsV1
          owner isConstructor isView resultKind slots paramCount false
          eventCount eventFieldCounts errorCount errorFieldCounts fns defaultBody total
        total := td
        closed := allClosed && cd
    | .forLoop varTemp counterTemp maxIterations initial cond update body =>
        unless varTemp != counterTemp do
          throw <| .planInvariant .evm
            s!"{owner} for-loop induction and counter temps must be distinct"
        unless maxIterations.toNat <= 4096 do
          throw <| .planInvariant .evm
            s!"{owner} for-loop maxIterations exceeds the wire maximum 4096"
        unless exprIsUInt64CompatibleV1 fns initial do
          throw <| .planInvariant .evm
            s!"{owner} for-loop initial must be a UInt64-typed expression"
        unless exprIsBoolCompatibleV1 fns cond do
          throw <| .planInvariant .evm
            s!"{owner} for-loop condition must be a Bool-typed expression"
        unless exprIsUInt64CompatibleV1 fns update do
          throw <| .planInvariant .evm
            s!"{owner} for-loop update must be a UInt64-typed expression"
        total ← addPlanExprNodes slots paramCount total fns initial
        total ← addPlanExprNodes slots paramCount total fns cond
        total ← addPlanExprNodes slots paramCount total fns update
        -- forLoop node + counter init/check/increment accounting
        total := total + 4
        let (tb, _cb) ← checkPlanStatementsV1
          owner isConstructor isView resultKind slots paramCount false
          eventCount eventFieldCounts errorCount errorFieldCounts fns body total
        total := tb
        -- A for-loop does not itself close every path; code after the loop may run.
        closed := false
  pure (total, closed)

/-- Validate the public `Evm.Plan` value before any Yul is produced. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless isIdentifier plan.objectName do
    throw <| .planInvariant .evm s!"object name '{plan.objectName}' is not a safe EVM identifier"
  if plan.objectName.toUTF8.size > maxArtifactStemBytes then
    throw <| .planInvariant .evm
      s!"object name exceeds artifact-stem limit {maxArtifactStemBytes} bytes"
  unless isIdentifier plan.runtimeObjectName && plan.runtimeObjectName != plan.objectName do
    throw <| .planInvariant .evm "runtime object name must be safe and distinct from the containing object"
  if plan.entries.isEmpty then
    throw <| .planInvariant .evm "plan has no entries"
  if plan.storageLayout.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"storage layout exceeds profile limit {maxStorageBindings}"
  if plan.entries.size > maxEntries then
    throw <| .planInvariant .evm s!"entry count exceeds profile limit {maxEntries}"
  for binding in plan.storageLayout do
    unless isIdentifier binding.name do
      throw <| .planInvariant .evm s!"storage name '{binding.name}' is not a safe identifier"
    unless validAbiByteWidth binding.byteWidth do
      throw <| .planInvariant .evm
        s!"storage '{binding.name}' byteWidth {binding.byteWidth} is not an admitted ABI width"
  let stateIds := plan.storageLayout.map (·.sourceId)
  let stateNames := plan.storageLayout.map (·.name)
  let slots := plan.storageLayout.map (·.slot)
  if hasDuplicates stateIds || hasDuplicates stateNames || hasDuplicates slots then
    throw <| .planInvariant .evm "storage ids, names, and slots must each be unique"
  for binding in plan.events do
    unless isIdentifier binding.name && binding.fieldCount <= maxParams do
      throw <| .planInvariant .evm s!"event '{binding.name}' is not a canonical binding"
  if hasDuplicates (plan.events.map (·.name)) then
    throw <| .planInvariant .evm "event names must be unique"
  for binding in plan.errors do
    unless isIdentifier binding.name && binding.fieldCount <= maxParams do
      throw <| .planInvariant .evm s!"error '{binding.name}' is not a canonical binding"
  if hasDuplicates (plan.errors.map (·.name)) then
    throw <| .planInvariant .evm "error names must be unique"
  let eventFieldCounts := plan.events.map (·.fieldCount)
  let errorFieldCounts := plan.errors.map (·.fieldCount)
  for index in [0:plan.storageLayout.size] do
    unless plan.storageLayout[index]!.slot == index &&
        plan.storageLayout[index]!.sourceId == index do
      throw <| .planInvariant .evm "storage slots and semantic origins must match declaration order"
  let constructorNodes := plan.constructor.map (fun constructor =>
    let stmtCount :=
      if constructor.body.isEmpty then constructor.stores.size else constructor.body.size
    1 + constructor.params.size + stmtCount) |>.getD 0
  let entryNodes := plan.entries.foldl (fun total entry =>
    total + entry.params.size + entry.body.size) 0
  let fnNodes := plan.fns.foldl (fun total fn =>
    total + fn.params.size + fn.body.size) 0
  let mut totalPlanNodes :=
    plan.storageLayout.size + plan.entries.size + plan.fns.size +
      constructorNodes + entryNodes + fnNodes
  if totalPlanNodes > maxPlanNodes then
    throw <| .planInvariant .evm s!"plan exceeds aggregate node limit {maxPlanNodes}"
  if plan.fns.size > maxEntries then
    throw <| .planInvariant .evm s!"fn count exceeds profile limit {maxEntries}"
  for fn in plan.fns do
    unless isIdentifier fn.name do
      throw <| .planInvariant .evm s!"fn name '{fn.name}' is not a safe identifier"
    if fn.params.size > maxParams || fn.body.size > maxBodyStatements then
      throw <| .planInvariant .evm s!"fn '{fn.name}' exceeds the profile resource limits"
    for index in [0:fn.params.size] do
      unless fn.params[index]!.wordIndex == index &&
          fn.params[index]!.sourceId == index do
        throw <| .planInvariant .evm
          s!"fn '{fn.name}' ABI words and semantic origins must be canonical"
      unless isIdentifier fn.params[index]!.name do
        throw <| .planInvariant .evm s!"fn '{fn.name}' parameter name is not a safe ABI identifier"
      unless validAbiByteWidth fn.params[index]!.byteWidth do
        throw <| .planInvariant .evm
          s!"fn '{fn.name}' parameter byteWidth is not an admitted ABI width"
      unless !fn.params[index]!.isInt ||
          (fn.params[index]!.byteWidth == 1 || fn.params[index]!.byteWidth == 2 ||
            fn.params[index]!.byteWidth == 4 || fn.params[index]!.byteWidth == 8) do
        throw <| .planInvariant .evm
          s!"fn '{fn.name}' Int parameter must have byteWidth 1/2/4/8"
      unless !(fn.params[index]!.byteWidth == 32) || !fn.params[index]!.isInt do
        throw <| .planInvariant .evm
          s!"fn '{fn.name}' Field (byteWidth 32) parameter must not be Int"
    let sourceIds := fn.params.map (·.sourceId)
    let names := fn.params.map (·.name)
    let words := fn.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm s!"fn '{fn.name}' parameter bindings must be unique"
  let fnNames := plan.fns.map (·.name)
  if hasDuplicates fnNames then
    throw <| .planInvariant .evm "fn names must be unique"
  if let some constructor := plan.constructor then
    let ctorBodySize :=
      if constructor.body.isEmpty then constructor.stores.size else constructor.body.size
    if constructor.params.size > maxParams || ctorBodySize > maxBodyStatements then
      throw <| .planInvariant .evm "constructor exceeds the profile resource limits"
    for index in [0:constructor.params.size] do
      unless constructor.params[index]!.wordIndex == index &&
          constructor.params[index]!.sourceId == index do
        throw <| .planInvariant .evm "constructor ABI words and semantic origins must be canonical"
      unless isIdentifier constructor.params[index]!.name do
        throw <| .planInvariant .evm "constructor parameter name is not a safe ABI identifier"
      unless validAbiByteWidth constructor.params[index]!.byteWidth do
        throw <| .planInvariant .evm
          "constructor parameter byteWidth is not an admitted ABI width"
      unless !constructor.params[index]!.isInt ||
          (constructor.params[index]!.byteWidth == 1 ||
            constructor.params[index]!.byteWidth == 2 ||
            constructor.params[index]!.byteWidth == 4 ||
            constructor.params[index]!.byteWidth == 8) do
        throw <| .planInvariant .evm
          "constructor Int parameter must have byteWidth 1/2/4/8"
      unless !(constructor.params[index]!.byteWidth == 32) ||
          !constructor.params[index]!.isInt do
        throw <| .planInvariant .evm
          "constructor Field (byteWidth 32) parameter must not be Int"
    let sourceIds := constructor.params.map (·.sourceId)
    let names := constructor.params.map (·.name)
    let words := constructor.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm "constructor parameter bindings must be unique"
    if constructor.body.isEmpty then
      for store in constructor.stores do
        unless exprIsUInt64CompatibleV1 plan.fns store.value do
          throw <| .planInvariant .evm
            "constructor cannot store a Bool-typed expression into a UInt64 slot"
        totalPlanNodes ← addPlanStoreNodes slots constructor.params.size totalPlanNodes
          plan.fns store
    else
      let (t, _) ← checkPlanStatementsV1 "constructor" true false .uint64
        slots constructor.params.size true
        plan.events.size eventFieldCounts plan.errors.size errorFieldCounts
        plan.fns constructor.body totalPlanNodes
      totalPlanNodes := t
  for entry in plan.entries do
    unless isIdentifier entry.name && validSelector entry.selector do
      throw <| .planInvariant .evm s!"entry '{entry.name}' has an invalid ABI identity"
    if entry.params.size > maxParams || entry.body.size > maxBodyStatements then
      throw <| .planInvariant .evm s!"entry '{entry.name}' exceeds the profile resource limits"
    for index in [0:entry.params.size] do
      unless entry.params[index]!.wordIndex == index &&
          entry.params[index]!.sourceId == index do
        throw <| .planInvariant .evm
          s!"entry '{entry.name}' ABI words and semantic origins must be canonical"
      unless isIdentifier entry.params[index]!.name do
        throw <| .planInvariant .evm s!"entry '{entry.name}' parameter name is not a safe ABI identifier"
      unless validAbiByteWidth entry.params[index]!.byteWidth do
        throw <| .planInvariant .evm
          s!"entry '{entry.name}' parameter byteWidth is not an admitted ABI width"
      unless !entry.params[index]!.isInt ||
          (entry.params[index]!.byteWidth == 1 || entry.params[index]!.byteWidth == 2 ||
            entry.params[index]!.byteWidth == 4 || entry.params[index]!.byteWidth == 8) do
        throw <| .planInvariant .evm
          s!"entry '{entry.name}' Int parameter must have byteWidth 1/2/4/8"
      unless !(entry.params[index]!.byteWidth == 32) || !entry.params[index]!.isInt do
        throw <| .planInvariant .evm
          s!"entry '{entry.name}' Field (byteWidth 32) parameter must not be Int"
  let entryNames := plan.entries.map (·.name)
  let selectors := plan.entries.map (·.selector)
  if hasDuplicates entryNames then
    throw <| .planInvariant .evm "entry names must be unique"
  if hasDuplicates selectors then
    throw <| .planInvariant .evm "entry selectors collide"
  for entry in plan.entries do
    let expectedSelector := Keccak.selector entry.name
      (entry.params.map abiParamTypeString)
    unless entry.selector == expectedSelector do
      throw <| .planInvariant .evm
        s!"entry '{entry.name}' selector is not bound to its canonical ABI signature"
    let sourceIds := entry.params.map (·.sourceId)
    let names := entry.params.map (·.name)
    let words := entry.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm s!"entry '{entry.name}' parameter bindings must be unique"
    if entry.body.isEmpty then
      throw <| .planInvariant .evm s!"entry '{entry.name}' has no body"
    let (t, returned) ← checkPlanStatementsV1 s!"entry '{entry.name}'" false
      (entry.mutability == .view) entry.resultKind slots entry.params.size
      false plan.events.size eventFieldCounts plan.errors.size errorFieldCounts
      plan.fns entry.body totalPlanNodes
    totalPlanNodes := t
    unless returned do
      throw <| .planInvariant .evm s!"entry '{entry.name}' does not return"
  -- pureFn bodies: no store/emit (isView=true), must return, result kind from flag.
  for fn in plan.fns do
    if fn.body.isEmpty then
      throw <| .planInvariant .evm s!"fn '{fn.name}' has no body"
    let resultKind : ResultKind :=
      if fn.resultIsBool then .bool
      else if fn.resultIsInt then .int64
      else .uint64
    let (t, returned) ← checkPlanStatementsV1 s!"fn '{fn.name}'" false
      true resultKind slots fn.params.size
      false plan.events.size eventFieldCounts plan.errors.size errorFieldCounts
      plan.fns fn.body totalPlanNodes
    totalPlanNodes := t
    unless returned do
      throw <| .planInvariant .evm s!"fn '{fn.name}' does not return"




end ProofForgeV2.Targets.Evm
