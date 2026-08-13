/-
  D3/S7b engineering FinalizedArtifactsV1 finalization-authority tests.

  Real product path only:
    compileValidatedSourceV1 → resolveBuildSelectionV1 →
    resolveEngineeringRequirementsV1 → materializeResult →
    finalizeMaterializedArtifactsV1 / emitProgram

  Not formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity /
  SupportClaim / ToolchainIdentity. No forged private-ctor carriers;
  no reimplemented on-disk renderer.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Emit
import ProofForgeV2.CLI.Main
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Evm.FinalizeV1
import ProofForgeV2.Targets.Near.FinalizeV1
import Tests.Language.ParserSession
import Lean
import Lean.Elab.Command

namespace Tests.Materialization.EngineeringFinalizationV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1
open System
open Lean
open Lean.Elab.Command

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def liftStringExcept (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def materializeOk (label : String) (capability : Targets.ResolvedEngineeringBuildV1) :
    IO MaterializedArtifactsV1 :=
  liftResult label (Targets.materializeResult capability)

private def accumulatorSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Accumulator where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n\n" ++
  "end ProofForgeV2.Examples\n"

private def accumulatorModuleNameV1 : String := "Examples.Accumulator"

private unsafe def compileStateCell : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load StateCell" (← session.selectProgramV1
    Examples.stateCellSourceText "<finalization-stateCell>"
    Examples.stateCellModuleNameV1 none)
  liftResult "compile StateCell" (Compiler.compileValidatedSourceV1 source)

private unsafe def compileAccumulator : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Accumulator" (← session.selectProgramV1
    accumulatorSourceTextV1 "<finalization-accumulator>"
    accumulatorModuleNameV1 none)
  liftResult "compile Accumulator" (Compiler.compileValidatedSourceV1 source)

private def testDraftNote : String :=
  "test-only finalization draft"

private def solanaProductNotePrefix : String :=
  "solana-sbpf-cpi-elf-v1 sbpf "

private def noirNote : String :=
  "NOIR-IR-6: default noir-source-u64-relations-v1 finalization is zero-tool; relation source/schema (.nr transitional/debug base) were emitted without invoking nargo; ACIR product dual-write is opt-in profile noir-nargo-1.0.0-beta.26-acir-v1 (nargo-assisted path-normalized ProgramArtifact finalized-extra); no witness execution, proof, or verification (deployable=false); pure-Lean ACIR opcode encoder is not implemented"

private def aleoNote : String :=
  "Aleo materialization emits canonical Aleo Instructions plus its network-state query descriptor; product finalization performs no compilation, VM execution, proof, deployment, or network query"

/-- Expect an IO error whose message contains `needle`. -/
private def expectIoErrorContains (label needle : String) (act : IO Unit) : IO Unit := do
  try
    act
    throw <| IO.userError s!"{label}: expected failure containing {needle}"
  catch e =>
    let msg := toString e
    expect ((msg.splitOn needle).length > 1)
      s!"{label}: expected '{needle}' in:\n{msg}"

