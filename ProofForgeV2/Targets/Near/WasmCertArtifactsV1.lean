import ProofForgeV2.Targets.Near.StaticAlignmentV1
import ProofForgeV2.Targets.Near.WasmCertWireV1

/-!
# NEAR WasmCert invocation, trace, and observation artifacts

Closed, bounded PF-JCS carriers for the semantics-bearing input and output of
the pinned WasmCert provider. These types describe external host inputs and
observations only. They do not define a contract step, execute a ProofForge
program, or make a provider record true.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Core.Common

def wasmCertInvocationArtifactSchemaV1 : String :=
  "proof-forge.near.wasmcert-invocation.v1"

def wasmCertHostTraceArtifactSchemaV1 : String :=
  "proof-forge.near.wasmcert-host-trace.v1"

def wasmCertObservationArtifactSchemaV1 : String :=
  "proof-forge.near.wasmcert-observation.v1"

def wasmCertObservationPolicyV1 : String :=
  "proof-forge.near.strict-call-observation.v1"

def wasmCertMaxInvocationInputBytesV1 : Nat := 65536
def wasmCertMaxStorageRowsV1 : Nat := 256
def wasmCertMaxStorageKeyBytesV1 : Nat := 1024
def wasmCertMaxStorageValueBytesV1 : Nat := 1048576
def wasmCertMaxAggregatePayloadBytesV1 : Nat := 8388608
def wasmCertMaxArtifactWireBytesV1 : Nat := 33554432
def wasmCertMaxTraceEventsV1 : Nat := 100000
def wasmCertMaxEventArgumentsV1 : Nat := 8
def wasmCertMaxEventPayloadsV1 : Nat := 3
def wasmCertMaxEventPayloadBytesV1 : Nat := 1048576
def wasmCertMaxLogsV1 : Nat := 256
def wasmCertMaxPromisesV1 : Nat := 256
def wasmCertMaxPromiseBytesV1 : Nat := 1048576
def wasmCertMaxContextPromiseResultsV1 : Nat := 64
def wasmCertMaxOutputDataReceiversV1 : Nat := 64

/-- One exact raw NEAR KV row. Rows are canonical only when keys are nonempty,
    unique, and strictly increasing by unsigned byte lexicographic order. -/
structure WasmCertStorageRowV1 where
  key : ByteArray
  value : ByteArray
  deriving BEq, DecidableEq, Repr

inductive WasmCertPromiseResultStatusV1 where
  | notReady
  | successful
  | failed
  deriving BEq, DecidableEq, Repr

structure WasmCertPromiseResultV1 where
  status : WasmCertPromiseResultStatusV1
  data : ByteArray
  deriving BEq, DecidableEq, Repr

/-- Explicit NEAR VM context for the strict first provider profile. Numeric
    fields wider than PF-JCS safe integers are represented by their exact Lean
    values and encoded as fixed-width little-endian lowercase hex. -/
structure WasmCertNearContextV1 where
  currentAccountId : String
  signerAccountId : String
  signerAccountPk : ByteArray
  predecessorAccountId : String
  blockHeight : UInt64
  blockTimestampNanos : UInt64
  epochHeight : UInt64
  accountBalance : ByteArray
  accountLockedBalance : ByteArray
  storageUsage : UInt64
  attachedDeposit : ByteArray
  prepaidGas : UInt64
  randomSeed : ByteArray
  isView : Bool
  outputDataReceivers : Array String
  promiseResults : Array WasmCertPromiseResultV1
  deriving BEq, DecidableEq, Repr

/-- Semantics-bearing provider input. `input` is the raw exported-method ABI
    payload; no environment variable or working-directory default completes
    this record. -/
structure WasmCertInvocationArtifactV1 where
  schema : String
  hostProfile : String
  observationPolicy : String
  exportName : String
  input : ByteArray
  context : WasmCertNearContextV1
  preStorage : Array WasmCertStorageRowV1
  deriving BEq, DecidableEq, Repr

/-- One ordered call into the bounded NEAR host. `payloads` record bytes read
    or written by that ABI call; arguments and result retain the raw i64 host
    words. This is a trace row, not a host-state transition. -/
structure WasmCertHostTraceEventV1 where
  index : Nat
  importName : String
  arguments : Array UInt64
  result : Option UInt64
  payloads : Array ByteArray
  deriving BEq, DecidableEq, Repr

structure WasmCertHostTraceArtifactV1 where
  schema : String
  hostProfile : String
  invocationSha256 : Digest
  events : Array WasmCertHostTraceEventV1
  deriving BEq, DecidableEq, Repr

inductive WasmCertObservationStatusV1 where
  | returned
  | trapped
  deriving BEq, DecidableEq, Repr

inductive WasmCertTrapKindV1 where
  | wasm
  | host
  deriving BEq, DecidableEq, Repr

/-- Canonical call-boundary output. Trap rollback and view immutability are
    checked against the separately bound invocation artifact. -/
structure WasmCertObservationArtifactV1 where
  schema : String
  hostProfile : String
  invocationSha256 : Digest
  status : WasmCertObservationStatusV1
  trapKind : Option WasmCertTrapKindV1
  returnData : Option ByteArray
  postStorage : Array WasmCertStorageRowV1
  logs : Array ByteArray
  promises : Array ByteArray
  deriving BEq, DecidableEq, Repr

def wasmCertInvocationArtifactFieldsV1 : Array String := #[
  "context",
  "exportName",
  "hostProfile",
  "inputHex",
  "observationPolicy",
  "preStorage",
  "schema"
]

def wasmCertNearContextFieldsV1 : Array String := #[
  "accountBalanceHex",
  "accountLockedBalanceHex",
  "attachedDepositHex",
  "blockHeightHex",
  "blockTimestampNanosHex",
  "currentAccountId",
  "epochHeightHex",
  "isView",
  "outputDataReceivers",
  "predecessorAccountId",
  "prepaidGasHex",
  "promiseResults",
  "randomSeedHex",
  "signerAccountId",
  "signerAccountPkHex",
  "storageUsageHex"
]

