import ProofForgeV2.Targets.Near.WasmCertProviderV1

/-
  Canonical PF-JCS interchange for the unprovisioned WasmCert provider.

  Successful decode establishes only canonical record shape and exact field
  identity. It does not establish that WasmCert ran or that record claims are
  true. Product execution remains blocked by
  `requireWasmCertProviderProvisionedV1`.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Core.Common

def wasmCertProviderHostProfileV1 : String :=
  "proof-forge.near.wasmcert-host.v1"

/-- Hard request ceiling for the future extracted stepper. Zero and unbounded
    execution are forbidden. -/
def wasmCertProviderMaxFuelV1 : UInt64 := 10000000

inductive WasmCertParserResultV1 where
  | parsedUnverified
  | rejected
  deriving BEq, DecidableEq, Repr

inductive WasmCertCheckerResultV1 where
  | acceptedProvedSound
  | rejected
  deriving BEq, DecidableEq, Repr

inductive WasmCertInstantiationResultV1 where
  | acceptedProvedSound
  | rejected
  deriving BEq, DecidableEq, Repr

inductive WasmCertExecutionResultV1 where
  | returned
  | trapped
  | exhausted
  | providerError
  deriving BEq, DecidableEq, Repr

/-- Canonical request data. Paths are lexical project-relative paths; the
    wrapper must not discover semantics-bearing input from its environment. -/
structure WasmCertProviderRequestV1 where
  schema : String
  providerRevision : String
  inputWasmPath : String
  inputWasmSha256 : Digest
  invocationPath : String
  invocationSha256 : Digest
  fuel : UInt64
  deriving DecidableEq, Repr

/-- Canonical provider result data. This is deliberately named a record, not a
    certificate or evidence carrier. -/
structure WasmCertProviderResultRecordV1 where
  schema : String
  providerRevision : String
  executableSha256 : Digest
  argv : Array String
  inputWasmSha256 : Digest
  invocationSha256 : Digest
  parserStatus : WasmCertParserResultV1
  checkerStatus : WasmCertCheckerResultV1
  instantiationStatus : WasmCertInstantiationResultV1
  executionStatus : WasmCertExecutionResultV1
  hostProfile : String
  hostTraceSha256 : Digest
  observationSha256 : Digest
  simdUsed : Bool
  deriving DecidableEq, Repr

private def parserResultWireV1 : WasmCertParserResultV1 → String
  | .parsedUnverified => "parsed-unverified"
  | .rejected => "rejected"

private def parserResultOfWireV1 : String → Except String WasmCertParserResultV1
  | "parsed-unverified" => pure .parsedUnverified
  | "rejected" => pure .rejected
  | value => throw s!"unknown WasmCert parserStatus '{value}'"

private def checkerResultWireV1 : WasmCertCheckerResultV1 → String
  | .acceptedProvedSound => "accepted-proved-sound"
  | .rejected => "rejected"

private def checkerResultOfWireV1 : String → Except String WasmCertCheckerResultV1
  | "accepted-proved-sound" => pure .acceptedProvedSound
  | "rejected" => pure .rejected
  | value => throw s!"unknown WasmCert checkerStatus '{value}'"

private def instantiationResultWireV1 : WasmCertInstantiationResultV1 → String
  | .acceptedProvedSound => "accepted-proved-sound"
  | .rejected => "rejected"

private def instantiationResultOfWireV1 :
    String → Except String WasmCertInstantiationResultV1
  | "accepted-proved-sound" => pure .acceptedProvedSound
  | "rejected" => pure .rejected
  | value => throw s!"unknown WasmCert instantiationStatus '{value}'"

private def executionResultWireV1 : WasmCertExecutionResultV1 → String
  | .returned => "returned"
  | .trapped => "trapped"
  | .exhausted => "exhausted"
  | .providerError => "provider-error"

private def executionResultOfWireV1 : String → Except String WasmCertExecutionResultV1
  | "returned" => pure .returned
  | "trapped" => pure .trapped
  | "exhausted" => pure .exhausted
  | "provider-error" => pure .providerError
  | value => throw s!"unknown WasmCert executionStatus '{value}'"

