/-
  D3/S7a engineering MaterializedArtifactsV1 carrier tests.

  Real product path only:
    compileValidatedSourceV1 → resolveBuildSelectionV1 →
    resolveEngineeringRequirementsV1 → materializeResult / emitProgram

  Not formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity / SupportClaim.
  No forged private-ctor carriers; no reimplemented on-disk renderer.
-/
import ProofForgeV2
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.CLI.Emit
import ProofForgeV2.CLI.Main
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.WireV1
import Tests.Language.ParserSession
import Lean
import Lean.Elab.Command

namespace Tests.Materialization.OutputEnvelopeV1

open ProofForgeV2
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.BuildSelectionV1
open System
open Lean
open Lean.Elab.Command

private def dummyPlanDigestV1 : IO Digest := do
  match engineeringAbsentPlanDigestV1
      TargetId.evm CodegenProfileId.evmYulSolc0834V1 with
  | .ok d => pure d
  | .error e => throw <| IO.userError s!"dummy plan digest: {e}"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def materializeOk (label : String) (capability : Targets.ResolvedEngineeringBuildV1) :
    IO MaterializedArtifactsV1 :=
  liftResult label (Targets.materializeResult capability)

private unsafe def compileCounter : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<output-envelope-counter>"
    Examples.counterModuleNameV1 none)
  liftResult "compile Counter" (Compiler.compileValidatedSourceV1 source)

/-- Canonical Counter ordered artifact paths per TargetId (carrier contract). -/
private def expectedCounterPaths (tid : TargetId) : Array String :=
  if tid == TargetId.evm then
    #["Counter.yul", "Counter.abi.json"]
  else if tid == TargetId.solana then
    #["Counter.sbpf-plan", "Counter.idl.json"]
  else if tid == TargetId.near then
    #["Counter.wat", "Counter.near-abi.json"]
  else if tid == TargetId.noir then
    #[
      "Counter.noir-relations.json",
      "relations/r0-init/src/main.nr",
      "relations/r0-init/Nargo.toml",
      "relations/r1-increment/src/main.nr",
      "relations/r1-increment/Nargo.toml",
      "relations/r2-get/src/main.nr",
      "relations/r2-get/Nargo.toml"
    ]
  else
    #[]

/-- Four targets: exact capability binding, canonical compiled identity,
    exact ordered artifact path names, deterministic bytes, no partial carrier. -/
private unsafe def testFourTargetCarrierBinding : IO Unit := do
  let compiled ← compileCounter
  let artifactName := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  let recomputedSemantic ← match semanticHashV1 (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok digest => pure digest
    | .error error => throw <| IO.userError s!"semanticHashV1 failed: {repr error}"
  expect (recomputedSemantic == semanticDigest)
    "compiled semantic digest must be the retained SemanticProgramV1 hash"
  for tid in #[TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let selection ← liftResult s!"select {tid}" (resolveBuildSelectionV1 tid none)
    let capability ← liftResult s!"resolve {tid}"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    expect (Targets.ResolvedEngineeringBuildV1.targetIdOf capability == tid)
      s!"capability target {tid}"
    expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf capability ==
        selection.codegenProfile)
      s!"capability profile {tid}"
    expect (Targets.ResolvedEngineeringBuildV1.kindOf capability == selection.kind)
      s!"capability kind {tid}"
    let a ← materializeOk s!"materialize {tid}" capability
    let b ← materializeOk s!"materialize {tid} again" capability
    -- Determinism + no partial / rebuild drift.
    expect (a == b) s!"{tid} materialize must be deterministic"
    expect (MaterializedArtifactsV1.targetIdOf a == tid)
      s!"{tid} carrier targetId"
    expect (MaterializedArtifactsV1.codegenProfileIdOf a == selection.codegenProfile)
      s!"{tid} carrier profile"
    expect (MaterializedArtifactsV1.kindOf a == selection.kind)
      s!"{tid} carrier kind"
    expect (MaterializedArtifactsV1.artifactProgramNameOf a == artifactName)
      s!"{tid} semantic-derived artifact program name"
    expect (MaterializedArtifactsV1.sourceDigestOf a == sourceDigest)
      s!"{tid} canonical ProgramV1 source digest"
    expect (MaterializedArtifactsV1.semanticDigestOf a == semanticDigest)
      s!"{tid} retained SemanticProgramV1 digest"
    match renderDigest (MaterializedArtifactsV1.sourceDigestOf a) with
    | .ok wire =>
        expect (wire.startsWith "sha256:")
          s!"{tid} source digest wire"
    | .error error => throw <| IO.userError s!"{tid} renderDigest: {error}"
    let files := MaterializedArtifactsV1.filesOf a
    expect (!files.isEmpty) s!"{tid} must emit ≥1 artifact"
    let expected := expectedCounterPaths tid
    expect (!expected.isEmpty) s!"{tid} must have expected Counter path pin"
    expect (files.map (·.path) == expected)
      s!"{tid} exact Counter path order/names:\n  got {files.map (·.path)}\n  want {expected}"
    -- Path safety via sole package helper + uniqueness.
    let mut paths : Array String := #[]
    for f in files do
      expect (safeRelativeArtifactPathV1 f.path)
        s!"{tid} path must pass safeRelativeArtifactPathV1: {f.path}"
      expect (!paths.contains f.path) s!"{tid} no duplicate path {f.path}"
      paths := paths.push f.path
    -- Deterministic path order + content bytes across two mints.
    expect (files.map (·.path) == (MaterializedArtifactsV1.filesOf b).map (·.path))
      s!"{tid} deterministic path order"
    expect (files.map (·.contents) == (MaterializedArtifactsV1.filesOf b).map (·.contents))
      s!"{tid} deterministic file bytes"

