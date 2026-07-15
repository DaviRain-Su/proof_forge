/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Experimental Core export (`core.v0`) — LR-1a

Serialize a **validated** Canonical Core module to deterministic JSON for
read-only Rust consumers (`pf-core-inspect`, later optional backends).

Normative draft: `docs/superpowers/specs/2026-07-15-core-export-v0-draft.md`.
This remains experimental; do not treat it as a stable public SDK.
-/
import ProofForge.IR.Core.Validate
import ProofForge.Util.Json

namespace ProofForge.IR.Core.Export

open ProofForge.IR.Core
open ProofForge.IR.Core.Validate
open ProofForge.Util.Json

/-- Experimental Core export schema id. -/
def coreSchema : String := "core.v0"

/-- Envelope schema major while experimental. -/
def envelopeSchemaVersion : Nat := 0

/-- Capability plan schema id (companion file). -/
def capabilityPlanSchema : String := "capability-plan.v0"

structure ExportError where
  message : String
  deriving Repr

def natJson (n : Nat) : String := toString n

def idJson (n : Nat) : String := natJson n

def optNatJson : Option Nat → String
  | none => "null"
  | some n => natJson n

def optJson (f : α → String) : Option α → String
  | none => "null"
  | some v => f v

partial def coreTypeJson : CoreType → String
  | .unit => jsonObject #[("kind", jsonString "unit")]
  | .bool => jsonObject #[("kind", jsonString "bool")]
  | .u8 => jsonObject #[("kind", jsonString "u8")]
  | .u32 => jsonObject #[("kind", jsonString "u32")]
  | .u64 => jsonObject #[("kind", jsonString "u64")]
  | .u128 => jsonObject #[("kind", jsonString "u128")]
  | .address => jsonObject #[("kind", jsonString "address")]
  | .bytes => jsonObject #[("kind", jsonString "bytes")]
  | .string => jsonObject #[("kind", jsonString "string")]
  | .hash => jsonObject #[("kind", jsonString "hash")]
  | .fixedArray element length =>
      jsonObject #[
        ("kind", jsonString "fixedArray"),
        ("element", coreTypeJson element),
        ("length", natJson length)
      ]
  | .array element =>
      jsonObject #[
        ("kind", jsonString "array"),
        ("element", coreTypeJson element)
      ]
  | .memoryRef element =>
      jsonObject #[
        ("kind", jsonString "memoryRef"),
        ("element", coreTypeJson element)
      ]
  | .structType typeId =>
      jsonObject #[
        ("kind", jsonString "structType"),
        ("typeId", idJson typeId.value)
      ]

def valueDefJson (v : ValueDef) : String :=
  jsonObject #[
    ("id", idJson v.id.value),
    ("type", coreTypeJson v.type)
  ]

def valueRefJson (v : ValueRef) : String :=
  jsonObject #[
    ("id", idJson v.id.value),
    ("type", coreTypeJson v.type)
  ]

def valueRefArrayJson (values : Array ValueRef) : String :=
  jsonArray (values.map valueRefJson)

def valueDefArrayJson (values : Array ValueDef) : String :=
  jsonArray (values.map valueDefJson)

def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + (n - 10))

def hexByte (b : UInt8) : String :=
  let hi := (b.toNat >>> 4) % 16
  let lo := b.toNat % 16
  String.ofList [hexDigit hi, hexDigit lo]

def byteArrayHex (bytes : ByteArray) : String :=
  String.intercalate "" (bytes.toList.map hexByte)

def literalJson : CoreLiteral → String
  | .unitLit => jsonObject #[("kind", jsonString "unit")]
  | .boolLit b => jsonObject #[("kind", jsonString "bool"), ("value", jsonBool b)]
  | .u8Lit n => jsonObject #[("kind", jsonString "u8"), ("value", natJson n)]
  | .u32Lit n => jsonObject #[("kind", jsonString "u32"), ("value", natJson n)]
  | .u64Lit n => jsonObject #[("kind", jsonString "u64"), ("value", natJson n)]
  | .u128Lit n => jsonObject #[("kind", jsonString "u128"), ("value", natJson n)]
  | .addressLit s => jsonObject #[("kind", jsonString "address"), ("value", jsonString s)]
  | .bytesLit b =>
      jsonObject #[
        ("kind", jsonString "bytes"),
        ("hex", jsonString (byteArrayHex b))
      ]
  | .stringLit s => jsonObject #[("kind", jsonString "string"), ("value", jsonString s)]
  | .hashLit s => jsonObject #[("kind", jsonString "hash"), ("value", jsonString s)]

