import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.YulSemantics
import ProofForge.Contract.Examples.ValueVault
import ProofForge.IR.Examples.EvmAbiAggregateProbe
import ProofForge.IR.Examples.EvmExpressionProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.EvmLoopProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.IR.Examples.EvmTypedStorageProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmContextProbe
import ProofForge.IR.Semantics

namespace ProofForge.Backend.Evm.Refinement

open ProofForge.IR

/-! Refinement scaffolding for the IR -> EVM/Yul path.

This mirrors the NEAR trace-obligation pattern without claiming a full EVM or
Yul semantics yet. The obligations fix observable IR traces for the shared
Counter and ValueVault scenarios, check that generated EVM Yul exposes every
entrypoint needed by those traces, and execute the focused Yul subset to compare
observable return words.
-/

inductive ObservableReturn where
  | none
  | bool (value : Bool)
  | u32 (value : Nat)
  | u64 (value : Nat)
  | hash (a b c d : Nat)
  | words (values : Array Nat)
  deriving Repr, BEq, DecidableEq

structure ObservableEventLog where
  eventName : String
  topics : Array Nat := #[]
  dataWords : Array Nat := #[]
  deriving Repr, BEq, DecidableEq

structure ObservableStep where
  entrypointName : String
  selector : String
  returnValue : ObservableReturn
  logs : Array ObservableEventLog := #[]
  deriving Repr, BEq, DecidableEq

structure TraceCall where
  entrypoint : Entrypoint
  args : Array ProofForge.IR.Semantics.Value := #[]
  evmArgs : Array Nat := #[]
  deriving Repr

structure TraceObligation where
  name : String
  module : Module
  calls : Array TraceCall
  expected : Array ObservableStep
  deriving Repr

partial def observableWordsFromValue (value : ProofForge.IR.Semantics.Value) :
    Except String (Array Nat) :=
  match value with
  | .unit => .ok #[]
  | .bool value => .ok #[if value then 1 else 0]
  | .u32 value => .ok #[value]
  | .u64 value => .ok #[value]
  | .address value => .ok #[value]
  | .bytes values => do
      let wordCount := (values.length + 31) / 32
      let mut words := #[values.length]
      for _h : _idx in [0:wordCount] do
        words := words.push 0
      .ok words
  | .string value => do
      let bytes := value.toUTF8
      let wordCount := (bytes.size + 31) / 32
      let mut words := #[bytes.size]
      for _h : _idx in [0:wordCount] do
        words := words.push 0
      .ok words
  | .hash a b c d =>
      .ok #[a * ProofForge.Backend.Evm.YulSemantics.twoPow 192 +
        b * ProofForge.Backend.Evm.YulSemantics.twoPow 128 +
        c * ProofForge.Backend.Evm.YulSemantics.twoPow 64 +
        d]
  | .array values => do
      let mut words := #[]
      for value in values do
        words := words ++ (← observableWordsFromValue value)
      .ok words
  | .struct _ fields => do
      let mut words := #[]
      for field in fields do
        words := words ++ (← observableWordsFromValue field.snd)
      .ok words

partial def observableIndexedWordsFromValue (value : ProofForge.IR.Semantics.Value) :
    Except String (Array Nat) := do
  match value with
  | .array _ | .struct _ _ => do
      let words ← observableWordsFromValue value
      .ok #[ProofForge.Backend.Evm.YulSemantics.pseudoKeccakWords words]
  | _ =>
      observableWordsFromValue value

partial def eventSignatureTypeFromValue (value : ProofForge.IR.Semantics.Value) :
    Except String String := do
  match value with
  | .bool _ => .ok "bool"
  | .u32 _ => .ok "uint32"
  | .u64 _ => .ok "uint64"
  | .hash _ _ _ _ => .ok "bytes32"
  | .address _ => .ok "address"
  | .bytes _ => .ok "bytes"
  | .string _ => .ok "string"
  | .array [] =>
      .error "event fixed-array signature requires at least one element"
  | .array (first :: rest) => do
      let elementType ← eventSignatureTypeFromValue first
      for value in rest do
        let currentType ← eventSignatureTypeFromValue value
        if currentType != elementType then
          .error "event fixed-array signature requires homogeneous element types"
      .ok (elementType ++ s!"[{rest.length + 1}]")
  | .struct _ fields => do
      if fields.isEmpty then
        .error "event struct signature requires at least one field"
      let mut fieldTypes := #[]
      for field in fields do
        fieldTypes := fieldTypes.push (← eventSignatureTypeFromValue field.snd)
      .ok ("(" ++ String.intercalate "," fieldTypes.toList ++ ")")
  | .unit =>
      .error "event signature does not support Unit fields"

def pseudoKeccakMemoryWords (words : Array Nat) (size : Nat) : Nat :=
  words.foldl ProofForge.Backend.Evm.YulSemantics.pseudoKeccakStep
    ((0 + 1) * 16777619 + (size + 1) * 1099511628211)

def eventSignatureTopic (signature : String) : Nat :=
  let (words, length) := ProofForge.Backend.Evm.IR.packedUtf8Words signature
  pseudoKeccakMemoryWords words length

def eventSignatureFromValues (name : String) (indexed data : Array ProofForge.IR.Semantics.Value) :
    Except String String := do
  let mut typeNames := #[]
  for value in indexed ++ data do
    typeNames := typeNames.push (← eventSignatureTypeFromValue value)
  .ok (name ++ "(" ++ String.intercalate "," typeNames.toList ++ ")")

