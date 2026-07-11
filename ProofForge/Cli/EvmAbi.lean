import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.AbiType
import ProofForge.Backend.Evm.Validate
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.HexUtil
import ProofForge.Cli.IrJson
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Process
import ProofForge.IR

open ProofForge.Cli.ConstructorAbi
open ProofForge.Cli.HexUtil
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

def selectorFor (cast : String) (sig : String) : IO String := do
  let stdout ← runProcess cast #["sig", sig]
  let selector := stripHexPrefix (trimAsciiString stdout)
  if selector.length != 8 || !isHexString selector then
    throw <| IO.userError s!"cast returned invalid selector for {sig}: {trimAsciiString stdout}"
  return selector

def entrypointAbiScalarTypeName
    (context : String)
    (type : ProofForge.IR.ValueType)
    (evmAbiWord? : Option String := none) : Except String String :=
  ProofForge.Backend.Evm.AbiType.scalarTypeName context type evmAbiWord?

partial def entrypointAbiType
    (module : ProofForge.IR.Module)
    (context : String)
    (type : ProofForge.IR.ValueType)
    (evmAbiWord? : Option String := none) : Except String String := do
  ProofForge.Backend.Evm.AbiType.typeName module context type evmAbiWord?

partial def entrypointAbiWordTypes
    (module : ProofForge.IR.Module)
    (context : String)
    (type : ProofForge.IR.ValueType) : Except String (Array String) := do
  ProofForge.Backend.Evm.AbiType.wordTypes module context type

def entrypointAbiValueJson
    (name? : Option String)
    (type : ProofForge.IR.ValueType)
    (abiType : String)
    (wordTypes : Array String) : String :=
  let encoding :=
    if type == .unit then "none"
    else if type == .bytes || type == .string then "abi-dynamic-bytes"
    else if match type with | .array _ => true | _ => false then "abi-dynamic-array"
    else "abi-static-words"
  let nameFields :=
    match name? with
    | some name => #[("name", jsonString name)]
    | none => #[]
  jsonObject (nameFields ++ #[
    ("type", valueTypeJson type),
    ("irType", valueTypeJson type),
    ("abiType", jsonString abiType),
    ("encoding", jsonString encoding),
    ("wordTypes", jsonStringArray wordTypes),
    ("wordCount", toString wordTypes.size)
  ])

def entrypointParamJson
    (module : ProofForge.IR.Module)
    (entrypointName : String)
    (param : String × ProofForge.IR.ValueType)
    (evmAbiWord? : Option String := none) : Except String (String × Nat × String) := do
  let abiType ← entrypointAbiType module s!"entrypoint `{entrypointName}` parameter `{param.fst}`" param.snd evmAbiWord?
  let wordTypes ← entrypointAbiWordTypes module s!"entrypoint `{entrypointName}` parameter `{param.fst}`" param.snd
  .ok (abiType, wordTypes.size, entrypointAbiValueJson (some param.fst) param.snd abiType wordTypes)

def entrypointParamEvmAbiWord (entrypoint : ProofForge.IR.Entrypoint) (index : Nat) : Option String :=
  if h : index < entrypoint.paramAbiWords.size then
    entrypoint.paramAbiWords[index]
  else
    none