def overflowModeJson : OverflowMode → String
  | .wrapping => jsonString "wrapping"
  | .checked => jsonString "checked"

def unaryOpJson : UnaryOp → String
  | .not => jsonString "not"
  | .neg => jsonString "neg"

def arithmeticOpJson : ArithmeticOp → String
  | .add => jsonString "add"
  | .sub => jsonString "sub"
  | .mul => jsonString "mul"
  | .div => jsonString "div"
  | .mod => jsonString "mod"
  | .and => jsonString "and"
  | .or => jsonString "or"
  | .xor => jsonString "xor"
  | .shl => jsonString "shl"
  | .shr => jsonString "shr"

def compareOpJson : CompareOp → String
  | .eq => jsonString "eq"
  | .ne => jsonString "ne"
  | .lt => jsonString "lt"
  | .le => jsonString "le"
  | .gt => jsonString "gt"
  | .ge => jsonString "ge"

def booleanOpJson : BooleanOp → String
  | .and => jsonString "and"
  | .or => jsonString "or"

def contextFieldJson : ContextField → String
  | .sender => jsonString "sender"
  | .signer => jsonString "signer"
  | .value => jsonString "value"
  | .blockNumber => jsonString "blockNumber"
  | .blockTimestamp => jsonString "blockTimestamp"
  | .gas => jsonString "gas"
  | .contractAddress => jsonString "contractAddress"

def pureOpJson : PureOp → String
  | .literal value =>
      jsonObject #[("kind", jsonString "literal"), ("value", literalJson value)]
  | .unary op arg =>
      jsonObject #[
        ("kind", jsonString "unary"),
        ("op", unaryOpJson op),
        ("arg", valueRefJson arg)
      ]
  | .arithmetic op mode lhs rhs =>
      jsonObject #[
        ("kind", jsonString "arithmetic"),
        ("op", arithmeticOpJson op),
        ("mode", overflowModeJson mode),
        ("lhs", valueRefJson lhs),
        ("rhs", valueRefJson rhs)
      ]
  | .compare op lhs rhs =>
      jsonObject #[
        ("kind", jsonString "compare"),
        ("op", compareOpJson op),
        ("lhs", valueRefJson lhs),
        ("rhs", valueRefJson rhs)
      ]
  | .boolean op lhs rhs =>
      jsonObject #[
        ("kind", jsonString "boolean"),
        ("op", booleanOpJson op),
        ("lhs", valueRefJson lhs),
        ("rhs", valueRefJson rhs)
      ]
  | .cast to arg =>
      jsonObject #[
        ("kind", jsonString "cast"),
        ("to", coreTypeJson to),
        ("arg", valueRefJson arg)
      ]
  | .hash arg =>
      jsonObject #[("kind", jsonString "hash"), ("arg", valueRefJson arg)]
  | .hashTwoToOne lhs rhs =>
      jsonObject #[
        ("kind", jsonString "hashTwoToOne"),
        ("lhs", valueRefJson lhs),
        ("rhs", valueRefJson rhs)
      ]
  | .structLit typeId fields =>
      jsonObject #[
        ("kind", jsonString "structLit"),
        ("typeId", idJson typeId.value),
        ("fields", valueRefArrayJson fields)
      ]

def storageSegmentJson : StorageSegment → String
  | .mapKey key => jsonObject #[("kind", jsonString "mapKey"), ("key", valueRefJson key)]
  | .index index => jsonObject #[("kind", jsonString "index"), ("index", valueRefJson index)]
  | .field field => jsonObject #[("kind", jsonString "field"), ("fieldId", idJson field.value)]