def observableEventLogFromIr (log : ProofForge.IR.Semantics.EventLog) :
    Except String ObservableEventLog := do
  let mut indexedWords := #[]
  for value in log.indexed do
    indexedWords := indexedWords ++ (← observableIndexedWordsFromValue value)
  let mut dataWords := #[]
  for value in log.data do
    dataWords := dataWords ++ (← observableWordsFromValue value)
  let signature ← eventSignatureFromValues log.name log.indexed log.data
  .ok {
    eventName := log.name
    topics := #[eventSignatureTopic signature] ++ indexedWords
    dataWords
  }

def arrayDrop {α : Type} (values : Array α) (n : Nat) : Array α :=
  values.toList.drop n |>.toArray

def observableEventLogsFromIr (logs : Array ProofForge.IR.Semantics.EventLog) :
    Except String (Array ObservableEventLog) := do
  let mut observed := #[]
  for log in logs do
    observed := observed.push (← observableEventLogFromIr log)
  .ok observed

def observableEventLogFromEvmLog (log : ProofForge.Backend.Evm.YulSemantics.Log) :
    ObservableEventLog := {
  eventName := ""
  topics := log.topics
  dataWords := log.data
}

def observableEventLogsFromEvmLogs
    (logs : Array ProofForge.Backend.Evm.YulSemantics.Log) :
    Array ObservableEventLog :=
  logs.map observableEventLogFromEvmLog

def all2List {α β : Type} (p : α → β → Bool) : List α → List β → Bool
  | [], [] => true
  | lhs :: lhsRest, rhs :: rhsRest => p lhs rhs && all2List p lhsRest rhsRest
  | _, _ => false

def all2Array {α β : Type} (p : α → β → Bool) (lhs : Array α) (rhs : Array β) :
    Bool :=
  all2List p lhs.toList rhs.toList

def ObservableEventLog.evmCompatible (actual expected : ObservableEventLog) : Bool :=
  actual.topics == expected.topics &&
    actual.dataWords == expected.dataWords

def ObservableStep.evmCompatible (actual expected : ObservableStep) : Bool :=
  actual.entrypointName == expected.entrypointName &&
    actual.selector == expected.selector &&
    actual.returnValue == expected.returnValue &&
    all2Array ObservableEventLog.evmCompatible actual.logs expected.logs

def observableReturn (expectedType : ValueType) (value? : Option ProofForge.IR.Semantics.Value) :
    Except String ObservableReturn :=
  match expectedType, value? with
  | .unit, none => .ok .none
  | .unit, some .unit => .ok .none
  | .bool, some (.bool value) => .ok (.bool value)
  | .u32, some (.u32 value) => .ok (.u32 value)
  | .u64, some (.u64 value) => .ok (.u64 value)
  | .hash, some (.hash a b c d) => .ok (.hash a b c d)
  | .address, some (.address value) => .ok (.u64 value)
  | .bytes, some (.bytes _) | .string, some (.string _) => .ok (.none)
  | .fixedArray _ _, some value => do
      .ok (.words (← observableWordsFromValue value))
  | .structType _, some value => do
      .ok (.words (← observableWordsFromValue value))
  | _, none => .error s!"entrypoint expected `{expectedType.name}` but returned no value"
  | _, some _ => .error s!"entrypoint returned a value that does not match `{expectedType.name}`"

def unpackHashWord (word : Nat) : ObservableReturn :=
  let limb := ProofForge.Backend.Evm.YulSemantics.twoPow 64
  let a := word / ProofForge.Backend.Evm.YulSemantics.twoPow 192
  let b := (word / ProofForge.Backend.Evm.YulSemantics.twoPow 128) % limb
  let c := (word / ProofForge.Backend.Evm.YulSemantics.twoPow 64) % limb
  let d := word % limb
  .hash a b c d

def observableReturnFromEvmWords (expectedType : ValueType) (words : Array Nat) :
    Except String ObservableReturn :=
  match expectedType, words.toList with
  | .unit, [] => .ok .none
  | .bool, [0] => .ok (.bool false)
  | .bool, [1] => .ok (.bool true)
  | .bool, [_] => .error "EVM Bool return word must be 0 or 1"
  | .u32, [value] =>
      if value <= 4294967295 then
        .ok (.u32 value)
      else
        .error "EVM U32 return word exceeds U32 range"
  | .u64, [value] => .ok (.u64 value)
  | .hash, [word] => .ok (unpackHashWord word)
  | .address, [value] => .ok (.u64 value)
  | .bytes, words | .string, words => .ok (.words words.toArray)
  | .fixedArray _ _, words => .ok (.words words.toArray)
  | .structType _, words => .ok (.words words.toArray)
  | .unit, _ => .error s!"entrypoint expected `Unit` but returned {words.size} word(s)"
  | _, [] => .error s!"entrypoint expected `{expectedType.name}` but returned no EVM words"
  | _, _ => .error s!"entrypoint expected `{expectedType.name}` but returned {words.size} EVM word(s)"

def runEntrypointObservable (state : ProofForge.IR.Semantics.State) (call : TraceCall) :
    Except String (ProofForge.IR.Semantics.State × ObservableStep) := do
  let entrypoint := call.entrypoint
  let selector ←
    match entrypoint.selector? with
    | some selector => .ok selector
    | none => .error s!"entrypoint `{entrypoint.name}` has no EVM selector metadata"
  let (nextState, result?) ←
    ProofForge.IR.Semantics.runEntrypointWithArgs state entrypoint call.args
  let returnValue ← observableReturn entrypoint.returns result?
  let logs ← observableEventLogsFromIr (arrayDrop nextState.logs state.logs.size)
  .ok (nextState, { entrypointName := entrypoint.name, selector, returnValue, logs })

