import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Solana.FinalizeV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

/-!
# Tests.Targets.SolanaElfV1 — S2a solana-sbpf-elf-v1 profile

Pins:
* registry membership of `solana-sbpf-elf-v1` with default still plan-v1
* requirement-support row for the elf profile
* residual descriptor stays plan-v1 but accepts elf via acceptsCodegenProfile
* buildFromCapability under elf emits `.s` + plan + IDL; plan profile unchanged
* `.s` contents match `emitSbpfAsmV1` and are deterministic
* FinalizeV1 plan profile stays zero-tool
* FinalizeV1 elf pure helpers + missing-tool path (`PF-TOOLCHAIN-MISSING` via empty PROOF_FORGE_TOOL_ROOT)
* empty-.so gate without invoking the real assembler

S2b registers locked `sbpf` (sourceBuild). Missing-tool coverage forces an empty tool root
so the suite stays hermetic without a provisioned binary. Positive e2e `.so` emission is a
manual/CI provision+materialize path, not this suite.
-/

namespace Tests.Targets.SolanaElfV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.Solana
open ProofForgeV2.Materialization.LockedToolchainV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def expectIoErrorContains (label expected : String) (action : IO Unit) : IO Unit := do
  try
    action
    throw <| IO.userError s!"{label}: expected error containing '{expected}'"
  catch e =>
    let msg := toString e
    unless msg.contains expected do
      throw <| IO.userError s!"{label}: expected '{expected}' in:\n{msg}"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def solanaCapability
    (compiled : CompiledSemanticV1) (profile? : Option CodegenProfileId) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.solana profile?
  Targets.resolveEngineeringRequirementsV1 selection compiled

/-- Registry: elf profile is a member; default remains plan; not reserved. -/
private def testRegistryMembership : IO Unit := do
  let reg ← liftResult <| registration? TargetId.solana
  let reg ← match reg with
    | some r => pure r
    | none => throw <| IO.userError "solana registration missing"
  expect (reg.profiles.any (· == CodegenProfileId.solanaSbpfElfV1))
    "registry: solana profiles include solana-sbpf-elf-v1"
  expect (reg.profiles.any (· == CodegenProfileId.solanaSbpfPlanV1))
    "registry: solana profiles include solana-sbpf-plan-v1"
  expect (reg.defaultProfile == some CodegenProfileId.solanaSbpfPlanV1)
    "registry: default profile remains solana-sbpf-plan-v1"
  -- Strict ASCII ascending: elf < plan
  match reg.profiles[0]?, reg.profiles[1]? with
  | some p0, some p1 =>
      expect (p0 == CodegenProfileId.solanaSbpfElfV1) "registry: ascending first is elf"
      expect (p1 == CodegenProfileId.solanaSbpfPlanV1) "registry: ascending second is plan"
  | _, _ => throw <| IO.userError "registry: expected exactly two solana profiles"
  expect (!(ProofForgeV2.Targets.BuildSelectionV1.reservedFutureProfiles.contains
      "solana-sbpf-elf-v1"))
    "registry: solana-sbpf-elf-v1 is no longer reserved"
  expect (ProofForgeV2.Targets.BuildSelectionV1.reservedFutureProfiles.contains
      "noir-acir-proof-v1")
    "registry: noir-acir-proof-v1 remains reserved"
  let defaultSel ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  expect (defaultSel.codegenProfile == CodegenProfileId.solanaSbpfPlanV1)
    "resolve: default selection is plan profile"
  let elfSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.solana (some CodegenProfileId.solanaSbpfElfV1)
  expect (elfSel.codegenProfile == CodegenProfileId.solanaSbpfElfV1)
    "resolve: explicit elf selection"