def wasmCertStorageRowFieldsV1 : Array String := #["keyHex", "valueHex"]
def wasmCertPromiseResultFieldsV1 : Array String := #["dataHex", "status"]

def wasmCertHostTraceArtifactFieldsV1 : Array String := #[
  "events", "hostProfile", "invocationSha256", "schema"
]

def wasmCertHostTraceEventFieldsV1 : Array String := #[
  "argumentsHex", "import", "index", "payloadsHex", "resultHex"
]

def wasmCertObservationArtifactFieldsV1 : Array String := #[
  "hostProfile",
  "invocationSha256",
  "logsHex",
  "postStorage",
  "promisesHex",
  "returnDataHex",
  "schema",
  "status",
  "trapKind"
]

private def lowerHexDigitV1 (value : Nat) : Char :=
  if value < 10 then
    Char.ofNat ('0'.toNat + value)
  else
    Char.ofNat ('a'.toNat + value - 10)

/-- Exact lowercase hex used for every raw byte field in these artifacts. -/
def encodeWasmCertHexV1 (bytes : ByteArray) : String :=
  String.ofList <| bytes.data.toList.flatMap fun byte =>
    [lowerHexDigitV1 (byte.toNat / 16), lowerHexDigitV1 (byte.toNat % 16)]

private def lowerHexNibbleV1 (character : Char) : Option Nat :=
  if '0' ≤ character && character ≤ '9' then
    some (character.toNat - '0'.toNat)
  else if 'a' ≤ character && character ≤ 'f' then
    some (10 + character.toNat - 'a'.toNat)
  else
    none

/-- Strict lowercase hex decoder with an explicit decoded-byte ceiling. -/
def decodeWasmCertHexV1
    (text : String) (maxBytes : Nat) (context : String) :
    Except String ByteArray := do
  let characters := text.toList.toArray
  unless characters.size % 2 = 0 do
    throw s!"{context} must contain complete lowercase hex byte pairs"
  unless characters.size / 2 ≤ maxBytes do
    throw s!"{context} exceeds the {maxBytes}-byte limit"
  let mut result := ByteArray.empty
  let mut index := 0
  while index < characters.size do
    let high ← match lowerHexNibbleV1 characters[index]! with
      | some value => pure value
      | none => throw s!"{context} contains a non-lowercase-hex character"
    let low ← match lowerHexNibbleV1 characters[index + 1]! with
      | some value => pure value
      | none => throw s!"{context} contains a non-lowercase-hex character"
    result := result.push (UInt8.ofNat (high * 16 + low))
    index := index + 2
  pure result

private def encodeUInt64HexV1 (value : UInt64) : String :=
  encodeWasmCertHexV1 <| ByteArray.mk #[
    value.toUInt8,
    (UInt64.shiftRight value 8).toUInt8,
    (UInt64.shiftRight value 16).toUInt8,
    (UInt64.shiftRight value 24).toUInt8,
    (UInt64.shiftRight value 32).toUInt8,
    (UInt64.shiftRight value 40).toUInt8,
    (UInt64.shiftRight value 48).toUInt8,
    (UInt64.shiftRight value 56).toUInt8
  ]

private def decodeUInt64HexV1 (text context : String) : Except String UInt64 := do
  let bytes ← decodeWasmCertHexV1 text 8 context
  unless bytes.size = 8 do
    throw s!"{context} must encode exactly eight little-endian bytes"
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := value ||| UInt64.shiftLeft bytes[index]!.toUInt64
      (UInt64.ofNat (8 * index))
  pure value

private def compareByteArraysV1 (left right : ByteArray) : Ordering := Id.run do
  let common := Nat.min left.size right.size
  for index in [:common] do
    let leftByte := left[index]!
    let rightByte := right[index]!
    if leftByte < rightByte then return .lt
    if leftByte > rightByte then return .gt
  pure (compare left.size right.size)

private def requireObjectV1
    (value : PfJson) (context : String) : Except String (Array (String × PfJson)) :=
  match value with
  | .object fields => pure fields
  | _ => throw s!"{context} must be a PF-JCS object"

private def requireExactKeysV1
    (fields : Array (String × PfJson))
    (expected : Array String)
    (context : String) : Except String Unit := do
  unless fields.size = expected.size do
    throw s!"{context} must have exactly {expected.size} fields"
  for index in [:fields.size] do
    match fields[index]?, expected[index]? with
    | some field, some key =>
        unless field.1 = key do
          throw s!"{context} expected key '{key}', got '{field.1}'"
    | _, _ => throw s!"{context} field index is out of bounds"

private def fieldV1
    (fields : Array (String × PfJson))
    (key context : String) : Except String PfJson :=
  match fields.find? (·.1 == key) with
  | some field => pure field.2
  | none => throw s!"{context} missing field '{key}'"

private def requireStringV1
    (value : PfJson) (context : String) : Except String String :=
  match value with
  | .string result => pure result
  | _ => throw s!"{context} must be a string"

private def requireBoolV1
    (value : PfJson) (context : String) : Except String Bool :=
  match value with
  | .bool result => pure result
  | _ => throw s!"{context} must be a boolean"

private def requireArrayV1
    (value : PfJson) (context : String) : Except String (Array PfJson) :=
  match value with
  | .array result => pure result
  | _ => throw s!"{context} must be an array"

private def requireDigestV1
    (value : PfJson) (context : String) : Except String Digest := do
  let text ← requireStringV1 value context
  match parseDigest text with
  | .ok digest => pure digest
  | .error error => throw s!"{context}: {error}"

private def digestJsonV1 (digest : Digest) : Except String PfJson := do
  pure (.string (← renderDigest digest))

private def renderArtifactV1 (value : PfJson) (context : String) : Except String String := do
  let text ← renderPfJcs value
  unless text.toUTF8.size ≤ wasmCertMaxArtifactWireBytesV1 do
    throw s!"{context} exceeds the wire-size limit"
  pure text

