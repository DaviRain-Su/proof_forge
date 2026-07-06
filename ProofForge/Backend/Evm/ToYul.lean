import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Backend.Evm.ToYul.Create
import ProofForge.Backend.Evm.ToYul.Crosscall
import ProofForge.Backend.Evm.ToYul.Helpers
import ProofForge.Backend.Evm.ToYul.Local
import ProofForge.Backend.Evm.ToYul.Abi
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def entrypointFunctionName (moduleName entrypointName : String) : String :=
  s!"f_{moduleName}_{entrypointName}"

def entrypointPlanFunctionName (moduleName : String) (entrypoint : EntrypointPlan) : String :=
  entrypointFunctionName moduleName entrypoint.name

def contextFieldExpr
    (lowerExpr : Expr → Except String Lean.Compiler.Yul.Expr) :
    ContextField → Except String Lean.Compiler.Yul.Expr
  | .userId => .ok (Lean.Compiler.Yul.builtin "caller" #[])
  | .userIdHash => .error "EVM context read `userIdHash` is not supported; NEAR-only full predecessor account hash"
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

def entrypointCallExpr
    (moduleName : String)
    (entrypoint : EntrypointPlan) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call (entrypointPlanFunctionName moduleName entrypoint) (entrypointCallArgs entrypoint.params)

def entrypointFunctionDefinition
    (moduleName : String)
    (entrypoint : EntrypointPlan)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Statement :=
  .funcDef
    (entrypointPlanFunctionName moduleName entrypoint)
    (entrypointParamTypedNames entrypoint.params)
    (returnTypedNames entrypoint.returns)
    { statements := bodyStatements }

/-- Build a fallback or receive function definition. These have no params,
   no return value, and use a fixed name (`__pf_fallback` or `__pf_receive`). -/
def fallbackReceiveFunctionDefinition
    (funcName : String)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Statement :=
  .funcDef funcName #[] #[] { statements := bodyStatements }

/-- Function name for a fallback or receive entrypoint. -/
def fallbackReceiveFunctionName (kind : ProofForge.IR.EntrypointKind) : String :=
  match kind with
  | .fallback => "__pf_fallback"
  | .receive => "__pf_receive"
  | .function => "__pf_fallback"  -- shouldn't happen, but provide a default

def dispatchSelectorExpr : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "shr" #[
    Lean.Compiler.Yul.Expr.num 224,
    Lean.Compiler.Yul.builtin "calldataload" #[Lean.Compiler.Yul.Expr.num 0]
  ]

def eip1967ImplementationSlotExpr : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.lit
    (Lean.Compiler.Yul.Literal.hex "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc")

def uupsProxyFallbackBody : Array Lean.Compiler.Yul.Statement := #[
  .varDecl #[{ name := "_impl" }] (some (Lean.Compiler.Yul.builtin "sload" #[eip1967ImplementationSlotExpr])),
  .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_impl"]) { statements := #[revertStatement] },
  .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "calldatasize" #[]
  ]),
  .varDecl #[{ name := "_ok" }] (some (Lean.Compiler.Yul.builtin "delegatecall" #[
    Lean.Compiler.Yul.builtin "gas" #[],
    Lean.Compiler.Yul.Expr.id "_impl",
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "calldatasize" #[],
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0
  ])),
  .exprStmt (Lean.Compiler.Yul.builtin "returndatacopy" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "returndatasize" #[]
  ]),
  .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_ok"]) {
    statements := #[
      .exprStmt (Lean.Compiler.Yul.builtin "revert" #[
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.builtin "returndatasize" #[]
      ])
    ]
  },
  .exprStmt (Lean.Compiler.Yul.builtin "return" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "returndatasize" #[]
  ])
]

