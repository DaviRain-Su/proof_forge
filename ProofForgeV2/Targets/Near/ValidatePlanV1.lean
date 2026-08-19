import ProofForgeV2.Targets.Near.LowerSemanticV1

/-!
# Near ValidatePlanV1 — plan canonicity

Validates the public target-owned NEAR Plan before recipe lowering.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

private def loopBindingKeyV1 (index : Nat) : Nat :=
  2 * index

private def sha256BindingKeyV1 (index : Nat) : Nat :=
  2 * index + 1

private def keccak256BindingKeyV1 (index : Nat) : Nat :=
  2 * index + 3

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
  | .narrowShl .. | .narrowShr .. | .narrowSignedCheckedAdd ..
  | .narrowSignedCheckedSub .. | .narrowSignedCheckedMul ..
  | .sha256Result _ | .keccak256Result _ => false
  | _ => true

/-- Exact expression family accepted as the one-word (four LE limbs) input to
    the dedicated NEAR SHA-256 host leaf. No UInt64, Bool, Int, aggregate, or
    pureFn expression is widened implicitly. -/
private def exprIsUInt256CompatibleV1 : Expr → Bool
  | .bigLiteral 256 _ | .narrowParam 256 _ | .narrowStateLoad 256 _
  | .narrowCheckedAdd 256 .. | .narrowCheckedSub 256 ..
  | .narrowCheckedMul 256 .. | .narrowCheckedDiv 256 ..
  | .narrowCheckedMod 256 .. | .narrowBitAnd 256 ..
  | .narrowBitOr 256 .. | .narrowBitXor 256 .. | .narrowBitNot 256 _
  | .narrowShl 256 .. | .narrowShr 256 .. | .sha256Result _ | .keccak256Result _ => true
  | _ => false

