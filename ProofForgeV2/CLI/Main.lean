import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.InlineProofCertifierV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Language.TheoremInventoryV1
import ProofForgeV2.Targets.BuildSelectionV1

namespace ProofForgeV2.CLI

open ProofForgeV2 System
open ProofForgeV2.Compiler.InlineProofCertifierV1
open ProofForgeV2.Compiler.InlineProofProtocolV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Language.TheoremInventoryV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Compiler

private def usage : String :=
  "ProofForge V2 alpha\n\n" ++
  "Usage:\n" ++
  "  proof-forge-next list-targets [--all] [--json]\n" ++
  "  proof-forge-next doctor [--json] [--target <id>]... [--with-runtime] [--all]\n" ++
  "  proof-forge-next inspect <target> [--json]\n" ++
  "  proof-forge-next inspect <output-dir> [--json]\n" ++
  "  proof-forge-next inspect --output-dir <dir> [--json]\n" ++
  "  proof-forge-next check <source.lean> --module <Lean.Name> [--root <dir>] [--program <Name>] [--target <target>] [--profile <id>] [--language-version <semver>] [--resource-limit <stage>.<field>=<n>]... [--json]\n" ++
  "  proof-forge-next build <source.lean> --module <Lean.Name> --target <target> [-o <dir>] [--program <Name>] [--root <dir>] [--profile <id>] [--language-version <semver>] [--minimum-evidence <grade>] [--resource-limit <stage>.<field>=<n>]... [--json]\n" ++
  "\n" ++
  "Notes:\n" ++
  "  --profile selects a registered codegen profile for the target (default profile when omitted).\n" ++
  "  --network is not supported (no network registry); it is a usage error.\n" ++
  "  --resource-limit is lower-only; check rejects external-tool/artifact-output; wall-ms and build artifact-output.published-bytes are enforced in-process (RES-1 / output-only RES-1B).\n" ++
  "  --minimum-evidence is build-only (specified|artifact_validated|local_runtime|network_or_proof_validated).\n" ++
  "  --json emits deterministic PF-JCS on stdout for list-targets/inspect/check/build;\n" ++
  "    doctor --json emits proof-forge.doctor.v1 (Tool Lock presence under PROOF_FORGE_TOOL_ROOT).\n" ++
  "  doctor requires scripts/proof_forge_doctor.py under the process working directory (repo root).\n" ++
  "  inspect <arg> prefers a registered target id when ambiguous; use --output-dir to force a path.\n" ++
  "  inspect output-dir validates proof-forge.output.v1 artifact-content + exact disk closure.\n" ++
  "  check validates without writing artifacts; build materializes under -o (default build/v2).\n"

/-- CLI usage/config failure: plain stderr and exit 2, not a diagnostic bundle. -/
private def failUsage (message : String) : IO α := do
  IO.eprintln message
  IO.Process.exit 2

/-- Product source/type/effect failure: full human bundle and catalog exit code. -/
private def failBundle (bundle : DiagnosticBundleV1) : IO α := do
  let text := DiagnosticBundleV1.renderHuman bundle
  unless text.isEmpty do
    IO.eprintln text
  let code := DiagnosticBundleV1.selectExitCode bundle
  let exitByte : UInt8 := if code ≥ 256 then 70 else UInt8.ofNat code
  IO.Process.exit exitByte

private def validateSourceArgument (source : String) : IO ProjectRelativePath := do
  unless source.endsWith ".lean" do
    failUsage "source path must end in .lean"
  match parseProjectRelativePath source with
  | .ok path => pure path
  | .error _ =>
      failUsage "source path must be a canonical project-relative path under --root"

/-- Resolve only the caller-selected trusted root lexically. Source lookup is
    performed by the in-process Loader under this root. -/
private def resolveProjectRoot (value : String) : IO FilePath := do
  if value.isEmpty || value.toList.any (· == '\x00') then
    failUsage "--root must be a nonempty filesystem path"
  let cwd ← IO.currentDir
  if value == "." then
    return cwd
  let input := FilePath.mk value
  if input.isAbsolute then
    if value == "/" then
      return input
    let tail := String.intercalate "/" ((value.splitOn "/").drop 1)
    match parseProjectRelativePath tail with
    | .error _ =>
        failUsage "absolute --root must use canonical non-dot path components"
    | .ok canonical =>
        let rendered ← match renderProjectRelativePath canonical with
          | .ok rendered => pure rendered
          | .error _ => failUsage "absolute --root is not canonical"
        return FilePath.mk ("/" ++ rendered)
  match parseProjectRelativePath value with
  | .error _ =>
      failUsage "relative --root must be a canonical project-relative path or ."
  | .ok canonical =>
      let rendered ← match renderProjectRelativePath canonical with
        | .ok rendered => pure rendered
        | .error _ => failUsage "relative --root is not canonical"
      pure (cwd / FilePath.mk rendered)