def entrypointReturnJson
    (module : ProofForge.IR.Module)
    (entrypointName : String)
    (type : ProofForge.IR.ValueType)
    (abiWord? : Option String := none) : Except String (Nat × String) := do
  match type with
  | .unit =>
      .ok (0, entrypointAbiValueJson none type "void" #[])
  | _ => do
      let abiType ← entrypointAbiType module s!"entrypoint `{entrypointName}` return" type abiWord?
      let wordTypes ← entrypointAbiWordTypes module s!"entrypoint `{entrypointName}` return" type
      .ok (wordTypes.size, entrypointAbiValueJson none type abiType wordTypes)

def entrypointSoliditySignature
    (module : ProofForge.IR.Module)
    (entrypoint : ProofForge.IR.Entrypoint) : Except String String := do
  let mut paramAbiTypes := #[]
  for h : idx in [0:entrypoint.params.size] do
    let param := entrypoint.params[idx]
    let abiType ← entrypointAbiType module s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" param.snd
      (entrypointParamEvmAbiWord entrypoint idx)
    paramAbiTypes := paramAbiTypes.push abiType
  .ok s!"{entrypoint.name}({String.intercalate "," paramAbiTypes.toList})"

def hydrateEvmSelectors (cast : String) (module : ProofForge.IR.Module) :
    IO ProofForge.IR.Module := do
  let mut entrypoints := #[]
  for entrypoint in module.entrypoints do
    let signature ←
      match entrypointSoliditySignature module entrypoint with
      | .ok signature => pure signature
      | .error msg => throw <| IO.userError msg
    let derived ← selectorFor cast signature
    match entrypoint.selector? with
    | some selector =>
        if selector.toLower != derived.toLower then
          throw <| IO.userError
            s!"entrypoint `{entrypoint.name}` selector `{selector}` does not match ABI signature `{signature}` selector `{derived}`"
        entrypoints := entrypoints.push entrypoint
    | none =>
        entrypoints := entrypoints.push { entrypoint with selector? := some derived }
  return { module with entrypoints := entrypoints }

def entrypointJson (module : ProofForge.IR.Module) (entrypoint : ProofForge.IR.Entrypoint) : Except String String := do
  let mut params := #[]
  let mut paramAbiTypes := #[]
  let mut calldataWords := 0
  for h : idx in [0:entrypoint.params.size] do
    let param := entrypoint.params[idx]
    let (abiType, wordCount, paramJson) ← entrypointParamJson module entrypoint.name param
      (entrypointParamEvmAbiWord entrypoint idx)
    params := params.push paramJson
    paramAbiTypes := paramAbiTypes.push abiType
    calldataWords := calldataWords + wordCount
  let (returnWords, returnValue) ← entrypointReturnJson module entrypoint.name entrypoint.returns
    entrypoint.returnAbiWord?
  let signature := s!"{entrypoint.name}({String.intercalate "," paramAbiTypes.toList})"
  let selectorValue :=
    match entrypoint.selector? with
    | some selector => jsonString selector
    | none =>
      match entrypoint.kind with
      | .fallback => jsonString "fallback"
      | .receive => jsonString "receive"
      | .function => "null"
  .ok <| jsonObject #[
    ("name", jsonString entrypoint.name),
    ("selector", selectorValue),
    ("signature", jsonString signature),
    ("mutability", jsonString entrypoint.mutability.id),
    ("params", jsonArray params),
    ("returns", valueTypeJson entrypoint.returns),
    ("returnValue", returnValue),
    ("calldataWords", toString calldataWords),
    ("returnWords", toString returnWords)
  ]

structure EventAbiField where
  name : String
  irType : ProofForge.IR.ValueType
  abiType : String
  indexed : Bool
  wordTypes : Array String
  deriving BEq, Repr

structure EventAbi where
  name : String
  signature : String
  topic0 : String
  indexedFields : Array EventAbiField
  dataFields : Array EventAbiField
  deriving BEq, Repr