def runTraceList : List TraceCall → ProofForge.IR.Semantics.State →
    Except String (ProofForge.IR.Semantics.State × Array ObservableStep)
  | [], state => .ok (state, #[])
  | call :: rest, state => do
      let (nextState, step) ← runEntrypointObservable state call
      let (finalState, steps) ← runTraceList rest nextState
      .ok (finalState, #[step] ++ steps)

def runTrace (calls : Array TraceCall) : Except String (Array ObservableStep) := do
  let (_, steps) ← runTraceList calls.toList ProofForge.IR.Semantics.State.empty
  .ok steps

def TraceObligation.irTraceOk (obligation : TraceObligation) : Bool :=
  match runTrace obligation.calls with
  | .ok actual => actual == obligation.expected
  | .error _ => false

namespace YulSurface

def isNatLiteral (expected : Nat) : Lean.Compiler.Yul.Expr → Bool
  | .lit literal =>
      match literal.kind with
      | .number => literal.value == toString expected
      | .hexNumber | .bool | .string | .hexString => false
  | .ident _ | .call _ _ | .builtin _ _ => false

def isCalldataSelectorExpr : Lean.Compiler.Yul.Expr → Bool
  | .builtin "shr" args =>
      match args.toList with
      | [shift, .builtin "calldataload" loadArgs] =>
          isNatLiteral 224 shift &&
            match loadArgs.toList with
            | [offset] => isNatLiteral 0 offset
            | _ => false
      | _ => false
  | .lit _ | .ident _ | .call _ _ | .builtin _ _ => false

partial def exprCallsFunction (functionName : String) : Lean.Compiler.Yul.Expr → Bool
  | .call name args =>
      name == functionName || args.any (exprCallsFunction functionName)
  | .builtin _ args =>
      args.any (exprCallsFunction functionName)
  | .lit _ | .ident _ => false

mutual
  partial def blockCallsFunction (functionName : String) (block : Lean.Compiler.Yul.Block) : Bool :=
    block.statements.any (statementCallsFunction functionName)

  partial def caseCallsFunction (functionName : String) (case : Lean.Compiler.Yul.Case) : Bool :=
    blockCallsFunction functionName case.body

  partial def statementCallsFunction (functionName : String) : Lean.Compiler.Yul.Statement → Bool
    | .block block => blockCallsFunction functionName block
    | .varDecl _ value? =>
        match value? with
        | some value => exprCallsFunction functionName value
        | none => false
    | .assignment _ value => exprCallsFunction functionName value
    | .exprStmt value => exprCallsFunction functionName value
    | .ifStmt cond body =>
        exprCallsFunction functionName cond || blockCallsFunction functionName body
    | .switchStmt selector cases =>
        exprCallsFunction functionName selector || cases.any (caseCallsFunction functionName)
    | .funcDef _ _ _ body => blockCallsFunction functionName body
    | .forLoop pre cond post body =>
        blockCallsFunction functionName pre ||
          exprCallsFunction functionName cond ||
          blockCallsFunction functionName post ||
          blockCallsFunction functionName body
    | .break | .continue | .leave => false
end

def caseHasSelector (selector : String) (case : Lean.Compiler.Yul.Case) : Bool :=
  match case.value with
  | some literal =>
      match literal.kind with
      | .hexNumber => literal.value == "0x" ++ selector
      | .number | .bool | .string | .hexString => false
  | none => false

def dispatchCaseOk (selector functionName : String) (case : Lean.Compiler.Yul.Case) : Bool :=
  caseHasSelector selector case && caseCallsFunction functionName case

def statementHasDispatchCase (selector functionName : String) : Lean.Compiler.Yul.Statement → Bool
  | .switchStmt dispatchExpr cases =>
      isCalldataSelectorExpr dispatchExpr &&
        cases.any (dispatchCaseOk selector functionName)
  | _ => false

def hasTopLevelFunction (object : Lean.Compiler.Yul.Object) (functionName : String) : Bool :=
  object.code.statements.any fun
    | .funcDef name _ _ _ => name == functionName
    | _ => false

def hasDispatchCase (object : Lean.Compiler.Yul.Object) (selector functionName : String) : Bool :=
  object.code.statements.any (statementHasDispatchCase selector functionName)

def entrypointOk (module : Module) (object : Lean.Compiler.Yul.Object) (entrypoint : Entrypoint) :
    Bool :=
  match entrypoint.selector? with
  | some selector =>
      let functionName := ProofForge.Backend.Evm.IR.yulFunctionName module.name entrypoint.name
      hasTopLevelFunction object functionName && hasDispatchCase object selector functionName
  | none => false

end YulSurface

def TraceObligation.evmYulSurfaceOk (obligation : TraceObligation) : Bool :=
  match ProofForge.Backend.Evm.IR.lowerModule obligation.module with
  | .ok object =>
      obligation.calls.all fun call =>
        YulSurface.entrypointOk obligation.module object call.entrypoint
  | .error _ => false

def runEvmEntrypointObservable
    (object : Lean.Compiler.Yul.Object)
    (storage : ProofForge.Backend.Evm.YulSemantics.WordBindings)
    (call : TraceCall) :
    Except String (ProofForge.Backend.Evm.YulSemantics.WordBindings × ObservableStep) := do
  let entrypoint := call.entrypoint
  let selectorString ←
    match entrypoint.selector? with
    | some selector => .ok selector
    | none => .error s!"entrypoint `{entrypoint.name}` has no EVM selector metadata"
  let selector ← ProofForge.Backend.Evm.YulSemantics.parseHexNat selectorString
  let (nextStorage, returnWords, logs) ←
    ProofForge.Backend.Evm.YulSemantics.runSelectorWithArgsWithLogs
      object storage selector call.evmArgs
  let returnValue ← observableReturnFromEvmWords entrypoint.returns returnWords
  .ok (nextStorage, {
    entrypointName := entrypoint.name
    selector := selectorString
    returnValue
    logs := observableEventLogsFromEvmLogs logs
  })

def runEvmTraceList
    (object : Lean.Compiler.Yul.Object) :
    List TraceCall → ProofForge.Backend.Evm.YulSemantics.WordBindings →
      Except String (ProofForge.Backend.Evm.YulSemantics.WordBindings × Array ObservableStep)
  | [], storage => .ok (storage, #[])
  | call :: rest, storage => do
      let (nextStorage, step) ← runEvmEntrypointObservable object storage call
      let (finalStorage, steps) ← runEvmTraceList object rest nextStorage
      .ok (finalStorage, #[step] ++ steps)

def runEvmTrace (object : Lean.Compiler.Yul.Object) (calls : Array TraceCall) :
    Except String (Array ObservableStep) := do
  let (_, steps) ← runEvmTraceList object calls.toList []
  .ok steps

def TraceObligation.evmYulTraceOk (obligation : TraceObligation) : Bool :=
  match ProofForge.Backend.Evm.IR.lowerModule obligation.module with
  | .ok object =>
      match runEvmTrace object obligation.calls with
      | .ok actual => all2Array ObservableStep.evmCompatible actual obligation.expected
      | .error _ => false
  | .error _ => false

def counterTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint },
  { entrypoint := ProofForge.IR.Examples.Counter.get },
  { entrypoint := ProofForge.IR.Examples.Counter.increment },
  { entrypoint := ProofForge.IR.Examples.Counter.get }
]

def counterExpectedTrace : Array ObservableStep := #[
  { entrypointName := "initialize", selector := "8129fc1c", returnValue := .none },
  { entrypointName := "get", selector := "6d4ce63c", returnValue := .u64 0 },
  { entrypointName := "increment", selector := "d09de08a", returnValue := .none },
  { entrypointName := "get", selector := "6d4ce63c", returnValue := .u64 1 }
]

def counterTraceObligation : TraceObligation := {
  name := "Counter.initialize-get-increment-get"
  module := ProofForge.IR.Examples.Counter.module
  calls := counterTraceCalls
  expected := counterExpectedTrace
}

def valueVaultSelector? : String → Option String
  | "initialize" => some "fe4b84df"
  | "deposit" => some "b6b55f25"
  | "charge_fee" => some "be168a46"
  | "release" => some "37bdc99b"
  | "snapshot" => some "9711715a"
  | "get_balance" => some "c1cfb99a"
  | "get_net_value" => some "d43f79a2"
  | _ => none

def hydrateValueVaultEntrypoint (entrypoint : Entrypoint) : Entrypoint :=
  match valueVaultSelector? entrypoint.name with
  | some selector => { entrypoint with selector? := some selector }
  | none => entrypoint

def valueVaultEvmModule : Module :=
  let module := ProofForge.Contract.Examples.ValueVault.module
  { module with entrypoints := module.entrypoints.map hydrateValueVaultEntrypoint }

def missingEntrypoint (name : String) : Entrypoint := {
  name := name
  body := #[]
}

def entrypointByName (module : Module) (name : String) : Entrypoint :=
  (module.entrypoints.find? fun entrypoint => entrypoint.name == name).getD
    (missingEntrypoint name)

def valueVaultEntrypoint (name : String) : Entrypoint :=
  entrypointByName valueVaultEvmModule name

def irU64 (value : Nat) : ProofForge.IR.Semantics.Value :=
  .u64 value

def irU32 (value : Nat) : ProofForge.IR.Semantics.Value :=
  .u32 value

def irBool (value : Bool) : ProofForge.IR.Semantics.Value :=
  .bool value

def irHash (a b c d : Nat) : ProofForge.IR.Semantics.Value :=
  .hash a b c d

def evmHashWord (a b c d : Nat) : Nat :=
  a * ProofForge.Backend.Evm.YulSemantics.twoPow 192 +
    b * ProofForge.Backend.Evm.YulSemantics.twoPow 128 +
    c * ProofForge.Backend.Evm.YulSemantics.twoPow 64 +
    d

def irArray (values : List ProofForge.IR.Semantics.Value) : ProofForge.IR.Semantics.Value :=
  .array values

def irStruct (typeName : String) (fields : List (String × ProofForge.IR.Semantics.Value)) :
    ProofForge.IR.Semantics.Value :=
  .struct typeName fields

def irPair (left right : Nat) : ProofForge.IR.Semantics.Value :=
  irStruct "Pair" [("left", irU64 left), ("right", irU64 right)]

def eventLog (name signature : String) (indexed data : Array Nat) : ObservableEventLog := {
  eventName := name
  topics := #[eventSignatureTopic signature] ++ indexed
  dataWords := data
}

def aggregateTopic (words : Array Nat) : Nat :=
  ProofForge.Backend.Evm.YulSemantics.pseudoKeccakWords words

def valueVaultTraceCalls : Array TraceCall := #[
  { entrypoint := valueVaultEntrypoint "initialize", args := #[irU64 100], evmArgs := #[100] },
  { entrypoint := valueVaultEntrypoint "get_balance" },
  { entrypoint := valueVaultEntrypoint "deposit", args := #[irU64 25], evmArgs := #[25] },
  { entrypoint := valueVaultEntrypoint "get_balance" },
  { entrypoint := valueVaultEntrypoint "charge_fee", args := #[irU64 100, irU64 250], evmArgs := #[100, 250] },
  { entrypoint := valueVaultEntrypoint "get_balance" },
  { entrypoint := valueVaultEntrypoint "get_net_value" },
  { entrypoint := valueVaultEntrypoint "release", args := #[irU64 23], evmArgs := #[23] },
  { entrypoint := valueVaultEntrypoint "get_balance" },
  { entrypoint := valueVaultEntrypoint "snapshot" },
  { entrypoint := valueVaultEntrypoint "get_net_value" }
]

def valueVaultExpectedTrace : Array ObservableStep := #[
  {
    entrypointName := "initialize"
    selector := "fe4b84df"
    returnValue := .none
    logs := #[eventLog "VaultInitialized" "VaultInitialized(uint64,uint64)" #[] #[100, 0]]
  },
  { entrypointName := "get_balance", selector := "c1cfb99a", returnValue := .u64 100 },
  {
    entrypointName := "deposit"
    selector := "b6b55f25"
    returnValue := .none
    logs := #[eventLog "ValueDeposited" "ValueDeposited(uint64,uint64,uint64)" #[] #[25, 125, 2]]
  },
  { entrypointName := "get_balance", selector := "c1cfb99a", returnValue := .u64 125 },
  {
    entrypointName := "charge_fee"
    selector := "be168a46"
    returnValue := .none
    logs := #[eventLog "ValueCharged" "ValueCharged(uint64,uint64,uint64,uint64)" #[] #[100, 2, 98, 223]]
  },
  { entrypointName := "get_balance", selector := "c1cfb99a", returnValue := .u64 223 },
  { entrypointName := "get_net_value", selector := "d43f79a2", returnValue := .u64 221 },
  {
    entrypointName := "release"
    selector := "37bdc99b"
    returnValue := .none
    logs := #[eventLog "ValueReleased" "ValueReleased(uint64,uint64,uint64)" #[] #[23, 200, 23]]
  },
  { entrypointName := "get_balance", selector := "c1cfb99a", returnValue := .u64 200 },
  {
    entrypointName := "snapshot"
    selector := "9711715a"
    returnValue := .u64 200
    logs := #[eventLog "ValueSnapshot" "ValueSnapshot(uint64,uint64,uint64,uint64)" #[] #[200, 23, 2, 0]]
  },
  { entrypointName := "get_net_value", selector := "d43f79a2", returnValue := .u64 198 }
]

def valueVaultTraceObligation : TraceObligation := {
  name := "ValueVault.testkit-scenario"
  module := valueVaultEvmModule
  calls := valueVaultTraceCalls
  expected := valueVaultExpectedTrace
}

def expressionTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.EvmExpressionProbe.arithmeticU64 },
  { entrypoint := ProofForge.IR.Examples.EvmExpressionProbe.bitwiseU64 },
  { entrypoint := ProofForge.IR.Examples.EvmExpressionProbe.predicateMatrix },
  {
    entrypoint := ProofForge.IR.Examples.EvmExpressionProbe.castsAndU32
    args := #[.u32 7, .bool true]
    evmArgs := #[7, 1]
  }
]

def expressionExpectedTrace : Array ObservableStep := #[
  { entrypointName := "arithmetic_u64", selector := "139ade38", returnValue := .u64 40 },
  { entrypointName := "bitwise_u64", selector := "2e124ba8", returnValue := .u64 11 },
  { entrypointName := "predicate_matrix", selector := "219a55f8", returnValue := .u64 8 },
  { entrypointName := "casts_and_u32", selector := "555e000e", returnValue := .u64 50 }
]