def dispatchDefaultCase (defaultPlan : DispatchDefaultPlan) : Lean.Compiler.Yul.Case :=
  match defaultPlan with
  | .revert => {
      value := none
      body := { statements := #[revertStatement] }
    }
  | .uupsProxy => {
      value := none
      body := { statements := uupsProxyFallbackBody }
    }
  | .fallback => {
      value := none
      body := { statements := #[
        .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "calldatasize" #[]])
          { statements := #[
            .exprStmt (Lean.Compiler.Yul.call "__pf_receive" #[]),
            .exprStmt (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
          ] },
        .exprStmt (Lean.Compiler.Yul.call "__pf_fallback" #[])
      ] }
    }
  | .receive => {
      value := none
      body := { statements := #[
        .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "calldatasize" #[]])
          { statements := #[
            .exprStmt (Lean.Compiler.Yul.call "__pf_receive" #[]),
            .exprStmt (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
          ] },
        .exprStmt (Lean.Compiler.Yul.call "__pf_fallback" #[])
      ] }
    }

def entrypointDispatchCase
    {ε : Type}
    (mkError : String → ε)
    (entrypoint : EntrypointPlan)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) :
    Except ε Lean.Compiler.Yul.Case := do
  if entrypoint.selector.isEmpty then
    .error (mkError s!"EVM EntrypointPlan dispatch case for `{entrypoint.name}` requires a selector")
  else
    .ok {
      value := some (Lean.Compiler.Yul.Literal.hex ("0x" ++ entrypoint.selector))
      body := { statements := bodyStatements }
    }

def dispatchSwitchStatement
    (cases : Array Lean.Compiler.Yul.Case)
    (defaultCase : Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  .switchStmt dispatchSelectorExpr (cases.push defaultCase)

def abiParamPlanIsDynamic (param : AbiParamPlan) : Bool :=
  param.isDynamic

def entrypointPlanHasDynamicParams (entrypoint : EntrypointPlan) : Bool :=
  entrypoint.params.any abiParamPlanIsDynamic

def dispatchBlockStatement
    (entrypoints : Array EntrypointPlan)
    (cases : Array Lean.Compiler.Yul.Case)
    (defaultCase : Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  let switchStmt := dispatchSwitchStatement cases defaultCase
  if entrypoints.any entrypointPlanHasDynamicParams then
    .block { statements := #[
      Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.num 128]),
      switchStmt
    ] }
  else
    switchStmt

def dispatchPlanStatement
    (dispatch : DispatchPlan)
    (cases : Array Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  dispatchBlockStatement dispatch.entrypoints cases (dispatchDefaultCase dispatch.default)

def dispatchResultName (index : Nat) : String :=
  s!"_r{index}"

def dispatchResultNames (wordCount : Nat) : Array String :=
  if wordCount == 1 then
    #["_r"]
  else
    Id.run do
      let mut names : Array String := #[]
      for _h : idx in [0:wordCount] do
        names := names.push (dispatchResultName idx)
      names

def staticDispatchReturnStatements
    {ε : Type}
    (mkError : String → ε)
    (validationStatements : Array Lean.Compiler.Yul.Statement)
    (returns : ReturnPlan)
    (callExpr : Lean.Compiler.Yul.Expr) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  match returns.returnType with
  | .unit =>
    .ok (validationStatements ++ #[
      Lean.Compiler.Yul.Statement.exprStmt callExpr,
      Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
    ])
  | .bytes | .string | .array _ =>
      .error (mkError s!"EVM static dispatch return plan does not support dynamic `{returns.returnType.name}`")
  | _ =>
      if returns.wordTypes.isEmpty then
        .error (mkError s!"EVM dispatch return plan for `{returns.returnType.name}` has no ABI words")
      else
        let resultNames := dispatchResultNames returns.wordTypes.size
        let mut statements : Array Lean.Compiler.Yul.Statement :=
          validationStatements ++ #[
            Lean.Compiler.Yul.Statement.varDecl
              (resultNames.map fun name => ({ name := name } : Lean.Compiler.Yul.TypedName))
              (some callExpr)
          ]
        for h : idx in [0:resultNames.size] do
          statements := statements.push <|
            Lean.Compiler.Yul.Statement.exprStmt
              (Lean.Compiler.Yul.builtin "mstore" #[
                Lean.Compiler.Yul.Expr.num (idx * 32),
                Lean.Compiler.Yul.Expr.id resultNames[idx]
              ])
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.exprStmt
            (Lean.Compiler.Yul.builtin "return" #[
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num (returns.wordTypes.size * 32)
            ])
        .ok statements

def dynamicDispatchReturnStatements
    {ε : Type}
    (mkError : String → ε)
    (validationStatements : Array Lean.Compiler.Yul.Statement)
    (returns : ReturnPlan)
    (callExpr : Lean.Compiler.Yul.Expr) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  match returns.returnType with
  | .bytes | .string | .array _ =>
      let retWordCountExpr :=
        match returns.returnType with
        | .array _ => Lean.Compiler.Yul.Expr.id "_ret_len"
        | _ => Lean.Compiler.Yul.builtin "div" #[
            Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "_ret_len", Lean.Compiler.Yul.Expr.num 31],
            Lean.Compiler.Yul.Expr.num 32
          ]
      .ok (validationStatements ++ #[
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_r" }] (some callExpr),
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_ret_len" }]
          (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.id "_r"])),
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_ret_word_count" }]
          (some retWordCountExpr),
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 32]),
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "_ret_len"]),
        Lean.Compiler.Yul.Statement.forLoop
          { statements := #[
            Lean.Compiler.Yul.Statement.varDecl #[{ name := "_i" }]
              (some (Lean.Compiler.Yul.Expr.num 0))
          ] }
          (Lean.Compiler.Yul.builtin "lt" #[
            Lean.Compiler.Yul.Expr.id "_i",
            Lean.Compiler.Yul.Expr.id "_ret_word_count"
          ])
          { statements := #[
            Lean.Compiler.Yul.Statement.assignment #["_i"]
              (Lean.Compiler.Yul.builtin "add" #[
                Lean.Compiler.Yul.Expr.id "_i",
                Lean.Compiler.Yul.Expr.num 1
              ])
          ] }
          { statements := #[
            Lean.Compiler.Yul.Statement.exprStmt
              (Lean.Compiler.Yul.builtin "mstore" #[
                Lean.Compiler.Yul.builtin "add" #[
                  Lean.Compiler.Yul.Expr.num 64,
                  Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.num 32]
                ],
                Lean.Compiler.Yul.builtin "mload" #[
                  Lean.Compiler.Yul.builtin "add" #[
                    Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "_r", Lean.Compiler.Yul.Expr.num 32],
                    Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.num 32]
                  ]
                ]
              ])
          ] },
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "return" #[
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.builtin "add" #[
              Lean.Compiler.Yul.Expr.num 64,
              Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_ret_word_count", Lean.Compiler.Yul.Expr.num 32]
            ]
          ])
      ])
  | _ =>
      .error (mkError s!"EVM dynamic dispatch return plan expected a dynamic type, got `{returns.returnType.name}`")

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