def storageRefJson (ref : StorageRef) : String :=
  jsonObject #[
    ("root", idJson ref.root.value),
    ("path", jsonArray (ref.path.map storageSegmentJson)),
    ("resultType", coreTypeJson ref.resultType)
  ]

def crosscallModeJson : CoreCrosscallMode → String
  | .invoke => jsonString "invoke"
  | .staticInvoke => jsonString "staticInvoke"
  | .delegateInvoke => jsonString "delegateInvoke"
  | .namedInvoke => jsonString "namedInvoke"
  | .continuation => jsonString "continuation"

def hostOpVersionJson (v : ProofForge.Target.HostOpVersion) : String :=
  jsonObject #[
    ("major", natJson v.major),
    ("minor", natJson v.minor),
    ("patch", natJson v.patch)
  ]

def hostOpIdJson (id : ProofForge.Target.HostOpId) : String :=
  jsonObject #[
    ("namespace", jsonString id.namespace_),
    ("name", jsonString id.name),
    ("version", hostOpVersionJson id.version),
    ("render", jsonString id.render)
  ]

def hostOpCallJson (call : HostOpCall) : String :=
  jsonObject #[
    ("id", hostOpIdJson call.id),
    ("args", valueRefArrayJson call.args)
  ]

def errorRefJson (err : CoreErrorRef) : String :=
  jsonObject #[
    ("id", idJson err.id.value),
    ("args", valueRefArrayJson err.args)
  ]

def crosscallSpecJson (spec : CoreCrosscallSpec) : String :=
  jsonObject #[
    ("mode", crosscallModeJson spec.mode),
    ("target", valueRefJson spec.target),
    ("method", valueRefJson spec.method),
    ("gas", optJson valueRefJson spec.gas),
    ("value", optJson valueRefJson spec.value),
    ("paramTypes", jsonArray (spec.paramTypes.map coreTypeJson)),
    ("argNames", jsonStringArray spec.argNames),
    ("returnType", coreTypeJson spec.returnType)
  ]

def instructionOpJson : InstructionOp → String
  | .pure op => jsonObject #[("kind", jsonString "pure"), ("op", pureOpJson op)]
  | .storageLoad path =>
      jsonObject #[("kind", jsonString "storageLoad"), ("path", storageRefJson path)]
  | .storageContains path =>
      jsonObject #[("kind", jsonString "storageContains"), ("path", storageRefJson path)]
  | .storageStore path value =>
      jsonObject #[
        ("kind", jsonString "storageStore"),
        ("path", storageRefJson path),
        ("value", valueRefJson value)
      ]
  | .storageRemove path =>
      jsonObject #[("kind", jsonString "storageRemove"), ("path", storageRefJson path)]
  | .storageLength root =>
      jsonObject #[("kind", jsonString "storageLength"), ("root", idJson root.value)]
  | .storageResize root length =>
      jsonObject #[
        ("kind", jsonString "storageResize"),
        ("root", idJson root.value),
        ("length", valueRefJson length)
      ]
  | .memoryAlloc type length =>
      jsonObject #[
        ("kind", jsonString "memoryAlloc"),
        ("type", coreTypeJson type),
        ("length", valueRefJson length)
      ]
  | .memoryLoad base index =>
      jsonObject #[
        ("kind", jsonString "memoryLoad"),
        ("base", valueRefJson base),
        ("index", valueRefJson index)
      ]
  | .memoryStore base index value =>
      jsonObject #[
        ("kind", jsonString "memoryStore"),
        ("base", valueRefJson base),
        ("index", valueRefJson index),
        ("value", valueRefJson value)
      ]
  | .memoryRelease base =>
      jsonObject #[("kind", jsonString "memoryRelease"), ("base", valueRefJson base)]
  | .contextRead field =>
      jsonObject #[("kind", jsonString "contextRead"), ("field", contextFieldJson field)]
  | .emit event args =>
      jsonObject #[
        ("kind", jsonString "emit"),
        ("eventId", idJson event.value),
        ("args", valueRefArrayJson args)
      ]
  | .assert condition error =>
      jsonObject #[
        ("kind", jsonString "assert"),
        ("condition", valueRefJson condition),
        ("error", errorRefJson error)
      ]
  | .crosscall spec args =>
      jsonObject #[
        ("kind", jsonString "crosscall"),
        ("spec", crosscallSpecJson spec),
        ("args", valueRefArrayJson args)
      ]
  | .hostCall call =>
      jsonObject #[("kind", jsonString "hostCall"), ("call", hostOpCallJson call)]

