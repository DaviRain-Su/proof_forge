import ProofForge.Contract.Spec.Json
import ProofForge.Target.Registry
import ProofForge.Util.StringUtil

namespace ProofForge.Contract.SdkSchema

open ProofForge.IR
open ProofForge.Target
open ProofForge.Util.StringUtil

def schemaId : String := "proof-forge.sdk-schema.v0"

def schemaVersion : Nat := 0

def irVersion : String := "portable-ir-v0"

abbrev JsonField := String × String

structure FileRef where
  path : String
  sha256 : String
  bytes : Nat
  deriving Repr, BEq

structure TargetExtension where
  key : String
  targetId : String
  fields : Array JsonField
  requiredCapabilities : Array Capability := #[]
  deriving Repr

namespace Json

def string := ProofForge.Contract.Spec.Json.jsonString

def array := ProofForge.Contract.Spec.Json.jsonArray

def object := ProofForge.Contract.Spec.Json.jsonObject

def stringArray := ProofForge.Contract.Spec.Json.jsonStringArray

def stringOption := ProofForge.Contract.Spec.Json.jsonStringOption

end Json

def runProcess (cmd : String) (args : Array String) : IO String := do
  let output ← IO.Process.output { cmd := cmd, args := args }
  if output.exitCode != 0 then
    let stderr := trimAscii output.stderr
    let stdout := trimAscii output.stdout
    let detail := if stderr.isEmpty then stdout else stderr
    throw <| IO.userError s!"{cmd} failed: {detail}"
  return output.stdout

def joinPath (dir rel : String) : String :=
  if dir.isEmpty then rel
  else if dir.endsWith "/" then dir ++ rel
  else dir ++ "/" ++ rel

def fileDigestAndBytes (path : String) : IO (String × Nat) := do
  let script := "import hashlib, pathlib, sys; data = pathlib.Path(sys.argv[1]).read_bytes(); print(hashlib.sha256(data).hexdigest(), len(data))"
  let stdout ← runProcess "python3" #["-c", script, path]
  match (trimAscii stdout).splitOn " " with
  | [digest, byteCount] =>
      match byteCount.toNat? with
      | some bytes => return (digest, bytes)
      | none => throw <| IO.userError s!"invalid byte count for {path}: {byteCount}"
  | _ => throw <| IO.userError s!"invalid sha256 output for {path}: {stdout}"

def FileRef.fromRelative (schemaDir relPath : String) : IO FileRef := do
  let (digest, bytes) ← fileDigestAndBytes (joinPath schemaDir relPath)
  return { path := relPath, sha256 := digest, bytes := bytes }

def hasPrefix (pref value : String) : Bool :=
  value.length >= pref.length && value.take pref.length == pref

def isAbsolutePath (path : String) : Bool :=
  hasPrefix "/" path || hasPrefix "~/" path

def hasParentEscape (path : String) : Bool :=
  path.splitOn "/" |>.any (fun segment => segment == "..")

def validateRelativeRef (label : String) (ref : FileRef) : Except String Unit := do
  if ref.path.isEmpty then
    .error s!"SDK schema reference {label} has an empty path"
  else if isAbsolutePath ref.path then
    .error s!"SDK schema reference {label} must be relative, got {ref.path}"
  else if hasParentEscape ref.path then
    .error s!"SDK schema reference {label} must not escape its SDK directory, got {ref.path}"
  else
    .ok ()

def FileRef.json (ref : FileRef) : String :=
  Json.object #[
    ("path", Json.string ref.path),
    ("sha256", Json.string ref.sha256),
    ("bytes", toString ref.bytes)
  ]

def refsJson (refs : Array (String × FileRef)) : String :=
  Json.object (refs.map fun ref => (ref.fst, ref.snd.json))

def valueTypeJson (type : ValueType) : String :=
  Json.string type.name

def paramJson (param : String × ValueType) : String :=
  Json.object #[
    ("name", Json.string param.fst),
    ("type", valueTypeJson param.snd)
  ]

def stateKindJson : StateKind → String
  | .scalar => Json.string "scalar"
  | .map _ _ => Json.string "map"
  | .array _ => Json.string "array"
  | .dynamicArray => Json.string "dynamic_array"