def packedUtf8Words (value : String) : Array Nat × Nat := Id.run do
  let bytes := value.toUTF8
  let wordCount := (bytes.size + 31) / 32
  let mut words := #[]
  for _h : wordIdx in [0:wordCount] do
    let mut wordVal := 0
    for _h : byteIdx in [0:32] do
      let pos := wordIdx * 32 + byteIdx
      if pos < bytes.size then
        let b := (bytes.get! pos).toNat
        let shift := (31 - byteIdx) * 8
        wordVal := wordVal + (b * (2 ^ shift))
    words := words.push wordVal
  pure (words, bytes.size)

def eventIndexedTopicName (index : Nat) : String :=
  s!"_indexed_topic{index}"

def eventIndexedFieldCount (event : EventPlan) : Nat :=
  event.indexedFields.size

def eventLogBuiltinName
    {ε : Type}
    (mkError : String → ε)
    (indexedFieldCount : Nat) : Except ε String :=
  if indexedFieldCount <= 3 then
    .ok s!"log{indexedFieldCount + 1}"
  else
    .error (mkError "EVM IR v0 supports at most 3 indexed event fields")

def eventSignatureTopicStatements (event : EventPlan) : Array Lean.Compiler.Yul.Statement := Id.run do
  let (words, length) := packedUtf8Words event.signature
  let mut statements := #[]
  for _h : idx in [0:words.size] do
    statements := statements.push <|
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num (idx * 32),
        Lean.Compiler.Yul.Expr.num words[idx]
      ])
  pure <| statements.push <|
    .varDecl #[{ name := "_topic0" }]
      (some (Lean.Compiler.Yul.builtin "keccak256" #[
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num length
      ]))

def eventDataStoreStatements (words : Array Lean.Compiler.Yul.Expr) : Array Lean.Compiler.Yul.Statement := Id.run do
  let mut statements := #[]
  for _h : idx in [0:words.size] do
    statements := statements.push <|
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num (idx * 32),
        words[idx]
      ])
  pure statements

def eventIndexedTopicStatements
    {ε : Type}
    (mkError : String → ε)
    (field : EventFieldPlan)
    (index : Nat)
    (words : Array Lean.Compiler.Yul.Expr) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  let topicName := eventIndexedTopicName index
  match field.type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      match words[0]? with
      | some word =>
          if words.size == 1 then
            .ok #[.varDecl #[{ name := topicName }] (some word)]
          else
            .error (mkError s!"EVM indexed scalar event field `{field.name}` expected one data word, got {words.size}")
      | none =>
          .error (mkError s!"EVM indexed scalar event field `{field.name}` expected one data word, got 0")
  | .fixedArray _ _ | .structType _ | .array _ =>
      .ok <| eventDataStoreStatements words |>.push
        (.varDecl #[{ name := topicName }]
          (some (Lean.Compiler.Yul.builtin "keccak256" #[
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.Expr.num (words.size * 32)
          ])))
  | .unit | .bytes | .string =>
      .error (mkError s!"EVM indexed event field `{field.name}` has unsupported type `{field.type.name}`")

def eventLogStatement
    {ε : Type}
    (mkError : String → ε)
    (event : EventPlan)
    (dataWordCount : Nat) : Except ε Lean.Compiler.Yul.Statement := do
  let indexedFieldCount := eventIndexedFieldCount event
  let mut logArgs : Array Lean.Compiler.Yul.Expr := #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num (dataWordCount * 32),
    Lean.Compiler.Yul.Expr.id "_topic0"
  ]
  for _h : idx in [0:indexedFieldCount] do
    logArgs := logArgs.push (Lean.Compiler.Yul.Expr.id (eventIndexedTopicName idx))
  .ok (.exprStmt (Lean.Compiler.Yul.builtin (← eventLogBuiltinName mkError indexedFieldCount) logArgs))

def eventEmitCoreStatement
    {ε : Type}
    (mkError : String → ε)
    (event : EventPlan)
    (indexedTopicStatements : Array Lean.Compiler.Yul.Statement)
    (dataWords : Array Lean.Compiler.Yul.Expr) :
    Except ε Lean.Compiler.Yul.Statement := do
  let mut statements := eventSignatureTopicStatements event
  statements := statements ++ indexedTopicStatements
  statements := statements ++ eventDataStoreStatements dataWords
  statements := statements.push (← eventLogStatement mkError event dataWords.size)
  .ok (.block { statements := statements })