/-- Sole mint + capability/artifact binding positives/negatives. -/
private unsafe def testSoleMintBinding : IO Unit := do
  let compiled ← compileStateCell
  let artifactName := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
  let capability ← liftResult "resolve solana"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← materializeOk "materialize solana" capability
  let draft : EngineeringFinalizationDraftV1 := {
    deployable := false
    extraFiles := #[]
    evidenceNote := testDraftNote
  }
  let ok ← liftResult "mint ok" (mintFinalizedArtifactsV1 capability artifacts draft)
  expect (FinalizedArtifactsV1.deployableOf ok == false)
    "mint must retain the test draft deployable field"
  expect (FinalizedArtifactsV1.extraFilesOf ok == #[])
    "mint must retain the test draft empty extras"
  expect (FinalizedArtifactsV1.evidenceNoteOf ok == testDraftNote)
    "mint must retain the test draft note exactly"
  expect (MaterializedArtifactsV1.targetIdOf (FinalizedArtifactsV1.artifactsOf ok) ==
      TargetId.solana) "mint binds solana artifacts"
  expect (Targets.ResolvedEngineeringBuildV1.targetIdOf
      (FinalizedArtifactsV1.capabilityOf ok) == TargetId.solana)
    "mint binds solana capability"
  -- Empty extras + base files preserved.
  expect (MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf ok) ==
      MaterializedArtifactsV1.filesOf artifacts)
    "mint does not alter base files"
  -- Extra path collision with base → reject.
  let collide : EngineeringFinalizationDraftV1 := {
    deployable := false
    extraFiles := #["StateCell.s"]
    evidenceNote := testDraftNote
  }
  match mintFinalizedArtifactsV1 capability artifacts collide with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "base-path collision → invalidProgram"
  | .ok _ => throw <| IO.userError "extra colliding with base must not mint"
  -- Unsafe extra path → reject.
  let unsafeExtra : EngineeringFinalizationDraftV1 := {
    deployable := false
    extraFiles := #["../escape.bin"]
    evidenceNote := testDraftNote
  }
  match mintFinalizedArtifactsV1 capability artifacts unsafeExtra with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "unsafe extra → invalidProgram"
  | .ok _ => throw <| IO.userError "unsafe extra must not mint"
  -- Duplicate extras → reject.
  let dupExtra : EngineeringFinalizationDraftV1 := {
    deployable := true
    extraFiles := #["StateCell.bin", "StateCell.bin"]
    evidenceNote := "x"
  }
  match mintFinalizedArtifactsV1 capability artifacts dupExtra with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "duplicate extra → invalidProgram"
  | .ok _ => throw <| IO.userError "duplicate extra must not mint"
  -- Capability/artifact target drift via foreign capability.
  let nearSel ← liftResult "select near" (resolveBuildSelectionV1 TargetId.near none)
  let nearCap ← liftResult "resolve near"
    (Targets.resolveEngineeringRequirementsV1 nearSel compiled)
  match mintFinalizedArtifactsV1 nearCap artifacts draft with
  | .error e =>
      expect (e.code == "PF-REGISTRY-INVALID") "target drift → registryInvalid"
  | .ok _ => throw <| IO.userError "capability/artifact target drift must not mint"
  expect (MaterializedArtifactsV1.artifactProgramNameOf artifacts == artifactName &&
      MaterializedArtifactsV1.sourceDigestOf artifacts == sourceDigest &&
      MaterializedArtifactsV1.semanticDigestOf artifacts == semanticDigest)
    "materialized carrier must preserve compiled semantic identity"
  -- Same-target identity gates: StateCell artifacts + Accumulator capability.
  let accCompiled ← compileAccumulator
  expect (CompiledSemanticV1.artifactProgramNameOf accCompiled != artifactName)
    "Accumulator name diverges from StateCell"
  expect (CompiledSemanticV1.sourceDigestOf accCompiled != sourceDigest)
    "Accumulator source digest diverges from StateCell"
  expect (CompiledSemanticV1.semanticDigestOf accCompiled != semanticDigest)
    "Accumulator semantic digest diverges from StateCell"
  let accSel ← liftResult "select solana acc" (resolveBuildSelectionV1 TargetId.solana none)
  let accCap ← liftResult "resolve solana acc"
    (Targets.resolveEngineeringRequirementsV1 accSel accCompiled)
  -- Same targetId; artifact name/digests must still fail closed.
  match mintFinalizedArtifactsV1 accCap artifacts draft with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "compiled identity drift → invalidProgram"
      expect (((e.render.splitOn "artifact program name").length > 1) ||
          ((e.render.splitOn "source digest").length > 1) ||
          ((e.render.splitOn "semantic digest").length > 1))
        s!"identity drift message expected name/digest, got:\n{e.render}"
  | .ok _ =>
      throw <| IO.userError "same-target different-program identity drift must not mint"
  -- Publisher dual-defense extras (would catch mint skip of path uniqueness).
  let basePaths := (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  expectIoErrorContains "publisher collide base" "PF-OUTPUT-PATH" do
    ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["StateCell.s"]
  expectIoErrorContains "publisher unsafe" "PF-OUTPUT-PATH" do
    ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["../escape.bin"]
  expectIoErrorContains "publisher dup extra" "PF-OUTPUT-PATH" do
    ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["extra.bin", "extra.bin"]
  -- Happy path dual-defense accepts safe unique extras.
  ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["StateCell.bin"]

/-- Pre-IO bind: mismatched capability/artifacts fail before tool invocation. -/
private unsafe def testPreIoBindBeforeTools : IO Unit := do
  let stateCell ← compileStateCell
  let accumulator ← compileAccumulator
  let stateCellSel ← liftResult "select evm stateCell"
    (resolveBuildSelectionV1 TargetId.evm none)
  let stateCellCap ← liftResult "resolve evm stateCell"
    (Targets.resolveEngineeringRequirementsV1 stateCellSel stateCell)
  let stateCellArtifacts ← materializeOk "mat stateCell evm" stateCellCap
  let accSel ← liftResult "select evm acc" (resolveBuildSelectionV1 TargetId.evm none)
  let accCap ← liftResult "resolve evm acc"
    (Targets.resolveEngineeringRequirementsV1 accSel accumulator)
  -- Pre-IO compiled identity bind must fail before writing extras.
  -- (If tools ran first with valid StateCell.yul, solc would write StateCell.bin.)
  let staging := FilePath.mk "build/v2/finalization-preio-bind"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  for f in MaterializedArtifactsV1.filesOf stateCellArtifacts do
    IO.FS.writeFile (staging / f.path) f.contents
  try
    let _ ← Targets.finalizeMaterializedArtifactsV1 accCap stateCellArtifacts staging
    throw <| IO.userError "mismatched program pair must fail finalize pre-IO"
  catch e =>
    let msg := toString e
    -- If this was a re-throw of our own assertion, surface it.
    if (msg.splitOn "mismatched program pair").length > 1 then
      throw e
    expect ((msg.splitOn "PF-TOOLCHAIN-MISSING").length == 1)
      s!"pre-IO bind must not invoke tools (TOOLCHAIN-MISSING):\n{msg}"
    expect ((msg.splitOn "PF-TOOLCHAIN-MISMATCH").length == 1)
      s!"pre-IO bind must not invoke tools (TOOLCHAIN-MISMATCH):\n{msg}"
    expect ((msg.splitOn "PF-SRC-INVALID").length > 1)
      s!"pre-IO bind must surface compiled identity failure:\n{msg}"
    expect (!(← (staging / "StateCell.bin").pathExists))
      "pre-IO bind failure must not write .bin extra"

/-- NEAR finalization must bind its materialized WAT to the exact capability
    re-render and then bind staging bytes before resolving/running wat2wasm. -/
private unsafe def testNearFinalizerInputBinding : IO FinalizedArtifactsV1 := do
  let compiled ← compileStateCell
  let selection ← liftResult "select near input binding"
    (resolveBuildSelectionV1 TargetId.near none)
  let capability ← liftResult "resolve near input binding"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← materializeOk "materialize near input binding" capability
  let staging := FilePath.mk "build/v2/finalization-near-input-binding"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  for file in MaterializedArtifactsV1.filesOf artifacts do
    IO.FS.writeFile (staging / file.path) file.contents
  let accumulator ← compileAccumulator
  let accumulatorSelection ← liftResult "select near canonical mismatch"
    (resolveBuildSelectionV1 TargetId.near none)
  let accumulatorCapability ← liftResult "resolve near canonical mismatch"
    (Targets.resolveEngineeringRequirementsV1 accumulatorSelection accumulator)
  expectIoErrorContains "near capability WAT mismatch"
      "materialized WAT input 'StateCell.wat' is not canonical for capability" do
    let _ ← Targets.Near.FinalizeV1.finalize accumulatorCapability artifacts staging
    pure ()
  expect (!(← (staging / "StateCell.wasm").pathExists))
    "noncanonical capability/WAT pair must fail before wat2wasm writes an output"
  IO.FS.writeFile (staging / "StateCell.wat") "(module)\n"
  expectIoErrorContains "near divergent staging WAT"
      "staging WAT input 'StateCell.wat' diverges from materialized bytes" do
    let _ ← Targets.Near.FinalizeV1.finalize capability artifacts staging
    pure ()
  expect (!(← (staging / "StateCell.wasm").pathExists))
    "divergent NEAR WAT input must fail before wat2wasm writes an output"
  liftResult "mint near WasmCert activation carrier"
    (mintFinalizedArtifactsV1 capability artifacts {
      deployable := true
      extraFiles := #["StateCell.wasm"]
      evidenceNote := "test-only locked WasmCert activation boundary"
    })

/-- The bounded core-Wasm consumer must consume every section, enforce
    canonical u32 LEB lengths, and reject duplicate/out-of-order sections. -/
private def expectWasmDecodeError
    (bytes : ByteArray)
    (expected : Targets.Near.WasmBinaryErrorV1)
    (message : String) : IO Unit :=
  match Targets.Near.decodeWasmBinaryModuleV1 bytes with
  | .error actual =>
    expect (actual == expected) s!"{message}: got {repr actual}"
  | .ok sections =>
    throw <| IO.userError s!"{message}: unexpectedly decoded {repr sections}"

private def testNearWasmBinaryEnvelope : IO Unit := do
  let header := ByteArray.mk
    #[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
  let valid := header ++ ByteArray.mk
    #[0x01, 0x01, 0xaa, 0x00, 0x00, 0x03, 0x00, 0x0c, 0x00, 0x0a, 0x00, 0x0b, 0x00]
  match Targets.Near.decodeWasmBinaryModuleV1 valid with
  | .ok sections =>
    expect (sections.map (·.id) == #[1, 0, 3, 12, 10, 11])
      "Wasm envelope must preserve exact section order"
    expect (sections[0]!.payloadOffset == 10 && sections[0]!.payloadSize == 1)
      "Wasm envelope must retain exact payload extent"
  | .error error =>
    throw <| IO.userError s!"valid Wasm envelope rejected: {repr error}"
  expectWasmDecodeError
    (ByteArray.mk #[0x01, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]) .invalidMagic
    "Wasm envelope must reject invalid magic"
  expectWasmDecodeError
    (ByteArray.mk #[0x00, 0x61, 0x73, 0x6d, 0x02, 0x00, 0x00, 0x00])
    .unsupportedVersion
    "Wasm envelope must reject unsupported versions"
  expectWasmDecodeError
    (header ++ ByteArray.mk #[0x01, 0x80, 0x00]) .noncanonicalLeb
    "Wasm envelope must reject nonminimal u32 LEB"
  expectWasmDecodeError
    (header ++ ByteArray.mk #[0x01, 0xff, 0xff, 0xff, 0xff, 0x10]) .lebOverflow
    "Wasm envelope must reject u32 LEB overflow"
  expectWasmDecodeError
    (header ++ ByteArray.mk #[0x01, 0x00, 0x01, 0x00]) (.sectionOrder 1)
    "Wasm envelope must reject duplicate core sections"
  expectWasmDecodeError
    (header ++ ByteArray.mk #[0x02, 0x00, 0x01, 0x00]) (.sectionOrder 1)
    "Wasm envelope must reject out-of-order core sections"
  expectWasmDecodeError
    (header ++ ByteArray.mk #[0x0d, 0x00]) (.invalidSectionId 13)
    "Wasm envelope must fail closed on unsupported section ids"
  expectWasmDecodeError
    (header ++ ByteArray.mk #[0x01, 0x02, 0xaa]) .sectionPayloadOutOfBounds
    "Wasm envelope must reject truncated section payloads"
  expectWasmDecodeError (header ++ ByteArray.mk #[0x00]) .truncated
    "Wasm envelope must not ignore trailing bytes"

/-- The external Wasm semantics source pin is exact, while product activation
    remains fail closed until a structured wrapper executable has a Tool Lock
    digest. Source authority must never substitute for executable identity. -/
private def testNearWasmCertProviderBoundary : IO Unit := do
  match Targets.Near.validateWasmCertCoqSourceAuthorityV1
      Targets.Near.wasmCertCoqSourceAuthorityV1 with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError s!"valid WasmCert source authority rejected: {error}"
  let altered : Targets.Near.WasmCertCoqSourceAuthorityV1 := {
    Targets.Near.wasmCertCoqSourceAuthorityV1 with
    revision := "0ab0f87f03fff5507749efc273ec662fe27e6d14"
  }
  match Targets.Near.validateWasmCertCoqSourceAuthorityV1 altered with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "altered WasmCert revision must fail closed"
  expect (Targets.Near.wasmCertProviderArgvV1 "request.json" "result.json" == #[
      "check-execute", "--request", "request.json", "--result", "result.json"])
    "WasmCert structured provider argv must remain exact"
  expect (Targets.Near.wasmCertProviderExpectedVersionV1 ==
      "proof-forge-wasmcert-provider-v1 1.0.0 9ab0f87f03fff5507749efc273ec662fe27e6d14")
    "WasmCert structured provider version probe must remain exact"
  expect (Targets.Near.wasmCertProviderHostTracePathV1 "result.json" ==
      "result.json.host-trace.pf-jcs.json" &&
      Targets.Near.wasmCertProviderObservationPathV1 "result.json" ==
        "result.json.observation.pf-jcs.json")
    "WasmCert provider auxiliary artifact paths must remain deterministic"
  expect (Targets.Near.wasmCertProviderRequestFieldsV1.size == 7 &&
      Targets.Near.wasmCertProviderResultFieldsV1.size == 14)
    "WasmCert request/result protocols must retain their closed field sets"
  expect (Targets.Near.wasmCertBinaryParserStatusV1 == .unverified &&
      Targets.Near.wasmCertModuleCheckerStatusV1 == .provedSoundOnSuccess &&
      Targets.Near.wasmCertInstantiationStatusV1 == .provedSoundOnSuccess &&
      Targets.Near.wasmCertExecutionStatusV1 == .provedInterpreterCore &&
      Targets.Near.wasmCertHostStatusV1 == .hostAssumptions)
    "WasmCert mechanization boundary must remain explicit"
  expect ((Targets.Near.wasmCertProviderExecutableSha256V1
      .darwinArm64).isNone &&
      (Targets.Near.wasmCertProviderExecutableSha256V1
        .linuxX86_64).isNone)
    "WasmCert provider activation must remain independently closed on both platforms"
  match Targets.Near.requireWasmCertProviderProvisionedV1 with
  | .error .executableUnprovisioned => pure ()
  | .error .unsupportedPlatform =>
      throw <| IO.userError "test target unexpectedly lacks a supported Tool Lock platform"
  | .ok _ =>
      throw <| IO.userError
        "WasmCert provider must not activate without a Tool Lock executable digest"

/-- The isolated product consumer accepts only a capability-bound finalized
    NEAR Wasm closure and then fails at provider activation before reading the
    staging artifact. A local provider binary and PATH cannot bypass this gate. -/
private def testNearWasmCertProductActivationBoundary
    (finalized : FinalizedArtifactsV1) : IO Unit := do
  expect (Targets.Near.wasmCertLockedExecutionIdentitySchemaV1 ==
      "proof-forge.near.wasmcert-locked-execution.v1")
    "WasmCert locked execution identity schema must remain exact"
  let zero16 := ByteArray.mk (Array.replicate 16 (0 : UInt8))
  let invocation : Targets.Near.WasmCertInvocationArtifactV1 := {
    schema := Targets.Near.wasmCertInvocationArtifactSchemaV1
    hostProfile := Targets.Near.wasmCertProviderHostProfileV1
    observationPolicy := Targets.Near.wasmCertObservationPolicyV1
    exportName := "init"
    input := ByteArray.empty
    context := {
      currentAccountId := "state-cell.test.near"
      signerAccountId := "alice.test.near"
      signerAccountPk := ByteArray.mk (Array.replicate 33 (1 : UInt8))
      predecessorAccountId := "alice.test.near"
      blockHeight := 42
      blockTimestampNanos := 1700000000000000000
      epochHeight := 7
      accountBalance := zero16
      accountLockedBalance := zero16
      storageUsage := 0
      attachedDeposit := zero16
      prepaidGas := 300000000000000
      randomSeed := ByteArray.mk (Array.replicate 32 (2 : UInt8))
      isView := false
      outputDataReceivers := #[]
      promiseResults := #[]
    }
    preStorage := #[]
  }
  let absentStaging := FilePath.mk "build/v2/wasmcert-product-must-not-read"
  if ← absentStaging.pathExists then IO.FS.removeDirAll absentStaging
  expectIoErrorContains "locked WasmCert activation" "PF-TOOLCHAIN-MISSING" do
    let _ ← Targets.Near.executeLockedWasmCertV1
      finalized absentStaging invocation 100000
    pure ()
  expect (!(← absentStaging.pathExists))
    "unprovisioned WasmCert product consumer must not create or read staging"

/-- Canonical provider interchange is strict record plumbing only: request and
    result identity/status join can succeed, while noncanonical/unknown fields,
    digest drift, rejected stages, and SIMD fail closed. -/
private def testNearWasmCertProviderWire : IO Unit := do
  let inputDigest := sha256Bytes "wasm-input".toUTF8
  let invocationDigest := sha256Bytes "invocation".toUTF8
  let request : Targets.Near.WasmCertProviderRequestV1 := {
    schema := Targets.Near.wasmCertProviderRequestSchemaV1
    providerRevision := Targets.Near.wasmCertCoqRevisionV1
    inputWasmPath := "work/VerifiedVaultPF.wasm"
    inputWasmSha256 := inputDigest
    invocationPath := "work/invocation.pf-jcs.json"
    invocationSha256 := invocationDigest
    fuel := 100000
  }
  let requestText ← liftStringExcept "encode WasmCert request"
    (Targets.Near.encodeWasmCertProviderRequestV1 request)
  let decodedRequest ← liftStringExcept "decode WasmCert request"
    (Targets.Near.decodeWasmCertProviderRequestV1 requestText.toUTF8)
  expect (decodedRequest == request) "WasmCert request canonical roundtrip"
  let zeroFuel := { request with fuel := 0 }
  match Targets.Near.validateWasmCertProviderRequestV1 zeroFuel with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "zero WasmCert fuel must fail closed"
  let excessiveFuel := {
    request with fuel := Targets.Near.wasmCertProviderMaxFuelV1 + 1
  }
  match Targets.Near.validateWasmCertProviderRequestV1 excessiveFuel with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "excessive WasmCert fuel must fail closed"
  match Targets.Near.decodeWasmCertProviderRequestV1 (requestText ++ "\n").toUTF8 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "noncanonical WasmCert request must fail closed"
  let unknownFieldText := "{\"extra\":0," ++ (requestText.drop 1).copy
  match Targets.Near.decodeWasmCertProviderRequestV1 unknownFieldText.toUTF8 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "unknown WasmCert request field must fail closed"
  let requestPath := "work/request.pf-jcs.json"
  let resultPath := "work/result.pf-jcs.json"
  let record : Targets.Near.WasmCertProviderResultRecordV1 := {
    schema := Targets.Near.wasmCertProviderResultSchemaV1
    providerRevision := Targets.Near.wasmCertCoqRevisionV1
    executableSha256 := sha256Bytes "provider".toUTF8
    argv := Targets.Near.wasmCertProviderArgvV1 requestPath resultPath
    inputWasmSha256 := inputDigest
    invocationSha256 := invocationDigest
    parserStatus := .parsedUnverified
    checkerStatus := .acceptedProvedSound
    instantiationStatus := .acceptedProvedSound
    executionStatus := .returned
    hostProfile := Targets.Near.wasmCertProviderHostProfileV1
    hostTraceSha256 := sha256Bytes "trace".toUTF8
    observationSha256 := sha256Bytes "observation".toUTF8
    simdUsed := false
  }
  let resultText ← liftStringExcept "encode WasmCert result"
    (Targets.Near.encodeWasmCertProviderResultRecordV1 record)
  let decodedRecord ← liftStringExcept "decode WasmCert result"
    (Targets.Near.decodeWasmCertProviderResultRecordV1 resultText.toUTF8)
  expect (decodedRecord == record) "WasmCert result canonical roundtrip"
  match Targets.Near.decodeWasmCertProviderResultRecordV1
      (resultText ++ "\n").toUTF8 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "noncanonical WasmCert result must fail closed"
  let unknownResultFieldText := "{\"extra\":0," ++ (resultText.drop 1).copy
  match Targets.Near.decodeWasmCertProviderResultRecordV1
      unknownResultFieldText.toUTF8 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "unknown WasmCert result field must fail closed"
  let _ ← liftStringExcept "join WasmCert request/result candidate"
    (Targets.Near.validateWasmCertProviderResultForRequestV1
      request requestPath resultPath record)
  let wrongInput := { record with inputWasmSha256 := sha256Bytes "wrong".toUTF8 }
  match Targets.Near.validateWasmCertProviderResultForRequestV1
      request requestPath resultPath wrongInput with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert input digest drift must fail closed"
  let rejected := { record with checkerStatus := .rejected }
  match Targets.Near.validateWasmCertProviderResultForRequestV1
      request requestPath resultPath rejected with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert checker rejection must fail join"
  let parserRejected := { record with parserStatus := .rejected }
  match Targets.Near.validateWasmCertProviderResultForRequestV1
      request requestPath resultPath parserRejected with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert parser rejection must fail join"
  let instantiationRejected := { record with instantiationStatus := .rejected }
  match Targets.Near.validateWasmCertProviderResultForRequestV1
      request requestPath resultPath instantiationRejected with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert instantiation rejection must fail join"
  let exhausted := { record with executionStatus := .exhausted }
  match Targets.Near.validateWasmCertProviderResultForRequestV1
      request requestPath resultPath exhausted with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert exhaustion must fail join"
  let simd := { record with simdUsed := true }
  match Targets.Near.validateWasmCertProviderResultForRequestV1
      request requestPath resultPath simd with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert strict profile must reject SIMD"

/-- Canonical invocation/trace/observation artifacts bind actual content, keep
    the strict host ABI closed, enforce rollback/view policy, and project only
    into the existing passive observation carrier. They still do not activate
    or execute the unprovisioned provider. -/
private def testNearWasmCertArtifacts : IO Unit := do
  let zero16 := ByteArray.mk (Array.replicate 16 (0 : UInt8))
  let layoutRow : Targets.Near.WasmCertStorageRowV1 := {
    key := "pf:v1:layout".toUTF8
    value := ByteArray.mk #[1, 0, 0, 0, 0, 0, 0, 0]
  }
  let stateRow : Targets.Near.WasmCertStorageRowV1 := {
    key := "pf:v1:state:0".toUTF8
    value := ByteArray.mk #[10, 0, 0, 0, 0, 0, 0, 0]
  }
  let context : Targets.Near.WasmCertNearContextV1 := {
    currentAccountId := "vault.test.near"
    signerAccountId := "alice.test.near"
    signerAccountPk := ByteArray.mk (Array.replicate 33 (1 : UInt8))
    predecessorAccountId := "alice.test.near"
    blockHeight := 42
    blockTimestampNanos := 1700000000000000000
    epochHeight := 7
    accountBalance := zero16
    accountLockedBalance := zero16
    storageUsage := 128
    attachedDeposit := zero16
    prepaidGas := 300000000000000
    randomSeed := ByteArray.mk (Array.replicate 32 (2 : UInt8))
    isView := true
    outputDataReceivers := #[]
    promiseResults := #[]
  }
  let invocation : Targets.Near.WasmCertInvocationArtifactV1 := {
    schema := Targets.Near.wasmCertInvocationArtifactSchemaV1
    hostProfile := Targets.Near.wasmCertProviderHostProfileV1
    observationPolicy := Targets.Near.wasmCertObservationPolicyV1
    exportName := "status"
    input := ByteArray.empty
    context
    preStorage := #[layoutRow, stateRow]
  }
  let invocationText ← liftStringExcept "encode WasmCert invocation artifact"
    (Targets.Near.encodeWasmCertInvocationArtifactV1 invocation)
  let invocationBytes := invocationText.toUTF8
  let decodedInvocation ← liftStringExcept "decode WasmCert invocation artifact"
    (Targets.Near.decodeWasmCertInvocationArtifactV1 invocationBytes)
  expect (decodedInvocation == invocation)
    "WasmCert invocation artifact canonical roundtrip"
  match Targets.Near.decodeWasmCertHexV1 "AA" 1 "uppercase" with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "WasmCert raw bytes must use lowercase hex"
  let duplicateStorage := { invocation with preStorage := #[layoutRow, layoutRow] }
  match Targets.Near.validateWasmCertInvocationArtifactV1 duplicateStorage with
  | .error _ => pure ()
  | .ok () =>
      throw <| IO.userError "WasmCert invocation storage keys must be unique and ordered"

  let invocationDigest := sha256Bytes invocationBytes
  let returnBytes := ByteArray.mk #[10, 0, 0, 0, 0, 0, 0, 0]
  let inputEvent : Targets.Near.WasmCertHostTraceEventV1 := {
    index := 0
    importName := "env.input"
    arguments := #[0]
    result := none
    payloads := #[ByteArray.empty]
  }
  let returnEvent : Targets.Near.WasmCertHostTraceEventV1 := {
    index := 1
    importName := "env.value_return"
    arguments := #[8, 0]
    result := none
    payloads := #[returnBytes]
  }
  let trace : Targets.Near.WasmCertHostTraceArtifactV1 := {
    schema := Targets.Near.wasmCertHostTraceArtifactSchemaV1
    hostProfile := Targets.Near.wasmCertProviderHostProfileV1
    invocationSha256 := invocationDigest
    events := #[inputEvent, returnEvent]
  }
  let traceText ← liftStringExcept "encode WasmCert host trace artifact"
    (Targets.Near.encodeWasmCertHostTraceArtifactV1 trace)
  let traceBytes := traceText.toUTF8
  let decodedTrace ← liftStringExcept "decode WasmCert host trace artifact"
    (Targets.Near.decodeWasmCertHostTraceArtifactV1 traceBytes)
  expect (decodedTrace == trace) "WasmCert host trace canonical roundtrip"
  let unknownImport := {
    trace with events := #[{ inputEvent with importName := "env.unknown" }]
  }
  match Targets.Near.validateWasmCertHostTraceArtifactV1 unknownImport with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert host imports must fail closed"
  let nonDenseTrace := { trace with events := #[{ inputEvent with index := 1 }] }
  match Targets.Near.validateWasmCertHostTraceArtifactV1 nonDenseTrace with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert host trace indices must be dense"

  let observation : Targets.Near.WasmCertObservationArtifactV1 := {
    schema := Targets.Near.wasmCertObservationArtifactSchemaV1
    hostProfile := Targets.Near.wasmCertProviderHostProfileV1
    invocationSha256 := invocationDigest
    status := .returned
    trapKind := none
    returnData := some returnBytes
    postStorage := invocation.preStorage
    logs := #[]
    promises := #[]
  }
  let observationText ← liftStringExcept "encode WasmCert observation artifact"
    (Targets.Near.encodeWasmCertObservationArtifactV1 observation)
  let observationBytes := observationText.toUTF8
  let decodedObservation ← liftStringExcept "decode WasmCert observation artifact"
    (Targets.Near.decodeWasmCertObservationArtifactV1 observationBytes)
  expect (decodedObservation == observation)
    "WasmCert observation artifact canonical roundtrip"
  let trappedWithoutRollback := {
    observation with
    status := .trapped
    trapKind := some .host
    returnData := none
    postStorage := #[layoutRow]
  }
  match Targets.Near.validateWasmCertObservationForInvocationV1
      invocationDigest invocation trappedWithoutRollback with
  | .error _ => pure ()
  | .ok () =>
      throw <| IO.userError "WasmCert trapped observation must roll storage back"
  let driftedInputTrace := {
    trace with events := #[{ inputEvent with payloads := #[ByteArray.mk #[1]] }]
  }
  match Targets.Near.validateWasmCertHostTraceForInvocationV1
      invocationDigest invocation driftedInputTrace with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "WasmCert env.input trace must bind invocation input"

  let requestPath := "work/request.pf-jcs.json"
  let resultPath := "work/result.pf-jcs.json"
  let request : Targets.Near.WasmCertProviderRequestV1 := {
    schema := Targets.Near.wasmCertProviderRequestSchemaV1
    providerRevision := Targets.Near.wasmCertCoqRevisionV1
    inputWasmPath := "work/VerifiedVaultPF.wasm"
    inputWasmSha256 := sha256Bytes "wasm-input".toUTF8
    invocationPath := "work/invocation.pf-jcs.json"
    invocationSha256 := invocationDigest
    fuel := 100
  }
  let record : Targets.Near.WasmCertProviderResultRecordV1 := {
    schema := Targets.Near.wasmCertProviderResultSchemaV1
    providerRevision := Targets.Near.wasmCertCoqRevisionV1
    executableSha256 := sha256Bytes "unactivated-provider-candidate".toUTF8
    argv := Targets.Near.wasmCertProviderArgvV1 requestPath resultPath
    inputWasmSha256 := request.inputWasmSha256
    invocationSha256 := invocationDigest
    parserStatus := .parsedUnverified
    checkerStatus := .acceptedProvedSound
    instantiationStatus := .acceptedProvedSound
    executionStatus := .returned
    hostProfile := Targets.Near.wasmCertProviderHostProfileV1
    hostTraceSha256 := sha256Bytes traceBytes
    observationSha256 := sha256Bytes observationBytes
    simdUsed := false
  }
  let _ ← liftStringExcept "join WasmCert artifact candidate content"
    (Targets.Near.validateWasmCertProviderArtifactsForRequestV1 request
      requestPath resultPath record invocationBytes traceBytes observationBytes)
  let forgedReturnTrace := {
    trace with events := #[inputEvent, {
      returnEvent with payloads := #[ByteArray.mk #[11, 0, 0, 0, 0, 0, 0, 0]]
    }]
  }
  match Targets.Near.validateWasmCertHostReplayForObservationV1
      invocationDigest invocation forgedReturnTrace observation with
  | .error _ => pure ()
  | .ok () =>
      throw <| IO.userError
        "WasmCert observation return data must be justified by host-trace replay"
  let wrongObservationRecord := {
    record with observationSha256 := sha256Bytes "wrong-observation".toUTF8
  }
  match Targets.Near.validateWasmCertProviderArtifactsForRequestV1 request
      requestPath resultPath wrongObservationRecord invocationBytes traceBytes
      observationBytes with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "WasmCert artifact content digest drift must fail closed"
  let passive :=
    Targets.Near.callObservationOfWasmCertArtifactsV1 invocation observation
  expect (passive.exportName == "status" && passive.failureObserved == false &&
      passive.returnData == some returnBytes &&
      passive.preStorage.lookup "pf:v1:state:0" == some stateRow.value)
    "WasmCert artifacts must project into the existing passive observation carrier"

/-- Hermetic PF-ARTIFACT-NONDEPLOYABLE gates (empty solc bytecode + bad Wasm). -/
private unsafe def testNonDeployablePhases : IO Unit := do
  -- Empty solc bytecode presence gate.
  expectIoErrorContains "empty solc bytecode" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Evm.FinalizeV1.requireNonemptySolcBytecode ""
  -- Non-empty bytecode accepts (gate is post-trim in finalize).
  Targets.Evm.FinalizeV1.requireNonemptySolcBytecode "6000"
  -- Missing Wasm artifact path.
  let staging := FilePath.mk "build/v2/finalization-nondeployable"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  expectIoErrorContains "missing wasm" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "StateCell.wasm")
  -- Non-file (directory) Wasm path.
  IO.FS.createDirAll (staging / "StateCell.wasm")
  expectIoErrorContains "wasm dir not file" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "StateCell.wasm")
  IO.FS.removeDirAll (staging / "StateCell.wasm")
  -- Invalid Wasm header (too short / wrong magic).
  IO.FS.writeBinFile (staging / "StateCell.wasm") (ByteArray.mk #[0x00, 0x01, 0x02, 0x03])
  expectIoErrorContains "bad wasm header" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "StateCell.wasm")
  expectIoErrorContains "bad wasm magic bytes" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireValidWasmHeader (ByteArray.mk #[0x00, 0x61, 0x73, 0x6d])
  expectIoErrorContains "noncanonical Wasm section length" "invalid Wasm binary envelope" do
    Targets.Near.FinalizeV1.requireValidWasmBinaryEnvelope
      (ByteArray.mk #[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x80, 0x00])
  -- Valid minimal header accepts.
  let validHeader := ByteArray.mk #[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
  Targets.Near.FinalizeV1.requireValidWasmHeader validHeader
  Targets.Near.FinalizeV1.requireValidWasmBinaryEnvelope validHeader
  IO.FS.writeBinFile (staging / "StateCell.wasm") validHeader
  Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "StateCell.wasm")

/-- Exact finalization paths/deployable/evidence notes via the product path. -/
private unsafe def testFourTargetFinalization : IO Unit := do
  let compiled ← compileStateCell
  let sourceHash ← liftResult "derive StateCell source hash"
    (CompiledSemanticV1.artifactSourceHashHexOf compiled)
  -- Solana: sole CPI-ELF rail finalizes with locked sbpf and publishes .so.
  do
    let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
    let capability ← liftResult "resolve solana"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat solana" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    let outDir := FilePath.mk "build/v2/finalization-solana"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == true) "solana sole CPI-ELF rail deployable"
    expect (receipt.target == TargetId.solana) "solana emit target"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"solana base byte preservation {f.path}"
    let soBytes ← IO.FS.readBinFile (outDir / "StateCell.so")
    expect (!soBytes.isEmpty) "solana locked sbpf must publish nonempty StateCell.so"
    expect (!(← (outDir / "StateCell.bin").pathExists)) "solana no EVM .bin"
    expect (!(← (outDir / "StateCell.wasm").pathExists)) "solana no Wasm artifact"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn solanaProductNotePrefix).length > 1 &&
        (evidence.splitOn "profile=solana-sbpf-cpi-elf-v1").length > 1 &&
        (evidence.splitOn "planDigest=sha256:").length > 1 &&
        (evidence.splitOn "completed successfully").length > 1)
      "solana evidence must bind sole profile, Plan digest, and locked-sbpf success"
    let manifest ← IO.FS.readFile (outDir / "manifest.json")
    expect ((manifest.splitOn "\"deployable\": true").length > 1)
      "solana manifest deployable"
    expect ((manifest.splitOn "\"path\": \"StateCell.s\"").length > 1)
      "solana base in manifest"
    expect ((manifest.splitOn "\"path\": \"StateCell.so\"").length > 1 &&
        (manifest.splitOn "\"role\": \"finalized-extra\"").length > 1)
      "solana manifest binds StateCell.so as finalized extra"
  -- Noir: zero-tool product emit.
  do
    let selection ← liftResult "select noir" (resolveBuildSelectionV1 TargetId.noir none)
    let capability ← liftResult "resolve noir"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat noir" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    let outDir := FilePath.mk "build/v2/finalization-noir"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == false) "noir emit non-deployable"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"noir base byte preservation {f.path}"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn noirNote).length > 1) "noir exact note on disk"
  -- Aleo Instructions finalization is zero-tool and non-deployable.
  do
    let selection ← liftResult "select aleo" (resolveBuildSelectionV1 TargetId.aleo none)
    let capability ← liftResult "resolve aleo"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat aleo" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    expect (baseFiles.map (·.path) ==
        #["statecell.aleo", "statecell.aleo-query-contract.json"])
      s!"aleo base paths, got {baseFiles.map (·.path)}"
    expect (baseFiles[0]!.mediaType == "text/plain" &&
        baseFiles[1]!.mediaType == "application/json")
      "aleo base mediaTypes"
    let outDir := FilePath.mk "build/v2/finalization-aleo"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == false) "aleo emit non-deployable"
    expect (receipt.target == TargetId.aleo) "aleo emit target"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"aleo base byte preservation {f.path}"
    expect (!(← (outDir / "StateCell.wasm").pathExists)) "aleo no compiled wasm"
    expect (!(← (outDir / "statecell.wasm").pathExists)) "aleo no lowercase wasm extra"
    -- Zero-tool finalize: no finalized-extra siblings beyond the two base files
    -- + transitional sidecars.
    expect (!(← (outDir / "statecell.bin").pathExists)) "aleo no .bin extra"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn aleoNote).length > 1) "aleo exact zero-tool note on disk"
    let manifest ← IO.FS.readFile (outDir / "manifest.json")
    expect ((manifest.splitOn "\"deployable\": false").length > 1)
      "aleo manifest non-deployable"
    expect ((manifest.splitOn "statecell.aleo").length > 1)
      "aleo primary Instructions base in manifest"
    let primaryDisk ← IO.FS.readFile (outDir / "statecell.aleo")
    expect (primaryDisk.contains "program statecell.aleo;")
      "aleo zero-tool primary is Instructions text"
    expect (!primaryDisk.contains "program statecell.aleo {")
      "aleo zero-tool primary uses the Instructions grammar"
    expect ((manifest.splitOn "statecell.aleo-query-contract.json").length > 1)
      "aleo query-contract base in manifest"
  -- EVM: real solc .bin extra + base preservation.
  do
    let selection ← liftResult "select evm" (resolveBuildSelectionV1 TargetId.evm none)
    let capability ← liftResult "resolve evm"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat evm" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    expect (baseFiles.map (·.path) == #["StateCell.yul", "StateCell.abi.json"])
      "evm base paths"
    let outDir := FilePath.mk "build/v2/finalization-evm"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == true) "evm emit deployable"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"evm base byte preservation {f.path}"
    let binPath := outDir / "StateCell.bin"
    expect (← binPath.pathExists) "evm writes StateCell.bin"
    let bin ← IO.FS.readFile binPath
    expect (!bin.isEmpty && bin.endsWith "\n") "evm .bin nonempty trailing newline"
    let hexBody := if bin.endsWith "\n" then bin.dropEnd 1 |>.copy else bin
    expect (hexBody.all fun c =>
        ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F'))
      "evm .bin is hex bytecode + newline"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn "solc ").length > 1) "evm evidence solc note"
    expect ((evidence.splitOn "completed successfully").length > 1)
      "evm evidence success phrase"
    let manifest ← IO.FS.readFile (outDir / "manifest.json")
    expect ((manifest.splitOn "\"deployable\": true").length > 1) "evm manifest deployable"
    expect ((manifest.splitOn "StateCell.bin").length > 1) "evm manifest includes .bin"
    expect ((manifest.splitOn sourceHash).length > 1) "evm manifest sourceHash"
  -- NEAR: real wat2wasm .wasm + base wat preservation.
  do
    let selection ← liftResult "select near" (resolveBuildSelectionV1 TargetId.near none)
    let capability ← liftResult "resolve near"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat near" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    expect (baseFiles.map (·.path) == #["StateCell.wat", "StateCell.near-abi.json"])
      "near base paths"
    let outDir := FilePath.mk "build/v2/finalization-near"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == true) "near emit deployable"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"near base byte preservation {f.path}"
    let wasmPath := outDir / "StateCell.wasm"
    expect (← wasmPath.pathExists) "near writes StateCell.wasm"
    let wasm ← IO.FS.readBinFile wasmPath
    expect (wasm.size >= 8 && wasm[0]! == 0x00 && wasm[1]! == 0x61 &&
        wasm[2]! == 0x73 && wasm[3]! == 0x6d && wasm[4]! == 0x01 &&
        wasm[5]! == 0x00 && wasm[6]! == 0x00 && wasm[7]! == 0x00)
      "near wasm magic/version header"
    let watSha256 := Crypto.sha256Hex baseFiles[0]!.contents.toUTF8
    let wasmSha256 := Crypto.sha256Hex wasm
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn "near-wat2wasm-observation-v1").length > 1 &&
        (evidence.splitOn "tool=wat2wasm").length > 1 &&
        (evidence.splitOn "argv=StateCell.wat,-o,StateCell.wasm").length > 1)
      "near evidence must identify the locked consumer and exact argv"
    expect ((evidence.splitOn s!"inputPath=StateCell.wat inputSha256={watSha256}").length > 1 &&
        (evidence.splitOn "canonicalRerenderIdentity=true").length > 1 &&
        (evidence.splitOn s!"outputPath=StateCell.wasm outputSha256={wasmSha256}").length > 1)
      "near evidence must bind canonical WAT input and observed Wasm output bytes"
    expect ((evidence.splitOn "validWasmHeader=true").length > 1 &&
        (evidence.splitOn "canonicalSectionEnvelope=true").length > 1 &&
        (evidence.splitOn "translator correctness and runtime remain separate").length > 1)
      "near evidence must preserve the consumer-provenance assurance boundary"
    let manifest ← IO.FS.readFile (outDir / "manifest.json")
    expect ((manifest.splitOn "StateCell.wasm").length > 1 &&
        (manifest.splitOn watSha256).length > 1 &&
        (manifest.splitOn wasmSha256).length > 1)
      "near manifest must inventory both exact WAT and Wasm content digests"