def expressionTraceObligation : TraceObligation := {
  name := "EvmExpressionProbe.expression-assertion-trace"
  module := ProofForge.IR.Examples.EvmExpressionProbe.module
  calls := expressionTraceCalls
  expected := expressionExpectedTrace
}

def conditionalTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.ConditionalProbe.conditionalLifecycle }
]

def conditionalExpectedTrace : Array ObservableStep := #[
  { entrypointName := "conditional_lifecycle", selector := "f3380744", returnValue := .u64 10 }
]

def conditionalTraceObligation : TraceObligation := {
  name := "ConditionalProbe.if-else-storage-trace"
  module := ProofForge.IR.Examples.ConditionalProbe.module
  calls := conditionalTraceCalls
  expected := conditionalExpectedTrace
}

def loopTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.EvmLoopProbe.countToThree },
  {
    entrypoint := ProofForge.IR.Examples.EvmLoopProbe.chooseWithEarlyReturn
    args := #[irBool true]
    evmArgs := #[1]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmLoopProbe.chooseWithEarlyReturn
    args := #[irBool false]
    evmArgs := #[0]
  },
  { entrypoint := ProofForge.IR.Examples.EvmLoopProbe.loopEarlyReturn }
]

def loopExpectedTrace : Array ObservableStep := #[
  { entrypointName := "count_to_three", selector := "c4eff2de", returnValue := .u64 3 },
  { entrypointName := "choose_with_early_return", selector := "d9b42937", returnValue := .u64 11 },
  { entrypointName := "choose_with_early_return", selector := "d9b42937", returnValue := .u64 99 },
  { entrypointName := "loop_early_return", selector := "d11c9505", returnValue := .u64 0 }
]

