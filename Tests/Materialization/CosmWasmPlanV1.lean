/-
  CosmWasm Plan/IR/WAT engineering suite (MVP leaf + CW-4 schedule SubMsg).

  Pins Counter plan shape, CosmWasm ABI exports (instantiate/execute/query/
  allocate/deallocate/interface_version_8), Region/JSON markers, db_* imports,
  CW-4 schedule → SubMsg reply_on=never (Plan/IR/WAT shape), sync call still
  fail closed, and other FC boundaries (multi-width, aggregates, invariants).

  Product capability resolve still declines effect.asynchronous-workflow until
  main-agent integration; schedule positive coverage uses engineering Plan/IR
  entry points that bypass resolve. Not wasmd runtime (A2). Not formal D4.
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

private unsafe def testCallStillFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Sync call remains FC at plan layer (WasmMsg::Execute is SubMsg, not CALL).
  let callSrc := wrapProgram "CallFc" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    call other.method(s)\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let validated ← liftResult (← session.selectProgramV1 callSrc
    "<cw-call-fc>" "Examples.CallFc" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ =>
      -- May fail at normalize/check/capability before plan; either is FC.
      pure ()
  | .ok compiled =>
      match cosmwasmCapability compiled with
      | .error _ => pure ()  -- resolver FC on effect.synchronous-call
      | .ok capability =>
          expectPlanErrorContaining "call plan" "call" (planFromCapability capability)
      -- Engineering path (bypass resolve): plan layer still rejects sync call.
      expectPlanErrorContaining "call eng plan" "call"
        (engineeringPlanFromCompiled compiled)
  IO.println "  ✓ call/sync still fail closed"

private unsafe def testScheduleSubMsg
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- CW-4: schedule → SubMsg reply_on=never Plan/IR/WAT pin.
  -- Resolver async key is open (integration): capability resolve succeeds and
  -- produces the same SubMsg plan as the engineering entry.
  let schedSrc := wrapProgram "ScheduleFlow" <|
    "  state count : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    count := x\n\n" ++
    "  entry later() : UInt64 do\n" ++
    "    schedule ledger.daily(count)\n" ++
    "    count := count + 1\n" ++
    "    return count\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session schedSrc
    "Examples.ScheduleFlow" "<cw-schedule-flow>"
  -- Capability resolve now admits async (sync still declined, pinned above).
  let capability ← match cosmwasmCapability compiled with
    | .error e =>
        throw <| IO.userError
          s!"schedule: capability resolve must admit async after CW-4 integration, got {e.render}"
    | .ok capability => pure capability
  let plan ← liftResult <| planFromCapability capability
  expect (plan.programName == "ScheduleFlow") "schedule program name"
  expect (plan.hostImports == canonicalImports)
    "schedule keeps db_*/abort imports (no promise hosts)"
  let some later := plan.entries.find? (·.name == "later") |
    throw <| IO.userError "schedule: missing later entry"
  let hasPromise := later.body.any fun s =>
    match s with
    | .promiseAccount receiver method args =>
        receiver == "ledger.daily" && method == "daily" && args.size == 1
    | _ => false
  expect hasPromise
    "schedule: later must lower promiseAccount(ledger.daily, daily, count)"
  -- schedule + state write coexist in body order
  let kinds := later.body.map fun s =>
    match s with
    | .promiseAccount .. => "promise"
    | .store .. => "store"
    | .returnValue _ => "ret"
    | _ => "other"
  expect (kinds.contains "promise" && kinds.contains "store" && kinds.contains "ret")
    s!"schedule+state body kinds, got {kinds}"
  let ir ← liftResult <| engineeringIrFromPlan plan
  let irHasPromise := ir.methods.any fun m =>
    m.operations.any fun op =>
      match op with
      | .promiseAccount r meth _ => r == "ledger.daily" && meth == "daily"
      | _ => false
  expect irHasPromise "schedule IR must contain promiseAccount"
  let files ← liftResult <| engineeringFilesFromPlan plan
  let wat ← findFile files "ScheduleFlow.wat"
  expect (wat.contains "schedule SubMsg reply_on=never")
    "WAT schedule SubMsg comment"
  expect (wat.contains "SubMsg shape:") "WAT SubMsg shape comment"
  expect (wat.contains "\"reply_on\":\"never\"") "WAT SubMsg reply_on=never shape"
  expect (wat.contains "\"contract_addr\":\"ledger.daily\"")
    "WAT contract_addr stub = QN join"
  expect (wat.contains "\"msg\":{\"daily\":") "WAT execute method key in msg"
  expect (wat.contains "\"funds\":[]") "WAT empty funds"
  expect (wat.contains "\"id\":0") "WAT SubMsg id=0 (UNUSED_MSG_ID)"
  expect (wat.contains "$pf_msg_byte") "WAT SubMsg byte builder"
  expect (wat.contains "$pf_msg_u64") "WAT SubMsg arg decimal encoder"
  expect (wat.contains "$msg_len") "WAT messages buffer length global"
  -- Uppercase QN fails receiver-stub grammar (no silent case fold).
  let badSrc := wrapProgram "ScheduleBad" <|
    "  state count : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    count := x\n\n" ++
    "  entry later() : UInt64 do\n" ++
    "    schedule Ledger.daily(count)\n" ++
    "    return count\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return count\n"
  let badCompiled ← compileSource session badSrc
    "Examples.ScheduleBad" "<cw-schedule-bad>"
  match engineeringPlanFromCompiled badCompiled with
  | .error (.planInvariant .cosmwasm msg) =>
      expect (msg.contains "account id" || msg.contains "schedule receiver")
        s!"schedule uppercase must fail account-id gate, got {msg}"
  | .error other =>
      throw <| IO.userError s!"schedule uppercase: expected planInvariant, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "schedule uppercase: expected planInvariant fail-closed"
  IO.println "  ✓ schedule SubMsg reply_on=never Plan/IR/WAT"

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

/-- A1-repair P0-1: static layout capacity gates must fail closed at Plan/IR
    emission (never silently overlap heap). keysEnd > 3000 via many state
    fields; needles > 4096 via many long method names. -/
private unsafe def testStaticLayoutCapacityFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- (a) keysEnd overflow: 200 × 16-char state fields ⇒ keysEnd ≈ 3264 > 3000.
  let states := String.intercalate "" <|
    (List.range 200).map (fun i =>
      let name := "s" ++ String.mk (List.replicate 15 (Char.ofNat ('a'.toNat + i % 26)))
      s!"  state {name}{i} : UInt64\n")
  let keysSrc := wrapProgram "KeysOverflow" <|
    states ++
    "  init() do\n" ++
    "    saaaaaaaaaaaaaaa0 := 0\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return saaaaaaaaaaaaaaa0\n"
  let keysCompiled ← compileSource session keysSrc
    "Examples.KeysOverflow" "<cw-keys-overflow>"
  match cosmwasmCapability keysCompiled with
  | .error e => throw <| IO.userError s!"keys-overflow capability: {e.render}"
  | .ok capability =>
      expectPlanErrorContaining "keysEnd gate" "overlaps needle base"
        (buildFromCapability capability)
  -- (b) needle overflow: init + 5 entries with 240-char names (identifier
  -- limit) ⇒ needles ≈ 5 × 243 = 1215 bytes from 3000, crossing 4096.
  let longName := "m" ++ String.mk (List.replicate 238 'x')
  let entries := String.intercalate "" <|
    (List.range 5).map (fun i =>
      s!"  entry {longName}{i}() : UInt64 do\n    return {i}\n\n")
  let needleSrc := wrapProgram "NeedleOverflow" <|
    "  state count : UInt64\n\n" ++
    "  init() do\n" ++
    "    count := 0\n\n" ++
    entries ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session needleSrc
    "Examples.NeedleOverflow" "<cw-needle-overflow>"
  match cosmwasmCapability compiled with
  | .error e => throw <| IO.userError s!"needle-overflow capability: {e.render}"
  | .ok capability =>
      expectPlanErrorContaining "needle gate" "would overlap bump heap"
        (buildFromCapability capability)
  IO.println "  ✓ static layout capacity fail closed (P0-1)"

/-- Entry point for manual / future shard registration. -/
unsafe def run : IO Unit := do
  IO.println "CosmWasmPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testCounterPlan session
  testCounterIRAndWat session
  testMultiField session
  testCallStillFailClosed session
  testScheduleSubMsg session
  testMultiWidthFc session
  testNamedAggregateFc session
  testInvariantFc session
  testMaterializeAggregate session
  testStaticLayoutCapacityFc session
  IO.println "CosmWasmPlanV1: all checks passed"

end Tests.Materialization.CosmWasmPlanV1