/-- Spawn product CLI with an isolated tool-root override (no process-global setEnv). -/
private def runProductCliWithToolRoot (toolRoot : String) (args : Array String) :
    IO IO.Process.Output :=
  IO.Process.output {
    cmd := "lake"
    args := #["env", ".lake/build/bin/proof-forge-next"] ++ args
    env := #[("PROOF_FORGE_TOOL_ROOT", toolRoot)]
    inheritEnv := true
  }

/-- Tool-failure zero publish (EVM missing tool root via CLI child process). -/
private unsafe def testToolFailureZeroPublish : IO Unit := do
  -- Ensure product CLI exists for this focused suite.
  let build ← IO.Process.output { cmd := "lake", args := #["build", "proof_forge_next"] }
  expect (build.exitCode == 0) s!"proof_forge_next build failed:\n{build.stderr}"
  let outDir := FilePath.mk "build/v2/finalization-tool-fail"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let result ← runProductCliWithToolRoot "/definitely/missing-s7b-tool-root" #[
    "build", "Examples/StateCell.lean", "--module", "Examples.StateCell",
    "--target", "evm", "-o", outDir.toString
  ]
  expect (result.exitCode != 0) "missing solc must fail closed"
  let combined := result.stdout ++ result.stderr
  expect (((combined.splitOn "PF-TOOLCHAIN-MISSING").length > 1) ||
      ((combined.splitOn "PF-TOOLCHAIN-MISMATCH").length > 1))
    s!"missing solc must surface toolchain diagnostic:\n{combined}"
  expect (!(← outDir.pathExists)) "tool failure must not publish output directory"

