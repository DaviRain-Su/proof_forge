/-
  CosmWasm Plan/IR/WAT engineering suite (MVP leaf + CW-4 schedule SubMsg).

  Pins Counter plan shape, CosmWasm ABI exports (instantiate/execute/query/
  allocate/deallocate/interface_version_8), Region/JSON markers, db_* imports,
  CW-4 schedule → SubMsg reply_on=never with Binary (base64) execute msg
  (Plan/IR/WAT shape), pure Lean base64 encode matrix (empty / 1 / 2 / 3+
  bytes + typical JSON), B-RET-ABI named Struct/Enum entry/view returns
  (PairRet/MaybeRet Plan/IR/WAT/ABI pins + param/>8/pureFn FC), N-ANON-RESULT
  anonymous Array UInt64 N / Option UInt64 entry/view returns (ArrayRet/
  OptionRet Plan/IR/WAT/ABI pins + Map/Bytes/N>8/nested FC), sync call still
  fail closed, multi-width UInt8/16/32 pins (body guards / param range /
  8-byte narrow state slots), and other FC boundaries (UInt128, invariants).

  Schedule positive coverage uses product capability resolve (async admitted)
  plus engineering Plan/IR entry points. Not wasmd chain (A2). Not formal D4.
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

/-- Pure RFC 4648 base64 (with `=` padding). Mirrors WAT `$pf_base64_encode`
    table-lookup algorithm for engineering pin tests — not a product export. -/
private def cosmwasmBase64Encode (input : ByteArray) : String := Id.run do
  let alphabet : Array Char :=
    ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/").toList.toArray
  let getChar (n : Nat) : Char := alphabet[n]!
  let mut out : Array Char := #[]
  let mut i := 0
  while i + 3 ≤ input.size do
    let b0 := (input.get! i).toNat
    let b1 := (input.get! (i + 1)).toNat
    let b2 := (input.get! (i + 2)).toNat
    out := out.push (getChar (b0 >>> 2))
    out := out.push (getChar (((b0 &&& 3) <<< 4) ||| (b1 >>> 4)))
    out := out.push (getChar (((b1 &&& 15) <<< 2) ||| (b2 >>> 6)))
    out := out.push (getChar (b2 &&& 63))
    i := i + 3
  let rem := input.size - i
  if rem == 1 then
    let b0 := (input.get! i).toNat
    out := out.push (getChar (b0 >>> 2))
    out := out.push (getChar ((b0 &&& 3) <<< 4))
    out := out.push '='
    out := out.push '='
  else if rem == 2 then
    let b0 := (input.get! i).toNat
    let b1 := (input.get! (i + 1)).toNat
    out := out.push (getChar (b0 >>> 2))
    out := out.push (getChar (((b0 &&& 3) <<< 4) ||| (b1 >>> 4)))
    out := out.push (getChar ((b1 &&& 15) <<< 2))
    out := out.push '='
  pure (String.ofList out.toList)

private def testBase64HelperMatrix : IO Unit := do
  -- Empty input → empty output (WAT $pf_base64_encode returns 0).
  expect (cosmwasmBase64Encode ByteArray.empty == "")
    "base64 empty → \"\""
  -- Single byte remainder → `==` padding.
  expect (cosmwasmBase64Encode "A".toUTF8 == "QQ==")
    "base64 single byte A → QQ=="
  -- Two-byte remainder → `=` padding.
  expect (cosmwasmBase64Encode "AB".toUTF8 == "QUI=")
    "base64 two bytes AB → QUI="
  -- Exact 3-byte group → no padding.
  expect (cosmwasmBase64Encode "ABC".toUTF8 == "QUJD")
    "base64 three bytes ABC → QUJD"
  -- 4 bytes = 3+1 → mixed full group + `==`.
  expect (cosmwasmBase64Encode "ABCD".toUTF8 == "QUJDRA==")
    "base64 four bytes ABCD → QUJDRA=="
  -- Typical schedule inner JSON (fixed count=5).
  let typical := "{\"daily\":{\"a0\":5}}".toUTF8
  expect (cosmwasmBase64Encode typical == "eyJkYWlseSI6eyJhMCI6NX19")
    "base64 typical schedule JSON {\"daily\":{\"a0\":5}}"
  -- Zero-arg method body.
  let emptyArgs := "{\"daily\":{}}".toUTF8
  expect (cosmwasmBase64Encode emptyArgs == "eyJkYWlseSI6e319")
    "base64 empty-args method JSON"
  IO.println "  ✓ base64 helper matrix (empty/1/2/3/4/typical JSON)"