def loopTraceObligation : TraceObligation := {
  name := "EvmLoopProbe.bounded-loop-and-early-return-trace"
  module := ProofForge.IR.Examples.EvmLoopProbe.module
  calls := loopTraceCalls
  expected := loopExpectedTrace
}

def eventTraceCalls : Array TraceCall := #[
  {
    entrypoint := ProofForge.IR.Examples.EventProbe.emitValueEvent
    args := #[irU64 42]
    evmArgs := #[42]
  },
  {
    entrypoint := ProofForge.IR.Examples.EventProbe.emitIndexedEvent
    args := #[irU64 7, irU64 99]
    evmArgs := #[7, 99]
  },
  {
    entrypoint := ProofForge.IR.Examples.EventProbe.emitTwoIndexedEvent
    args := #[irU64 1, irU64 2, irU64 3]
    evmArgs := #[1, 2, 3]
  },
  {
    entrypoint := ProofForge.IR.Examples.EventProbe.emitTypedScalarEvent
    args := #[irBool true, irU32 7, irHash 1 2 3 4]
    evmArgs := #[1, 7, evmHashWord 1 2 3 4]
  },
  {
    entrypoint := ProofForge.IR.Examples.EventProbe.emitPairEvent
    args := #[irU64 5, irU64 8]
    evmArgs := #[5, 8]
  },
  {
    entrypoint := ProofForge.IR.Examples.EventProbe.emitIndexedPairEvent
    args := #[irU64 5, irU64 8, irU64 13]
    evmArgs := #[5, 8, 13]
  }
]