/-- NEAR missing/mismatch zero-output without weakening EVM. -/
private unsafe def testNearToolFailureZeroPublish : IO Unit := do
  let outDir := FilePath.mk "build/v2/finalization-near-tool-fail"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let result ← runProductCliWithToolRoot "/definitely/missing-s7b-near-tool-root" #[
    "build", "Examples/StateCell.lean", "--module", "Examples.StateCell",
    "--target", "near", "-o", outDir.toString
  ]
  expect (result.exitCode != 0) "missing wat2wasm must fail closed"
  let combined := result.stdout ++ result.stderr
  expect (((combined.splitOn "PF-TOOLCHAIN-MISSING").length > 1) ||
      ((combined.splitOn "PF-TOOLCHAIN-MISMATCH").length > 1))
    s!"missing wat2wasm must surface toolchain diagnostic:\n{combined}"
  expect (!(← outDir.pathExists)) "NEAR tool failure must not publish"
  -- EVM product path still works with normal tool root (no weakening).
  let compiled ← compileStateCell
  let evmSel ← liftResult "select evm restore" (resolveBuildSelectionV1 TargetId.evm none)
  let evmCap ← liftResult "resolve evm restore"
    (Targets.resolveEngineeringRequirementsV1 evmSel compiled)
  let evmOut := FilePath.mk "build/v2/finalization-evm-after-near-fail"
  if ← evmOut.pathExists then IO.FS.removeDirAll evmOut
  let receipt ← ProofForgeV2.CLI.emitProgram evmCap evmOut
  expect (receipt.deployable == true) "EVM still deployable after NEAR tool-fail case"
  expect (← (evmOut / "StateCell.bin").pathExists) "EVM still emits .bin"