private unsafe def testScheduleSubMsg
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- CW-4: schedule → SubMsg reply_on=never + Binary (base64) msg Plan/IR/WAT pin.
  -- Capability resolve admits async and produces the same SubMsg plan as eng.
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
  expect (wat.contains "SubMsg shape (Binary msg):")
    "WAT SubMsg Binary shape comment"
  expect (wat.contains "\"reply_on\":\"never\"") "WAT SubMsg reply_on=never shape"
  expect (wat.contains "\"contract_addr\":\"ledger.daily\"")
    "WAT contract_addr stub = QN join"
  -- Binary msg: outer envelope opens a JSON *string* for msg, not a nested object.
  expect (wat.contains "\",\"msg\":\"")
    "WAT execute msg is Binary string (opens quote after msg key)"
  -- Must NOT emit nested object shape for WasmMsg::Execute.msg.
  expect (!wat.contains "\"msg\":{\"daily\":")
    "WAT must not use nested JSON object for Binary msg field"
  expect (wat.contains "\"funds\":[]") "WAT empty funds"
  expect (wat.contains "\"id\":0") "WAT SubMsg id=0 (UNUSED_MSG_ID)"
  -- Base64 + inner JSON builders present (runtime Binary path).
  expect (wat.contains "$pf_base64_encode") "WAT $pf_base64_encode helper"
  expect (wat.contains "$pf_b64_char") "WAT $pf_b64_char alphabet lookup"
  expect (wat.contains "$pf_msg_b64") "WAT $pf_msg_b64 Binary append"
  expect (wat.contains "$pf_inner_byte") "WAT $pf_inner_byte inner JSON builder"
  expect (wat.contains "$pf_inner_u64") "WAT $pf_inner_u64 arg decimal into inner JSON"
  expect (wat.contains "$pf_inner_reset") "WAT $pf_inner_reset"
  expect (wat.contains "$msg_len") "WAT messages buffer length global"
  expect (wat.contains "$inner_len") "WAT inner JSON length global"
  expect (wat.contains "call $pf_msg_b64") "WAT schedule calls pf_msg_b64"
  -- Inner JSON still carries method key + a0 field spelling in byte immediates path
  -- (shape comment documents base64 of {"daily":{...}}).
  expect (wat.contains "base64(UTF-8 of {\"daily\":")
    "WAT documents Binary = base64 of method-keyed JSON"
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
  IO.println "  ✓ schedule SubMsg Binary (base64) reply_on=never Plan/IR/WAT"

/-- Collect Plan body evidence for narrow UInt8 Counter (no nested mut walk). -/
private def collectNarrowUInt8BodyFlags (body : Array Statement) :
    Bool × Bool × Bool × Bool := Id.run do
  let mut sawNarrowAdd := false
  let mut sawNarrowLoad := false
  let mut sawFullAdd := false
  let mut storeBw1 := false
  for stmt in body do
    match stmt with
    | .store store =>
        if store.byteWidth == 1 then storeBw1 := true
        match store.value with
        | .narrowCheckedAdd 8
            (.narrowStateLoad 8 _)
            (.narrowParam 8 _) =>
            sawNarrowAdd := true
            sawNarrowLoad := true
        | .narrowCheckedAdd 8 l r =>
            sawNarrowAdd := true
            match l with | .narrowStateLoad 8 _ => sawNarrowLoad := true | _ => pure ()
            match r with | .narrowParam 8 _ => pure () | _ => pure ()
        | .checkedAdd _ _ => sawFullAdd := true
        | .narrowStateLoad 8 _ => sawNarrowLoad := true
        | .narrowParam 8 _ => pure ()
        | _ => pure ()
    | .returnValue (.narrowStateLoad 8 _) => sawNarrowLoad := true
    | .returnValue (.narrowCheckedAdd 8 _ _) => sawNarrowAdd := true
    | .returnValue (.checkedAdd _ _) => sawFullAdd := true
    | _ => pure ()
  pure (sawNarrowAdd, sawNarrowLoad, sawFullAdd, storeBw1)

