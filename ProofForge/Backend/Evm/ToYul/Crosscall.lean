import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def maxU32 : Nat := 4294967295

def crosscallReturnTypeSuffix {ε : Type} (mkError : String → ε) : ValueType → Except ε String
  | .u64 => .ok ""
  | .u32 => .ok "_u32"
  | .bool => .ok "_bool"
  | .hash => .ok "_hash"
  | .u8 => .ok "_u8"
  | .u128 => .ok "_u128"
  | .address => .ok "_address"
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error (mkError "crosscall return type must be U32, U64, Bool, or Hash in IR EVM v0")

def crosscallFunctionName {ε : Type} (mkError : String → ε) (arity : Nat) (returnType : ValueType) :
    Except ε String := do
  .ok s!"__proof_forge_crosscall_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallValueFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (returnType : ValueType)
    (plainTransfer : Bool := false) : Except ε String := do
  if plainTransfer then
    .ok s!"__proof_forge_native_transfer{← crosscallReturnTypeSuffix mkError returnType}"
  else
    .ok s!"__proof_forge_crosscall_value_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallStaticFunctionName {ε : Type} (mkError : String → ε) (arity : Nat) (returnType : ValueType) :
    Except ε String := do
  .ok s!"__proof_forge_crosscall_static_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallDelegateFunctionName {ε : Type} (mkError : String → ε) (arity : Nat) (returnType : ValueType) :
    Except ε String := do
  .ok s!"__proof_forge_crosscall_delegate_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallReturnWordTag {ε : Type} (mkError : String → ε) : ValueType → Except ε String
  | .u64 => .ok "u64"
  | .u32 => .ok "u32"
  | .bool => .ok "bool"
  | .hash => .ok "hash"
  | .u8 => .ok "u8"
  | .u128 => .ok "u128"
  | .address => .ok "address"
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error (mkError "crosscall aggregate return words must be U32, U64, Bool, or Hash in IR EVM v0")

def crosscallReturnWordTagsSuffix
    {ε : Type}
    (mkError : String → ε)
    (wordTypes : Array ValueType) : Except ε String := do
  let mut suffix := ""
  for wordType in wordTypes do
    suffix := suffix ++ "_" ++ (← crosscallReturnWordTag mkError wordType)
  .ok suffix

def crosscallAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType) : Except ε String := do
  .ok s!"__proof_forge_crosscall_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallValueAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType)
    (plainTransfer : Bool := false) : Except ε String := do
  if plainTransfer then
    .error (mkError "plain native transfer does not support aggregate crosscall returns in IR EVM v0")
  else
    .ok s!"__proof_forge_crosscall_value_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallStaticAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType) : Except ε String := do
  .ok s!"__proof_forge_crosscall_static_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallDelegateAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType) : Except ε String := do
  .ok s!"__proof_forge_crosscall_delegate_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallReturnIsScalarWord : ValueType → Bool
  | .u8 | .u64 | .u32 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

def crosscallModeForwardsValue : CrosscallMode → Bool
  | .callValue => true
  | .call | .staticcall | .delegatecall => false

def crosscallArgName (idx : Nat) : String :=
  s!"arg{idx}"

def crosscallCallValueName : String := "call_value"

def crosscallCalldataSize (arity : Nat) : Nat :=
  4 + arity * 32

def crosscallFunctionParams
    (arity : Nat)
    (mode : CrosscallMode)
    (plainTransfer : Bool := false) : Array Lean.Compiler.Yul.TypedName :=
  if plainTransfer then
    #[
      ({ name := "target" } : Lean.Compiler.Yul.TypedName),
      ({ name := crosscallCallValueName } : Lean.Compiler.Yul.TypedName)
    ]
  else
    let base := #[
      ({ name := "target" } : Lean.Compiler.Yul.TypedName),
      ({ name := "selector" } : Lean.Compiler.Yul.TypedName)
    ]
    let base :=
      if crosscallModeForwardsValue mode then
        base.push ({ name := crosscallCallValueName } : Lean.Compiler.Yul.TypedName)
      else
        base
    go 0 base
  where
    go (idx : Nat) (acc : Array Lean.Compiler.Yul.TypedName) : Array Lean.Compiler.Yul.TypedName :=
      if h : idx < arity then
        go (idx + 1) (acc.push ({ name := crosscallArgName idx } : Lean.Compiler.Yul.TypedName))
      else
        acc

def crosscallArgStoreStatements (arity : Nat) : Array Lean.Compiler.Yul.Statement :=
  go 0 #[]