/-- CLI authority deletion pins (source + Environment). -/
private unsafe def testCliAuthorityDeletion : IO Unit := do
  let rg (pat : String) (paths : Array String) : IO (UInt32 × String) := do
    let args := #["--glob", "*.lean", "-n", "--no-heading", pat] ++ paths
    let out ← IO.Process.output { cmd := "rg", args }
    pure (out.exitCode, out.stdout)
  -- Deleted CLI tool/finalize product surfaces.
  for pat in #[
      "finalizeEvm",
      "finalizeNear",
      "CLI\\.Toolchain",
      "import ProofForgeV2\\.CLI\\.Toolchain",
      "resolve \"solc\"",
      "resolve \"wat2wasm\""
    ] do
    let (ec, hits) ← rg pat #["ProofForgeV2/CLI"]
    expect (ec == 1) s!"CLI deletion: forbidden pattern still present for {pat}:\n{hits}"
  -- CLI/Toolchain.lean file must not exist.
  expect (!(← (FilePath.mk "ProofForgeV2/CLI/Toolchain.lean").pathExists))
    "CLI/Toolchain.lean must be deleted"
  -- Sole FinalizedArtifactsV1.mk near mint.
  let (ecMk, hitsMk) ← rg "FinalizedArtifactsV1\\.mk" #["ProofForgeV2"]
  expect (ecMk == 0) s!"sole mint: expected FinalizedArtifactsV1.mk hits:\n{hitsMk}"
  let lines := (hitsMk.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (lines.length == 1)
    s!"sole mint: expected exactly one FinalizedArtifactsV1.mk, got {lines.length}:\n{hitsMk}"
  expect ((hitsMk.splitOn "EngineeringFinalizationV1.lean").length > 1)
    "sole mint must live in EngineeringFinalizationV1.lean"
  -- Sole finalizeMaterializedArtifactsV1 in Registry.
  let (ecFin, hitsFin) ← rg "^\\s*def finalizeMaterializedArtifactsV1\\b" #["ProofForgeV2"]
  expect (ecFin == 0) s!"finalizeMaterializedArtifactsV1 must exist:\n{hitsFin}"
  let finLines := (hitsFin.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (finLines.length == 1)
    s!"sole finalizeMaterializedArtifactsV1, got {finLines.length}:\n{hitsFin}"
  expect ((hitsFin.splitOn "Registry.lean").length > 1)
    "finalizeMaterializedArtifactsV1 must live in Registry.lean"
  -- LockedToolchainV1 present; no Core.Source import.
  let (ecSrc, hitsSrc) ← rg
    "^\\s*import ProofForgeV2\\.Core\\.Source\\b"
    #["ProofForgeV2/Materialization/LockedToolchainV1.lean"]
  expect (ecSrc == 1)
    s!"LockedToolchainV1 must not import Core.Source:\n{hitsSrc}"

private def assertFinalizationEnv (env : Environment) : Except String Unit := do
  let carrier := Name.mkStr2 "ProofForgeV2" "FinalizedArtifactsV1"
  unless env.contains carrier do
    throw "FinalizedArtifactsV1 missing from Environment"
  let mint := Name.mkStr2 "ProofForgeV2" "mintFinalizedArtifactsV1"
  unless env.contains mint do
    throw "mintFinalizedArtifactsV1 missing from Environment"
  -- Module namespace may not appear as a declaration; check resolve symbol.
  let resolveName := Name.mkStr4 "ProofForgeV2" "Materialization" "LockedToolchainV1" "resolve"
  unless env.contains resolveName do
    throw "LockedToolchainV1.resolve missing from Environment"
  -- Deleted CLI tool-runner symbols must be absent.
  let oldEnvTest := Name.mkStr4 "ProofForgeV2" "CLI" "Toolchain" "resolve"
  if env.contains oldEnvTest then
    throw s!"deleted CLI tool-runner resolve still present: {oldEnvTest}"
  pure ()

run_cmd do
  let env ← getEnv
  match assertFinalizationEnv env with
  | .ok () => pure ()
  | .error e => throwError e

unsafe def run : IO Unit := do
  testSoleMintBinding
  testPreIoBindBeforeTools
  let nearFinalized ← testNearFinalizerInputBinding
  testNearWasmBinaryEnvelope
  testNearWasmCertProviderBoundary
  testNearWasmCertProductActivationBoundary nearFinalized
  testNearWasmCertProviderWire
  testNearWasmCertArtifacts
  testNonDeployablePhases
  testFourTargetFinalization
  testToolFailureZeroPublish
  testNearToolFailureZeroPublish
  testCliAuthorityDeletion
  IO.println "Tests.Materialization.EngineeringFinalizationV1: ok"

end Tests.Materialization.EngineeringFinalizationV1