/-- BL-15: UInt8 Counter plan/IR/WAT pins — narrow body high-bit guards,
    JSON param range-check (exact width, no silent truncation), and
    8-byte physical state slots with high-bytes-zero load guard. -/
private unsafe def testMultiWidthUInt8
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowCounter" <|
    "  state count : UInt8\n\n" ++
    "  init(initial : UInt8) do\n" ++
    "    count := initial\n\n" ++
    "  entry increment(delta : UInt8) : UInt8 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt8 do\n" ++
    "    return count\n"
  let compiled ← compileSource session src
    "Examples.NarrowCounter" "<cw-u8-narrow>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 1) "NarrowCounter one state field"
  expect (plan.storage.fields[0]!.byteWidth == 1)
    s!"NarrowCounter state semantic byteWidth=1, got {plan.storage.fields[0]!.byteWidth}"
  expect (plan.initializer.params.size == 1) "init one param"
  expect (plan.initializer.params[0]!.byteWidth == 1)
    "init param semantic byteWidth=1"
  let some inc := plan.entries.find? (·.name == "increment") |
    throw <| IO.userError "NarrowCounter missing increment"
  expect (inc.resultKind == .uint8) "increment returns UInt8"
  expect (inc.params.size == 1 && inc.params[0]!.byteWidth == 1)
    "increment param byteWidth=1"
  let (sawNarrowAdd, sawNarrowLoad, sawFullAdd, storeBw1) :=
    collectNarrowUInt8BodyFlags inc.body
  expect storeBw1 "store semantic byteWidth=1"
  expect sawNarrowAdd "increment body must lower UInt8 + to narrowCheckedAdd 8"
  expect sawNarrowLoad "increment body must load count via narrowStateLoad 8"
  expect (!sawFullAdd) "UInt8 add must not use full-width checkedAdd"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "NarrowCounter.wat"
  -- Body high-bit guard after narrow add: shr_u by 8 then trap if nonzero.
  expect (wat.contains "(i64.const 8)")
    "NarrowCounter WAT must emit bitWidth=8 high-bit guards"
  expect (wat.contains "i64.shr_u")
    "NarrowCounter WAT must use shr_u for high-bit / range guards"
  -- Param range-check after JSON parse (init initial : UInt8).
  expect (wat.contains "pf_parse_u64_field") "JSON parse still used"
  -- Physical store remains 8-byte Region helper (not variable-length KV).
  expect (wat.contains "$pf_db_store_u64") "physical 8-byte Region store"
  expect (wat.contains "$pf_db_load_u64") "physical 8-byte Region load"
  let abi ← findFile files "NarrowCounter.cosmwasm-abi.json"
  expect (abi.contains "\"type\":\"u8\"")
    s!"ABI must declare u8 for narrow fields/params, got: {abi}"
  expect (abi.contains "\"returns\":\"u8\"")
    s!"ABI returns must be u8, got: {abi}"
  IO.println "  ✓ multi-width UInt8 Plan/IR/WAT/ABI pins (body guards + range + 8B slot)"