def stateJson (state : StateDecl) : String :=
  Json.object #[
    ("id", Json.string state.id),
    ("kind", stateKindJson state.kind),
    ("type", valueTypeJson state.type)
  ]

def structFieldJson (field : StructField) : String :=
  Json.object #[
    ("name", Json.string field.id),
    ("type", valueTypeJson field.type),
    ("public", if field.isPublic then "true" else "false"),
    ("ref", if field.isRef then "true" else "false")
  ]

def structJson (decl : StructDecl) : String :=
  Json.object #[
    ("name", Json.string decl.name),
    ("fields", Json.array (decl.fields.map structFieldJson)),
    ("semantics", Json.string decl.semantics.id),
    ("deriveStorage", if decl.deriveStorage then "true" else "false"),
    ("public", if decl.isPublic then "true" else "false")
  ]

def entrypointJson (entrypoint : Entrypoint) : String :=
  Json.object #[
    ("name", Json.string entrypoint.name),
    ("selector", Json.stringOption entrypoint.selector?),
    ("mutability", Json.string entrypoint.mutability.id),
    ("params", Json.array (entrypoint.params.map paramJson)),
    ("returns", valueTypeJson entrypoint.returns)
  ]

def pushUnique [BEq α] (values : Array α) (value : α) : Array α :=
  if values.any (fun existing => existing == value) then values else values.push value

def dedup [BEq α] (values : Array α) : Array α :=
  values.foldl pushUnique #[]

def dedupStrings (values : Array String) : Array String :=
  values.foldl pushUnique #[]