def eventFieldWordPlanExprs
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (event : EventPlan)
    (fields : Array EventFieldPlan)
    (fieldWords : Array (Array ExprPlan)) :
    Except ε (Array Lean.Compiler.Yul.Expr) := do
  if fields.size != fieldWords.size then
    .error (mkError s!"planned scalar control-flow event `{event.name}` field/word-plan count mismatch")
  let mut words : Array Lean.Compiler.Yul.Expr := #[]
  for _h : idx in [0:fields.size] do
    let some fieldWordPlans := fieldWords[idx]?
      | .error (mkError s!"planned scalar control-flow event `{event.name}` missing field word plans at index {idx}")
    words := words ++ (← fieldWordPlans.mapM lowerPlanExpr)
  .ok words

def eventIndexedTopicStatementsFromWordPlans
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (event : EventPlan)
    (fieldWords : Array (Array ExprPlan)) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  let fields := event.indexedFields
  if fields.size != fieldWords.size then
    .error (mkError s!"planned scalar control-flow event `{event.name}` indexed field/word-plan count mismatch")
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:fields.size] do
    let some fieldWordPlans := fieldWords[idx]?
      | .error (mkError s!"planned scalar control-flow event `{event.name}` missing indexed field word plans at index {idx}")
    let words ← fieldWordPlans.mapM lowerPlanExpr
    statements := statements ++ (← eventIndexedTopicStatements mkError fields[idx] idx words)
  .ok statements

def eventEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect (.eventEmitWords event dataFieldWords) => do
      let dataWords ← eventFieldWordPlanExprs
        mkError
        lowerPlanExpr
        event
        event.dataFields
        dataFieldWords
      .ok #[← eventEmitCoreStatement mkError event #[] dataWords]
  | .effect (.eventEmitIndexedWords event indexedFieldWords dataFieldWords) => do
      let indexedTopicStatements ← eventIndexedTopicStatementsFromWordPlans
        mkError
        lowerPlanExpr
        event
        indexedFieldWords
      let dataWords ← eventFieldWordPlanExprs
        mkError
        lowerPlanExpr
        event
        event.dataFields
        dataFieldWords
      .ok #[← eventEmitCoreStatement mkError event indexedTopicStatements dataWords]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul event effect lowering expected eventEmitWords/eventEmitIndexedWords")

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

partial def exprPlanExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    ExprPlan → Except ε Lean.Compiler.Yul.Expr
  | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
  | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
  | .calldataWord paramIndex => .ok (calldataWordExpr paramIndex)
  | .storageLoad slot => do
      .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr slot])
  | .builtin name args => do
      .ok (Lean.Compiler.Yul.builtin name (← args.mapM (exprPlanExpr mkError lowerExpr lowerEffect)))
  | .helperCall helper args => do
      .ok (helperCall helper (← args.mapM (exprPlanExpr mkError lowerExpr lowerEffect)))
  | .checkedArith op lhs rhs => do
      .ok (checkedArithExpr op
        (← exprPlanExpr mkError lowerExpr lowerEffect lhs)
        (← exprPlanExpr mkError lowerExpr lowerEffect rhs))
  | .hashPack a b c d => do
      .ok (hashPackExpr
        (← exprPlanExpr mkError lowerExpr lowerEffect a)
        (← exprPlanExpr mkError lowerExpr lowerEffect b)
        (← exprPlanExpr mkError lowerExpr lowerEffect c)
        (← exprPlanExpr mkError lowerExpr lowerEffect d))
  | .context field =>
      contextExprPlan (exprPlanExpr mkError lowerExpr lowerEffect) field
  | .crosscall mode target methodId callValue? args returnType =>
      crosscallExpandedExprPlanExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
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
        (← exprPlanExpr mkError lowerExpr lowerEffect callValue)
        (← salt?.mapM (exprPlanExpr mkError lowerExpr lowerEffect))
        initCodeHex
  | .cast source _ =>
      exprPlanExpr mkError lowerExpr lowerEffect source
  | .structField base fieldName =>
      localStructFieldExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
        base
        fieldName
  | .arrayGet array index =>
      arrayGetExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
        array
        index
  | .memoryArrayNew _ length => do
      .ok (helperCall Helper.memoryArrayNew #[← exprPlanExpr mkError lowerExpr lowerEffect length])
  | .memoryArrayLength array => do
      .ok (Lean.Compiler.Yul.builtin "mload" #[← exprPlanExpr mkError lowerExpr lowerEffect array])
  | .memoryArrayGet array index => do
      .ok (helperCall Helper.memoryArrayGet #[
        ← exprPlanExpr mkError lowerExpr lowerEffect array,
        ← exprPlanExpr mkError lowerExpr lowerEffect index
      ])
  | .localArrayGet name path lengths =>
      localArrayGetExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
        name
        path
        lengths
  | .arrayLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support array literal plans yet")
  | .structLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support struct literal plans yet")
  | .hashValue a b c d => do
      .ok (hashPackExpr
        (← exprPlanExpr mkError lowerExpr lowerEffect a)
        (← exprPlanExpr mkError lowerExpr lowerEffect b)
        (← exprPlanExpr mkError lowerExpr lowerEffect c)
        (← exprPlanExpr mkError lowerExpr lowerEffect d))
  | .hash preimage => do
      .ok (helperCall Helper.hashWord #[← exprPlanExpr mkError lowerExpr lowerEffect preimage])
  | .hashTwoToOne lhs rhs => do
      .ok (helperCall Helper.hashPair #[
        ← exprPlanExpr mkError lowerExpr lowerEffect lhs,
        ← exprPlanExpr mkError lowerExpr lowerEffect rhs
      ])
  | .nativeValue =>
      .ok (Lean.Compiler.Yul.builtin "callvalue" #[])
  | .effect effect =>
      lowerEffect effect

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
    (revertStatementsFor : Option ProofForge.IR.ErrorRef → Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .assert condition _ errorRef? => do
      .ok #[
        assertStatementFromCondition
          (← exprPlanExpr mkError lowerExpr lowerEffect condition)
          (revertStatementsFor errorRef?)
      ]
  | .assertEq lhs rhs _ errorRef? => do
      let lhsExpr ← exprPlanExpr mkError lowerExpr lowerEffect lhs
      let rhsExpr ← exprPlanExpr mkError lowerExpr lowerEffect rhs
      .ok #[
        assertStatementFromCondition
          (Lean.Compiler.Yul.builtin "eq" #[lhsExpr, rhsExpr])
          (revertStatementsFor errorRef?)
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar assertion lowering expected assert/assertEq")

def revertStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (revertStatementsFor : ProofForge.IR.ErrorRef → Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .revert message =>
      if message.isEmpty then
        .ok #[revertStatement]
      else
        .ok (revertWithMessageStatements message)
  | .revertWithError errorRef =>
      .ok (revertStatementsFor errorRef)
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
          (checkedArithExpr op
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

def scalarStorageWriteStatements
    (storageSlot valueExpr : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Array Lean.Compiler.Yul.Statement :=
  if byteWidth >= 32 || byteOffset == 0 && byteWidth == 32 then
    #[
      .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[storageSlot, valueExpr])
    ]
  else
    let shiftBits := (32 - (byteOffset + byteWidth)) * 8
    let mask := (2^(byteWidth * 8 : Nat)) - 1
    let shiftedMask := Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num shiftBits,
      Lean.Compiler.Yul.Expr.num mask
    ]
    #[
      .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
        storageSlot,
        Lean.Compiler.Yul.builtin "or" #[
          Lean.Compiler.Yul.builtin "and" #[
            Lean.Compiler.Yul.builtin "sload" #[storageSlot],
            Lean.Compiler.Yul.builtin "not" #[shiftedMask]
          ],
          Lean.Compiler.Yul.builtin "shl" #[
            Lean.Compiler.Yul.Expr.num shiftBits,
            valueExpr
          ]
        ]
      ])
    ]

