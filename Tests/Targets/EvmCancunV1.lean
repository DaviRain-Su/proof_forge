import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Targets.Evm.FinalizeV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

/-!
# Tests.Targets.EvmCancunV1 — EVMOZ-001 explicit Cancun profile

Pins (engineering only; not formal D4 / OZ compatibility / release evidence):
* registry membership of `evm-yul-solc-0.8.34-cancun-v1` with default still legacy v1
* requirement-support row for the Cancun profile (same S2 set as default)
* residual descriptor stays legacy v1 but accepts Cancun via acceptsCodegenProfile
* pure Finalize argv: Cancun adds `--evm-version cancun`; legacy keeps historical args
* evidence hardfork note is non-empty only for Cancun
-/

namespace Tests.Targets.EvmCancunV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.Evm
open ProofForgeV2.Materialization

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def evmCapability
    (compiled : CompiledSemanticV1) (profile? : Option CodegenProfileId) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.evm profile?
  Targets.resolveEngineeringRequirementsV1 selection compiled

/-- Registry: cancun profile is a member; default remains legacy v1; ascending. -/
private def testRegistryMembership : IO Unit := do
  let reg ← liftResult <| registration? TargetId.evm
  let reg ← match reg with
    | some r => pure r
    | none => throw <| IO.userError "evm registration missing"
  expect (reg.profiles.any (· == CodegenProfileId.evmYulSolc0834CancunV1))
    "registry: evm profiles include cancun-v1"
  expect (reg.profiles.any (· == CodegenProfileId.evmYulSolc0834V1))
    "registry: evm profiles include legacy v1"
  expect (reg.defaultProfile == some CodegenProfileId.evmYulSolc0834V1)
    "registry: default profile remains evm-yul-solc-0.8.34-v1"
  match reg.profiles[0]?, reg.profiles[1]? with
  | some p0, some p1 =>
      expect (p0 == CodegenProfileId.evmYulSolc0834CancunV1)
        "registry: ascending first is cancun-v1"
      expect (p1 == CodegenProfileId.evmYulSolc0834V1)
        "registry: ascending second is legacy v1"
  | _, _ => throw <| IO.userError "registry: expected exactly two evm profiles"
  let defaultSel ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  expect (defaultSel.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
    "resolve none → legacy default"
  let cancunSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.evm (some CodegenProfileId.evmYulSolc0834CancunV1)
  expect (cancunSel.codegenProfile == CodegenProfileId.evmYulSolc0834CancunV1)
    "resolve explicit cancun"

/-- Support rows: both EVM profiles present with identical S2 capability size. -/
private def testSupportAndDescriptor : IO Unit := do
  let rows ← liftResult productSupportRowsV1
  let cancunRow ← match rows.find? (fun r =>
      r.targetId == TargetId.evm &&
        r.codegenProfile == CodegenProfileId.evmYulSolc0834CancunV1) with
    | some r => pure r
    | none => throw <| IO.userError "missing evm cancun support row"
  let legacyRow ← match rows.find? (fun r =>
      r.targetId == TargetId.evm &&
        r.codegenProfile == CodegenProfileId.evmYulSolc0834V1) with
    | some r => pure r
    | none => throw <| IO.userError "missing evm legacy support row"
  expect (cancunRow.supported.size == legacyRow.supported.size)
    "support: cancun and legacy share the same S2 capability set size"
  expect (cancunRow.supported.map (·.id) == legacyRow.supported.map (·.id))
    "support: cancun and legacy share exact S2 id list"
  let desc := Targets.Evm.descriptor
  expect (desc.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
    "descriptor residual is legacy default"
  expect (acceptsCodegenProfile desc CodegenProfileId.evmYulSolc0834V1)
    "accepts legacy"
  expect (acceptsCodegenProfile desc CodegenProfileId.evmYulSolc0834CancunV1)
    "accepts cancun"
  expect (!acceptsCodegenProfile desc CodegenProfileId.solanaSbpfPlanV1)
    "rejects foreign solana profile"

/-- Pure Finalize argv + evidence note are profile-gated (no tool invocation). -/
private def testFinalizeArgsAndNote : IO Unit := do
  match FinalizeV1.solcArgsForProfile CodegenProfileId.evmYulSolc0834V1 "StateCell.yul" with
  | .ok legacyArgs =>
      expect (legacyArgs == #["--strict-assembly", "--optimize", "--bin", "StateCell.yul"])
        "legacy solc args enable --optimize (no ambient --evm-version)"
  | .error e => throw <| IO.userError s!"legacy solcArgs must succeed: {e}"
  match FinalizeV1.solcArgsForProfile CodegenProfileId.evmYulSolc0834CancunV1 "StateCell.yul" with
  | .ok cancunArgs =>
      expect (cancunArgs ==
          #["--strict-assembly", "--optimize", "--evm-version", "cancun",
            "--bin", "StateCell.yul"])
        "cancun solc args pin --evm-version cancun"
  | .error e => throw <| IO.userError s!"cancun solcArgs must succeed: {e}"
  -- Unknown profile fail closed (open-else would silently treat as legacy).
  match FinalizeV1.solcArgsForProfile CodegenProfileId.solanaSbpfPlanV1 "StateCell.yul" with
  | .ok _ => throw <| IO.userError "foreign profile solcArgs must fail closed"
  | .error e =>
      expect (e.contains "unsupported EVM finalize profile")
        s!"foreign solcArgs error must name unsupported profile, got: {e}"
  match FinalizeV1.evidenceHardforkNote CodegenProfileId.evmYulSolc0834V1 with
  | .ok note => expect (note == "") "legacy evidence note has no hardfork fragment"
  | .error e => throw <| IO.userError s!"legacy hardfork note must succeed: {e}"
  match FinalizeV1.evidenceHardforkNote CodegenProfileId.evmYulSolc0834CancunV1 with
  | .ok note =>
      expect (note == " evm-version=cancun")
        "cancun evidence note observes hardfork pin"
  | .error e => throw <| IO.userError s!"cancun hardfork note must succeed: {e}"
  match FinalizeV1.evidenceHardforkNote CodegenProfileId.nearWasmRawU64V1 with
  | .ok _ => throw <| IO.userError "foreign profile hardfork note must fail closed"
  | .error e =>
      expect (e.contains "unsupported EVM finalize profile")
        s!"foreign hardfork note error must name unsupported profile, got: {e}"

/-- Capability mint + materialize succeed for both profiles on StateCell. -/
private unsafe def testCapabilityMint : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let compiled ← compileSource session stateCellSourceText stateCellModuleNameV1
    "<evm-cancun-stateCell>"
  let legacyCap ← liftResult <| evmCapability compiled none
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf legacyCap ==
      CodegenProfileId.evmYulSolc0834V1)
    "default capability binds legacy profile"
  let cancunCap ← liftResult <|
    evmCapability compiled (some CodegenProfileId.evmYulSolc0834CancunV1)
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf cancunCap ==
      CodegenProfileId.evmYulSolc0834CancunV1)
    "cancun capability binds cancun profile"
  let legacyOut ← liftResult <| Targets.materializeResult legacyCap
  let cancunOut ← liftResult <| Targets.materializeResult cancunCap
  expect (MaterializedArtifactsV1.codegenProfileIdOf legacyOut ==
      CodegenProfileId.evmYulSolc0834V1)
    "materialized legacy profile"
  expect (MaterializedArtifactsV1.codegenProfileIdOf cancunOut ==
      CodegenProfileId.evmYulSolc0834CancunV1)
    "materialized cancun profile"

unsafe def run : IO Unit := do
  testRegistryMembership
  testSupportAndDescriptor
  testFinalizeArgsAndNote
  testCapabilityMint
  IO.println "Tests.Targets.EvmCancunV1: ok"

end Tests.Targets.EvmCancunV1