mutual
  partial def collectExprEvents (events : Array String) : Expr → Array String
    | .arrayLit _ values => values.foldl collectExprEvents events
    | .arrayGet array index => collectExprEvents (collectExprEvents events array) index
    | .memoryArrayNew _ length => collectExprEvents events length
    | .memoryArrayLength array => collectExprEvents events array
    | .memoryArrayGet array index => collectExprEvents (collectExprEvents events array) index
    | .structLit _ fields => fields.foldl (fun acc field => collectExprEvents acc field.snd) events
    | .field base _ => collectExprEvents events base
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        collectExprEvents (collectExprEvents events lhs) rhs
    | .cast value _ | .boolNot value | .hash value => collectExprEvents events value
    | .hashValue a b c d =>
        collectExprEvents (collectExprEvents (collectExprEvents (collectExprEvents events a) b) c) d
    | .ecrecover a b c d =>
        collectExprEvents (collectExprEvents (collectExprEvents (collectExprEvents events a) b) c) d
    | .eip712PermitDigest a b c d e f =>
        collectExprEvents
          (collectExprEvents
            (collectExprEvents
              (collectExprEvents
                (collectExprEvents (collectExprEvents events a) b) c) d) e) f
    | .crosscallAbiPacked target _ _ _ _ _ dynLen? _ dynTargets =>
        let events₁ := collectExprEvents events target
        let events₂ :=
          match dynLen? with
          | some e => collectExprEvents events₁ e
          | none => events₁
        dynTargets.foldl collectExprEvents events₂
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        args.foldl collectExprEvents (collectExprEvents (collectExprEvents events target) methodId)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        args.foldl collectExprEvents
          (collectExprEvents (collectExprEvents (collectExprEvents events target) methodId) callValue)
    | .crosscallCreate callValue _ => collectExprEvents events callValue
    | .crosscallCreate2 callValue salt _ => collectExprEvents (collectExprEvents events callValue) salt
    | .crosscallNamed _ _ args _ => args.foldl collectExprEvents events
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
        let events' := collectExprEvents (collectExprEvents (collectExprEvents events parentPromise) callbackMethod) deposit
        args.foldl (fun acc arg => collectExprEvents acc arg) events'
    | .nearPromiseResultsCount => events
    | .nearPromiseResultStatus index => collectExprEvents events index
    | .nearPromiseResultU64 index => collectExprEvents events index
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        let events₁ := collectExprEvents events accountIndex
        let events₂ := collectExprEvents events₁ methodId
        let events₃ := collectExprEvents events₂ deposit
        args.foldl collectExprEvents events₃
    | .effect effect => collectEffectEvents events effect
    | .literal _ | .local _ | .nativeValue => events

  partial def collectEffectEvents (events : Array String) : Effect → Array String
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageArrayWrite _ _ value
    | .storageArrayStructFieldWrite _ _ _ value
    | .storageDynamicArrayPush _ value
    | .memoryArraySet _ _ value
    | .storageStructFieldWrite _ _ value
    | .storagePathWrite _ _ value
    | .storagePathAssignOp _ _ _ value =>
        collectExprEvents events value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        collectExprEvents events key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value =>
        collectExprEvents (collectExprEvents events key) value
    | .eventEmit name fields
    | .eventEmitIndexed name fields _ =>
        fields.foldl (fun acc field => collectExprEvents acc field.snd) (pushUnique events name)
    | .checkErc721Received operator fromAddr toAddr tokenId =>
        collectExprEvents
          (collectExprEvents
            (collectExprEvents (collectExprEvents events operator) fromAddr) toAddr) tokenId
    | .checkErc1155Received operator fromAddr toAddr id amount =>
        collectExprEvents
          (collectExprEvents
            (collectExprEvents
              (collectExprEvents (collectExprEvents events operator) fromAddr) toAddr) id) amount
    | .checkErc1155BatchReceived operator fromAddr toAddr id0 amount0 id1 amount1 =>
        collectExprEvents
          (collectExprEvents
            (collectExprEvents
              (collectExprEvents
                (collectExprEvents
                  (collectExprEvents (collectExprEvents events operator) fromAddr) toAddr) id0) amount0) id1) amount1
    | .storageScalarRead _
    | .storageDynamicArrayPop _
    | .storageStructFieldRead _ _
    | .storagePathRead _ _
    | .contextRead _ => events

  partial def collectStatementEvents (events : Array String) : Statement → Array String
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assign _ value
    | .assignOp _ _ value
    | .return value => collectExprEvents events value
    | .effect effect => collectEffectEvents events effect
    | .assert condition _ _ => collectExprEvents events condition
    | .assertEq lhs rhs _ _ => collectExprEvents (collectExprEvents events lhs) rhs
    | .ifElse condition thenBody elseBody =>
        let events := collectExprEvents events condition
        let events := thenBody.foldl collectStatementEvents events
        elseBody.foldl collectStatementEvents events
    | .boundedFor _ _ _ body
    | .whileLoop _ body => body.foldl collectStatementEvents events
    | .revert _ | .revertWithError _ | .release _ => events
end

def eventJson (name : String) : String :=
  Json.object #[("name", Json.string name)]

def eventsJson (module : Module) : String :=
  let events := module.entrypoints.foldl
    (fun acc entrypoint => entrypoint.body.foldl collectStatementEvents acc) #[]
  Json.array (events.map eventJson)

def sdkSupportedCapabilities (profile : TargetProfile) : Array Capability :=
  if profile.id == "move-sui" then
    #[
      .storageScalar,
      .assertions,
      .accountExplicit
    ]
  else
    profile.capabilities

def capabilityIdsJson (capabilities : Array Capability) : String :=
  Json.stringArray (dedupStrings (capabilities.map Capability.id))

def unsupportedCapabilities (targetId : String) (capabilities : Array Capability) : Except String (Array Capability) := do
  let some profile := Target.find? targetId
    | .error s!"unknown SDK schema target `{targetId}`"
  let supported := sdkSupportedCapabilities profile
  return dedup capabilities |>.filter (fun capability => !supported.contains capability)

def requireCapabilitiesSupported (targetId context : String) (capabilities : Array Capability) : Except String Unit := do
  let unsupported ← unsupportedCapabilities targetId capabilities
  if unsupported.isEmpty then
    .ok ()
  else
    let ids := String.intercalate ", " (unsupported.map Capability.id).toList
    .error s!"SDK schema target `{targetId}` cannot advertise unsupported {context} capability/capabilities: {ids}"