where
  go (idx : Nat) (acc : Array Lean.Compiler.Yul.Statement) : Array Lean.Compiler.Yul.Statement :=
    if h : idx < arity then
      let store := Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num (4 + idx * 32),
          Lean.Compiler.Yul.Expr.id (crosscallArgName idx)
        ])
      go (idx + 1) (acc.push store)
    else
      acc

def crosscallReturnGuardStatementsForName
    {ε : Type}
    (mkError : String → ε)
    (resultName : String)
    (returnType : ValueType) : Except ε (Array Lean.Compiler.Yul.Statement) :=
  match returnType with
  | .u32 =>
      .ok #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id resultName, Lean.Compiler.Yul.Expr.num maxU32])
          { statements := #[revertStatement] }
      ]
  | .bool =>
      .ok #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id resultName, Lean.Compiler.Yul.Expr.num 1])
          { statements := #[revertStatement] }
      ]
  | .u8 | .u64 | .u128 | .hash | .address => .ok #[]
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error (mkError "crosscall return type must be U32, U64, Bool, or Hash in IR EVM v0")

def crosscallHelperReturnNames (wordCount : Nat) : Array Lean.Compiler.Yul.TypedName :=
  if wordCount == 1 then
    #[{ name := "result" }]
  else
    Id.run do
      let mut names : Array Lean.Compiler.Yul.TypedName := #[]
      for _h : idx in [0:wordCount] do
        names := names.push ({ name := s!"result{idx}" } : Lean.Compiler.Yul.TypedName)
      names

def crosscallHelperReturnNameStrings (wordCount : Nat) : Array String :=
  (crosscallHelperReturnNames wordCount).map fun name => name.name

def crosscallHelperFunctionName
    {ε : Type}
    (mkError : String → ε)
    (spec : CrosscallHelperSpec) : Except ε String := do
  match spec.mode, crosscallReturnIsScalarWord spec.returnType with
  | .call, true => crosscallFunctionName mkError spec.arity spec.returnType
  | .call, false => crosscallAggregateFunctionName mkError spec.arity spec.wordTypes
  | .callValue, true =>
      crosscallValueFunctionName mkError spec.arity spec.returnType spec.plainTransfer
  | .callValue, false =>
      crosscallValueAggregateFunctionName mkError spec.arity spec.wordTypes spec.plainTransfer
  | .staticcall, true => crosscallStaticFunctionName mkError spec.arity spec.returnType
  | .staticcall, false => crosscallStaticAggregateFunctionName mkError spec.arity spec.wordTypes
  | .delegatecall, true => crosscallDelegateFunctionName mkError spec.arity spec.returnType
  | .delegatecall, false => crosscallDelegateAggregateFunctionName mkError spec.arity spec.wordTypes

def crosscallCallExpr (spec : CrosscallHelperSpec) (outputSize : Nat) : Lean.Compiler.Yul.Expr :=
  let callValue :=
    if crosscallModeForwardsValue spec.mode then
      Lean.Compiler.Yul.Expr.id crosscallCallValueName
    else
      Lean.Compiler.Yul.Expr.num 0
  match spec.mode with
  | .call | .callValue =>
      Lean.Compiler.Yul.builtin "call" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        Lean.Compiler.Yul.Expr.id "target",
        callValue,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num outputSize
      ]
  | .staticcall =>
      Lean.Compiler.Yul.builtin "staticcall" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        Lean.Compiler.Yul.Expr.id "target",
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num outputSize
      ]
  | .delegatecall =>
      Lean.Compiler.Yul.builtin "delegatecall" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        Lean.Compiler.Yul.Expr.id "target",
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num outputSize
      ]

def crosscallPlainTransferHelperFunction
    {ε : Type}
    (mkError : String → ε)
    (spec : CrosscallHelperSpec)
    (functionName : String) : Except ε Lean.Compiler.Yul.Statement := do
  if spec.wordTypes.size != 1 then
    .error (mkError "plain native transfer expects a single-word return type in IR EVM v0")
  else
    let returnName := (crosscallHelperReturnNameStrings 1)[0]!
    .ok <| .funcDef functionName
      (crosscallFunctionParams spec.arity spec.mode true)
      (crosscallHelperReturnNames 1)
      {
        statements := #[
          .varDecl #[{ name := "_success" }] (some <|
            Lean.Compiler.Yul.builtin "call" #[
              Lean.Compiler.Yul.builtin "gas" #[],
              Lean.Compiler.Yul.Expr.id "target",
              Lean.Compiler.Yul.Expr.id crosscallCallValueName,
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num 0
            ]),
          .ifStmt
            (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_success"])
            { statements := #[revertStatement] },
          .assignment #[returnName] (Lean.Compiler.Yul.Expr.num 0)
        ]
      }

