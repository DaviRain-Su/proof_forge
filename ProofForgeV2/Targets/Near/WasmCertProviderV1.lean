import ProofForgeV2.Core.Common
import ProofForgeV2.Core.ToolLockV4

/-
  Pinned source and fail-closed activation contract for the
  WasmCert-Coq semantics provider.

  This module intentionally does not run WasmCert, decode its output, or mint
  target-refinement evidence. The upstream binary parser remains unverified.
  Product consumers must pass `requireWasmCertProviderProvisionedV1`, resolve
  and rehash the active platform's Tool Lock executable, and validate every
  structured output before accepting a provider observation.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.ToolLockV4

/-- Source/schema annotation carried by
    `supply-chain/wasmcert-coq-authority.v1.json`. This is not executable
    identity and cannot authorize provider output. -/
structure WasmCertCoqSourceAuthorityV1 where
  repository : String
  release : String
  revision : String
  executable : String
  deriving BEq, Repr

def wasmCertCoqRepositoryV1 : String :=
  "https://github.com/WasmCert/WasmCert-Coq"

def wasmCertCoqReleaseV1 : String := "2.2.1"

def wasmCertCoqRevisionV1 : String :=
  "9ab0f87f03fff5507749efc273ec662fe27e6d14"

def wasmCertCoqUpstreamExecutableV1 : String := "wasm_coq_interpreter"

def wasmCertCoqSourceAuthorityV1 : WasmCertCoqSourceAuthorityV1 := {
  repository := wasmCertCoqRepositoryV1
  release := wasmCertCoqReleaseV1
  revision := wasmCertCoqRevisionV1
  executable := wasmCertCoqUpstreamExecutableV1
}

private def isLowerHexCharacterV1 (character : Char) : Bool :=
  ('0' ≤ character && character ≤ '9') ||
    ('a' ≤ character && character ≤ 'f')

/-- Exact source-authority validation. A valid source pin still does not imply
    that a provider executable has been provisioned. -/
def validateWasmCertCoqSourceAuthorityV1
    (authority : WasmCertCoqSourceAuthorityV1) : Except String Unit := do
  unless authority == wasmCertCoqSourceAuthorityV1 do
    throw "WasmCert-Coq source authority does not match the package pin"
  unless authority.revision.length = 40 &&
      authority.revision.all isLowerHexCharacterV1 do
    throw "WasmCert-Coq revision must be exactly 40 lowercase hex characters"

/-- ProofForge-owned structured provider request/result protocols. The
    upstream human/ANSI CLI is not a machine evidence protocol. -/
def wasmCertProviderRequestSchemaV1 : String :=
  "proof-forge.near.wasmcert-request.v1"

def wasmCertProviderResultSchemaV1 : String :=
  "proof-forge.near.wasmcert-result.v1"

def wasmCertProviderToolIdV1 : String := "wasmcert-coq-provider"

def wasmCertProviderExecutableV1 : String :=
  "proof-forge-wasmcert-provider-v1"

def wasmCertProviderVersionV1 : String := "1.0.0"

/-- Exact output of the wrapper's Tool Lock version probe. Presence of this
    string alone does not provision an executable. -/
def wasmCertProviderExpectedVersionV1 : String :=
  s!"{wasmCertProviderExecutableV1} {wasmCertProviderVersionV1} {wasmCertCoqRevisionV1}"

/-- The closed CLI has no extra output-path arguments. Its two canonical
    auxiliary artifacts are derived mechanically from the explicit result
    path, never discovered from the environment. -/
def wasmCertProviderHostTracePathV1 (resultPath : String) : String :=
  resultPath ++ ".host-trace.pf-jcs.json"

def wasmCertProviderObservationPathV1 (resultPath : String) : String :=
  resultPath ++ ".observation.pf-jcs.json"

/-- Closed request field set, recorded here so a future sidecar cannot silently
    widen the semantics-bearing input. `invocationSha256` binds a separate
    canonical invocation/context/pre-state artifact. -/
def wasmCertProviderRequestFieldsV1 : Array String := #[
  "fuel",
  "inputWasmPath",
  "inputWasmSha256",
  "invocationPath",
  "invocationSha256",
  "providerRevision",
  "schema"
]

/-- Closed result field set. A result is a provider record, not a certificate:
    parser status remains explicitly unverified, and host/observation joins
    require separate ProofForge checking. -/
def wasmCertProviderResultFieldsV1 : Array String := #[
  "argv",
  "checkerStatus",
  "executableSha256",
  "executionStatus",
  "hostProfile",
  "hostTraceSha256",
  "inputWasmSha256",
  "instantiationStatus",
  "invocationSha256",
  "observationSha256",
  "parserStatus",
  "providerRevision",
  "schema",
  "simdUsed"
]

/-- Exact argv owned by the structured wrapper. Paths are arguments, not
    shell text. The wrapper must read canonical request bytes and write one
    canonical result record; stdout/stderr are diagnostics only. -/
def wasmCertProviderArgvV1
    (requestPath resultPath : String) : Array String := #[
  "check-execute",
  "--request", requestPath,
  "--result", resultPath
]

/-- Mechanization/trust status of each upstream layer at the pinned revision. -/
inductive WasmCertMechanizationStatusV1 where
  | unverified
  | provedSoundOnSuccess
  | provedInterpreterCore
  | hostAssumptions
  deriving BEq, Repr

def wasmCertBinaryParserStatusV1 : WasmCertMechanizationStatusV1 :=
  .unverified

def wasmCertModuleCheckerStatusV1 : WasmCertMechanizationStatusV1 :=
  .provedSoundOnSuccess

def wasmCertInstantiationStatusV1 : WasmCertMechanizationStatusV1 :=
  .provedSoundOnSuccess

def wasmCertExecutionStatusV1 : WasmCertMechanizationStatusV1 :=
  .provedInterpreterCore

def wasmCertHostStatusV1 : WasmCertMechanizationStatusV1 :=
  .hostAssumptions

/-- Closed activation errors. Execution/result failures remain in the locked
    product consumer. -/
inductive WasmCertProviderActivationErrorV1 where
  | executableUnprovisioned
  | unsupportedPlatform
  deriving BEq, Repr

private def parsePinnedWasmCertExecutableDigestV1 (wire : String) : Option Digest :=
  match parseDigest wire with
  | .ok digest => some digest
  | .error _ => none

/-- Independently audited executable identity for each admitted Tool Lock v4
    closure. A Linux hash cannot activate Darwin, and the upstream source
    revision cannot substitute for either executable hash. -/
def wasmCertProviderExecutableSha256V1 : ToolLockPlatformV4 → Option Digest
  | .darwinArm64 => parsePinnedWasmCertExecutableDigestV1
      "sha256:696b55dd6c02159a5c45f7aba0e1196ee4cc046ac903ffe6b7387763e3399842"
  | .linuxX86_64 => parsePinnedWasmCertExecutableDigestV1
      "sha256:c08b1622b5e9593f9803e60977c40f8531e52e9596dc2549fea14edaf2615919"

/-- Mandatory platform activation gate. The product subsequently resolves and
    rehashes `wasmcert-coq-provider` from the active Tool Lock and requires the
    resolved executable to equal this identity; these constants alone cannot
    authorize provider output. -/
def requireWasmCertProviderProvisionedV1 :
    Except WasmCertProviderActivationErrorV1 Digest :=
  match activeToolLockPlatformV4 with
  | .error _ => .error .unsupportedPlatform
  | .ok platform =>
      match wasmCertProviderExecutableSha256V1 platform with
      | some digest => .ok digest
      | none => .error .executableUnprovisioned

end ProofForgeV2.Targets.Near