private def requireObjectV1
    (value : PfJson) (context : String) : Except String (Array (String × PfJson)) :=
  match value with
  | .object fields => pure fields
  | _ => throw s!"{context} must be a PF-JCS object"

private def requireExactKeysV1
    (fields : Array (String × PfJson))
    (expected : Array String)
    (context : String) : Except String Unit := do
  unless fields.size == expected.size do
    throw s!"{context} must have exactly {expected.size} fields"
  for index in List.range fields.size do
    match fields[index]?, expected[index]? with
    | some field, some key =>
        unless field.1 == key do
          throw s!"{context} expected key '{key}', got '{field.1}'"
    | _, _ => throw s!"{context} field index is out of bounds"

private def fieldV1
    (fields : Array (String × PfJson))
    (key context : String) : Except String PfJson :=
  match fields.find? (·.1 == key) with
  | some field => pure field.2
  | none => throw s!"{context} missing field '{key}'"

private def requireStringV1 (value : PfJson) (context : String) : Except String String :=
  match value with
  | .string result => pure result
  | _ => throw s!"{context} must be a string"

private def requireBoolV1 (value : PfJson) (context : String) : Except String Bool :=
  match value with
  | .bool result => pure result
  | _ => throw s!"{context} must be a boolean"

private def requireStringArrayV1
    (value : PfJson) (context : String) : Except String (Array String) :=
  match value with
  | .array values => values.mapM fun value => requireStringV1 value context
  | _ => throw s!"{context} must be an array of strings"

private def requireDigestV1 (value : PfJson) (context : String) : Except String Digest := do
  let wire ← requireStringV1 value context
  match parseDigest wire with
  | .ok digest => pure digest
  | .error error => throw s!"{context}: {error}"

private def requireFuelV1 (value : PfJson) : Except String UInt64 :=
  match value with
  | .int fuel =>
      if 0 < fuel && fuel ≤ Int.ofNat wasmCertProviderMaxFuelV1.toNat then
        pure (UInt64.ofNat fuel.toNat)
      else
        throw s!"WasmCert fuel must be in 1..{wasmCertProviderMaxFuelV1}"
  | _ => throw "WasmCert fuel must be an integer"

private def digestJsonV1 (digest : Digest) : Except String PfJson := do
  pure (.string (← renderDigest digest))

/-- Validate request identity, paths, digests, and bounded fuel. -/
def validateWasmCertProviderRequestV1
    (request : WasmCertProviderRequestV1) : Except String Unit := do
  unless request.schema == wasmCertProviderRequestSchemaV1 do
    throw s!"WasmCert request schema must be '{wasmCertProviderRequestSchemaV1}'"
  unless request.providerRevision == wasmCertCoqRevisionV1 do
    throw "WasmCert request providerRevision does not match the package pin"
  let inputPath ← parseProjectRelativePath request.inputWasmPath
  let invocationPath ← parseProjectRelativePath request.invocationPath
  unless inputPath.value != invocationPath.value do
    throw "WasmCert inputWasmPath and invocationPath must be distinct"
  validateDigest request.inputWasmSha256
  validateDigest request.invocationSha256
  unless 0 < request.fuel && request.fuel ≤ wasmCertProviderMaxFuelV1 do
    throw s!"WasmCert fuel must be in 1..{wasmCertProviderMaxFuelV1}"

/-- Encode one validated canonical request. -/
def encodeWasmCertProviderRequestV1
    (request : WasmCertProviderRequestV1) : Except String String := do
  validateWasmCertProviderRequestV1 request
  renderPfJcs (.object #[
    ("fuel", .int (Int.ofNat request.fuel.toNat)),
    ("inputWasmPath", .string request.inputWasmPath),
    ("inputWasmSha256", ← digestJsonV1 request.inputWasmSha256),
    ("invocationPath", .string request.invocationPath),
    ("invocationSha256", ← digestJsonV1 request.invocationSha256),
    ("providerRevision", .string request.providerRevision),
    ("schema", .string request.schema)
  ])

