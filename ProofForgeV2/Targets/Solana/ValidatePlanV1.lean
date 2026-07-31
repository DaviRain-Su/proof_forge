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
    | .literal .. => some 1
    | .temp _ => some 1
    | .param dataOffset => if params.any (·.dataOffset == dataOffset) then some 1 else none
    | .stateLoad accountIndex byteOffset =>
        if account.fields.any (fun field =>
            field.accountIndex == accountIndex && field.byteOffset == byteOffset) then
          some 1
        else
          none
    | .checkedAdd lhs rhs | .checkedSub lhs rhs
    | .checkedMul lhs rhs | .checkedDiv lhs rhs | .checkedMod lhs rhs
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shl lhs rhs | .shr lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs
    | .compare _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params fns childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? account params fns childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .bitNot operand | .boolNot operand =>
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
  | .compare .. | .boolNot _ | .boolAnd .. | .boolOr .. => false
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => !fn.resultIsBool
      | none => false
  | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .bitNot _
  | .bitAnd .. | .bitOr .. | .bitXor .. | .shl .. | .shr ..
  | .checkedAdd .. | .checkedSub .. | .literal _ | .param _ | .stateLoad ..
  | .temp _ => true

/-- Bool-compatible plan expression (compare/boolNot/boolAnd/boolOr and
    Bool-returning callFn). -/
private def exprIsBoolCompatibleV1 (fns : Array FnBinding) : Expr → Bool
  | .compare .. | .boolNot _ | .boolAnd .. | .boolOr .. => true
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => fn.resultIsBool
      | none => false
  | .literal _ => true
  | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .bitNot _
  | .bitAnd .. | .bitOr .. | .bitXor .. | .shl .. | .shr ..
  | .checkedAdd .. | .checkedSub .. | .param _ | .stateLoad .. | .temp _ => false

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
  unless account.exactDataLen == stateHeaderBytes + account.fields.size * 8 do
    throw <| .planInvariant .solana "state account exact data length does not match its fields"
  let sourceIds := account.fields.map (·.sourceId)
  let names := account.fields.map (·.name)
  let offsets := account.fields.map (·.byteOffset)
  if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana "state field origins, names, and offsets must be unique"
  for index in [0:account.fields.size] do
    let field := account.fields[index]!
    unless field.sourceId == index && field.accountIndex == account.index &&
        field.byteOffset == stateHeaderBytes + index * 8 && field.byteWidth == 8 &&
        field.endianness == .little && isIdentifier field.name do
      throw <| .planInvariant .solana "state field layout is not canonical UInt64 little-endian"

def validateParams (owner : String) (params : Array Param) : CompileResult Unit := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let sourceIds := params.map (·.sourceId)
  let names := params.map (·.name)
  let offsets := params.map (·.dataOffset)
  if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana s!"parameter bindings in {owner} must be unique"
  for index in [0:params.size] do
    let param := params[index]!
    unless param.sourceId == index && param.dataOffset == discriminatorBytes + index * 8 &&
        param.byteWidth == 8 && param.endianness == .little && isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter binding in {owner} is not canonical UInt64 little-endian"

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
        unless account.fields.any (fun field =>
            field.accountIndex == store.accountIndex && field.byteOffset == store.byteOffset) do
          throw <| .planInvariant .solana "handler stores to an unknown field"
        total ← addPlanExprNodes account params fns total store.value
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
