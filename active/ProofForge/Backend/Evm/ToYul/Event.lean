import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Compiler.Yul.AST

/-! # EVM event plan emission

Event-topic and event-data statement builders used by plan-driven Yul lowering.
-/

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

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
  s!"__pf_event_indexed_topic{index}"

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
    .varDecl #[{ name := "__pf_event_topic0" }]
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
    Lean.Compiler.Yul.Expr.id "__pf_event_topic0"
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

end ProofForge.Backend.Evm.ToYul