def eventExpectedTrace : Array ObservableStep := #[
  {
    entrypointName := "emit_value_event"
    selector := "2ae8cae3"
    returnValue := .none
    logs := #[eventLog "ValueEvent" "ValueEvent(uint64)" #[] #[42]]
  },
  {
    entrypointName := "emit_indexed_event"
    selector := "bc07d04f"
    returnValue := .none
    logs := #[eventLog "IndexedValue" "IndexedValue(uint64,uint64)" #[7] #[99]]
  },
  {
    entrypointName := "emit_two_indexed_event"
    selector := "2d00700c"
    returnValue := .none
    logs := #[eventLog "IndexedTwoValues" "IndexedTwoValues(uint64,uint64,uint64)" #[1, 2] #[3]]
  },
  {
    entrypointName := "emit_typed_scalar_event"
    selector := "989413a3"
    returnValue := .none
    logs := #[eventLog "TypedScalarEvent" "TypedScalarEvent(bool,uint32,bytes32)" #[] #[1, 7, evmHashWord 1 2 3 4]]
  },
  {
    entrypointName := "emit_pair_event"
    selector := "35361bda"
    returnValue := .none
    logs := #[eventLog "PairEvent" "PairEvent((uint64,uint64))" #[] #[5, 8]]
  },
  {
    entrypointName := "emit_indexed_pair_event"
    selector := "e027f054"
    returnValue := .none
    logs := #[eventLog "IndexedPair" "IndexedPair((uint64,uint64),uint64)" #[aggregateTopic #[5, 8]] #[13]]
  }
]

def eventTraceObligation : TraceObligation := {
  name := "EventProbe.scalar-and-aggregate-log-trace"
  module := ProofForge.IR.Examples.EventProbe.evmModule
  calls := eventTraceCalls
  expected := eventExpectedTrace
}

/-! The following obligations extend the same IR-vs-emitted-Yul executable
    trace pattern across stateful maps, typed storage, storage aggregates, and
    ABI-facing aggregate values. Event-log observability now covers EventProbe
    scalar events, multi-topic indexed events, typed scalar payloads, struct
    data, and hashed aggregate indexed topics. -/

def evmMapTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.EvmMapProbe.mapLifecycle },
  { entrypoint := ProofForge.IR.Examples.EvmMapProbe.getSeedBalance },
  {
    entrypoint := ProofForge.IR.Examples.EvmMapProbe.containsBalance
    args := #[irU64 1001]
    evmArgs := #[1001]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmMapProbe.upsertBalance
    args := #[irU64 7007, irU64 123]
    evmArgs := #[7007, 123]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmMapProbe.readBalance
    args := #[irU64 7007]
    evmArgs := #[7007]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmMapProbe.setBalance
    args := #[irU64 7007, irU64 456]
    evmArgs := #[7007, 456]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmMapProbe.readBalance
    args := #[irU64 7007]
    evmArgs := #[7007]
  },
  { entrypoint := ProofForge.IR.Examples.EvmMapProbe.pathLifecycle },
  { entrypoint := ProofForge.IR.Examples.EvmMapProbe.pathAssignLifecycle },
  { entrypoint := ProofForge.IR.Examples.EvmMapProbe.nestedPathLifecycle },
  {
    entrypoint := ProofForge.IR.Examples.EvmMapProbe.nestedPathDynamic
    args := #[irU64 6006, irU64 7007, irU64 888]
    evmArgs := #[6006, 7007, 888]
  }
]

def evmMapExpectedTrace : Array ObservableStep := #[
  { entrypointName := "map_lifecycle", selector := "3bb39394", returnValue := .u64 55 },
  { entrypointName := "get_seed_balance", selector := "541be503", returnValue := .u64 55 },
  { entrypointName := "contains_balance", selector := "4c136189", returnValue := .bool true },
  { entrypointName := "upsert_balance", selector := "e1de6ac8", returnValue := .u64 0 },
  { entrypointName := "read_balance", selector := "68eb1eef", returnValue := .u64 123 },
  { entrypointName := "set_balance", selector := "b41d1f5c", returnValue := .none },
  { entrypointName := "read_balance", selector := "68eb1eef", returnValue := .u64 456 },
  { entrypointName := "path_lifecycle", selector := "84c21205", returnValue := .u64 77 },
  { entrypointName := "path_assign_lifecycle", selector := "bce9e77b", returnValue := .u64 58 },
  { entrypointName := "nested_path_lifecycle", selector := "13a524e0", returnValue := .u64 95 },
  { entrypointName := "nested_path_dynamic", selector := "ce6fd7c0", returnValue := .u64 888 }
]