/-- Requirement support row for both solana profiles; descriptor residual stays plan. -/
private def testSupportAndDescriptor : IO Unit := do
  let rows ← liftResult productSupportRowsV1
  let elfRow ← match rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfElfV1) with
    | some r => pure r
    | none => throw <| IO.userError "missing solana elf support row"
  let planRow ← match rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfPlanV1) with
    | some r => pure r
    | none => throw <| IO.userError "missing solana plan support row"
  expect (elfRow.supported.size == planRow.supported.size)
    "support: elf and plan share the same S2 capability set size"
  expect (elfRow.supported.map (·.id) == planRow.supported.map (·.id))
    "support: elf and plan share exact S2 id list"
  let ids := planRow.supported.map (·.id)
  expect (ids.size == 5 &&
      !ids.contains "effect.synchronous-call" &&
      !ids.contains "effect.asynchronous-workflow")
    "support: both legacy profiles decline call/schedule until the opt-in CPI profile"
  let desc := Targets.Solana.descriptor
  expect (desc.codegenProfile == CodegenProfileId.solanaSbpfPlanV1)
    "descriptor: residual binds plan profile"
  expect (acceptsCodegenProfile desc CodegenProfileId.solanaSbpfPlanV1)
    "descriptor: accepts plan"
  expect (acceptsCodegenProfile desc CodegenProfileId.solanaSbpfElfV1)
    "descriptor: accepts elf"
  expect (!acceptsCodegenProfile desc CodegenProfileId.evmYulSolc0834V1)
    "descriptor: rejects foreign profile"