private def requireIndexV1
    (value : PfJson) (context : String) : Except String Nat :=
  match value with
  | .int index =>
      if 0 ≤ index && index < Int.ofNat wasmCertMaxTraceEventsV1 then
        pure index.toNat
      else
        throw s!"{context} must be in 0..{wasmCertMaxTraceEventsV1 - 1}"
  | _ => throw s!"{context} must be an integer"

private def requireOptionalStringV1
    (value : PfJson) (context : String) : Except String (Option String) :=
  match value with
  | .null => pure none
  | .string result => pure (some result)
  | _ => throw s!"{context} must be null or a string"

private def validateStorageRowsV1
    (rows : Array WasmCertStorageRowV1) (context : String) : Except String Unit := do
  unless rows.size ≤ wasmCertMaxStorageRowsV1 do
    throw s!"{context} exceeds the {wasmCertMaxStorageRowsV1}-row limit"
  let mut previous : Option ByteArray := none
  let mut totalBytes := 0
  for row in rows do
    unless 0 < row.key.size && row.key.size ≤ wasmCertMaxStorageKeyBytesV1 do
      throw s!"{context} key size must be in 1..{wasmCertMaxStorageKeyBytesV1}"
    unless row.value.size ≤ wasmCertMaxStorageValueBytesV1 do
      throw s!"{context} value exceeds the {wasmCertMaxStorageValueBytesV1}-byte limit"
    match previous with
    | none => pure ()
    | some prior =>
        unless compareByteArraysV1 prior row.key = .lt do
          throw s!"{context} keys must be unique and strictly byte-lexicographic"
    previous := some row.key
    totalBytes := totalBytes + row.key.size + row.value.size
    unless totalBytes ≤ wasmCertMaxAggregatePayloadBytesV1 do
      throw s!"{context} exceeds the aggregate payload limit"

private def promiseResultStatusWireV1 : WasmCertPromiseResultStatusV1 → String
  | .notReady => "not-ready"
  | .successful => "successful"
  | .failed => "failed"

private def promiseResultStatusOfWireV1
    (value : String) : Except String WasmCertPromiseResultStatusV1 :=
  match value with
  | "not-ready" => pure .notReady
  | "successful" => pure .successful
  | "failed" => pure .failed
  | _ => throw s!"unknown WasmCert promise result status '{value}'"

private def validatePromiseResultV1
    (result : WasmCertPromiseResultV1) : Except String Unit := do
  unless result.data.size ≤ wasmCertMaxPromiseBytesV1 do
    throw s!"promise result exceeds the {wasmCertMaxPromiseBytesV1}-byte limit"
  unless result.status = .successful || result.data.isEmpty do
    throw "not-ready and failed promise results must carry empty data"

private def validateNearContextV1
    (context : WasmCertNearContextV1) : Except String Unit := do
  unless isNearAccountId context.currentAccountId do
    throw "WasmCert currentAccountId is not a strict NEAR account id"
  unless isNearAccountId context.signerAccountId do
    throw "WasmCert signerAccountId is not a strict NEAR account id"
  unless isNearAccountId context.predecessorAccountId do
    throw "WasmCert predecessorAccountId is not a strict NEAR account id"
  unless context.signerAccountPk.size = 33 || context.signerAccountPk.size = 65 do
    throw "WasmCert signerAccountPk must contain 33 or 65 tagged key bytes"
  unless context.accountBalance.size = 16 &&
      context.accountLockedBalance.size = 16 &&
      context.attachedDeposit.size = 16 do
    throw "WasmCert NEAR monetary fields must contain exactly 16 little-endian bytes"
  unless context.randomSeed.size = 32 do
    throw "WasmCert randomSeed must contain exactly 32 bytes"
  unless context.outputDataReceivers.size ≤ wasmCertMaxOutputDataReceiversV1 do
    throw "WasmCert outputDataReceivers exceeds the strict profile limit"
  for receiver in context.outputDataReceivers do
    unless isNearAccountId receiver do
      throw "WasmCert outputDataReceivers contains an invalid NEAR account id"
  unless context.promiseResults.size ≤ wasmCertMaxContextPromiseResultsV1 do
    throw "WasmCert promiseResults exceeds the strict profile limit"
  let mut promiseBytes := 0
  for result in context.promiseResults do
    validatePromiseResultV1 result
    promiseBytes := promiseBytes + result.data.size
    unless promiseBytes ≤ wasmCertMaxAggregatePayloadBytesV1 do
      throw "WasmCert promiseResults exceeds the aggregate payload limit"
  if context.isView then
    unless context.attachedDeposit == ByteArray.mk (Array.replicate 16 0) do
      throw "WasmCert view context must have zero attached deposit"

/-- Closed structural validation of a semantics-bearing invocation artifact. -/
def validateWasmCertInvocationArtifactV1
    (artifact : WasmCertInvocationArtifactV1) : Except String Unit := do
  unless artifact.schema = wasmCertInvocationArtifactSchemaV1 do
    throw s!"WasmCert invocation schema must be '{wasmCertInvocationArtifactSchemaV1}'"
  unless artifact.hostProfile = wasmCertProviderHostProfileV1 do
    throw s!"WasmCert invocation hostProfile must be '{wasmCertProviderHostProfileV1}'"
  unless artifact.observationPolicy = wasmCertObservationPolicyV1 do
    throw s!"WasmCert observationPolicy must be '{wasmCertObservationPolicyV1}'"
  unless isIdentifier artifact.exportName do
    throw "WasmCert exportName must be a strict NEAR identifier"
  unless artifact.input.size ≤ wasmCertMaxInvocationInputBytesV1 do
    throw s!"WasmCert input exceeds the {wasmCertMaxInvocationInputBytesV1}-byte limit"
  validateNearContextV1 artifact.context
  validateStorageRowsV1 artifact.preStorage "WasmCert preStorage"

private def encodeStorageRowJsonV1
    (row : WasmCertStorageRowV1) : PfJson :=
  .object #[
    ("keyHex", .string (encodeWasmCertHexV1 row.key)),
    ("valueHex", .string (encodeWasmCertHexV1 row.value))
  ]

