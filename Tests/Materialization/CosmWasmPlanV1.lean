/-
  CosmWasm Plan/IR/WAT engineering suite (MVP leaf).

  Pins Counter plan shape, CosmWasm ABI exports (instantiate/execute/query/
  allocate/deallocate/interface_version_8), Region/JSON markers, db_* imports,
  and explicit fail-closed boundaries (call/schedule, multi-width, aggregates,
  invariants, Field/Principal/String).

  Not registered in Tests/Shards/* — main agent must register the shard.
  Not wasmd runtime / cosmwasm-check (A2). Not formal D4.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.CosmWasm
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.CosmWasmPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.CosmWasm

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

private def expectPlanError (label : String) (result : CompileResult α) : IO Unit :=
  match result with
  | .error (.planInvariant .cosmwasm msg) =>
      expect (msg.length > 0) s!"{label}: empty planInvariant message"
  | .error e => throw <| IO.userError s!"{label}: expected cosmwasm planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected failure, got ok"

private def expectPlanErrorContaining (label needle : String)
    (result : CompileResult α) : IO Unit :=
  match result with
  | .error (.planInvariant .cosmwasm msg) =>
      expect (msg.contains needle)
        s!"{label}: expected message containing '{needle}', got '{msg}'"
  | .error e => throw <| IO.userError s!"{label}: expected cosmwasm planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected failure, got ok"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def cosmwasmCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.cosmwasm none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planCw (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let capability ← cosmwasmCapability compiled
  planFromCapability capability

private def irCw (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← cosmwasmCapability compiled
  irFromCapability capability

private def filesCw (compiled : CompiledSemanticV1) : CompileResult (Array OutputFile) := do
  let capability ← cosmwasmCapability compiled
  buildFromCapability capability

private def findFile (files : Array OutputFile) (path : String) : IO String :=
  match files.find? (·.path == path) with
  | some file => pure file.contents
  | none => throw <| IO.userError s!"missing output file '{path}'; got {files.map (·.path)}"

private unsafe def testCounterPlan
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleName "<cw-counter>"
  let plan ← liftResult <| planCw compiled
  expect (plan.programName == "Counter") "program name Counter"
  expect (plan.hostAbi == hostAbiVersion) "canonical host ABI"
  expect (plan.inputAbi == rawInputAbi) "JSON msg input ABI"
  expect (plan.codegenProfile == "cosmwasm-wasm-u64-v1") "default profile"
  expect (plan.hostImports == canonicalImports) "db_read/write/remove/abort only"
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
  -- Plan digest is stable/deterministic.
  let d1 ← match engineeringCosmWasmPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  let d2 ← match engineeringCosmWasmPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  expect (d1 == d2) "plan digest deterministic"
  IO.println "  ✓ Counter plan shape"

private unsafe def testCounterIRAndWat
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleName "<cw-counter-ir>"
  let ir ← liftResult <| irCw compiled
  expect (ir.name == "Counter") "IR name"
  expect (ir.methods.size == 3) "init + 2 entries"
  expect (ir.imports == canonicalImports) "IR host imports"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "Counter.wat"
  let abi ← findFile files "Counter.cosmwasm-abi.json"
  -- Module shape
  expect (wat.contains "(module") "WAT module"
  expect (wat.contains "(memory (export \"memory\") 1)") "single memory min=1 no max"
  -- CosmWasm ABI exports
  for exp in #["allocate", "deallocate", "interface_version_8",
      "instantiate", "execute", "query"] do
    expect (wat.contains s!"(export \"{exp}\")") s!"export {exp}"
  -- Host imports
  for imp in #["db_read", "db_write", "db_remove", "abort"] do
    expect (wat.contains s!"\"{imp}\"") s!"import env.{imp}"
  -- Region helpers present
  expect (wat.contains "$pf_allocate") "bump allocate helper"
  expect (wat.contains "$pf_key_region") "key Region helper"
  expect (wat.contains "$pf_db_load_u64") "db load helper"
  expect (wat.contains "$pf_db_store_u64") "db store helper"
  expect (wat.contains "$pf_ok_result") "ContractResult ok builder"
  expect (wat.contains "$pf_error_result") "ContractResult error builder"
  expect (wat.contains "$pf_parse_u64_field") "JSON integer field scan"
  expect (wat.contains "$pf_find") "JSON method name byte-compare"
  -- Method bodies
  expect (wat.contains "$m_init") "init body"
  expect (wat.contains "$m_increment") "increment body"
  expect (wat.contains "$m_get") "get body"
  -- No NEAR host leakage
  expect (!wat.contains "storage_read") "no NEAR storage_read"
  expect (!wat.contains "value_return") "no NEAR value_return"
  expect (!wat.contains "promise_batch") "no promise imports"
  -- ABI JSON
  expect (abi.contains "proof-forge-cosmwasm-abi/v1alpha1") "ABI schema"
  expect (abi.contains "instantiate") "ABI entrypoints"
  expect (abi.contains "env.db_read") "ABI imports list"
  expect (abi.contains "\"offset:u32\"") "Region layout documented"
  expect (abi.contains "jsonSubset") "JSON subset documented"
  IO.println "  ✓ Counter IR/WAT/ABI CosmWasm shape"

private unsafe def testMultiField
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session multiFieldSourceText
    "Examples.MultiField" "<cw-multi>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 2) "two KV leaves"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "MultiField.wat"
  expect (wat.contains "pf:cw:v1:state:0") "state key 0"
  expect (wat.contains "pf:cw:v1:state:1") "state key 1"
  IO.println "  ✓ multi-field state KV"

private unsafe def testCallScheduleFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Resolver declines both call keys; plan layer also FC if capability forced.
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
    "<cw-call-fc>" "Examples.CallFc" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ =>
      -- May fail at normalize/check before plan; either is FC.
      pure ()
  | .ok compiled =>
      match cosmwasmCapability compiled with
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
    "<cw-sched-fc>" "Examples.SchedFc" none)
  match Compiler.compileValidatedSourceV1 validated2 with
  | .error _ => pure ()
  | .ok compiled =>
      match cosmwasmCapability compiled with
      | .error _ => pure ()
      | .ok capability =>
          expectPlanErrorContaining "schedule plan" "schedule" (planFromCapability capability)
  IO.println "  ✓ call/schedule fail closed"

private unsafe def testMultiWidthFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "Narrow" <|
    "  state s : UInt8\n\n" ++
    "  init(x : UInt8) do\n" ++
    "    s := x\n\n" ++
    "  entry bump(d : UInt8) : UInt8 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view get() : UInt8 do\n" ++
    "    return s\n"
  let validated ← liftResult (← session.selectProgramV1 src
    "<cw-u8-fc>" "Examples.Narrow" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()
  | .ok compiled =>
      match cosmwasmCapability compiled with
      | .error _ => pure ()
      | .ok capability =>
          expectPlanError "UInt8 state" (planFromCapability capability)
  IO.println "  ✓ multi-width UInt8 fail closed"

private unsafe def testNamedAggregateFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NamedAgg" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n\n" ++
    "  state p : Point\n\n" ++
    "  init() do\n" ++
    "    p := Point.new(0, 0)\n\n" ++
    "  entry setX(v : UInt64) : UInt64 do\n" ++
    "    p.x := v\n" ++
    "    return p.x\n\n" ++
    "  view getX() : UInt64 do\n" ++
    "    return p.x\n"
  let validated ← liftResult (← session.selectProgramV1 src
    "<cw-named-fc>" "Examples.NamedAgg" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()  -- normalize or type may reject before plan
  | .ok compiled =>
      match cosmwasmCapability compiled with
      | .error _ => pure ()
      | .ok capability =>
          expectPlanError "named Struct state" (planFromCapability capability)
  IO.println "  ✓ named Struct state fail closed"

private unsafe def testInvariantFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "Inv" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return s\n\n" ++
    "  invariant nonZero : s != 0\n"
  let validated ← liftResult (← session.selectProgramV1 src
    "<cw-inv-fc>" "Examples.Inv" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()
  | .ok compiled =>
      match cosmwasmCapability compiled with
      | .error _ => pure ()
      | .ok capability =>
          expectPlanError "nonempty invariants" (planFromCapability capability)
  IO.println "  ✓ nonempty invariants fail closed"

private def materializeSelected (target : TargetId) (compiled : CompiledSemanticV1) :
    CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

private unsafe def testMaterializeAggregate
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleName "<cw-agg>"
  let output ← liftResult <| materializeSelected TargetId.cosmwasm compiled
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.any (·.path == "Counter.wat")) "materialized WAT"
  expect (files.any (·.path == "Counter.cosmwasm-abi.json")) "materialized ABI"
  expect (MaterializedArtifactsV1.artifactProgramNameOf output == "Counter")
    "artifact program name"
  IO.println "  ✓ Registry materializeResult cosmwasm"

/-- Entry point for manual / future shard registration. -/
unsafe def run : IO Unit := do
  IO.println "CosmWasmPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testCounterPlan session
  testCounterIRAndWat session
  testMultiField session
  testCallScheduleFc session
  testMultiWidthFc session
  testNamedAggregateFc session
  testInvariantFc session
  testMaterializeAggregate session
  IO.println "CosmWasmPlanV1: all checks passed"

end Tests.Materialization.CosmWasmPlanV1