/-- BL-15: UInt16/UInt32 also admit with matching Plan widths. -/
private unsafe def testMultiWidthUInt16UInt32
    (session : Language.Loader.ParserSession) : IO Unit := do
  for (w, bw, kindLabel) in #[(16, 2, "UInt16"), (32, 4, "UInt32")] do
    let name := s!"Narrow{kindLabel}"
    let src := wrapProgram name <|
      s!"  state s : {kindLabel}\n\n" ++
      s!"  init(x : {kindLabel}) do\n" ++
      "    s := x\n\n" ++
      s!"  entry bump(d : {kindLabel}) : {kindLabel} do\n" ++
      "    s := s + d\n" ++
      "    return s\n\n" ++
      s!"  view get() : {kindLabel} do\n" ++
      "    return s\n"
    let compiled ← compileSource session src s!"Examples.{name}" s!"<cw-{kindLabel}>"
    let plan ← liftResult <| planCw compiled
    expect (plan.storage.fields[0]!.byteWidth == bw)
      s!"{kindLabel} state byteWidth={bw}"
    expect (plan.initializer.params[0]!.byteWidth == bw)
      s!"{kindLabel} param byteWidth={bw}"
    let some bump := plan.entries.find? (·.name == "bump") |
      throw <| IO.userError s!"{name} missing bump"
    let expectedKind :=
      if w == 16 then MethodResultKind.uint16 else MethodResultKind.uint32
    expect (bump.resultKind == expectedKind)
      s!"{kindLabel} result kind"
    let files ← liftResult <| filesCw compiled
    let wat ← findFile files s!"{name}.wat"
    expect (wat.contains s!"(i64.const {w})")
      s!"{kindLabel} WAT high-bit guard bitWidth={w}"
  IO.println "  ✓ multi-width UInt16/UInt32 Plan/WAT pins"

/-- BL-15 FC: UInt128 / Int8 stay fail closed on CosmWasm. -/
private unsafe def testMultiWidthFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let u128 := wrapProgram "Wide128" <|
    "  state s : UInt128\n\n" ++
    "  init(x : UInt128) do\n" ++
    "    s := x\n\n" ++
    "  entry bump(d : UInt128) : UInt128 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view get() : UInt128 do\n" ++
    "    return s\n"
  match ← session.selectProgramV1 u128 "<cw-u128-fc>" "Examples.Wide128" none with
  | .error _ => pure ()  -- may fail at compile/normalize
  | .ok validated =>
      match Compiler.compileValidatedSourceV1 validated with
      | .error _ => pure ()
      | .ok compiled =>
          match cosmwasmCapability compiled with
          | .error _ => pure ()
          | .ok capability =>
              expectPlanError "UInt128 state" (planFromCapability capability)
  let i8src := wrapProgram "NarrowI8" <|
    "  state s : Int8\n\n" ++
    "  init(x : Int8) do\n" ++
    "    s := x\n\n" ++
    "  entry bump(d : Int8) : Int8 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view get() : Int8 do\n" ++
    "    return s\n"
  match ← session.selectProgramV1 i8src "<cw-i8-fc>" "Examples.NarrowI8" none with
  | .error _ => pure ()
  | .ok validated =>
      match Compiler.compileValidatedSourceV1 validated with
      | .error _ => pure ()
      | .ok compiled =>
          match cosmwasmCapability compiled with
          | .error _ => pure ()
          | .ok capability =>
              expectPlanError "Int8 state" (planFromCapability capability)
  IO.println "  ✓ multi-width UInt128/Int8 fail closed"