def evmMapTraceObligation : TraceObligation := {
  name := "EvmMapProbe.map-storage-trace"
  module := ProofForge.IR.Examples.EvmMapProbe.module
  calls := evmMapTraceCalls
  expected := evmMapExpectedTrace
}

def evmMapContainsTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.EvmMapProbe.containsLifecycle },
  {
    entrypoint := ProofForge.IR.Examples.EvmMapProbe.containsBalance
    args := #[irU64 1001]
    evmArgs := #[1001]
  }
]

def evmMapContainsExpectedTrace : Array ObservableStep := #[
  { entrypointName := "contains_lifecycle", selector := "a0c7a60a", returnValue := .u64 99 },
  { entrypointName := "contains_balance", selector := "4c136189", returnValue := .bool true }
]

def evmMapContainsTraceObligation : TraceObligation := {
  name := "EvmMapProbe.presence-trace"
  module := ProofForge.IR.Examples.EvmMapProbe.module
  calls := evmMapContainsTraceCalls
  expected := evmMapContainsExpectedTrace
}

def typedStorageTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.EvmTypedStorageProbe.boolScalarLifecycle },
  { entrypoint := ProofForge.IR.Examples.EvmTypedStorageProbe.typedArrayLifecycle },
  {
    entrypoint := ProofForge.IR.Examples.EvmTypedStorageProbe.readFlag
    args := #[irU64 0]
    evmArgs := #[0]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmTypedStorageProbe.readFlag
    args := #[irU64 1]
    evmArgs := #[1]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmTypedStorageProbe.readRoot
    args := #[irU64 1]
    evmArgs := #[1]
  },
  { entrypoint := ProofForge.IR.Examples.EvmTypedStorageProbe.pathAssignU32 }
]

def typedStorageExpectedTrace : Array ObservableStep := #[
  { entrypointName := "bool_scalar_lifecycle", selector := "06422075", returnValue := .bool true },
  { entrypointName := "typed_array_lifecycle", selector := "9f3c504b", returnValue := .u64 32 },
  { entrypointName := "read_flag", selector := "afbe1175", returnValue := .bool true },
  { entrypointName := "read_flag", selector := "afbe1175", returnValue := .bool false },
  { entrypointName := "read_root", selector := "4994f441", returnValue := .hash 5 6 7 8 },
  { entrypointName := "path_assign_u32", selector := "5ab2cb77", returnValue := .u64 30 }
]

def typedStorageTraceObligation : TraceObligation := {
  name := "EvmTypedStorageProbe.array-storage-trace"
  module := ProofForge.IR.Examples.EvmTypedStorageProbe.module
  calls := typedStorageTraceCalls
  expected := typedStorageExpectedTrace
}

def storageStructTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.structLifecycle },
  { entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.pathLifecycle },
  { entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.arrayStructLifecycle },
  {
    entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.readPointX
    args := #[irU64 1]
    evmArgs := #[1]
  },
  { entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.typedSum },
  { entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.rootValue },
  { entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.wholeStructWriteSum },
  { entrypoint := ProofForge.IR.Examples.EvmStorageStructProbe.selfStructStorageWrite }
]

def storageStructExpectedTrace : Array ObservableStep := #[
  { entrypointName := "struct_lifecycle", selector := "93ddf147", returnValue := .u64 18 },
  { entrypointName := "path_lifecycle", selector := "84c21205", returnValue := .u64 48 },
  { entrypointName := "array_struct_lifecycle", selector := "2d84bb06", returnValue := .u64 12 },
  { entrypointName := "read_point_x", selector := "db006782", returnValue := .u64 7 },
  { entrypointName := "typed_sum", selector := "2ec467be", returnValue := .u64 34 },
  { entrypointName := "root_value", selector := "c42f8c06", returnValue := .hash 1 2 3 4 },
  { entrypointName := "whole_struct_write_sum", selector := "c1e31e63", returnValue := .u64 70 },
  { entrypointName := "self_struct_storage_write", selector := "696ddaa7", returnValue := .u64 705 }
]

def storageStructTraceObligation : TraceObligation := {
  name := "EvmStorageStructProbe.struct-storage-trace"
  module := ProofForge.IR.Examples.EvmStorageStructProbe.module
  calls := storageStructTraceCalls
  expected := storageStructExpectedTrace
}

def abiAggregateTraceCalls : Array TraceCall := #[
  {
    entrypoint := ProofForge.IR.Examples.EvmAbiAggregateProbe.sumPair
    args := #[irPair 7 11]
    evmArgs := #[7, 11]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmAbiAggregateProbe.sumArray
    args := #[irArray [irU64 2, irU64 3, irU64 5]]
    evmArgs := #[2, 3, 5]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmAbiAggregateProbe.sumMatrix
    args := #[irArray [irArray [irU64 1, irU64 2], irArray [irU64 3, irU64 4]]]
    evmArgs := #[1, 2, 3, 4]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmAbiAggregateProbe.sumPairArray
    args := #[irArray [irPair 1 2, irPair 3 4]]
    evmArgs := #[1, 2, 3, 4]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmAbiAggregateProbe.makePair
    args := #[irU64 13, irU64 21]
    evmArgs := #[13, 21]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmAbiAggregateProbe.makeArray
    args := #[irU64 3, irU64 5, irU64 8]
    evmArgs := #[3, 5, 8]
  },
  {
    entrypoint := ProofForge.IR.Examples.EvmAbiAggregateProbe.makeMatrix
    args := #[irU64 1, irU64 2, irU64 3, irU64 4]
    evmArgs := #[1, 2, 3, 4]
  }
]

