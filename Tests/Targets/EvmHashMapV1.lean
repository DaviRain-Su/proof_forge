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
# Tests.Targets.EvmHashMapV1 — opt-in hashed-Map storage profile

Pins (engineering only):
* registry membership of `evm-yul-solc-0.8.34-hashmap-v1` as product default
* descriptor accepts hashmap; foreign profiles fail closed
* Finalize argv matches dense (`--optimize --bin`); evidence note `map-storage=hashed`
* capability mint + materialize succeed for StateCell under hashmap profile
* MapMini under hashed profile lowers with `hashedMapStorage = true` and 1-slot Map base
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
  expect (reg.profiles.any (· == CodegenProfileId.evmYulSolc0834HashMapV1))
    "registry: evm profiles include hashmap-v1"
  expect (reg.defaultProfile == some CodegenProfileId.evmYulSolc0834HashMapV1)
    "registry: default is hashmap-v1"
  let sel ← liftResult <|
    resolveBuildSelectionV1 TargetId.evm (some CodegenProfileId.evmYulSolc0834HashMapV1)
  expect (sel.codegenProfile == CodegenProfileId.evmYulSolc0834HashMapV1)
    "resolve explicit hashmap"
  let desc := Targets.Evm.descriptor
  expect (acceptsCodegenProfile desc CodegenProfileId.evmYulSolc0834HashMapV1)
    "accepts hashmap"
  expect (!acceptsCodegenProfile desc CodegenProfileId.solanaSbpfPlanV1)
    "rejects foreign"

private def testFinalizeArgsAndNote : IO Unit := do
  match FinalizeV1.solcArgsForProfile CodegenProfileId.evmYulSolc0834HashMapV1 "x.yul" with
  | .ok args =>
      expect (args == #["--strict-assembly", "--optimize", "--bin", "x.yul"])
        "hashmap solc args match dense optimized finalize"
  | .error e => throw <| IO.userError s!"hashmap solcArgs must succeed: {e}"
  match FinalizeV1.evidenceHardforkNote CodegenProfileId.evmYulSolc0834HashMapV1 with
  | .ok note =>
      expect (note == " map-storage=hashed")
        "hashmap evidence note observes map-storage=hashed"
  | .error e => throw <| IO.userError s!"hashmap hardfork note must succeed: {e}"

private unsafe def testCapabilityAndMapPlan : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let compiled ← compileSource session stateCellSourceText stateCellModuleNameV1
    "<evm-hashmap-stateCell>"
  let cap ← liftResult <|
    evmCapability compiled (some CodegenProfileId.evmYulSolc0834HashMapV1)
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf cap ==
      CodegenProfileId.evmYulSolc0834HashMapV1)
    "hashmap capability binds hashmap profile"
  let out ← liftResult <| Targets.materializeResult cap
  expect (MaterializedArtifactsV1.codegenProfileIdOf out ==
      CodegenProfileId.evmYulSolc0834HashMapV1)
    "materialized hashmap profile"

  let mapCompiled ← compileSource session mapMiniSource "Tests.EvmHashMapMini" "<evm-hashmap-mapMini>"
  let mapCap ← liftResult <|
    evmCapability mapCompiled (some CodegenProfileId.evmYulSolc0834HashMapV1)
  let plan ← liftResult <| materializePlanFromCapabilityV1 mapCap
  expect plan.hashedMapStorage
    "MapMini hashed plan sets hashedMapStorage"
  expect (plan.storageLayout.size == 1)
    s!"MapMini hashed layout must be single base slot, got {plan.storageLayout.size}"
  match plan.storageLayout[0]? with
  | some b =>
      expect (b.name.endsWith "_base")
        s!"hashed Map base leaf name must end with _base, got {b.name}"
  | none => throw <| IO.userError "hashed layout missing base binding"

  -- Default (none) is now hashed; dense still available via explicit profile.
  let defaultCap ← liftResult <| evmCapability mapCompiled none
  let defaultPlan ← liftResult <| materializePlanFromCapabilityV1 defaultCap
  expect defaultPlan.hashedMapStorage "default MapMini plan is hashed"
  expect (defaultPlan.storageLayout.size == 1)
    s!"default MapMini layout must be 1 base slot, got {defaultPlan.storageLayout.size}"
  let denseCap ← liftResult <|
    evmCapability mapCompiled (some CodegenProfileId.evmYulSolc0834V1)
  let densePlan ← liftResult <| materializePlanFromCapabilityV1 denseCap
  expect (!densePlan.hashedMapStorage) "explicit dense hashedMapStorage=false"
  expect (densePlan.storageLayout.size == 24)
    s!"dense MapMini layout must stay 24 leaves, got {densePlan.storageLayout.size}"

unsafe def run : IO Unit := do
  testRegistryAndDescriptor
  testFinalizeArgsAndNote
  testCapabilityAndMapPlan
  IO.println "Tests.Targets.EvmHashMapV1: ok"

end Tests.Targets.EvmHashMapV1