def crosscallHelperFunction
    {ε : Type}
    (mkError : String → ε)
    (spec : CrosscallHelperSpec) : Except ε Lean.Compiler.Yul.Statement := do
  if spec.wordTypes.isEmpty then
    .error (mkError s!"EVM CrosscallHelperSpec for `{spec.returnType.name}` has no return word layout")
  else
    let functionName ← crosscallHelperFunctionName mkError spec
    if spec.plainTransfer then
      crosscallPlainTransferHelperFunction mkError spec functionName
    else
      let outputSize := spec.wordTypes.size * 32
      let callExpr := crosscallCallExpr spec outputSize
      let returnNameStrings := crosscallHelperReturnNameStrings spec.wordTypes.size
      let mut copyAssignments : Array Lean.Compiler.Yul.Statement := #[]
      for h : idx in [0:spec.wordTypes.size] do
        copyAssignments := copyAssignments.push <|
          .assignment #[returnNameStrings[idx]!]
            (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num (idx * 32)])
      let mut guardStatements : Array Lean.Compiler.Yul.Statement := #[]
      for h : idx in [0:spec.wordTypes.size] do
        guardStatements := guardStatements ++
          (← crosscallReturnGuardStatementsForName mkError returnNameStrings[idx]! spec.wordTypes[idx])
      .ok <| .funcDef functionName
        (crosscallFunctionParams spec.arity spec.mode spec.plainTransfer)
        (crosscallHelperReturnNames spec.wordTypes.size)
        {
          statements :=
            #[
              .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.builtin "shl" #[
                  Lean.Compiler.Yul.Expr.num 224,
                  Lean.Compiler.Yul.Expr.id "selector"
                ]
              ])
            ] ++
            crosscallArgStoreStatements spec.arity ++
            #[
              .varDecl #[{ name := "_success" }] (some callExpr),
              .ifStmt
                (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_success"])
                { statements := #[revertStatement] },
              .ifStmt
                (Lean.Compiler.Yul.builtin "lt" #[
                  Lean.Compiler.Yul.builtin "returndatasize" #[],
                  Lean.Compiler.Yul.Expr.num outputSize
                ])
                { statements := #[revertStatement] },
              .exprStmt (Lean.Compiler.Yul.builtin "returndatacopy" #[
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.Expr.num outputSize
              ])
            ] ++
            copyAssignments ++
            guardStatements
        }

def crosscallScalarHelperSpec
    (mode : CrosscallMode)
    (arity : Nat)
    (returnType : ValueType)
    (plainTransfer : Bool := false) : CrosscallHelperSpec := {
  arity
  returnType
  wordTypes := #[returnType]
  mode
  plainTransfer
}

def crosscallAggregateHelperSpec
    (mode : CrosscallMode)
    (arity : Nat)
    (returnType : ValueType)
    (wordTypes : Array ValueType) : CrosscallHelperSpec := {
  arity
  returnType
  wordTypes
  mode
  plainTransfer := false
}