private def decodeStorageRowJsonV1
    (value : PfJson) (context : String) : Except String WasmCertStorageRowV1 := do
  let fields ← requireObjectV1 value context
  requireExactKeysV1 fields wasmCertStorageRowFieldsV1 context
  pure {
    key := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "keyHex" context) s!"{context}.keyHex")
      wasmCertMaxStorageKeyBytesV1 s!"{context}.keyHex"
    value := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "valueHex" context) s!"{context}.valueHex")
      wasmCertMaxStorageValueBytesV1 s!"{context}.valueHex"
  }

private def encodePromiseResultJsonV1
    (result : WasmCertPromiseResultV1) : PfJson :=
  .object #[
    ("dataHex", .string (encodeWasmCertHexV1 result.data)),
    ("status", .string (promiseResultStatusWireV1 result.status))
  ]

private def decodePromiseResultJsonV1
    (value : PfJson) (context : String) : Except String WasmCertPromiseResultV1 := do
  let fields ← requireObjectV1 value context
  requireExactKeysV1 fields wasmCertPromiseResultFieldsV1 context
  let result : WasmCertPromiseResultV1 := {
    data := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "dataHex" context) s!"{context}.dataHex")
      wasmCertMaxPromiseBytesV1 s!"{context}.dataHex"
    status := ← promiseResultStatusOfWireV1
      (← requireStringV1 (← fieldV1 fields "status" context) s!"{context}.status")
  }
  validatePromiseResultV1 result
  pure result

private def encodeNearContextJsonV1 (context : WasmCertNearContextV1) : PfJson :=
  .object #[
    ("accountBalanceHex", .string (encodeWasmCertHexV1 context.accountBalance)),
    ("accountLockedBalanceHex",
      .string (encodeWasmCertHexV1 context.accountLockedBalance)),
    ("attachedDepositHex", .string (encodeWasmCertHexV1 context.attachedDeposit)),
    ("blockHeightHex", .string (encodeUInt64HexV1 context.blockHeight)),
    ("blockTimestampNanosHex", .string (encodeUInt64HexV1 context.blockTimestampNanos)),
    ("currentAccountId", .string context.currentAccountId),
    ("epochHeightHex", .string (encodeUInt64HexV1 context.epochHeight)),
    ("isView", .bool context.isView),
    ("outputDataReceivers",
      .array (context.outputDataReceivers.map PfJson.string)),
    ("predecessorAccountId", .string context.predecessorAccountId),
    ("prepaidGasHex", .string (encodeUInt64HexV1 context.prepaidGas)),
    ("promiseResults", .array (context.promiseResults.map encodePromiseResultJsonV1)),
    ("randomSeedHex", .string (encodeWasmCertHexV1 context.randomSeed)),
    ("signerAccountId", .string context.signerAccountId),
    ("signerAccountPkHex", .string (encodeWasmCertHexV1 context.signerAccountPk)),
    ("storageUsageHex", .string (encodeUInt64HexV1 context.storageUsage))
  ]

private def decodeStringArrayV1
    (value : PfJson) (context : String) : Except String (Array String) := do
  let values ← requireArrayV1 value context
  values.mapM fun item => requireStringV1 item context

private def decodeNearContextJsonV1
    (value : PfJson) : Except String WasmCertNearContextV1 := do
  let fields ← requireObjectV1 value "WasmCert context"
  requireExactKeysV1 fields wasmCertNearContextFieldsV1 "WasmCert context"
  let context : WasmCertNearContextV1 := {
    accountBalance := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "accountBalanceHex" "WasmCert context")
        "accountBalanceHex") 16 "accountBalanceHex"
    accountLockedBalance := ← decodeWasmCertHexV1
      (← requireStringV1
        (← fieldV1 fields "accountLockedBalanceHex" "WasmCert context")
        "accountLockedBalanceHex") 16 "accountLockedBalanceHex"
    attachedDeposit := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "attachedDepositHex" "WasmCert context")
        "attachedDepositHex") 16 "attachedDepositHex"
    blockHeight := ← decodeUInt64HexV1
      (← requireStringV1 (← fieldV1 fields "blockHeightHex" "WasmCert context")
        "blockHeightHex") "blockHeightHex"
    blockTimestampNanos := ← decodeUInt64HexV1
      (← requireStringV1
        (← fieldV1 fields "blockTimestampNanosHex" "WasmCert context")
        "blockTimestampNanosHex") "blockTimestampNanosHex"
    currentAccountId := ← requireStringV1
      (← fieldV1 fields "currentAccountId" "WasmCert context") "currentAccountId"
    epochHeight := ← decodeUInt64HexV1
      (← requireStringV1 (← fieldV1 fields "epochHeightHex" "WasmCert context")
        "epochHeightHex") "epochHeightHex"
    isView := ← requireBoolV1
      (← fieldV1 fields "isView" "WasmCert context") "isView"
    outputDataReceivers := ← decodeStringArrayV1
      (← fieldV1 fields "outputDataReceivers" "WasmCert context")
      "outputDataReceivers"
    predecessorAccountId := ← requireStringV1
      (← fieldV1 fields "predecessorAccountId" "WasmCert context")
      "predecessorAccountId"
    prepaidGas := ← decodeUInt64HexV1
      (← requireStringV1 (← fieldV1 fields "prepaidGasHex" "WasmCert context")
        "prepaidGasHex") "prepaidGasHex"
    promiseResults := ← (← requireArrayV1
      (← fieldV1 fields "promiseResults" "WasmCert context")
      "promiseResults").mapIdxM fun index item =>
        decodePromiseResultJsonV1 item s!"promiseResults[{index}]"
    randomSeed := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "randomSeedHex" "WasmCert context")
        "randomSeedHex") 32 "randomSeedHex"
    signerAccountId := ← requireStringV1
      (← fieldV1 fields "signerAccountId" "WasmCert context") "signerAccountId"
    signerAccountPk := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "signerAccountPkHex" "WasmCert context")
        "signerAccountPkHex") 65 "signerAccountPkHex"
    storageUsage := ← decodeUInt64HexV1
      (← requireStringV1 (← fieldV1 fields "storageUsageHex" "WasmCert context")
        "storageUsageHex") "storageUsageHex"
  }
  validateNearContextV1 context
  pure context

