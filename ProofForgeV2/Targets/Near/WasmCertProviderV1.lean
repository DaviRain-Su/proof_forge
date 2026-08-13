import ProofForgeV2.Core.Common

/-
  Pinned source and fail-closed activation contract for the future
  WasmCert-Coq semantics provider.

  This module intentionally does not run WasmCert, decode its output, or mint
  target-refinement evidence. The upstream binary parser is unverified and no
  reproducible provider executable is present in Tool Lock v4 yet. Product
  consumers must therefore pass `requireWasmCertProviderProvisionedV1` before
  invoking or accepting this provider; it currently always fails closed.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Core.Common

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

/-- Exact argv owned by the future structured wrapper. Paths are arguments, not
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

/-- Closed activation errors. Additional execution/result failures are defined
    only when the structured wrapper exists. -/
inductive WasmCertProviderActivationErrorV1 where
  | executableUnprovisioned
  deriving BEq, Repr

/-- There is deliberately no executable digest until a reproducible wrapper
    artifact is added to the per-platform Tool Lock v4 closure. The upstream
    source revision is not an executable hash. -/
def wasmCertProviderExecutableSha256V1 : Option Digest := none

/-- Mandatory product activation gate. It remains impossible to accept a
    provider result merely because source identity and protocol constants are
    present in this module. -/
def requireWasmCertProviderProvisionedV1 :
    Except WasmCertProviderActivationErrorV1 Digest :=
  match wasmCertProviderExecutableSha256V1 with
  | some digest => .ok digest
  | none => .error .executableUnprovisioned

end ProofForgeV2.Targets.Near
