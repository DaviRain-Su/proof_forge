import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.EvmSmoke

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def materializeSelected (target : TargetId) (compiled : CompiledProgramV1) :
    CompileResult OutputSet := do
  let selection ← resolveBuildSelectionV1 target none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<evm-smoke-counter>" Examples.counterModuleNameV1 none)
  let compiled ← liftResult "compile Counter" <| Compiler.compileValidatedSourceV1 source
  let semantic := CompiledProgramV1.alphaResidualOf compiled
  let resolved ← liftResult "resolve EVM" <| Targets.resolve .evm Targets.Evm.descriptor semantic
  let plan ← liftResult "plan EVM" <| Targets.Evm.makePlan resolved
  expect (plan.objectName == "Counter" && plan.storageLayout.map (·.name) == #["count"])
    "EVM smoke must preserve the Counter identity and storage layout"
  expect (plan.entries.map (·.name) == #["increment", "get"])
    "EVM smoke must preserve both Counter entries"

  let ir ← liftResult "lower EVM" <| Targets.Evm.lower plan
  expect (ir.yul.contains "case 0xdd9a82bc" && ir.yul.contains "case 0x6d4ce63c")
    "EVM smoke must render canonical increment/get selectors"
  expect (ir.abi.contains "\"name\":\"increment\"" &&
      ir.abi.contains "\"name\":\"get\"")
    "EVM smoke must render the Counter ABI"

  let output ← liftResult "materialize EVM" <| materializeSelected TargetId.evm compiled
  expect (output.files.map (·.path) == #["Counter.yul", "Counter.abi.json"])
    "EVM smoke must emit deterministic target-owned source artifacts"
  expect (output.manifest.sourceHash == semantic.sourceHash &&
      output.manifest.semanticHash == semantic.semanticHash)
    "EVM smoke manifest must bind source and semantic hashes"

end Tests.Materialization.EvmSmoke