/-- B-RET-ABI: named Struct view return flattens to 2×UInt64 leaves via
`returnAggregate` / `setReturnDataMulti` / JSON decimal array wire. -/
private unsafe def testNamedStructReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "PairRet" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n\n" ++
    "  entry setPair(x : UInt64, y : UInt64) : Pair do\n" ++
    "    p := Pair.new(x, y)\n" ++
    "    return p\n\n" ++
    "  view getPair() : Pair do\n" ++
    "    return p\n"
  let compiled ← compileSource session source "Examples.PairRet" "<cw-pair-ret>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 2) "PairRet Pair flattens to 2 KV leaves"
  let some getPair := plan.entries.find? (·.name == "getPair") |
    throw <| IO.userError "PairRet missing getPair"
  match getPair.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"PairRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "PairRet leaves must be u64 (not Int)"
      expect (leaves.all (·.byteWidth == 8))
        "PairRet leaves must be 8-byte words"
  | other =>
      throw <| IO.userError
        s!"PairRet getPair resultKind must be .aggregate, got {repr other}"
  expect (getPair.body.size == 1) "PairRet getPair body must be one return"
  match getPair.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2)
        s!"returnAggregate must have 2 leaves, got {leaves.size}"
      expect (leafIsInt == #[false, false])
        "returnAggregate leafIsInt must be #[false, false]"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0, .stateLoad 1 => pure ()
      | _, _ =>
          throw <| IO.userError
            "PairRet returnAggregate leaves must be stateLoad of p fields"
  | _ =>
      throw <| IO.userError "PairRet getPair body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"PairRet plan must validate: {e.render}"
  let ir ← liftResult <| irCw compiled
  let some getPairIR := ir.methods.find? (·.name == "getPair") |
    throw <| IO.userError "PairRet IR missing getPair"
  expect (getPairIR.resultKind == getPair.resultKind)
    "PairRet IR resultKind must match Plan"
  let mut sawMulti := false
  for op in getPairIR.operations do
    match op with
    | .setReturnDataMulti temps =>
        expect (temps.size == 2)
          s!"setReturnDataMulti must have 2 temps, got {temps.size}"
        sawMulti := true
    | .setReturnData _ =>
        throw <| IO.userError "PairRet must not emit scalar setReturnData"
    | _ => pure ()
  expect sawMulti "PairRet IR must emit setReturnDataMulti"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "PairRet.wat"
  expect (wat.contains "$ret_count") "PairRet WAT ret_count global"
  expect (wat.contains "$pf_query_ok_agg") "PairRet WAT multi-leaf query helper"
  expect (wat.contains "(global.set $ret_kind (i32.const 4))")
    "PairRet WAT setReturnDataMulti ret_kind=4"
  let abi ← findFile files "PairRet.cosmwasm-abi.json"
  expect (abi.contains "\"returns\":[\"u64\",\"u64\"]")
    s!"PairRet ABI must declare leaf tuple [\"u64\",\"u64\"], got: {abi}"
  IO.println "  ✓ PairRet named Struct return Plan/IR/WAT/ABI pin"

/-- B-RET-ABI: named Enum return = tag + max-payload slots (Maybe = 2 leaves). -/
private unsafe def testNamedEnumReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MaybeRet" <|
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry setSome(v : UInt64) : Maybe do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return m\n\n" ++
    "  view peek() : Maybe do\n" ++
    "    return m\n"
  let compiled ← compileSource session source "Examples.MaybeRet" "<cw-maybe-ret>"
  let plan ← liftResult <| planCw compiled
  let some peek := plan.entries.find? (·.name == "peek") |
    throw <| IO.userError "MaybeRet missing peek"
  match peek.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"MaybeRet peek must have 2 leaves (tag+payload), got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"MaybeRet peek resultKind must be .aggregate, got {repr other}"
  let mut sawAgg := false
  for stmt in peek.body do
    match stmt with
    | .returnAggregate leaves leafIsInt =>
        expect (leaves.size == 2) "MaybeRet returnAggregate 2 leaves"
        expect (leafIsInt.size == 2) "MaybeRet leafIsInt 2"
        sawAgg := true
    | .ifThenElse _ thenBody elseBody =>
        for s in thenBody ++ elseBody do
          match s with
          | .returnAggregate .. => sawAgg := true
          | _ => pure ()
    | _ => pure ()
  expect sawAgg "MaybeRet must emit returnAggregate on some path"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MaybeRet plan must validate: {e.render}"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "MaybeRet.wat"
  expect (wat.contains "$pf_query_ok_agg" || wat.contains "ret_kind")
    "MaybeRet WAT multi-leaf return surface"
  let abi ← findFile files "MaybeRet.cosmwasm-abi.json"
  expect (abi.contains "\"returns\":[\"u64\",\"u64\"]")
    s!"MaybeRet ABI leaf tuple, got: {abi}"
  IO.println "  ✓ MaybeRet named Enum return Plan/IR/WAT/ABI pin"

/-- B-RET-ABI fail-closed: named aggregate params, >8 leaves, pureFn aggregate. -/
private unsafe def testAggregateReturnFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Named aggregate param stays FC.
  let paramSrc := wrapProgram "AggParam" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry take(p : Pair) : UInt64 do\n" ++
    "    return p.a\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return s\n"
  let paramCompiled ← compileSource session paramSrc "Examples.AggParam" "<cw-agg-param>"
  expectPlanErrorContaining "named aggregate param" "parameter"
    (planCw paramCompiled)
  -- >8 leaves (9-field Struct) stays FC.
  let wideSrc := wrapProgram "WideRet" <|
    "  struct Wide where\n" ++
    "    a0 : UInt64\n" ++
    "    a1 : UInt64\n" ++
    "    a2 : UInt64\n" ++
    "    a3 : UInt64\n" ++
    "    a4 : UInt64\n" ++
    "    a5 : UInt64\n" ++
    "    a6 : UInt64\n" ++
    "    a7 : UInt64\n" ++
    "    a8 : UInt64\n" ++
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  view getWide() : Wide do\n" ++
    "    return Wide.new(0, 0, 0, 0, 0, 0, 0, 0, 0)\n"
  let wideCompiled ← compileSource session wideSrc "Examples.WideRet" "<cw-wide-ret>"
  expectPlanErrorContaining "wide-ret cap-8" "8"
    (planCw wideCompiled)
  -- pureFn aggregate return stays FC.
  let pureSrc := wrapProgram "PureAgg" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  fn mk(x : UInt64) : Pair do\n" ++
    "    return Pair.new(x, x)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return s\n"
  let pureCompiled ← compileSource session pureSrc "Examples.PureAgg" "<cw-pure-agg>"
  expectPlanErrorContaining "pureFn aggregate" "pureFn"
    (planCw pureCompiled)
  IO.println "  ✓ aggregate return FC boundaries (param / >8 / pureFn)"

/-- N-ANON-RESULT (CosmWasm ABI): anonymous Array UInt64 2 → 2×u64 leaves via
`returnAggregate` / `setReturnDataMulti` / JSON decimal array wire. -/
private unsafe def testAnonymousArrayReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ArrayRet" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init(a : UInt64, b : UInt64) do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n\n" ++
    "  entry setArr(a : UInt64, b : UInt64) : Array UInt64 2 do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "    return slots\n\n" ++
    "  view getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session source "Examples.ArrayRet" "<cw-array-ret>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 2) "ArrayRet Array UInt64 2 → 2 KV leaves"
  let some getArr := plan.entries.find? (·.name == "getArr") |
    throw <| IO.userError "ArrayRet missing getArr"
  match getArr.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"ArrayRet aggregate return must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "ArrayRet leaves must be u64 (not Int)"
      expect (leaves.all (·.byteWidth == 8))
        "ArrayRet leaves must be 8-byte words"
  | other =>
      throw <| IO.userError
        s!"ArrayRet getArr resultKind must be .aggregate, got {repr other}"
  expect (getArr.body.size == 1) "ArrayRet getArr body must be one return"
  match getArr.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2)
        s!"returnAggregate must have 2 leaves, got {leaves.size}"
      expect (leafIsInt == #[false, false])
        "returnAggregate leafIsInt must be #[false, false]"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0, .stateLoad 1 => pure ()
      | _, _ =>
          throw <| IO.userError
            "ArrayRet returnAggregate leaves must be stateLoad of slots"
  | _ =>
      throw <| IO.userError "ArrayRet getArr body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrayRet plan must validate: {e.render}"
  let ir ← liftResult <| irCw compiled
  let some getArrIR := ir.methods.find? (·.name == "getArr") |
    throw <| IO.userError "ArrayRet IR missing getArr"
  expect (getArrIR.resultKind == getArr.resultKind)
    "ArrayRet IR resultKind must match Plan"
  let mut sawMulti := false
  for op in getArrIR.operations do
    match op with
    | .setReturnDataMulti temps =>
        expect (temps.size == 2)
          s!"setReturnDataMulti must have 2 temps, got {temps.size}"
        sawMulti := true
    | .setReturnData _ =>
        throw <| IO.userError "ArrayRet must not emit scalar setReturnData"
    | _ => pure ()
  expect sawMulti "ArrayRet IR must emit setReturnDataMulti"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "ArrayRet.wat"
  expect (wat.contains "$ret_count") "ArrayRet WAT ret_count global"
  expect (wat.contains "$pf_query_ok_agg") "ArrayRet WAT multi-leaf query helper"
  expect (wat.contains "(global.set $ret_kind (i32.const 4))")
    "ArrayRet WAT setReturnDataMulti ret_kind=4"
  let abi ← findFile files "ArrayRet.cosmwasm-abi.json"
  expect (abi.contains "\"returns\":[\"u64\",\"u64\"]")
    s!"ArrayRet ABI must declare leaf tuple [\"u64\",\"u64\"], got: {abi}"
  IO.println "  ✓ ArrayRet anonymous Array return Plan/IR/WAT/ABI pin"

/-- N-ANON-RESULT: anonymous Option UInt64 = tag + payload (2 leaves). -/
private unsafe def testAnonymousOptionReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptionRet" <|
    "  state seed : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    seed := x\n\n" ++
    "  entry asSome(v : UInt64) : Option UInt64 do\n" ++
    "    return Option.some(v)\n\n" ++
    "  view asNone() : Option UInt64 do\n" ++
    "    return Option.none()\n\n" ++
    "  view asSomeOfSeed() : Option UInt64 do\n" ++
    "    return Option.some(seed)\n"
  let compiled ← compileSource session source "Examples.OptionRet" "<cw-option-ret>"
  let plan ← liftResult <| planCw compiled
  let some asNone := plan.entries.find? (·.name == "asNone") |
    throw <| IO.userError "OptionRet missing asNone"
  match asNone.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptionRet asNone must have 2 leaves (tag+payload), got {leaves.size}"
      expect (!leaves[0]!.isInt && !leaves[1]!.isInt)
        "OptionRet leaves must be u64"
  | other =>
      throw <| IO.userError
        s!"OptionRet asNone resultKind must be .aggregate, got {repr other}"
  match asNone.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2) "OptionRet returnAggregate 2 leaves"
      expect (leafIsInt == #[false, false]) "OptionRet leafIsInt #[false,false]"
      match leaves[0]!, leaves[1]! with
      | .literal 0, .literal 0 => pure ()
      | _, _ =>
          throw <| IO.userError
            s!"OptionRet asNone leaves must be literal 0/0, got {repr leaves[0]!}/{repr leaves[1]!}"
  | _ =>
      throw <| IO.userError "OptionRet asNone body must be .returnAggregate"
  let some asSome := plan.entries.find? (·.name == "asSome") |
    throw <| IO.userError "OptionRet missing asSome"
  match asSome.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2) "OptionRet asSome must return 2-leaf Option"
  | _ =>
      throw <| IO.userError "OptionRet asSome resultKind must be .aggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptionRet plan must validate: {e.render}"
  let ir ← liftResult <| irCw compiled
  let some asNoneIR := ir.methods.find? (·.name == "asNone") |
    throw <| IO.userError "OptionRet IR missing asNone"
  let mut sawMulti := false
  for op in asNoneIR.operations do
    match op with
    | .setReturnDataMulti temps =>
        expect (temps.size == 2) "OptionRet setReturnDataMulti [2]"
        sawMulti := true
    | _ => pure ()
  expect sawMulti "OptionRet asNone IR must emit setReturnDataMulti"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "OptionRet.wat"
  expect (wat.contains "$pf_query_ok_agg" || wat.contains "ret_kind")
    "OptionRet WAT multi-leaf return surface"
  let abi ← findFile files "OptionRet.cosmwasm-abi.json"
  expect (abi.contains "\"returns\":[\"u64\",\"u64\"]")
    s!"OptionRet ABI leaf tuple, got: {abi}"
  IO.println "  ✓ OptionRet anonymous Option return Plan/IR/WAT/ABI pin"