def extensionKeyForTarget? : String → Option String
  | "evm" => some "evm"
  | "solana-sbpf-asm" => some "solana"
  | "wasm-near" => some "near"
  | "wasm-stellar-soroban" => some "soroban"
  | "wasm-cosmwasm" => some "cosmwasm"
  | "move-sui" => some "sui"
  | _ => none

def extensionKeyForTarget (targetId : String) : String :=
  (extensionKeyForTarget? targetId).getD targetId

def stringListFieldsJson (values : Array String) : String :=
  Json.stringArray values

def defaultExtension (targetId : String) : TargetExtension :=
  match targetId with
  | "evm" => {
      key := "evm"
      targetId := targetId
      fields := #[
        ("abi", Json.string "ProofForge EVM ABI metadata"),
        ("runtimeBytecode", Json.string "Counter.bin"),
        ("initCode", Json.string "Counter.init.bin"),
        ("deployManifest", Json.string "proof-forge-deploy.json"),
        ("typescriptWrapper", Json.string "proof-forge-evm-abi.ts"),
        ("constructorArgs", Json.array #[])
      ]
    }
  | "solana-sbpf-asm" => {
      key := "solana"
      targetId := targetId
      fields := #[
        ("idl", Json.string "proof-forge-idl.json"),
        ("client", Json.string "proof-forge-client.ts"),
        ("manifest", Json.string "manifest.toml"),
        ("accounts", Json.array #[]),
        ("pda", Json.array #[]),
        ("cpi", Json.array #[]),
        ("computeBudget", Json.object #[("status", Json.string "not-required")])
      ]
      requiredCapabilities := #[.accountExplicit]
    }
  | "wasm-near" => {
      key := "near"
      targetId := targetId
      fields := #[
        ("wat", Json.string "counter.wat"),
        ("wasm", Json.string "counter.wasm"),
        ("deployManifest", Json.string "proof-forge-deploy.json"),
        ("contractSpec", Json.string "Counter.contract-spec.json"),
        ("typescriptWrapper", Json.string "proof-forge-near.ts"),
        ("offlineHost", Json.string "runtime/offline-host"),
        ("callOptions", Json.object #[
          ("gas", Json.string "optional"),
          ("deposit", Json.string "optional")
        ])
      ]
    }
  | "wasm-cosmwasm" => {
      key := "cosmwasm"
      targetId := targetId
      fields := #[
        ("wat", Json.string "counter.wat"),
        ("wasm", Json.string "counter.wasm"),
        ("deployManifest", Json.string "proof-forge-deploy.json"),
        ("contractSpec", Json.string "Counter.contract-spec.json"),
        ("typescriptWrapper", Json.string "proof-forge-cosmwasm.ts"),
        ("offlineHost", Json.string "runtime/offline-host"),
        ("executeMsg", Json.string "stub (PF-P3-02; full submessages follow-on)")
      ]
    }
  | "move-sui" => {
      key := "sui"
      targetId := targetId
      fields := #[
        ("packageDir", Json.string "."),
        ("packageName", Json.string "counter"),
        ("module", Json.string "counter"),
        ("moduleAddress", Json.string "proof_forge"),
        ("client", Json.string "proof-forge-client.ts"),
        ("moveToml", Json.string "Move.toml"),
        ("sources", Json.stringArray #["sources/counter.move"]),
        ("tests", Json.stringArray #["tests/counter_tests.move"]),
        ("object", Json.object #[
          ("type", Json.string "Counter"),
          ("objectType", Json.string "Counter"),
          ("moveType", Json.string "proof_forge::counter::Counter"),
          ("uidField", Json.string "id"),
          ("uidType", Json.string "UID"),
          ("ownership", Json.string "owned-object")
        ]),
        ("stateFieldMapping", Json.object #[
          ("count", Json.object #[
            ("field", Json.string "count"),
            ("type", Json.string "u64"),
            ("moveType", Json.string "u64"),
            ("objectField", Json.string "Counter.count")
          ])
        ]),
        ("entrypoints", Json.object #[
          ("create", Json.object #[
            ("txContext", Json.string "&mut TxContext"),
            ("objectRequirements", Json.array #[]),
            ("returns", Json.string "Counter"),
            ("returnsOrTransfers", Json.string "returns new Counter")
          ]),
          ("initialize", Json.object #[
            ("txContext", Json.string "&mut TxContext"),
            ("objectRequirements", Json.array #[]),
            ("returns", Json.string "Counter"),
            ("returnsOrTransfers", Json.string "returns new Counter")
          ]),
          ("increment", Json.object #[
            ("object", Json.string "&mut Counter"),
            ("objectRequirements", Json.array #[
              Json.object #[
                ("name", Json.string "counter"),
                ("type", Json.string "Counter"),
                ("mutability", Json.string "mutable"),
                ("passing", Json.string "&mut Counter")
              ]
            ]),
            ("returns", Json.string "unit")
          ]),
          ("value", Json.object #[
            ("object", Json.string "&Counter"),
            ("objectRequirements", Json.array #[
              Json.object #[
                ("name", Json.string "counter"),
                ("type", Json.string "Counter"),
                ("mutability", Json.string "immutable"),
                ("passing", Json.string "&Counter")
              ]
            ]),
            ("returns", Json.string "u64")
          ]),
          ("get", Json.object #[
            ("object", Json.string "&Counter"),
            ("objectRequirements", Json.array #[
              Json.object #[
                ("name", Json.string "counter"),
                ("type", Json.string "Counter"),
                ("mutability", Json.string "immutable"),
                ("passing", Json.string "&Counter")
              ]
            ]),
            ("returns", Json.string "u64")
          ])
        ])
      ]
      requiredCapabilities := #[.storageScalar, .accountExplicit]
    }
  | other => {
      key := other
      targetId := targetId
      fields := #[("targetId", Json.string targetId)]
    }

