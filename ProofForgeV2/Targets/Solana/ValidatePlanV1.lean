import ProofForgeV2.Targets.Solana.LowerSemanticV1

/-!
# Solana ValidatePlanV1 — plan canonicity

Validates the public target-owned Plan before typed IR lowering.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

private partial def planExprNodes? (account : StateAccount) (params : Array Param)
    (fns : Array FnBinding)
    (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. | .bigLiteral .. => some 1
    | .temp _ => some 1
    | .param dataOffset | .narrowParam _ dataOffset =>
        if params.any (·.dataOffset == dataOffset) then some 1 else none
    | .stateLoad accountIndex byteOffset | .narrowStateLoad _ accountIndex byteOffset =>
        if account.fields.any (fun field =>
            field.accountIndex == accountIndex && field.byteOffset == byteOffset) then
          some 1
        else
          none
    | .checkedAdd lhs rhs | .checkedSub lhs rhs
    | .checkedMul lhs rhs | .checkedDiv lhs rhs | .checkedMod lhs rhs
    | .narrowCheckedAdd _ lhs rhs | .narrowCheckedSub _ lhs rhs
    | .narrowCheckedMul _ lhs rhs | .narrowCheckedDiv _ lhs rhs
    | .narrowCheckedMod _ lhs rhs
    | .signedCheckedAdd lhs rhs | .signedCheckedSub lhs rhs
    | .signedCheckedMul lhs rhs | .signedCheckedDiv lhs rhs
    | .signedCheckedMod lhs rhs
    | .narrowSignedCheckedAdd _ lhs rhs | .narrowSignedCheckedSub _ lhs rhs
    | .narrowSignedCheckedMul _ lhs rhs | .narrowSignedCheckedDiv _ lhs rhs
    | .narrowSignedCheckedMod _ lhs rhs
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .narrowBitAnd _ lhs rhs | .narrowBitOr _ lhs rhs | .narrowBitXor _ lhs rhs
    | .shl lhs rhs | .shr lhs rhs | .sar lhs rhs | .narrowSar _ lhs rhs
    | .narrowShl _ lhs rhs | .narrowShr _ lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs
    | .compare _ lhs rhs | .wideCompare _ _ lhs rhs | .signedCompare _ lhs rhs
    | .narrowSignedCompare _ _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params fns childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? account params fns childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .bitNot operand | .narrowBitNot _ operand | .boolNot operand
    | .checkedNeg operand | .narrowCheckedNeg _ operand =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params fns childDepth available operand with
        | none => none
        | some n => some (1 + n)
    | .callFn fnIndex args =>
        match fns[fnIndex]? with
        | none => none
        | some fn =>
            if args.size != fn.params.size then
              none
            else
              let childDepth := depthLeft - 1
              let rec walk (remaining : List Expr) (available totalNodes : Nat) : Option Nat :=
                match remaining with
                | [] => some totalNodes
                | arg :: rest =>
                    match planExprNodes? account params fns childDepth available arg with
                    | none => none
                    | some n => walk rest (available - n) (totalNodes + n)
              walk args.toList (nodeBudget - 1) 1

/-- UInt64-compatible plan expression (comparison/boolNot/boolAnd/boolOr results
    and Bool-returning callFn results are not UInt64). -/
private def exprIsUInt64CompatibleV1 (fns : Array FnBinding) : Expr → Bool
  | .compare .. | .wideCompare .. | .signedCompare .. | .narrowSignedCompare ..
  | .boolNot _ | .boolAnd .. | .boolOr .. => false
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => !fn.resultIsBool
      | none => false
  | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .bitNot _
  | .narrowCheckedAdd .. | .narrowCheckedSub .. | .narrowCheckedMul ..
  | .narrowCheckedDiv .. | .narrowCheckedMod .. | .narrowBitNot ..
  | .signedCheckedAdd .. | .signedCheckedSub .. | .signedCheckedMul ..
  | .signedCheckedDiv .. | .signedCheckedMod .. | .checkedNeg _
  | .narrowSignedCheckedAdd .. | .narrowSignedCheckedSub ..
  | .narrowSignedCheckedMul .. | .narrowSignedCheckedDiv ..
  | .narrowSignedCheckedMod .. | .narrowCheckedNeg ..
  | .bitAnd .. | .bitOr .. | .bitXor .. | .shl .. | .shr .. | .sar .. | .narrowSar ..
  | .narrowBitAnd .. | .narrowBitOr .. | .narrowBitXor ..
  | .narrowShl .. | .narrowShr ..
  | .checkedAdd .. | .checkedSub .. | .literal _ | .bigLiteral .. | .param _ | .narrowParam ..
  | .stateLoad .. | .narrowStateLoad ..
  | .temp _ => true

/-- Bool-compatible plan expression (compare/boolNot/boolAnd/boolOr and
    Bool-returning callFn). -/
private def exprIsBoolCompatibleV1 (fns : Array FnBinding) : Expr → Bool
  | .compare .. | .wideCompare .. | .signedCompare .. | .narrowSignedCompare ..
  | .boolNot _ | .boolAnd .. | .boolOr .. => true
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => fn.resultIsBool
      | none => false
  | .literal _ => true
  | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .bitNot _
  | .narrowCheckedAdd .. | .narrowCheckedSub .. | .narrowCheckedMul ..
  | .narrowCheckedDiv .. | .narrowCheckedMod .. | .narrowBitNot ..
  | .signedCheckedAdd .. | .signedCheckedSub .. | .signedCheckedMul ..
  | .signedCheckedDiv .. | .signedCheckedMod .. | .checkedNeg _
  | .narrowSignedCheckedAdd .. | .narrowSignedCheckedSub ..
  | .narrowSignedCheckedMul .. | .narrowSignedCheckedDiv ..
  | .narrowSignedCheckedMod .. | .narrowCheckedNeg ..
  | .bitAnd .. | .bitOr .. | .bitXor .. | .shl .. | .shr .. | .sar .. | .narrowSar ..
  | .narrowBitAnd .. | .narrowBitOr .. | .narrowBitXor ..
  | .narrowShl .. | .narrowShr ..
  | .checkedAdd .. | .checkedSub .. | .param _ | .narrowParam ..
  | .stateLoad .. | .narrowStateLoad .. | .temp _ | .bigLiteral .. => false

private def addPlanExprNodes (account : StateAccount) (params : Array Param)
    (fns : Array FnBinding) (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  match planExprNodes? account params fns maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .solana
        s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

def validateStateAccount (account : StateAccount) : CompileResult Unit := do
  unless account.index == 0 && account.name == "state" &&
      account.ownerPolicy == .currentProgram do
    throw <| .planInvariant .solana "state account identity/owner policy is not canonical"
  unless account.headerOffset == 0 && account.headerWidth == stateHeaderBytes &&
      account.initializedMarker != 0 &&
      account.initializedMarker == layoutMarker account.fields &&
      account.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .solana "state account header is not canonical"
  if account.fields.isEmpty || account.fields.size > maxStateFields then
    throw <| .planInvariant .solana "state account field count is outside the profile limits"
  let names := account.fields.map (·.name)
  let offsets := account.fields.map (·.byteOffset)
  -- ArrayState: multi-leaf fields share one logical `sourceId`; uniqueness is
  -- required for physical names and offsets. Logical origins are validated via
  -- `stateLeaves` below (when present) or 1:1 sourceId==index (legacy).
  if hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana "state field origins, names, and offsets must be unique"
  -- Cumulative pitch: UInt{8,16,32,64} keep 8-byte slots; UInt128→16; UInt256→32.
  let mut expectedOffset : Nat := stateHeaderBytes
  for index in [0:account.fields.size] do
    let field := account.fields[index]!
    let admittedWidth :=
      field.byteWidth == 1 || field.byteWidth == 2 ||
      field.byteWidth == 4 || field.byteWidth == 8 ||
      field.byteWidth == 16 || field.byteWidth == 32
    unless field.accountIndex == account.index &&
        field.byteOffset == expectedOffset && admittedWidth &&
        field.endianness == .little && isIdentifier field.name do
      throw <| .planInvariant .solana
        "state field layout is not canonical little-endian with admitted ABI byteWidth"
    expectedOffset := expectedOffset + slotPitchOfByteWidth field.byteWidth
  unless account.exactDataLen == expectedOffset do
    throw <| .planInvariant .solana "state account exact data length does not match its fields"
  if account.stateLeaves.isEmpty then
    -- Legacy 1:1: each field sourceId equals its physical index.
    for index in [0:account.fields.size] do
      let field := account.fields[index]!
      unless field.sourceId == index do
        throw <| .planInvariant .solana
          "state field origins, names, and offsets must be unique"
  else
    -- ArrayState multi-leaf: stateLeaves partitions fields; every field index
    -- appears exactly once; each leaf's sourceId equals its logical state id.
    unless account.stateLeaves.size > 0 do
      throw <| .planInvariant .solana "stateLeaves must be nonempty when present"
    let mut seen : Array Bool := Array.replicate account.fields.size false
    for sid in [0:account.stateLeaves.size] do
      let some leaves := account.stateLeaves[sid]? |
        throw <| .planInvariant .solana "stateLeaves row missing"
      unless leaves.size ≥ 1 do
        throw <| .planInvariant .solana "stateLeaves row must be nonempty"
      for fi in leaves do
        unless fi < account.fields.size do
          throw <| .planInvariant .solana "stateLeaves references out-of-range field"
        let some already := seen[fi]? |
          throw <| .planInvariant .solana "stateLeaves seen table corrupt"
        if already then
          throw <| .planInvariant .solana "stateLeaves field index must be unique"
        seen := seen.set! fi true
        let field := account.fields[fi]!
        unless field.sourceId == sid do
          throw <| .planInvariant .solana
            "stateLeaves sourceId must match logical state id"
    unless seen.all (· == true) do
      throw <| .planInvariant .solana "stateLeaves must cover every physical field"

def validateParams (owner : String) (params : Array Param) : CompileResult Unit := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let sourceIds := params.map (·.sourceId)
  let names := params.map (·.name)
  let offsets := params.map (·.dataOffset)
  if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana s!"parameter bindings in {owner} must be unique"
  let mut expectedOffset : Nat := discriminatorBytes
  for index in [0:params.size] do
    let param := params[index]!
    let admittedWidth :=
      param.byteWidth == 1 || param.byteWidth == 2 ||
      param.byteWidth == 4 || param.byteWidth == 8 ||
      param.byteWidth == 16 || param.byteWidth == 32
    -- Int ABI identity: narrow Int 1/2/4/8; no Int128/256.
    unless !param.isInt || param.byteWidth == 1 || param.byteWidth == 2 ||
        param.byteWidth == 4 || param.byteWidth == 8 do
      throw <| .planInvariant .solana
        s!"parameter binding in {owner} marks Int with invalid byte width"
    unless param.sourceId == index && param.dataOffset == expectedOffset &&
        admittedWidth && param.endianness == .little && isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter binding in {owner} is not canonical little-endian with admitted ABI byteWidth"
    expectedOffset := expectedOffset + slotPitchOfByteWidth param.byteWidth

/-- Recursive statement-tree validator for one handler: view-write ban
    (including inside branches), node accounting, and per-level return
    ordering. Returns the updated node total and whether this level closes in
    return or revert on every path. A bare-return marker is accepted only at
    the top level of the initializer body (`allowReturnNone`); early bare
    returns inside branch arms fail closed (the initializer's header-marking
    epilogue must run on every path). -/
private partial def checkHandlerStatementsV1
    (account : StateAccount) (isInitializer : Bool) (isView : Bool)
    (allowReturnNone : Bool)
    (eventCount : Nat) (eventFieldCounts : Array Nat)
    (errorCount : Nat) (errorFieldCounts : Array Nat)
    (fns : Array FnBinding)
    (params : Array Param) (statements : Array Statement) (total : Nat) :
    CompileResult (Nat × Bool) := do
  let mut total := total
  let mut closed := false
  for statement in statements do
    if closed then
      throw <| .planInvariant .solana "handler has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .solana "view handler writes state"
        let some field := account.fields.find? (fun field =>
            field.accountIndex == store.accountIndex && field.byteOffset == store.byteOffset) |
          throw <| .planInvariant .solana "handler stores to an unknown field"
        unless store.byteWidth == field.byteWidth do
          throw <| .planInvariant .solana
            "handler store byteWidth does not match state field layout"
        total ← addPlanExprNodes account params fns total store.value
    | .storeAggregate leaves =>
        if isView then
          throw <| .planInvariant .solana "view handler writes state"
        unless leaves.size > 0 do
          throw <| .planInvariant .solana "handler storeAggregate requires at least one leaf"
        let mut seenTargets : Array (Nat × Nat) := #[]
        for store in leaves do
          let target := (store.accountIndex, store.byteOffset)
          if seenTargets.contains target then
            throw <| .planInvariant .solana
              "handler storeAggregate writes the same state field more than once"
          seenTargets := seenTargets.push target
          let some field := account.fields.find? (fun field =>
              field.accountIndex == store.accountIndex && field.byteOffset == store.byteOffset) |
            throw <| .planInvariant .solana "handler storeAggregate targets an unknown field"
          unless store.byteWidth == field.byteWidth do
            throw <| .planInvariant .solana
              "handler storeAggregate byteWidth does not match state field layout"
          total ← addPlanExprNodes account params fns total store.value
        total := total + 1
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .solana "initializer cannot return a value"
        total ← addPlanExprNodes account params fns total value
        closed := true
    | .returnNone =>
        unless allowReturnNone do
          throw <| .planInvariant .solana "handler has an early bare return inside a branch arm"
        total := total + 1
        closed := true
    | .emitEvent eventIndex args =>
        if isView then
          throw <| .planInvariant .solana "view handler emits an event"
        unless eventIndex < eventCount do
          throw <| .planInvariant .solana "handler emits an unknown event"
        unless args.size == eventFieldCounts[eventIndex]! do
          throw <| .planInvariant .solana "handler event argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .solana "handler event arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params fns total arg
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .solana "handler reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .solana "handler error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .solana "handler error arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params fns total arg
        total := total + 1
        closed := true
    | .assert condition =>
        unless exprIsBoolCompatibleV1 fns condition do
          throw <| .planInvariant .solana "handler assert condition must be a Bool expression"
        total ← addPlanExprNodes account params fns total condition
    | .externalCall callee args =>
        if isView then
          throw <| .planInvariant .solana "view handler makes an external call"
        unless callee.size ≥ 2 do
          throw <| .planInvariant .solana
            "handler external call callee must have at least two components"
        for c in callee do
          unless isIdentifier c do
            throw <| .planInvariant .solana
              s!"handler external call callee component '{c}' is not a safe identifier"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .solana
              "handler external call arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params fns total arg
        total := total + 1
    | .schedule callee args =>
        if isView then
          throw <| .planInvariant .solana "view handler schedules a workflow"
        unless callee.size ≥ 2 do
          throw <| .planInvariant .solana
            "handler schedule callee must have at least two components"
        for c in callee do
          unless isIdentifier c do
            throw <| .planInvariant .solana
              s!"handler schedule callee component '{c}' is not a safe identifier"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .solana
              "handler schedule arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params fns total arg
        total := total + 1
    | .ifThenElse condition thenBody elseBody =>
        total ← addPlanExprNodes account params fns total condition
        total := total + 1
        let (t1, c1) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params thenBody total
        let (t2, c2) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params elseBody t1
        total := t2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes account params fns total scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, c) ← checkHandlerStatementsV1
            account isInitializer isView false
            eventCount eventFieldCounts errorCount errorFieldCounts fns params caseBody total
          total := t
          allClosed := allClosed && c
        let (td, cd) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params defaultBody total
        total := td
        closed := allClosed && cd
    | .forLoop _varTemp initial cond update maxIterations body =>
        total ← addPlanExprNodes account params fns total initial
        total ← addPlanExprNodes account params fns total cond
        total ← addPlanExprNodes account params fns total update
        total := total + 1
        -- maxIterations is wire-capped at 4096 by Normalize/structure gates.
        unless maxIterations <= 4096 do
          throw <| .planInvariant .solana
            "handler forLoop maxIterations exceeds the wire ceiling 4096"
        let (tBody, cBody) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params body total
        total := tBody
        -- A loop body that returns/reverts on every path still leaves the
        -- post-loop fallthrough reachable only when the body is open; the
        -- loop statement itself never closes the enclosing region.
        closed := false
        let _ := cBody
  pure (total, closed)

def expectedAccess (account : StateAccount) (mode : HandlerMode) : AccountAccess :=
  accessFor account mode

private def validateHandler (account : StateAccount) (isInitializer : Bool)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding)
    (baseNodes : Nat) (handler : Handler) : CompileResult Nat := do
  unless isIdentifier handler.name && validDiscriminator handler.discriminator do
    throw <| .planInvariant .solana s!"handler '{handler.name}' has an invalid ABI identity"
  if isInitializer then
    unless handler.name == "initialize" && handler.mode == .initialize do
      throw <| .planInvariant .solana "initializer handler identity is not canonical"
  else
    if handler.mode == .initialize then
      throw <| .planInvariant .solana "entry handler cannot use initialize mode"
  validateParams s!"handler '{handler.name}'" handler.params
  unless handler.discriminator == instructionDiscriminator handler.name handler.params do
    throw <| .planInvariant .solana
      s!"handler '{handler.name}' discriminator is not bound to its canonical signature"
  unless handler.accountAccess == expectedAccess account handler.mode do
    throw <| .planInvariant .solana s!"handler '{handler.name}' account access is not canonical"
  if handler.body.isEmpty || handler.body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"handler '{handler.name}' has an invalid body size"
  let (total, closed) ← checkHandlerStatementsV1
    account isInitializer (handler.mode == .view) isInitializer
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    fns handler.params handler.body baseNodes
  unless closed do
    throw <| .planInvariant .solana
      s!"handler '{handler.name}' does not terminate on all paths"
  return total