def scalarStoragePackedReadExpr
    (storageSlot : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Lean.Compiler.Yul.Expr :=
  if byteWidth >= 32 || byteOffset == 0 && byteWidth == 32 then
    Lean.Compiler.Yul.builtin "sload" #[storageSlot]
  else
    let shiftBits := (32 - (byteOffset + byteWidth)) * 8
    let mask := (2^(byteWidth * 8 : Nat)) - 1
    Lean.Compiler.Yul.builtin "and" #[
      Lean.Compiler.Yul.builtin "shr" #[
        Lean.Compiler.Yul.Expr.num shiftBits,
        Lean.Compiler.Yul.builtin "sload" #[storageSlot]
      ],
      Lean.Compiler.Yul.Expr.num mask
    ]

def scalarStorageTargetReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (target : ScalarStorageTargetPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok <| scalarStoragePackedReadExpr
    (← storageSlotExpr mkError lowerExpr target.slot)
    target.byteOffset
    target.byteWidth

def scalarStorageAssignOpStatements
    (op : AssignOp)
    (storageSlot valueExpr : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Array Lean.Compiler.Yul.Statement :=
  let packedRead := scalarStoragePackedReadExpr storageSlot byteOffset byteWidth
  let computedValue := checkedArithExpr op packedRead valueExpr
  scalarStorageWriteStatements storageSlot computedValue byteOffset byteWidth

def scalarStorageEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (storageSlotFor : String → Except ε Lean.Compiler.Yul.Expr)
    (packingFor : String → Except ε (Nat × Nat)) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageScalarWrite stateId value => do
      let storageSlot ← storageSlotFor stateId
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      let (byteOffset, byteWidth) ← packingFor stateId
      .ok <| scalarStorageWriteStatements storageSlot valueExpr byteOffset byteWidth
  | .storageScalarAssignOp stateId op value => do
      let storageSlot ← storageSlotFor stateId
      let (byteOffset, byteWidth) ← packingFor stateId
      let rhs ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageAssignOpStatements op storageSlot rhs byteOffset byteWidth
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul scalar storage effect lowering expected storageScalarWrite/storageScalarAssignOp")

def scalarStorageEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (storageSlotFor : String → Except ε Lean.Compiler.Yul.Expr)
    (packingFor : String → Except ε (Nat × Nat)) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      scalarStorageEffectPlanStatements mkError lowerExpr lowerEffect storageSlotFor packingFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar storage effect lowering expected effect")

def scalarStorageTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageScalarWriteTarget target value => do
      let targetSlot ← storageSlotExpr mkError lowerExpr target.slot
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageWriteStatements targetSlot valueExpr target.byteOffset target.byteWidth
  | .storageScalarAssignOpTarget target op value => do
      let targetSlot ← storageSlotExpr mkError lowerExpr target.slot
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageAssignOpStatements op targetSlot valueExpr target.byteOffset target.byteWidth
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned scalar storage lowering expected storageScalarWriteTarget/storageScalarAssignOpTarget")

def scalarStorageTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      scalarStorageTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned scalar storage lowering expected effect")

def mapWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (mapRootSlotFor : String → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageMapInsert stateId key value
  | .storageMapSet stateId key value => do
      .ok #[
        .exprStmt (helperCall Helper.mapWrite #[
          ← mapRootSlotFor stateId,
          ← exprPlanExpr mkError lowerExpr lowerEffect key,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul map write lowering expected storageMapInsert/storageMapSet")

def mapWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (mapRootSlotFor : String → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      mapWriteEffectPlanStatements mkError lowerExpr lowerEffect mapRootSlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul map write lowering expected effect")

def mapSetReturnTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapWriteTargetPlan)
    (key value : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (helperCall Helper.mapSetReturn #[
    slotExpr target.rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key,
    ← exprPlanExpr mkError lowerExpr lowerEffect value
  ])

def mapContainsExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let presenceSlot := helperCall Helper.mapPresenceSlot #[
    slotExpr rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key
  ]
  .ok (Lean.Compiler.Yul.builtin "iszero" #[
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "sload" #[presenceSlot]
    ]
  ])

def mapContainsTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapReadTargetPlan)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  mapContainsExpr mkError lowerExpr lowerEffect target.rootSlot key

def mapGetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let valueSlot := helperCall Helper.mapSlot #[
    slotExpr rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[valueSlot])

def mapGetTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapReadTargetPlan)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  mapGetExpr mkError lowerExpr lowerEffect target.rootSlot key

def mapWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageMapInsertTarget target key value
  | .storageMapSetTarget target key value => do
      .ok #[
        .exprStmt (helperCall Helper.mapWrite #[
          slotExpr target.rootSlot,
          ← exprPlanExpr mkError lowerExpr lowerEffect key,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned map write lowering expected storageMapInsertTarget/storageMapSetTarget")

def mapWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      mapWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned map write lowering expected effect")

def arrayWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (arraySlotFor : String → ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayWrite stateId index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← arraySlotFor stateId index,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul array write lowering expected storageArrayWrite")

def arrayWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (arraySlotFor : String → ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      arrayWriteEffectPlanStatements mkError lowerExpr lowerEffect arraySlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul array write lowering expected effect")

def arrayReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot length : Nat)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let elementSlot := helperCall Helper.arraySlot #[
    slotExpr rootSlot,
    Lean.Compiler.Yul.Expr.num length,
    ← exprPlanExpr mkError lowerExpr lowerEffect index
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[elementSlot])

def arrayReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : ArrayReadTargetPlan)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  arrayReadExpr mkError lowerExpr lowerEffect target.rootSlot target.length index

def arrayWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayWriteTarget target index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.arraySlot #[
            slotExpr target.rootSlot,
            Lean.Compiler.Yul.Expr.num target.length,
            ← exprPlanExpr mkError lowerExpr lowerEffect index
          ],
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned array write lowering expected storageArrayWriteTarget")

def arrayWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      arrayWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned array write lowering expected effect")