/-- Decode canonical PF-JCS and reject every unknown/missing/reordered field. -/
def decodeWasmCertProviderRequestV1
    (bytes : ByteArray) : Except String WasmCertProviderRequestV1 := do
  let value ← parsePfJcsBytes bytes
  let fields ← requireObjectV1 value "WasmCert request"
  requireExactKeysV1 fields wasmCertProviderRequestFieldsV1 "WasmCert request"
  let request : WasmCertProviderRequestV1 := {
    fuel := ← requireFuelV1 (← fieldV1 fields "fuel" "WasmCert request")
    inputWasmPath := ← requireStringV1
      (← fieldV1 fields "inputWasmPath" "WasmCert request") "inputWasmPath"
    inputWasmSha256 := ← requireDigestV1
      (← fieldV1 fields "inputWasmSha256" "WasmCert request") "inputWasmSha256"
    invocationPath := ← requireStringV1
      (← fieldV1 fields "invocationPath" "WasmCert request") "invocationPath"
    invocationSha256 := ← requireDigestV1
      (← fieldV1 fields "invocationSha256" "WasmCert request") "invocationSha256"
    providerRevision := ← requireStringV1
      (← fieldV1 fields "providerRevision" "WasmCert request") "providerRevision"
    schema := ← requireStringV1
      (← fieldV1 fields "schema" "WasmCert request") "schema"
  }
  validateWasmCertProviderRequestV1 request
  pure request

/-- Structural result validation only. It deliberately accepts rejected,
    exhausted, and provider-error status records for diagnostics. -/
def validateWasmCertProviderResultRecordV1
    (record : WasmCertProviderResultRecordV1) : Except String Unit := do
  unless record.schema == wasmCertProviderResultSchemaV1 do
    throw s!"WasmCert result schema must be '{wasmCertProviderResultSchemaV1}'"
  unless record.providerRevision == wasmCertCoqRevisionV1 do
    throw "WasmCert result providerRevision does not match the package pin"
  unless record.hostProfile == wasmCertProviderHostProfileV1 do
    throw s!"WasmCert hostProfile must be '{wasmCertProviderHostProfileV1}'"
  validateDigest record.executableSha256
  validateDigest record.inputWasmSha256
  validateDigest record.invocationSha256
  validateDigest record.hostTraceSha256
  validateDigest record.observationSha256

/-- Encode one structurally valid provider record. This does not make the
    record eligible for a Reference join. -/
def encodeWasmCertProviderResultRecordV1
    (record : WasmCertProviderResultRecordV1) : Except String String := do
  validateWasmCertProviderResultRecordV1 record
  renderPfJcs (.object #[
    ("argv", .array (record.argv.map PfJson.string)),
    ("checkerStatus", .string (checkerResultWireV1 record.checkerStatus)),
    ("executableSha256", ← digestJsonV1 record.executableSha256),
    ("executionStatus", .string (executionResultWireV1 record.executionStatus)),
    ("hostProfile", .string record.hostProfile),
    ("hostTraceSha256", ← digestJsonV1 record.hostTraceSha256),
    ("inputWasmSha256", ← digestJsonV1 record.inputWasmSha256),
    ("instantiationStatus",
      .string (instantiationResultWireV1 record.instantiationStatus)),
    ("invocationSha256", ← digestJsonV1 record.invocationSha256),
    ("observationSha256", ← digestJsonV1 record.observationSha256),
    ("parserStatus", .string (parserResultWireV1 record.parserStatus)),
    ("providerRevision", .string record.providerRevision),
    ("schema", .string record.schema),
    ("simdUsed", .bool record.simdUsed)
  ])