def lowerExceptString (result : Except ProofForge.Backend.Evm.IR.LowerError α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error err => .error err.render

def lowerValidateExceptString (result : Except ProofForge.Backend.Evm.Validate.LowerError α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error err => .error err.message

def liftExceptString (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error msg => throw <| IO.userError msg

def eventAbiWordTypeName : ProofForge.IR.ValueType → Except String String
  | .u8 => .ok "uint8"
  | .u32 => .ok "uint32"
  | .u64 => .ok "uint64"
  | .u128 => .ok "uint128"
  | .bool => .ok "bool"
  | .hash => .ok "bytes32"
  | .address => .ok "address"
  | type => .error s!"event ABI word type must be scalar, got `{type.name}`"

def eventAbiField
    (module : ProofForge.IR.Module)
    (env : ProofForge.Backend.Evm.IR.TypeEnv)
    (eventName : String)
    (indexed : Bool)
    (field : String × ProofForge.IR.Expr) : Except String EventAbiField := do
  let irType ← lowerExceptString <|
    ProofForge.Backend.Evm.IR.inferExprType module env field.snd
  let abiType ← lowerValidateExceptString <|
    ProofForge.Backend.Evm.Validate.eventSignatureFieldType module eventName field.fst irType
  let wordTypes ← lowerExceptString <|
    ProofForge.Backend.Evm.IR.abiValueWordTypes module s!"event `{eventName}` field `{field.fst}`" irType
  let mut wordTypeNames : Array String := #[]
  if wordTypes.size == 1 &&
      match irType with
      | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
      | _ => false then
    wordTypeNames := #[abiType]
  else
    for wordType in wordTypes do
      wordTypeNames := wordTypeNames.push (← eventAbiWordTypeName wordType)
  .ok {
    name := field.fst,
    irType := irType,
    abiType := abiType,
    indexed := indexed,
    wordTypes := wordTypeNames
  }

def eventAbiFieldJson (field : EventAbiField) : String :=
  let encoding :=
    if field.indexed then
      if field.wordTypes.size == 1 then
        "indexed-word"
      else
        "indexed-keccak256"
    else
      "abi-static-words"
  jsonObject #[
    ("name", jsonString field.name),
    ("type", jsonString field.abiType),
    ("irType", valueTypeJson field.irType),
    ("indexed", jsonBool field.indexed),
    ("encoding", jsonString encoding),
    ("wordTypes", jsonStringArray field.wordTypes),
    ("wordCount", toString field.wordTypes.size)
  ]

def eventFieldsWordCount (fields : Array EventAbiField) : Nat :=
  fields.foldl (fun count field => count + field.wordTypes.size) 0

def eventTopic0For (cast signature : String) : IO String := do
  let stdout ← runProcess cast #["keccak", signature]
  let topic := stripHexPrefix (trimAsciiString stdout)
  if topic.length == 64 && isHexString topic then
    return "0x" ++ lowerHexString topic
  else
    throw <| IO.userError s!"cast returned invalid event topic for {signature}: {trimAsciiString stdout}"

def eventAbi
    (cast : String)
    (module : ProofForge.IR.Module)
    (env : ProofForge.Backend.Evm.IR.TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × ProofForge.IR.Expr)) : IO EventAbi := do
  let signature ← liftExceptString <| lowerExceptString <|
    ProofForge.Backend.Evm.IR.eventSignature module env name (indexedFields ++ dataFields)
  let topic0 ← eventTopic0For cast signature
  let indexed ← liftExceptString <| indexedFields.foldlM (init := #[]) fun acc field => do
    .ok (acc.push (← eventAbiField module env name true field))
  let data ← liftExceptString <| dataFields.foldlM (init := #[]) fun acc field => do
    .ok (acc.push (← eventAbiField module env name false field))
  return {
    name := name,
    signature := signature,
    topic0 := topic0,
    indexedFields := indexed,
    dataFields := data
  }

def eventAbiJson (event : EventAbi) : String :=
  jsonObject #[
    ("name", jsonString event.name),
    ("signature", jsonString event.signature),
    ("topic0", jsonString event.topic0),
    ("anonymous", "false"),
    ("indexedFields", jsonArray (event.indexedFields.map eventAbiFieldJson)),
    ("dataFields", jsonArray (event.dataFields.map eventAbiFieldJson)),
    ("topics", toString (event.indexedFields.size + 1)),
    ("dataWords", toString (eventFieldsWordCount event.dataFields))
  ]

def mergeEventAbis (left right : Array EventAbi) : Except String (Array EventAbi) :=
  right.foldlM (init := left) fun acc event => do
    match acc.find? (fun existing => existing.signature == event.signature) with
    | none => .ok (acc.push event)
    | some existing =>
        if existing == event then
          .ok acc
        else
          .error s!"conflicting EVM event ABI metadata for signature `{event.signature}`"

mutual
  partial def eventAbisInStatements
      (cast : String)
      (module : ProofForge.IR.Module)
      (env : ProofForge.Backend.Evm.IR.TypeEnv)
      (statements : Array ProofForge.IR.Statement) :
      IO (Array EventAbi × ProofForge.Backend.Evm.IR.TypeEnv) := do
    let mut events : Array EventAbi := #[]
    let mut currentEnv := env
    for statement in statements do
      let (statementEvents, nextEnv) ← eventAbisInStatement cast module currentEnv statement
      events ← liftExceptString <| mergeEventAbis events statementEvents
      currentEnv := nextEnv
    return (events, currentEnv)

  partial def eventAbisInStatement
      (cast : String)
      (module : ProofForge.IR.Module)
      (env : ProofForge.Backend.Evm.IR.TypeEnv) :
      ProofForge.IR.Statement → IO (Array EventAbi × ProofForge.Backend.Evm.IR.TypeEnv)
    | .letBind name type _ => do
        let nextEnv ← liftExceptString <| lowerExceptString <|
          ProofForge.Backend.Evm.IR.addLocal env name type false
        return (#[], nextEnv)
    | .letMutBind name type _ => do
        let nextEnv ← liftExceptString <| lowerExceptString <|
          ProofForge.Backend.Evm.IR.addLocal env name type true
        return (#[], nextEnv)
    | .assign _ _ | .assignOp _ _ _ | .assert _ _ _ | .assertEq _ _ _ _ | .return _
    | .release _ | .revert _ | .revertWithError _ =>
        return (#[], env)
    | .effect (.eventEmit name fields) => do
        let event ← eventAbi cast module env name #[] fields
        return (#[event], env)
    | .effect (.eventEmitIndexed name indexedFields dataFields) => do
        let event ← eventAbi cast module env name indexedFields dataFields
        return (#[event], env)
    | .effect _ =>
        return (#[], env)
    | .ifElse _ thenBody elseBody => do
        let (thenEvents, _) ← eventAbisInStatements cast module env thenBody
        let (elseEvents, _) ← eventAbisInStatements cast module env elseBody
        let events ← liftExceptString <| mergeEventAbis thenEvents elseEvents
        return (events, env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← liftExceptString <| lowerExceptString <|
          ProofForge.Backend.Evm.IR.addLocal env indexName .u32 false
        let (events, _) ← eventAbisInStatements cast module loopEnv body
        return (events, env)
    | .whileLoop _cond body => do
        let (events, _) ← eventAbisInStatements cast module env body
        return (events, env)
end

def eventAbisForModule (cast : String) (module : ProofForge.IR.Module) : IO (Array EventAbi) := do
  let mut events : Array EventAbi := #[]
  for entrypoint in module.entrypoints do
    let (entrypointEvents, _) ←
      eventAbisInStatements cast module (ProofForge.Backend.Evm.IR.entrypointTypeEnv entrypoint) entrypoint.body
    events ← liftExceptString <| mergeEventAbis events entrypointEvents
  return events

def constructorParamJson (param : ConstructorParamSpec) : String :=
  let fields : Array (String × String) := #[
    ("name", jsonString param.name),
    ("type", jsonString param.abiType),
    ("encoding", jsonString (constructorParamEncoding param.abiType)),
    ("slotBytes", "32")
  ]
  let fields :=
    if param.abiType == "uint256[]" then
      fields.push ("elementType", jsonString "uint256")
    else
      fields
  jsonObject fields

def constructorAbiJson (params : Array ConstructorParamSpec) : String :=
  jsonObject #[
    ("params", jsonArray (params.map constructorParamJson)),
    ("encoding", jsonString "abi")
  ]


end ProofForge.Cli
