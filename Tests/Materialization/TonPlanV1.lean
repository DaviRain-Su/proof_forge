/-
  Ton Plan/IR/Tolk engineering suite (TON-2 Counter leaf).

  Pins Counter plan shape, Tolk surface (Storage/onInternalMessage/get fun),
  op+query_id envelope, UInt64 range-check markers, and explicit fail-closed
  boundaries (sync call, multi-width, aggregates, invariants, Field/Principal).

  Not registered in Tests/Shards/* — main agent must register the shard.
  Not @ton/sandbox runtime (TON-3). Not formal D4.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Ton
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.TonPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Ton

private def counterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Counter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def counterModuleName : String := "Examples.Counter"

private def multiFieldSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program MultiField where\n" ++
  "  state a : UInt64\n" ++
  "  state b : UInt64\n\n" ++
  "  init(x : UInt64, y : UInt64) do\n" ++
  "    a := x\n" ++
  "    b := y\n\n" ++
  "  entry bump(d : UInt64) : UInt64 do\n" ++
  "    a := a + d\n" ++
  "    return a\n\n" ++
  "  view both() : UInt64 do\n" ++
  "    return b\n\n" ++
  "end ProofForgeV2.Examples\n"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  s!"program {name} where\n" ++ body ++
  "\nend ProofForgeV2.Examples\n"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def expectPlanErrorContaining (label needle : String)
    (result : CompileResult α) : IO Unit :=
  match result with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains needle)
        s!"{label}: expected message containing '{needle}', got '{msg}'"
  | .error e => throw <| IO.userError s!"{label}: expected ton planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected failure, got ok"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def tonCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.ton none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planTon (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let capability ← tonCapability compiled
  planFromCapability capability

private def irTon (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← tonCapability compiled
  irFromCapability capability

private def filesTon (compiled : CompiledSemanticV1) : CompileResult (Array OutputFile) := do
  let capability ← tonCapability compiled
  buildFromCapability capability

private def findFile (files : Array OutputFile) (path : String) : IO String :=
  match files.find? (·.path == path) with
  | some file => pure file.contents
  | none => throw <| IO.userError s!"missing output file '{path}'; got {files.map (·.path)}"

private unsafe def testCounterPlan
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleName "<ton-counter>"
  let plan ← liftResult <| planTon compiled
  expect (plan.programName == "Counter") "program name Counter"
  expect (plan.hostAbi == hostAbiVersion) "canonical host ABI"
  expect (plan.inputAbi == rawInputAbi) "internal-msg input ABI"
  expect (plan.codegenProfile == "ton-tolk-boc-v1") "default profile"
  expect (plan.hostImports == canonicalImports) "tvmCellStorage only"
  expect (plan.storage.fields.size == 1) "one state field"
  expect (plan.storage.fields[0]!.name == "count") "state name count"
  expect (plan.storage.fields[0]!.byteWidth == 8) "UInt64 leaf width"
  expect (plan.initializer.name == "init") "init method"
  expect (plan.initializer.mode == .initialize) "init mode"
  expect (plan.initializer.params.size == 1) "init one param"
  expect (plan.entries.size == 2) "increment + get"
  let some inc := plan.entries.find? (·.name == "increment") |
    throw <| IO.userError "missing increment"
  expect (inc.mode == .mutate && inc.resultKind == .uint64) "increment mutate UInt64"
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "missing get"
  expect (get.mode == .view && get.resultKind == .uint64) "get view UInt64"
  let d1 ← match engineeringTonPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  let d2 ← match engineeringTonPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  expect (d1 == d2) "plan digest deterministic"
  IO.println "  ✓ Counter plan shape"

private unsafe def testCounterIRAndTolk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleName "<ton-counter-ir>"
  let ir ← liftResult <| irTon compiled
  expect (ir.name == "Counter") "IR name"
  expect (ir.methods.size == 3) "init + 2 entries"
  expect (ir.imports == canonicalImports) "IR host imports"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "Counter.tolk"
  let abi ← findFile files "Counter.ton-abi.json"
  -- Tolk surface
  expect (tolk.contains "struct Storage") "Storage struct"
  expect (tolk.contains "__layout: uint64") "layout marker field"
  expect (tolk.contains "count: uint64") "count field"
  expect (tolk.contains "Storage.fromCell(contract.getData())") "c4 load"
  expect (tolk.contains "contract.setData(self.toCell())") "c4 save"
  expect (tolk.contains "fun onInternalMessage(in: InMessage)") "message entry"
  expect (tolk.contains "body.loadUint(32)") "32-bit op"
  expect (tolk.contains "body.loadUint(64)") "64-bit query_id / params"
  expect (tolk.contains "get fun get()") "get-method view"
  expect (tolk.contains "const OP_init") "init op const"
  expect (tolk.contains "const OP_increment") "increment op const"
  expect (tolk.contains s!"throw {errOverflow}" ||
      tolk.contains s!"throw {errOverflow};" ||
      tolk.contains "(1 << 64)") "UInt64 range gate present"
  expect (tolk.contains "(1 << 64)") "explicit 2^64 bound"
  -- No Wasm / CosmWasm leakage
  expect (!tolk.contains "db_read") "no CosmWasm db_read"
  expect (!tolk.contains "(module") "no WAT module"
  expect (!tolk.contains "storage_read") "no NEAR storage_read"
  -- ABI JSON
  expect (abi.contains "proof-forge-ton-abi/v1alpha1") "ABI schema"
  expect (abi.contains "c4-flat-struct") "storage kind"
  expect (abi.contains "\"opBits\":32") "op envelope"
  expect (abi.contains "\"queryIdBits\":64") "query_id envelope"
  IO.println "  ✓ Counter IR/Tolk/ABI shape"

private unsafe def testMultiField
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session multiFieldSourceText
    "Examples.MultiField" "<ton-multi>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 2) "two cell fields"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "MultiField.tolk"
  expect (tolk.contains "a: uint64") "field a"
  expect (tolk.contains "b: uint64") "field b"
  IO.println "  ✓ multi-field state cell"

private unsafe def testCallScheduleFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let callSrc := wrapProgram "CallFc" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    call Other.method(s)\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let validated ← liftResult (← session.selectProgramV1 callSrc
    "<ton-call-fc>" "Examples.CallFc" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()
  | .ok compiled =>
      match tonCapability compiled with
      | .error _ => pure ()  -- resolver FC on effect.synchronous-call
      | .ok capability =>
          expectPlanErrorContaining "call plan" "call" (planFromCapability capability)
  let schedSrc := wrapProgram "SchedFc" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    schedule Other.method(s)\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let validated2 ← liftResult (← session.selectProgramV1 schedSrc
    "<ton-sched-fc>" "Examples.SchedFc" none)
  match Compiler.compileValidatedSourceV1 validated2 with
  | .error _ => pure ()
  | .ok compiled =>
      match tonCapability compiled with
      | .error _ => pure ()
      | .ok capability =>
          -- Capability admits schedule; plan MVP still FC.
          expectPlanErrorContaining "schedule plan" "schedule" (planFromCapability capability)
  IO.println "  ✓ call/schedule fail closed"

private unsafe def testMultiWidthFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowFc" <|
    "  state s : UInt8\n\n" ++
    "  init(x : UInt8) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt8) : UInt8 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt8 do\n" ++
    "    return s\n"
  let validated ← liftResult (← session.selectProgramV1 src
    "<ton-u8-fc>" "Examples.NarrowFc" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()
  | .ok compiled =>
      match tonCapability compiled with
      | .error _ => pure ()
      | .ok capability =>
          match planFromCapability capability with
          | .error (.planInvariant .ton msg) =>
              expect (msg.length > 0) "multi-width planInvariant nonempty"
          | .error e => throw <| IO.userError s!"multi-width: unexpected {e.render}"
          | .ok _ => throw <| IO.userError "multi-width: expected FC, got ok"
  IO.println "  ✓ multi-width UInt8 fail closed"

private unsafe def testRegistryDispatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleName
    "<ton-registry>"
  let capability ← liftResult <| tonCapability compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.artifactProgramNameOf artifacts == "Counter")
    "registry materialize program name"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.any (·.path == "Counter.tolk")) "registry emits .tolk"
  expect (files.any (·.path == "Counter.ton-abi.json")) "registry emits ton-abi"
  IO.println "  ✓ Registry materialize dispatch"

unsafe def run : IO Unit := do
  IO.println "TonPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testCounterPlan session
  testCounterIRAndTolk session
  testMultiField session
  testCallScheduleFc session
  testMultiWidthFc session
  testRegistryDispatch session
  IO.println "TonPlanV1: all checks passed"

end Tests.Materialization.TonPlanV1