def TargetExtension.json (extension : TargetExtension) : String :=
  Json.object (#[("targetId", Json.string extension.targetId)] ++ extension.fields)

def validateExtension (targetId : String) (extension : TargetExtension) : Except String Unit := do
  let expectedKey := extensionKeyForTarget targetId
  if extension.key != expectedKey then
    .error s!"SDK schema target `{targetId}` expected extension block `{expectedKey}`, got `{extension.key}`"
  else if extension.targetId != targetId then
    .error s!"SDK schema target `{targetId}` cannot use extension metadata for `{extension.targetId}`"
  else
    requireCapabilitiesSupported targetId "extension" extension.requiredCapabilities

def validateRefs (kind : String) (refs : Array (String × FileRef)) : Except String Unit := do
  for ref in refs do
    validateRelativeRef s!"{kind}.{ref.fst}" ref.snd

def moduleCapabilities (module : Module) : Array Capability :=
  dedup module.capabilities

def render
    (targetId : String)
    (spec : ContractSpec)
    (artifacts : Array (String × FileRef))
    (clients : Array (String × FileRef))
    (extension? : Option TargetExtension := none) : Except String String := do
  let some _ := Target.find? targetId
    | .error s!"unknown SDK schema target `{targetId}`"
  validateRefs "artifacts" artifacts
  validateRefs "clients" clients
  let capabilities := moduleCapabilities spec.module
  requireCapabilitiesSupported targetId "contract" capabilities
  let extension := extension?.getD (defaultExtension targetId)
  validateExtension targetId extension
  return Json.object #[
    ("schema", Json.string schemaId),
    ("schemaVersion", toString schemaVersion),
    ("contract", Json.object #[
      ("name", Json.string spec.name)
    ]),
    ("target", Json.string targetId),
    ("irVersion", Json.string irVersion),
    ("state", Json.array (spec.module.state.map stateJson)),
    ("types", Json.array (spec.module.structs.map structJson)),
    ("entrypoints", Json.array (spec.module.entrypoints.map entrypointJson)),
    ("errors", Json.array (ProofForge.Contract.Spec.Json.errorCatalog spec.module |>.map
      ProofForge.Contract.Spec.Json.errorCatalogEntryJson)),
    ("events", eventsJson spec.module),
    ("capabilities", capabilityIdsJson capabilities),
    ("artifacts", refsJson artifacts),
    ("clients", refsJson clients),
    ("extensions", Json.object #[(extension.key, extension.json)])
  ]

end ProofForge.Contract.SdkSchema