/-- N-ANON-RESULT FC: Map/Bytes/Array-of-9/nested Option stay fail closed. -/
private unsafe def expectAnonymousReturnFc
    (session : Language.Loader.ParserSession)
    (label moduleName body : String)
    (messageNeedles : Array String) : IO Unit := do
  let source := wrapProgram label body
  match ← session.selectProgramV1 source s!"<cw-{label}>" moduleName none with
  | .error e => throw <| IO.userError s!"{label} select: {e.render}"
  | .ok validated =>
      match Compiler.compileValidatedSourceV1 validated with
      | .error _ => pure ()  -- Normalize/Check may reject first.
      | .ok compiled =>
          match planCw compiled with
          | .error e =>
              let msg := e.render
              let hit := messageNeedles.any (fun n => msg.contains n)
              expect hit
                s!"{label}: FC message must cite {messageNeedles}, got {msg}"
          | .ok _ =>
              throw <| IO.userError
                s!"{label}: CosmWasm must fail closed on this anonymous return shape"

private unsafe def testAnonymousReturnFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Bytes N return remains fail closed (Bytes still outside type-closure pilot).
  expectAnonymousReturnFc session "BytesRet" "Examples.BytesRet"
    ("  state payload : Bytes 2\n\n" ++
      "  init() do\n" ++
      "    payload[0] := 1\n" ++
      "    payload[1] := 2\n\n" ++
      "  view getBytes() : Bytes 2 do\n" ++
      "    return payload\n")
    #["Bytes", "return", "B-RET", "unsupported", "anonymous", "container"]
  -- Map return remains fail closed.
  expectAnonymousReturnFc session "MapRet" "Examples.MapRet"
    ("  state table : Map UInt64 UInt64\n\n" ++
      "  init() do\n" ++
      "    table[0] := 1\n\n" ++
      "  view getMap() : Map UInt64 UInt64 do\n" ++
      "    return table\n")
    #["Map", "return", "B-RET", "unsupported", "anonymous"]
  -- Array UInt64 9 exceeds leaf cap-8.
  expectAnonymousReturnFc session "Array9Ret" "Examples.Array9Ret"
    ("  state slots : Array UInt64 9\n\n" ++
      "  init() do\n" ++
      "    slots[0] := 0\n" ++
      "    slots[1] := 0\n" ++
      "    slots[2] := 0\n" ++
      "    slots[3] := 0\n" ++
      "    slots[4] := 0\n" ++
      "    slots[5] := 0\n" ++
      "    slots[6] := 0\n" ++
      "    slots[7] := 0\n" ++
      "    slots[8] := 0\n\n" ++
      "  view getArr() : Array UInt64 9 do\n" ++
      "    return slots\n")
    #["8", "leaf", "cap", "9", "exceeding", "aggregate"]
  -- Nested anonymous Option (Array …) remains fail closed (non-UInt64 payload).
  expectAnonymousReturnFc session "NestedOptRet" "Examples.NestedOptRet"
    ("  state seed : UInt64\n\n" ++
      "  init() do\n" ++
      "    seed := 0\n\n" ++
      "  view getNested() : Option Array UInt64 2 do\n" ++
      "    return Option.none()\n")
    #["Option", "UInt64", "payload", "return", "unsupported", "anonymous", "Array"]
  IO.println "  ✓ anonymous return FC boundaries (Bytes / Map / Array9 / nested Option)"

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
  testBase64HelperMatrix
  testScheduleSubMsg session
  testMultiWidthUInt8 session
  testMultiWidthUInt16UInt32 session
  testMultiWidthFc session
  testNamedStructReturn session
  testNamedEnumReturn session
  testAggregateReturnFc session
  testAnonymousArrayReturn session
  testAnonymousOptionReturn session
  testAnonymousReturnFc session
  testInvariantFc session
  testMaterializeAggregate session
  testStaticLayoutCapacityFc session
  IO.println "CosmWasmPlanV1: all checks passed"

end Tests.Materialization.CosmWasmPlanV1