def dynamicArraySlotTargetExpr
    (target : DynamicArrayTargetPlan)
    (index : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  helperCall Helper.dynamicArraySlot #[slotExpr target.rootSlot, index]

def dynamicArrayPushTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageDynamicArrayPushTarget target value => do
      let baseSlot := slotExpr target.rootSlot
      let lenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_len"
      let newLenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_new_len"
      .ok #[
        .varDecl #[{ name := "__proof_forge_dyn_array_len" }] (some (Lean.Compiler.Yul.builtin "sload" #[baseSlot])),
        .varDecl #[{ name := "__proof_forge_dyn_array_new_len" }]
          (some (Lean.Compiler.Yul.builtin "add" #[lenExpr, Lean.Compiler.Yul.Expr.num 1])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          dynamicArraySlotTargetExpr target lenExpr,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[baseSlot, newLenExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned dynamic array push lowering expected storageDynamicArrayPushTarget")

def dynamicArrayPushTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      dynamicArrayPushTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned dynamic array push lowering expected effect")

def dynamicArrayPopTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageDynamicArrayPopTarget target => do
      let baseSlot := slotExpr target.rootSlot
      let lenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_len"
      let newLenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_new_len"
      .ok #[
        .varDecl #[{ name := "__proof_forge_dyn_array_len" }] (some (Lean.Compiler.Yul.builtin "sload" #[baseSlot])),
        .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[lenExpr])
          { statements := #[.exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])] },
        .varDecl #[{ name := "__proof_forge_dyn_array_new_len" }]
          (some (Lean.Compiler.Yul.builtin "sub" #[lenExpr, Lean.Compiler.Yul.Expr.num 1])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[baseSlot, newLenExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned dynamic array pop lowering expected storageDynamicArrayPopTarget")

def dynamicArrayPopTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      dynamicArrayPopTargetEffectPlanStatements mkError effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned dynamic array pop lowering expected effect")

def structFieldWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFieldSlotFor : String → String → Except ε Lean.Compiler.Yul.Expr)
    (structArrayFieldSlotFor : String → ExprPlan → String → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageStructFieldWrite stateId fieldName value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← structFieldSlotFor stateId fieldName,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← structArrayFieldSlotFor stateId index fieldName,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul struct field write lowering expected storageStructFieldWrite/storageArrayStructFieldWrite")

def structFieldWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFieldSlotFor : String → String → Except ε Lean.Compiler.Yul.Expr)
    (structArrayFieldSlotFor : String → ExprPlan → String → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structFieldWriteEffectPlanStatements mkError lowerExpr lowerEffect structFieldSlotFor structArrayFieldSlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul struct field write lowering expected effect")

def structFieldWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageStructFieldWriteTarget target value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← storageSlotExpr mkError lowerExpr target.slot,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned struct field write lowering expected storageStructFieldWriteTarget")

def structFieldWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structFieldWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned struct field write lowering expected effect")

def structArrayFieldWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayStructFieldWriteTarget target index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.structArraySlot #[
            slotExpr target.rootSlot,
            Lean.Compiler.Yul.Expr.num target.length,
            Lean.Compiler.Yul.Expr.num target.fieldCount,
            Lean.Compiler.Yul.Expr.num target.fieldOffset,
            ← exprPlanExpr mkError lowerExpr lowerEffect index
          ],
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned struct-array field write lowering expected storageArrayStructFieldWriteTarget")

def structArrayFieldWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structArrayFieldWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned struct-array field write lowering expected effect")

def structFieldReadExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "sload" #[slotExpr slot]

def structFieldReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (target : StructFieldReadTargetPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr target.slot])

def structArrayFieldReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot length fieldCount fieldOffset : Nat)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let fieldSlot := helperCall Helper.structArraySlot #[
    slotExpr rootSlot,
    Lean.Compiler.Yul.Expr.num length,
    Lean.Compiler.Yul.Expr.num fieldCount,
    Lean.Compiler.Yul.Expr.num fieldOffset,
    ← exprPlanExpr mkError lowerExpr lowerEffect index
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[fieldSlot])

def structArrayFieldReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : StructArrayFieldReadTargetPlan)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  structArrayFieldReadExpr
    mkError lowerExpr lowerEffect
    target.rootSlot target.length target.fieldCount target.fieldOffset
    index

structure StorageStructWriteField where
  slot : Lean.Compiler.Yul.Expr
  fieldName : String
  value : Lean.Compiler.Yul.Expr
  deriving Inhabited

def storageStructAssignTempName (stateId fieldName : String) : String :=
  s!"__proof_forge_assign_storage_struct_{stateId}_{fieldName}"

def storageStructWriteStatements
    (stateId : String)
    (fields : Array StorageStructWriteField) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for field in fields do
      statements := statements.push <|
        .varDecl #[{ name := storageStructAssignTempName stateId field.fieldName }] (some field.value)
    for field in fields do
      statements := statements.push <|
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          field.slot,
          Lean.Compiler.Yul.Expr.id (storageStructAssignTempName stateId field.fieldName)
        ])
    pure statements

def storageStructWriteFieldFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (field : StorageStructWriteFieldPlan) : Except ε StorageStructWriteField := do
  .ok {
    slot := slotExpr field.slot
    fieldName := field.fieldName
    value := ← exprPlanExpr mkError lowerExpr lowerEffect field.value
  }

def storageStructWriteFieldPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (stateId : String)
    (fields : Array StorageStructWriteFieldPlan) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  .ok #[
    .block {
      statements :=
        storageStructWriteStatements stateId
          (← fields.mapM (storageStructWriteFieldFromPlan mkError lowerExpr lowerEffect))
    }
  ]

inductive StoragePathWriteTarget where
  | mapWrite (rootSlot key : Lean.Compiler.Yul.Expr)
  | singleSlot (slot : Lean.Compiler.Yul.Expr)
  | mapValuePresence (valueSlot presenceSlot : Lean.Compiler.Yul.Expr)
  deriving Inhabited

def storagePathWriteTargetFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    StoragePathWriteTargetPlan → Except ε StoragePathWriteTarget
  | .mapWrite rootSlot key => do
      .ok (.mapWrite (slotExpr rootSlot) (← lowerValuePlan lowerExpr key))
  | .singleSlot slot => do
      .ok (.singleSlot (← storageSlotExpr mkError lowerExpr slot))
  | .mapValuePresence valueSlot presenceSlot => do
      .ok (.mapValuePresence
        (← storageSlotExpr mkError lowerExpr valueSlot)
        (← storageSlotExpr mkError lowerExpr presenceSlot))

def storagePathWriteExprTargetFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StoragePathWriteExprTargetPlan → Except ε StoragePathWriteTarget
  | .mapWrite rootSlot key => do
      .ok (.mapWrite (slotExpr rootSlot) (← lowerPlanExpr key))
  | .singleSlot slot => do
      .ok (.singleSlot (← storageSlotExprPlan mkError lowerPlanExpr slot))
  | .mapValuePresence valueSlot presenceSlot => do
      .ok (.mapValuePresence
        (← storageSlotExprPlan mkError lowerPlanExpr valueSlot)
        (← storageSlotExprPlan mkError lowerPlanExpr presenceSlot))

def storagePathWriteTargetStatements
    (value : Lean.Compiler.Yul.Expr) :
    StoragePathWriteTarget → Array Lean.Compiler.Yul.Statement
  | .mapWrite rootSlot key =>
      #[
        .exprStmt (helperCall Helper.mapWrite #[rootSlot, key, value])
      ]
  | .singleSlot slot =>
      #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[slot, value])
      ]
  | .mapValuePresence valueSlot presenceSlot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some valueSlot),
          .varDecl #[{ name := "_presence_slot" }] (some presenceSlot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            value
          ]),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_presence_slot",
            Lean.Compiler.Yul.Expr.num 1
          ])
        ]}
      ]

def storagePathWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathWriteTarget target value => do
      .ok <| storagePathWriteTargetStatements
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteTargetFromPlan mkError lowerExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path write lowering expected storagePathWriteTarget")

def storagePathWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path write lowering expected effect")

def storagePathWriteExprTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathWriteExprTarget target value => do
      .ok <| storagePathWriteTargetStatements
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteExprTargetFromPlan mkError lowerPlanExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path write expr lowering expected storagePathWriteExprTarget")

def storagePathWriteExprTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathWriteExprTargetEffectPlanStatements mkError lowerExpr lowerEffect lowerPlanExpr effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path write expr lowering expected effect")

def storagePathAssignOpTargetStatements
    (op : AssignOp)
    (value : Lean.Compiler.Yul.Expr) :
    StoragePathWriteTarget → Array Lean.Compiler.Yul.Statement
  | .mapWrite rootSlot key =>
      #[
        .exprStmt (helperCall (Helper.mapAssign op) #[rootSlot, key, value])
      ]
  | .singleSlot slot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some slot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            checkedArithExpr op
              (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"])
              value
          ])
        ]}
      ]
  | .mapValuePresence valueSlot presenceSlot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some valueSlot),
          .varDecl #[{ name := "_presence_slot" }] (some presenceSlot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            checkedArithExpr op
              (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"])
              value
          ]),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_presence_slot",
            Lean.Compiler.Yul.Expr.num 1
          ])
        ]}
      ]

def storagePathAssignOpTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathAssignOpTarget target op value => do
      .ok <| storagePathAssignOpTargetStatements op
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteTargetFromPlan mkError lowerExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path assign_op lowering expected storagePathAssignOpTarget")

def storagePathAssignOpTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathAssignOpTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path assign_op lowering expected effect")

def storagePathAssignOpExprTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathAssignOpExprTarget target op value => do
      .ok <| storagePathAssignOpTargetStatements
        op
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteExprTargetFromPlan mkError lowerPlanExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path assign_op expr lowering expected storagePathAssignOpExprTarget")

def storagePathAssignOpExprTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathAssignOpExprTargetEffectPlanStatements mkError lowerExpr lowerEffect lowerPlanExpr effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path assign_op expr lowering expected effect")
def memoryArraySetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .memoryArraySet array index value => do
      let arrayExpr ← exprPlanExpr mkError lowerExpr lowerEffect array
      let indexExpr ← exprPlanExpr mkError lowerExpr lowerEffect index
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      let lengthExpr := Lean.Compiler.Yul.builtin "mload" #[arrayExpr]
      let inBounds := Lean.Compiler.Yul.builtin "lt" #[indexExpr, lengthExpr]
      let revertGuard := Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "iszero" #[inBounds])
        { statements := #[revertStatement] }
      let elementPtr := Lean.Compiler.Yul.builtin "add" #[
        Lean.Compiler.Yul.builtin "add" #[arrayExpr, Lean.Compiler.Yul.Expr.num 32],
        Lean.Compiler.Yul.builtin "mul" #[indexExpr, Lean.Compiler.Yul.Expr.num 32]
      ]
      .ok #[
        revertGuard,
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[elementPtr, valueExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul memory array set lowering expected memoryArraySet")

def memoryArraySetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      memoryArraySetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul memory array set lowering expected effect")

/-! ## Plan-driven helper requirements

`StorageSlotPlan.requiredHelpers` lets the plan declare which EVM helper functions
a given slot plan needs, without `ToYul` re-discovering them from Yul text. -/

def slotHelperRequirements (slot : StorageSlotPlan) : HelperSet :=
  slot.requiredHelpers

def storageLayoutHelpers (layout : StorageLayout) : HelperSet :=
  layout.states.foldl (init := #[]) fun acc state =>
    match state.kind with
    | .map _ _ => HelperSet.insert (HelperSet.insert acc Helper.mapSlot) Helper.mapPresenceSlot
    | _ => acc

end ProofForge.Backend.Evm.ToYul