private def validateFnBinding (account : StateAccount)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding)
    (baseNodes : Nat) (fn : FnBinding) : CompileResult Nat := do
  unless isIdentifier fn.name do
    throw <| .planInvariant .solana s!"fn '{fn.name}' has an invalid name"
  validateParams s!"fn '{fn.name}'" fn.params
  if fn.body.isEmpty || fn.body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"fn '{fn.name}' has an invalid body size"
  -- pureFn bodies: isView=true bans store/emit; no bare returnNone.
  let (total, closed) ← checkHandlerStatementsV1
    account false true false
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    fns fn.params fn.body baseNodes
  unless closed do
    throw <| .planInvariant .solana
      s!"fn '{fn.name}' does not terminate on all paths"
  return total

/-- Validate the public target-owned Plan before typed IR lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.instructionDiscriminatorDomain == discriminatorDomain &&
      plan.instructionDiscriminatorBytes == discriminatorBytes &&
      plan.stateLayoutDomain == layoutDomain &&
      plan.arithmeticOverflowError == arithmeticOverflowError &&
      plan.assertionFailedError == assertionFailedError &&
      plan.loopBoundExceededError == loopBoundExceededError &&
      plan.invalidShiftError == invalidShiftError do
    throw <| .planInvariant .solana "Solana Plan profile/error policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .solana s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > maxArtifactStemBytes then
    throw <| .planInvariant .solana
      s!"program name exceeds artifact-stem limit {maxArtifactStemBytes} bytes"
  validateStateAccount plan.stateAccount
  if plan.entries.isEmpty || plan.entries.size > maxEntries then
    throw <| .planInvariant .solana "entry count is outside the profile limits"
  if plan.fns.size > maxEntries then
    throw <| .planInvariant .solana s!"pureFn count exceeds profile limit {maxEntries}"
  let handlerCount := 1 + plan.entries.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total handler => total + handler.params.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total handler => total + handler.body.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.body.size) 0
  let mut total := plan.stateAccount.fields.size + handlerCount + plan.fns.size +
    paramCount + statementCount
  if total > maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  for fn in plan.fns do
    total ← validateFnBinding plan.stateAccount plan.events plan.errors plan.fns total fn
  if hasDuplicates (plan.fns.map (·.name)) then
    throw <| .planInvariant .solana "fn names must be unique"
  total ← validateHandler plan.stateAccount true plan.events plan.errors plan.fns
    total plan.initializer
  for handler in plan.entries do
    total ← validateHandler plan.stateAccount false plan.events plan.errors plan.fns
      total handler
  let handlers := #[plan.initializer] ++ plan.entries
  if hasDuplicates (handlers.map (·.name)) then
    throw <| .planInvariant .solana "handler names must be unique"
  if hasDuplicates (handlers.map (·.discriminator)) then
    throw <| .planInvariant .solana "handler discriminators collide"
  -- pureFn names must not collide with handler names either.
  if hasDuplicates (handlers.map (·.name) ++ plan.fns.map (·.name)) then
    throw <| .planInvariant .solana "handler and fn names must be unique together"




end ProofForgeV2.Targets.Solana
