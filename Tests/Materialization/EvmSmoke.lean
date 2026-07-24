import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Targets.Registry

namespace Tests.Materialization.EvmSmoke

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

def run : IO Unit := do
  let semantic ← liftResult "compile Counter" <| Compiler.compile Examples.counter
  let resolved ← liftResult "resolve EVM" <| Targets.resolve Targets.Evm.descriptor semantic
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

  let output ← Targets.materialize .evm semantic
  expect (output.files.map (·.path) == #["Counter.yul", "Counter.abi.json"])
    "EVM smoke must emit deterministic target-owned source artifacts"
  expect (output.manifest.sourceHash == semantic.sourceHash &&
      output.manifest.semanticHash == semantic.semanticHash)
    "EVM smoke manifest must bind source and semantic hashes"

end Tests.Materialization.EvmSmoke