/-- Emit path: capability-only, receipt fields, exact on-disk proof-forge.output.v1 + evidence. -/
private unsafe def testEmitReceiptAndDiskManifest : IO Unit := do
  let compiled ← compileCounter
  let sourceHash ← liftResult "derive source hash"
    (CompiledSemanticV1.artifactSourceHashHexOf compiled)
  let semanticHash ← liftResult "derive semantic hash"
    (CompiledSemanticV1.artifactSemanticHashHexOf compiled)
  let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
  let capability ← liftResult "resolve solana"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let carrier ← materializeOk "materialize solana" capability
  let carrierPaths := (MaterializedArtifactsV1.filesOf carrier).map (·.path)
  expect (carrierPaths == #["Counter.sbpf-plan", "Counter.idl.json"])
    "solana carrier paths for golden manifest"
  let outDir := FilePath.mk "build/v2/output-envelope-solana"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
  expect (receipt.target == TargetId.solana) "emit receipt target"
  expect (receipt.codegenProfile == CodegenProfileId.solanaSbpfPlanV1)
    "emit receipt profile"
  expect (receipt.deployable == false) "solana plan-only is non-deployable"
  -- Recompute engineering OutputSet from product finalize (solana plan: no extras).
  let stagingScratch := FilePath.mk "build/v2/output-envelope-solana-scratch"
  if ← stagingScratch.pathExists then IO.FS.removeDirAll stagingScratch
  IO.FS.createDirAll stagingScratch
  for file in MaterializedArtifactsV1.filesOf carrier do
    IO.FS.writeFile (stagingScratch / file.path) file.contents
  let finalized ← Targets.finalizeMaterializedArtifactsV1 capability carrier stagingScratch
  let inv ← scanEngineeringArtifactContentOnlyV1 finalized stagingScratch
  let outputSet ← liftResult "mint output set" (mintEngineeringOutputSetV1 finalized inv)
  let expectedManifest ← match renderEngineeringOutputSetManifestV1 outputSet with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"render manifest: {e}"
  let expectedEvidence ← match renderEngineeringOutputSetEvidenceV1 outputSet with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"render evidence: {e}"
  let json ← IO.FS.readFile (outDir / "manifest.json")
  expect (json == expectedManifest)
    s!"exact proof-forge.output.v1 manifest byte identity:\n---got---\n{json}\n---want---\n{expectedManifest}"
  expect ((json.splitOn "\"schemaVersion\": \"proof-forge.output.v1\"").length > 1)
    "on-disk schemaVersion proof-forge.output.v1"
  expect ((json.splitOn "\"path\": \"Counter.sbpf-plan\"").length > 1)
    "on-disk files include Counter.sbpf-plan descriptor"
  expect ((json.splitOn "\"path\": \"Counter.idl.json\"").length > 1)
    "on-disk files include Counter.idl.json descriptor"
  expect ((json.splitOn "\"role\": \"materialized-base\"").length > 1)
    "on-disk files carry materialized-base role"
  expect ((json.splitOn "\"contentSha256\":").length > 1)
    "on-disk files carry contentSha256"
  expect ((json.splitOn "\"evidenceSha256\":").length > 1)
    "on-disk evidenceSha256 present"
  expect ((json.splitOn "\"deployable\": false").length > 1)
    "on-disk deployable false"
  expect ((json.splitOn "\"artifactProgramName\": \"Counter\"").length > 1)
    "on-disk artifactProgramName"
  expect ((json.splitOn "\"buildIdentityDigest\":").length > 1)
    "on-disk buildIdentityDigest present"
  expect ((json.splitOn "\"planDigest\":").length > 1)
    "on-disk planDigest present"
  expect ((json.splitOn "\"outputSetDigest\":").length > 1)
    "on-disk outputSetDigest present"
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (evidence == expectedEvidence)
    s!"exact evidence.json byte identity:\n---got---\n{evidence}\n---want---\n{expectedEvidence}"
  -- Evidence still carries source/semantic hex for tool-note continuity.
  expect ((evidence.splitOn s!"\"sourceHash\": \"{sourceHash}\"").length > 1)
    "evidence sourceHash"
  expect ((evidence.splitOn s!"\"semanticHash\": \"{semanticHash}\"").length > 1)
    "evidence semanticHash"
  if ← stagingScratch.pathExists then IO.FS.removeDirAll stagingScratch

/-- Mint helpers that take capability+files reject unsafe/duplicate/empty paths
    without returning a partial carrier (package-visible mint). -/
private unsafe def testMintPathNegatives : IO Unit := do
  let compiled ← compileCounter
  let selection ← liftResult "select evm" (resolveBuildSelectionV1 TargetId.evm none)
  let capability ← liftResult "resolve evm"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let ok ← materializeOk "baseline" capability
  let goodFiles := MaterializedArtifactsV1.filesOf ok
  expect (!goodFiles.isEmpty) "baseline files nonempty"
  -- Sole package path helper mirrors mint rejection set (shared with CLI).
  expect (safeRelativeArtifactPathV1 "Counter.yul") "safe path accepted by helper"
  expect (!safeRelativeArtifactPathV1 "") "helper rejects empty"
  expect (!safeRelativeArtifactPathV1 "foo/./bar") "helper rejects '.' component"
  expect (!safeRelativeArtifactPathV1 "a\u0000b") "helper rejects null"
  expect (!safeRelativeArtifactPathV1 "a\nb") "helper rejects LF"
  expect (!safeRelativeArtifactPathV1 "a\rb") "helper rejects CR"
  expect (!safeRelativeArtifactPathV1 ("x".pushn 'y' 240)) "helper rejects >240 UTF-8"
  match Targets.descriptorForKind? .evm with
  | none => throw <| IO.userError "missing EVM descriptor"
  | some desc =>
      let reject (label path : String) : IO Unit := do
        let file : OutputFile := {
          path := path
          mediaType := "text/plain"
          contents := "x"
        }
        match mintMaterializedArtifactsV1 capability desc #[file] (← dummyPlanDigestV1) with
        | .error e =>
            expect (e.code == "PF-SRC-INVALID")
              s!"{label} → invalidProgram (got {e.code})"
        | .ok _ => throw <| IO.userError s!"{label} must not mint"
      -- Empty files → fail closed, no carrier.
      match mintMaterializedArtifactsV1 capability desc #[] (← dummyPlanDigestV1) with
      | .error e =>
          expect (e.code == "PF-SRC-INVALID") "empty files → invalidProgram"
      | .ok _ => throw <| IO.userError "empty files must not mint"
      -- Absolute / parent / empty / '.' / null / CR / LF / length>240.
      reject "absolute path" "/tmp/evil.yul"
      reject "parent path" "../escape.yul"
      reject "empty path string" ""
      reject "dot component" "foo/./bar"
      reject "null byte" "a\u0000b"
      reject "newline LF" "a\nb"
      reject "carriage return" "a\rb"
      reject "utf8 length 241" ("x".pushn 'y' 240)
      -- Duplicate path.
      let f0 := goodFiles[0]!
      match mintMaterializedArtifactsV1 capability desc #[f0, f0] (← dummyPlanDigestV1) with
      | .error e =>
          expect (e.code == "PF-SRC-INVALID") "duplicate path → invalidProgram"
      | .ok _ => throw <| IO.userError "duplicate path must not mint"
      -- Descriptor target drift vs capability.
      let drifted := { desc with targetId := TargetId.solana }
      match mintMaterializedArtifactsV1 capability drifted goodFiles (← dummyPlanDigestV1) with
      | .error e =>
          expect (e.code == "PF-REGISTRY-INVALID") "target drift → registryInvalid"
      | .ok _ => throw <| IO.userError "descriptor target drift must not mint"
      -- Descriptor profile drift.
      let profileDrift := {
        desc with codegenProfile := CodegenProfileId.solanaSbpfPlanV1
      }
      match mintMaterializedArtifactsV1 capability profileDrift goodFiles (← dummyPlanDigestV1) with
      | .error e =>
          expect (e.code == "PF-REGISTRY-INVALID") "profile drift → registryInvalid"
      | .ok _ => throw <| IO.userError "descriptor profile drift must not mint"

/-- Source-level deletion / sole-mint pins (rg via IO). -/
private unsafe def testDeletionPins : IO Unit := do
  let rg (pat : String) (paths : Array String) : IO (UInt32 × String) := do
    let args := #["--glob", "*.lean", "-n", "--no-heading", pat] ++ paths
    let out ← IO.Process.output { cmd := "rg", args }
    pure (out.exitCode, out.stdout)
  -- Forbidden public product surfaces under ProofForgeV2 (definition forms).
  for pat in #[
      "^\\s*structure OutputSet\\b",
      "^\\s*structure OutputManifest\\b",
      "^\\s*def makeOutput\\b",
      "^\\s*def manifestJson\\b",
      "^\\s*def validateOutputSet\\b"
    ] do
    let (ec, hits) ← rg pat #["ProofForgeV2"]
    expect (ec == 1) s!"deletion: forbidden def still present for {pat}:\n{hits}"
  -- Sole mint site for MaterializedArtifactsV1.mk
  let (ecMk, hitsMk) ← rg "MaterializedArtifactsV1\\.mk" #["ProofForgeV2"]
  expect (ecMk == 0) s!"sole mint: expected MaterializedArtifactsV1.mk hits:\n{hitsMk}"
  let lines := (hitsMk.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (lines.length == 1)
    s!"sole mint: expected exactly one MaterializedArtifactsV1.mk, got {lines.length}:\n{hitsMk}"
  expect ((hitsMk.splitOn "MaterializedArtifactsV1.lean").length > 1)
    "sole mint must live in MaterializedArtifactsV1.lean"
  -- Sole path-safety definition (CLI must not reimplement body).
  let (ecPath, hitsPath) ← rg "^\\s*def safeRelativeArtifactPathV1\\b" #["ProofForgeV2"]
  expect (ecPath == 0)
    s!"safeRelativeArtifactPathV1 must be defined once:\n{hitsPath}"
  let pathLines := (hitsPath.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (pathLines.length == 1)
    s!"safeRelativeArtifactPathV1 sole def, got {pathLines.length}:\n{hitsPath}"
  expect ((hitsPath.splitOn "MaterializedArtifactsV1.lean").length > 1)
    "safeRelativeArtifactPathV1 must live in MaterializedArtifactsV1.lean"
  -- CLI must not re-define the path body (only thin wrapper allowed).
  let (ecCliBody, hitsCliBody) ← rg
    "path\\.components\\.contains" #["ProofForgeV2/CLI"]
  expect (ecCliBody == 1)
    s!"CLI must not reimplement path-safety body:\n{hitsCliBody}"
  -- materializeResult returns MaterializedArtifactsV1 (signature may span lines).
  let matOut ← IO.Process.output {
    cmd := "rg"
    args := #["--glob", "*.lean", "-n", "--no-heading", "-A", "2",
      "def materializeResult", "ProofForgeV2/Targets"]
  }
  expect (matOut.exitCode == 0)
    s!"materializeResult def must exist:\n{matOut.stdout}"
  expect ((matOut.stdout.splitOn "MaterializedArtifactsV1").length > 1)
    s!"materializeResult must return MaterializedArtifactsV1:\n{matOut.stdout}"

/-- Environment reflection: deleted public symbols must be absent; carrier present. -/
private def assertNoPublicOldCarrier (env : Environment) : Except String Unit := do
  -- Name.mkStr2 / str chains avoid `` for deleted identifiers.
  let forbidden : Array Name := #[
    Name.mkStr2 "ProofForgeV2" "OutputSet",
    Name.mkStr2 "ProofForgeV2" "OutputManifest",
    Name.mkStr3 "ProofForgeV2" "Targets" "makeOutput",
    Name.mkStr3 "ProofForgeV2" "Targets" "manifestJson"
  ]
  for n in forbidden do
    if env.contains n then
      throw s!"deleted product symbol still present in Environment: {n}"
  -- New carrier type must exist.
  let carrier := Name.mkStr2 "ProofForgeV2" "MaterializedArtifactsV1"
  unless env.contains carrier do
    throw "MaterializedArtifactsV1 missing from Environment"
  -- Shared path helper must exist (sole package definition).
  let pathHelper := Name.mkStr2 "ProofForgeV2" "safeRelativeArtifactPathV1"
  unless env.contains pathHelper do
    throw "safeRelativeArtifactPathV1 missing from Environment"
  pure ()

run_cmd do
  let env ← getEnv
  match assertNoPublicOldCarrier env with
  | .ok () => pure ()
  | .error e => throwError e

unsafe def run : IO Unit := do
  testFourTargetCarrierBinding
  testEmitReceiptAndDiskManifest
  testMintPathNegatives
  testDeletionPins
  IO.println "Tests.Materialization.OutputEnvelopeV1: ok"

end Tests.Materialization.OutputEnvelopeV1