def instructionJson (insn : Instruction) : String :=
  jsonObject #[
    ("results", valueDefArrayJson insn.results),
    ("op", instructionOpJson insn.op)
  ]

def loopBoundJson : LoopBound → String
  | .atMost n => jsonObject #[("kind", jsonString "atMost"), ("iterations", natJson n)]
  | .requiresUnbounded => jsonObject #[("kind", jsonString "requiresUnbounded")]

def terminatorJson : Terminator → String
  | .jump target args bound =>
      jsonObject #[
        ("kind", jsonString "jump"),
        ("target", idJson target.value),
        ("args", valueRefArrayJson args),
        ("backedgeBound", optJson loopBoundJson bound)
      ]
  | .branch condition onTrue onFalse =>
      jsonObject #[
        ("kind", jsonString "branch"),
        ("condition", valueRefJson condition),
        ("onTrue", idJson onTrue.value),
        ("onFalse", idJson onFalse.value)
      ]
  | .return values =>
      jsonObject #[("kind", jsonString "return"), ("values", valueRefArrayJson values)]
  | .revert error =>
      jsonObject #[("kind", jsonString "revert"), ("error", errorRefJson error)]

def blockJson (b : Block) : String :=
  jsonObject #[
    ("id", idJson b.id.value),
    ("params", valueDefArrayJson b.params),
    ("instructions", jsonArray (b.instructions.map instructionJson)),
    ("terminator", terminatorJson b.terminator)
  ]

def functionJson (f : Function) : String :=
  jsonObject #[
    ("id", idJson f.id.value),
    ("params", valueDefArrayJson f.params),
    ("retType", coreTypeJson f.retType),
    ("entry", idJson f.entry.value),
    ("blocks", jsonArray (f.blocks.map blockJson))
  ]

def fieldOwnershipJson : FieldOwnership → String
  | .value => jsonString "value"
  | .reference => jsonString "reference"

def structSemanticsJson : StructSemantics → String
  | .value => jsonString "value"
  | .linearRecord => jsonString "linearRecord"

def fieldDeclJson (f : FieldDecl) : String :=
  jsonObject #[
    ("id", idJson f.id.value),
    ("type", coreTypeJson f.type),
    ("ownership", fieldOwnershipJson f.ownership)
  ]

def structJson (s : Struct) : String :=
  jsonObject #[
    ("id", idJson s.id.value),
    ("fields", jsonArray (s.fields.map fieldDeclJson)),
    ("semantics", structSemanticsJson s.semantics)
  ]

def stateShapeJson : StateShape → String
  | .scalar value =>
      jsonObject #[("kind", jsonString "scalar"), ("value", coreTypeJson value)]
  | .map key value capacity =>
      jsonObject #[
        ("kind", jsonString "map"),
        ("key", coreTypeJson key),
        ("value", coreTypeJson value),
        ("capacity", optNatJson capacity)
      ]
  | .mapN keys value capacity =>
      jsonObject #[
        ("kind", jsonString "mapN"),
        ("keys", jsonArray (keys.map coreTypeJson)),
        ("value", coreTypeJson value),
        ("capacity", optNatJson capacity)
      ]
  | .fixedArray element length =>
      jsonObject #[
        ("kind", jsonString "fixedArray"),
        ("element", coreTypeJson element),
        ("length", natJson length)
      ]
  | .dynamicArray element =>
      jsonObject #[
        ("kind", jsonString "dynamicArray"),
        ("element", coreTypeJson element)
      ]
  | .record typeId =>
      jsonObject #[("kind", jsonString "record"), ("typeId", idJson typeId.value)]

def stateDeclJson (s : StateDecl) : String :=
  jsonObject #[
    ("id", idJson s.id.value),
    ("shape", stateShapeJson s.shape)
  ]

