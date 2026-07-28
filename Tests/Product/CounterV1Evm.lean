import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Product.CounterV1Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftCompile (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def liftSource (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftCompile "load ProgramV1" (← session.selectProgramV1
    Examples.counterSourceText "<counter-v1>" Examples.counterModuleNameV1 none)

  let identity := NonEmptyArray.toArray source.programIdentity.components |>.map (·.raw)
  expect (identity == #["Examples", "Counter", "ProofForgeV2", "Examples", "Counter"])
    "ProgramV1 identity must join explicit module, active namespace, and declaration"
  expect (source.program.items.size == 4)
    "Counter ProgramV1 must retain state/init/entry/view source order"

  let multiple :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program One where\n  view get() : UInt64 do\n    return 1\n" ++
    "program Two where\n  view get() : UInt64 do\n    return 2\n"
  match ← session.selectProgramV1 multiple "<multiple-v1>" "Product.Multi" none with
  | .error (.invalidProgram message) =>
      expect (message ==
        "source contains multiple programs; pass --program <qualified-name>")
        "multiple ProgramV1 sources must require an explicit raw identity"
  | .error error => throw <| IO.userError s!"multiple selection: {error.render}"
  | .ok _ => throw <| IO.userError "multiple ProgramV1 source selected implicitly"
  let selected ← liftCompile "select raw ProgramV1 identity" (←
    session.selectProgramV1 multiple "<multiple-v1>" "Product.Multi"
      (some "Product.Multi.Two"))
  expect ((NonEmptyArray.toArray selected.programIdentity.components).map (·.raw) ==
      #["Product", "Multi", "Two"])
    "--program must select by parser-produced raw component arrays"

  let digest ← liftSource "sourceHashV1" (sourceHashV1 source)
  let renderedDigest ← liftSource "render sourceHashV1" (renderDigest digest)
  let nodeTable ← liftSource "assign NodeIds" <|
    assignNodeIdsV1 source.moduleName source.programIdentity source.program
  expect (!(nodeAssignmentsPreorderV1 nodeTable).isEmpty)
    "validated ProgramV1 must produce canonical NodeId assignments"

  -- S3/S5: product compile retains NormalizeV1 structure-valid SemanticProgramV1.
  let carrier1 ← match normalizeProgramV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"Counter Normalize #1: {repr e}"
  let carrier2 ← match normalizeProgramV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"Counter Normalize #2: {repr e}"
  match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1 carrier1 with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"Counter validate SemanticProgramV1: {repr e}"
  expect (carrier1.canonicalBytes == carrier2.canonicalBytes)
    "Counter Normalize canonicalBytes must be deterministic"
  let h1 ← match ProofForgeV2.Semantic.WireV1.semanticHashV1 carrier1 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"Counter semanticHash #1: {repr e}"
  let h2 ← match ProofForgeV2.Semantic.WireV1.semanticHashV1 carrier2 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"Counter semanticHash #2: {repr e}"
  expect (h1 == h2) "Counter semanticHashV1 must be deterministic"

  let compiled ← liftCompile "compile ProgramV1" <|
    Compiler.compileValidatedSourceV1 source
  let retained := CompiledProgramV1.semanticV1Of compiled
  expect (retained.canonicalBytes == carrier1.canonicalBytes)
    "product compile must retain NormalizeV1 SemanticProgramV1 bytes"
  let semantic := CompiledProgramV1.alphaResidualOf compiled
  expect (semantic.qualifiedName ==
      "Examples.Counter.ProofForgeV2.Examples.Counter")
    "Typed/Semantic identity must come from ProgramV1 raw components"
  expect (renderedDigest == "sha256:" ++ semantic.sourceHash)
    "Semantic provenance must use sourceHashV1 exactly"
  expect (semantic.state.map (·.name) == #["count"] &&
      semantic.entries.map (·.name) == #["increment", "get"])
    "ProgramV1 typing must preserve Counter state and callables"

  let resolved ← liftCompile "resolve EVM" <|
    Targets.resolve .evm Targets.Evm.descriptor semantic
  let plan ← liftCompile "make EVM plan" <| Targets.Evm.makePlan resolved
  expect (plan.storageLayout.map (·.name) == #["count"] &&
      plan.entries.map (·.name) == #["increment", "get"])
    "EVM-owned plan must derive Counter layout and entries"

  let ir ← liftCompile "lower EVM IR" <| Targets.Evm.lower plan
  expect (ir.yul.contains "case 0xdd9a82bc" &&
      ir.yul.contains "case 0x6d4ce63c")
    "EVM IR must contain canonical Counter selectors"
  let first ← liftCompile "materialize EVM" <| (do
    let selection ← ProofForgeV2.Targets.BuildSelectionV1.resolveBuildSelectionV1
      TargetId.evm none
    let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
    Targets.materializeResult capability)
  let second ← liftCompile "materialize EVM again" <| (do
    let selection ← ProofForgeV2.Targets.BuildSelectionV1.resolveBuildSelectionV1
      TargetId.evm none
    let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
    Targets.materializeResult capability)
  expect (first == second)
    "ProgramV1 EVM materialization must be deterministic"
  expect (first.files.map (·.path) == #["Counter.yul", "Counter.abi.json"])
    "ProgramV1 EVM materialization must emit target-owned Yul and ABI artifacts"
  expect (first.manifest.sourceHash == semantic.sourceHash &&
      first.manifest.semanticHash == semantic.semanticHash)
    "EVM manifest must bind ProgramV1 source and semantic hashes"

end Tests.Product.CounterV1Evm