/-- Encode one validated semantics-bearing invocation artifact. -/
def encodeWasmCertInvocationArtifactV1
    (artifact : WasmCertInvocationArtifactV1) : Except String String := do
  validateWasmCertInvocationArtifactV1 artifact
  renderArtifactV1 (.object #[
    ("context", encodeNearContextJsonV1 artifact.context),
    ("exportName", .string artifact.exportName),
    ("hostProfile", .string artifact.hostProfile),
    ("inputHex", .string (encodeWasmCertHexV1 artifact.input)),
    ("observationPolicy", .string artifact.observationPolicy),
    ("preStorage", .array (artifact.preStorage.map encodeStorageRowJsonV1)),
    ("schema", .string artifact.schema)
  ]) "WasmCert invocation artifact"

/-- Decode canonical PF-JCS and reject every widened or unbounded invocation. -/
def decodeWasmCertInvocationArtifactV1
    (bytes : ByteArray) : Except String WasmCertInvocationArtifactV1 := do
  unless bytes.size ≤ wasmCertMaxArtifactWireBytesV1 do
    throw "WasmCert invocation artifact exceeds the wire-size limit"
  let fields ← requireObjectV1 (← parsePfJcsBytes bytes) "WasmCert invocation"
  requireExactKeysV1 fields wasmCertInvocationArtifactFieldsV1 "WasmCert invocation"
  let artifact : WasmCertInvocationArtifactV1 := {
    context := ← decodeNearContextJsonV1
      (← fieldV1 fields "context" "WasmCert invocation")
    exportName := ← requireStringV1
      (← fieldV1 fields "exportName" "WasmCert invocation") "exportName"
    hostProfile := ← requireStringV1
      (← fieldV1 fields "hostProfile" "WasmCert invocation") "hostProfile"
    input := ← decodeWasmCertHexV1
      (← requireStringV1 (← fieldV1 fields "inputHex" "WasmCert invocation")
        "inputHex") wasmCertMaxInvocationInputBytesV1 "inputHex"
    observationPolicy := ← requireStringV1
      (← fieldV1 fields "observationPolicy" "WasmCert invocation")
      "observationPolicy"
    preStorage := ← (← requireArrayV1
      (← fieldV1 fields "preStorage" "WasmCert invocation")
      "preStorage").mapIdxM fun index item =>
        decodeStorageRowJsonV1 item s!"preStorage[{index}]"
    schema := ← requireStringV1
      (← fieldV1 fields "schema" "WasmCert invocation") "schema"
  }
  validateWasmCertInvocationArtifactV1 artifact
  pure artifact

def wasmCertStrictHostImportsV1 : Array String := #[
  "env.attached_deposit",
  "env.input",
  "env.log_utf8",
  "env.panic_utf8",
  "env.read_register",
  "env.register_len",
  "env.storage_read",
  "env.storage_write",
  "env.value_return"
]

private def validateEventPayloadLengthV1
    (event : WasmCertHostTraceEventV1)
    (argumentIndex payloadIndex : Nat) : Except String Unit := do
  match event.arguments[argumentIndex]?, event.payloads[payloadIndex]? with
  | some length, some payload =>
      unless length.toNat = payload.size do
        throw s!"WasmCert trace event {event.index} payload length does not match its host argument"
  | _, _ =>
      throw s!"WasmCert trace event {event.index} lacks a length argument or payload"

private def validateHostTraceEventV1
    (event : WasmCertHostTraceEventV1) : Except String Unit := do
  unless event.arguments.size ≤ wasmCertMaxEventArgumentsV1 do
    throw "WasmCert trace event has too many arguments"
  unless event.payloads.size ≤ wasmCertMaxEventPayloadsV1 do
    throw "WasmCert trace event has too many payloads"
  for payload in event.payloads do
    unless payload.size ≤ wasmCertMaxEventPayloadBytesV1 do
      throw "WasmCert trace event payload exceeds the strict profile limit"
  unless wasmCertStrictHostImportsV1.contains event.importName do
    throw s!"WasmCert trace contains unsupported host import '{event.importName}'"
  match event.importName with
  | "env.input" =>
      unless event.arguments.size = 1 && event.result.isNone && event.payloads.size = 1 do
        throw "WasmCert env.input trace shape mismatch"
  | "env.register_len" =>
      unless event.arguments.size = 1 && event.result.isSome && event.payloads.isEmpty do
        throw "WasmCert env.register_len trace shape mismatch"
  | "env.read_register" =>
      unless event.arguments.size = 2 && event.result.isNone && event.payloads.size = 1 do
        throw "WasmCert env.read_register trace shape mismatch"
  | "env.storage_read" =>
      unless event.arguments.size = 3 && event.result.isSome &&
          (event.payloads.size = 1 || event.payloads.size = 2) do
        throw "WasmCert env.storage_read trace shape mismatch"
      validateEventPayloadLengthV1 event 0 0
  | "env.storage_write" =>
      unless event.arguments.size = 5 && event.result.isSome &&
          (event.payloads.size = 2 || event.payloads.size = 3) do
        throw "WasmCert env.storage_write trace shape mismatch"
      validateEventPayloadLengthV1 event 0 0
      validateEventPayloadLengthV1 event 2 1
  | "env.value_return" | "env.log_utf8" | "env.panic_utf8" =>
      unless event.arguments.size = 2 && event.result.isNone && event.payloads.size = 1 do
        throw s!"WasmCert {event.importName} trace shape mismatch"
      validateEventPayloadLengthV1 event 0 0
  | "env.attached_deposit" =>
      unless event.arguments.size = 1 && event.result.isNone &&
          event.payloads.size = 1 && event.payloads[0]!.size = 16 do
        throw "WasmCert env.attached_deposit trace shape mismatch"
  | _ => throw "WasmCert host import escaped the closed profile"

