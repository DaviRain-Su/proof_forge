import ProofForge.Contract.Spec
import ProofForge.IR.Contract

namespace ProofForge.Contract.Spec.Json

open ProofForge.IR

def jsonString (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

def jsonBool (value : Bool) : String :=
  if value then "true" else "false"

def jsonArray (items : Array String) : String :=
  "[" ++ String.intercalate ", " items.toList ++ "]"

def jsonObject (fields : Array (String × String)) : String :=
  "{" ++
    String.intercalate ", " (fields.toList.map fun field =>
      jsonString field.fst ++ ": " ++ field.snd) ++
  "}"

def jsonStringOption : Option String → String
  | some value => jsonString value
  | none => "null"

def jsonStringArray (values : Array String) : String :=
  jsonArray (values.map jsonString)

def jsonUInt32 (value : UInt32) : String :=
  toString value.toNat

def valueTypeJson (type : ValueType) : String := jsonString type.name

def paramJson (param : String × ValueType) : String :=
  jsonObject #[
    ("name", jsonString param.fst),
    ("type", valueTypeJson param.snd)
  ]

def entrypointJson (entrypoint : Entrypoint) : String :=
  jsonObject #[
    ("name", jsonString entrypoint.name),
    ("selector", jsonStringOption entrypoint.selector?),
    ("returns", valueTypeJson entrypoint.returns),
    ("params", jsonArray (entrypoint.params.map paramJson))
  ]

def stateJson (state : StateDecl) : String :=
  jsonObject #[
    ("id", jsonString state.id),
    ("kind", jsonString (match state.kind with
      | .scalar => "scalar"
      | .map _ _ => "map"
      | .array _ => "array"
      | .dynamicArray => "dynamic_array")),
    ("type", valueTypeJson state.type)
  ]

def intentKindJson : ProofForge.Contract.IntentKind → String
  | .module => jsonString "module"
  | .state => jsonString "state"
  | .entrypoint => jsonString "entrypoint"
  | .capability => jsonString "capability"

def intentJson (intent : ProofForge.Contract.Intent) : String :=
  jsonObject #[
    ("kind", intentKindJson intent.kind),
    ("label", jsonString intent.label)
  ]

def pushUnique (values : Array String) (value : String) : Array String :=
  if values.any (fun existing => existing == value) then values else values.push value

def dedupStrings (values : Array String) : Array String :=
  values.foldl pushUnique #[]

structure ErrorCatalogEntry where
  assertionId : UInt32
  userCode? : Option String := none
  message : String
  entrypoints : Array String
  deriving Repr

def ErrorCatalogEntry.matches (entry : ErrorCatalogEntry) (ref : ErrorRef) (message : String) : Bool :=
  entry.assertionId == ref.assertionId &&
    entry.userCode? == ref.userCode? &&
    entry.message == message

def addErrorRef (entrypointName message : String) (ref : ErrorRef)
    (entries : Array ErrorCatalogEntry) : Array ErrorCatalogEntry :=
  let rec merge : List ErrorCatalogEntry → List ErrorCatalogEntry
    | [] => [{
        assertionId := ref.assertionId
        userCode? := ref.userCode?
        message
        entrypoints := #[entrypointName]
      }]
    | entry :: rest =>
        if entry.matches ref message then
          { entry with entrypoints := pushUnique entry.entrypoints entrypointName } :: rest
        else
          entry :: merge rest
  (merge entries.toList).toArray

partial def collectStatementErrors (entrypointName : String)
    (entries : Array ErrorCatalogEntry) : Statement → Array ErrorCatalogEntry
  | .assert _ message (some ref) => addErrorRef entrypointName message ref entries
  | .assertEq _ _ message (some ref) => addErrorRef entrypointName message ref entries
  | .ifElse _ thenBody elseBody =>
      let entries := thenBody.foldl (collectStatementErrors entrypointName) entries
      elseBody.foldl (collectStatementErrors entrypointName) entries
  | .boundedFor _ _ _ body =>
      body.foldl (collectStatementErrors entrypointName) entries
  | _ => entries

def collectEntrypointErrors (entries : Array ErrorCatalogEntry)
    (entrypoint : Entrypoint) : Array ErrorCatalogEntry :=
  entrypoint.body.foldl (collectStatementErrors entrypoint.name) entries

def errorCatalog (module : Module) : Array ErrorCatalogEntry :=
  module.entrypoints.foldl collectEntrypointErrors #[]

def errorCatalogEntryJson (entry : ErrorCatalogEntry) : String :=
  jsonObject #[
    ("assertionId", jsonUInt32 entry.assertionId),
    ("userCode", jsonStringOption entry.userCode?),
    ("message", jsonString entry.message),
    ("entrypoints", jsonStringArray entry.entrypoints)
  ]

def render (spec : ContractSpec) : String :=
  let upgradePolicyField :=
    match spec.upgradePolicy? with
    | some policy => ("upgradePolicy", UpgradePolicy.json policy)
    | none => ("upgradePolicy", "null")
  let proxyPatternField :=
    match spec.proxyPattern? with
    | some pattern => ("proxyPattern", ProxyPattern.json pattern)
    | none => ("proxyPattern", "null")
  jsonObject #[
    ("schema", jsonString "proof-forge.contract-spec.v0"),
    ("name", jsonString spec.name),
    ("irVersion", jsonString "portable-ir-v0"),
    ("state", jsonArray (spec.module.state.map stateJson)),
    ("entrypoints", jsonArray (spec.module.entrypoints.map entrypointJson)),
    ("capabilities", jsonStringArray (dedupStrings (spec.module.capabilities.map fun c => c.id))),
    ("intents", jsonArray (spec.intents.map intentJson)),
    ("errors", jsonArray (errorCatalog spec.module |>.map errorCatalogEntryJson)),
    upgradePolicyField,
    proxyPatternField
  ]

end ProofForge.Contract.Spec.Json