private def sourceStartOrigin (sourcePath : ProjectRelativePath) : DiagnosticOriginV1 := {
  sourcePath
  startByte := 0
  endByte := 0
  nodeId := none
}

private def failFrontendDiagnostic
    (sourcePath : ProjectRelativePath)
    (code : DiagnosticCodeV1)
    (message expected actual stableClass : String) : IO α := do
  let diagnostic := DiagnosticV1.make code message
    (primary := some (sourceStartOrigin sourcePath))
    (expected := some (PfJson.string expected))
    (actual := some (PfJson.string actual))
    (stableContext := some stableClass)
  failBundle (mkFailureBundleV1 #[diagnostic])

/-- Sole CLI source authority: one in-process `IO.FS.readFile` under the
    resolved project root, then a single Loader snapshot that yields
    ValidatedSourceV1 + OriginInventoryV1 + opaque TheoremInventoryV1.
    Returns the same raw String held for the inline certifier (no second
    read, no worker/supervisor). -/
private unsafe def loadSourceProduct
    (projectRoot : FilePath)
    (sourcePath : ProjectRelativePath)
    (moduleSelector : String)
    (programSelector : Option String) :
    IO (ProductParserSessionV1 × String × ValidatedSourceV1 ×
      OriginInventoryV1 × TheoremInventoryV1) := do
  let logicalPath ← match renderProjectRelativePath sourcePath with
    | .ok path => pure path
    | .error _ => failUsage "source path is not canonical"
  let sourceFile := projectRoot / FilePath.mk logicalPath
  let rawSource ← IO.FS.readFile sourceFile
  let productSession ← ProductParserSessionV1.create
  match ← productSession.selectProgramV1ProductWithTheoremInventory
      rawSource logicalPath moduleSelector programSelector with
  | .error bundle => failBundle bundle
  | .ok (source, origins, theorems) =>
      pure (productSession, rawSource, source, origins, theorems)

/-- Stable phase tag for product PF-SRC-INVALID proof failures. -/
private def inlineProofPhaseTagV1 : InlineProofFailurePhaseV1 → String
  | .request => "request"
  | .policy => "policy"
  | .subject => "subject"
  | .obligation => "obligation"
  | .certification => "certification"
  | .internal => "internal"

/-- Stable detail tag for product PF-SRC-INVALID proof failures. -/
private def inlineProofDetailTagV1 : InlineProofCertifierDetailV1 → String
  | .subjectBuild => "subjectBuild"
  | .obligationMap => "obligationMap"
  | .requestBuild => "requestBuild"
  | .elaborate => "elaborate"
  | .subjectBytes => "subjectBytes"
  | .missingSubjectDecl => "missingSubjectDecl"
  | .missingTheorem => "missingTheorem"
  | .missingExpectedType => "missingExpectedType"
  | .audit => "audit"
  | .successMint => "successMint"
  | .internal => "internal"

/-- Product inline-proof failure: structured PF-SRC-INVALID / catalog exit 3.
    Never materializes, never resolves targets after this boundary. -/
private def failInlineProofV1
    (sourcePath : ProjectRelativePath)
    (phase : InlineProofFailurePhaseV1)
    (detail : InlineProofCertifierDetailV1) : IO α := do
  let diagnostic := DiagnosticV1.make .sourceInvalid
    s!"inline proof certification failed: phase={inlineProofPhaseTagV1 phase} detail={inlineProofDetailTagV1 detail}"
    (primary := some (sourceStartOrigin sourcePath))
    (expected := some (PfJson.string "certified-or-not-required"))
    (actual := some (PfJson.string
      s!"failed:{inlineProofPhaseTagV1 phase}:{inlineProofDetailTagV1 detail}"))
    (stableContext := some "inline-proof-certifier")
  failBundle (mkFailureBundleV1 #[diagnostic])

/-- Run the product inline certifier on the held raw source + compile carrier.
    `.failed` → stable PF-SRC-INVALID exit 3.
    `.noProof` → explicit ProductProofStatusV1.notRequired (never forged certified).
    `.certified` → accepts only the private CertifiedInlineProofV1 capability. -/
private unsafe def certifyProductInlineProofV1
    (productSession : ProductParserSessionV1)
    (rawSource : String)
    (sourceProgram : ValidatedSourceV1)
    (origins : OriginInventoryV1)
    (theorems : TheoremInventoryV1)
    (compiled : CompiledSemanticV1)
    (sourcePath : ProjectRelativePath)
    (moduleSelector : String)
    (programSelector : Option String) :
    IO ProductProofStatusV1 := do
  let outcome ← certifyInlineProofV1
    productSession rawSource sourceProgram origins theorems compiled
    sourcePath moduleSelector programSelector
  match outcome with
  | .failed phase detail => failInlineProofV1 sourcePath phase detail
  | .noProof => pure ProductProofStatusV1.notRequired
  | .certified certified =>
      pure (ProductProofStatusV1.certified
        (CertifiedInlineProofV1.theoremCount certified)
        (CertifiedInlineProofV1.proofCertificationDigest certified))

private def liftCompileResult (result : Except CompileError α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def resolveLanguageVersionForCli (requested : Option String) : IO SemVer :=
  match resolveLanguageParserDescriptorV1 requested with
  | .ok descriptor => pure (LanguageParserDescriptorV1.version descriptor)
  | .error diagnostic => failBundle (mkFailureBundleV1 #[diagnostic])

/-- Build argv selection. An ID absent from the frozen target catalog is a
usage/config error; registered design-only targets and profile-selection
failures remain typed product-selection errors. `--profile` selects a
registered profile for the target via `resolveBuildSelectionV1`. -/
private def resolveBuildSelectionForCli (options : BuildOptions) : IO ResolvedBuildSelectionV1 := do
  let target ← match options.target with
    | some target => pure target
    | none => failUsage "--target is required"
  match resolveBuildSelectionV1 target options.profile with
  | .ok selection => pure selection
  | .error (.unknownTarget input) => failUsage s!"unknown target '{input}'"
  | .error error => throw <| IO.userError error.render

/-- Optional selection for `check`: target may be omitted; profile requires target. -/
private def resolveOptionalSelectionForCheck
    (options : BuildOptions) : IO (Option ResolvedBuildSelectionV1) := do
  match options.target with
  | none =>
      if options.profile.isSome then
        failUsage "--profile requires --target"
      pure none
  | some target =>
      match resolveBuildSelectionV1 target options.profile with
      | .ok selection => pure (some selection)
      | .error (.unknownTarget input) => failUsage s!"unknown target '{input}'"
      | .error error => throw <| IO.userError error.render

/-- RES-1: product wall fail-closed (exit 6, PF-RESOURCE-TIME). -/
private def failResourceTime (message : String) : IO α := do
  IO.eprintln message
  IO.Process.exit 6

/-- RES-1B output-only slice: the publisher has already removed staging;
    classify the stable resource error at the CLI boundary as exit 6. -/
private def failResourceOutput (message : String) : IO α := do
  IO.eprintln message
  IO.Process.exit 6

/-- RES-1: enforce any configured stage.wall-ms overrides against elapsed mono ms. -/
private def enforceWallBudgetV1
    (options : BuildOptions) (startedMs : Nat) : IO Unit := do
  let now ← IO.monoMsNow
  let elapsedNat := now - startedMs
  let elapsed := UInt64.ofNat elapsedNat
  match enforceAllWallMsLimitsV1 options.resourceLimits elapsed with
  | .ok () => pure ()
  | .error msg => failResourceTime msg

private unsafe def buildSource (options : BuildOptions) : IO Unit := do
  -- RES-1: wall budget covers load → compile → inline cert → materialize.
  let startedMs ← IO.monoMsNow
  -- Argv / required-field checks only. Target registry resolve is deferred
  -- until after the inline certifier so proof failure wins over unknown target
  -- and never reaches materialize/staging.
  if options.target.isNone then
    failUsage "--target is required"
  let _languageVersion ← resolveLanguageVersionForCli options.languageVersion
  let source ← match options.source with
    | some source => pure source
    | none => failUsage "source file is required"
  let moduleName ← match options.moduleName with
    | some moduleName => pure moduleName
    | none => failUsage "--module is required for canonical ProgramV1 identity"
  let sourcePath ← validateSourceArgument source
  let root ← resolveProjectRoot (options.root.getD ".")
  let (productSession, rawSource, sourceProgram, origins, theorems) ←
    loadSourceProduct root sourcePath moduleName options.programName
  match Compiler.compileProgramProductV1 sourceProgram origins with
  | .error bundle => failBundle bundle
  | .ok compiled =>
      -- Inline certifier owns product proof gating (private capability only).
      -- Structural ambient ProofBundle join remains deleted.
      let _proofStatus ← certifyProductInlineProofV1
        productSession rawSource sourceProgram origins theorems compiled
        sourcePath moduleName options.programName
      let selection ← resolveBuildSelectionForCli options
      -- Product phase: capability → emit/finalize/disk closure.
      -- Selected codegen profile is bound by selection and flows into the
      -- capability / OutputSet `codegenProfile` field.
      let capability ← liftCompileResult
        (Targets.resolveEngineeringRequirementsV1 selection compiled)
      let requestedOutput := FilePath.mk (options.output.getD "build/v2")
      let outputPath :=
        if requestedOutput.isAbsolute then requestedOutput else root / requestedOutput
      -- RES-1 wall is enforced inside emitProgram immediately before rename so
      -- over-budget cleans staging and never publishes; check keeps post-success
      -- enforcement below. published-bytes still gates pre-sidecar-write.
      let receipt ←
        try
          emitProgram capability outputPath options.resourceLimits (some startedMs)
        catch
        | .userError msg =>
            if msg.startsWith "PF-RESOURCE-OUTPUT:" then
              failResourceOutput msg
            else if msg.startsWith "PF-RESOURCE-TIME:" then
              failResourceTime msg
            else
              throw <| IO.userError msg
        | error => throw error
      if options.json then
        IO.println (← liftCompileResult
          (renderBuildOkJsonV1 receipt options.resourceLimits options.minimumEvidence))
      else
        IO.println (renderBuildOkHumanV1 receipt)

/-- Product validation without materialization. Same source authority as build.
Optional `--target`/`--profile` also resolve the engineering requirement
capability (fail closed) without writing artifacts. Inline certifier runs
after compile and before any TargetRegistry resolve. -/
private unsafe def checkSource (options : BuildOptions) : IO Unit := do
  if options.output.isSome then
    failUsage "check does not write artifacts; omit -o/--output"
  -- RES-1: wall budget covers load → compile → cert → optional resolve.
  let startedMs ← IO.monoMsNow
  -- Profile-without-target is pure argv; registry resolve stays post-certifier.
  if options.target.isNone && options.profile.isSome then
    failUsage "--profile requires --target"
  let _languageVersion ← resolveLanguageVersionForCli options.languageVersion
  let source ← match options.source with
    | some source => pure source
    | none => failUsage "source file is required"
  let moduleName ← match options.moduleName with
    | some moduleName => pure moduleName
    | none => failUsage "--module is required for canonical ProgramV1 identity"
  let sourcePath ← validateSourceArgument source
  let root ← resolveProjectRoot (options.root.getD ".")
  let (productSession, rawSource, sourceProgram, origins, theorems) ←
    loadSourceProduct root sourcePath moduleName options.programName
  match Compiler.compileProgramProductV1 sourceProgram origins with
  | .error bundle => failBundle bundle
  | .ok compiled =>
      let proofStatus ← certifyProductInlineProofV1
        productSession rawSource sourceProgram origins theorems compiled
        sourcePath moduleName options.programName
      let selection? ← resolveOptionalSelectionForCheck options
      let target? := selection?.map ResolvedBuildSelectionV1.targetIdOf
      let profile? := selection?.map ResolvedBuildSelectionV1.codegenProfileOf
      match selection? with
      | some selection =>
          let _capability ← liftCompileResult
            (Targets.resolveEngineeringRequirementsV1 selection compiled)
          pure ()
      | none => pure ()
      enforceWallBudgetV1 options startedMs
      let programName := CompiledSemanticV1.artifactProgramNameOf compiled
      let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
      let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
      if options.json then
        IO.println (← liftCompileResult
          (renderCheckOkJsonV1 programName sourceDigest semanticDigest target? profile?
            options.resourceLimits proofStatus))
      else
        IO.println (← liftCompileResult
          (renderCheckOkHumanV1 programName sourceDigest semanticDigest target? profile?
            proofStatus))

private def listTargets (options : ListTargetsOptions) : IO Unit := do
  if options.json then
    IO.println (← liftCompileResult (listTargetsJson options.includeDesignOnly))
  else
    let lines ← liftCompileResult (listTargetLines options.includeDesignOnly)
    for line in lines do
      IO.println line

/-- Product doctor: thin CLI wrapper over package-owned
    `scripts/proof_forge_doctor.py` (Tool Lock presence; no PATH fallback).
    Requires the process CWD to be the repo root so the script is discoverable.
    Exit codes are forwarded from the engine (0 all-ok, 3 missing/partial/mismatch,
    2 usage, 1 internal). -/
private def runDoctor (options : DoctorOptions) : IO Unit := do
  let cwd ← IO.currentDir
  let script := cwd / "scripts" / "proof_forge_doctor.py"
  unless ← script.pathExists do
    failUsage
      "doctor requires scripts/proof_forge_doctor.py under the current working directory (run from repo root)"
  let mut args : Array String := #["-I", "-S", script.toString]
  if options.json then
    args := args.push "--json"
  if options.withRuntime then
    args := args.push "--with-runtime"
  if options.includeDesignOnly then
    args := args.push "--all"
  for target in options.targets do
    args := args.push "--target"
    args := args.push target
  let output ← IO.Process.output {
    cmd := "/usr/bin/python3"
    args
  }
  unless output.stdout.isEmpty do
    (← IO.getStdout).putStr output.stdout
  unless output.stderr.isEmpty do
    (← IO.getStderr).putStr output.stderr
  if output.exitCode == 0 then
    pure ()
  else
    let codeNat := output.exitCode.toNat
    let exitByte : UInt8 := if codeNat ≥ 256 then 70 else UInt8.ofNat codeNat
    IO.Process.exit exitByte

private def inspectTarget (value : String) (json : Bool) : IO Unit := do
  IO.println (← liftCompileResult (inspectTargetText value json))

/-- Product failure for inspect-output: plain `PF-OUTPUT-MANIFEST:` line + emit-phase
    exit 6 (same priority band as DiagnosticCodeV1 emit codes). Not a full
    DiagnosticBundle (no source origin); keeps the historical emit wire prefix. -/
private def failOutputManifest (message : String) : IO α := do
  IO.eprintln s!"PF-OUTPUT-MANIFEST: {message}"
  IO.Process.exit 6

private def pathType? (path : FilePath) : IO (Option IO.FS.FileType) :=
  try
    return some (← path.symlinkMetadata).type
  catch _ =>
    return none

/-- Read and strictly validate an engineering build output directory.

    Stable-reads sidecars via ArtifactContentV1, parses proof-forge.output.v1
    with content descriptors + evidenceSha256, sole-scan exact disk closure,
    exact inventory compare, evidence digest/identity, outputSetDigest recompute.
    Does not forge FinalizedArtifactsV1. Engineering only. -/
private def inspectOutputDir (dir : String) (json : Bool) : IO Unit := do
  if dir.isEmpty then
    failUsage "inspect output directory path must be nonempty"
  let outputPath := FilePath.mk dir
  match ← pathType? outputPath with
  | none =>
      failOutputManifest s!"output directory does not exist: {dir}"
  | some .symlink =>
      failOutputManifest s!"output directory cannot be a symbolic link: {dir}"
  | some .dir => pure ()
  | some _ =>
      failOutputManifest s!"output path is not a directory: {dir}"
  let manifest ← try
    inspectEngineeringOutputDirV1 outputPath
  catch e =>
    let msg := toString e
    -- Strip optional "Error: " / userError wrappers for stable PF-OUTPUT-MANIFEST.
    let cleaned :=
      if msg.startsWith "Error: " then (msg.drop 7).toString else msg
    failOutputManifest cleaned
  if json then
    IO.println (← liftCompileResult (renderInspectOutputJsonV1 dir manifest))
  else
    IO.println (renderInspectOutputHumanV1 dir manifest)

/-- Product CLI entry. Sole dispatcher: `parseProductCliCommandV1` =
seed-first preflight (`parseCliCommandWithSeedV1` on frozen seed) then
`parseCliCommandV1`. Does not mint selection capability; bodies bind seed again.
Positional `inspect <arg>` prefers a registered TargetId; otherwise treats
`<arg>` as an output directory. Explicit `--output-dir` always selects
output-dir mode. -/
unsafe def run (args : List String) : IO Unit := do
  match parseProductCliCommandV1 args with
  | .error msg => failUsage msg
  | .ok command =>
      match command with
      | .listTargets options => listTargets options
      | .doctor options => runDoctor options
      | .inspect arg json =>
          if isRegisteredInspectTargetV1 arg then
            inspectTarget arg json
          else
            inspectOutputDir arg json
      | .inspectOutput dir json => inspectOutputDir dir json
      | .check options => checkSource options
      | .build options => buildSource options
      | .usage => failUsage usage

end ProofForgeV2.CLI

-- Top-level `main` lives in `ProofForgeV2.CLI.Exe` (lean_exe root) so this
-- module can be imported by library/tests without colliding with test mains.
