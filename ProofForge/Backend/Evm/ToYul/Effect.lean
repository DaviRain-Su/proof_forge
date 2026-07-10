import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Backend.Evm.ToYul.Create
import ProofForge.Backend.Evm.ToYul.Crosscall
import ProofForge.Backend.Evm.ToYul.Helpers
import ProofForge.Backend.Evm.ToYul.Local
import ProofForge.Backend.Evm.ToYul.Abi
import ProofForge.Backend.Evm.ToYul.AbiEncode
import ProofForge.Backend.Evm.ToYul.Event
import ProofForge.Compiler.Yul.AST

/-! # EVM plan-driven Yul lowering

Expression, statement, and effect-plan lowering from semantic `Plan` nodes into
Yul AST nodes. `ToYul.lean` imports this module as the public facade.
-/

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

/-- EVM `userIdHash`: identity-width digest of `msg.sender`.
Uses the existing `hashWord` helper (`mstore(0, value); keccak256(0, 32)`), so
the value is a true Hash word distinct from raw address-width `caller`. -/
def userIdHashYulExpr : Lean.Compiler.Yul.Expr :=
  helperCall Helper.hashWord #[Lean.Compiler.Yul.builtin "caller" #[]]

def contextFieldExpr
    (lowerExpr : Expr → Except String Lean.Compiler.Yul.Expr) :
    ContextField → Except String Lean.Compiler.Yul.Expr
  | .userId => .ok (Lean.Compiler.Yul.builtin "caller" #[])
  | .userIdHash => .ok userIdHashYulExpr
  | .contractId => .ok (Lean.Compiler.Yul.builtin "address" #[])
  | .checkpointId => .ok (Lean.Compiler.Yul.builtin "number" #[])
  | .timestamp => .ok (Lean.Compiler.Yul.builtin "timestamp" #[])
  | .epochHeight => .error "EVM context read `epochHeight` is not supported; EVM has no epoch-height opcode"
  | .chainId => .ok (Lean.Compiler.Yul.builtin "chainid" #[])
  | .gasPrice => .ok (Lean.Compiler.Yul.builtin "gasprice" #[])
  | .gasLeft => .ok (Lean.Compiler.Yul.builtin "gas" #[])
  | .baseFee => .ok (Lean.Compiler.Yul.builtin "basefee" #[])
  | .prevRandao => .ok (Lean.Compiler.Yul.builtin "prevrandao" #[])
  | .randomSeed => .error "EVM context read `randomSeed` is not supported; use prevRandao for the EVM prevrandao opcode"
  | .origin => .ok (Lean.Compiler.Yul.builtin "origin" #[])
  | .coinbase => .ok (Lean.Compiler.Yul.builtin "coinbase" #[])
  | .blockHash blockNumber => do
      .ok (Lean.Compiler.Yul.builtin "blockhash" #[← lowerExpr blockNumber])

partial def contextExprPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    ContextExprPlan → Except ε Lean.Compiler.Yul.Expr
  | .userId => .ok (Lean.Compiler.Yul.builtin "caller" #[])
  | .userIdHash => .ok userIdHashYulExpr
  | .contractId => .ok (Lean.Compiler.Yul.builtin "address" #[])
  | .checkpointId => .ok (Lean.Compiler.Yul.builtin "number" #[])
  | .timestamp => .ok (Lean.Compiler.Yul.builtin "timestamp" #[])
  | .chainId => .ok (Lean.Compiler.Yul.builtin "chainid" #[])
  | .gasPrice => .ok (Lean.Compiler.Yul.builtin "gasprice" #[])
  | .gasLeft => .ok (Lean.Compiler.Yul.builtin "gas" #[])
  | .baseFee => .ok (Lean.Compiler.Yul.builtin "basefee" #[])
  | .prevRandao => .ok (Lean.Compiler.Yul.builtin "prevrandao" #[])
  | .origin => .ok (Lean.Compiler.Yul.builtin "origin" #[])
  | .coinbase => .ok (Lean.Compiler.Yul.builtin "coinbase" #[])
  | .blockHash blockNumber => do
      .ok (Lean.Compiler.Yul.builtin "blockhash" #[← lowerPlanExpr blockNumber])

def hashPackExpr
    (a b c d : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "or" #[
    Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 192, a],
    Lean.Compiler.Yul.builtin "or" #[
      Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 128, b],
      Lean.Compiler.Yul.builtin "or" #[
        Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 64, c],
        d
      ]
    ]
  ]

def lowerValuePlan
    {ε : Type}
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    ValuePlan → Except ε Lean.Compiler.Yul.Expr
  | .irExpr expr => lowerExpr expr

def lowerMapValueSlotExpr
    {ε : Type}
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ValuePlan) : Except ε Lean.Compiler.Yul.Expr := do
  let mut current := slotExpr rootSlot
  for key in keys do
    current := helperCall Helper.mapSlot #[current, ← lowerValuePlan lowerExpr key]
  .ok current

def lowerMapPresenceSlotExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ValuePlan) : Except ε Lean.Compiler.Yul.Expr := do
  match keys.toList.reverse with
  | [] => .error (mkError "EVM map presence slot plan requires at least one key")
  | last :: parentKeysReversed =>
      let mut parent := slotExpr rootSlot
      for key in parentKeysReversed.reverse do
        parent := helperCall Helper.mapSlot #[parent, ← lowerValuePlan lowerExpr key]
      .ok (helperCall Helper.mapPresenceSlot #[parent, ← lowerValuePlan lowerExpr last])

def storageSlotExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    StorageSlotPlan → Except ε Lean.Compiler.Yul.Expr
  | .scalarSlot slot => .ok (slotExpr slot)
  | .fixedSlot slotHex => .ok (Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex slotHex))
  | .mapValueSlot rootSlot keys =>
      if keys.isEmpty then
        .error (mkError "EVM map value slot plan requires at least one key")
      else
        lowerMapValueSlotExpr lowerExpr rootSlot keys
  | .mapPresenceSlot rootSlot keys =>
      lowerMapPresenceSlotExpr mkError lowerExpr rootSlot keys
  | .arraySlot rootSlot length index => do
      .ok (helperCall Helper.arraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        ← lowerValuePlan lowerExpr index
      ])
  | .structArrayFieldSlot rootSlot length fieldCount fieldOffset index => do
      .ok (helperCall Helper.structArraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        Lean.Compiler.Yul.Expr.num fieldCount,
        Lean.Compiler.Yul.Expr.num fieldOffset,
        ← lowerValuePlan lowerExpr index
      ])
  | .dynamicArraySlot rootSlot index => do
      .ok (helperCall Helper.dynamicArraySlot #[
        slotExpr rootSlot,
        ← lowerValuePlan lowerExpr index
      ])

def lowerMapValueSlotExprPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let mut current := slotExpr rootSlot
  for key in keys do
    current := helperCall Helper.mapSlot #[current, ← lowerPlanExpr key]
  .ok current

def lowerMapPresenceSlotExprPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  match keys.toList.reverse with
  | [] => .error (mkError "EVM map presence slot plan requires at least one key")
  | last :: parentKeysReversed =>
      let mut parent := slotExpr rootSlot
      for key in parentKeysReversed.reverse do
        parent := helperCall Helper.mapSlot #[parent, ← lowerPlanExpr key]
      .ok (helperCall Helper.mapPresenceSlot #[parent, ← lowerPlanExpr last])

def storageSlotExprPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StorageSlotExprPlan → Except ε Lean.Compiler.Yul.Expr
  | .scalarSlot slot => .ok (slotExpr slot)
  | .fixedSlot slotHex => .ok (Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex slotHex))
  | .mapValueSlot rootSlot keys =>
      if keys.isEmpty then
        .error (mkError "EVM map value slot plan requires at least one key")
      else
        lowerMapValueSlotExprPlan lowerPlanExpr rootSlot keys
  | .mapPresenceSlot rootSlot keys =>
      lowerMapPresenceSlotExprPlan mkError lowerPlanExpr rootSlot keys
  | .arraySlot rootSlot length index => do
      .ok (helperCall Helper.arraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        ← lowerPlanExpr index
      ])
  | .structArrayFieldSlot rootSlot length fieldCount fieldOffset index => do
      .ok (helperCall Helper.structArraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        Lean.Compiler.Yul.Expr.num fieldCount,
        Lean.Compiler.Yul.Expr.num fieldOffset,
        ← lowerPlanExpr index
      ])
  | .dynamicArraySlot rootSlot index => do
      .ok (helperCall Helper.dynamicArraySlot #[
        slotExpr rootSlot,
        ← lowerPlanExpr index
      ])

def storagePathReadExprFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (slot : StorageSlotPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr slot])

def storagePathReadExprFromExprPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (slot : StorageSlotExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExprPlan mkError lowerPlanExpr slot])

partial def exprPlanExprWithArithmeticWidths
    {ε : Type}
    (useNarrowArithmetic : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (plan : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let lowerPlan :=
    exprPlanExprWithArithmeticWidths useNarrowArithmetic mkError lowerExpr lowerEffect
  match plan with
  | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
  | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
  | .calldataWord paramIndex => .ok (calldataWordExpr paramIndex)
  | .storageLoad slot => do
      .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr slot])
  | .builtin name args => do
      .ok (Lean.Compiler.Yul.builtin name (← args.mapM lowerPlan))
  | .helperCall helper args => do
      .ok (helperCall helper (← args.mapM lowerPlan))
  | .checkedArith op lhs rhs overflowChecked resultByteWidth? => do
      let lhs ← lowerPlan lhs
      let rhs ← lowerPlan rhs
      if useNarrowArithmetic then
        match op with
        | .add | .sub | .mul =>
            match resultByteWidth? with
            | some byteWidth =>
                if byteWidth == 0 then
                  .error (mkError "EVM narrow scalar storage arithmetic plan has zero result byte width")
                else if byteWidth < 32 then
                  .ok (narrowArithExpr overflowChecked op byteWidth lhs rhs)
                else
                  .ok (arithExpr overflowChecked op lhs rhs)
            | none =>
                .error (mkError "EVM narrow scalar storage arithmetic plan is missing result byte width metadata")
        | .div | .mod | .bitAnd | .bitOr | .bitXor | .shiftLeft | .shiftRight =>
            .ok (arithExpr overflowChecked op lhs rhs)
      else
        .ok (arithExpr overflowChecked op lhs rhs)
  | .hashPack a b c d => do
      .ok (hashPackExpr
        (← lowerPlan a)
        (← lowerPlan b)
        (← lowerPlan c)
        (← lowerPlan d))
  | .context field =>
      contextExprPlan lowerPlan field
  | .crosscall mode target methodId callValue? args returnType =>
      crosscallExpandedExprPlanExpr
        mkError
        lowerPlan
        mode
        target
        methodId
        callValue?
        args
        returnType
  | .create mode callValue salt? initCodeHex => do
      createHelperCallExpr
        mkError
        mode
        (← lowerPlan callValue)
        (← salt?.mapM lowerPlan)
        initCodeHex
  | .cast source _ =>
      lowerPlan source
  | .structField base fieldName =>
      localStructFieldExpr
        mkError
        lowerPlan
        base
        fieldName
  | .arrayGet array index =>
      arrayGetExpr
        mkError
        lowerPlan
        array
        index
  | .memoryArrayNew _ length => do
      .ok (helperCall Helper.memoryArrayNew #[← lowerPlan length])
  | .memoryArrayLength array => do
      .ok (Lean.Compiler.Yul.builtin "mload" #[← lowerPlan array])
  | .memoryArrayGet array index => do
      .ok (helperCall Helper.memoryArrayGet #[
        ← lowerPlan array,
        ← lowerPlan index
      ])
  | .localArrayGet name path lengths =>
      localArrayGetExpr
        mkError
        lowerPlan
        name
        path
        lengths
  | .arrayLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support array literal plans yet")
  | .structLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support struct literal plans yet")
  | .hashValue a b c d => do
      .ok (hashPackExpr
        (← lowerPlan a)
        (← lowerPlan b)
        (← lowerPlan c)
        (← lowerPlan d))
  | .hash preimage => do
      .ok (helperCall Helper.hashWord #[← lowerPlan preimage])
  | .hashTwoToOne lhs rhs => do
      .ok (helperCall Helper.hashPair #[
        ← lowerPlan lhs,
        ← lowerPlan rhs
      ])
  | .ecrecover digest v r s => do
      .ok (helperCall Helper.ecrecover #[
        ← lowerPlan digest,
        ← lowerPlan v,
        ← lowerPlan r,
        ← lowerPlan s
      ])
  | .eip712PermitDigest owner spender value nonce deadline domainSep => do
      .ok (helperCall Helper.eip712PermitDigest #[
        ← lowerPlan owner,
        ← lowerPlan spender,
        ← lowerPlan value,
        ← lowerPlan nonce,
        ← lowerPlan deadline,
        ← lowerPlan domainSep
      ])
  | .crosscallAbiPacked target selector stores argsSize outSize dynLenOffset? dynLen?
      dynTargetOffsets dynTargets => do
      let targetYul ← lowerPlan target
      let spec : ProofForge.Backend.Evm.Plan.AbiPackedHelperSpec :=
        { selector := selector, stores := stores, argsSize := argsSize, outSize := outSize,
          dynLenOffset? := dynLenOffset?, dynTargetOffsets := dynTargetOffsets }
      let nYul ←
        match dynLen? with
        | none => pure none
        | some len => .ok (some (← lowerPlan len))
      let tgtYul ← dynTargets.mapM lowerPlan
      .ok (ProofForge.Backend.Evm.ToYul.AbiEncode.abiPackedHelperCallExpr targetYul spec nYul tgtYul)
  | .nativeValue =>
      .ok (Lean.Compiler.Yul.builtin "callvalue" #[])
  | .effect effect =>
      lowerEffect effect

def exprPlanExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    ExprPlan → Except ε Lean.Compiler.Yul.Expr :=
  exprPlanExprWithArithmeticWidths false mkError lowerExpr lowerEffect

def narrowStorageExprPlanExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    ExprPlan → Except ε Lean.Compiler.Yul.Expr :=
  exprPlanExprWithArithmeticWidths true mkError lowerExpr lowerEffect

/-! ## StmtPlan-to-Yul helpers -/

def stmtPlanBodyStatements
    {err state : Type}
    (plans : Array StmtPlan)
    (initialState : state)
    (leaveAfterReturn : Bool)
    (lowerStmt : state → Bool → StmtPlan → Except err (Array Lean.Compiler.Yul.Statement × state)) :
    Except err (Array Lean.Compiler.Yul.Statement × state) := do
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  let mut currentState := initialState
  for h : idx in [0:plans.size] do
    let stmtLeaveAfterReturn := leaveAfterReturn || decide (idx + 1 < plans.size)
    let (lowered, nextState) ← lowerStmt currentState stmtLeaveAfterReturn plans[idx]
    statements := statements ++ lowered
    currentState := nextState
  .ok (statements, currentState)

def scalarBindingStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .letBind name _ value
  | .letMutBind name _ value => do
      .ok #[
        .varDecl
          #[({ name := name } : Lean.Compiler.Yul.TypedName)]
          (some (← exprPlanExpr mkError lowerExpr lowerEffect value))
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar binding lowering expected a let binding")

def assertStatementFromCondition
    (condition : Lean.Compiler.Yul.Expr)
    (revertStatements : Array Lean.Compiler.Yul.Statement) :
    Lean.Compiler.Yul.Statement :=
  Lean.Compiler.Yul.Statement.ifStmt
    (Lean.Compiler.Yul.builtin "iszero" #[condition])
    { statements := revertStatements }

def scalarAssertStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (revertStatementsFor : Option ProofForge.IR.ErrorRef → Except ε (Array Lean.Compiler.Yul.Statement)) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .assert condition _ errorRef? => do
      .ok #[
        assertStatementFromCondition
          (← exprPlanExpr mkError lowerExpr lowerEffect condition)
          (← revertStatementsFor errorRef?)
      ]
  | .assertEq lhs rhs _ errorRef? => do
      let lhsExpr ← exprPlanExpr mkError lowerExpr lowerEffect lhs
      let rhsExpr ← exprPlanExpr mkError lowerExpr lowerEffect rhs
      .ok #[
        assertStatementFromCondition
          (Lean.Compiler.Yul.builtin "eq" #[lhsExpr, rhsExpr])
          (← revertStatementsFor errorRef?)
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar assertion lowering expected assert/assertEq")

def revertStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (revertStatementsFor : ProofForge.IR.ErrorRef → Except ε (Array Lean.Compiler.Yul.Statement)) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .revert message =>
      if message.isEmpty then
        .ok #[revertStatement]
      else
        .ok (revertWithMessageStatements message)
  | .revertWithError errorRef =>
      revertStatementsFor errorRef
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul revert lowering expected revert/revertWithError")

def scalarReturnStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (returnNames : Array String)
    (leaveAfterReturn : Bool) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .return value => do
      let some returnName := returnNames[0]?
        | .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected one return name, got 0")
      if returnNames.size != 1 then
        .error (mkError s!"EVM StmtPlan-to-Yul scalar return lowering expected one return name, got {returnNames.size}")
      else
        let statements := #[
          Lean.Compiler.Yul.Statement.assignment
            #[returnName]
            (← exprPlanExpr mkError lowerExpr lowerEffect value)
        ]
        .ok <| if leaveAfterReturn then statements.push .leave else statements
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected return")

def scalarReturnExprPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (returnNames : Array String)
    (leaveAfterReturn : Bool) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .return value => do
      let some returnName := returnNames[0]?
        | .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected one return name, got 0")
      if returnNames.size != 1 then
        .error (mkError s!"EVM StmtPlan-to-Yul scalar return lowering expected one return name, got {returnNames.size}")
      else
        let statements := #[
          Lean.Compiler.Yul.Statement.assignment
            #[returnName]
            (← lowerPlanExpr value)
        ]
        .ok <| if leaveAfterReturn then statements.push .leave else statements
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected return")

def dynamicReturnStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (returns : ReturnPlan)
    (leaveAfterReturn : Bool) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .return (.local name) => do
      match returns.returnType with
      | .bytes | .string | .array _ =>
          let some returnName := returns.localNames[0]?
            | .error (mkError "EVM StmtPlan-to-Yul dynamic return lowering expected one return name, got 0")
          if returns.localNames.size != 1 then
            .error (mkError s!"EVM StmtPlan-to-Yul dynamic return lowering expected one return name, got {returns.localNames.size}")
          else
            let statements := #[
              Lean.Compiler.Yul.Statement.assignment
                #[returnName]
                (Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName name))
            ]
            .ok <| if leaveAfterReturn then statements.push .leave else statements
      | _ =>
          .error (mkError s!"EVM StmtPlan-to-Yul dynamic return lowering expected a dynamic return type, got `{returns.returnType.name}`")
  | .return _ =>
      .error (mkError "EVM StmtPlan-to-Yul dynamic return lowering supports local dynamic values only")
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul dynamic return lowering expected return")

def scalarAssignmentTargetName
    {ε : Type}
    (mkError : String → ε) : ExprPlan → Except ε String
  | .local targetName =>
      .ok targetName
  | .localArrayGet name path lengths => do
      let some staticPath := localArrayStaticPath? path
        | .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected a static local-array target")
      validateLocalArrayStaticPath mkError name staticPath lengths
      .ok (arrayLocalPathName name staticPath)
  | .structField (.local name) fieldName =>
      .ok (structLocalFieldName name fieldName)
  | .structField (.localArrayGet name path lengths) fieldName => do
      let some staticPath := localArrayStaticPath? path
        | .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected a static local-array struct-field target")
      validateLocalArrayStaticPath mkError name staticPath lengths
      .ok (arrayStructLocalPathFieldName name staticPath fieldName)
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected a local, static local-array, or static struct-field target")

def scalarAssignmentStmtPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .assign target value => do
      let targetName ← scalarAssignmentTargetName mkError target
      .ok #[
        Lean.Compiler.Yul.Statement.assignment
          #[targetName]
          (← exprPlanExpr mkError lowerExpr lowerEffect value)
      ]
  | .assignOp target op value => do
      let targetName ← scalarAssignmentTargetName mkError target
      .ok #[
        Lean.Compiler.Yul.Statement.assignment
          #[targetName]
          (arithExpr overflowChecked op
            (Lean.Compiler.Yul.Expr.id targetName)
            (← exprPlanExpr mkError lowerExpr lowerEffect value))
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected assign/assignOp")

structure FixedArrayAssignmentSource where
  index : Nat
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

structure StructArrayAssignmentSource where
  index : Nat
  fieldName : String
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

structure NestedFixedArrayAssignmentSource where
  path : Array Nat
  fieldName? : Option String
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

structure StructAssignmentSource where
  fieldName : String
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

def aggregateAssignArrayTempName (name : String) (index : Nat) : String :=
  s!"__proof_forge_assign_array_{name}_{index}"

def aggregateAssignArrayPathTempName (name : String) (path : Array Nat) : String :=
  s!"__proof_forge_assign_array_{name}_{natPathSuffix path}"

def aggregateAssignStructTempName (name fieldName : String) : String :=
  s!"__proof_forge_assign_struct_{name}_{fieldName}"

def aggregateAssignStructArrayTempName (name : String) (index : Nat) (fieldName : String) : String :=
  s!"__proof_forge_assign_array_struct_{name}_{index}_{fieldName}"

def nestedFixedArrayTargetName (name : String) (path : Array Nat) (fieldName? : Option String) : String :=
  match fieldName? with
  | none => arrayLocalPathName name path
  | some fieldName => arrayStructLocalPathFieldName name path fieldName

def aggregateAssignNestedFixedArrayTempName (name : String) (path : Array Nat) (fieldName? : Option String) : String :=
  match fieldName? with
  | none => aggregateAssignArrayPathTempName name path
  | some fieldName => s!"__proof_forge_assign_array_struct_{name}_{natPathSuffix path}_{fieldName}"

def fixedArrayAssignmentStatements
    (name : String)
    (sources : Array FixedArrayAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl #[{ name := aggregateAssignArrayTempName name source.index }] (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[arrayLocalElementName name source.index]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignArrayTempName name source.index))
    statements

def wholeFixedArrayAssignStmt
    (name : String)
    (sources : Array FixedArrayAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := fixedArrayAssignmentStatements name sources }

def fixedArrayAssignmentSourceFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (source : FixedArrayAssignmentSourcePlan) :
    Except ε FixedArrayAssignmentSource := do
  .ok {
    index := source.index
    expr := ← lowerPlanExpr source.expr
  }

def wholeFixedArrayAssignStmtFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (sources : Array FixedArrayAssignmentSourcePlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  .ok <| wholeFixedArrayAssignStmt name (← sources.mapM (fixedArrayAssignmentSourceFromPlan lowerPlanExpr))

def structArrayAssignmentStatements
    (name : String)
    (sources : Array StructArrayAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl #[{ name := aggregateAssignStructArrayTempName name source.index source.fieldName }] (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[arrayStructLocalFieldName name source.index source.fieldName]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignStructArrayTempName name source.index source.fieldName))
    statements

def wholeStructArrayAssignStmt
    (name : String)
    (sources : Array StructArrayAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := structArrayAssignmentStatements name sources }

def structArrayAssignmentSourceFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (source : StructArrayAssignmentSourcePlan) :
    Except ε StructArrayAssignmentSource := do
  .ok {
    index := source.index,
    fieldName := source.fieldName,
    expr := ← lowerPlanExpr source.expr
  }

def wholeStructArrayAssignStmtFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (sources : Array StructArrayAssignmentSourcePlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  .ok <| wholeStructArrayAssignStmt name (← sources.mapM (structArrayAssignmentSourceFromPlan lowerPlanExpr))

def nestedFixedArrayAssignmentStatements
    (name : String)
    (sources : Array NestedFixedArrayAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl
          #[{ name := aggregateAssignNestedFixedArrayTempName name source.path source.fieldName? }]
          (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[nestedFixedArrayTargetName name source.path source.fieldName?]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignNestedFixedArrayTempName name source.path source.fieldName?))
    statements

def wholeNestedFixedArrayAssignStmt
    (name : String)
    (sources : Array NestedFixedArrayAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := nestedFixedArrayAssignmentStatements name sources }

def nestedFixedArrayAssignmentSourceFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (source : NestedFixedArrayAssignmentSourcePlan) :
    Except ε NestedFixedArrayAssignmentSource := do
  .ok {
    path := source.path,
    fieldName? := source.fieldName?,
    expr := ← lowerPlanExpr source.expr
  }

def wholeNestedFixedArrayAssignStmtFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (sources : Array NestedFixedArrayAssignmentSourcePlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  .ok <| wholeNestedFixedArrayAssignStmt name (← sources.mapM (nestedFixedArrayAssignmentSourceFromPlan lowerPlanExpr))

def structAssignmentStatements
    (name : String)
    (sources : Array StructAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl #[{ name := aggregateAssignStructTempName name source.fieldName }] (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[structLocalFieldName name source.fieldName]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignStructTempName name source.fieldName))
    statements

def wholeStructAssignStmt
    (name : String)
    (sources : Array StructAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := structAssignmentStatements name sources }

def structAssignmentSourceFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (source : StructAssignmentSourcePlan) :
    Except ε StructAssignmentSource := do
  .ok {
    fieldName := source.fieldName
    expr := ← lowerPlanExpr source.expr
  }

def wholeStructAssignStmtFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (sources : Array StructAssignmentSourcePlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  .ok <| wholeStructAssignStmt name (← sources.mapM (structAssignmentSourceFromPlan lowerPlanExpr))

def dynamicArrayIndexLocalName : String := "__proof_forge_array_index"

def dynamicArrayValueLocalName : String := "__proof_forge_array_value"

def dynamicArrayIndexPathLocalName (depth : Nat) : String :=
  s!"__proof_forge_array_index_{depth}"

def dynamicArrayValueExpr : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName

def dynamicAssignmentRhs
    (targetName : String)
    (op? : Option AssignOp) : Lean.Compiler.Yul.Expr :=
  match op? with
  | some op => checkedArithExpr op (Lean.Compiler.Yul.Expr.id targetName) dynamicArrayValueExpr
  | none => dynamicArrayValueExpr

def dynamicAssignmentStatement
    (targetName : String)
    (op? : Option AssignOp) : Lean.Compiler.Yul.Statement :=
  .assignment #[targetName] (dynamicAssignmentRhs targetName op?)

def dynamicLocalSwitchCase
    (index : Nat)
    (statements : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Case := {
  value := some (Lean.Compiler.Yul.Literal.natLit index)
  body := { statements }
}

def dynamicLocalSwitchDefaultCase : Lean.Compiler.Yul.Case := {
  value := none
  body := { statements := #[revertStatement] }
}

def dynamicLocalFixedArraySwitchCases
    (length : Nat)
    (bodyForIndex : Nat → Array Lean.Compiler.Yul.Statement) : Array Lean.Compiler.Yul.Case :=
  Id.run do
    let mut cases : Array Lean.Compiler.Yul.Case := #[]
    for _h : idx in [0:length] do
      cases := cases.push (dynamicLocalSwitchCase idx (bodyForIndex idx))
    cases.push dynamicLocalSwitchDefaultCase

def dynamicLocalValueSwitchBlock
    (indexExpr valueExpr : Lean.Compiler.Yul.Expr)
    (length : Nat)
    (bodyForIndex : Nat → Array Lean.Compiler.Yul.Statement) :
    Lean.Compiler.Yul.Statement :=
  .block {
    statements := #[
      .varDecl #[{ name := dynamicArrayIndexLocalName }] (some indexExpr),
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr),
      .switchStmt
        (Lean.Compiler.Yul.Expr.id dynamicArrayIndexLocalName)
        (dynamicLocalFixedArraySwitchCases length bodyForIndex)
    ]
  }

def dynamicLocalPathSwitchBlock
    (depth : Nat)
    (indexExpr : Lean.Compiler.Yul.Expr)
    (cases : Array Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  let indexName := dynamicArrayIndexPathLocalName depth
  .block {
    statements := #[
      .varDecl #[{ name := indexName }] (some indexExpr),
      .switchStmt (Lean.Compiler.Yul.Expr.id indexName) cases
    ]
  }

def dynamicLocalValueBlock
    (valueExpr : Lean.Compiler.Yul.Expr)
    (body : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Statement :=
  .block {
    statements := #[
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr)
    ] ++ body
  }

def dynamicAggregateAssignmentLeafName
    (name : String) (pathPrefix : Array Nat) (fieldName? : Option String) : String :=
  match fieldName? with
  | some fieldName => arrayStructLocalPathFieldName name pathPrefix fieldName
  | none => arrayLocalPathName name pathPrefix

def dynamicAggregateScalarAssignmentTarget?
    (target : ExprPlan) : Option (String × Array ExprPlan × Array Nat × Option String) :=
  match target with
  | .localArrayGet name path lengths =>
      some (name, path, lengths, none)
  | .structField (.localArrayGet name path lengths) fieldName =>
      some (name, path, lengths, some fieldName)
  | _ =>
      none

partial def dynamicAggregateAssignmentPathBody
    {ε : Type}
    (mkError : String → ε)
    (lowerPlan : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (pathPlans : Array ExprPlan)
    (lengths : Array Nat)
    (pathPrefix : Array Nat)
    (fieldName? : Option String)
    (op? : Option AssignOp) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  if pathPrefix.size == pathPlans.size then
    let targetName := dynamicAggregateAssignmentLeafName name pathPrefix fieldName?
    .ok #[dynamicAssignmentStatement targetName op?]
  else
    let depth := pathPrefix.size
    let some length := lengths[depth]?
      | .error (mkError s!"EVM StmtPlan-to-Yul dynamic aggregate assignment missing length at path depth {depth}")
    let some indexPlan := pathPlans[depth]?
      | .error (mkError s!"EVM StmtPlan-to-Yul dynamic aggregate assignment missing path index at depth {depth}")
    match indexPlan with
    | .literalWord indexValue =>
        if indexValue >= length then
          .error (mkError s!"EVM StmtPlan-to-Yul dynamic aggregate assignment index {indexValue} is out of bounds for length {length}")
        else
          dynamicAggregateAssignmentPathBody
            mkError
            lowerPlan
            name
            pathPlans
            lengths
            (pathPrefix.push indexValue)
            fieldName?
            op?
    | _ =>
        let indexExpr ← lowerPlan indexPlan
        let mut cases : Array Lean.Compiler.Yul.Case := #[]
        for _h : idx in [0:length] do
          cases := cases.push <|
            dynamicLocalSwitchCase idx
              (← dynamicAggregateAssignmentPathBody
                mkError
                lowerPlan
                name
                pathPlans
                lengths
                (pathPrefix.push idx)
                fieldName?
                op?)
        cases := cases.push dynamicLocalSwitchDefaultCase
        .ok #[dynamicLocalPathSwitchBlock depth indexExpr cases]

def dynamicAggregateScalarAssignmentFromTarget
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target value : ExprPlan)
    (op? : Option AssignOp) : Except ε (Array Lean.Compiler.Yul.Statement) := do
  let some (name, pathPlans, lengths, fieldName?) := dynamicAggregateScalarAssignmentTarget? target
    | .error (mkError "EVM StmtPlan-to-Yul dynamic aggregate assignment lowering expected a dynamic local-array or struct-array field target")
  if (localArrayStaticPath? pathPlans).isSome then
    .error (mkError "EVM StmtPlan-to-Yul dynamic aggregate assignment lowering expected a dynamic local-array path")
  let lowerPlan := fun plan => exprPlanExpr mkError lowerExpr lowerEffect plan
  let valueExpr ← lowerPlan value
  match pathPlans with
  | #[indexPlan] =>
      match indexPlan with
      | .literalWord _ =>
          let body ←
            dynamicAggregateAssignmentPathBody
              mkError
              lowerPlan
              name
              pathPlans
              lengths
              #[]
              fieldName?
              op?
          .ok #[dynamicLocalValueBlock valueExpr body]
      | _ => do
          let indexExpr ← lowerPlan indexPlan
          let some length := lengths[0]?
            | .error (mkError "EVM StmtPlan-to-Yul dynamic aggregate assignment missing array length")
          .ok #[
            dynamicLocalValueSwitchBlock
              indexExpr
              valueExpr
              length
              (fun idx =>
                #[dynamicAssignmentStatement (dynamicAggregateAssignmentLeafName name #[idx] fieldName?) op?])
          ]
  | _ =>
    do
      let body ←
        dynamicAggregateAssignmentPathBody
          mkError
          lowerPlan
          name
          pathPlans
          lengths
          #[]
          fieldName?
          op?
      .ok #[dynamicLocalValueBlock valueExpr body]

def dynamicAggregateScalarAssignmentStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .assign target value =>
      dynamicAggregateScalarAssignmentFromTarget mkError lowerExpr lowerEffect target value none
  | .assignOp target op value =>
      dynamicAggregateScalarAssignmentFromTarget mkError lowerExpr lowerEffect target value (some op)
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul dynamic aggregate assignment lowering expected assign/assignOp")

def ifElseStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (thenStatements elseStatements : Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .ifElse condition _ _ => do
      .ok #[
        .switchStmt
          (← exprPlanExpr mkError lowerExpr lowerEffect condition)
          #[
            {
              value := some (Lean.Compiler.Yul.Literal.natLit 0)
              body := { statements := elseStatements }
            },
            {
              value := none
              body := { statements := thenStatements }
            }
          ]
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul ifElse lowering expected ifElse")

def boundedForConditionPlan (indexName : String) (stopExclusive : Nat) : ExprPlan :=
  .builtin "lt" #[.local indexName, .literalWord stopExclusive]

def boundedForStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .boundedFor indexName start stopExclusive _ => do
      if stopExclusive <= start then
        .error (mkError s!"bounded loop `{indexName}` must have stop greater than start")
      else
        .ok #[
          .forLoop
            { statements := #[
              .varDecl #[{ name := indexName }] (some (Lean.Compiler.Yul.Expr.num start))
            ] }
            (← exprPlanExpr mkError lowerExpr lowerEffect
              (boundedForConditionPlan indexName stopExclusive))
            { statements := #[
              .assignment #[indexName]
                (Lean.Compiler.Yul.builtin "add" #[
                  Lean.Compiler.Yul.Expr.id indexName,
                  Lean.Compiler.Yul.Expr.num 1
                ])
            ] }
            { statements := bodyStatements }
        ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul boundedFor lowering expected boundedFor")

/-- Lower the fixed-size ERC-1155 batch receiver check from its semantic
`EffectPlan`. Keeping expression lowering behind this boundary prevents the
legacy effect facade from rendering raw IR arguments directly. -/
def erc1155BatchReceiverEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExprPlan : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .checkErc1155BatchReceived operator fromAddr toAddr id0 amount0 id1 amount1 => do
      let args ←
        #[operator, fromAddr, toAddr, id0, amount0, id1, amount1].mapM lowerExprPlan
      match args with
      | #[operatorYul, fromYul, toYul, id0Yul, amount0Yul, id1Yul, amount1Yul] =>
          .ok (checkErc1155BatchReceivedStatements
            operatorYul fromYul toYul id0Yul amount0Yul id1Yul amount1Yul)
      | _ =>
          .error (mkError "EVM ERC-1155 batch receiver plan must lower exactly seven arguments")
  | _ =>
      .error (mkError "EVM ERC-1155 batch receiver lowering expected checkErc1155BatchReceived")

end ProofForge.Backend.Evm.ToYul