/-- buildFromCapability under elf emits .s + plan + IDL; plan profile unchanged. -/
private unsafe def testEmitProfiles
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-elf-emit>"
  -- Plan profile regression
  let planCap ← liftResult <| solanaCapability compiled none
  let planFiles ← liftResult <| buildFromCapability planCap
  let planPaths := planFiles.map (·.path)
  expect (planPaths.any (· == "Counter.sbpf-plan")) "plan emit: .sbpf-plan"
  expect (planPaths.any (· == "Counter.idl.json")) "plan emit: idl"
  expect (!planPaths.any (fun p => p.endsWith ".s"))
    "plan emit: must not publish .s"
  let planIdl ← match planFiles.find? (·.path == "Counter.idl.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "plan emit: missing idl"
  expect (planIdl.contains "\"codegenProfile\": \"solana-sbpf-plan-v1\"")
    "plan idl: codegen profile is plan"
  expect (planIdl.contains "\"deployable\": false")
    "plan idl: non-deployable"
  -- Elf profile
  let elfCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfElfV1)
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf elfCap ==
      CodegenProfileId.solanaSbpfElfV1)
    "elf capability profile"
  let elfFiles ← liftResult <| buildFromCapability elfCap
  let elfPaths := elfFiles.map (·.path)
  expect (elfPaths.any (· == "Counter.sbpf-plan")) "elf emit: .sbpf-plan"
  expect (elfPaths.any (· == "Counter.idl.json")) "elf emit: idl"
  expect (elfPaths.any (· == "Counter.s")) "elf emit: .s"
  let elfIdl ← match elfFiles.find? (·.path == "Counter.idl.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "elf emit: missing idl"
  expect (elfIdl.contains "\"codegenProfile\": \"solana-sbpf-elf-v1\"")
    "elf idl: codegen profile is elf"
  expect (elfIdl.contains "\"deployable\": true")
    "elf idl: deployable"
  let asmFromFiles ← match elfFiles.find? (·.path == "Counter.s") with
    | some f => pure f.contents
    | none => throw <| IO.userError "elf emit: missing .s file"
  let ir ← liftResult <| irFromCapability elfCap
  let asmDirect ← liftResult <| emitSbpfAsmV1 ir
  expect (asmFromFiles == asmDirect)
    "elf emit: .s contents equal emitSbpfAsmV1"
  expect (asmFromFiles.contains ".globl entrypoint")
    "elf emit: assembly golden fragment"
  expect (asmFromFiles.contains "entrypoint:")
    "elf emit: entrypoint label"
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asmFromFiles == asm2) "elf emit: deterministic"
  -- Aggregate materialize under elf also binds profile and ships .s
  let artifacts ← liftResult <| Targets.materializeResult elfCap
  expect (MaterializedArtifactsV1.codegenProfileIdOf artifacts ==
      CodegenProfileId.solanaSbpfElfV1)
    "materialize: carrier profile is elf"
  let matPaths := (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  expect (matPaths.any (· == "Counter.s")) "materialize: includes .s"

/-- Finalize pure helpers + plan stub regression + missing-tool path. -/
private unsafe def testFinalize
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Pure path helpers
  let root := FilePath.mk "/tmp/pf-solana-elf-project"
  expect (Targets.Solana.FinalizeV1.projectAsmPathV1 root "Counter" ==
      root / "src" / "Counter" / "Counter.s")
    "finalize helper: project asm path"
  expect (Targets.Solana.FinalizeV1.deploySoPathV1 root "Counter" ==
      root / "deploy" / "Counter.so")
    "finalize helper: deploy so path"
  -- Empty .so gate
  expectIoErrorContains "empty so" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Solana.FinalizeV1.requireNonemptySbpfElf (ByteArray.mk #[])
  Targets.Solana.FinalizeV1.requireNonemptySbpfElf (ByteArray.mk #[0x7f, 0x45])
  -- Plan profile: zero-tool stub unchanged
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-elf-finalize-plan>"
  let planCap ← liftResult <| solanaCapability compiled none
  let planArtifacts ← liftResult <| Targets.materializeResult planCap
  IO.FS.withTempDir fun staging => do
    let draft ← Targets.Solana.FinalizeV1.finalize planCap planArtifacts staging
    expect (draft.deployable == false) "plan finalize: not deployable"
    expect (draft.extraFiles.isEmpty) "plan finalize: no extras"
    expect (draft.evidenceNote.contains "non-executable")
      "plan finalize: non-executable note"
  -- Elf profile: missing locked tool → PF-TOOLCHAIN-MISSING (no S2b lock yet).
  -- Also covers missing staging .s before resolve is attempted when we stage empty.
  let elfCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfElfV1)
  let elfArtifacts ← liftResult <| Targets.materializeResult elfCap
  IO.FS.withTempDir fun staging => do
    -- No .s staged → fail closed before or independent of tool resolve
    expectIoErrorContains "missing staging asm" "PF-ARTIFACT-NONDEPLOYABLE" do
      let _ ← Targets.Solana.FinalizeV1.finalize elfCap elfArtifacts staging
      pure ()
  IO.FS.withTempDir fun staging => do
    -- Stage a minimal .s so finalize reaches resolve "sbpf"
    let asm ← match (MaterializedArtifactsV1.filesOf elfArtifacts).find?
        (·.path == "Counter.s") with
      | some f => pure f.contents
      | none => throw <| IO.userError "elf artifacts missing Counter.s"
    IO.FS.writeFile (staging / "Counter.s") asm
    -- S2b registers sbpf in the lock. Lean has no process-global setEnv; when the
    -- host has not yet materialized `sbpf` under PROOF_FORGE_TOOL_ROOT / default
    -- cache, resolve fails closed with PF-TOOLCHAIN-MISSING. When a provisioned
    -- binary is present, skip this negative (positive .so e2e is outside this suite).
    let toolRoot? ← IO.getEnv "PROOF_FORGE_TOOL_ROOT"
    let candidate ← match toolRoot? with
      | some root => pure (FilePath.mk root / "sbpf")
      | none =>
          match ← IO.getEnv "HOME" with
          | some home =>
              pure (FilePath.mk home / ".cache" / "proof-forge-v2" / "tool-root" /
                (if System.Platform.isOSX then "darwin-arm64" else "linux-x86_64") /
                "sbpf")
          | none => pure (FilePath.mk "/nonexistent-sbpf")
    if ← candidate.pathExists then
      pure ()
    else
      expectIoErrorContains "missing sbpf tool" "PF-TOOLCHAIN-MISSING" do
        let _ ← Targets.Solana.FinalizeV1.finalize elfCap elfArtifacts staging
        pure ()

unsafe def run : IO Unit := do
  testRegistryMembership
  testSupportAndDescriptor
  let session ← Tests.Language.ParserSession.shared
  testEmitProfiles session
  testFinalize session
  IO.println "Tests.Targets.SolanaElfV1: ok"

end Tests.Targets.SolanaElfV1