def abiAggregateExpectedTrace : Array ObservableStep := #[
  { entrypointName := "sum_pair", selector := "25508e13", returnValue := .u64 18 },
  { entrypointName := "sum_array", selector := "eb353b80", returnValue := .u64 10 },
  { entrypointName := "sum_matrix", selector := "da76e471", returnValue := .u64 10 },
  { entrypointName := "sum_pair_array", selector := "10e4c1da", returnValue := .u64 10 },
  { entrypointName := "make_pair", selector := "ef51ff62", returnValue := .words #[13, 21] },
  { entrypointName := "make_array", selector := "ffac5c16", returnValue := .words #[3, 5, 8] },
  { entrypointName := "make_matrix", selector := "b61c11b8", returnValue := .words #[1, 2, 3, 4] }
]

def abiAggregateTraceObligation : TraceObligation := {
  name := "EvmAbiAggregateProbe.abi-aggregate-trace"
  module := ProofForge.IR.Examples.EvmAbiAggregateProbe.module
  calls := abiAggregateTraceCalls
  expected := abiAggregateExpectedTrace
}

theorem counter_ir_observable_trace_ok :
    counterTraceObligation.irTraceOk = true := by
  native_decide

theorem counter_evm_yul_surface_trace_entrypoints :
    counterTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem counter_evm_yul_executable_trace_ok :
    counterTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem value_vault_ir_observable_trace_ok :
    valueVaultTraceObligation.irTraceOk = true := by
  native_decide

theorem value_vault_evm_yul_surface_trace_entrypoints :
    valueVaultTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem value_vault_evm_yul_executable_trace_ok :
    valueVaultTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem expression_ir_observable_trace_ok :
    expressionTraceObligation.irTraceOk = true := by
  native_decide

theorem expression_evm_yul_surface_trace_entrypoints :
    expressionTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem expression_evm_yul_executable_trace_ok :
    expressionTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem conditional_ir_observable_trace_ok :
    conditionalTraceObligation.irTraceOk = true := by
  native_decide

theorem conditional_evm_yul_surface_trace_entrypoints :
    conditionalTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem conditional_evm_yul_executable_trace_ok :
    conditionalTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem loop_ir_observable_trace_ok :
    loopTraceObligation.irTraceOk = true := by
  native_decide

theorem loop_evm_yul_surface_trace_entrypoints :
    loopTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem loop_evm_yul_executable_trace_ok :
    loopTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem event_ir_observable_trace_ok :
    eventTraceObligation.irTraceOk = true := by
  native_decide

theorem event_evm_yul_surface_trace_entrypoints :
    eventTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem event_evm_yul_executable_trace_ok :
    eventTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem evm_map_ir_observable_trace_ok :
    evmMapTraceObligation.irTraceOk = true := by
  native_decide

theorem evm_map_yul_surface_trace_entrypoints :
    evmMapTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem evm_map_yul_executable_trace_ok :
    evmMapTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem evm_map_contains_ir_observable_trace_ok :
    evmMapContainsTraceObligation.irTraceOk = true := by
  native_decide

theorem evm_map_contains_yul_surface_trace_entrypoints :
    evmMapContainsTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem evm_map_contains_yul_executable_trace_ok :
    evmMapContainsTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem typed_storage_ir_observable_trace_ok :
    typedStorageTraceObligation.irTraceOk = true := by
  native_decide

theorem typed_storage_yul_surface_trace_entrypoints :
    typedStorageTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem typed_storage_yul_executable_trace_ok :
    typedStorageTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem storage_struct_ir_observable_trace_ok :
    storageStructTraceObligation.irTraceOk = true := by
  native_decide

theorem storage_struct_yul_surface_trace_entrypoints :
    storageStructTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem storage_struct_yul_executable_trace_ok :
    storageStructTraceObligation.evmYulTraceOk = true := by
  native_decide

theorem abi_aggregate_ir_observable_trace_ok :
    abiAggregateTraceObligation.irTraceOk = true := by
  native_decide

theorem abi_aggregate_yul_surface_trace_entrypoints :
    abiAggregateTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem abi_aggregate_yul_executable_trace_ok :
    abiAggregateTraceObligation.evmYulTraceOk = true := by
  native_decide

def contextTraceCalls : Array TraceCall := #[
  { entrypoint := ProofForge.IR.Examples.EvmContextProbe.contextExtras },
  { entrypoint := ProofForge.IR.Examples.EvmContextProbe.contextHashes }
]

def contextExpectedTrace : Array ObservableStep := #[
  { entrypointName := "context_extras", selector := "d9b80589", returnValue := .words #[0, 0, 0, 0, 0, 0] },
  { entrypointName := "context_hashes", selector := "b59b9225", returnValue := .words #[0, 0, 0] }
]

def contextTraceObligation : TraceObligation := {
  name := "EvmContextProbe.context-reads-trace"
  module := ProofForge.IR.Examples.EvmContextProbe.module
  calls := contextTraceCalls
  expected := contextExpectedTrace
}


theorem context_ir_observable_trace_ok :
    contextTraceObligation.irTraceOk = true := by
  native_decide

theorem context_evm_yul_surface_trace_entrypoints :
    contextTraceObligation.evmYulSurfaceOk = true := by
  native_decide

theorem context_evm_yul_executable_trace_ok :
    contextTraceObligation.evmYulTraceOk = true := by
  native_decide

end ProofForge.Backend.Evm.Refinement
