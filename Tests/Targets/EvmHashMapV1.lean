import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Targets.Evm.FinalizeV1
import ProofForgeV2.Targets.Evm.LowerSemanticV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

/-!
# Tests.Targets.EvmHashMapV1 — product-default hashed-Map storage

Pins (engineering only):
* sole default profile is `evm-yul-solc-0.8.34-v1` (hashed Map; no separate hashmap id)
* Cancun remains the only additional EVM profile
* Finalize argv + evidence note ` map-storage=hashed` on default v1
* MapMini default plan is hashed (1 base slot)
-/

namespace Tests.Targets.EvmHashMapV1

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

private def mapMiniSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program MapMini where\n" ++
  "  state m : Map UInt64 UInt64\n" ++
  "  init() do\n" ++
  "    m := Map.empty()\n" ++
  "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
  "    m[k] := v\n" ++
  "    return v\n" ++
  "  view get(k : UInt64) : UInt64 do\n" ++
  "    match m[k] with\n" ++
  "    | Option.some(v) => do\n" ++
  "      return v\n" ++
  "    | _ => do\n" ++
  "      return 0\n"

private def testRegistryAndDescriptor : IO Unit := do
  let reg ← liftResult <| registration? TargetId.evm
  let reg ← match reg with
    | some r => pure r
    | none => throw <| IO.userError "evm registration missing"
  expect (reg.profiles ==
      #[CodegenProfileId.evmYulSolc0834CancunV1, CodegenProfileId.evmYulSolc0834V1])
    "registry: only cancun + v1"
  expect (reg.defaultProfile == some CodegenProfileId.evmYulSolc0834V1)
    "registry: default is v1"
  let sel ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  expect (sel.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
    "resolve none → v1"
  let desc := Targets.Evm.descriptor
  expect (desc.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
    "descriptor residual is v1"
  expect (acceptsCodegenProfile desc CodegenProfileId.evmYulSolc0834V1)
    "accepts v1"
  expect (acceptsCodegenProfile desc CodegenProfileId.evmYulSolc0834CancunV1)
    "accepts cancun"
  expect (!acceptsCodegenProfile desc CodegenProfileId.solanaSbpfPlanV1)
    "rejects foreign"

private def testFinalizeArgsAndNote : IO Unit := do
  match FinalizeV1.solcArgsForProfile CodegenProfileId.evmYulSolc0834V1 "x.yul" with
  | .ok args =>
      expect (args == #["--strict-assembly", "--optimize", "--bin", "x.yul"])
        "v1 solc args"
  | .error e => throw <| IO.userError s!"v1 solcArgs must succeed: {e}"
  match FinalizeV1.evidenceHardforkNote CodegenProfileId.evmYulSolc0834V1 with
  | .ok note =>
      expect (note == " map-storage=hashed")
        "v1 evidence note observes map-storage=hashed"
  | .error e => throw <| IO.userError s!"v1 hardfork note must succeed: {e}"
  match FinalizeV1.evidenceHardforkNote CodegenProfileId.evmYulSolc0834CancunV1 with
  | .ok note =>
      expect (note == " evm-version=cancun map-storage=hashed")
        "cancun evidence includes hardfork + hashed map"
  | .error e => throw <| IO.userError s!"cancun hardfork note must succeed: {e}"

private unsafe def testCapabilityAndMapPlan : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let compiled ← compileSource session stateCellSourceText stateCellModuleNameV1
    "<evm-hashed-stateCell>"
  let cap ← liftResult <| evmCapability compiled none
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf cap ==
      CodegenProfileId.evmYulSolc0834V1)
    "default capability binds v1"
  let out ← liftResult <| Targets.materializeResult cap
  expect (MaterializedArtifactsV1.codegenProfileIdOf out ==
      CodegenProfileId.evmYulSolc0834V1)
    "materialized v1"

  let mapCompiled ← compileSource session mapMiniSource "Tests.EvmHashMapMini"
    "<evm-hashed-mapMini>"
  let mapCap ← liftResult <| evmCapability mapCompiled none
  let plan ← liftResult <| materializePlanFromCapabilityV1 mapCap
  expect plan.hashedMapStorage
    "MapMini default plan sets hashedMapStorage"
  expect (plan.storageLayout.size == 1)
    s!"MapMini hashed layout must be single base slot, got {plan.storageLayout.size}"
  match plan.storageLayout[0]? with
  | some b =>
      expect (b.name.endsWith "_base")
        s!"hashed Map base leaf name must end with _base, got {b.name}"
  | none => throw <| IO.userError "hashed layout missing base binding"

  -- Cancun also hashed.
  let cancunCap ← liftResult <|
    evmCapability mapCompiled (some CodegenProfileId.evmYulSolc0834CancunV1)
  let cancunPlan ← liftResult <| materializePlanFromCapabilityV1 cancunCap
  expect cancunPlan.hashedMapStorage "cancun MapMini plan is hashed"
  expect (cancunPlan.storageLayout.size == 1)
    s!"cancun MapMini layout must be 1 base slot, got {cancunPlan.storageLayout.size}"

unsafe def run : IO Unit := do
  testRegistryAndDescriptor
  testFinalizeArgsAndNote
  testCapabilityAndMapPlan
  IO.println "Tests.Targets.EvmHashMapV1: ok"

end Tests.Targets.EvmHashMapV1