/-- Decode a canonical result record. No execution or truth claim is minted. -/
def decodeWasmCertProviderResultRecordV1
    (bytes : ByteArray) : Except String WasmCertProviderResultRecordV1 := do
  let value ← parsePfJcsBytes bytes
  let fields ← requireObjectV1 value "WasmCert result"
  requireExactKeysV1 fields wasmCertProviderResultFieldsV1 "WasmCert result"
  let parserStatus ← parserResultOfWireV1 (← requireStringV1
    (← fieldV1 fields "parserStatus" "WasmCert result") "parserStatus")
  let checkerStatus ← checkerResultOfWireV1 (← requireStringV1
    (← fieldV1 fields "checkerStatus" "WasmCert result") "checkerStatus")
  let instantiationStatus ← instantiationResultOfWireV1 (← requireStringV1
    (← fieldV1 fields "instantiationStatus" "WasmCert result")
      "instantiationStatus")
  let executionStatus ← executionResultOfWireV1 (← requireStringV1
    (← fieldV1 fields "executionStatus" "WasmCert result") "executionStatus")
  let record : WasmCertProviderResultRecordV1 := {
    argv := ← requireStringArrayV1
      (← fieldV1 fields "argv" "WasmCert result") "argv"
    checkerStatus
    executableSha256 := ← requireDigestV1
      (← fieldV1 fields "executableSha256" "WasmCert result") "executableSha256"
    executionStatus
    hostProfile := ← requireStringV1
      (← fieldV1 fields "hostProfile" "WasmCert result") "hostProfile"
    hostTraceSha256 := ← requireDigestV1
      (← fieldV1 fields "hostTraceSha256" "WasmCert result") "hostTraceSha256"
    inputWasmSha256 := ← requireDigestV1
      (← fieldV1 fields "inputWasmSha256" "WasmCert result") "inputWasmSha256"
    instantiationStatus
    invocationSha256 := ← requireDigestV1
      (← fieldV1 fields "invocationSha256" "WasmCert result") "invocationSha256"
    observationSha256 := ← requireDigestV1
      (← fieldV1 fields "observationSha256" "WasmCert result") "observationSha256"
    parserStatus
    providerRevision := ← requireStringV1
      (← fieldV1 fields "providerRevision" "WasmCert result") "providerRevision"
    schema := ← requireStringV1
      (← fieldV1 fields "schema" "WasmCert result") "schema"
    simdUsed := ← requireBoolV1
      (← fieldV1 fields "simdUsed" "WasmCert result") "simdUsed"
  }
  validateWasmCertProviderResultRecordV1 record
  pure record

/-- Identity/status join for a strict provider result candidate. This still
    does not compare executable identity with Tool Lock and cannot activate the
    provider. Returned and trapped are both terminal semantic observations. -/
def validateWasmCertProviderResultForRequestV1
    (request : WasmCertProviderRequestV1)
    (requestPath resultPath : String)
    (record : WasmCertProviderResultRecordV1) : Except String Unit := do
  validateWasmCertProviderRequestV1 request
  validateWasmCertProviderResultRecordV1 record
  let _ ← parseProjectRelativePath requestPath
  let _ ← parseProjectRelativePath resultPath
  unless requestPath != resultPath do
    throw "WasmCert request and result paths must be distinct"
  unless record.argv == wasmCertProviderArgvV1 requestPath resultPath do
    throw "WasmCert result argv does not match the exact invocation"
  unless record.inputWasmSha256 == request.inputWasmSha256 do
    throw "WasmCert result inputWasmSha256 does not match the request"
  unless record.invocationSha256 == request.invocationSha256 do
    throw "WasmCert result invocationSha256 does not match the request"
  unless record.parserStatus == .parsedUnverified do
    throw "WasmCert parser did not return parsed-unverified"
  unless record.checkerStatus == .acceptedProvedSound do
    throw "WasmCert module checker did not accept"
  unless record.instantiationStatus == .acceptedProvedSound do
    throw "WasmCert instantiation did not accept"
  unless record.executionStatus == .returned || record.executionStatus == .trapped do
    throw "WasmCert execution did not reach a supported terminal observation"
  if record.simdUsed then
    throw "WasmCert strict profile rejects SIMD"

end ProofForgeV2.Targets.Near
