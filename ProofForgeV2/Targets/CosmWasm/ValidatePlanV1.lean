import ProofForgeV2.Targets.CosmWasm.LowerSemanticV1

/-!
# CosmWasm ValidatePlanV1 — plan canonicity

Validates the public target-owned CosmWasm Plan before recipe lowering.
-/

namespace ProofForgeV2.Targets.CosmWasm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

private def exprIsUInt64CompatibleV1 (fns : Array FnBinding) : Expr → Bool
  | .compare .. | .wideCompare .. => false
  | .signedCompare .. => false
  | .boolNot _ => false
  | .boolAnd .. => false
  | .boolOr .. => false
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => !fn.resultIsBool
      | none => false
  -- Narrow body ops produce UInt{8,16,32} temps (still i64 storage); pureCall
  -- args require UInt64/Int64, so treat narrow results as non-UInt64-compatible.
  | .narrowCheckedAdd .. | .narrowCheckedSub .. | .narrowCheckedMul ..
  | .narrowCheckedDiv .. | .narrowCheckedMod .. | .narrowBitNot ..
  | .narrowBitAnd .. | .narrowBitOr .. | .narrowBitXor ..
  | .narrowShl .. | .narrowShr .. => false
  | _ => true

private partial def planExprNodes? (layout : StorageLayout) (params : Array Param)
    (fns : Array FnBinding) (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    let binaryNodes (lhs rhs : Expr) : Option Nat :=
      let childDepth := depthLeft - 1
      let available := nodeBudget - 1
      match planExprNodes? layout params fns childDepth available lhs with
      | none => none
      | some lhsNodes =>
          match planExprNodes? layout params fns childDepth (available - lhsNodes) rhs with
          | none => none
          | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    let unaryNodes (operand : Expr) : Option Nat :=
      let childDepth := depthLeft - 1
      let available := nodeBudget - 1
      match planExprNodes? layout params fns childDepth available operand with
      | none => none
      | some nodes => some (1 + nodes)
    match expr with
    | .literal .. | .bigLiteral .. => some 1
    | .param inputOffset | .narrowParam _ inputOffset =>
        if params.any (·.inputOffset == inputOffset) then some 1 else none
    | .stateLoad fieldIndex | .narrowStateLoad _ fieldIndex =>
        if fieldIndex < layout.fields.size then some 1 else none
    | .localTemp _ => some 1
    | .blockTimeSeconds => some 1
    | .nativeVaultBalance => some 1
    | .callerPrincipalLen => some 1
    | .callerPrincipalWord wordIndex =>
        if wordIndex < 8 then some 1 else none
    | .checkedAdd lhs rhs => binaryNodes lhs rhs
    | .checkedSub lhs rhs => binaryNodes lhs rhs
    | .checkedMul lhs rhs => binaryNodes lhs rhs
    | .checkedDiv lhs rhs => binaryNodes lhs rhs
    | .checkedMod lhs rhs => binaryNodes lhs rhs
    | .narrowCheckedAdd _ lhs rhs | .narrowCheckedSub _ lhs rhs
    | .narrowCheckedMul _ lhs rhs | .narrowCheckedDiv _ lhs rhs
    | .narrowCheckedMod _ lhs rhs
    | .narrowBitAnd _ lhs rhs | .narrowBitOr _ lhs rhs | .narrowBitXor _ lhs rhs
    | .narrowShl _ lhs rhs | .narrowShr _ lhs rhs => binaryNodes lhs rhs
    | .signedCheckedAdd lhs rhs => binaryNodes lhs rhs
    | .signedCheckedSub lhs rhs => binaryNodes lhs rhs
    | .signedCheckedMul lhs rhs => binaryNodes lhs rhs
    | .signedCheckedDiv lhs rhs => binaryNodes lhs rhs
    | .signedCheckedMod lhs rhs => binaryNodes lhs rhs
    | .signedCompare _ lhs rhs => binaryNodes lhs rhs
    | .bitAnd lhs rhs => binaryNodes lhs rhs
    | .bitOr lhs rhs => binaryNodes lhs rhs
    | .bitXor lhs rhs => binaryNodes lhs rhs
    | .shl lhs rhs => binaryNodes lhs rhs
    | .shr lhs rhs => binaryNodes lhs rhs
    | .sar lhs rhs => binaryNodes lhs rhs
    | .bitNot operand | .narrowBitNot _ operand => unaryNodes operand
    | .boolNot operand => unaryNodes operand
    | .checkedNeg operand => unaryNodes operand
    | .boolAnd lhs rhs => binaryNodes lhs rhs
    | .boolOr lhs rhs => binaryNodes lhs rhs
    | .compare _ lhs rhs | .wideCompare _ _ lhs rhs => binaryNodes lhs rhs
    | .callFn fnIndex args => Id.run do
        match fns[fnIndex]? with
        | none => pure none
        | some fn =>
            if args.size != fn.params.size then pure none
            else
              let childDepth := depthLeft - 1
              let mut available := nodeBudget - 1
              let mut totalNodes : Nat := 1
              let mut ok := true
              for arg in args do
                unless exprIsUInt64CompatibleV1 fns arg do
                  ok := false
                match planExprNodes? layout params fns childDepth available arg with
                | none => ok := false
                | some n =>
                    totalNodes := totalNodes + n
                    available := available - n
              pure (if ok then some totalNodes else none)

private def addPlanExprNodes (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (fns : Array FnBinding) (total : Nat) (expr : Expr) :
    CompileResult Nat := do
  if total >= limits.maxPlanNodes then
    throw <| .planInvariant .cosmwasm
      s!"plan exceeds aggregate node limit {limits.maxPlanNodes}"
  match planExprNodes? layout params fns limits.maxExprDepth
      (limits.maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .cosmwasm
        s!"plan expression has a dangling reference or exceeds depth {limits.maxExprDepth}/node limit {limits.maxPlanNodes}"

private def addMethodExprTemps (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (fns : Array FnBinding) (total : Nat) (expr : Expr) :
    CompileResult Nat := do
  if total >= limits.maxMethodLocals then
    throw <| .planInvariant .cosmwasm
      s!"method expression exceeds local limit {limits.maxMethodLocals}"
  match planExprNodes? layout params fns limits.maxExprDepth
      (limits.maxMethodLocals - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .cosmwasm
        s!"method expression has a dangling reference or exceeds depth {limits.maxExprDepth}/local limit {limits.maxMethodLocals}"

private def validateStorageLayout (limits : ResourceLimits)
    (layout : StorageLayout) : CompileResult Unit := do
  unless layout.markerKey == layoutMarkerKey && layout.markerValue != 0 &&
      layout.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .cosmwasm "CosmWasm storage initialization/layout policy is not canonical"
  if layout.fields.isEmpty || layout.fields.size > limits.maxStateFields then
    throw <| .planInvariant .cosmwasm "state field count is outside the profile limits"
  for index in [0:layout.fields.size] do
    let field := layout.fields[index]!
    -- BL-15: Plan semantic byteWidth ∈ {1,2,4,8} for UInt{8,16,32,64}/Int64.
    -- Physical CosmWasm KV is always an 8-byte Region (high bytes zero for
    -- narrow values); Emit does not use byteWidth as the Region length.
    let admittedWidth :=
      field.byteWidth == 1 || field.byteWidth == 2 ||
      field.byteWidth == 4 || field.byteWidth == 8
    unless field.sourceId == index && isIdentifier field.name &&
        field.key == stateKey index && admittedWidth &&
        field.endianness == .little do
      throw <| .planInvariant .cosmwasm
        "state field KV layout is not canonical little-endian with admitted ABI byteWidth"
  if hasDuplicates (layout.fields.map (·.name)) ||
      hasDuplicates (layout.fields.map (·.key)) ||
      layout.fields.any (·.key == layout.markerKey) then
    throw <| .planInvariant .cosmwasm "state field names/keys must be unique and distinct from the marker"
  unless layout.markerValue == layoutMarker layout.fields do
    throw <| .planInvariant .cosmwasm "state layout marker is not bound to the canonical KV schema"

private def validateParams (limits : ResourceLimits) (owner : String)
    (params : Array Param) : CompileResult Unit := do
  if params.size > limits.maxParams then
    throw <| .planInvariant .cosmwasm
      s!"parameter count in {owner} exceeds profile limit {limits.maxParams}"
  let mut expectedOffset : Nat := 0
  for index in [0:params.size] do
    let param := params[index]!
    let admittedWidth :=
      param.byteWidth == 1 || param.byteWidth == 2 ||
      param.byteWidth == 4 || param.byteWidth == 8 ||
      param.byteWidth == 16 || param.byteWidth == 32
    unless param.sourceId == index && isIdentifier param.name &&
        param.inputOffset == expectedOffset && admittedWidth &&
        param.endianness == .little do
      throw <| .planInvariant .cosmwasm
        s!"parameter binding in {owner} is not canonical little-endian with admitted ABI byteWidth"
    expectedOffset := expectedOffset + slotPitchOfByteWidth param.byteWidth
  if hasDuplicates (params.map (·.name)) then
    throw <| .planInvariant .cosmwasm s!"parameter names in {owner} must be unique"

/-- Recursive statement-tree validator for one method or pureFn: view-write ban
    (including inside branches), pureFn state/event ban, node/temp accounting,
    and per-level return ordering. Returns (total, methodTemps, closed). A
    bare-return marker is accepted only at the top level of the initializer
    body (`allowReturnNone`); early bare returns inside branch arms fail closed
    (the initializer's layout-marking epilogue must run on every path). -/
private partial def checkMethodStatementsV1
    (limits : ResourceLimits) (layout : StorageLayout)
    (isInitializer : Bool) (isView : Bool) (isPureFn : Bool)
    (allowReturnNone : Bool)
    (eventCount : Nat) (eventFieldCounts : Array Nat)
    (errorCount : Nat) (errorFieldCounts : Array Nat)
    (params : Array Param) (fns : Array FnBinding)
    (statements : Array Statement)
    (total : Nat) (methodTemps : Nat) :
    CompileResult (Nat × Nat × Bool) := do
  let mut total := total
  let mut methodTemps := methodTemps
  let mut closed := false
  for statement in statements do
    if closed then
      throw <| .planInvariant .cosmwasm s!"method has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .cosmwasm s!"view method writes state"
        if isPureFn then
          throw <| .planInvariant .cosmwasm s!"pureFn body writes state"
        unless store.fieldIndex < layout.fields.size do
          throw <| .planInvariant .cosmwasm s!"method stores to an unknown KV field"
        let field := layout.fields[store.fieldIndex]!
        unless store.byteWidth == field.byteWidth do
          throw <| .planInvariant .cosmwasm
            "method store byteWidth does not match state field layout"
        total ← addPlanExprNodes limits layout params fns total store.value
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps store.value
    | .storeAtomic leaves =>
        if isView then
          throw <| .planInvariant .cosmwasm s!"view method writes state"
        if isPureFn then
          throw <| .planInvariant .cosmwasm s!"pureFn body writes state"
        unless leaves.size > 0 do
          throw <| .planInvariant .cosmwasm "atomic store must have at least one leaf"
        -- Count each leaf Expr toward plan/method budgets independently (same
        -- as N sequential stores). Duplicate fieldIndex is fail-closed.
        let mut seen : Array Nat := #[]
        for store in leaves do
          unless store.fieldIndex < layout.fields.size do
            throw <| .planInvariant .cosmwasm s!"method stores to an unknown KV field"
          if seen.any (· == store.fieldIndex) then
            throw <| .planInvariant .cosmwasm
              "atomic store writes the same KV field more than once"
          seen := seen.push store.fieldIndex
          let field := layout.fields[store.fieldIndex]!
          unless store.byteWidth == field.byteWidth do
            throw <| .planInvariant .cosmwasm
              "method store byteWidth does not match state field layout"
          total ← addPlanExprNodes limits layout params fns total store.value
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps store.value
        total := total + 1
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .cosmwasm "initializer cannot return a value"
        total ← addPlanExprNodes limits layout params fns total value
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps value
        closed := true
    | .returnAggregate leaves leafIsInt =>
        if isInitializer then
          throw <| .planInvariant .cosmwasm "initializer cannot return a value"
        if isPureFn then
          throw <| .planInvariant .cosmwasm
            "pureFn cannot returnAggregate (B-RET-ABI: pureFn aggregate returns stay fail closed)"
        unless leaves.size > 0 && leaves.size ≤ 8 do
          throw <| .planInvariant .cosmwasm
            "method returnAggregate leaf count must be in 1..8 (B-RET-ABI)"
        unless leafIsInt.size == leaves.size do
          throw <| .planInvariant .cosmwasm
            "method returnAggregate leafIsInt length must match leaves"
        for leaf in leaves do
          unless exprIsUInt64CompatibleV1 fns leaf do
            throw <| .planInvariant .cosmwasm
              "method returnAggregate leaves must be integer expressions"
          total ← addPlanExprNodes limits layout params fns total leaf
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps leaf
        total := total + 1
        closed := true
    | .returnNone =>
        unless allowReturnNone do
          throw <| .planInvariant .cosmwasm "method has an early bare return inside a branch arm"
        total := total + 1
        closed := true
    | .emitEvent eventIndex args =>
        if isView then
          throw <| .planInvariant .cosmwasm "view method emits an event"
        if isPureFn then
          throw <| .planInvariant .cosmwasm s!"pureFn body emits an event"
        unless eventIndex < eventCount do
          throw <| .planInvariant .cosmwasm "method emits an unknown event"
        unless args.size == eventFieldCounts[eventIndex]! do
          throw <| .planInvariant .cosmwasm "method event argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .cosmwasm "method event arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg
        total := total + 1
    | .promiseAccount receiver method args =>
        -- CW-4: schedule → SubMsg reply_on=never admitted on mutate/init only.
        if isView then
          throw <| .planInvariant .cosmwasm
            (nearScheduleDisallowedError "view callable schedules a workflow")
        if isPureFn then
          throw <| .planInvariant .cosmwasm
            (nearScheduleDisallowedError "pureFn cannot schedule workflows")
        unless isNearAccountId receiver do
          throw <| .planInvariant .cosmwasm (nearAccountIdError receiver)
        unless isIdentifier method do
          throw <| .planInvariant .cosmwasm
            s!"schedule method '{method}' is not a safe identifier"
        for arg in args do
          -- UInt64-compatible trees cover public UInt64 and the shared i64
          -- signed arithmetic surface (excludes Bool/compare results).
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .cosmwasm
              "method schedule arguments must be UInt64 or Int64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg
        total := total + 1
    | .nativeDeposit amount =>
        -- ADR-0029 C1: deposit only on mutate/init; view/pureFn banned.
        if isView then
          throw <| .planInvariant .cosmwasm
            "view method cannot pf.assets.native.deposit"
        if isPureFn then
          throw <| .planInvariant .cosmwasm
            "pureFn cannot pf.assets.native.deposit"
        unless exprIsUInt64CompatibleV1 fns amount do
          throw <| .planInvariant .cosmwasm
            "method nativeDeposit amount must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total amount
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps amount
        total := total + 1
    | .nativeTransfer dstLen dstBodyWords amount =>
        if isView then
          throw <| .planInvariant .cosmwasm
            "view method cannot pf.assets.native.transfer"
        if isPureFn then
          throw <| .planInvariant .cosmwasm
            "pureFn cannot pf.assets.native.transfer"
        unless dstBodyWords.size == 8 do
          throw <| .planInvariant .cosmwasm
            "method nativeTransfer dst must have 8 body words (Principal pilot)"
        unless exprIsUInt64CompatibleV1 fns dstLen do
          throw <| .planInvariant .cosmwasm
            "method nativeTransfer dstLen must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total dstLen
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps dstLen
        for w in dstBodyWords do
          unless exprIsUInt64CompatibleV1 fns w do
            throw <| .planInvariant .cosmwasm
              "method nativeTransfer dst body words must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total w
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps w
        unless exprIsUInt64CompatibleV1 fns amount do
          throw <| .planInvariant .cosmwasm
            "method nativeTransfer amount must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total amount
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps amount
        total := total + 1
    | .tokenTransfer mintLen mintBodyWords dstLen dstBodyWords amount =>
        -- ADR-0030 E1-CW: CW20 Transfer SubMsg (reply_on=never) on mutate/init only.
        if isView then
          throw <| .planInvariant .cosmwasm
            "view method cannot pf.assets.token.transfer"
        if isPureFn then
          throw <| .planInvariant .cosmwasm
            "pureFn cannot pf.assets.token.transfer"
        unless mintBodyWords.size == 8 do
          throw <| .planInvariant .cosmwasm
            "method tokenTransfer mint must have 8 body words (Principal pilot)"
        unless exprIsUInt64CompatibleV1 fns mintLen do
          throw <| .planInvariant .cosmwasm
            "method tokenTransfer mintLen must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total mintLen
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps mintLen
        for w in mintBodyWords do
          unless exprIsUInt64CompatibleV1 fns w do
            throw <| .planInvariant .cosmwasm
              "method tokenTransfer mint body words must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total w
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps w
        unless dstBodyWords.size == 8 do
          throw <| .planInvariant .cosmwasm
            "method tokenTransfer dst must have 8 body words (Principal pilot)"
        unless exprIsUInt64CompatibleV1 fns dstLen do
          throw <| .planInvariant .cosmwasm
            "method tokenTransfer dstLen must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total dstLen
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps dstLen
        for w in dstBodyWords do
          unless exprIsUInt64CompatibleV1 fns w do
            throw <| .planInvariant .cosmwasm
              "method tokenTransfer dst body words must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total w
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps w
        unless exprIsUInt64CompatibleV1 fns amount do
          throw <| .planInvariant .cosmwasm
            "method tokenTransfer amount must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total amount
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps amount
        total := total + 1
    | .tokenVaultBalance mintLen mintBodyWords resultTemp =>
        -- ADR-0030 E2-4-CW: read-only query_chain CW20 smart-query
        -- (pf.assets.token.balanceOfSelf). View/entry-callable; pureFn banned.
        if isPureFn then
          throw <| .planInvariant .cosmwasm
            "pureFn cannot use tokenVaultBalance (host read is not pure)"
        unless mintBodyWords.size == 8 do
          throw <| .planInvariant .cosmwasm
            "method tokenVaultBalance mint must have 8 body words (Principal pilot)"
        unless exprIsUInt64CompatibleV1 fns mintLen do
          throw <| .planInvariant .cosmwasm
            "method tokenVaultBalance mintLen must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total mintLen
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps mintLen
        for w in mintBodyWords do
          unless exprIsUInt64CompatibleV1 fns w do
            throw <| .planInvariant .cosmwasm
              "method tokenVaultBalance mint body words must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total w
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps w
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .cosmwasm "method reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .cosmwasm "method error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .cosmwasm "method error arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg
        total := total + 1
        closed := true
    | .assert condition =>
        total ← addPlanExprNodes limits layout params fns total condition
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition
    | .ifThenElse condition thenBody elseBody =>
        total ← addPlanExprNodes limits layout params fns total condition
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition
        total := total + 1
        let (t1, m1, c1) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns thenBody total methodTemps
        let (t2, m2, c2) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns elseBody t1 m1
        total := t2
        methodTemps := m2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes limits layout params fns total scrutinee
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, m, c) ← checkMethodStatementsV1
            limits layout isInitializer isView isPureFn false
            eventCount eventFieldCounts errorCount errorFieldCounts
            params fns caseBody total methodTemps
          total := t
          methodTemps := m
          allClosed := allClosed && c
        let (td, md, cd) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns defaultBody total methodTemps
        total := td
        methodTemps := md
        closed := allClosed && cd
    | .forLoop _varTemp initial condition update _maxIterations body =>
        total ← addPlanExprNodes limits layout params fns total initial
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps initial
        total ← addPlanExprNodes limits layout params fns total condition
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition
        total ← addPlanExprNodes limits layout params fns total update
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps update
        total := total + 1
        let (tb, mb, _cb) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns body total methodTemps
        total := tb
        methodTemps := mb
        -- A for-loop itself does not close the enclosing method.
        closed := false
  pure (total, methodTemps, closed)

private def validateMethod (limits : ResourceLimits) (layout : StorageLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding)
    (isInitializer : Bool) (baseNodes : Nat) (method : Method) : CompileResult Nat := do
  unless isIdentifier method.name && method.name != "memory" do
    throw <| .planInvariant .cosmwasm s!"method '{method.name}' is not a safe export name"
  if isInitializer then
    unless method.name == "init" && method.mode == .initialize &&
        method.depositPolicy == .requireZero && method.resultKind == .unit do
      throw <| .planInvariant .cosmwasm "initializer export identity is not canonical"
  else if method.mode == .initialize then
    throw <| .planInvariant .cosmwasm "entry method cannot use initialize mode"
  else
    let resultKindOk :=
      match method.resultKind with
      | .uint64 | .bool | .int64 | .uint8 | .uint16 | .uint32
      | .uint128 | .uint256 | .int8 | .int16 | .int32 => true
      | .aggregate leaves =>
          leaves.size > 0 && leaves.size ≤ 8 &&
            leaves.all (fun l => l.byteWidth == 8)
      | .unit => false
    unless resultKindOk do
      throw <| .planInvariant .cosmwasm
        s!"method '{method.name}' result kind must be UInt8/16/32/64/128/256, Int64, Bool, or aggregate (named Struct/Enum or anonymous Array/Option; 1..8 × 8-byte leaves)"
  -- Deposit policy must match body deposit markers (ADR-0029 C1).
  let depositCount := statementsNativeDepositCountV1 method.body
  let expectedDeposit : DepositPolicy :=
    if method.mode == .view then .queryOnly
    else if depositCount == 1 then .requireExactNative
    else .requireZero
  unless method.depositPolicy == expectedDeposit do
    throw <| .planInvariant .cosmwasm s!"method '{method.name}' deposit policy is not canonical"
  unless depositCount ≤ 1 do
    throw <| .planInvariant .cosmwasm
      s!"method '{method.name}' may contain at most one nativeDeposit"
  validateParams limits s!"method '{method.name}'" method.params
  unless method.exactInputLen == exactInputLenOfParams method.params do
    throw <| .planInvariant .cosmwasm s!"method '{method.name}' raw input length is not canonical"
  if method.body.size > limits.maxBodyStatements || (!isInitializer && method.body.isEmpty) then
    throw <| .planInvariant .cosmwasm s!"method '{method.name}' has an invalid body size"
  let (total, _, closed) ← checkMethodStatementsV1
    limits layout isInitializer (method.mode == .view) false isInitializer
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    method.params fns method.body baseNodes 0
  unless closed do
    throw <| .planInvariant .cosmwasm
      s!"method '{method.name}' does not terminate on all paths"
  return total

private def validateFnBinding (limits : ResourceLimits) (layout : StorageLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding) (baseNodes : Nat) (fn : FnBinding) : CompileResult Nat := do
  unless isIdentifier fn.name && fn.name != "memory" do
    throw <| .planInvariant .cosmwasm s!"pureFn '{fn.name}' is not a safe identifier"
  validateParams limits s!"pureFn '{fn.name}'" fn.params
  if fn.body.isEmpty || fn.body.size > limits.maxBodyStatements then
    throw <| .planInvariant .cosmwasm s!"pureFn '{fn.name}' has an invalid body size"
  let (total, _, closed) ← checkMethodStatementsV1
    limits layout false false true false
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    fn.params fns fn.body baseNodes 0
  unless closed do
    throw <| .planInvariant .cosmwasm
      s!"pureFn '{fn.name}' does not terminate on all paths"
  return total

/-- Whether any statement tree contains a schedule→promise lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  let expectedImports := hostImportsFor (planUsesPromiseV1 plan)
  unless plan.targetDescriptor == descriptor &&
      plan.semanticSchemaVersion == semanticProgramSchemaVersionV1 &&
      plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.hostAbi == hostAbiVersion && plan.inputAbi == rawInputAbi &&
      plan.layoutDomain == stateLayoutDomain &&
      plan.hostImports == expectedImports &&
      plan.failurePolicy == canonicalFailurePolicy &&
      plan.commitPolicy == .rollbackOnTrap &&
      plan.resourceLimits == canonicalResourceLimits do
    throw <| .planInvariant .cosmwasm "CosmWasm Plan descriptor/schema/profile policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .cosmwasm s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > plan.resourceLimits.maxArtifactStemBytes then
    throw <| .planInvariant .cosmwasm
      s!"program name exceeds artifact-stem limit {plan.resourceLimits.maxArtifactStemBytes} bytes"
  validateStorageLayout plan.resourceLimits plan.storage
  if plan.entries.isEmpty || plan.entries.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .cosmwasm "entry count is outside the profile limits"
  if plan.fns.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .cosmwasm "pureFn count is outside the profile limits"
  let handlerCount := 1 + plan.entries.size + plan.fns.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total method => total + method.params.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total method => total + method.body.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.body.size) 0
  let mut total := plan.storage.fields.size + handlerCount + paramCount + statementCount
  if total > plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .cosmwasm
      s!"plan exceeds aggregate node limit {plan.resourceLimits.maxPlanNodes}"
  for fn in plan.fns do
    total ← validateFnBinding plan.resourceLimits plan.storage plan.events plan.errors
      plan.fns total fn
  total ← validateMethod plan.resourceLimits plan.storage plan.events plan.errors plan.fns
    true total plan.initializer
  for method in plan.entries do
    total ← validateMethod plan.resourceLimits plan.storage plan.events plan.errors plan.fns
      false total method
  let methods := #[plan.initializer] ++ plan.entries
  if hasDuplicates (methods.map (·.name)) then
    throw <| .planInvariant .cosmwasm "CosmWasm export names must be unique"
  if hasDuplicates (plan.fns.map (·.name)) then
    throw <| .planInvariant .cosmwasm "CosmWasm pureFn names must be unique"
  let exportAndFnNames := methods.map (·.name) ++ plan.fns.map (·.name)
  if hasDuplicates exportAndFnNames then
    throw <| .planInvariant .cosmwasm "CosmWasm export and pureFn names must not collide"




end ProofForgeV2.Targets.CosmWasm