def eventFieldJson (f : EventFieldDecl) : String :=
  jsonObject #[
    ("id", idJson f.id.value),
    ("type", coreTypeJson f.type)
  ]

def eventJson (e : Event) : String :=
  jsonObject #[
    ("id", idJson e.id.value),
    ("fields", jsonArray (e.fields.map eventFieldJson))
  ]

def errorDeclJson (e : ErrorDecl) : String :=
  jsonObject #[
    ("id", idJson e.id.value),
    ("namespace", jsonString e.namespace_),
    ("name", jsonString e.name),
    ("code", natJson e.code),
    ("params", jsonArray (e.params.map coreTypeJson))
  ]

/-- Deterministic JSON body for a Core module (no envelope). -/
def moduleBodyJson (m : Module) : String :=
  jsonObject #[
    ("schemaVersion", natJson envelopeSchemaVersion),
    ("coreSchema", jsonString coreSchema),
    ("module", jsonObject #[
      ("name", jsonString m.name),
      ("structs", jsonArray (m.structs.map structJson)),
      ("state", jsonArray (m.state.map stateDeclJson)),
      ("functions", jsonArray (m.functions.map functionJson)),
      ("events", jsonArray (m.events.map eventJson)),
      ("errors", jsonArray (m.errors.map errorDeclJson))
    ])
  ]

/-- Minimal capability-plan companion (target declared; host handlers later). -/
def capabilityPlanJson (targetId : String) (capabilityIds : Array String) : String :=
  jsonObject #[
    ("schemaVersion", natJson envelopeSchemaVersion),
    ("capabilityPlanSchema", jsonString capabilityPlanSchema),
    ("targetId", jsonString targetId),
    ("capabilities", jsonStringArray capabilityIds),
    ("hostOpHandlers", jsonArray #[]),
    ("profileNotes", jsonString "experimental: hostOpHandlers empty until resolveSpec wiring (LR-1b)")
  ]

/-- source-manifest sketch (not part of contentHash). -/
def sourceManifestJson
    (sourceKind productPath? requestedTarget : String)
    (inputDigests : Array (String × String) := #[]) : String :=
  let digests := jsonObject (inputDigests.map fun pair => (pair.fst, jsonString pair.snd))
  jsonObject #[
    ("productPath", if productPath?.isEmpty then "null" else jsonString productPath?),
    ("sourceKind", jsonString sourceKind),
    ("requestedTarget", jsonString requestedTarget),
    ("inputDigests", digests),
    ("notPartOfContentHash", jsonStringArray #["productPath", "inputDigests"])
  ]

/-- Export-meta without contentHash (caller may fill after hashing bodies). -/
def exportMetaJson
    (targetId moduleName contentHash leanToolchain leanVersionObserved : String)
    : String :=
  jsonObject #[
    ("schemaVersion", natJson envelopeSchemaVersion),
    ("coreSchema", jsonString coreSchema),
    ("capabilityPlanSchema", jsonString capabilityPlanSchema),
    ("leanToolchain", jsonString leanToolchain),
    ("leanVersionObserved", jsonString leanVersionObserved),
    ("targetId", jsonString targetId),
    ("moduleName", jsonString moduleName),
    ("contentHash", jsonString contentHash),
    ("createdBy", jsonString "proof-forge export-core (experimental)")
  ]

/-- Validate then serialize. Fail-closed: no body on Validate error. -/
def exportModuleJson
    (m : Module) (catalog? : Option ProofForge.IR.Core.HostOp.HostOpCatalog := none)
    : Except ExportError String :=
  match validateModule m catalog? with
  | .error err => .error { message := s!"core export refused: {repr err}" }
  | .ok _ => .ok (moduleBodyJson m)

/-- Same as `exportModuleJson` but returns the checked module for further packaging. -/
def exportChecked
    (m : Module)
    (catalog? : Option ProofForge.IR.Core.HostOp.HostOpCatalog := none)
    : Except ExportError (CheckedModule × String) :=
  match validateModule m catalog? with
  | .error err => .error { message := s!"core export refused: {repr err}" }
  | .ok checked => .ok (checked, moduleBodyJson checked.module)

end ProofForge.IR.Core.Export