/-- Structural host-trace validation. It checks known ABI row shapes and
    bounded ordered indices, but does not replay host state. -/
def validateWasmCertHostTraceArtifactV1
    (artifact : WasmCertHostTraceArtifactV1) : Except String Unit := do
  unless artifact.schema = wasmCertHostTraceArtifactSchemaV1 do
    throw s!"WasmCert host-trace schema must be '{wasmCertHostTraceArtifactSchemaV1}'"
  unless artifact.hostProfile = wasmCertProviderHostProfileV1 do
    throw s!"WasmCert host-trace hostProfile must be '{wasmCertProviderHostProfileV1}'"
  validateDigest artifact.invocationSha256
  unless artifact.events.size ≤ wasmCertMaxTraceEventsV1 do
    throw s!"WasmCert host trace exceeds the {wasmCertMaxTraceEventsV1}-event limit"
  let mut payloadBytes := 0
  for index in [:artifact.events.size] do
    match artifact.events[index]? with
    | none => throw "WasmCert host trace index is out of bounds"
    | some event =>
        unless event.index = index do
          throw "WasmCert host trace indices must be dense and source ordered"
        validateHostTraceEventV1 event
        for payload in event.payloads do
          payloadBytes := payloadBytes + payload.size
          unless payloadBytes ≤ wasmCertMaxAggregatePayloadBytesV1 do
            throw "WasmCert host trace exceeds the aggregate payload limit"

private def optionalUInt64JsonV1 : Option UInt64 → PfJson
  | none => .null
  | some value => .string (encodeUInt64HexV1 value)

private def encodeHostTraceEventJsonV1
    (event : WasmCertHostTraceEventV1) : PfJson :=
  .object #[
    ("argumentsHex", .array (event.arguments.map fun value =>
      .string (encodeUInt64HexV1 value))),
    ("import", .string event.importName),
    ("index", .int (Int.ofNat event.index)),
    ("payloadsHex", .array (event.payloads.map fun payload =>
      .string (encodeWasmCertHexV1 payload))),
    ("resultHex", optionalUInt64JsonV1 event.result)
  ]

private def decodeHexByteArrayV1
    (value : PfJson) (maxBytes : Nat) (context : String) : Except String ByteArray := do
  decodeWasmCertHexV1 (← requireStringV1 value context) maxBytes context

private def decodeHostTraceEventJsonV1
    (value : PfJson) (context : String) : Except String WasmCertHostTraceEventV1 := do
  let fields ← requireObjectV1 value context
  requireExactKeysV1 fields wasmCertHostTraceEventFieldsV1 context
  let arguments ← (← requireArrayV1
    (← fieldV1 fields "argumentsHex" context) s!"{context}.argumentsHex").mapM fun item => do
      decodeUInt64HexV1 (← requireStringV1 item s!"{context}.argumentsHex")
        s!"{context}.argumentsHex"
  let payloads ← (← requireArrayV1
    (← fieldV1 fields "payloadsHex" context) s!"{context}.payloadsHex").mapM fun item =>
      decodeHexByteArrayV1 item wasmCertMaxEventPayloadBytesV1 s!"{context}.payloadsHex"
  let resultText ← requireOptionalStringV1
    (← fieldV1 fields "resultHex" context) s!"{context}.resultHex"
  let event : WasmCertHostTraceEventV1 := {
    arguments
    importName := ← requireStringV1
      (← fieldV1 fields "import" context) s!"{context}.import"
    index := ← requireIndexV1
      (← fieldV1 fields "index" context) s!"{context}.index"
    payloads
    result := ← resultText.mapM fun text =>
      decodeUInt64HexV1 text s!"{context}.resultHex"
  }
  validateHostTraceEventV1 event
  pure event

def encodeWasmCertHostTraceArtifactV1
    (artifact : WasmCertHostTraceArtifactV1) : Except String String := do
  validateWasmCertHostTraceArtifactV1 artifact
  renderArtifactV1 (.object #[
    ("events", .array (artifact.events.map encodeHostTraceEventJsonV1)),
    ("hostProfile", .string artifact.hostProfile),
    ("invocationSha256", ← digestJsonV1 artifact.invocationSha256),
    ("schema", .string artifact.schema)
  ]) "WasmCert host-trace artifact"

def decodeWasmCertHostTraceArtifactV1
    (bytes : ByteArray) : Except String WasmCertHostTraceArtifactV1 := do
  unless bytes.size ≤ wasmCertMaxArtifactWireBytesV1 do
    throw "WasmCert host-trace artifact exceeds the wire-size limit"
  let fields ← requireObjectV1 (← parsePfJcsBytes bytes) "WasmCert host trace"
  requireExactKeysV1 fields wasmCertHostTraceArtifactFieldsV1 "WasmCert host trace"
  let artifact : WasmCertHostTraceArtifactV1 := {
    events := ← (← requireArrayV1
      (← fieldV1 fields "events" "WasmCert host trace") "events").mapIdxM fun index item =>
        decodeHostTraceEventJsonV1 item s!"events[{index}]"
    hostProfile := ← requireStringV1
      (← fieldV1 fields "hostProfile" "WasmCert host trace") "hostProfile"
    invocationSha256 := ← requireDigestV1
      (← fieldV1 fields "invocationSha256" "WasmCert host trace")
      "invocationSha256"
    schema := ← requireStringV1
      (← fieldV1 fields "schema" "WasmCert host trace") "schema"
  }
  validateWasmCertHostTraceArtifactV1 artifact
  pure artifact

private def observationStatusWireV1 : WasmCertObservationStatusV1 → String
  | .returned => "returned"
  | .trapped => "trapped"

private def observationStatusOfWireV1
    (value : String) : Except String WasmCertObservationStatusV1 :=
  match value with
  | "returned" => pure .returned
  | "trapped" => pure .trapped
  | _ => throw s!"unknown WasmCert observation status '{value}'"

