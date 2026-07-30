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

private def materializeSelected (target : TargetId) (compiled : CompiledSemanticV1) :
    CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

private def planEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.planFromCapability capability

private def testSemanticPlanSourceAuthority : IO Unit := do
  let path := "ProofForgeV2/Targets/Evm.lean"
  let forbidden ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "alphaResidualOf|makePlanFromAlpha", path]
  }
  expect (forbidden.exitCode == 1)
    s!"EVM Plan body must not retain the alpha residual route:\n{forbidden.stdout}"
  let required ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "semanticV1Of|validateSemanticProgramV1|makePlanFromSemanticV1", path]
  }
  expect (required.exitCode == 0 &&
      required.stdout.contains "semanticV1Of" &&
      required.stdout.contains "validateSemanticProgramV1" &&
      required.stdout.contains "makePlanFromSemanticV1")
    s!"EVM Plan body must be visibly SemanticProgramV1-native:\n{required.stdout}"

private unsafe def testRichUInt64SemanticPlan : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Ledger where\n" ++
    "  state left : UInt64\n" ++
    "  state right : UInt64\n" ++
    "  init(a : UInt64, b : UInt64) do\n" ++
    "    left := a\n" ++
    "    right := b\n" ++
    "  entry mix(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    left := left + x - y\n" ++
    "    right := right - x\n" ++
    "    return left\n" ++
    "  view getRight() : UInt64 do\n" ++
    "    return right\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load rich UInt64" (← session.selectProgramV1
    sourceText "<evm-semantic-rich>" "Tests.EvmSemantic" none)
  let compiled ← liftResult "compile rich UInt64" <|
    Compiler.compileValidatedSourceV1 source
  let plan ← liftResult "plan rich UInt64" <| planEvm compiled
  expect (plan.objectName == "Ledger")
    "EVM object name must be the final SemanticProgramV1 qualified component"
  expect (plan.storageLayout == #[
      { sourceId := 0, name := "left", slot := 0 },
      { sourceId := 1, name := "right", slot := 1 }])
    "EVM SemanticProgramV1 state ids must map to declaration-order slots"
  match plan.constructor with
  | none => throw <| IO.userError "rich S1 stateful plan must retain its initializer"
  | some constructor =>
      expect (constructor.params == #[
          { sourceId := 0, name := "a", wordIndex := 0 },
          { sourceId := 1, name := "b", wordIndex := 1 }])
        "EVM constructor ValueIds must map to canonical ABI words"
      expect (constructor.stores == #[
          { slot := 0, value := .param 0 },
          { slot := 1, value := .param 1 }])
        "EVM constructor stores must preserve source order"
  expect (plan.entries.map (·.name) == #["mix", "getRight"])
    "EVM entries must preserve callable source order"
  let mix := plan.entries[0]!
  expect (mix.params == #[
      { sourceId := 0, name := "x", wordIndex := 0 },
      { sourceId := 1, name := "y", wordIndex := 1 }])
    "EVM entry ValueIds must map to canonical ABI words"
  expect (mix.body == #[
      .store {
        slot := 0
        value := .checkedSub
          (.checkedAdd (.storageLoad 0) (.param 0)) (.param 1)
      },
      .store {
        slot := 1
        value := .checkedSub (.storageLoad 1) (.param 0)
      },
      .returnValue (.storageLoad 0)])
    "EVM SSA lowering must preserve nested add/sub, store order, and post-store return"
  expect (plan.entries[1]!.body == #[.returnValue (.storageLoad 1)])
    "EVM view lowering must preserve the selected storage slot"
  let output ← liftResult "materialize rich add/sub" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "Ledger.yul") |
    throw <| IO.userError "rich add/sub: missing Ledger.yul"
  let yul := yulFile.contents
  expect (yul.contains "if lt(expr2, expr3) { revert(0, 0) }" &&
      yul.contains "let expr4 := sub(expr2, expr3)")
    "EVM Yul must check UInt64 underflow before subtraction"

unsafe def run : IO Unit := do
  testSemanticPlanSourceAuthority
  testRichUInt64SemanticPlan
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<evm-smoke-counter>" Examples.counterModuleNameV1 none)
  let compiled ← liftResult "compile Counter" <| Compiler.compileValidatedSourceV1 source
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  let plan ← liftResult "plan EVM" <| planEvm compiled
  expect (plan.objectName == "Counter" && plan.storageLayout.map (·.name) == #["count"])
    "EVM smoke must preserve the Counter identity and storage layout"
  expect (plan.entries.map (·.name) == #["increment", "get"])
    "EVM smoke must preserve both Counter entries"

  -- S6: no public Plan→IR; capability materialize is sole emit path.
  let output ← liftResult "materialize EVM" <| materializeSelected TargetId.evm compiled
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.map (·.path) == #["Counter.yul", "Counter.abi.json"])
    "EVM smoke must emit deterministic target-owned source artifacts"
  let yul ← match files.find? (·.path == "Counter.yul") with
    | some f => pure f.contents
    | none => throw <| IO.userError "EVM smoke missing Counter.yul"
  let abi ← match files.find? (·.path == "Counter.abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "EVM smoke missing Counter.abi.json"
  expect (yul.contains "case 0xdd9a82bc" && yul.contains "case 0x6d4ce63c")
    "EVM smoke must render canonical increment/get selectors"
  expect (abi.contains "\"name\":\"increment\"" && abi.contains "\"name\":\"get\"")
    "EVM smoke must render the Counter ABI"
  expect (MaterializedArtifactsV1.sourceDigestOf output == sourceDigest &&
      MaterializedArtifactsV1.semanticDigestOf output == semanticDigest)
    "EVM smoke carrier must bind canonical source and semantic digests"
  -- plan is still capability-gated and used for layout assertions above
  let _ := plan
  IO.println "Tests.Materialization.EvmSmoke: ok"

end Tests.Materialization.EvmSmoke