private partial def planExprNodes? (layout : StorageLayout) (params : Array Param)
    (fns : Array FnBinding) (depthLeft nodeBudget : Nat) (expr : Expr)
    (localScope : Array Nat := #[]) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    let binaryNodes (lhs rhs : Expr) : Option Nat :=
      let childDepth := depthLeft - 1
      let available := nodeBudget - 1
      match planExprNodes? layout params fns childDepth available lhs localScope with
      | none => none
      | some lhsNodes =>
          match planExprNodes? layout params fns childDepth
              (available - lhsNodes) rhs localScope with
          | none => none
          | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    let unaryNodes (operand : Expr) : Option Nat :=
      let childDepth := depthLeft - 1
      let available := nodeBudget - 1
      match planExprNodes? layout params fns childDepth available operand localScope with
      | none => none
      | some nodes => some (1 + nodes)
    match expr with
    | .literal .. | .bigLiteral .. => some 1
    | .param inputOffset =>
        match params.find? (·.inputOffset == inputOffset) with
        | some p => if p.byteWidth == 8 then some 1 else none
        | none => none
    | .narrowParam bitWidth inputOffset =>
        match params.find? (·.inputOffset == inputOffset) with
        | some p =>
            if !p.isInt && bitWidth == 8 * p.byteWidth then some 1 else none
        | none => none
    | .narrowSignedParam bitWidth inputOffset =>
        match params.find? (·.inputOffset == inputOffset) with
        | some p =>
            if p.isInt && (bitWidth == 8 || bitWidth == 16 || bitWidth == 32) &&
                bitWidth == 8 * p.byteWidth then some 1 else none
        | none => none
    | .stateLoad fieldIndex =>
        match layout.fields[fieldIndex]? with
        | some f => if f.byteWidth == 8 then some 1 else none
        | none => none
    | .narrowStateLoad bitWidth fieldIndex =>
        match layout.fields[fieldIndex]? with
        | some f =>
            if !f.isInt && bitWidth == 8 * f.byteWidth then some 1 else none
        | none => none
    | .narrowSignedStateLoad bitWidth fieldIndex =>
        match layout.fields[fieldIndex]? with
        | some f =>
            if f.isInt && (bitWidth == 8 || bitWidth == 16 || bitWidth == 32) &&
                bitWidth == 8 * f.byteWidth then some 1 else none
        | none => none
    | .localTemp index =>
        if localScope.contains (loopBindingKeyV1 index) then some 1 else none
    | .sha256Result resultTemp =>
        if localScope.contains (sha256BindingKeyV1 resultTemp) then some 1 else none
    | .keccak256Result resultTemp =>
        if localScope.contains (keccak256BindingKeyV1 resultTemp) then some 1 else none
    | .blockTimestampSeconds => some 1
    | .blockIndex => some 1
    | .accountBalance => some 1
    | .accountBalanceU128 => some 1
    | .attachedDepositValue => some 1
    -- ADR-0031 S1: context.caller Principal leaves (len + wordIndex ∈ 0..7).
    | .callerPrincipalLen => some 1
    | .callerPrincipalWord wordIndex =>
        if wordIndex < 8 then some 1 else none
    | .selfPrincipalLen => some 1
    | .selfPrincipalWord wordIndex =>
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
    | .narrowSignedCheckedAdd bitWidth lhs rhs
    | .narrowSignedCheckedSub bitWidth lhs rhs
    | .narrowSignedCheckedMul bitWidth lhs rhs =>
        if bitWidth == 8 || bitWidth == 16 || bitWidth == 32 then
          binaryNodes lhs rhs
        else
          none
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
                match planExprNodes? layout params fns childDepth available arg localScope with
                | none => ok := false
                | some n =>
                    totalNodes := totalNodes + n
                    available := available - n
              pure (if ok then some totalNodes else none)

private def addPlanExprNodes (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (fns : Array FnBinding) (total : Nat) (expr : Expr)
    (localScope : Array Nat := #[]) :
    CompileResult Nat := do
  if total >= limits.maxPlanNodes then
    throw <| .planInvariant .near
      s!"plan exceeds aggregate node limit {limits.maxPlanNodes}"
  match planExprNodes? layout params fns limits.maxExprDepth
      (limits.maxPlanNodes - total) expr localScope with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .near
        s!"plan expression has a dangling reference or exceeds depth {limits.maxExprDepth}/node limit {limits.maxPlanNodes}"

private def addMethodExprTemps (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (fns : Array FnBinding) (total : Nat) (expr : Expr)
    (localScope : Array Nat := #[]) :
    CompileResult Nat := do
  if total >= limits.maxMethodLocals then
    throw <| .planInvariant .near
      s!"method expression exceeds local limit {limits.maxMethodLocals}"
  match planExprNodes? layout params fns limits.maxExprDepth
      (limits.maxMethodLocals - total) expr localScope with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .near
        s!"method expression has a dangling reference or exceeds depth {limits.maxExprDepth}/local limit {limits.maxMethodLocals}"

private def validateStorageLayout (limits : ResourceLimits)
    (layout : StorageLayout) : CompileResult Unit := do
  unless layout.markerKey == layoutMarkerKey && layout.markerValue != 0 &&
      layout.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .near "NEAR storage initialization/layout policy is not canonical"
  if layout.fields.isEmpty || layout.fields.size > limits.maxStateFields then
    throw <| .planInvariant .near "state field count is outside the profile limits"
  for index in [0:layout.fields.size] do
    let field := layout.fields[index]!
    let admittedWidth :=
      field.byteWidth == 1 || field.byteWidth == 2 ||
      field.byteWidth == 4 || field.byteWidth == 8 ||
      field.byteWidth == 16 || field.byteWidth == 32
    unless field.sourceId == index && isIdentifier field.name &&
        field.key == stateKey index && admittedWidth &&
        field.endianness == .little &&
        (!field.isInt || field.byteWidth == 1 || field.byteWidth == 2 ||
          field.byteWidth == 4 || field.byteWidth == 8) do
      throw <| .planInvariant .near
        "state field KV layout is not canonical little-endian with admitted ABI byteWidth"
  if hasDuplicates (layout.fields.map (·.name)) ||
      hasDuplicates (layout.fields.map (·.key)) ||
      layout.fields.any (·.key == layout.markerKey) then
    throw <| .planInvariant .near "state field names/keys must be unique and distinct from the marker"
  unless layout.markerValue == layoutMarker layout.fields do
    throw <| .planInvariant .near "state layout marker is not bound to the canonical KV schema"

private def validateParams (limits : ResourceLimits) (owner : String)
    (params : Array Param) : CompileResult Unit := do
  if params.size > limits.maxParams then
    throw <| .planInvariant .near
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
        param.endianness == .little &&
        (!param.isInt || param.byteWidth == 1 || param.byteWidth == 2 ||
          param.byteWidth == 4 || param.byteWidth == 8) do
      throw <| .planInvariant .near
        s!"parameter binding in {owner} is not canonical little-endian with admitted ABI byteWidth"
    expectedOffset := expectedOffset + slotPitchOfByteWidth param.byteWidth
  if hasDuplicates (params.map (·.name)) then
    throw <| .planInvariant .near s!"parameter names in {owner} must be unique"

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
    (localScope : Array Nat)
    (statements : Array Statement)
    (total : Nat) (methodTemps : Nat) :
    CompileResult (Nat × Nat × Bool) := do
  let mut total := total
  let mut methodTemps := methodTemps
  let mut closed := false
  let mut localScope := localScope
  for statement in statements do
    if closed then
      throw <| .planInvariant .near s!"method has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .near s!"view method writes state"
        if isPureFn then
          throw <| .planInvariant .near s!"pureFn body writes state"
        unless store.fieldIndex < layout.fields.size do
          throw <| .planInvariant .near s!"method stores to an unknown KV field"
        let field := layout.fields[store.fieldIndex]!
        unless store.byteWidth == field.byteWidth do
          throw <| .planInvariant .near
            "method store byteWidth does not match state field layout"
        unless store.isInt == field.isInt do
          throw <| .planInvariant .near
            "method store isInt does not match state field layout"
        if field.isInt then
          unless field.byteWidth == 1 || field.byteWidth == 2 ||
              field.byteWidth == 4 || field.byteWidth == 8 do
            throw <| .planInvariant .near
              "signed method store requires a 1/2/4/8-byte field"
        total ← addPlanExprNodes limits layout params fns total store.value localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps
          store.value localScope
    | .storeAtomic leaves =>
        if isView then
          throw <| .planInvariant .near s!"view method writes state"
        if isPureFn then
          throw <| .planInvariant .near s!"pureFn body writes state"
        unless leaves.size > 0 do
          throw <| .planInvariant .near "atomic store must have at least one leaf"
        -- Count each leaf Expr toward plan/method budgets independently (same
        -- as N sequential stores). Duplicate fieldIndex is fail-closed.
        let mut seen : Array Nat := #[]
        for store in leaves do
          unless store.fieldIndex < layout.fields.size do
            throw <| .planInvariant .near s!"method stores to an unknown KV field"
          if seen.any (· == store.fieldIndex) then
            throw <| .planInvariant .near
              "atomic store writes the same KV field more than once"
          seen := seen.push store.fieldIndex
          let field := layout.fields[store.fieldIndex]!
          unless store.byteWidth == field.byteWidth do
            throw <| .planInvariant .near
              "method store byteWidth does not match state field layout"
          unless store.isInt == field.isInt do
            throw <| .planInvariant .near
              "method store isInt does not match state field layout"
          if field.isInt then
            unless field.byteWidth == 1 || field.byteWidth == 2 ||
                field.byteWidth == 4 || field.byteWidth == 8 do
              throw <| .planInvariant .near
                "signed method store requires a 1/2/4/8-byte field"
          total ← addPlanExprNodes limits layout params fns total store.value localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps
            store.value localScope
        total := total + 1
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .near "initializer cannot return a value"
        total ← addPlanExprNodes limits layout params fns total value localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps value localScope
        closed := true
    | .returnAggregate leaves leafIsInt =>
        if isInitializer then
          throw <| .planInvariant .near "initializer cannot return a value"
        if isPureFn then
          throw <| .planInvariant .near "pureFn cannot return an aggregate"
        unless leaves.size > 0 && leaves.size ≤ 24 do
          throw <| .planInvariant .near
            "returnAggregate leaf count must be in 1..24 (B-RET-ABI; Map cap-8 = 24)"
        unless leafIsInt.size == leaves.size do
          throw <| .planInvariant .near
            "returnAggregate leafIsInt length must match leaves"
        for leaf in leaves do
          total ← addPlanExprNodes limits layout params fns total leaf localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps leaf localScope
        total := total + 1
        closed := true
    | .returnNone =>
        unless allowReturnNone do
          throw <| .planInvariant .near "method has an early bare return inside a branch arm"
        total := total + 1
        closed := true
    | .emitEvent eventIndex args =>
        if isView then
          throw <| .planInvariant .near "view method emits an event"
        if isPureFn then
          throw <| .planInvariant .near s!"pureFn body emits an event"
        unless eventIndex < eventCount do
          throw <| .planInvariant .near "method emits an unknown event"
        unless args.size == eventFieldCounts[eventIndex]! do
          throw <| .planInvariant .near "method event argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .near "method event arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg localScope
        total := total + 1
    | .promiseAccount receiver method args =>
        if isView then
          throw <| .planInvariant .near
            (nearScheduleDisallowedError "view callable schedules a workflow")
        if isPureFn then
          throw <| .planInvariant .near
            (nearScheduleDisallowedError "pureFn cannot schedule workflows")
        unless isNearAccountId receiver do
          throw <| .planInvariant .near (nearAccountIdError receiver)
        unless isIdentifier method do
          throw <| .planInvariant .near
            s!"schedule method '{method}' is not a safe identifier"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .near "method schedule arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg localScope
        total := total + 1
    | .sha256Precompile input resultTemp =>
        if isView then
          throw <| .planInvariant .near
            "view method cannot invoke pf.crypto.sha256"
        if isPureFn then
          throw <| .planInvariant .near
            "pureFn body cannot invoke pf.crypto.sha256"
        if isInitializer then
          throw <| .planInvariant .near
            "initializer cannot invoke pf.crypto.sha256"
        unless exprIsUInt256CompatibleV1 input do
          throw <| .planInvariant .near
            "pf.crypto.sha256 Plan input must be a UInt256 expression"
        let resultKey := sha256BindingKeyV1 resultTemp
        if localScope.contains resultKey then
          throw <| .planInvariant .near
            "pf.crypto.sha256 Plan result binding must be unique in its lexical scope"
        total ← addPlanExprNodes limits layout params fns total input localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps input localScope
        total := total + 1
        if methodTemps + 4 > limits.maxMethodLocals then
          throw <| .planInvariant .near
            s!"method expression exceeds local limit {limits.maxMethodLocals}"
        methodTemps := methodTemps + 4
        localScope := localScope.push resultKey
    | .sha256BytesHost inputLeaves resultTemp =>
        if isView then
          throw <| .planInvariant .near
            "view method cannot invoke pf.crypto.sha256Bytes"
        if isPureFn then
          throw <| .planInvariant .near
            "pureFn body cannot invoke pf.crypto.sha256Bytes"
        if isInitializer then
          throw <| .planInvariant .near
            "initializer cannot invoke pf.crypto.sha256Bytes"
        unless 1 ≤ inputLeaves.size && inputLeaves.size ≤ maxSha256BytesLenV1 do
          throw <| .planInvariant .near
            s!"pf.crypto.sha256Bytes Plan Bytes N must be in 1..{maxSha256BytesLenV1}"
        for leaf in inputLeaves do
          unless match leaf with
            | .narrowParam 8 _ | .narrowStateLoad 8 _ | .literal _ => true
            | _ => false
          do
            throw <| .planInvariant .near
              "pf.crypto.sha256Bytes Plan input leaves must be UInt8 expressions"
          total ← addPlanExprNodes limits layout params fns total leaf localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps leaf localScope
        let resultKey := sha256BindingKeyV1 resultTemp
        if localScope.contains resultKey then
          throw <| .planInvariant .near
            "pf.crypto.sha256Bytes Plan result binding must be unique in its lexical scope"
        total := total + 1
        if methodTemps + 4 > limits.maxMethodLocals then
          throw <| .planInvariant .near
            s!"method expression exceeds local limit {limits.maxMethodLocals}"
        methodTemps := methodTemps + 4
        localScope := localScope.push resultKey
    | .keccak256Host input resultTemp =>
        if isView then
          throw <| .planInvariant .near
            "view method cannot invoke pf.crypto.keccak256"
        if isPureFn then
          throw <| .planInvariant .near
            "pureFn body cannot invoke pf.crypto.keccak256"
        if isInitializer then
          throw <| .planInvariant .near
            "initializer cannot invoke pf.crypto.keccak256"
        unless exprIsUInt256CompatibleV1 input do
          throw <| .planInvariant .near
            "pf.crypto.keccak256 Plan input must be a UInt256 expression"
        let resultKey := keccak256BindingKeyV1 resultTemp
        if localScope.contains resultKey then
          throw <| .planInvariant .near
            "pf.crypto.keccak256 Plan result binding must be unique in its lexical scope"
        total ← addPlanExprNodes limits layout params fns total input localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps input localScope
        total := total + 1
        if methodTemps + 4 > limits.maxMethodLocals then
          throw <| .planInvariant .near
            s!"method expression exceeds local limit {limits.maxMethodLocals}"
        methodTemps := methodTemps + 4
        localScope := localScope.push resultKey
    | .nativeDeposit amount =>
        if isView then
          throw <| .planInvariant .near
            "view method cannot check attached deposit (pf.assets.native.deposit)"
        if isPureFn then
          throw <| .planInvariant .near
            "pureFn body cannot check attached deposit (pf.assets.native.deposit)"
        if isInitializer then
          throw <| .planInvariant .near
            "initializer cannot check attached deposit (pf.assets.native.deposit)"
        unless exprIsUInt64CompatibleV1 fns amount do
          throw <| .planInvariant .near
            "method deposit amount must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total amount localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps amount localScope
        total := total + 1
    | .promiseTransfer dstLen dstWords amount =>
        if isView then
          throw <| .planInvariant .near
            "view method cannot transferAsync"
        if isPureFn then
          throw <| .planInvariant .near
            "pureFn body cannot transferAsync"
        if isInitializer then
          throw <| .planInvariant .near
            "initializer cannot transferAsync"
        unless dstWords.size == nearPrincipalDataWordCountV1 do
          throw <| .planInvariant .near
            "transferAsync Principal body word count must be 8"
        unless exprIsUInt64CompatibleV1 fns dstLen do
          throw <| .planInvariant .near
            "transferAsync dst len must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total dstLen localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps dstLen localScope
        for w in dstWords do
          unless exprIsUInt64CompatibleV1 fns w do
            throw <| .planInvariant .near
              "transferAsync dst body words must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total w localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps w localScope
        unless exprIsUInt64CompatibleV1 fns amount do
          throw <| .planInvariant .near
            "transferAsync amount must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total amount localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps amount localScope
        total := total + 1
    | .promiseTokenTransfer mintLen mintWords dstLen dstWords amount =>
        if isView then
          throw <| .planInvariant .near
            "view method cannot token transferAsync"
        if isPureFn then
          throw <| .planInvariant .near
            "pureFn body cannot token transferAsync"
        if isInitializer then
          throw <| .planInvariant .near
            "initializer cannot token transferAsync"
        unless mintWords.size == nearPrincipalDataWordCountV1 do
          throw <| .planInvariant .near
            "token transferAsync mint Principal body word count must be 8"
        unless exprIsUInt64CompatibleV1 fns mintLen do
          throw <| .planInvariant .near
            "token transferAsync mint len must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total mintLen localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps mintLen localScope
        for w in mintWords do
          unless exprIsUInt64CompatibleV1 fns w do
            throw <| .planInvariant .near
              "token transferAsync mint body words must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total w localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps w localScope
        unless dstWords.size == nearPrincipalDataWordCountV1 do
          throw <| .planInvariant .near
            "token transferAsync dst Principal body word count must be 8"
        unless exprIsUInt64CompatibleV1 fns dstLen do
          throw <| .planInvariant .near
            "token transferAsync dst len must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total dstLen localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps dstLen localScope
        for w in dstWords do
          unless exprIsUInt64CompatibleV1 fns w do
            throw <| .planInvariant .near
              "token transferAsync dst body words must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total w localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps w localScope
        unless exprIsUInt64CompatibleV1 fns amount do
          throw <| .planInvariant .near
            "token transferAsync amount must be a UInt64 expression"
        total ← addPlanExprNodes limits layout params fns total amount localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps amount localScope
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .near "method reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .near "method error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .near "method error arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg localScope
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg localScope
        total := total + 1
        closed := true
    | .assert condition =>
        total ← addPlanExprNodes limits layout params fns total condition localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition localScope
    | .ifThenElse condition thenBody elseBody =>
        total ← addPlanExprNodes limits layout params fns total condition localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition localScope
        total := total + 1
        let (t1, m1, c1) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns localScope thenBody total methodTemps
        let (t2, m2, c2) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns localScope elseBody t1 m1
        total := t2
        methodTemps := m2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes limits layout params fns total scrutinee localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps scrutinee localScope
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, m, c) ← checkMethodStatementsV1
            limits layout isInitializer isView isPureFn false
            eventCount eventFieldCounts errorCount errorFieldCounts
            params fns localScope caseBody total methodTemps
          total := t
          methodTemps := m
          allClosed := allClosed && c
        let (td, md, cd) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns localScope defaultBody total methodTemps
        total := td
        methodTemps := md
        closed := allClosed && cd
    | .forLoop varTemp initial condition update _maxIterations body =>
        let loopKey := loopBindingKeyV1 varTemp
        if localScope.contains loopKey then
          throw <| .planInvariant .near
            "nested NEAR for-loop induction locals must not shadow an enclosing binding"
        total ← addPlanExprNodes limits layout params fns total initial localScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps
          initial localScope
        let loopScope := localScope.push loopKey
        total ← addPlanExprNodes limits layout params fns total condition loopScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps
          condition loopScope
        total ← addPlanExprNodes limits layout params fns total update loopScope
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps update loopScope
        total := total + 1
        let (tb, mb, _cb) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns loopScope body total methodTemps
        total := tb
        methodTemps := mb
        -- A for-loop itself does not close the enclosing method.
        closed := false
  pure (total, methodTemps, closed)

/-- B-RET-ABI depth defense: return form must match resultKind. -/
private partial def checkMethodReturnFormsV1
    (methodName : String) (resultKind : MethodResultKind)
    (stmts : Array Statement) : CompileResult Unit := do
  for s in stmts do
    match s with
    | .returnValue _ =>
        match resultKind with
        | .unit =>
            throw <| .planInvariant .near
              s!"method '{methodName}' unit resultKind must use returnNone, not returnValue"
        | .aggregate _ =>
            throw <| .planInvariant .near
              s!"method '{methodName}' aggregate resultKind must use returnAggregate, not returnValue"
        | _ => pure ()
    | .returnNone =>
        unless resultKind == .unit do
          throw <| .planInvariant .near
            s!"method '{methodName}' returnNone requires unit resultKind"
    | .returnAggregate leaves leafIsInt =>
        match resultKind with
        | .aggregate expected =>
            unless leaves.size == expected.size && leafIsInt.size == expected.size do
              throw <| .planInvariant .near
                s!"method '{methodName}' returnAggregate leaf count mismatch"
            for i in [0:expected.size] do
              let some exp := expected[i]? |
                throw <| .planInvariant .near "returnAggregate expected leaf missing"
              let some gotInt := leafIsInt[i]? |
                throw <| .planInvariant .near "returnAggregate leafIsInt missing"
              unless gotInt == exp.isInt do
                throw <| .planInvariant .near
                  s!"method '{methodName}' returnAggregate leaf {i} isInt mismatch"
        | _ =>
            throw <| .planInvariant .near
              s!"method '{methodName}' returnAggregate requires an aggregate resultKind"
    | .ifThenElse _ t e =>
        checkMethodReturnFormsV1 methodName resultKind t
        checkMethodReturnFormsV1 methodName resultKind e
    | .switchOn _ cases defaultBody =>
        for (_, body) in cases do
          checkMethodReturnFormsV1 methodName resultKind body
        checkMethodReturnFormsV1 methodName resultKind defaultBody
    | .forLoop _ _ _ _ _ body =>
        checkMethodReturnFormsV1 methodName resultKind body
    | _ => pure ()

private def validateMethod (limits : ResourceLimits) (layout : StorageLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding)
    (isInitializer : Bool) (baseNodes : Nat) (method : Method) : CompileResult Nat := do
  unless isIdentifier method.name && method.name != "memory" do
    throw <| .planInvariant .near s!"method '{method.name}' is not a safe export name"
  if isInitializer then
    unless method.name == "init" && method.mode == .initialize &&
        method.depositPolicy == .requireZero && method.resultKind == .unit do
      throw <| .planInvariant .near "initializer export identity is not canonical"
  else if method.mode == .initialize then
    throw <| .planInvariant .near "entry method cannot use initialize mode"
  else
    let resultKindOk : Bool :=
      match method.resultKind with
      | .uint64 | .bool | .int64 | .uint8 | .uint16 | .uint32
      | .uint128 | .uint256 | .int8 | .int16 | .int32 => true
      | .aggregate leaves =>
          -- Homogeneous pack: all 8-byte (Struct/Array/Option/Map) or all
          -- 1-byte (Bytes N). Mixed widths stay FC. Map cap-8 = 24 leaves.
          leaves.size > 0 && leaves.size ≤ 24 &&
            (leaves.all (fun l => l.byteWidth == 8) ||
              leaves.all (fun l => l.byteWidth == 1))
      | .unit => method.mode == MethodMode.mutate
    unless resultKindOk do
      throw <| .planInvariant .near
        s!"method '{method.name}' result kind must be mutate-Unit, UInt8/16/32/64/128/256, Int8/16/32/64, Bool, or aggregate (named Struct/Enum, anonymous Array/Option/Map ×8-byte leaves, or Bytes N ×1-byte leaves; 1..24 leaves)"
  -- ADR-0029 C2 / ADR-0031 S4: allowAttached for mutate nativeDeposit or
  -- init/entry attachedValue reads; views stay queryOnly; others requireZero.
  let expectedDeposit : DepositPolicy :=
    if method.mode == .view then .queryOnly
    else if method.mode == .mutate && statementsUseNativeDepositV1 method.body then
      .allowAttached
    else if (method.mode == .mutate || method.mode == .initialize) &&
        statementsUseAttachedDepositValueV1 method.body then
      .allowAttached
    else .requireZero
  unless method.depositPolicy == expectedDeposit do
    throw <| .planInvariant .near s!"method '{method.name}' deposit policy is not canonical"
  validateParams limits s!"method '{method.name}'" method.params
  unless method.exactInputLen == exactInputLenOfParams method.params do
    throw <| .planInvariant .near s!"method '{method.name}' raw input length is not canonical"
  if method.body.size > limits.maxBodyStatements || (!isInitializer && method.body.isEmpty) then
    throw <| .planInvariant .near s!"method '{method.name}' has an invalid body size"
  let (total, _, closed) ← checkMethodStatementsV1
    limits layout isInitializer (method.mode == .view) false
      (isInitializer || method.resultKind == .unit)
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    method.params fns #[] method.body baseNodes 0
  unless closed do
    throw <| .planInvariant .near
      s!"method '{method.name}' does not terminate on all paths"
  checkMethodReturnFormsV1 method.name method.resultKind method.body
  return total

private def validateFnBinding (limits : ResourceLimits) (layout : StorageLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding) (baseNodes : Nat) (fn : FnBinding) : CompileResult Nat := do
  unless isIdentifier fn.name && fn.name != "memory" do
    throw <| .planInvariant .near s!"pureFn '{fn.name}' is not a safe identifier"
  validateParams limits s!"pureFn '{fn.name}'" fn.params
  if fn.body.isEmpty || fn.body.size > limits.maxBodyStatements then
    throw <| .planInvariant .near s!"pureFn '{fn.name}' has an invalid body size"
  let (total, _, closed) ← checkMethodStatementsV1
    limits layout false false true false
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    fn.params fns #[] fn.body baseNodes 0
  unless closed do
    throw <| .planInvariant .near
      s!"pureFn '{fn.name}' does not terminate on all paths"
  return total

private def strictlyIncreasingNatListV1 : List Nat → Bool
  | [] | [_] => true
  | first :: second :: rest =>
      first < second && strictlyIncreasingNatListV1 (second :: rest)

private def strictlyIncreasingNatArrayV1 (values : Array Nat) : Bool :=
  strictlyIncreasingNatListV1 values.toList

private def validateErasureDigestV1 (label : String) (digest : Digest) :
    CompileResult Unit :=
  match validateDigest digest with
  | .ok () => pure ()
  | .error error =>
      throw <| .planInvariant .near
        s!"NEAR invariant-erasure {label} digest is invalid: {error}"

/-- Validate the appended proof-bound callable partition. Semantic kinds and
    exact InvariantDecl roots were checked while deriving this decision from the
    retained semantic carrier; this is the target Plan tamper/canonicity gate. -/
private def validateInvariantErasureDecisionV1
    (plan : Plan) (decision : InvariantErasureDecisionV1) : CompileResult Unit := do
  unless decision.version == invariantErasurePlanVersionV1 do
    throw <| .planInvariant .near
      "NEAR invariant-erasure Plan version is not canonical"
  validateErasureDigestV1 "source" decision.sourceDigest
  validateErasureDigestV1 "semantic" decision.semanticDigest
  validateErasureDigestV1 "proof-certification" decision.proofCertificationDigest
  unless decision.semanticCallableCount > 0 &&
        !decision.erasedInvariantCallableIds.isEmpty do
    throw <| .planInvariant .near
      "NEAR invariant-erasure decision requires a nonempty callable table and erased root set"
  unless decision.retainedMethodCallableIds.size == plan.entries.size &&
        decision.retainedPureFnCallableIds.size == plan.fns.size do
    throw <| .planInvariant .near
      "NEAR invariant-erasure callable partition does not match Plan handlers"
  unless strictlyIncreasingNatArrayV1 decision.retainedMethodCallableIds &&
        strictlyIncreasingNatArrayV1 decision.retainedPureFnCallableIds &&
        strictlyIncreasingNatArrayV1 decision.erasedInvariantCallableIds do
    throw <| .planInvariant .near
      "NEAR invariant-erasure callable id lists must be strictly increasing"
  let allIds := #[decision.retainedInitializerCallableId] ++
    decision.retainedMethodCallableIds ++ decision.retainedPureFnCallableIds ++
    decision.erasedInvariantCallableIds
  unless allIds.size == decision.semanticCallableCount &&
        allIds.all (fun callableId => callableId < decision.semanticCallableCount) &&
        (List.range decision.semanticCallableCount).all
          (fun callableId => allIds.contains callableId) do
    throw <| .planInvariant .near
      "NEAR invariant-erasure callable ids must form the exact dense semantic partition"

/-- Whether any statement tree contains a schedule→promise lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  let expectedImports := hostImportsFor (planUsesSchedulePromiseV1 plan)
    (planUsesTransferPromiseV1 plan) (planUsesTokenTransferPromiseV1 plan)
    (planUsesTimestampV1 plan) (planUsesBlockIndexV1 plan)
    (planUsesAccountBalanceV1 plan) (planUsesCallerV1 plan)
    (planUsesSelfV1 plan) (planUsesSha256V1 plan) (planUsesKeccak256V1 plan)
  unless plan.targetDescriptor == descriptor &&
      plan.semanticSchemaVersion == semanticProgramSchemaVersionV1 &&
      plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.hostAbi == hostAbiVersion && plan.inputAbi == rawInputAbi &&
      plan.layoutDomain == stateLayoutDomain &&
      plan.hostImports == expectedImports &&
      plan.failurePolicy == canonicalFailurePolicy &&
      plan.commitPolicy == .rollbackOnTrap &&
      plan.resourceLimits == canonicalResourceLimits do
    throw <| .planInvariant .near "NEAR Plan descriptor/schema/profile policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .near s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > plan.resourceLimits.maxArtifactStemBytes then
    throw <| .planInvariant .near
      s!"program name exceeds artifact-stem limit {plan.resourceLimits.maxArtifactStemBytes} bytes"
  unless Plan.hasValidInvariantErasureBindingV1 plan do
    throw <| .planInvariant .near
      "NEAR invariant-erasure decision is missing or diverges from its capability-derived Plan binding"
  match plan.invariantErasure? with
  | none => pure ()
  | some decision => validateInvariantErasureDecisionV1 plan decision
  validateStorageLayout plan.resourceLimits plan.storage
  if plan.entries.isEmpty || plan.entries.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .near "entry count is outside the profile limits"
  if plan.fns.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .near "pureFn count is outside the profile limits"
  let handlerCount := 1 + plan.entries.size + plan.fns.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total method => total + method.params.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total method => total + method.body.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.body.size) 0
  let mut total := plan.storage.fields.size + handlerCount + paramCount + statementCount
  if total > plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .near
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
    throw <| .planInvariant .near "NEAR export names must be unique"
  if hasDuplicates (plan.fns.map (·.name)) then
    throw <| .planInvariant .near "NEAR pureFn names must be unique"
  let exportAndFnNames := methods.map (·.name) ++ plan.fns.map (·.name)
  if hasDuplicates exportAndFnNames then
    throw <| .planInvariant .near "NEAR export and pureFn names must not collide"




end ProofForgeV2.Targets.Near