private def trapKindWireV1 : WasmCertTrapKindV1 → String
  | .wasm => "wasm"
  | .host => "host"

private def trapKindOfWireV1 (value : String) : Except String WasmCertTrapKindV1 :=
  match value with
  | "wasm" => pure .wasm
  | "host" => pure .host
  | _ => throw s!"unknown WasmCert trap kind '{value}'"

private def optionalBytesJsonV1 : Option ByteArray → PfJson
  | none => .null
  | some bytes => .string (encodeWasmCertHexV1 bytes)

private def optionalTrapJsonV1 : Option WasmCertTrapKindV1 → PfJson
  | none => .null
  | some kind => .string (trapKindWireV1 kind)

private def validateBytePayloadArrayV1
    (values : Array ByteArray) (maxCount maxBytes : Nat) (context : String) :
    Except String Unit := do
  unless values.size ≤ maxCount do
    throw s!"{context} exceeds the {maxCount}-row limit"
  let mut totalBytes := 0
  for value in values do
    unless value.size ≤ maxBytes do
      throw s!"{context} row exceeds the {maxBytes}-byte limit"
    totalBytes := totalBytes + value.size
    unless totalBytes ≤ wasmCertMaxAggregatePayloadBytesV1 do
      throw s!"{context} exceeds the aggregate payload limit"

def validateWasmCertObservationArtifactV1
    (artifact : WasmCertObservationArtifactV1) : Except String Unit := do
  unless artifact.schema = wasmCertObservationArtifactSchemaV1 do
    throw s!"WasmCert observation schema must be '{wasmCertObservationArtifactSchemaV1}'"
  unless artifact.hostProfile = wasmCertProviderHostProfileV1 do
    throw s!"WasmCert observation hostProfile must be '{wasmCertProviderHostProfileV1}'"
  validateDigest artifact.invocationSha256
  validateStorageRowsV1 artifact.postStorage "WasmCert postStorage"
  validateBytePayloadArrayV1 artifact.logs wasmCertMaxLogsV1
    wasmCertMaxEventPayloadBytesV1 "WasmCert logs"
  validateBytePayloadArrayV1 artifact.promises wasmCertMaxPromisesV1
    wasmCertMaxPromiseBytesV1 "WasmCert promises"
  match artifact.returnData with
  | some value =>
      unless value.size ≤ wasmCertMaxEventPayloadBytesV1 do
        throw "WasmCert return data exceeds the strict profile limit"
  | none => pure ()
  match artifact.status, artifact.trapKind with
  | .returned, none => pure ()
  | .trapped, some _ =>
      unless artifact.returnData.isNone do
        throw "WasmCert trapped observation must not carry return data"
  | .returned, some _ =>
      throw "WasmCert returned observation must not carry a trap kind"
  | .trapped, none =>
      throw "WasmCert trapped observation must carry a trap kind"

def encodeWasmCertObservationArtifactV1
    (artifact : WasmCertObservationArtifactV1) : Except String String := do
  validateWasmCertObservationArtifactV1 artifact
  renderArtifactV1 (.object #[
    ("hostProfile", .string artifact.hostProfile),
    ("invocationSha256", ← digestJsonV1 artifact.invocationSha256),
    ("logsHex", .array (artifact.logs.map fun value =>
      .string (encodeWasmCertHexV1 value))),
    ("postStorage", .array (artifact.postStorage.map encodeStorageRowJsonV1)),
    ("promisesHex", .array (artifact.promises.map fun value =>
      .string (encodeWasmCertHexV1 value))),
    ("returnDataHex", optionalBytesJsonV1 artifact.returnData),
    ("schema", .string artifact.schema),
    ("status", .string (observationStatusWireV1 artifact.status)),
    ("trapKind", optionalTrapJsonV1 artifact.trapKind)
  ]) "WasmCert observation artifact"

private def decodeOptionalBytesV1
    (value : PfJson) (maxBytes : Nat) (context : String) :
    Except String (Option ByteArray) :=
  match value with
  | .null => pure none
  | .string text => some <$> decodeWasmCertHexV1 text maxBytes context
  | _ => throw s!"{context} must be null or lowercase hex"

private def decodeBytePayloadArrayV1
    (value : PfJson) (maxCount maxBytes : Nat) (context : String) :
    Except String (Array ByteArray) := do
  let values ← requireArrayV1 value context
  unless values.size ≤ maxCount do
    throw s!"{context} exceeds the {maxCount}-row limit"
  values.mapM fun item => decodeHexByteArrayV1 item maxBytes context

def decodeWasmCertObservationArtifactV1
    (bytes : ByteArray) : Except String WasmCertObservationArtifactV1 := do
  unless bytes.size ≤ wasmCertMaxArtifactWireBytesV1 do
    throw "WasmCert observation artifact exceeds the wire-size limit"
  let fields ← requireObjectV1 (← parsePfJcsBytes bytes) "WasmCert observation"
  requireExactKeysV1 fields wasmCertObservationArtifactFieldsV1 "WasmCert observation"
  let trapText ← requireOptionalStringV1
    (← fieldV1 fields "trapKind" "WasmCert observation") "trapKind"
  let artifact : WasmCertObservationArtifactV1 := {
    hostProfile := ← requireStringV1
      (← fieldV1 fields "hostProfile" "WasmCert observation") "hostProfile"
    invocationSha256 := ← requireDigestV1
      (← fieldV1 fields "invocationSha256" "WasmCert observation")
      "invocationSha256"
    logs := ← decodeBytePayloadArrayV1
      (← fieldV1 fields "logsHex" "WasmCert observation") wasmCertMaxLogsV1
      wasmCertMaxEventPayloadBytesV1 "logsHex"
    postStorage := ← (← requireArrayV1
      (← fieldV1 fields "postStorage" "WasmCert observation")
      "postStorage").mapIdxM fun index item =>
        decodeStorageRowJsonV1 item s!"postStorage[{index}]"
    promises := ← decodeBytePayloadArrayV1
      (← fieldV1 fields "promisesHex" "WasmCert observation") wasmCertMaxPromisesV1
      wasmCertMaxPromiseBytesV1 "promisesHex"
    returnData := ← decodeOptionalBytesV1
      (← fieldV1 fields "returnDataHex" "WasmCert observation")
      wasmCertMaxEventPayloadBytesV1 "returnDataHex"
    schema := ← requireStringV1
      (← fieldV1 fields "schema" "WasmCert observation") "schema"
    status := ← observationStatusOfWireV1 (← requireStringV1
      (← fieldV1 fields "status" "WasmCert observation") "status")
    trapKind := ← trapText.mapM trapKindOfWireV1
  }
  validateWasmCertObservationArtifactV1 artifact
  pure artifact