def crosscallScalarHelperCallExpr
    {ε : Type}
    (mkError : String → ε)
    (mode : CrosscallMode)
    (target methodId : Lean.Compiler.Yul.Expr)
    (callValue? : Option Lean.Compiler.Yul.Expr)
    (args : Array Lean.Compiler.Yul.Expr)
    (returnType : ValueType)
    (plainTransfer : Bool := false) : Except ε Lean.Compiler.Yul.Expr := do
  if !crosscallReturnIsScalarWord returnType then
    .error (mkError s!"EVM scalar crosscall helper call does not support aggregate return type `{returnType.name}`")
  else if plainTransfer && mode != .callValue then
    .error (mkError "plain native transfer helper calls must use callValue mode")
  else if plainTransfer && !args.isEmpty then
    .error (mkError "plain native transfer helper calls cannot include calldata arguments")
  else
    let functionName ←
      crosscallHelperFunctionName mkError
        (crosscallScalarHelperSpec mode args.size returnType plainTransfer)
    match mode, callValue? with
    | .callValue, some callValue =>
        if plainTransfer then
          .ok (Lean.Compiler.Yul.call functionName #[target, callValue])
        else
          .ok (Lean.Compiler.Yul.call functionName (#[target, methodId, callValue] ++ args))
    | .callValue, none =>
        .error (mkError "value-bearing crosscall helper calls require call value")
    | .call, none
    | .staticcall, none
    | .delegatecall, none =>
        .ok (Lean.Compiler.Yul.call functionName (#[target, methodId] ++ args))
    | .call, some _
    | .staticcall, some _
    | .delegatecall, some _ =>
        .error (mkError "non-value crosscall helper calls cannot include call value")

def crosscallAggregateHelperCallExpr
    {ε : Type}
    (mkError : String → ε)
    (mode : CrosscallMode)
    (target methodId : Lean.Compiler.Yul.Expr)
    (callValue? : Option Lean.Compiler.Yul.Expr)
    (args : Array Lean.Compiler.Yul.Expr)
    (returnType : ValueType)
    (wordTypes : Array ValueType) : Except ε Lean.Compiler.Yul.Expr := do
  if crosscallReturnIsScalarWord returnType then
    .error (mkError s!"EVM aggregate crosscall helper call requires an aggregate return type, got `{returnType.name}`")
  else if wordTypes.isEmpty then
    .error (mkError s!"EVM aggregate crosscall helper call for `{returnType.name}` has no return word layout")
  else
    let functionName ←
      crosscallHelperFunctionName mkError
        (crosscallAggregateHelperSpec mode args.size returnType wordTypes)
    match mode, callValue? with
    | .callValue, some callValue =>
        .ok (Lean.Compiler.Yul.call functionName (#[target, methodId, callValue] ++ args))
    | .callValue, none =>
        .error (mkError "value-bearing aggregate crosscall helper calls require call value")
    | .call, none
    | .staticcall, none
    | .delegatecall, none =>
        .ok (Lean.Compiler.Yul.call functionName (#[target, methodId] ++ args))
    | .call, some _
    | .staticcall, some _
    | .delegatecall, some _ =>
        .error (mkError "non-value aggregate crosscall helper calls cannot include call value")

def crosscallAggregateReturnAssignment
    {ε : Type}
    (mkError : String → ε)
    (returnNames : Array String)
    (mode : CrosscallMode)
    (target methodId : Lean.Compiler.Yul.Expr)
    (callValue? : Option Lean.Compiler.Yul.Expr)
    (args : Array Lean.Compiler.Yul.Expr)
    (returnType : ValueType)
    (wordTypes : Array ValueType) : Except ε Lean.Compiler.Yul.Statement := do
  if returnNames.size != wordTypes.size then
    .error (mkError s!"aggregate crosscall return assignment has {returnNames.size} target(s), expected {wordTypes.size}")
  else
    .ok <| .assignment returnNames
      (← crosscallAggregateHelperCallExpr
        mkError
        mode
        target
        methodId
        callValue?
        args
        returnType
        wordTypes)

partial def crosscallExpandedArgWordPlanExprs
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (plans : Array CrosscallArgWordPlan) : Except ε (Array Lean.Compiler.Yul.Expr) := do
  let mut words : Array Lean.Compiler.Yul.Expr := #[]
  for plan in plans do
    match plan with
    | .expr exprPlan =>
        words := words.push (← lowerPlanExpr exprPlan)
    | .local .. | .storage .. =>
        .error (mkError "EVM crosscall lowering expected pre-expanded argument word plans")
  .ok words

def crosscallAggregateReturnAssignmentExpandedPlanStatement
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (plan : CrosscallReturnAssignmentPlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  let target ← lowerPlanExpr plan.target
  let methodId ← lowerPlanExpr plan.methodId
  let callValue? ← plan.callValue?.mapM lowerPlanExpr
  let argWords ← crosscallExpandedArgWordPlanExprs mkError lowerPlanExpr plan.args
  crosscallAggregateReturnAssignment
    mkError
    plan.returns.localNames
    plan.mode
    target
    methodId
    callValue?
    argWords
    plan.returns.returnType
    plan.returns.wordTypes

partial def crosscallExpandedExprPlanExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (mode : CrosscallMode)
    (target methodId : ExprPlan)
    (callValue? : Option ExprPlan)
    (args : Array CrosscallArgWordPlan)
    (returnType : ValueType) : Except ε Lean.Compiler.Yul.Expr := do
  let targetExpr ← lowerPlanExpr target
  let methodIdExpr ← lowerPlanExpr methodId
  let callValueExpr? ← callValue?.mapM lowerPlanExpr
  let argExprs ← crosscallExpandedArgWordPlanExprs mkError lowerPlanExpr args
  let plainTransfer :=
    mode == .callValue && argExprs.isEmpty &&
      match methodId with
      | .literalWord 0 => true
      | _ => false
  crosscallScalarHelperCallExpr
    mkError
    mode
    targetExpr
    methodIdExpr
    callValueExpr?
    argExprs
    returnType
    plainTransfer

end ProofForge.Backend.Evm.ToYul