/-- Content-level join for a decoded trace and invocation. This validates
    direct context-bearing host payloads without replaying storage. -/
def validateWasmCertHostTraceForInvocationV1
    (invocationDigest : Digest)
    (invocation : WasmCertInvocationArtifactV1)
    (trace : WasmCertHostTraceArtifactV1) : Except String Unit := do
  validateWasmCertInvocationArtifactV1 invocation
  validateWasmCertHostTraceArtifactV1 trace
  unless trace.invocationSha256 = invocationDigest do
    throw "WasmCert host trace does not bind the invocation digest"
  unless trace.hostProfile = invocation.hostProfile do
    throw "WasmCert host trace does not bind the invocation host profile"
  for event in trace.events do
    if event.importName = "env.input" then
      unless event.payloads[0]? = some invocation.input do
        throw "WasmCert env.input trace payload does not match invocation input"
    else if event.importName = "env.attached_deposit" then
      unless event.payloads[0]? = some invocation.context.attachedDeposit do
        throw "WasmCert attached_deposit trace payload does not match invocation context"

/-- Content-level call-boundary policy join. Traps roll storage back; views
    cannot mutate storage or create promises. -/
def validateWasmCertObservationForInvocationV1
    (invocationDigest : Digest)
    (invocation : WasmCertInvocationArtifactV1)
    (observation : WasmCertObservationArtifactV1) : Except String Unit := do
  validateWasmCertInvocationArtifactV1 invocation
  validateWasmCertObservationArtifactV1 observation
  unless observation.invocationSha256 = invocationDigest do
    throw "WasmCert observation does not bind the invocation digest"
  unless observation.hostProfile = invocation.hostProfile do
    throw "WasmCert observation does not bind the invocation host profile"
  if observation.status = .trapped then
    unless observation.postStorage = invocation.preStorage do
      throw "WasmCert trapped observation must expose exact pre-storage rollback"
    unless observation.promises.isEmpty do
      throw "WasmCert trapped observation must not expose promises"
  if invocation.context.isView then
    unless observation.postStorage = invocation.preStorage do
      throw "WasmCert view observation must preserve storage"
    unless observation.promises.isEmpty do
      throw "WasmCert view observation must not expose promises"

/-- Decode and join the three canonical artifacts to one provider result
    candidate. Exact-byte hashes are recomputed here. This still does not run
    the provider, rehash its executable against Tool Lock, or activate it. -/
def validateWasmCertProviderArtifactsForRequestV1
    (request : WasmCertProviderRequestV1)
    (requestPath resultPath : String)
    (record : WasmCertProviderResultRecordV1)
    (invocationBytes traceBytes observationBytes : ByteArray) :
    Except String (WasmCertInvocationArtifactV1 ×
      WasmCertHostTraceArtifactV1 × WasmCertObservationArtifactV1) := do
  validateWasmCertProviderResultForRequestV1 request requestPath resultPath record
  let invocation ← decodeWasmCertInvocationArtifactV1 invocationBytes
  let invocationDigest := sha256Bytes invocationBytes
  unless invocationDigest = request.invocationSha256 do
    throw "WasmCert invocation artifact digest does not match the request"
  let trace ← decodeWasmCertHostTraceArtifactV1 traceBytes
  unless sha256Bytes traceBytes = record.hostTraceSha256 do
    throw "WasmCert host trace artifact digest does not match the result"
  let observation ← decodeWasmCertObservationArtifactV1 observationBytes
  unless sha256Bytes observationBytes = record.observationSha256 do
    throw "WasmCert observation artifact digest does not match the result"
  unless trace.events.size ≤ request.fuel.toNat do
    throw "WasmCert host trace event count exceeds request fuel"
  validateWasmCertHostTraceForInvocationV1 invocationDigest invocation trace
  validateWasmCertObservationForInvocationV1 invocationDigest invocation observation
  unless (record.executionStatus = .returned && observation.status = .returned) ||
      (record.executionStatus = .trapped && observation.status = .trapped) do
    throw "WasmCert result and observation terminal statuses differ"
  pure (invocation, trace, observation)

/-- Convert canonical raw rows into the passive storage carrier already used
    by the target-refinement relations. No storage transition is introduced. -/
def storageObservationOfWasmCertRowsV1
    (rows : Array WasmCertStorageRowV1) : StorageObservationV1 := {
  lookup := fun key =>
    match rows.find? (fun row => row.key == key.toUTF8) with
    | some row => some row.value
    | none => none
}

/-- Project the external artifacts into the existing passive call observation.
    The sole business outcome remains `ReferenceMachineV1`; this function only
    changes carrier representation. -/
def callObservationOfWasmCertArtifactsV1
    (invocation : WasmCertInvocationArtifactV1)
    (observation : WasmCertObservationArtifactV1) : CallObservationV1 := {
  exportName := invocation.exportName
  input := invocation.input
  returnData := observation.returnData
  failureObserved := observation.status = .trapped
  logs := observation.logs
  promises := observation.promises
  preStorage := storageObservationOfWasmCertRowsV1 invocation.preStorage
  postStorage := storageObservationOfWasmCertRowsV1 observation.postStorage
}

end ProofForgeV2.Targets.Near
